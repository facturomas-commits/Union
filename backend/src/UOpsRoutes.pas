unit UOpsRoutes;

interface

procedure RegisterOpsRoutes;

implementation

uses
  System.SysUtils, System.JSON, System.Classes, System.Variants, System.Math,
  Horse, UHttp, UAuth, UApi, UDB, ULog;

const
  SERVICE_FIELDS: array[0..14] of TFieldDef = (
    (Name: 'service_date';   Kind: fkDate; Required: True),
    (Name: 'route_id';       Kind: fkInt;  Required: True),
    (Name: 'vehicle_id';     Kind: fkInt;  Required: True),
    (Name: 'driver_id';      Kind: fkInt;  Required: False),
    (Name: 'guard_id';       Kind: fkInt;  Required: False),
    (Name: 'departure_time'; Kind: fkTime; Required: False),
    (Name: 'schedule_label'; Kind: fkText; Required: False),
    (Name: 'km';             Kind: fkNum;  Required: False),
    (Name: 'ticket_from';    Kind: fkInt;  Required: False),
    (Name: 'ticket_to';      Kind: fkInt;  Required: False),
    (Name: 'fare_total';     Kind: fkNum;  Required: False),
    (Name: 'notes';          Kind: fkText; Required: False),
    (Name: 'direction';      Kind: fkText; Required: False),
    (Name: 'return_of_id';   Kind: fkInt;  Required: False),
    (Name: 'schedule_id';    Kind: fkInt;  Required: False)
  );

  FUEL_FIELDS: array[0..9] of TFieldDef = (
    (Name: 'vehicle_id';      Kind: fkInt;  Required: True),
    (Name: 'service_id';      Kind: fkInt;  Required: False),
    (Name: 'load_date';       Kind: fkDate; Required: True),
    (Name: 'liters';          Kind: fkNum;  Required: False),
    (Name: 'price_per_liter'; Kind: fkNum;  Required: False),
    (Name: 'amount';          Kind: fkNum;  Required: False),
    (Name: 'odometer';        Kind: fkNum;  Required: False),
    (Name: 'full_tank';       Kind: fkBool; Required: False),
    (Name: 'station';         Kind: fkText; Required: False),
    (Name: 'notes';           Kind: fkText; Required: False)
  );

  EXPENSE_FIELDS: array[0..5] of TFieldDef = (
    (Name: 'service_id';   Kind: fkInt;  Required: False),
    (Name: 'vehicle_id';   Kind: fkInt;  Required: False),
    (Name: 'expense_date'; Kind: fkDate; Required: True),
    (Name: 'category';     Kind: fkText; Required: True),
    (Name: 'description';  Kind: fkText; Required: False),
    (Name: 'amount';       Kind: fkNum;  Required: False)
  );

  MAINT_FIELDS: array[0..11] of TFieldDef = (
    (Name: 'vehicle_id';       Kind: fkInt;  Required: True),
    (Name: 'maintenance_date'; Kind: fkDate; Required: True),
    (Name: 'category';         Kind: fkText; Required: True),
    (Name: 'concept';          Kind: fkText; Required: True),
    (Name: 'measures';         Kind: fkText; Required: False),
    (Name: 'next_due';         Kind: fkDate; Required: False),
    (Name: 'odometer';         Kind: fkNum;  Required: False),
    (Name: 'cost';             Kind: fkNum;  Required: False),
    (Name: 'budget_amount';    Kind: fkNum;  Required: False),
    (Name: 'status';           Kind: fkText; Required: False),
    (Name: 'workshop_id';      Kind: fkInt;  Required: False),
    (Name: 'notes';            Kind: fkText; Required: False)
  );

function AlertDays(ACompany: Integer): Integer;
var
  LValue: string;
begin
  LValue := TDB.Q('select value from settings where company_id = :p0 and key = ''maintenance_alert_days''', [ACompany]);
  Result := StrToIntDef(LValue, 15);
  if Result < 0 then Result := 15;
end;

function ValidCategory(const AValue: string): Boolean;
begin
  Result := (AValue = 'oncology') or (AValue = 'ticket_office') or
            (AValue = 'mp') or (AValue = 'other');
end;

function ValidDirection(const AValue: string): Boolean;
begin
  Result := (AValue = 'ida') or (AValue = 'vuelta');
end;

function ValidMaintenanceStatus(const AValue: string): Boolean;
begin
  Result := (AValue = 'programado') or (AValue = 'presupuestado') or
            (AValue = 'realizado') or (AValue = 'cancelado');
end;

function WorkshopExists(AWorkshopId, ACompany: Integer): Boolean;
begin
  if AWorkshopId <= 0 then
    Exit(True);
  Result := TDB.QInt('select count(*) from workshops where id = :p0 and company_id = :p1',
    [AWorkshopId, ACompany]) > 0;
end;

function CreateReturnFor(AOutboundId, ACompany: Integer; const AReturnTime: string;
  out AErr: string): Integer;
var
  LLabel: string;
  LUserId: Variant;
begin
  AErr := '';
  LLabel := 'VUELTA ' + Copy(AReturnTime, 1, 5);
  if GAuth.UserId > 0 then LUserId := GAuth.UserId else LUserId := 1;
  try
    Result := TDB.ExecRetId(
      'insert into services (company_id, service_date, route_id, vehicle_id, driver_id, guard_id,' +
      ' departure_time, schedule_label, direction, return_of_id, km, fare_total, status, notes, created_by)' +
      ' select company_id, service_date, route_id, vehicle_id, driver_id, guard_id,' +
      ' :p0::time, :p1, ''vuelta'', id, km, 0, ''open'', ''Vuelta generada automáticamente'', :p2' +
      ' from services where id = :p3 and company_id = :p4 returning id',
      [AReturnTime, LLabel, LUserId, AOutboundId, ACompany]);
    if Result <= 0 then
      AErr := 'No se pudo generar la vuelta';
  except
    on E: Exception do
    begin
      AErr := E.Message;
      Result := 0;
    end;
  end;
end;

function MonthStart: string;
begin
  Result := Copy(TodayISO, 1, 7) + '-01';
end;

{ ================= SERVICIOS ================= }

procedure ListServices(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LFrom, LTo, LStatus, LDirection: string;
  LVehicle: Integer;
begin
  try
    LFrom := QueryValue(Req, 'date_from', MonthStart);
    LTo := QueryValue(Req, 'date_to', TodayISO);
    LStatus := QueryValue(Req, 'status', '');
    LDirection := QueryValue(Req, 'direction', '');
    LVehicle := QueryInt(Req, 'vehicle_id', 0);

    LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      'select * from v_services where company_id = :p0 and service_date between :p1::date and :p2::date';
    SetLength(LParams, 3);
    LParams[0] := EffectiveCompany(Req);
    LParams[1] := LFrom;
    LParams[2] := LTo;
    if not LStatus.IsEmpty then
    begin
      LSQL := LSQL + ' and status = :p' + IntToStr(Length(LParams));
      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := LStatus;
    end;
    if LVehicle > 0 then
    begin
      LSQL := LSQL + ' and vehicle_id = :p' + IntToStr(Length(LParams));
      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := LVehicle;
    end;
    if not LDirection.IsEmpty then
    begin
      LSQL := LSQL + ' and direction = :p' + IntToStr(Length(LParams));
      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := LDirection;
    end;
    LSQL := LSQL + ' order by service_date desc, departure_time) t';
    SendList(Res, LSQL, LParams);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure GetService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LId, LCompany: Integer;
  LJson: string;
begin
  try
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);
    if TDB.QInt('select count(*) from services where id = :p0 and company_id = :p1',
      [LId, LCompany]) = 0 then
    begin
      SendError(Res, 'Servicio no encontrado', 404);
      Exit;
    end;
    LJson := TDB.Q(
      'select json_build_object(' +
      '  ''service'', (select row_to_json(s) from (select * from v_services where id = :p0 and company_id = :p1) s),' +
      '  ''fuel'', (select coalesce(json_agg(row_to_json(f)), ''[]'') from (select * from v_fuel_loads where service_id = :p0) f),' +
      '  ''expenses'', (select coalesce(json_agg(row_to_json(e)), ''[]'') from (select * from v_expenses where service_id = :p0) e)' +
      ')', [LId, LCompany]);
    SendJsonText(Res, LJson, 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure ApplyServiceNested(AId, ACompany: Integer; AObj: TJSONObject);
var
  LAmount, LLiters, LPrice: Double;
  LFull: Boolean;
  LDateText: string;
  LVehicleId: Integer;
  LOnc, LTick, LMp, LOth: Double;
  LUserId: Variant;
  LProcessFuel, LProcessExpenses: Boolean;
begin
  LDateText := TDB.Q('select service_date::text from services where id = :p0 and company_id = :p1', [AId, ACompany]);
  LVehicleId := TDB.QInt('select vehicle_id from services where id = :p0 and company_id = :p1', [AId, ACompany]);
  if GAuth.UserId > 0 then LUserId := GAuth.UserId else LUserId := Null;

  LProcessFuel := Has(AObj, 'fuel_amount') or Has(AObj, 'fuel_liters');
  if LProcessFuel then
  begin
    TDB.Exec('delete from fuel_loads where service_id = :p0', [AId]);
    LAmount := GetNum(AObj, 'fuel_amount', 0);
    LLiters := GetNum(AObj, 'fuel_liters', 0);
    LFull := GetBool(AObj, 'full_tank', False);
    if (LAmount > 0) or (LLiters > 0) then
    begin
      if LLiters > 0 then
        LPrice := Round(LAmount / LLiters * 100) / 100
      else
        LPrice := 0;
      TDB.Exec(
        'insert into fuel_loads (company_id, vehicle_id, service_id, load_date, liters, ' +
        'price_per_liter, amount, full_tank, notes, created_by) ' +
        'values (:p0, :p1, :p2, :p3::date, :p4, :p5, :p6, :p7, :p8, :p9)',
        [ACompany, LVehicleId, AId, LDateText, LLiters, LPrice, LAmount, LFull,
         'Cargado desde servicio', LUserId]);
    end;
  end;

  LProcessExpenses := Has(AObj, 'oncology_amount') or Has(AObj, 'ticket_office_amount') or
                      Has(AObj, 'mp_amount') or Has(AObj, 'other_amount');
  if LProcessExpenses then
  begin
    TDB.Exec('delete from service_expenses where service_id = :p0 and category in ' +
      '(''oncology'',''ticket_office'',''mp'',''other'')', [AId]);
    LOnc := GetNum(AObj, 'oncology_amount', 0);
    LTick := GetNum(AObj, 'ticket_office_amount', 0);
    LMp := GetNum(AObj, 'mp_amount', 0);
    LOth := GetNum(AObj, 'other_amount', 0);
    if LOnc > 0 then
      TDB.Exec('insert into service_expenses (company_id, service_id, vehicle_id, expense_date, category, description, amount, created_by) ' +
        'values (:p0,:p1,:p2,:p3::date,''oncology'',''Oncológico'',:p4,:p5)',
        [ACompany, AId, LVehicleId, LDateText, LOnc, LUserId]);
    if LTick > 0 then
      TDB.Exec('insert into service_expenses (company_id, service_id, vehicle_id, expense_date, category, description, amount, created_by) ' +
        'values (:p0,:p1,:p2,:p3::date,''ticket_office'',''Boleterías'',:p4,:p5)',
        [ACompany, AId, LVehicleId, LDateText, LTick, LUserId]);
    if LMp > 0 then
      TDB.Exec('insert into service_expenses (company_id, service_id, vehicle_id, expense_date, category, description, amount, created_by) ' +
        'values (:p0,:p1,:p2,:p3::date,''mp'',''Mercado Pago'',:p4,:p5)',
        [ACompany, AId, LVehicleId, LDateText, LMp, LUserId]);
    if LOth > 0 then
      TDB.Exec('insert into service_expenses (company_id, service_id, vehicle_id, expense_date, category, description, amount, created_by) ' +
        'values (:p0,:p1,:p2,:p3::date,''other'',''Otros'',:p4,:p5)',
        [ACompany, AId, LVehicleId, LDateText, LOth, LUserId]);
  end;
end;

procedure CreateService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LDirection, LReturnTime: string;
  LId, LCompany: Integer;
  LRoute, LVehicle, LReturnId: Integer;
  LCreateReturn: Boolean;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LRoute := GetInt(LBody, 'route_id', 0);
    LVehicle := GetInt(LBody, 'vehicle_id', 0);
    LDirection := GetStr(LBody, 'direction', 'ida');
    LCreateReturn := GetBool(LBody, 'create_return', False);
    LReturnTime := GetStr(LBody, 'return_departure_time', '');
    if not ValidDirection(LDirection) then
    begin SendError(Res, 'Dirección inválida: use ida o vuelta', 400); Exit; end;
    if LCreateReturn and (LDirection <> 'ida') then
    begin SendError(Res, 'Solo un servicio de ida puede generar su vuelta', 400); Exit; end;
    if LCreateReturn and LReturnTime.Trim.IsEmpty then
    begin SendError(Res, 'Indique el horario de la vuelta', 400); Exit; end;
    if TDB.QInt('select count(*) from routes where id = :p0 and company_id = :p1',
      [LRoute, LCompany]) = 0 then
    begin SendError(Res, 'Ruta inválida para la empresa', 400); Exit; end;
    if TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
      [LVehicle, LCompany]) = 0 then
    begin SendError(Res, 'Vehículo inválido para la empresa', 400); Exit; end;
    if (GetInt(LBody, 'schedule_id', 0) > 0) and
       (TDB.QInt('select count(*) from service_schedules where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'schedule_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Programación inválida para la empresa', 400); Exit; end;

    TDB.BeginTx;
    try
      if not InsertRow('services', SERVICE_FIELDS, LBody, LCompany, LId, LErr) then
      begin
        TDB.RollbackTx;
        SendError(Res, LErr, 400);
        Exit;
      end;
      TDB.Exec('update services set created_by = :p0 where id = :p1', [GAuth.UserId, LId]);
      ApplyServiceNested(LId, LCompany, LBody);
      if LCreateReturn then
      begin
        LReturnId := CreateReturnFor(LId, LCompany, Copy(LReturnTime, 1, 8), LErr);
        if LReturnId <= 0 then
        begin
          TDB.RollbackTx;
          SendError(Res, LErr, 400);
          Exit;
        end;
      end;
      TDB.CommitTx;
    except
      TDB.RollbackTx;
      raise;
    end;

    AuditAction('create', 'service', LId, '{}');
    SendJsonText(Res, TDB.Q('select row_to_json(t) from (select * from v_services where id = :p0) t', [LId]), 201);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr, LDirection, LReturnTime: string;
  LId, LCompany, LExistingReturn: Integer;
  LCreateReturn: Boolean;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    LDirection := GetStr(LBody, 'direction', '');
    if LDirection.IsEmpty then
      LDirection := TDB.Q('select direction from services where id = :p0 and company_id = :p1', [LId, LCompany]);
    if not ValidDirection(LDirection) then
    begin SendError(Res, 'Dirección inválida: use ida o vuelta', 400); Exit; end;
    LCreateReturn := GetBool(LBody, 'create_return', False);
    LReturnTime := GetStr(LBody, 'return_departure_time', '');
    if LCreateReturn and (LDirection <> 'ida') then
    begin SendError(Res, 'Solo un servicio de ida puede generar su vuelta', 400); Exit; end;
    if Has(LBody, 'route_id') and
       (TDB.QInt('select count(*) from routes where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'route_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Ruta inválida para la empresa', 400); Exit; end;
    if Has(LBody, 'vehicle_id') and
       (TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'vehicle_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Vehículo inválido para la empresa', 400); Exit; end;
    if Has(LBody, 'schedule_id') and (GetInt(LBody, 'schedule_id', 0) > 0) and
       (TDB.QInt('select count(*) from service_schedules where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'schedule_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Programación inválida para la empresa', 400); Exit; end;

    TDB.BeginTx;
    try
      if not UpdateRow('services', SERVICE_FIELDS, LBody, LId, LCompany, LErr) then
      begin
        TDB.RollbackTx;
        SendError(Res, LErr, 400);
        Exit;
      end;
      ApplyServiceNested(LId, LCompany, LBody);
      if LCreateReturn then
      begin
        LExistingReturn := TDB.QInt(
          'select coalesce(max(id),0) from services where return_of_id = :p0 and direction = ''vuelta''', [LId]);
        if LExistingReturn <= 0 then
        begin
          if LReturnTime.Trim.IsEmpty then
          begin
            TDB.RollbackTx;
            SendError(Res, 'Indique el horario de la vuelta', 400);
            Exit;
          end;
          if CreateReturnFor(LId, LCompany, Copy(LReturnTime, 1, 8), LErr) <= 0 then
          begin
            TDB.RollbackTx;
            SendError(Res, LErr, 400);
            Exit;
          end;
        end
        else if not LReturnTime.Trim.IsEmpty then
          TDB.Exec(
            'update services set departure_time = :p0::time, schedule_label = :p1 where id = :p2 and company_id = :p3',
            [Copy(LReturnTime, 1, 8), 'VUELTA ' + Copy(LReturnTime, 1, 5), LExistingReturn, LCompany]);
      end;
      TDB.CommitTx;
    except
      TDB.RollbackTx;
      raise;
    end;

    AuditAction('update', 'service', LId, '{}');
    SendJsonText(Res, TDB.Q('select row_to_json(t) from (select * from v_services where id = :p0) t', [LId]), 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('services', 'service', LId, EffectiveCompany(Req), True, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

procedure CloseService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany: Integer;
  LRevenue, LFuel, LOnc, LTick, LMp, LOth, LSurplus, LCash, LDiff: Double;
  LUserId: Variant;
  LResp: TJSONObject;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);
    if not ParseBodyObject(Req, LBody, LErr) then
    begin
      // El cierre puede venir sin body: se asume efectivo = sobrante.
      LBody := TJSONObject.Create;
    end;

    LRevenue := TDB.QFloat('select revenue from v_services where id = :p0 and company_id = :p1', [LId, LCompany]);
    if TDB.QInt('select count(*) from v_services where id = :p0 and company_id = :p1', [LId, LCompany]) = 0 then
    begin SendError(Res, 'Servicio no encontrado', 404); Exit; end;

    LFuel := TDB.QFloat('select fuel_amount from v_services where id = :p0', [LId]);
    LOnc := TDB.QFloat('select oncology_amount from v_services where id = :p0', [LId]);
    LTick := TDB.QFloat('select ticket_office_amount from v_services where id = :p0', [LId]);
    LMp := TDB.QFloat('select mp_amount from v_services where id = :p0', [LId]);
    LOth := TDB.QFloat('select other_amount from v_services where id = :p0', [LId]);
    LSurplus := TDB.QFloat('select surplus from v_services where id = :p0', [LId]);
    LCash := GetNum(LBody, 'cash_delivered', LSurplus);
    LDiff := LCash - LSurplus;
    if GAuth.UserId > 0 then LUserId := GAuth.UserId else LUserId := Null;

    TDB.BeginTx;
    try
      TDB.Exec(
        'insert into service_closings (service_id, revenue, fuel_amount, other_amount, surplus, ' +
        'cash_delivered, difference, notes, closed_by) ' +
        'values (:p0,:p1,:p2,:p3,:p4,:p5,:p6,:p7,:p8) ' +
        'on conflict (service_id) do update set revenue = excluded.revenue, ' +
        'fuel_amount = excluded.fuel_amount, other_amount = excluded.other_amount, ' +
        'surplus = excluded.surplus, cash_delivered = excluded.cash_delivered, ' +
        'difference = excluded.difference, notes = excluded.notes, ' +
        'closed_by = excluded.closed_by, closed_at = now()',
        [LId, LRevenue, LFuel, LOnc + LTick + LMp + LOth, LSurplus, LCash, LDiff,
         GetStr(LBody, 'notes'), LUserId]);
      TDB.Exec('update services set status = ''closed'', closed_at = now(), closed_by = :p0 where id = :p1 and company_id = :p2',
        [LUserId, LId, LCompany]);
      TDB.CommitTx;
    except
      TDB.RollbackTx;
      raise;
    end;

    AuditAction('close', 'service', LId, '{}');
    LResp := TJSONObject.Create;
    try
      LResp.AddPair('closed', True);
      LResp.AddPair('surplus', TJSONNumber.Create(LSurplus));
      LResp.AddPair('cash_delivered', TJSONNumber.Create(LCash));
      LResp.AddPair('difference', TJSONNumber.Create(LDiff));
      SendJsonText(Res, LResp.ToJSON, 200);
    finally
      LResp.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure ReopenService(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  try
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);
    TDB.BeginTx;
    try
      TDB.Exec('update services set status = ''open'', closed_at = null, closed_by = null where id = :p0 and company_id = :p1', [LId, LCompany]);
      TDB.Exec('delete from service_closings where service_id = :p0', [LId]);
      TDB.CommitTx;
    except
      TDB.RollbackTx;
      raise;
    end;
    AuditAction('reopen', 'service', LId, '{}');
    SendOk(Res, '{"reopened":true}');
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

{ ================= COMBUSTIBLE ================= }

procedure ListFuel(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LVehicle: Integer;
begin
  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_fuel_loads where company_id = :p0 and load_date between :p1::date and :p2::date';
  SetLength(LParams, 3);
  LParams[0] := EffectiveCompany(Req);
  LParams[1] := QueryValue(Req, 'date_from', MonthStart);
  LParams[2] := QueryValue(Req, 'date_to', TodayISO);
  LVehicle := QueryInt(Req, 'vehicle_id', 0);
  if LVehicle > 0 then
  begin
    LSQL := LSQL + ' and vehicle_id = :p' + IntToStr(Length(LParams));
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LVehicle;
  end;
  LSQL := LSQL + ' order by load_date desc, id desc) t';
  SendList(Res, LSQL, LParams);
end;

procedure GetFuel(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_fuel_loads', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateFuel(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany, LService: Integer;
  LLiters, LAmount, LPrice: Double;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LService := GetInt(LBody, 'service_id', 0);
    if LService > 0 then
    begin
      if TDB.QInt('select count(*) from services where id = :p0 and company_id = :p1', [LService, LCompany]) = 0 then
      begin SendError(Res, 'Servicio inválido', 400); Exit; end;
      if TDB.QInt('select count(*) from fuel_loads where service_id = :p0', [LService]) > 0 then
      begin SendError(Res, 'El servicio ya tiene una carga de combustible asociada. Edítela desde el servicio.', 409); Exit; end;
    end;

    LLiters := GetNum(LBody, 'liters', 0);
    LAmount := GetNum(LBody, 'amount', 0);
    LPrice := GetNum(LBody, 'price_per_liter', 0);
    if (LAmount = 0) and (LLiters > 0) and (LPrice > 0) then
    begin
      LAmount := Round(LLiters * LPrice * 100) / 100;
      LBody.RemovePair('amount').Free;
      LBody.AddPair('amount', TJSONNumber.Create(LAmount));
    end;

    if not InsertRow('fuel_loads', FUEL_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    TDB.Exec('update fuel_loads set created_by = :p0 where id = :p1', [GAuth.UserId, LId]);
    AuditAction('create', 'fuel', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateFuel(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if Has(LBody, 'vehicle_id') and
       (TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'vehicle_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Vehículo inválido', 400); Exit; end;
    if Has(LBody, 'service_id') and (GetInt(LBody, 'service_id', 0) > 0) then
    begin
      if TDB.QInt('select count(*) from services where id = :p0 and company_id = :p1',
        [GetInt(LBody, 'service_id', 0), LCompany]) = 0 then
      begin SendError(Res, 'Servicio inválido', 400); Exit; end;
      if TDB.QInt('select count(*) from fuel_loads where service_id = :p0 and id <> :p1',
        [GetInt(LBody, 'service_id', 0), LId]) > 0 then
      begin SendError(Res, 'El servicio ya tiene otra carga de combustible asociada', 409); Exit; end;
    end;
    if not UpdateRow('fuel_loads', FUEL_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'fuel', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteFuel(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('fuel_loads', 'fuel', LId, EffectiveCompany(Req), True, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ================= GASTOS ================= }

procedure ListExpenses(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LService: Integer;
begin
  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_expenses where company_id = :p0 and expense_date between :p1::date and :p2::date';
  SetLength(LParams, 3);
  LParams[0] := EffectiveCompany(Req);
  LParams[1] := QueryValue(Req, 'date_from', MonthStart);
  LParams[2] := QueryValue(Req, 'date_to', TodayISO);
  LService := QueryInt(Req, 'service_id', 0);
  if LService > 0 then
  begin
    LSQL := LSQL + ' and service_id = :p' + IntToStr(Length(LParams));
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LService;
  end;
  LSQL := LSQL + ' order by expense_date desc, id desc) t';
  SendList(Res, LSQL, LParams);
end;

procedure CreateExpense(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr, LCategory: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LCategory := GetStr(LBody, 'category');
    if not ValidCategory(LCategory) then
    begin SendError(Res, 'Categoría inválida', 400); Exit; end;
    if (GetInt(LBody, 'service_id', 0) > 0) and
       (TDB.QInt('select count(*) from services where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'service_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Servicio inválido', 400); Exit; end;
    if not InsertRow('service_expenses', EXPENSE_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    TDB.Exec('update service_expenses set created_by = :p0 where id = :p1', [GAuth.UserId, LId]);
    AuditAction('create', 'expense', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateExpense(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if Has(LBody, 'category') and (not ValidCategory(GetStr(LBody, 'category'))) then
    begin SendError(Res, 'Categoría inválida', 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if Has(LBody, 'service_id') and (GetInt(LBody, 'service_id', 0) > 0) and
       (TDB.QInt('select count(*) from services where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'service_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Servicio inválido', 400); Exit; end;
    if not UpdateRow('service_expenses', EXPENSE_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'expense', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteExpense(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('service_expenses', 'expense', LId, EffectiveCompany(Req), True, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ================= MANTENIMIENTO ================= }

procedure ListMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LVehicle, LDays: Integer;
  LDue, LStatus: string;
begin
  LDue := QueryValue(Req, 'due', '');
  LStatus := QueryValue(Req, 'status', '');
  LVehicle := QueryInt(Req, 'vehicle_id', 0);
  LDays := QueryInt(Req, 'days', AlertDays(EffectiveCompany(Req)));

  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_maintenance where company_id = :p0';
  SetLength(LParams, 1);
  LParams[0] := EffectiveCompany(Req);
  if LVehicle > 0 then
  begin
    LSQL := LSQL + ' and vehicle_id = :p' + IntToStr(Length(LParams));
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LVehicle;
  end;
  if not LStatus.IsEmpty and ValidMaintenanceStatus(LStatus) then
  begin
    LSQL := LSQL + ' and status = :p' + IntToStr(Length(LParams));
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LStatus;
  end;
  if LDue = '1' then
  begin
    LSQL := LSQL + ' and status = ''realizado'' and next_due is not null and next_due <= current_date + :p' + IntToStr(Length(LParams)) + '::int';
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LDays;
    LSQL := LSQL + ' order by next_due) t';
  end
  else
    LSQL := LSQL + ' order by maintenance_date desc, id desc) t';
  SendList(Res, LSQL, LParams);
end;

procedure GetMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_maintenance', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

procedure CreateMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany, LVehicle: Integer; LOdo: Double;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LVehicle := GetInt(LBody, 'vehicle_id', 0);
    if TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1', [LVehicle, LCompany]) = 0 then
    begin SendError(Res, 'Vehículo inválido', 400); Exit; end;
    if not Has(LBody, 'status') then
      LBody.AddPair('status', 'programado');
    if not ValidMaintenanceStatus(GetStr(LBody, 'status', 'programado')) then
    begin SendError(Res, 'Estado de mantenimiento inválido', 400); Exit; end;
    if not WorkshopExists(GetInt(LBody, 'workshop_id', 0), LCompany) then
    begin SendError(Res, 'Taller inválido', 400); Exit; end;
    if not InsertRow('maintenance', MAINT_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    TDB.Exec('update maintenance set created_by = :p0 where id = :p1', [GAuth.UserId, LId]);
    LOdo := GetNum(LBody, 'odometer', 0);
    if LOdo > 0 then
      TDB.Exec('update vehicles set odometer = greatest(odometer, :p0) where id = :p1 and company_id = :p2',
        [LOdo, LVehicle, LCompany]);
    AuditAction('create', 'maintenance', LId, '{}');
    SendCreated(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if Has(LBody, 'vehicle_id') and
       (TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'vehicle_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Vehículo inválido', 400); Exit; end;
    if Has(LBody, 'status') and (not ValidMaintenanceStatus(GetStr(LBody, 'status'))) then
    begin SendError(Res, 'Estado de mantenimiento inválido', 400); Exit; end;
    if Has(LBody, 'workshop_id') and (not WorkshopExists(GetInt(LBody, 'workshop_id', 0), LCompany)) then
    begin SendError(Res, 'Taller inválido', 400); Exit; end;
    if not UpdateRow('maintenance', MAINT_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'maintenance', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure CompleteMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany, LVehicle: Integer;
  LOdo: Double;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not Has(LBody, 'maintenance_date') then
      LBody.AddPair('maintenance_date', FormatDateTime('yyyy-mm-dd', Date));
    LBody.RemovePair('status').Free;
    LBody.AddPair('status', 'realizado');
    if not UpdateRow('maintenance', MAINT_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    LVehicle := TDB.QInt('select vehicle_id from maintenance where id = :p0 and company_id = :p1',
      [LId, LCompany]);
    LOdo := GetNum(LBody, 'odometer', 0);
    if (LVehicle > 0) and (LOdo > 0) then
      TDB.Exec('update vehicles set odometer = greatest(odometer, :p0) where id = :p1 and company_id = :p2',
        [LOdo, LVehicle, LCompany]);
    AuditAction('complete', 'maintenance', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteMaintenance(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('maintenance', 'maintenance', LId, EffectiveCompany(Req), True, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

procedure RegisterOpsRoutes;
begin
  THorse.Get('/api/services', ListServices);
  THorse.Get('/api/services/:id', GetService);
  THorse.Post('/api/services', CreateService);
  THorse.Put('/api/services/:id', UpdateService);
  THorse.Delete('/api/services/:id', DeleteService);
  THorse.Post('/api/services/:id/close', CloseService);
  THorse.Post('/api/services/:id/reopen', ReopenService);

  THorse.Get('/api/fuel', ListFuel);
  THorse.Get('/api/fuel/:id', GetFuel);
  THorse.Post('/api/fuel', CreateFuel);
  THorse.Put('/api/fuel/:id', UpdateFuel);
  THorse.Delete('/api/fuel/:id', DeleteFuel);

  THorse.Get('/api/expenses', ListExpenses);
  THorse.Post('/api/expenses', CreateExpense);
  THorse.Put('/api/expenses/:id', UpdateExpense);
  THorse.Delete('/api/expenses/:id', DeleteExpense);

  THorse.Get('/api/maintenance', ListMaintenance);
  THorse.Get('/api/maintenance/:id', GetMaintenance);
  THorse.Post('/api/maintenance', CreateMaintenance);
  THorse.Put('/api/maintenance/:id', UpdateMaintenance);
  THorse.Post('/api/maintenance/:id/complete', CompleteMaintenance);
  THorse.Delete('/api/maintenance/:id', DeleteMaintenance);
end;

end.
