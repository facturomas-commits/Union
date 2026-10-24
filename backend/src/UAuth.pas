unit UAuth;

interface

uses
  System.SysUtils, System.JSON, System.Hash, System.Generics.Collections,
  Horse, UHttp;

type
  TAuthInfo = record
    Authenticated: Boolean;
    UserId: Integer;
    CompanyId: Integer;
    Username: string;
    FullName: string;
    Role: string;
    MustChangePassword: Boolean;
    CanViewFinancials: Boolean;
    Modules: TArray<string>;
    function IsSuper: Boolean;
    function IsAdmin: Boolean;
    function CanWrite: Boolean;
    function HasModule(const AModule: string): Boolean;
    function HasAnyModule(const AModules: array of string): Boolean;
  end;

var
  GAuth: TAuthInfo;

function AuthInfo: TAuthInfo;
function DefaultModules(const ARole: string): TArray<string>;
procedure AuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);

procedure LoginHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure LogoutHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure MeHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
procedure ChangePasswordHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);

function RequireRole(Res: THorseResponse; const ARoles: array of string): Boolean;
function RequireWrite(Res: THorseResponse): Boolean;
function RequireAdmin(Res: THorseResponse): Boolean;
function RequireSuper(Res: THorseResponse): Boolean;

function EffectiveCompany(Req: THorseRequest): Integer;
function BodyCompany(Req: THorseRequest; AObj: TJSONObject): Integer;

procedure AuditAction(const AAction, AEntity: string; AEntityId: Integer;
  const ADetails: string = '');
procedure AuditLoginFailure(const AUsername, ADetails: string);
function TokenFromRequest(Req: THorseRequest): string;

implementation

uses
  System.Classes, System.Variants, UDB, UConfig, ULog;

function TAuthInfo.IsSuper: Boolean;
begin
  Result := Role = 'superadmin';
end;

function TAuthInfo.IsAdmin: Boolean;
begin
  Result := (Role = 'superadmin') or (Role = 'admin');
end;

function TAuthInfo.CanWrite: Boolean;
begin
  Result := (Role = 'superadmin') or (Role = 'admin') or
            (Role = 'supervisor') or (Role = 'operator');
end;

function TAuthInfo.HasModule(const AModule: string): Boolean;
var
  LModule: string;
begin
  for LModule in Modules do
    if LModule = AModule then
      Exit(True);
  Result := False;
end;

function TAuthInfo.HasAnyModule(const AModules: array of string): Boolean;
var
  LModule: string;
begin
  for LModule in AModules do
    if HasModule(LModule) then
      Exit(True);
  Result := False;
end;

const
  ALL_MODULES: array[0..11] of string = (
    'dashboard', 'schedules', 'colectivos', 'camion',
    'fuel', 'expenses', 'maintenance', 'masters',
    'reports', 'audit', 'users', 'settings'
  );
  SUPERVISOR_MODULES: array[0..8] of string = (
    'dashboard', 'schedules', 'colectivos', 'camion',
    'fuel', 'expenses', 'maintenance', 'masters', 'reports'
  );
  OPERATOR_MODULES: array[0..6] of string = (
    'dashboard', 'schedules', 'colectivos', 'camion',
    'fuel', 'expenses', 'maintenance'
  );
  VIEWER_MODULES: array[0..6] of string = (
    'dashboard', 'schedules', 'colectivos', 'camion',
    'fuel', 'expenses', 'maintenance'
  );

function DefaultModules(const ARole: string): TArray<string>;
var
  I: Integer;
begin
  if (ARole = 'superadmin') or (ARole = 'admin') then
  begin
    SetLength(Result, Length(ALL_MODULES));
    for I := 0 to High(ALL_MODULES) do Result[I] := ALL_MODULES[I];
  end
  else if ARole = 'supervisor' then
  begin
    SetLength(Result, Length(SUPERVISOR_MODULES));
    for I := 0 to High(SUPERVISOR_MODULES) do Result[I] := SUPERVISOR_MODULES[I];
  end
  else if ARole = 'operator' then
  begin
    SetLength(Result, Length(OPERATOR_MODULES));
    for I := 0 to High(OPERATOR_MODULES) do Result[I] := OPERATOR_MODULES[I];
  end
  else
  begin
    SetLength(Result, Length(VIEWER_MODULES));
    for I := 0 to High(VIEWER_MODULES) do Result[I] := VIEWER_MODULES[I];
  end;
end;

function DefaultFinancials(const ARole: string): Boolean;
begin
  Result := (ARole = 'superadmin') or (ARole = 'admin') or (ARole = 'supervisor');
end;

function AuthInfo: TAuthInfo;
begin
  Result := GAuth;
end;

function Sha256Hex(const AValue: string): string;
begin
  Result := THashSHA2.GetHashString(AValue, THashSHA2.TSHA2Version.SHA256).ToLower;
end;

function NewSessionToken: string;
begin
  Result := Sha256Hex(TGUID.NewGuid.ToString + '|' + TGUID.NewGuid.ToString + '|' +
    FormatDateTime('yyyymmddhhnnsszzz', Now));
end;

procedure SetSessionCookie(Res: THorseResponse; const AToken: string);
begin
  Res.RawWebResponse.SetCustomHeader('Set-Cookie',
    'union_session=' + AToken + '; Path=/; HttpOnly; SameSite=Lax; Max-Age=' +
    IntToStr(TConfig.SessionHours * 3600));
end;

procedure ClearSessionCookie(Res: THorseResponse);
begin
  Res.RawWebResponse.SetCustomHeader('Set-Cookie',
    'union_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0');
end;

function TokenFromRequest(Req: THorseRequest): string;
var
  LHeader: string;
  LCookie: string;
begin
  Result := '';
  LHeader := Req.Headers['Authorization'];
  if LHeader.ToLower.StartsWith('bearer ') then
    Exit(LHeader.Substring(7).Trim);

  try
    if Req.Cookie.TryGetValue('union_session', LCookie) then
      Result := LCookie.Trim;
  except
    Result := '';
  end;
end;

function ModulesAsJson: TJSONArray;
var
  LModule: string;
begin
  Result := TJSONArray.Create;
  for LModule in GAuth.Modules do
    Result.Add(LModule);
end;

procedure FillAuthFromJson(AObj: TJSONObject);
var
  LModules, LFin: TJSONValue;
  LArr: TJSONArray;
  I: Integer;
begin
  GAuth.Authenticated := True;
  GAuth.UserId := GetInt(AObj, 'id', 0);
  GAuth.CompanyId := GetInt(AObj, 'company_id', 0);
  GAuth.Username := GetStr(AObj, 'username');
  GAuth.FullName := GetStr(AObj, 'full_name');
  GAuth.Role := GetStr(AObj, 'role', 'viewer');
  GAuth.MustChangePassword := GetBool(AObj, 'must_change_password', False);

  LFin := AObj.FindValue('can_view_financials');
  if Assigned(LFin) and not (LFin is TJSONNull) then
    GAuth.CanViewFinancials := GetBool(AObj, 'can_view_financials', False)
  else
    GAuth.CanViewFinancials := DefaultFinancials(GAuth.Role);

  LModules := AObj.FindValue('allowed_modules');
  if Assigned(LModules) and (LModules is TJSONArray) then
  begin
    LArr := TJSONArray(LModules);
    SetLength(GAuth.Modules, LArr.Count);
    for I := 0 to LArr.Count - 1 do
      GAuth.Modules[I] := LArr.Items[I].Value;
  end
  else
    GAuth.Modules := DefaultModules(GAuth.Role);
end;

const
  FINANCIAL_KEYS: array[0..45] of string = (
    'price', 'fare_total', 'revenue', 'revenue_ida', 'revenue_vuelta',
    'fuel_amount', 'oncology_amount', 'ticket_office_amount', 'mp_amount', 'other_amount',
    'surplus', 'amount', 'total_amount', 'net_amount', 'vat_amount', 'driver_commission',
    'cost', 'total_costs', 'total_income_net', 'total_income_gross', 'margin',
    'base_fare', 'per_km', 'max_fare', 'price_per_liter', 'tariff', 'commission_pct', 'vat_pct',
    'bus_revenue', 'bus_fuel', 'bus_deductions', 'bus_surplus',
    'freight_net', 'freight_vat', 'freight_total', 'freight_commission',
    'maintenance', 'maintenance_total', 'total_mantenimiento', 'total_combustible',
    'general_total', 'general_expenses', 'general',
    'abono_price', 'total_abonos', 'total_cobros'
  );

function IsFinancialKey(const AKey: string): Boolean;
var
  LKey: string;
  I: Integer;
begin
  LKey := AKey.ToLower;
  for I := 0 to High(FINANCIAL_KEYS) do
    if FINANCIAL_KEYS[I] = LKey then
      Exit(True);
  Result := False;
end;

procedure StripFinancialValue(AValue: TJSONValue);
var
  LObj: TJSONObject;
  LArr: TJSONArray;
  I: Integer;
  LName: string;
begin
  if AValue is TJSONObject then
  begin
    LObj := TJSONObject(AValue);
    for I := LObj.Count - 1 downto 0 do
    begin
      LName := LObj.Pairs[I].JsonString.Value;
      if IsFinancialKey(LName) then
        LObj.RemovePair(LName).Free
      else
        StripFinancialValue(LObj.Pairs[I].JsonValue);
    end;
  end
  else if AValue is TJSONArray then
  begin
    LArr := TJSONArray(AValue);
    for I := 0 to LArr.Count - 1 do
      StripFinancialValue(LArr.Items[I]);
  end;
end;

procedure StripFinancials(Res: THorseResponse);
var
  LContentType, LContent: string;
  LValue: TJSONValue;
begin
  LContentType := Res.RawWebResponse.ContentType.ToLower;
  if Pos('application/json', LContentType) = 0 then
    Exit;
  LContent := Res.RawWebResponse.Content;
  if LContent.Trim.IsEmpty then
    Exit;
  LValue := TJSONObject.ParseJSONValue(LContent);
  if not Assigned(LValue) then
    Exit;
  try
    StripFinancialValue(LValue);
    Res.Send(LValue.ToJSON);
  finally
    LValue.Free;
  end;
end;

function PathModuleAllowed(const APath, AMethod: string): Boolean;
var
  LPath, LMethod: string;
begin  LPath := APath.ToLower;
  LMethod := AMethod.ToUpper;

  if LPath = '/api/reports/latest' then Exit(True);

  if LPath.StartsWith('/api/dashboard') then
    Exit(GAuth.HasModule('dashboard'));

  if LPath.StartsWith('/api/schedules') then
  begin
    if LMethod = 'GET' then
      Exit(GAuth.HasAnyModule(['schedules', 'colectivos']));
    Exit(GAuth.HasModule('schedules'));
  end;

  if LPath.StartsWith('/api/services') then
  begin
    if LMethod = 'GET' then
      Exit(GAuth.HasAnyModule(['colectivos', 'expenses', 'fuel', 'reports']));
    Exit(GAuth.HasModule('colectivos'));
  end;

  if LPath.StartsWith('/api/fuel') then Exit(GAuth.HasModule('fuel'));
  if LPath.StartsWith('/api/expenses') then Exit(GAuth.HasModule('expenses'));
  if LPath.StartsWith('/api/maintenance') then Exit(GAuth.HasModule('maintenance'));
  if LPath.StartsWith('/api/freight') then Exit(GAuth.HasModule('camion'));

  if LPath.StartsWith('/api/reports/audit') then Exit(GAuth.HasModule('audit'));
  if LPath.StartsWith('/api/reports') then Exit(GAuth.HasModule('reports'));

  if LPath.StartsWith('/api/vehicles') or LPath.StartsWith('/api/employees') or
     LPath.StartsWith('/api/routes') then
  begin
    if LMethod = 'GET' then Exit(True);
    Exit(GAuth.HasModule('masters'));
  end;

  if LPath.StartsWith('/api/users') or LPath.StartsWith('/api/companies') then
    Exit(GAuth.HasModule('users'));

  if LPath.StartsWith('/api/settings') then
  begin
    if LMethod = 'GET' then Exit(True);
    Exit(GAuth.HasModule('settings'));
  end;

  Result := True;
end;

procedure AuthMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LPath, LToken, LHash, LJson: string;
  LValue: TJSONValue;
begin
  LPath := Req.RawWebRequest.PathInfo.ToLower;
  if not LPath.StartsWith('/api') then
  begin
    Next;
    Exit;
  end;
  if (LPath = '/api/auth/login') or (LPath = '/api/health') then
  begin
    Next;
    Exit;
  end;

  LToken := TokenFromRequest(Req);
  if LToken.IsEmpty then
  begin
    SendError(Res, 'No autenticado', 401);
    raise EHorseCallbackInterrupted.Create;
  end;

  LHash := Sha256Hex(LToken);
  LJson := TDB.Q(
    'select json_build_object(' +
    '  ''id'', u.id, ''company_id'', u.company_id, ''username'', u.username,' +
    '  ''full_name'', u.full_name, ''role'', u.role,' +
    '  ''must_change_password'', u.must_change_password,' +
    '  ''allowed_modules'', u.allowed_modules,' +
    '  ''can_view_financials'', u.can_view_financials) ' +
    'from sessions s join users u on u.id = s.user_id ' +
    'where s.token_hash = :p0 and s.expires_at > now() and u.active',
    [LHash]);

  if LJson.Trim.IsEmpty then
  begin
    SendError(Res, 'Sesión inválida o expirada', 401);
    raise EHorseCallbackInterrupted.Create;
  end;

  LValue := TJSONObject.ParseJSONValue(LJson);
  if not Assigned(LValue) or not (LValue is TJSONObject) then
  begin
    LValue.Free;
    SendError(Res, 'Sesión inválida', 401);
    raise EHorseCallbackInterrupted.Create;
  end;

  try
    GAuth := Default(TAuthInfo);
    FillAuthFromJson(TJSONObject(LValue));
    if not PathModuleAllowed(LPath, Req.RawWebRequest.Method) then
    begin
      SendError(Res, 'No tiene acceso a este módulo', 403);
      raise EHorseCallbackInterrupted.Create;
    end;

    if (not GAuth.CanViewFinancials) and LPath.StartsWith('/api/reports') and
       (LPath <> '/api/reports/latest') and (not LPath.StartsWith('/api/reports/audit')) then
    begin
      SendError(Res, 'No tiene permiso para ver importes y recaudación', 403);
      raise EHorseCallbackInterrupted.Create;
    end;

    Next;
    if not GAuth.CanViewFinancials then
      StripFinancials(Res);
  finally
    LValue.Free;
    GAuth := Default(TAuthInfo);
  end;
end;

procedure LoginHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LUsername, LPassword, LJson, LToken, LHash, LIP, LUA: string;
  LValue: TJSONValue;
  LUser: TJSONObject;
  LResp: TJSONObject;
  LSeconds: Integer;
begin
  LBody := nil;
  LValue := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then
    begin
      SendError(Res, LErr, 400);
      Exit;
    end;

    LUsername := GetStr(LBody, 'username').Trim;
    LPassword := GetStr(LBody, 'password');
    if LUsername.IsEmpty or LPassword.IsEmpty then
    begin
      SendError(Res, 'Usuario y contraseña son obligatorios', 400);
      Exit;
    end;

    LJson := TDB.Q(
      'select json_build_object(' +
      '  ''id'', u.id, ''company_id'', u.company_id, ''username'', u.username,' +
      '  ''full_name'', u.full_name, ''role'', u.role,' +
      '  ''must_change_password'', u.must_change_password,' +
      '  ''allowed_modules'', u.allowed_modules,' +
      '  ''can_view_financials'', u.can_view_financials) ' +
      'from users u where u.username = :p0 and u.active ' +
      'and u.password_hash = crypt(:p1, u.password_hash)',
      [LUsername, LPassword]);

    if LJson.Trim.IsEmpty then
    begin
      AuditLoginFailure(LUsername, '{"reason":"invalid_credentials"}');
      SendError(Res, 'Usuario o contraseña incorrectos', 401);
      Exit;
    end;

    LValue := TJSONObject.ParseJSONValue(LJson);
    if not Assigned(LValue) or not (LValue is TJSONObject) then
    begin
      SendError(Res, 'Error interno de autenticación', 500);
      Exit;
    end;
    LUser := TJSONObject(LValue);

    GAuth := Default(TAuthInfo);
    FillAuthFromJson(LUser);

    LToken := NewSessionToken;
    LHash := Sha256Hex(LToken);
    LIP := Copy(Req.RawWebRequest.RemoteIP, 1, 60);
    LUA := Copy(Req.Headers['User-Agent'], 1, 255);
    LSeconds := TConfig.SessionHours * 3600;

    TDB.Exec(
      'insert into sessions (token_hash, user_id, expires_at, ip, user_agent) ' +
      'values (:p0, :p1, now() + make_interval(hours => :p2), :p3, :p4)',
      [LHash, GAuth.UserId, TConfig.SessionHours, LIP, LUA]);

    TDB.Exec('update users set last_login = now() where id = :p0', [GAuth.UserId]);
    AuditAction('login', 'session', 0, '{"result":"ok"}');

    LResp := TJSONObject.Create;
    try
      LResp.AddPair('token', LToken);
      LResp.AddPair('expires_in', TJSONNumber.Create(LSeconds));
      LResp.AddPair('user', TJSONObject(LValue.Clone));
      LResp.AddPair('must_change_password', TJSONBool.Create(GAuth.MustChangePassword));
      LResp.AddPair('modules', ModulesAsJson);
      LResp.AddPair('can_view_financials', TJSONBool.Create(GAuth.CanViewFinancials));
      SetSessionCookie(Res, LToken);
      SendJsonText(Res, LResp.ToJSON, 200);
    finally
      LResp.Free;
    end;
  except
    on E: Exception do
    begin
      LogError('login: ' + E.Message);
      SendError(Res, 'Error de autenticación', 500);
    end;
  end;
  LValue.Free;
  LBody.Free;
end;

procedure LogoutHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LToken: string;
begin
  try
    LToken := TokenFromRequest(Req);
    if not LToken.IsEmpty then
      TDB.Exec('delete from sessions where token_hash = :p0', [Sha256Hex(LToken)]);
    AuditAction('logout', 'session', 0, '{}');
    ClearSessionCookie(Res);
    SendOk(Res);
  except
    on E: Exception do
      SendError(Res, E.Message, 500);
  end;
end;

procedure MeHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LJson: string;
  LValue: TJSONValue;
begin
  try
    LJson := TDB.Q(
      'select json_build_object(' +
      '  ''user'', (select row_to_json(u) from (select * from v_users where id = :p0) u),' +
      '  ''company'', (select row_to_json(c) from (select id, name, legal_name, cuit, address, phone, email from companies where id = :p1) c),' +
      '  ''settings'', (select coalesce(json_object_agg(key, value), ''{}''::json) from settings where company_id = :p1)' +
      ')',
      [GAuth.UserId, GAuth.CompanyId]);
    LValue := TJSONObject.ParseJSONValue(LJson);
    if Assigned(LValue) and (LValue is TJSONObject) then
    begin
      TJSONObject(LValue).AddPair('modules', ModulesAsJson);
      TJSONObject(LValue).AddPair('can_view_financials', TJSONBool.Create(GAuth.CanViewFinancials));
      SendJsonText(Res, TJSONObject(LValue).ToJSON, 200);
    end
    else
      SendJsonText(Res, LJson, 200);
    LValue.Free;
  except
    on E: Exception do
      SendError(Res, E.Message, 500);
  end;
end;

procedure ChangePasswordHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LCurrent, LNew: string;
  LOk: Boolean;
begin
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then
    begin
      SendError(Res, LErr, 400);
      Exit;
    end;

    LCurrent := GetStr(LBody, 'current_password');
    LNew := GetStr(LBody, 'new_password');
    if Length(LNew) < 8 then
    begin
      SendError(Res, 'La nueva contraseña debe tener al menos 8 caracteres', 400);
      Exit;
    end;

    LOk := TDB.QInt(
      'select count(*) from users where id = :p0 and password_hash = crypt(:p1, password_hash)',
      [GAuth.UserId, LCurrent]) > 0;
    if not LOk then
    begin
      SendError(Res, 'La contraseña actual no es correcta', 400);
      Exit;
    end;

    TDB.Exec(
      'update users set password_hash = crypt(:p0, gen_salt(''bf'', 12)), ' +
      'must_change_password = false where id = :p1',
      [LNew, GAuth.UserId]);
    AuditAction('change_password', 'user', GAuth.UserId, '{}');
    SendOk(Res);
  except
    on E: Exception do
      SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

function RequireRole(Res: THorseResponse; const ARoles: array of string): Boolean;
var
  LRole: string;
begin
  for LRole in ARoles do
    if GAuth.Role = LRole then
      Exit(True);
  SendError(Res, 'No tiene permisos para esta operación', 403);
  raise EHorseCallbackInterrupted.Create;
end;

function RequireWrite(Res: THorseResponse): Boolean;
begin
  Result := RequireRole(Res, ['superadmin', 'admin', 'supervisor', 'operator']);
end;

function RequireAdmin(Res: THorseResponse): Boolean;
begin
  Result := RequireRole(Res, ['superadmin', 'admin']);
end;

function RequireSuper(Res: THorseResponse): Boolean;
begin
  Result := RequireRole(Res, ['superadmin']);
end;

function EffectiveCompany(Req: THorseRequest): Integer;
var
  LValue: string;
begin
  Result := GAuth.CompanyId;
  if GAuth.IsSuper then
  begin
    LValue := QueryValue(Req, 'company_id', '');
    if not LValue.IsEmpty then
      Result := StrToIntDef(LValue, Result);
  end;
end;

function BodyCompany(Req: THorseRequest; AObj: TJSONObject): Integer;
begin
  Result := GAuth.CompanyId;
  if GAuth.IsSuper and Has(AObj, 'company_id') then
    Result := GetInt(AObj, 'company_id', Result);
end;

procedure AuditAction(const AAction, AEntity: string; AEntityId: Integer;
  const ADetails: string);
var
  LDetails: string;
  LTest: TJSONValue;
  LObj: TJSONObject;
  LUser, LCompany, LEntity: Variant;
begin
  LDetails := ADetails.Trim;
  if LDetails.IsEmpty then
    LDetails := '{}';
  LTest := TJSONObject.ParseJSONValue(LDetails);
  if not Assigned(LTest) or not (LTest is TJSONObject) then
  begin
    LTest.Free;
    LObj := TJSONObject.Create;
    try
      LObj.AddPair('msg', LDetails);
      LDetails := LObj.ToJSON;
    finally
      LObj.Free;
    end;
  end
  else
    LTest.Free;

  if GAuth.UserId > 0 then LUser := GAuth.UserId else LUser := 0;
  if GAuth.CompanyId > 0 then LCompany := GAuth.CompanyId else LCompany := 0;
  if AEntityId > 0 then LEntity := AEntityId else LEntity := 0;

  try
    TDB.Exec(
      'insert into audit_log (company_id, user_id, username, action, entity, entity_id, details, ip) ' +
      'values (:p0, :p1, :p2, :p3, :p4, :p5, :p6::jsonb, :p7)',
      [LCompany, LUser, GAuth.Username, AAction, AEntity, LEntity, LDetails, GRequestIP]);
  except
    on E: Exception do
      LogError('audit: ' + E.Message);
  end;
end;

procedure AuditLoginFailure(const AUsername, ADetails: string);
begin
  try
    TDB.Exec(
      'insert into audit_log (company_id, user_id, username, action, entity, entity_id, details, ip) ' +
      'values (NULL, NULL, :p0, ''login_failed'', ''session'', NULL, :p1::jsonb, :p2)',
      [AUsername, ADetails, GRequestIP]);
  except
    on E: Exception do
      LogError('audit login: ' + E.Message);
  end;
end;

end.
