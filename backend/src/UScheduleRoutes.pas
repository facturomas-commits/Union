unit UScheduleRoutes;

interface

procedure RegisterScheduleRoutes;

implementation

uses
  System.SysUtils, System.JSON, System.Variants,
  Horse, UHttp, UAuth, UApi, UDB, ULog;

const
  SCHEDULE_FIELDS: array[0..7] of TFieldDef = (
    (Name: 'route_id';       Kind: fkInt;  Required: True),
    (Name: 'direction';      Kind: fkText; Required: True),
    (Name: 'departure_time'; Kind: fkTime; Required: True),
    (Name: 'vehicle_id';     Kind: fkInt;  Required: True),
    (Name: 'driver_id';      Kind: fkInt;  Required: False),
    (Name: 'guard_id';       Kind: fkInt;  Required: False),
    (Name: 'active';         Kind: fkBool; Required: False),
    (Name: 'notes';          Kind: fkText; Required: False)
  );

function ValidDirection(const AValue: string): Boolean;
begin
  Result := (AValue = 'ida') or (AValue = 'vuelta');
end;

procedure ListSchedules(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LRoute, LVehicle: Integer;
  LDirection: string;
begin
  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_schedules where company_id = :p0';
  SetLength(LParams, 1);
  LParams[0] := EffectiveCompany(Req);
  LRoute := QueryInt(Req, 'route_id', 0);
  LVehicle := QueryInt(Req, 'vehicle_id', 0);
  LDirection := QueryValue(Req, 'direction', '');
  if LRoute > 0 then
  begin
    LSQL := LSQL + ' and route_id = :p' + IntToStr(Length(LParams));
    SetLength(LParams, Length(LParams) + 1);
    LParams[High(LParams)] := LRoute;
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
  if QueryValue(Req, 'active', '') = '1' then
    LSQL := LSQL + ' and active = true';
  LSQL := LSQL + ' order by route_id, direction, departure_time) t';
  SendList(Res, LSQL, LParams);
end;

procedure GetSchedule(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  SendEntity(Res, 'v_schedules', StrToIntDef(ParamValue(Req, 'id', '0'), 0), EffectiveCompany(Req));
end;

function ValidateSchedule(AObj: TJSONObject; ACompany, AId: Integer; out AErr: string): Boolean;
var
  LDirection: string;
  LRoute, LVehicle, LDup: Integer;
  LTime: string;
begin
  AErr := '';
  Result := False;
  LDirection := GetStr(AObj, 'direction', 'ida');
  if not ValidDirection(LDirection) then
  begin
    AErr := 'Dirección inválida: use ida o vuelta';
    Exit;
  end;
  LRoute := GetInt(AObj, 'route_id', 0);
  LVehicle := GetInt(AObj, 'vehicle_id', 0);
  LTime := GetStr(AObj, 'departure_time', '');
  if (LRoute <= 0) or (LVehicle <= 0) or LTime.IsEmpty then
  begin
    AErr := 'Complete ruta, vehículo y horario';
    Exit;
  end;
  if TDB.QInt('select count(*) from routes where id = :p0 and company_id = :p1',
    [LRoute, ACompany]) = 0 then
  begin
    AErr := 'Ruta inválida';
    Exit;
  end;
  if TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
    [LVehicle, ACompany]) = 0 then
  begin
    AErr := 'Vehículo inválido';
    Exit;
  end;
  LDup := TDB.QInt(
    'select count(*) from service_schedules where company_id = :p0 and route_id = :p1' +
    ' and direction = :p2 and departure_time = :p3::time and vehicle_id = :p4 and id <> :p5',
    [ACompany, LRoute, LDirection, Copy(LTime, 1, 8), LVehicle, AId]);
  if LDup > 0 then
  begin
    AErr := 'Ya existe una programación para esa ruta, dirección, horario y vehículo';
    Exit;
  end;
  Result := True;
end;

procedure CreateSchedule(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    if not ValidateSchedule(LBody, LCompany, 0, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if not InsertRow('service_schedules', SCHEDULE_FIELDS, LBody, LCompany, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'schedule', LId, '{}');
    SendJsonText(Res, TDB.Q('select row_to_json(t) from (select * from v_schedules where id = :p0) t', [LId]), 201);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateSchedule(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := BodyCompany(Req, LBody);
    if not ValidateSchedule(LBody, LCompany, LId, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    if not UpdateRow('service_schedules', SCHEDULE_FIELDS, LBody, LId, LCompany, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'schedule', LId, '{}');
    SendJsonText(Res, TDB.Q('select row_to_json(t) from (select * from v_schedules where id = :p0) t', [LId]), 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteSchedule(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('service_schedules', 'schedule', LId, EffectiveCompany(Req), False, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

procedure RegisterScheduleRoutes;
begin
  THorse.Get('/api/schedules', ListSchedules);
  THorse.Get('/api/schedules/:id', GetSchedule);
  THorse.Post('/api/schedules', CreateSchedule);
  THorse.Put('/api/schedules/:id', UpdateSchedule);
  THorse.Delete('/api/schedules/:id', DeleteSchedule);
end;

end.
