unit UFreightRoutes;

interface

procedure RegisterFreightRoutes;

implementation

uses
  System.SysUtils, System.JSON, System.Classes, System.Variants, System.Math,
  System.Generics.Collections,
  Horse, UHttp, UAuth, UApi, UDB, ULog;

const
  TRIP_FIELDS: array[0..5] of TFieldDef = (
    (Name: 'trip_date';      Kind: fkDate; Required: True),
    (Name: 'vehicle_id';     Kind: fkInt;  Required: True),
    (Name: 'driver_id';      Kind: fkInt;  Required: False),
    (Name: 'km';             Kind: fkNum;  Required: False),
    (Name: 'commission_pct'; Kind: fkNum;  Required: False),
    (Name: 'notes';          Kind: fkText; Required: False)
  );

  ITEM_FIELDS: array[0..7] of TFieldDef = (
    (Name: 'trip_id';        Kind: fkInt;  Required: True),
    (Name: 'remito';         Kind: fkText; Required: False),
    (Name: 'origin';         Kind: fkText; Required: False),
    (Name: 'destination';    Kind: fkText; Required: False),
    (Name: 'kilos';          Kind: fkNum;  Required: True),
    (Name: 'tariff';         Kind: fkNum;  Required: True),
    (Name: 'vat_pct';        Kind: fkNum;  Required: False),
    (Name: 'commission_pct'; Kind: fkNum;  Required: False)
  );

function MonthStart: string;
begin
  Result := Copy(TodayISO, 1, 7) + '-01';
end;

function TripJson(ATripId, ACompanyId: Integer): string;
begin
  Result := TDB.Q(
    'select json_build_object(' +
    '  ''trip'', (select row_to_json(t) from (select * from v_freight_trips where id = :p0 and company_id = :p1) t),' +
    '  ''items'', (select coalesce(json_agg(row_to_json(i)), ''[]'') from (select * from v_freight_items where trip_id = :p0 order by id) i)' +
    ')', [ATripId, ACompanyId]);
end;

procedure InsertItems(ATripId, ACompanyId: Integer; AItems: TJSONArray; ACommission: Double; out AErr: string);
var
  I, LId: Integer;
  LItem: TJSONValue;
  LObj: TJSONObject;
  LErr: string;
begin
  AErr := '';
  if not Assigned(AItems) then
    Exit;
  for I := 0 to AItems.Count - 1 do
  begin
    LItem := AItems.Items[I];
    if not (LItem is TJSONObject) then
      Continue;
    LObj := TJSONObject(LItem);
    if Has(LObj, 'trip_id') then
      LObj.RemovePair('trip_id').Free;
    LObj.AddPair('trip_id', TJSONNumber.Create(ATripId));
    if not Has(LObj, 'commission_pct') then
      LObj.AddPair('commission_pct', TJSONNumber.Create(ACommission));
    if not Has(LObj, 'vat_pct') then
      LObj.AddPair('vat_pct', TJSONNumber.Create(21));
    if not InsertRow('freight_items', ITEM_FIELDS, LObj, 0, LId, LErr) then
    begin
      AErr := LErr;
      Exit;
    end;
  end;
end;

procedure ListTrips(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LSQL: string;
  LParams: TArray<Variant>;
  LVehicle: Integer;
begin
  LSQL := 'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_freight_trips where company_id = :p0 and trip_date between :p1::date and :p2::date';
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
  LSQL := LSQL + ' order by trip_date desc, id desc) t';
  SendList(Res, LSQL, LParams);
end;

procedure GetTrip(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LId, LCompany: Integer;
begin
  try
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);
    if TDB.QInt('select count(*) from freight_trips where id = :p0 and company_id = :p1',
      [LId, LCompany]) = 0 then
    begin SendError(Res, 'Viaje no encontrado', 404); Exit; end;
    SendJsonText(Res, TripJson(LId, LCompany), 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure CreateTrip(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany, LVehicle: Integer;
  LItems: TJSONValue;
  LCommission: Double;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LVehicle := GetInt(LBody, 'vehicle_id', 0);
    if TDB.QInt('select count(*) from vehicles where id = :p0 and company_id = :p1',
      [LVehicle, LCompany]) = 0 then
    begin SendError(Res, 'Vehículo inválido', 400); Exit; end;
    LCommission := GetNum(LBody, 'commission_pct', 15);

    TDB.BeginTx;
    try
      if not InsertRow('freight_trips', TRIP_FIELDS, LBody, LCompany, LId, LErr) then
      begin
        TDB.RollbackTx;
        SendError(Res, LErr, 400);
        Exit;
      end;
      TDB.Exec('update freight_trips set created_by = :p0 where id = :p1', [GAuth.UserId, LId]);
      LItems := LBody.FindValue('items');
      if Assigned(LItems) and (LItems is TJSONArray) then
      begin
        InsertItems(LId, LCompany, TJSONArray(LItems), LCommission, LErr);
        if not LErr.IsEmpty then
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

    AuditAction('create', 'freight_trip', LId, '{}');
    SendJsonText(Res, TripJson(LId, LCompany), 201);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateTrip(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany: Integer;
  LItems: TJSONValue;
  LCommission: Double;
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
    LCommission := GetNum(LBody, 'commission_pct',
      TDB.QFloat('select commission_pct from freight_trips where id = :p0 and company_id = :p1',
        [LId, LCompany]));

    TDB.BeginTx;
    try
      if not UpdateRow('freight_trips', TRIP_FIELDS, LBody, LId, LCompany, LErr) then
      begin
        TDB.RollbackTx;
        SendError(Res, LErr, 400);
        Exit;
      end;
      LItems := LBody.FindValue('items');
      if Assigned(LItems) and (LItems is TJSONArray) then
      begin
        TDB.Exec('delete from freight_items where trip_id = :p0', [LId]);
        InsertItems(LId, LCompany, TJSONArray(LItems), LCommission, LErr);
        if not LErr.IsEmpty then
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

    AuditAction('update', 'freight_trip', LId, '{}');
    SendJsonText(Res, TripJson(LId, LCompany), 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteTrip(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LErr: string; LId: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  if DeleteRow('freight_trips', 'freight_trip', LId, EffectiveCompany(Req), True, LErr) then
    SendDeleted(Res)
  else
    SendError(Res, LErr, 400);
end;

{ ---------------- ITEMS ---------------- }

procedure ListItems(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LTrip: Integer;
begin
  LTrip := QueryInt(Req, 'trip_id', 0);
  if LTrip <= 0 then
  begin SendError(Res, 'Indique trip_id', 400); Exit; end;
  if TDB.QInt('select count(*) from freight_trips where id = :p0 and company_id = :p1',
    [LTrip, EffectiveCompany(Req)]) = 0 then
  begin SendError(Res, 'Viaje no encontrado', 404); Exit; end;
  SendList(Res,
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (select * from v_freight_items where trip_id = :p0 order by id) t',
    [LTrip]);
end;

procedure CreateItem(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LBody: TJSONObject;
  LErr: string;
  LId, LCompany, LTrip: Integer;
  LCommission: Double;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LCompany := BodyCompany(Req, LBody);
    LTrip := GetInt(LBody, 'trip_id', 0);
    if TDB.QInt('select count(*) from freight_trips where id = :p0 and company_id = :p1',
      [LTrip, LCompany]) = 0 then
    begin SendError(Res, 'Viaje inválido', 400); Exit; end;
    LCommission := TDB.QFloat('select commission_pct from freight_trips where id = :p0', [LTrip]);
    if not Has(LBody, 'commission_pct') then
      LBody.AddPair('commission_pct', TJSONNumber.Create(LCommission));
    if not Has(LBody, 'vat_pct') then
      LBody.AddPair('vat_pct', TJSONNumber.Create(21));
    if not InsertRow('freight_items', ITEM_FIELDS, LBody, 0, LId, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('create', 'freight_item', LId, '{}');
    SendJsonText(Res, TDB.Q('select row_to_json(t) from (select * from v_freight_items where id = :p0) t', [LId]), 201);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure UpdateItem(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LBody: TJSONObject; LErr: string; LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LBody := nil;
  try
    if not ParseBodyObject(Req, LBody, LErr) then begin SendError(Res, LErr, 400); Exit; end;
    LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
    LCompany := EffectiveCompany(Req);
    if TDB.QInt('select count(*) from v_freight_items where id = :p0 and company_id = :p1',
      [LId, LCompany]) = 0 then
    begin SendError(Res, 'Remito no encontrado', 404); Exit; end;
    if Has(LBody, 'trip_id') and
       (TDB.QInt('select count(*) from freight_trips where id = :p0 and company_id = :p1',
         [GetInt(LBody, 'trip_id', 0), LCompany]) = 0) then
    begin SendError(Res, 'Viaje inválido', 400); Exit; end;
    if not UpdateRow('freight_items', ITEM_FIELDS, LBody, LId, 0, LErr) then
    begin SendError(Res, LErr, 400); Exit; end;
    AuditAction('update', 'freight_item', LId, '{}');
    SendSaved(Res, LId);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
  LBody.Free;
end;

procedure DeleteItem(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LId, LCompany: Integer;
begin
  if not RequireWrite(Res) then Exit;
  LId := StrToIntDef(ParamValue(Req, 'id', '0'), 0);
  LCompany := EffectiveCompany(Req);
  if TDB.QInt('select count(*) from v_freight_items where id = :p0 and company_id = :p1',
    [LId, LCompany]) = 0 then
  begin SendError(Res, 'Remito no encontrado', 404); Exit; end;
  if TDB.Exec('delete from freight_items where id = :p0', [LId]) > 0 then
  begin
    AuditAction('delete', 'freight_item', LId, '{}');
    SendDeleted(Res);
  end
  else
    SendError(Res, 'No se pudo eliminar el remito', 400);
end;

procedure RegisterFreightRoutes;
begin
  THorse.Get('/api/freight/trips', ListTrips);
  THorse.Get('/api/freight/trips/:id', GetTrip);
  THorse.Post('/api/freight/trips', CreateTrip);
  THorse.Put('/api/freight/trips/:id', UpdateTrip);
  THorse.Delete('/api/freight/trips/:id', DeleteTrip);

  THorse.Get('/api/freight/items', ListItems);
  THorse.Post('/api/freight/items', CreateItem);
  THorse.Put('/api/freight/items/:id', UpdateItem);
  THorse.Delete('/api/freight/items/:id', DeleteItem);
end;

end.
