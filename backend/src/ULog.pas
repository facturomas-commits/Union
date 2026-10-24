unit ULog;

interface

procedure LogInfo(const AMsg: string);
procedure LogError(const AMsg: string);

implementation

uses
  System.SysUtils, System.Classes, System.SyncObjs, System.IOUtils, UConfig;

var
  GLock: TCriticalSection;

procedure WriteLine(const ALevel, AMsg: string);
var
  LFile: string;
  LBytes: TBytes;
  LStream: TFileStream;
begin
  if not Assigned(GLock) then
    Exit;
  GLock.Enter;
  try
    try
      LFile := TPath.Combine(TConfig.LogDir, 'union-backend.log');
      ForceDirectories(TConfig.LogDir);
      LBytes := TEncoding.UTF8.GetBytes(
        FormatDateTime('yyyy-mm-dd hh:nn:ss.zzz', Now) + ' [' + ALevel + '] ' + AMsg + sLineBreak);
      if FileExists(LFile) then
        LStream := TFileStream.Create(LFile, fmOpenWrite or fmShareDenyWrite)
      else
        LStream := TFileStream.Create(LFile, fmCreate or fmShareDenyWrite);
      try
        LStream.Seek(0, soEnd);
        if Length(LBytes) > 0 then
          LStream.WriteBuffer(LBytes[0], Length(LBytes));
      finally
        LStream.Free;
      end;
    except
      // El log nunca debe tumbar un request.
    end;
  finally
    GLock.Leave;
  end;
end;

procedure LogInfo(const AMsg: string);
begin
  WriteLine('INFO', AMsg);
end;

procedure LogError(const AMsg: string);
begin
  WriteLine('ERROR', AMsg);
end;

initialization
  GLock := TCriticalSection.Create;

finalization
  FreeAndNil(GLock);

end.
