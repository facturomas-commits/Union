unit UHttp;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  Horse;

function ReadBodyUTF8(Req: THorseRequest): string;
procedure SendJsonText(Res: THorseResponse; const AJson: string; AStatus: Integer = 200);
procedure SendError(Res: THorseResponse; const AMsg: string; AStatus: Integer = 400);
procedure SendOk(Res: THorseResponse; const AJson: string = '{"ok":true}');

function ParseBodyObject(Req: THorseRequest; out AObj: TJSONObject; out AErr: string): Boolean;
function ParseBodyArray(Req: THorseRequest; out AArr: TJSONArray; out AErr: string): Boolean;

function Has(AObj: TJSONObject; const AName: string): Boolean;
function IsNullValue(AObj: TJSONObject; const AName: string): Boolean;
function GetStr(AObj: TJSONObject; const AName: string; const ADefault: string = ''): string;
function GetInt(AObj: TJSONObject; const AName: string; ADefault: Integer = 0): Integer;
function GetNum(AObj: TJSONObject; const AName: string; ADefault: Double = 0): Double;
function GetBool(AObj: TJSONObject; const AName: string; ADefault: Boolean = False): Boolean;

function QueryValue(Req: THorseRequest; const AName, ADefault: string): string;
function ParamValue(Req: THorseRequest; const AName, ADefault: string): string;
function QueryInt(Req: THorseRequest; const AName: string; ADefault: Integer): Integer;

function TodayISO: string;
function MonthISO: string;
function IsISODate(const AValue: string): Boolean;
function IsISOMonth(const AValue: string): Boolean;
function DateRangeStart(const AMonth: string): string;

function JsonArrayOrEmpty(const AJson: string): TJSONValue;
function JsonObjectOrEmpty(const AJson: string): TJSONValue;
function EscapeJsonText(const AText: string): string;

implementation

uses
  System.DateUtils;

function ReadBodyUTF8(Req: THorseRequest): string;
var
  LBytes: TBytes;
begin
  LBytes := Req.RawWebRequest.RawContent;
  if Length(LBytes) > 0 then
    Result := TEncoding.UTF8.GetString(LBytes)
  else
    Result := Req.Body;
end;

procedure SendJsonText(Res: THorseResponse; const AJson: string; AStatus: Integer);
begin
  Res.Status(AStatus)
     .ContentType('application/json; charset=utf-8')
     .Send(AJson);
end;

procedure SendError(Res: THorseResponse; const AMsg: string; AStatus: Integer);
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('error', AMsg);
    SendJsonText(Res, LObj.ToJSON, AStatus);
  finally
    LObj.Free;
  end;
end;

procedure SendOk(Res: THorseResponse; const AJson: string);
begin
  SendJsonText(Res, AJson, 200);
end;

function ParseBodyObject(Req: THorseRequest; out AObj: TJSONObject; out AErr: string): Boolean;
var
  LValue: TJSONValue;
begin
  AObj := nil;
  AErr := '';
  LValue := TJSONObject.ParseJSONValue(ReadBodyUTF8(Req));
  if not Assigned(LValue) then
  begin
    AErr := 'Cuerpo JSON inválido o vacío';
    Exit(False);
  end;
  if not (LValue is TJSONObject) then
  begin
    LValue.Free;
    AErr := 'Se esperaba un objeto JSON';
    Exit(False);
  end;
  AObj := TJSONObject(LValue);
  Result := True;
end;

function ParseBodyArray(Req: THorseRequest; out AArr: TJSONArray; out AErr: string): Boolean;
var
  LValue: TJSONValue;
begin
  AArr := nil;
  AErr := '';
  LValue := TJSONObject.ParseJSONValue(ReadBodyUTF8(Req));
  if not Assigned(LValue) then
  begin
    AErr := 'Cuerpo JSON inválido o vacío';
    Exit(False);
  end;
  if not (LValue is TJSONArray) then
  begin
    LValue.Free;
    AErr := 'Se esperaba un arreglo JSON';
    Exit(False);
  end;
  AArr := TJSONArray(LValue);
  Result := True;
end;

function Has(AObj: TJSONObject; const AName: string): Boolean;
begin
  Result := Assigned(AObj) and Assigned(AObj.FindValue(AName));
end;

function IsNullValue(AObj: TJSONObject; const AName: string): Boolean;
var
  LValue: TJSONValue;
begin
  LValue := nil;
  if Assigned(AObj) then
    LValue := AObj.FindValue(AName);
  Result := Assigned(LValue) and (LValue is TJSONNull);
end;

function GetStr(AObj: TJSONObject; const AName: string; const ADefault: string): string;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  LValue := AObj.FindValue(AName);
  if Assigned(LValue) and not (LValue is TJSONNull) then
    Result := LValue.Value;
end;

function GetInt(AObj: TJSONObject; const AName: string; ADefault: Integer): Integer;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  LValue := AObj.FindValue(AName);
  if not Assigned(LValue) or (LValue is TJSONNull) then
    Exit;
  if LValue is TJSONNumber then
    Result := TJSONNumber(LValue).AsInt
  else
    Result := StrToIntDef(LValue.Value, ADefault);
end;

function GetNum(AObj: TJSONObject; const AName: string; ADefault: Double): Double;
var
  LValue: TJSONValue;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  LValue := AObj.FindValue(AName);
  if not Assigned(LValue) or (LValue is TJSONNull) then
    Exit;
  if LValue is TJSONNumber then
    Result := TJSONNumber(LValue).AsDouble
  else
    Result := StrToFloatDef(LValue.Value, ADefault, TFormatSettings.Invariant);
end;

function GetBool(AObj: TJSONObject; const AName: string; ADefault: Boolean): Boolean;
var
  LValue: TJSONValue;
  LText: string;
begin
  Result := ADefault;
  if not Assigned(AObj) then
    Exit;
  LValue := AObj.FindValue(AName);
  if not Assigned(LValue) or (LValue is TJSONNull) then
    Exit;
  if LValue is TJSONBool then
    Exit(TJSONBool(LValue).AsBoolean);
  LText := LValue.Value.Trim.ToLower;
  Result := (LText = 'true') or (LText = '1') or (LText = 'si') or (LText = 'sí');
end;

function QueryValue(Req: THorseRequest; const AName, ADefault: string): string;
begin
  if not Req.Query.TryGetValue(AName, Result) or Result.Trim.IsEmpty then
    Result := ADefault;
end;

function ParamValue(Req: THorseRequest; const AName, ADefault: string): string;
begin
  if not Req.Params.TryGetValue(AName, Result) or Result.Trim.IsEmpty then
    Result := ADefault;
end;

function QueryInt(Req: THorseRequest; const AName: string; ADefault: Integer): Integer;
begin
  Result := StrToIntDef(QueryValue(Req, AName, IntToStr(ADefault)), ADefault);
end;

function TodayISO: string;
begin
  Result := FormatDateTime('yyyy-mm-dd', Date);
end;

function MonthISO: string;
begin
  Result := FormatDateTime('yyyy-mm', Date);
end;

function IsISODate(const AValue: string): Boolean;
var
  Y, M, D: Integer;
  LDate: TDateTime;
begin
  Result := False;
  if Length(AValue) <> 10 then Exit;
  if (AValue[5] <> '-') or (AValue[8] <> '-') then Exit;
  if not TryStrToInt(Copy(AValue, 1, 4), Y) then Exit;
  if not TryStrToInt(Copy(AValue, 6, 2), M) then Exit;
  if not TryStrToInt(Copy(AValue, 9, 2), D) then Exit;
  Result := TryEncodeDate(Y, M, D, LDate);
end;

function IsISOMonth(const AValue: string): Boolean;
var
  Y, M: Integer;
begin
  Result := False;
  if Length(AValue) <> 7 then Exit;
  if AValue[5] <> '-' then Exit;
  if not TryStrToInt(Copy(AValue, 1, 4), Y) then Exit;
  if not TryStrToInt(Copy(AValue, 6, 2), M) then Exit;
  Result := (Y >= 2000) and (Y <= 2100) and (M >= 1) and (M <= 12);
end;

function DateRangeStart(const AMonth: string): string;
begin
  Result := AMonth + '-01';
end;

function JsonArrayOrEmpty(const AJson: string): TJSONValue;
begin
  Result := nil;
  if not AJson.Trim.IsEmpty then
    Result := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(Result) then
    Result := TJSONArray.Create
  else if not (Result is TJSONArray) then
  begin
    Result.Free;
    Result := TJSONArray.Create;
  end;
end;

function JsonObjectOrEmpty(const AJson: string): TJSONValue;
begin
  Result := nil;
  if not AJson.Trim.IsEmpty then
    Result := TJSONObject.ParseJSONValue(AJson);
  if not Assigned(Result) then
    Result := TJSONObject.Create
  else if not (Result is TJSONObject) then
  begin
    Result.Free;
    Result := TJSONObject.Create;
  end;
end;

function EscapeJsonText(const AText: string): string;
var
  LObj: TJSONObject;
begin
  LObj := TJSONObject.Create;
  try
    LObj.AddPair('v', AText);
    Result := LObj.ToJSON;
  finally
    LObj.Free;
  end;
end;

end.
