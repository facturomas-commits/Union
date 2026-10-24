unit UDB;

interface

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.Generics.Collections,
  System.Variants, System.Diagnostics,
  FireDAC.Comp.Client, FireDAC.Comp.DataSet, FireDAC.Stan.Def, FireDAC.Stan.Async,
  FireDAC.Phys.PG, FireDAC.Phys.PGDef, FireDAC.Stan.Param, FireDAC.DApt, Data.DB,
  Horse, UConfig, ULog;

type
  TDB = class
  private
    class var FPool: TList<TFDConnection>;
    class var FLock: TCriticalSection;
    class function NewConn: TFDConnection; static;
    class procedure Bind(AQry: TFDQuery; const AParams: array of Variant); static;
    class function OpenSingle(const ASQL: string; const AParams: array of Variant): TFDQuery; static;
  public
    class procedure Init; static;
    class procedure Done; static;
    class function Acquire: TFDConnection; static;
    class procedure Release(AConn: TFDConnection); static;
    class function Conn: TFDConnection; static;

    class function Q(const ASQL: string; const AParams: array of Variant): string; static;
    class function QInt(const ASQL: string; const AParams: array of Variant): Integer; static;
    class function QFloat(const ASQL: string; const AParams: array of Variant): Double; static;
    class function QBool(const ASQL: string; const AParams: array of Variant): Boolean; static;
    class function Exec(const ASQL: string; const AParams: array of Variant): Integer; static;
    class function ExecRetId(const ASQL: string; const AParams: array of Variant): Integer; static;

    class procedure BeginTx; static;
    class procedure CommitTx; static;
    class procedure RollbackTx; static;
  end;

procedure DbMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);

threadvar
  GCurrentConn: TFDConnection;
  GRequestIP: string;

implementation

class function TDB.NewConn: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.DriverName := 'PG';
    Result.Params.Values['Server'] := TConfig.DbHost;
    Result.Params.Values['Port'] := TConfig.DbPort.ToString;
    Result.Params.Values['Database'] := TConfig.DbName;
    Result.Params.Values['User_Name'] := TConfig.DbUser;
    Result.Params.Values['Password'] := TConfig.DbPassword;
    Result.Params.Values['CharacterSet'] := 'UTF8';
    Result.LoginPrompt := False;
    Result.TxOptions.AutoCommit := True;
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

class procedure TDB.Init;
var
  LConn: TFDConnection;
begin
  if Assigned(FPool) then
    Exit;
  FPool := TList<TFDConnection>.Create;
  FLock := TCriticalSection.Create;
  // Falla rápido si la base no está disponible.
  LConn := Acquire;
  Release(LConn);
  LogInfo('Pool de base de datos inicializado (' + TConfig.DbName + '@' + TConfig.DbHost + ':' + TConfig.DbPort.ToString + ')');
end;

class procedure TDB.Done;
var
  LConn: TFDConnection;
begin
  if not Assigned(FPool) then
    Exit;
  FLock.Enter;
  try
    for LConn in FPool do
    begin
      try
        if LConn.Connected then LConn.Close;
      except
      end;
      LConn.Free;
    end;
    FPool.Clear;
  finally
    FLock.Leave;
  end;
  FreeAndNil(FPool);
  FreeAndNil(FLock);
end;

class function TDB.Acquire: TFDConnection;
begin
  FLock.Enter;
  try
    if FPool.Count > 0 then
    begin
      Result := FPool[FPool.Count - 1];
      FPool.Delete(FPool.Count - 1);
    end
    else
      Result := nil;
  finally
    FLock.Leave;
  end;

  if Result = nil then
    Result := NewConn
  else if not Result.Connected then
    Result.Open;
end;

class procedure TDB.Release(AConn: TFDConnection);
begin
  if not Assigned(AConn) then
    Exit;
  try
    if AConn.InTransaction then
      AConn.Rollback;
  except
  end;
  FLock.Enter;
  try
    if FPool.Count < TConfig.PoolSize then
      FPool.Add(AConn)
    else
    begin
      try
        if AConn.Connected then AConn.Close;
      except
      end;
      AConn.Free;
    end;
  finally
    FLock.Leave;
  end;
end;

class function TDB.Conn: TFDConnection;
begin
  if not Assigned(GCurrentConn) then
    raise Exception.Create('Conexión de base de datos no inicializada para este request');
  Result := GCurrentConn;
end;

class procedure TDB.Bind(AQry: TFDQuery; const AParams: array of Variant);
var
  I: Integer;
  LP: TFDParam;
begin
  for I := 0 to High(AParams) do
  begin
    LP := AQry.ParamByName('p' + IntToStr(I));
    if VarIsNull(AParams[I]) or VarIsEmpty(AParams[I]) then
      LP.Clear
    else
      LP.Value := AParams[I];
  end;
end;

class function TDB.OpenSingle(const ASQL: string; const AParams: array of Variant): TFDQuery;
begin
  Result := TFDQuery.Create(nil);
  try
    Result.Connection := Conn;
    Result.SQL.Text := ASQL;
    Bind(Result, AParams);
    Result.Open;
  except
    Result.Free;
    raise;
  end;
end;

class function TDB.Q(const ASQL: string; const AParams: array of Variant): string;
var
  LQry: TFDQuery;
begin
  LQry := OpenSingle(ASQL, AParams);
  try
    if LQry.IsEmpty or LQry.Fields[0].IsNull then
      Result := ''
    else
      Result := LQry.Fields[0].AsString;
  finally
    LQry.Free;
  end;
end;

class function TDB.QInt(const ASQL: string; const AParams: array of Variant): Integer;
var
  LQry: TFDQuery;
begin
  LQry := OpenSingle(ASQL, AParams);
  try
    if LQry.IsEmpty or LQry.Fields[0].IsNull then
      Result := 0
    else
      Result := LQry.Fields[0].AsInteger;
  finally
    LQry.Free;
  end;
end;

class function TDB.QFloat(const ASQL: string; const AParams: array of Variant): Double;
var
  LQry: TFDQuery;
begin
  LQry := OpenSingle(ASQL, AParams);
  try
    if LQry.IsEmpty or LQry.Fields[0].IsNull then
      Result := 0
    else
      Result := LQry.Fields[0].AsFloat;
  finally
    LQry.Free;
  end;
end;

class function TDB.QBool(const ASQL: string; const AParams: array of Variant): Boolean;
var
  LQry: TFDQuery;
begin
  LQry := OpenSingle(ASQL, AParams);
  try
    if LQry.IsEmpty or LQry.Fields[0].IsNull then
      Result := False
    else
      Result := LQry.Fields[0].AsBoolean;
  finally
    LQry.Free;
  end;
end;

class function TDB.Exec(const ASQL: string; const AParams: array of Variant): Integer;
var
  LQry: TFDQuery;
begin
  LQry := TFDQuery.Create(nil);
  try
    LQry.Connection := Conn;
    LQry.SQL.Text := ASQL;
    Bind(LQry, AParams);
    LQry.ExecSQL;
    Result := LQry.RowsAffected;
  finally
    LQry.Free;
  end;
end;

class function TDB.ExecRetId(const ASQL: string; const AParams: array of Variant): Integer;
var
  LQry: TFDQuery;
begin
  LQry := OpenSingle(ASQL, AParams);
  try
    if LQry.IsEmpty or LQry.Fields[0].IsNull then
      Result := 0
    else
      Result := LQry.Fields[0].AsInteger;
  finally
    LQry.Free;
  end;
end;

class procedure TDB.BeginTx;
begin
  Conn.StartTransaction;
end;

class procedure TDB.CommitTx;
begin
  Conn.Commit;
end;

class procedure TDB.RollbackTx;
begin
  if Conn.InTransaction then
    Conn.Rollback;
end;

procedure DbMiddleware(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LConn: TFDConnection;
  LPath: string;
  LWatch: TStopwatch;
begin
  LPath := Req.RawWebRequest.PathInfo;
  if not LPath.ToLower.StartsWith('/api') then
  begin
    Next;
    Exit;
  end;

  GRequestIP := Req.RawWebRequest.RemoteIP.Trim;
  if (GRequestIP = '127.0.0.1') or (GRequestIP = '::1') then
  begin
    GRequestIP := Req.Headers['CF-Connecting-IP'].Trim;
    if GRequestIP.IsEmpty then
      GRequestIP := Req.Headers['X-Forwarded-For'].Trim;
    if Pos(',', GRequestIP) > 0 then
      GRequestIP := Copy(GRequestIP, 1, Pos(',', GRequestIP) - 1).Trim;
  end;
  GRequestIP := Copy(GRequestIP, 1, 60);

  LWatch := TStopwatch.StartNew;
  LConn := TDB.Acquire;
  GCurrentConn := LConn;
  try
    try
      Next;
    except
      on E: EHorseCallbackInterrupted do
        raise;
      on E: Exception do
      begin
        LogError(Req.RawWebRequest.Method + ' ' + LPath + ' -> ' + E.ClassName + ': ' + E.Message);
        raise;
      end;
    end;
  finally
    GCurrentConn := nil;
    TDB.Release(LConn);
    LogInfo(Format('%s %s -> %d (%d ms)', [Req.RawWebRequest.Method, LPath,
      Res.Status, LWatch.ElapsedMilliseconds]));
  end;
end;

end.
