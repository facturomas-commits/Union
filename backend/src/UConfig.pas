unit UConfig;

interface

uses
  System.SysUtils, System.IOUtils;

type
  TConfig = class
  private
    class var FDbHost: string;
    class var FDbPort: Integer;
    class var FDbName: string;
    class var FDbUser: string;
    class var FDbPassword: string;
    class var FServerHost: string;
    class var FServerPort: Integer;
    class var FWebDir: string;
    class var FLogDir: string;
    class var FSessionHours: Integer;
    class var FPoolSize: Integer;
    class function Env(const AName, ADefault: string): string; static;
    class function ResolveWebDir: string; static;
  public
    class procedure Load; static;
    class property DbHost: string read FDbHost;
    class property DbPort: Integer read FDbPort;
    class property DbName: string read FDbName;
    class property DbUser: string read FDbUser;
    class property DbPassword: string read FDbPassword;
    class property ServerHost: string read FServerHost;
    class property ServerPort: Integer read FServerPort;
    class property WebDir: string read FWebDir;
    class property LogDir: string read FLogDir;
    class property SessionHours: Integer read FSessionHours;
    class property PoolSize: Integer read FPoolSize;
  end;

implementation

class function TConfig.Env(const AName, ADefault: string): string;
begin
  Result := GetEnvironmentVariable(AName);
  if Result.Trim.IsEmpty then
    Result := ADefault;
end;

class function TConfig.ResolveWebDir: string;
var
  LExeDir: string;
begin
  Result := Env('UNION_WEB_DIR', '');
  if not Result.IsEmpty then
    Exit(TPath.GetFullPath(Result));

  LExeDir := ExtractFilePath(ParamStr(0));
  Result := TPath.Combine(LExeDir, 'web');
  if TDirectory.Exists(Result) then
    Exit;

  // Ejecutando desde backend\Win64\Release -> backend\web
  Result := TPath.GetFullPath(TPath.Combine(LExeDir, '..\..\web'));
end;

class procedure TConfig.Load;
begin
  FDbHost     := Env('UNION_PG_HOST', 'localhost');
  FDbPort     := StrToIntDef(Env('UNION_PG_PORT', '5432'), 5432);
  FDbName     := Env('UNION_PG_DATABASE', 'union_transporte');
  FDbUser     := Env('UNION_PG_USER', 'postgres');
  FDbPassword := Env('UNION_PG_PASSWORD', 'postgres');
  FServerHost := Env('UNION_HOST', '127.0.0.1');
  FServerPort := StrToIntDef(Env('UNION_PORT', '9020'), 9020);
  FWebDir     := ResolveWebDir;
  FLogDir     := TPath.Combine(ExtractFilePath(ParamStr(0)), 'logs');
  FSessionHours := StrToIntDef(Env('UNION_SESSION_HOURS', '12'), 12);
  FPoolSize   := StrToIntDef(Env('UNION_POOL_SIZE', '10'), 10);
  if FPoolSize < 2 then FPoolSize := 2;
  ForceDirectories(FLogDir);
end;

end.
