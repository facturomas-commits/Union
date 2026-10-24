unit UReportRoutes;

interface

procedure RegisterReportRoutes;

implementation

uses
  System.SysUtils, System.JSON, System.Classes, System.Variants, System.Math, System.StrUtils,
  System.Generics.Collections,
  Horse, UHttp, UAuth, UApi, UDB, ULog, FireDAC.Comp.Client, FireDAC.Stan.Param, Data.DB;

function AlertDays(ACompany: Integer): Integer;
var LValue: string;
begin
  LValue := TDB.Q('select value from settings where company_id = :p0 and key = ''maintenance_alert_days''', [ACompany]);
  Result := StrToIntDef(LValue, 15);
  if Result < 0 then Result := 15;
end;

function JoinSemi(const AValues: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(AValues) do
  begin
    if I > 0 then Result := Result + ';';
    Result := Result + AValues[I];
  end;
end;

function BuildConsolidated(ATotals, AFreight: TJSONObject; AMaintTotal, AGeneralTotal: Double): TJSONObject;
var
  LBusRevenue, LBusFuel, LBusDed, LBusSurplus, LBusKm, LBusLiters, LBusTickets: Double;
  LFreightNet, LFreightVat, LFreightTotal, LFreightCommission, LFreightKm: Double;
  LTotalCosts, LTotalIncomeNet: Double;
  LOnc, LTick, LMp, LOth: Double;
begin
  LBusRevenue := ATotals.GetValue<Double>('revenue', 0);
  LBusFuel := ATotals.GetValue<Double>('fuel_amount', 0);
  LBusSurplus := ATotals.GetValue<Double>('surplus', 0);
  LBusKm := ATotals.GetValue<Double>('km', 0);
  LBusLiters := ATotals.GetValue<Double>('fuel_liters', 0);
  LBusTickets := ATotals.GetValue<Double>('tickets', 0);
  LOnc := ATotals.GetValue<Double>('oncology_amount', 0);
  LTick := ATotals.GetValue<Double>('ticket_office_amount', 0);
  LMp := ATotals.GetValue<Double>('mp_amount', 0);
  LOth := ATotals.GetValue<Double>('other_amount', 0);
  LBusDed := LOnc + LTick + LMp + LOth;

  LFreightNet := AFreight.GetValue<Double>('net_amount', 0);
  LFreightVat := AFreight.GetValue<Double>('vat_amount', 0);
  LFreightTotal := AFreight.GetValue<Double>('total_amount', 0);
  LFreightCommission := AFreight.GetValue<Double>('driver_commission', 0);
  LFreightKm := AFreight.GetValue<Double>('km', 0);

  LTotalIncomeNet := LBusRevenue + LFreightNet;
  LTotalCosts := LBusFuel + LBusDed + LFreightCommission + AMaintTotal + AGeneralTotal;

  Result := TJSONObject.Create;
  Result.AddPair('bus_revenue', TJSONNumber.Create(LBusRevenue));
  Result.AddPair('bus_fuel', TJSONNumber.Create(LBusFuel));
  Result.AddPair('bus_deductions', TJSONNumber.Create(LBusDed));
  Result.AddPair('bus_surplus', TJSONNumber.Create(LBusSurplus));
  Result.AddPair('bus_km', TJSONNumber.Create(LBusKm));
  Result.AddPair('bus_liters', TJSONNumber.Create(LBusLiters));
  Result.AddPair('bus_tickets', TJSONNumber.Create(LBusTickets));
  if LBusLiters > 0 then
    Result.AddPair('bus_km_per_liter', TJSONNumber.Create(LBusKm / LBusLiters))
  else
    Result.AddPair('bus_km_per_liter', TJSONNumber.Create(0));
  if LBusKm > 0 then
    Result.AddPair('bus_cost_per_km', TJSONNumber.Create((LBusFuel + LBusDed) / LBusKm))
  else
    Result.AddPair('bus_cost_per_km', TJSONNumber.Create(0));

  Result.AddPair('freight_net', TJSONNumber.Create(LFreightNet));
  Result.AddPair('freight_vat', TJSONNumber.Create(LFreightVat));
  Result.AddPair('freight_total', TJSONNumber.Create(LFreightTotal));
  Result.AddPair('freight_commission', TJSONNumber.Create(LFreightCommission));
  Result.AddPair('freight_km', TJSONNumber.Create(LFreightKm));
  Result.AddPair('freight_trips', TJSONNumber.Create(AFreight.GetValue<Integer>('trips', 0)));
  Result.AddPair('freight_kilos', TJSONNumber.Create(AFreight.GetValue<Double>('kilos', 0)));

  Result.AddPair('maintenance', TJSONNumber.Create(AMaintTotal));
  Result.AddPair('general_expenses', TJSONNumber.Create(AGeneralTotal));
  Result.AddPair('total_income_net', TJSONNumber.Create(LTotalIncomeNet));
  Result.AddPair('total_income_gross', TJSONNumber.Create(LBusRevenue + LFreightTotal));
  Result.AddPair('total_costs', TJSONNumber.Create(LTotalCosts));
  Result.AddPair('margin', TJSONNumber.Create(LTotalIncomeNet - LTotalCosts));
  Result.AddPair('total_km', TJSONNumber.Create(LBusKm + LFreightKm));
end;

function BuildDailyObject(ACompany: Integer; const ADate: string): TJSONObject;
var
  LServices, LTotals, LFreight, LFreightTotals, LMaint, LAlerts, LGeneral: string;
  LMaintTotal, LGeneralTotal: Double;
  LDays: Integer;
begin
  LDays := AlertDays(ACompany);

  LServices := TDB.Q(
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_services where company_id = :p0 and service_date = :p1::date ' +
    'order by departure_time, id) t', [ACompany, ADate]);

  LTotals := TDB.Q(
    'select row_to_json(t) from (select ' +
    ' count(*) as services,' +
    ' coalesce(sum(revenue),0) as revenue,' +
    ' coalesce(sum(fuel_amount),0) as fuel_amount,' +
    ' coalesce(sum(fuel_liters),0) as fuel_liters,' +
    ' coalesce(sum(oncology_amount),0) as oncology_amount,' +
    ' coalesce(sum(ticket_office_amount),0) as ticket_office_amount,' +
    ' coalesce(sum(mp_amount),0) as mp_amount,' +
    ' coalesce(sum(other_amount),0) as other_amount,' +
    ' coalesce(sum(surplus),0) as surplus,' +
    ' coalesce(sum(km),0) as km,' +
    ' coalesce(sum(tickets_count),0) as tickets,' +
    ' coalesce(sum(case when status = ''open'' then 1 else 0 end),0) as open_services ' +
    'from v_services where company_id = :p0 and service_date = :p1::date) t',
    [ACompany, ADate]);

  LFreight := TDB.Q(
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_freight_trips where company_id = :p0 and trip_date = :p1::date ' +
    'order by id) t', [ACompany, ADate]);

  LFreightTotals := TDB.Q(
    'select row_to_json(t) from (select ' +
    ' count(*) as trips,' +
    ' coalesce(sum(kilos),0) as kilos,' +
    ' coalesce(sum(net_amount),0) as net_amount,' +
    ' coalesce(sum(vat_amount),0) as vat_amount,' +
    ' coalesce(sum(total_amount),0) as total_amount,' +
    ' coalesce(sum(driver_commission),0) as driver_commission,' +
    ' coalesce(sum(km),0) as km ' +
    'from v_freight_trips where company_id = :p0 and trip_date = :p1::date) t',
    [ACompany, ADate]);

  LMaint := TDB.Q(
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_maintenance where company_id = :p0 and maintenance_date = :p1::date ' +
    'order by id) t', [ACompany, ADate]);

  LMaintTotal := TDB.QFloat(
    'select coalesce(sum(cost),0) from maintenance where company_id = :p0 and maintenance_date = :p1::date',
    [ACompany, ADate]);

  LGeneral := TDB.Q(
    'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
    'select * from v_expenses where company_id = :p0 and expense_date = :p1::date ' +
    'and service_id is null order by id) t', [ACompany, ADate]);

  LGeneralTotal := TDB.QFloat(
    'select coalesce(sum(amount),0) from service_expenses where company_id = :p0 ' +
    'and expense_date = :p1::date and service_id is null', [ACompany, ADate]);

  LAlerts := TDB.Q(
    'select coalesce(json_agg(row_to_json(a)), ''[]'') from (' +
    '  select ''maintenance'' as kind, m.id, m.vehicle_no as reference,' +
    '         m.concept as message, m.next_due as due_date, m.days_left' +
    '    from v_maintenance m' +
    '   where m.company_id = :p0 and m.next_due is not null' +
    '     and m.next_due <= current_date + :p1::int' +
    '  union all' +
    '  select ''negative_surplus'' as kind, s.id, s.vehicle_no as reference,' +
    '         ''Servicio con sobrante negativo'' as message, s.service_date as due_date, 0 as days_left' +
    '    from v_services s' +
    '   where s.company_id = :p0 and s.service_date = :p2::date and s.surplus < 0' +
    '  union all' +
    '  select ''open_service'' as kind, s.id, s.vehicle_no as reference,' +
    '         ''Servicio sin cerrar'' as message, s.service_date as due_date, 0 as days_left' +
    '    from v_services s' +
    '   where s.company_id = :p0 and s.service_date = :p2::date and s.status = ''open''' +
    ') a', [ACompany, LDays, ADate]);

  Result := TJSONObject.Create;
  Result.AddPair('date', ADate);
  Result.AddPair('services', JsonArrayOrEmpty(LServices));
  Result.AddPair('totals', JsonObjectOrEmpty(LTotals));
  Result.AddPair('freight', JsonArrayOrEmpty(LFreight));
  Result.AddPair('freight_totals', JsonObjectOrEmpty(LFreightTotals));
  Result.AddPair('maintenance', JsonArrayOrEmpty(LMaint));
  Result.AddPair('maintenance_total', TJSONNumber.Create(LMaintTotal));
  Result.AddPair('general_expenses', JsonArrayOrEmpty(LGeneral));
  Result.AddPair('general_total', TJSONNumber.Create(LGeneralTotal));
  Result.AddPair('alerts', JsonArrayOrEmpty(LAlerts));
  Result.AddPair('consolidated', BuildConsolidated(
    TJSONObject(Result.FindValue('totals')),
    TJSONObject(Result.FindValue('freight_totals')),
    LMaintTotal, LGeneralTotal));
end;

procedure DailyHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LDate: string;
  LObj: TJSONObject;
begin
  try
    LDate := QueryValue(Req, 'date', TodayISO);
    if not IsISODate(LDate) then
    begin SendError(Res, 'Fecha inválida (YYYY-MM-DD)', 400); Exit; end;
    LObj := BuildDailyObject(EffectiveCompany(Req), LDate);
    try
      SendJsonText(Res, LObj.ToJSON, 200);
    finally
      LObj.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure DashboardHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LDate, LSeries, LRecent: string;
  LCompany: Integer;
  LObj: TJSONObject;
begin
  try
    LDate := QueryValue(Req, 'date', TodayISO);
    if not IsISODate(LDate) then
    begin SendError(Res, 'Fecha inválida (YYYY-MM-DD)', 400); Exit; end;
    LCompany := EffectiveCompany(Req);

    LSeries := TDB.Q(
      'with days as (select generate_series(:p1::date - 6, :p1::date, interval ''1 day'')::date as d),' +
      ' svc as (select service_date, sum(revenue) revenue, sum(surplus) surplus, sum(fuel_amount) fuel,' +
      '                sum(km) km, sum(tickets_count) tickets' +
      '           from v_services where company_id = :p0 and service_date between :p1::date - 6 and :p1::date' +
      '          group by service_date),' +
      ' fr as (select trip_date, sum(net_amount) net, sum(total_amount) total, sum(driver_commission) commission' +
      '          from v_freight_trips where company_id = :p0 and trip_date between :p1::date - 6 and :p1::date' +
      '         group by trip_date)' +
      'select coalesce(json_agg(json_build_object(' +
      '  ''date'', to_char(d.d, ''YYYY-MM-DD''),' +
      '  ''revenue'', coalesce(s.revenue,0),' +
      '  ''surplus'', coalesce(s.surplus,0),' +
      '  ''fuel'', coalesce(s.fuel,0),' +
      '  ''km'', coalesce(s.km,0),' +
      '  ''tickets'', coalesce(s.tickets,0),' +
      '  ''freight_net'', coalesce(f.net,0),' +
      '  ''freight_total'', coalesce(f.total,0),' +
      '  ''freight_commission'', coalesce(f.commission,0)' +
      ') order by d.d), ''[]'')' +
      'from days d left join svc s on s.service_date = d.d left join fr f on f.trip_date = d.d',
      [LCompany, LDate]);

    LRecent := TDB.Q(
      'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      'select id, username, action, entity, entity_id, created_at from audit_log ' +
      'where company_id = :p0 order by created_at desc limit 10) t', [LCompany]);

    LObj := BuildDailyObject(LCompany, LDate);
    try
      LObj.AddPair('series', JsonArrayOrEmpty(LSeries));
      LObj.AddPair('recent', JsonArrayOrEmpty(LRecent));
      SendJsonText(Res, LObj.ToJSON, 200);
    finally
      LObj.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure MonthlyHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LMonth, LDaysJson, LVehicles, LDrivers, LTotals, LFreightTotals: string;
  LCompany: Integer;
  LObj: TJSONObject;
  LMonthStart: string;
  LGeneralTotal: Double;
begin
  try
    LMonth := QueryValue(Req, 'month', MonthISO);
    if not IsISOMonth(LMonth) then
    begin SendError(Res, 'Mes inválido (YYYY-MM)', 400); Exit; end;
    LCompany := EffectiveCompany(Req);
    LMonthStart := LMonth + '-01';

    LDaysJson := TDB.Q(
      'with days as (select generate_series(:p1::date, (:p1::date + interval ''1 month - 1 day'')::date, interval ''1 day'')::date as d),' +
      ' svc as (select service_date, sum(revenue) revenue, sum(surplus) surplus, sum(fuel_amount) fuel,' +
      '                sum(fuel_liters) liters, sum(km) km, sum(tickets_count) tickets' +
      '           from v_services where company_id = :p0' +
      '            and service_date >= :p1::date and service_date < (:p1::date + interval ''1 month'')' +
      '          group by service_date),' +
      ' fr as (select trip_date, sum(net_amount) net, sum(total_amount) total, sum(driver_commission) commission' +
      '          from v_freight_trips where company_id = :p0' +
      '           and trip_date >= :p1::date and trip_date < (:p1::date + interval ''1 month'')' +
      '         group by trip_date),' +
      ' mt as (select maintenance_date, sum(cost) cost from maintenance where company_id = :p0' +
      '          and maintenance_date >= :p1::date and maintenance_date < (:p1::date + interval ''1 month'')' +
      '         group by maintenance_date),' +
      ' gen as (select expense_date, sum(amount) amount from service_expenses where company_id = :p0' +
      '          and service_id is null and expense_date >= :p1::date' +
      '          and expense_date < (:p1::date + interval ''1 month'') group by expense_date)' +
      'select coalesce(json_agg(row_to_json(x) order by x.date), ''[]'') from (' +
      '  select to_char(d.d, ''YYYY-MM-DD'') as date, coalesce(s.revenue,0) revenue,' +
      '         coalesce(s.fuel,0) fuel, coalesce(s.surplus,0) surplus, coalesce(s.liters,0) liters,' +
      '         coalesce(s.km,0) km, coalesce(s.tickets,0) tickets,' +
      '         coalesce(f.net,0) freight_net, coalesce(f.total,0) freight_total,' +
      '         coalesce(f.commission,0) freight_commission, coalesce(mt.cost,0) maintenance,' +
      '         coalesce(g.amount,0) general' +
      '    from days d left join svc s on s.service_date = d.d' +
      '    left join fr f on f.trip_date = d.d left join mt on mt.maintenance_date = d.d' +
      '    left join gen g on g.expense_date = d.d' +
      ') x', [LCompany, LMonthStart]);

    LVehicles := TDB.Q(
      'select coalesce(json_agg(row_to_json(t) order by t.vehicle_no), ''[]'') from (' +
      'select vehicle_no, count(*) services, sum(revenue) revenue, sum(fuel_amount) fuel,' +
      '       sum(surplus) surplus, sum(km) km, sum(tickets_count) tickets, sum(fuel_liters) liters' +
      '  from v_services where company_id = :p0' +
      '   and service_date >= :p1::date and service_date < (:p1::date + interval ''1 month'')' +
      ' group by vehicle_no) t', [LCompany, LMonthStart]);

    LDrivers := TDB.Q(
      'select coalesce(json_agg(row_to_json(t) order by t.driver_name), ''[]'') from (' +
      'select driver_name, count(*) services, sum(revenue) revenue, sum(surplus) surplus, sum(km) km' +
      '  from v_services where company_id = :p0 and driver_id is not null' +
      '   and service_date >= :p1::date and service_date < (:p1::date + interval ''1 month'')' +
      ' group by driver_name) t', [LCompany, LMonthStart]);

    LTotals := TDB.Q(
      'select row_to_json(t) from (select count(*) services, coalesce(sum(revenue),0) revenue,' +
      ' coalesce(sum(fuel_amount),0) fuel_amount, coalesce(sum(fuel_liters),0) fuel_liters,' +
      ' coalesce(sum(oncology_amount),0) oncology_amount, coalesce(sum(ticket_office_amount),0) ticket_office_amount,' +
      ' coalesce(sum(mp_amount),0) mp_amount, coalesce(sum(other_amount),0) other_amount,' +
      ' coalesce(sum(surplus),0) surplus, coalesce(sum(km),0) km, coalesce(sum(tickets_count),0) tickets' +
      ' from v_services where company_id = :p0 and service_date >= :p1::date' +
      '  and service_date < (:p1::date + interval ''1 month'')) t', [LCompany, LMonthStart]);

    LFreightTotals := TDB.Q(
      'select row_to_json(t) from (select count(*) trips, coalesce(sum(kilos),0) kilos,' +
      ' coalesce(sum(net_amount),0) net_amount, coalesce(sum(vat_amount),0) vat_amount,' +
      ' coalesce(sum(total_amount),0) total_amount, coalesce(sum(driver_commission),0) driver_commission,' +
      ' coalesce(sum(km),0) km from v_freight_trips where company_id = :p0 and trip_date >= :p1::date' +
      '  and trip_date < (:p1::date + interval ''1 month'')) t', [LCompany, LMonthStart]);

    LGeneralTotal := TDB.QFloat(
      'select coalesce(sum(amount),0) from service_expenses where company_id = :p0' +
      ' and service_id is null and expense_date >= :p1::date' +
      ' and expense_date < (:p1::date + interval ''1 month'')', [LCompany, LMonthStart]);

    LObj := TJSONObject.Create;
    try
      LObj.AddPair('month', LMonth);
      LObj.AddPair('days', JsonArrayOrEmpty(LDaysJson));
      LObj.AddPair('vehicles', JsonArrayOrEmpty(LVehicles));
      LObj.AddPair('drivers', JsonArrayOrEmpty(LDrivers));
      LObj.AddPair('totals', JsonObjectOrEmpty(LTotals));
      LObj.AddPair('freight_totals', JsonObjectOrEmpty(LFreightTotals));
      LObj.AddPair('general_total', TJSONNumber.Create(LGeneralTotal));
      LObj.AddPair('consolidated', BuildConsolidated(
        TJSONObject(LObj.FindValue('totals')),
        TJSONObject(LObj.FindValue('freight_totals')),
        TDB.QFloat('select coalesce(sum(cost),0) from maintenance where company_id = :p0' +
          ' and maintenance_date >= :p1::date and maintenance_date < (:p1::date + interval ''1 month'')',
          [LCompany, LMonthStart]), LGeneralTotal));
      SendJsonText(Res, LObj.ToJSON, 200);
    finally
      LObj.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure MaintenanceDueHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LCompany, LDays: Integer;
  LJson: string;
begin
  try
    LCompany := EffectiveCompany(Req);
    LDays := QueryInt(Req, 'days', AlertDays(LCompany));
    LJson := TDB.Q(
      'select json_build_object(''days'', :p1::int, ''items'', (' +
      ' select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      '  select * from v_maintenance where company_id = :p0 and next_due is not null' +
      '   and next_due <= current_date + :p1::int order by next_due) t))',
      [LCompany, LDays]);
    SendJsonText(Res, LJson, 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure LatestHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LCompany: Integer;
begin
  try
    LCompany := EffectiveCompany(Req);
    SendJsonText(Res, TDB.Q(
      'select json_build_object(' +
      '  ''service_date'', (select max(service_date)::text from services where company_id = :p0),' +
      '  ''freight_date'', (select max(trip_date)::text from freight_trips where company_id = :p0),' +
      '  ''today'', current_date::text)', [LCompany]), 200);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure AuditHandler(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var LCompany, LLimit: Integer;
begin
  if not RequireAdmin(Res) then Exit;
  try
    LCompany := EffectiveCompany(Req);
    LLimit := QueryInt(Req, 'limit', 200);
    if LLimit < 1 then LLimit := 1;
    if LLimit > 1000 then LLimit := 1000;
    SendList(Res,
      'select coalesce(json_agg(row_to_json(t)), ''[]'') from (' +
      'select * from audit_log where company_id = :p0 order by created_at desc limit :p1) t',
      [LCompany, LLimit]);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure ExportDailyCsv(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LCompany: Integer;
  LDate: string;
  LQry: TFDQuery;
  LSB: TStringBuilder;
  LTotalRevenue, LTotalFuel, LTotalDed, LTotalSurplus: Double;
  LTotalLiters, LTotalOnc, LTotalTick, LTotalMp, LTotalOther, LTotalKm: Double;
  LFreightNet, LFreightTotal, LFreightCommission, LFreightKilos, LFreightKmCsv: Double;
  LTruckItems: Integer;
begin
  try
    LDate := QueryValue(Req, 'date', TodayISO);
    if not IsISODate(LDate) then begin SendError(Res, 'Fecha inválida', 400); Exit; end;
    LCompany := EffectiveCompany(Req);

    LSB := TStringBuilder.Create;
    LQry := TFDQuery.Create(nil);
    try
      LQry.Connection := TDB.Conn;
      LQry.SQL.Text :=
        'select service_date, departure_time, schedule_label, vehicle_no, driver_name, guard_name,' +
        ' ticket_from, ticket_to, tickets_count, revenue, fuel_amount, fuel_liters,' +
        ' oncology_amount, ticket_office_amount, mp_amount, other_amount, surplus, km, status' +
        ' from v_services where company_id = :p0 and service_date = :p1::date order by departure_time';
      LQry.ParamByName('p0').AsInteger := LCompany;
      LQry.ParamByName('p1').AsString := LDate;
      LQry.Open;

      LSB.AppendLine('REPORTE DIARIO - COLECTIVOS');
      LSB.AppendLine('Fecha;' + LDate);
      LSB.AppendLine('Horario;Coche;Chofer;Guarda;Boleto desde;Boleto hasta;Cantidad;' +
        'Recaudación;Gasoil $;Gasoil L;Oncológico;Boleterías;MP;Otros;Sobró;Km;Estado');

      LTotalRevenue := 0; LTotalFuel := 0; LTotalDed := 0; LTotalSurplus := 0;
      LTotalLiters := 0; LTotalOnc := 0; LTotalTick := 0; LTotalMp := 0; LTotalOther := 0; LTotalKm := 0;
      while not LQry.Eof do
      begin
        LSB.Append(CsvEscape(FormatDateTime('hh:nn', LQry.FieldByName('departure_time').AsDateTime))).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('vehicle_no').AsString)).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('driver_name').AsString)).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('guard_name').AsString)).Append(';');
        LSB.Append(LQry.FieldByName('ticket_from').AsString).Append(';');
        LSB.Append(LQry.FieldByName('ticket_to').AsString).Append(';');
        LSB.Append(LQry.FieldByName('tickets_count').AsString).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('revenue').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('fuel_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('fuel_liters').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('oncology_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('ticket_office_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('mp_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('other_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('surplus').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('km').AsFloat)).Append(';');
        LSB.AppendLine(CsvEscape(IfThen(LQry.FieldByName('status').AsString = 'closed', 'Cerrado', 'Abierto')));

        LTotalRevenue := LTotalRevenue + LQry.FieldByName('revenue').AsFloat;
        LTotalFuel := LTotalFuel + LQry.FieldByName('fuel_amount').AsFloat;
        LTotalLiters := LTotalLiters + LQry.FieldByName('fuel_liters').AsFloat;
        LTotalOnc := LTotalOnc + LQry.FieldByName('oncology_amount').AsFloat;
        LTotalTick := LTotalTick + LQry.FieldByName('ticket_office_amount').AsFloat;
        LTotalMp := LTotalMp + LQry.FieldByName('mp_amount').AsFloat;
        LTotalOther := LTotalOther + LQry.FieldByName('other_amount').AsFloat;
        LTotalDed := LTotalDed + LQry.FieldByName('oncology_amount').AsFloat +
          LQry.FieldByName('ticket_office_amount').AsFloat +
          LQry.FieldByName('mp_amount').AsFloat + LQry.FieldByName('other_amount').AsFloat;
        LTotalSurplus := LTotalSurplus + LQry.FieldByName('surplus').AsFloat;
        LTotalKm := LTotalKm + LQry.FieldByName('km').AsFloat;
        LQry.Next;
      end;

      LSB.AppendLine(JoinSemi([
        'TOTALES', '', '', '', '', '', '',
        CsvNumber(LTotalRevenue), CsvNumber(LTotalFuel), CsvNumber(LTotalLiters),
        CsvNumber(LTotalOnc), CsvNumber(LTotalTick), CsvNumber(LTotalMp),
        CsvNumber(LTotalOther), CsvNumber(LTotalSurplus), CsvNumber(LTotalKm), ''
      ]));
      LSB.AppendLine;

      LQry.Close;
      LQry.SQL.Text :=
        'select id, trip_date, vehicle_no, driver_name, items_count, kilos, net_amount, vat_amount,' +
        ' total_amount, driver_commission, km from v_freight_trips' +
        ' where company_id = :p0 and trip_date = :p1::date order by id';
      LQry.ParamByName('p0').AsInteger := LCompany;
      LQry.ParamByName('p1').AsString := LDate;
      LQry.Open;

      LSB.AppendLine('REPORTE DIARIO - CAMIÓN');
      LSB.AppendLine('Viaje;Coche;Chofer;Remitos;Kilos;Neto;IVA;Total;Comisión;Km');
      LFreightNet := 0; LFreightTotal := 0; LFreightCommission := 0;
      LFreightKilos := 0; LFreightKmCsv := 0; LTruckItems := 0;
      while not LQry.Eof do
      begin
        LSB.Append(LQry.FieldByName('id').AsString).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('vehicle_no').AsString)).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('driver_name').AsString)).Append(';');
        LSB.Append(LQry.FieldByName('items_count').AsString).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('kilos').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('net_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('vat_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('total_amount').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('driver_commission').AsFloat)).Append(';');
        LSB.AppendLine(CsvNumber(LQry.FieldByName('km').AsFloat));
        LFreightNet := LFreightNet + LQry.FieldByName('net_amount').AsFloat;
        LFreightTotal := LFreightTotal + LQry.FieldByName('total_amount').AsFloat;
        LFreightCommission := LFreightCommission + LQry.FieldByName('driver_commission').AsFloat;
        LFreightKilos := LFreightKilos + LQry.FieldByName('kilos').AsFloat;
        LFreightKmCsv := LFreightKmCsv + LQry.FieldByName('km').AsFloat;
        LTruckItems := LTruckItems + LQry.FieldByName('items_count').AsInteger;
        LQry.Next;
      end;
      LSB.AppendLine(JoinSemi([
        'TOTALES', '', '', IntToStr(LTruckItems), CsvNumber(LFreightKilos),
        CsvNumber(LFreightNet), '', CsvNumber(LFreightTotal),
        CsvNumber(LFreightCommission), CsvNumber(LFreightKmCsv)
      ]));
      LSB.AppendLine;

      LQry.Close;
      LQry.SQL.Text :=
        'select category, description, vehicle_no, amount from v_expenses' +
        ' where company_id = :p0 and expense_date = :p1::date and service_id is null order by id';
      LQry.ParamByName('p0').AsInteger := LCompany;
      LQry.ParamByName('p1').AsString := LDate;
      LQry.Open;
      LSB.AppendLine('GASTOS GENERALES DEL DÍA');
      LSB.AppendLine('Categoría;Concepto;Vehículo;Importe');
      while not LQry.Eof do
      begin
        LSB.Append(CsvEscape(LQry.FieldByName('category').AsString)).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('description').AsString)).Append(';');
        LSB.Append(CsvEscape(LQry.FieldByName('vehicle_no').AsString)).Append(';');
        LSB.AppendLine(CsvNumber(LQry.FieldByName('amount').AsFloat));
        LQry.Next;
      end;

      SendCsv(Res, 'reporte-diario-' + LDate + '.csv', LSB.ToString);
    finally
      LQry.Free;
      LSB.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure ExportMonthlyCsv(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LCompany: Integer;
  LMonth: string;
  LQry: TFDQuery;
  LSB: TStringBuilder;
begin
  try
    LMonth := QueryValue(Req, 'month', MonthISO);
    if not IsISOMonth(LMonth) then begin SendError(Res, 'Mes inválido', 400); Exit; end;
    LCompany := EffectiveCompany(Req);
    LSB := TStringBuilder.Create;
    LQry := TFDQuery.Create(nil);
    try
      LQry.Connection := TDB.Conn;
      LQry.SQL.Text :=
        'select service_date, count(*) services, sum(revenue) revenue, sum(fuel_amount) fuel,' +
        ' sum(oncology_amount + ticket_office_amount + mp_amount + other_amount) deductions,' +
        ' sum(surplus) surplus, sum(km) km, sum(tickets_count) tickets' +
        ' from v_services where company_id = :p0 and service_date >= :p1::date' +
        ' and service_date < (:p1::date + interval ''1 month'') group by service_date order by service_date';
      LQry.ParamByName('p0').AsInteger := LCompany;
      LQry.ParamByName('p1').AsString := LMonth + '-01';
      LQry.Open;
      LSB.AppendLine('REPORTE MENSUAL - COLECTIVOS');
      LSB.AppendLine('Mes;' + LMonth);
      LSB.AppendLine('Fecha;Servicios;Recaudación;Gasoil;Deducciones;Sobró;Km;Boletos');
      while not LQry.Eof do
      begin
        LSB.Append(CsvDate(LQry.FieldByName('service_date').AsDateTime)).Append(';');
        LSB.Append(LQry.FieldByName('services').AsString).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('revenue').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('fuel').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('deductions').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('surplus').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('km').AsFloat)).Append(';');
        LSB.AppendLine(LQry.FieldByName('tickets').AsString);
        LQry.Next;
      end;
      LSB.AppendLine;

      LQry.Close;
      LQry.SQL.Text :=
        'select trip_date, count(*) trips, sum(kilos) kilos, sum(net_amount) net,' +
        ' sum(vat_amount) vat, sum(total_amount) total, sum(driver_commission) commission, sum(km) km' +
        ' from v_freight_trips where company_id = :p0 and trip_date >= :p1::date' +
        ' and trip_date < (:p1::date + interval ''1 month'') group by trip_date order by trip_date';
      LQry.ParamByName('p0').AsInteger := LCompany;
      LQry.ParamByName('p1').AsString := LMonth + '-01';
      LQry.Open;
      LSB.AppendLine('REPORTE MENSUAL - CAMIÓN');
      LSB.AppendLine('Fecha;Viajes;Kilos;Neto;IVA;Total;Comisión;Km');
      while not LQry.Eof do
      begin
        LSB.Append(CsvDate(LQry.FieldByName('trip_date').AsDateTime)).Append(';');
        LSB.Append(LQry.FieldByName('trips').AsString).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('kilos').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('net').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('vat').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('total').AsFloat)).Append(';');
        LSB.Append(CsvNumber(LQry.FieldByName('commission').AsFloat)).Append(';');
        LSB.AppendLine(CsvNumber(LQry.FieldByName('km').AsFloat));
        LQry.Next;
      end;
      SendCsv(Res, 'reporte-mensual-' + LMonth + '.csv', LSB.ToString);
    finally
      LQry.Free;
      LSB.Free;
    end;
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure RegisterReportRoutes;
begin
  THorse.Get('/api/reports/daily', DailyHandler);
  THorse.Get('/api/reports/monthly', MonthlyHandler);
  THorse.Get('/api/reports/maintenance-due', MaintenanceDueHandler);
  THorse.Get('/api/reports/latest', LatestHandler);
  THorse.Get('/api/reports/audit', AuditHandler);
  THorse.Get('/api/reports/export/daily.csv', ExportDailyCsv);
  THorse.Get('/api/reports/export/monthly.csv', ExportMonthlyCsv);
  THorse.Get('/api/dashboard', DashboardHandler);
end;

end.
