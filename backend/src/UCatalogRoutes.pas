unit UCatalogRoutes;

interface

procedure RegisterCatalogRoutes;

implementation

uses
  System.SysUtils, System.JSON, System.Classes, System.Variants, System.Math,
  System.Generics.Collections,
  Horse, UHttp, UAuth, UApi, UDB, ULog;

const
  VEHICLE_FIELDS: array[0..9] of TFieldDef = (
    (Name: 'kind';        Kind: fkText; Required: True),
    (Name: 'internal_no'; Kind: fkText; Required: True),
    (Name: 'plate';       Kind: fkText; Required: False),
    (Name: 'model';       Kind: fkText; Required: False),
    (Name: 'model_year';  Kind: fkInt;  Required: False),
    (Name: 'seats';       Kind: fkInt;  Required: False),
    (Name: 'capacity_kg'; Kind: fkNum;  Required: False),
    (Name: 'odometer';    Kind: fkNum;  Required: False),
    (Name: 'notes';       Kind: fkText; Required: False),
    (Name: 'active';      Kind: fkBool; Required: False)
  );

  EMPLOYEE_FIELDS: array[0..7] of TFieldDef = (
    (Name: 'full_name';  Kind: fkText; Required: True),
    (Name: 'dni';        Kind: fkText; Required: False),
    (Name: 'kind';       Kind: fkText; Required: True),
    (Name: 'license';    Kind: fkText; Required: False),
    (Name: 'phone';      Kind: fkText; Required: False),
    (Name: 'address';    Kind: fkText; Required: False),
    (Name: 'hire_date';  Kind: fkDate; Required: False),
    (Name: 'active';     Kind: fkBool; Required: False)
  );

  ROUTE_FIELDS: array[0..5] of TFieldDef = (
    (Name: 'code';         Kind: fkText; Required: False),
    (Name: 'name';         Kind: fkText; Required: True),
    (Name: 'origin';       Kind: fkText; Required: True),
    (Name: 'destination';  Kind: fkText; Required: True),
    (Name: 'distance_km';  Kind: fkNum;  Required: False),
    (Name: 'active';       Kind: fkBool; Required: False)
  );

  WORKSHOP_FIELDS: array[0..4] of TFieldDef = (
    (Name: 'name';    Kind: fkText; Required: True),
    (Name: 'phone';   Kind: fkText; Required: False),
    (Name: 'address'; Kind: fkText; Required: False),
    (Name: 'notes';   Kind: fkText; Required: False),
    (Name: 'active';  Kind: fkBool; Required: False)
  );

  USER_FIELDS: array[0..5] of TFieldDef = (
    (Name: 'username';              Kind: fkText; Required: False),
    (Name: 'full_name';             Kind: fkText; Required: False),
    (Name: 'email';                 Kind: fkText; Required: False),
    (Name: 'role';                  Kind: fkText; Required: False),
    (Name: 'active';                Kind: fkBool; Required: False),
    (Name: 'must_change_password';  Kind: fkBool; Required: False)
  );

  COMPANY_FIELDS: array[0..5] of TFieldDef = (
    (Name: 'name';       Kind: fkText; Required: True),
    (Name: 'legal_name'; Kind: fkText; Required: False),
    (Name: 'cuit';       Kind: fkText; Required: False),
    (Name: 'address';    Kind: fkText; Required: False),
    (Name: 'phone';      Kind: fkText; Required: False),
    (Name: 'email';      Kind: fkText; Required: False)
  );

function ValidRole(const ARole: string): Boolean;
begin
  Result := (ARole = 'superadmin') or (ARole = 'admin') or
            (ARole = 'supervisor') or (ARole = 'operator') or (ARole = 'viewer');
end;

function ModulesJson(AObj: TJSONObject): string;
var
  LValue: TJSONValue;
begin
  Result := '';
  if not Has(AObj, 'allowed_modules') then
    Exit;
  LValue := AObj.FindValue('allowed_modules');
  if Assigned(LValue) and (LValue is TJSONArray) then
    Result := TJSONArray(LValue).ToJSON;
end;

procedure HealthHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendJsonText(Res, '{"status":"ok","service":"union-backend","version":"1.0"}', 200);
end;

{ ---------------- VEHÍCULOS ---------------- }

procedure ListVehicles(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LCompany: Integer;
  LSQL: string;
  LParams: TArray<Variant>;
  LKind: string;
begin
  try
    LCompany := EffectiveCompany(Req);
    LKind := QueryValue(Req, 'kind', '');
    LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      'select * from v_vehicles where company_id = :p0';
    SetLength(LParams, 1);
    LParams[0] := LCompany;
    if not LKind.IsEmpty then
    begin
      LSQL := LSQL + ' and kind = :p' + IntToStr(Length(LParams));
      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := LKind;
    end;
    if QueryValue(Req, 'active', '') = '1' then
      LSQL := LSQL + ' and active = true';
    LSQL := LSQL + ' order by kind, internal_no) t';
    SendList(Res, LSQL, LParams);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure GetVehicle(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_vehicles', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateVehicle(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    if not InsertRow('vehicles', VEHICLE_FIELDS, LBody, LCompany, LId, LErr) then
    begin
      SendError(Res, LErr, 400);
      Exit;
    end;
    AuditAction('create', 'vehicle', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateVehicle(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not UpdateRow('vehicles', VEHICLE_FIELDS, LBody, LId, LCompany, LErr) then
    begin
      SendError(Res, LErr, 400);
      Exit;
    end;
    AuditAction('update', 'vehicle', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteVehicle(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('vehicles', 'vehicle', LId, EffectiveCompany(Req), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- EMPLEADOS ---------------- }

procedure ListEmployees(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LCompany: Integer;
  LSQL, LKind: string;
  LParams: TArray<Variant>;
begin
  try
    LCompany := EffectiveCompany(Req);
    LKind := QueryValue(Req, 'kind', '');
    LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      'select * from v_employees where company_id = :p0';
    SetLength(LParams, 1);
    LParams[0] := LCompany;
    if not LKind.IsEmpty then
    begin
      LSQL := LSQL + ' and kind = :p' + IntToStr(Length(LParams));
      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := LKind;
    end;
    if QueryValue(Req, 'active', '') = '1' then
      LSQL := LSQL + ' and active = true';
    LSQL := LSQL + ' order by full_name) t';
    SendList(Res, LSQL, LParams);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure GetEmployee(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_employees', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateEmployee(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    if not InsertRow('employees', EMPLOYEE_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'employee', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateEmployee(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not UpdateRow('employees', EMPLOYEE_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'employee', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteEmployee(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('employees', 'employee', LId, EffectiveCompany(Req), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- RUTAS ---------------- }

procedure ListRoutes(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendList(Res,
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_routes where company_id = :p0 order by name) t',
    [EffectiveCompany(Req)]);
end;

procedure GetRoute(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_routes', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateRoute(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    if not InsertRow('routes', ROUTE_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'route', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateRoute(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not UpdateRow('routes', ROUTE_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'route', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteRoute(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('routes', 'route', LId, EffectiveCompany(Req), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- TALLERES ---------------- }

procedure ListWorkshops(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
begin
  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_workshops where company_id = :p0';
  if QueryValue(Req, 'active', '') = '1' then
    LSQL := LSQL + ' and active = true';
  LSQL := LSQL + ' order by name) t';
  SendList(Res, LSQL, [EffectiveCompany(Req)]);
end;

procedure GetWorkshop(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_workshops', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateWorkshop(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if GetStr(LBody, 'name').Trim.IsEmpty then
    begin SendError(Res, 'El nombre del taller es obligatorio', 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    if not InsertRow('workshops', WORKSHOP_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'workshop', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateWorkshop(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if Has(LBody, 'name') and GetStr(LBody, 'name').Trim.IsEmpty then
    begin SendError(Res, 'El nombre del taller es obligatorio', 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not UpdateRow('workshops', WORKSHOP_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'workshop', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteWorkshop(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('workshops', 'workshop', LId, EffectiveCompany(Req), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- USUARIOS ---------------- }

procedure ListUsers(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  if not RequireAdmin(Res) then Exit;
  SendList(Res,
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_users where company_id = :p0 order by full_name) t',
    [EffectiveCompany(Req)]);
end;

procedure CreateUser(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LUsername, LFullName, LRole, LPassword, LHash, LModules, LFinancial: string;
  LCompany, LId: Integer;
  LActive: Boolean;
begin
  if not RequireAdmin(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LUsername := GetStr(LBody, 'username').Trim;
    LFullName := GetStr(LBody, 'full_name').Trim;
    LRole := GetStr(LBody, 'role', 'operator');
    LPassword := GetStr(LBody, 'password');
    LActive := GetBool(LBody, 'active', True);

    if LUsername.IsEmpty or LFullName.IsEmpty or LPassword.IsEmpty then
    begin SendError(Res, 'Usuario, nombre y contraseña son obligatorios', 400); Exit; end;
    if (Length(LPassword) < 10) or SameText(LPassword, 'Admin123!') or
       SameText(LPassword, 'Operador123!') or SameText(LPassword, 'Consulta123!') then
    begin SendError(Res, 'La contraseña debe tener al menos 10 caracteres y no ser una clave por defecto', 400); Exit; end;
    if not ValidRole(LRole) then
    begin SendError(Res, 'Rol inválido', 400); Exit; end;
    if (LRole = 'superadmin') and not GAuth.IsSuper then
    begin SendError(Res, 'Solo el superadministrador puede crear superadministradores', 403); Exit; end;

    LCompany := BodyCompany(Req, LBody);
    if LCompany <= 0 then
    begin SendError(Res, 'Empresa inválida', 400); Exit; end;

    LHash := TDB.Q('select crypt(:p0, gen_salt(''bf'', 12))', [LPassword]);
    LModules := ModulesJson(LBody);
    if Has(LBody, 'can_view_financials') then
    begin
      if GetBool(LBody, 'can_view_financials', False) then LFinancial := 'true' else LFinancial := 'false';
    end
    else
      LFinancial := '';
    LId := TDB.ExecRetId(
      'insert into users (company_id, username, full_name, email, password_hash, role, active, must_change_password, allowed_modules, can_view_financials) ' +
      'values (:p0, :p1, :p2, :p3, :p4, :p5, :p6, :p7, NULLIF(:p8, '''')::jsonb, NULLIF(:p9, '''')::boolean) returning id',
      [LCompany, LUsername, LFullName, GetStr(LBody, 'email'), LHash, LRole, LActive,
       GetBool(LBody, 'must_change_password', True), LModules, LFinancial]);
    AuditAction('create', 'user', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateUser(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LRole, LPassword, LHash, LModules, LFinancial: string;
  LId, LCompany, LTargetCompany: Integer;
  LTargetRole: string;
  LActive, LHasModules, LHasFinancial: Boolean;
begin
  if not RequireAdmin(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);

    LTargetCompany := TDB.QInt('select coalesce(company_id, 0) from users where id = :p0', [LId]);
    LTargetRole := TDB.Q('select role from users where id = :p0', [LId]);
    if TDB.QInt('select count(*) from users where id = :p0', [LId]) = 0 then
    begin SendError(Res, 'Usuario no encontrado', 404); Exit; end;
    if (not GAuth.IsSuper) and (LTargetCompany <> LCompany) then
    begin SendError(Res, 'Usuario no encontrado', 404); Exit; end;
    if (LTargetRole = 'superadmin') and (not GAuth.IsSuper) then
    begin SendError(Res, 'Solo el superadministrador puede modificar ese usuario', 403); Exit; end;

    if Has(LBody, 'role') then
    begin
      LRole := GetStr(LBody, 'role');
      if not ValidRole(LRole) then begin SendError(Res, 'Rol inválido', 400); Exit; end;
      if (LRole = 'superadmin') and not GAuth.IsSuper then
      begin SendError(Res, 'Solo el superadministrador puede asignar ese rol', 403); Exit; end;
      if (LId = GAuth.UserId) and (LRole <> LTargetRole) then
      begin SendError(Res, 'No puede cambiar su propio rol', 400); Exit; end;
    end;

    LActive := GetBool(LBody, 'active', True);
    if (LId = GAuth.UserId) and Has(LBody, 'active') and (not LActive) then
    begin SendError(Res, 'No puede desactivar su propio usuario', 400); Exit; end;

    LPassword := GetStr(LBody, 'password');
    if not LPassword.IsEmpty then
    begin
      if (Length(LPassword) < 10) or SameText(LPassword, 'Admin123!') or
         SameText(LPassword, 'Operador123!') or SameText(LPassword, 'Consulta123!') then
      begin SendError(Res, 'La contraseña debe tener al menos 10 caracteres y no ser una clave por defecto', 400); Exit; end;
      LHash := TDB.Q('select crypt(:p0, gen_salt(''bf'', 12))', [LPassword]);
      TDB.Exec('update users set password_hash = :p0, must_change_password = true where id = :p1', [LHash, LId]);
      TDB.Exec('delete from sessions where user_id = :p0', [LId]);
    end;

    LHasModules := Has(LBody, 'allowed_modules');
    if LHasModules then
    begin
      LModules := ModulesJson(LBody);
      TDB.Exec('update users set allowed_modules = NULLIF(:p0, '''')::jsonb where id = :p1', [LModules, LId]);
    end;

    LHasFinancial := Has(LBody, 'can_view_financials');
    if LHasFinancial then
    begin
      if GetBool(LBody, 'can_view_financials', False) then LFinancial := 'true' else LFinancial := 'false';
      TDB.Exec('update users set can_view_financials = :p0::boolean where id = :p1', [LFinancial, LId]);
    end;

    if not UpdateRow('users', USER_FIELDS, LBody, LId,
      IfThen(GAuth.IsSuper, 0, LCompany), LErr) then
    begin
      if not (not LPassword.IsEmpty) and (not LHasModules) and (not LHasFinancial) then
      begin SendError(Res, LErr, 400); Exit; end;
    end;

    AuditAction('update', 'user', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteUser(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr, LTargetRole: string; LId: Integer;
begin
  if not RequireAdmin(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if LId = GAuth.UserId then
  begin SendError(Res, 'No puede eliminar su propio usuario', 400); Exit; end;
  LTargetRole := TDB.Q('select role from users where id = :p0', [LId]);
  if (LTargetRole = 'superadmin') and (not GAuth.IsSuper) then
  begin SendError(Res, 'Solo el superadministrador puede eliminar ese usuario', 403); Exit; end;
  if DeleteRow('users', 'user', LId, IfThen(GAuth.IsSuper, 0, EffectiveCompany(Req)), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- EMPRESAS ---------------- }

procedure ListCompanies(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  if not RequireAdmin(Res) then Exit;
  if GAuth.IsSuper then
    SendList(Res, 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (select * from companies order by name) t', [])
  else
    SendList(Res,
      'select coalesce(json_agg(row_to_json(t)), ''[]'') from (select * from companies where id = :p0) t',
      [GAuth.CompanyId]);
end;

procedure CreateCompany(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId: Integer;
begin
  if not RequireSuper(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if not InsertRow('companies', COMPANY_FIELDS, LBody, 0, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'company', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateCompany(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId: Integer;
begin
  if not RequireSuper(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    if not UpdateRow('companies', COMPANY_FIELDS, LBody, LId, 0, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'company', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteCompany(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireSuper(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if LId = GAuth.CompanyId then
  begin SendError(Res, 'No puede desactivar su propia empresa', 400); Exit; end;
  if DeleteRow('companies', 'company', LId, 0, False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- SETTINGS ---------------- }

procedure GetSettings(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  if not RequireAdmin(Res) then Exit;
  SendList(Res,
    'select coalesce(json_object_agg(key, value), ''{}''::json) from settings where company_id = :p0',
    [EffectiveCompany(Req)]);
end;

procedure SaveSettings(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LPair: TJSONPair;
  LCompany: Integer;
  I: Integer;
begin
  if not RequireAdmin(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    for I := 0 to LBody.Count - 1 do
    begin
      LPair := LBody.Pairs[I];
      if LPair.JsonString.Value = 'company_id' then Continue;
      TDB.Exec(
        'insert into settings (company_id, key, value) values (:p0, :p1, :p2) ' +
        'on conflict (company_id, key) do update set value = excluded.value',
        [LCompany, LPair.JsonString.Value, LPair.JsonValue.Value]);
    end;
    AuditAction('update', 'settings', 0, '{}');
    SendOk(Res, '{"saved":true}');
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure RegisterCatalogRoutes;
begin
  THorse.Get('/api/health', HealthHandler);

  THorse.Get('/api/vehicles', ListVehicles);
  THorse.Get('/api/vehicles/:id', GetVehicle);
  THorse.Post('/api/vehicles', CreateVehicle);
  THorse.Put('/api/vehicles/:id', UpdateVehicle);
  THorse.Delete('/api/vehicles/:id', DeleteVehicle);

  THorse.Get('/api/employees', ListEmployees);
  THorse.Get('/api/employees/:id', GetEmployee);
  THorse.Post('/api/employees', CreateEmployee);
  THorse.Put('/api/employees/:id', UpdateEmployee);
  THorse.Delete('/api/employees/:id', DeleteEmployee);

  THorse.Get('/api/routes', ListRoutes);
  THorse.Get('/api/routes/:id', GetRoute);
  THorse.Post('/api/routes', CreateRoute);
  THorse.Put('/api/routes/:id', UpdateRoute);
  THorse.Delete('/api/routes/:id', DeleteRoute);

  THorse.Get('/api/workshops', ListWorkshops);
  THorse.Get('/api/workshops/:id', GetWorkshop);
  THorse.Post('/api/workshops', CreateWorkshop);
  THorse.Put('/api/workshops/:id', UpdateWorkshop);
  THorse.Delete('/api/workshops/:id', DeleteWorkshop);

  THorse.Get('/api/users', ListUsers);
  THorse.Post('/api/users', CreateUser);
  THorse.Put('/api/users/:id', UpdateUser);
  THorse.Delete('/api/users/:id', DeleteUser);

  THorse.Get('/api/companies', ListCompanies);
  THorse.Post('/api/companies', CreateCompany);
  THorse.Put('/api/companies/:id', UpdateCompany);
  THorse.Delete('/api/companies/:id', DeleteCompany);

  THorse.Get('/api/settings', GetSettings);
  THorse.Put('/api/settings', SaveSettings);
end;

end.
