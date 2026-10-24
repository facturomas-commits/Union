unit UWeb;

interface

procedure RegisterWebRoutes;

implementation

uses
  System.SysUtils, System.Classes, System.IOUtils,
  Horse, UHttp, UConfig, ULog;

function MimeFor(const AFile: string): string;
var
  LExt: string;
begin
  LExt := TPath.GetExtension(AFile).ToLower;
  if LExt = '.html' then Result := 'text/html; charset=utf-8'
  else if LExt = '.css' then Result := 'text/css; charset=utf-8'
  else if LExt = '.js' then Result := 'text/javascript; charset=utf-8'
  else if LExt = '.svg' then Result := 'image/svg+xml'
  else if LExt = '.json' then Result := 'application/json; charset=utf-8'
  else if LExt = '.png' then Result := 'image/png'
  else if LExt = '.ico' then Result := 'image/x-icon'
  else if LExt = '.woff2' then Result := 'font/woff2'
  else Result := 'application/octet-stream';
end;

procedure SecurityHeaders(Res: THorseResponse);
begin
  Res.RawWebResponse.SetCustomHeader('X-Content-Type-Options', 'nosniff');
  Res.RawWebResponse.SetCustomHeader('X-Frame-Options', 'DENY');
  Res.RawWebResponse.SetCustomHeader('Referrer-Policy', 'same-origin');
  Res.RawWebResponse.SetCustomHeader('Permissions-Policy',
    'camera=(), microphone=(), geolocation=()');
  Res.RawWebResponse.SetCustomHeader('Cross-Origin-Opener-Policy', 'same-origin');
  Res.RawWebResponse.SetCustomHeader('X-Permitted-Cross-Domain-Policies', 'none');
  Res.RawWebResponse.SetCustomHeader('Content-Security-Policy',
    'default-src ''self''; script-src ''self''; style-src ''self'' ''unsafe-inline''; ' +
    'img-src ''self'' data:; font-src ''self''; connect-src ''self''; ' +
    'object-src ''none''; base-uri ''self''; form-action ''self''; frame-ancestors ''none''');
  Res.RawWebResponse.SetCustomHeader('Strict-Transport-Security',
    'max-age=31536000');
end;

procedure ServeIndex(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  LPath: string;
  LHtml: string;
begin
  try
    LPath := TPath.Combine(TConfig.WebDir, 'index.html');
    if not FileExists(LPath) then
    begin
      SendError(Res, 'No se encontró index.html en ' + TConfig.WebDir, 500);
      Exit;
    end;
    LHtml := TFile.ReadAllText(LPath, TEncoding.UTF8);
    SecurityHeaders(Res);
    Res.RawWebResponse.SetCustomHeader('Cache-Control', 'no-store');
    Res.Status(200).ContentType('text/html; charset=utf-8').Send(LHtml);
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure ServeFrom(Res: THorseResponse; const ASubDir, AFile: string);
var
  LPath, LContent: string;
begin
  if AFile.IsEmpty or (AFile <> ExtractFileName(AFile)) or
     (Pos('..', AFile) > 0) or (Pos('/', AFile) > 0) or (Pos('\', AFile) > 0) then
  begin
    SendError(Res, 'Archivo inválido', 400);
    Exit;
  end;

  LPath := TPath.Combine(TPath.Combine(TConfig.WebDir, ASubDir), AFile);
  if not FileExists(LPath) then
  begin
    SendError(Res, 'Archivo no encontrado', 404);
    Exit;
  end;

  LContent := TFile.ReadAllText(LPath, TEncoding.UTF8);
  SecurityHeaders(Res);
  Res.RawWebResponse.SetCustomHeader('Cache-Control', 'no-store, no-cache, must-revalidate');
  Res.RawWebResponse.SetCustomHeader('Pragma', 'no-cache');
  Res.Status(200).ContentType(MimeFor(AFile)).Send(LContent);
end;

procedure ServeAsset(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
    ServeFrom(Res, 'assets', ParamValue(Req, 'file', ''));
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure ServeViewAsset(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  try
    ServeFrom(Res, TPath.Combine('assets', 'views'), ParamValue(Req, 'file', ''));
  except
    on E: Exception do SendError(Res, E.Message, 500);
  end;
end;

procedure Favicon(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  Res.Status(204).Send('');
end;

procedure RegisterWebRoutes;
begin
  THorse.Get('/', ServeIndex);
  THorse.Get('/assets/views/:file', ServeViewAsset);
  THorse.Get('/assets/:file', ServeAsset);
  THorse.Get('/favicon.ico', Favicon);
end;

end.
