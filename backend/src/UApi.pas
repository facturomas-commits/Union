unit UApi;

interface

uses
  System.SysUtils, System.JSON, System.Classes,
  Horse, UHttp, UAuth;

type
  TFieldKind = (fkText, fkInt, fkNum, fkBool, fkDate, fkTime);

  TFieldDef = record
    Name: string;
    Kind: TFieldKind;
    Required: Boolean;
  end;

function InsertRow(const ATable: string; const AFields: array of TFieldDef;
  AObj: TJSONObject; ACompanyId: Integer; out AId: Integer; out AErr: string): Boolean;
function UpdateRow(const ATable: string; const AFields: array of TFieldDef;
  AObj: TJSONObject; AId, ACompanyId: Integer; out AErr: string): Boolean;
function DeleteRow(const ATable, AEntity: string; AId, ACompanyId: Integer;
  AHard: Boolean; out AErr: string): Boolean;

procedure SendList(Res: THorseResponse; const ASQL: string; const AParams: array of Variant);
procedure SendEntity(Res: THorseResponse; const AView: string; AId, ACompanyId: Integer);
procedure SendCreated(Res: THorseResponse; AId: Integer);
procedure SendSaved(Res: THorseResponse; AId: Integer);
procedure SendDeleted(Res: THorseResponse);

function CsvEscape(const AValue: string): string;
function CsvNumber(AValue: Double): string;
function CsvDate(AValue: TDateTime): string;
procedure SendCsv(Res: THorseResponse; const AFileName, AContent: string);

function IsoDate(AValue: TDateTime): string;

implementation

uses
  System.Variants, System.Math, UDB, ULog;

function JoinList(AList: TStrings; const ASep: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to AList.Count - 1 do
  begin
    if I > 0 then
      Result := Result + ASep;
    Result := Result + AList[I];
  end;
end;

function FieldToVariant(AObj: TJSONObject; const AField: TFieldDef;
  out AValue: Variant; out AErr: string): Boolean;
var
  LText: string;
begin
  AValue := Unassigned;
  AErr := '';
  Result := False;

  if not Has(AObj, AField.Name) then
  begin
    if AField.Required then
    begin
      AErr := 'Falta el campo obligatorio: ' + AField.Name;
      Exit;
    end;
    Exit;
  end;

  if IsNullValue(AObj, AField.Name) then
  begin
    if AField.Required then
    begin
      AErr := 'El campo no puede ser nulo: ' + AField.Name;
      Exit;
    end;
    AValue := Null;
    Exit(True);
  end;

  case AField.Kind of
    fkText:
      begin
        LText := GetStr(AObj, AField.Name);
        if AField.Required and LText.Trim.IsEmpty then
        begin
          AErr := 'El campo no puede estar vacío: ' + AField.Name;
          Exit;
        end;
        AValue := LText;
      end;
    fkInt:
      AValue := GetInt(AObj, AField.Name);
    fkNum:
      AValue := GetNum(AObj, AField.Name);
    fkBool:
      AValue := GetBool(AObj, AField.Name);
    fkDate:
      begin
        LText := GetStr(AObj, AField.Name);
        if LText.Trim.IsEmpty then
        begin
          if AField.Required then
          begin
            AErr := 'Fecha obligatoria: ' + AField.Name;
            Exit;
          end;
          AValue := Null;
        end
        else
        begin
          if not IsISODate(LText) then
          begin
            AErr := 'Fecha inválida (use YYYY-MM-DD): ' + AField.Name;
            Exit;
          end;
          AValue := LText;
        end;
      end;
    fkTime:
      begin
        LText := GetStr(AObj, AField.Name);
        if LText.Trim.IsEmpty then
          AValue := Null
        else
          AValue := Copy(LText, 1, 8);
      end;
  end;

  Result := True;
end;

function Placeholder(const AField: TFieldDef; AIndex: Integer): string;
begin
  case AField.Kind of
    fkDate: Result := ':p' + IntToStr(AIndex) + '::date';
    fkTime: Result := ':p' + IntToStr(AIndex) + '::time';
  else
    Result := ':p' + IntToStr(AIndex);
  end;
end;

function InsertRow(const ATable: string; const AFields: array of TFieldDef;
  AObj: TJSONObject; ACompanyId: Integer; out AId: Integer; out AErr: string): Boolean;
var
  I: Integer;
  LCols, LPlace: TStringList;
  LParams: TArray<Variant>;
  LValue: Variant;
  LErr: string;
  LSQL: string;
begin
  AId := 0;
  AErr := '';
  LCols := TStringList.Create;
  LPlace := TStringList.Create;
  try
    try
      if ACompanyId > 0 then
      begin
        SetLength(LParams, 1);
        LParams[0] := ACompanyId;
        LCols.Add('company_id');
        LPlace.Add(':p0');
      end;

      for I := 0 to High(AFields) do
      begin
        if not FieldToVariant(AObj, AFields[I], LValue, LErr) then
        begin
          if not LErr.IsEmpty then
          begin
            AErr := LErr;
            Exit(False);
          end;
          Continue;
        end;
        LCols.Add(AFields[I].Name);
        if VarIsNull(LValue) then
          LPlace.Add('NULL')
        else
        begin
          LPlace.Add(Placeholder(AFields[I], Length(LParams)));
          SetLength(LParams, Length(LParams) + 1);
          LParams[High(LParams)] := LValue;
        end;
      end;

      if LCols.Count = 0 then
      begin
        AErr := 'No se recibieron datos para insertar';
        Exit(False);
      end;

      LSQL := 'insert into ' + ATable + ' (' + JoinList(LCols, ', ') + ') values (' +
        JoinList(LPlace, ', ') + ') returning id';
      AId := TDB.ExecRetId(LSQL, LParams);
      if AId <= 0 then
      begin
        AErr := 'No se pudo crear el registro';
        Exit(False);
      end;
      Result := True;
    except
      on E: Exception do
      begin
        AErr := E.Message;
        Result := False;
      end;
    end;
  finally
    LCols.Free;
    LPlace.Free;
  end;
end;

function UpdateRow(const ATable: string; const AFields: array of TFieldDef;
  AObj: TJSONObject; AId, ACompanyId: Integer; out AErr: string): Boolean;
var
  I: Integer;
  LSets: TStringList;
  LParams: TArray<Variant>;
  LValue: Variant;
  LErr, LSQL: string;
  LWhere: string;
begin
  AErr := '';
  LSets := TStringList.Create;
  try
    try
      for I := 0 to High(AFields) do
      begin
        if not Has(AObj, AFields[I].Name) then
          Continue;
        if not FieldToVariant(AObj, AFields[I], LValue, LErr) then
        begin
          AErr := LErr;
          Exit(False);
        end;
        if VarIsNull(LValue) then
          LSets.Add(AFields[I].Name + ' = NULL')
        else
        begin
          LSets.Add(AFields[I].Name + ' = ' + Placeholder(AFields[I], Length(LParams)));
          SetLength(LParams, Length(LParams) + 1);
          LParams[High(LParams)] := LValue;
        end;
      end;

      if LSets.Count = 0 then
      begin
        AErr := 'No se recibieron campos para actualizar';
        Exit(False);
      end;

      if ACompanyId > 0 then
        LWhere := ' where id = :p' + IntToStr(Length(LParams)) + ' and company_id = :p' +
          IntToStr(Length(LParams) + 1)
      else
        LWhere := ' where id = :p' + IntToStr(Length(LParams));

      LSQL := 'update ' + ATable + ' set ' + JoinList(LSets, ', ') + LWhere;

      SetLength(LParams, Length(LParams) + 1);
      LParams[High(LParams)] := AId;
      if ACompanyId > 0 then
      begin
        SetLength(LParams, Length(LParams) + 1);
        LParams[High(LParams)] := ACompanyId;
      end;

      if TDB.Exec(LSQL, LParams) = 0 then
      begin
        AErr := 'Registro no encontrado';
        Exit(False);
      end;
      Result := True;
    except
      on E: Exception do
      begin
        AErr := E.Message;
        Result := False;
      end;
    end;
  finally
    LSets.Free;
  end;
end;

function DeleteRow(const ATable, AEntity: string; AId, ACompanyId: Integer;
  AHard: Boolean; out AErr: string): Boolean;
var
  LSQL: string;
  LAffected: Integer;
begin
  AErr := '';
  try
    if AHard then
    begin
      if ACompanyId > 0 then
        LSQL := 'delete from ' + ATable + ' where id = :p0 and company_id = :p1'
      else
        LSQL := 'delete from ' + ATable + ' where id = :p0';
    end
    else
    begin
      if ACompanyId > 0 then
        LSQL := 'update ' + ATable + ' set active = false where id = :p0 and company_id = :p1'
      else
        LSQL := 'update ' + ATable + ' set active = false where id = :p0';
    end;

    if ACompanyId > 0 then
      LAffected := TDB.Exec(LSQL, [AId, ACompanyId])
    else
      LAffected := TDB.Exec(LSQL, [AId]);

    if LAffected = 0 then
    begin
      AErr := 'Registro no encontrado';
      Exit(False);
    end;
    if AHard then
      AuditAction('delete', AEntity, AId, '{"hard":true}')
    else
      AuditAction('delete', AEntity, AId, '{"hard":false}');
    Result := True;
  except
    on E: Exception do
    begin
      AErr := E.Message;
      Result := False;
    end;
  end;
end;

procedure SendList(Res: THorseResponse; const ASQL: string; const AParams: array of Variant);
var
  LJson: string;
begin
  try
    LJson := TDB.Q(ASQL, AParams);
    if LJson.Trim.IsEmpty then
      LJson := '[]';
    SendJsonText(Res, LJson, 200);
  except
    on E: Exception do
      SendError(Res, E.Message, 500);
  end;
end;

procedure SendEntity(Res: THorseResponse; const AView: string; AId, ACompanyId: Integer);
var
  LJson: string;
  LSQL: string;
begin
  try
    if ACompanyId > 0 then
      LSQL := 'select row_to_json(t) from (select * from ' + AView +
        ' where id = :p0 and company_id = :p1) t'
    else
      LSQL := 'select row_to_json(t) from (select * from ' + AView +
        ' where id = :p0) t';

    if ACompanyId > 0 then
      LJson := TDB.Q(LSQL, [AId, ACompanyId])
    else
      LJson := TDB.Q(LSQL, [AId]);

    if LJson.Trim.IsEmpty then
      SendError(Res, 'Registro no encontrado', 404)
    else
      SendJsonText(Res, LJson, 200);
  except
    on E: Exception do
      SendError(Res, E.Message, 500);
  end;
end;

procedure SendCreated(Res: THorseResponse; AId: Integer);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('id', TJSONNumber.Create(AId));
    LObj.AddPair('created', True);
    SendJsonText(Res, LObj.ToJSON, 201);
  finally
    LObj.Free;
  end;
end;

procedure SendSaved(Res: THorseResponse; AId: Integer);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('id', TJSONNumber.Create(AId));
    LObj.AddPair('saved', True);
    SendJsonText(Res, LObj.ToJSON, 200);
  finally
    LObj.Free;
  end;
end;

procedure SendDeleted(Res: THorseResponse);
begin
  SendJsonText(Res, '{"deleted":true}', 200);
end;

function CsvEscape(const AValue: string): string;
begin
  Result := AValue.Replace('"', '""');
  if (Pos(';', Result) > 0) or (Pos('"', AValue) > 0) or
     (Pos(#10, Result) > 0) or (Pos(#13, Result) > 0) then
    Result := '"' + Result + '"';
end;

function CsvNumber(AValue: Double): string;
var
  LFS: TFormatSettings;
begin
  LFS := TFormatSettings.Create;
  LFS.DecimalSeparator := ',';
  LFS.ThousandSeparator := '.';
  Result := FormatFloat('#,##0.00', AValue, LFS);
end;

function CsvDate(AValue: TDateTime): string;
begin
  if AValue = 0 then
    Result := ''
  else
    Result := FormatDateTime('dd/mm/yyyy', AValue);
end;

procedure SendCsv(Res: THorseResponse; const AFileName, AContent: string);
begin
  Res.Status(200)
     .ContentType('text/csv; charset=utf-8')
     .RawWebResponse.SetCustomHeader('Content-Disposition',
       'attachment; filename="' + AFileName + '"');
  Res.Send(#$FEFF + AContent);
end;

function IsoDate(AValue: TDateTime): string;
begin
  if AValue = 0 then
    Result := ''
  else
    Result := FormatDateTime('yyyy-mm-dd', AValue);
end;

end.
