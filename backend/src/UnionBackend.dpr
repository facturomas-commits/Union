program UnionBackend;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  Horse,
  UConfig, UDB, ULog, UAuth, URoutes;

var
  LPort: Integer;
begin
  ReportMemoryLeaksOnShutdown := False;
  try
    TConfig.Load;
    TDB.Init;
    LPort := TConfig.ServerPort;

    // Pool de conexiones + IP + log de requests
    THorse.Use(DbMiddleware);
    // Sesión / roles
    THorse.Use(AuthMiddleware);

    RegisterRoutes;

    THorse.OnListen := procedure(AHorse: THorse)
    begin
      WriteLn('UNION Backend escuchando en http://' + TConfig.ServerHost + ':' + LPort.ToString);
      WriteLn('Web: http://' + TConfig.ServerHost + ':' + LPort.ToString + '/');
      LogInfo('Servidor escuchando en ' + TConfig.ServerHost + ':' + LPort.ToString);
    end;

    THorse.Listen(LPort, TConfig.ServerHost);
  except
    on E: Exception do
    begin
      WriteLn('Error fatal: ' + E.Message);
      LogError('Error fatal: ' + E.ClassName + ': ' + E.Message);
      ExitCode := 1;
    end;
  end;
  TDB.Done;
end.
