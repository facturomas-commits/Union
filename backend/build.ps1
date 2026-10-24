param(
  [switch]$SkipWeb
)

$ErrorActionPreference = 'Stop'

$backend = $PSScriptRoot
$root    = Split-Path -Parent $backend
$src     = Join-Path $backend 'src'
$out     = Join-Path $backend 'Win64\Release'
$dpr     = Join-Path $src 'UnionBackend.dpr'
$rsvars  = 'C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat'

if (-not (Test-Path $rsvars)) {
  throw "No se encontró rsvars.bat. Ajuste la ruta de Delphi en backend\build.ps1"
}

$bds    = Split-Path -Parent (Split-Path -Parent $rsvars)
$bdsLib = Join-Path $bds 'lib\Win64\release'

New-Item -ItemType Directory -Force -Path $out | Out-Null

$cmd = 'call "' + $rsvars + '" >nul && dcc64 -B ' +
       '-U"' + $src + '" ' +
       '-U"' + (Join-Path $backend 'lib\horse') + '" ' +
       '-U"' + $bdsLib + '" ' +
       '-E"' + $out + '" ' +
       '-N0"' + $out + '" ' +
       '"' + $dpr + '"'

Write-Host 'Compilando UnionBackend (Win64)...' -ForegroundColor Cyan
cmd /c $cmd
if ($LASTEXITCODE -ne 0) {
  throw "Falló la compilación (código $LASTEXITCODE)"
}

if (-not $SkipWeb) {
  $webOut = Join-Path $out 'web'
  if (Test-Path $webOut) { Remove-Item $webOut -Recurse -Force }
  Copy-Item (Join-Path $backend 'web') $webOut -Recurse -Force
  Write-Host "Web copiada a $webOut" -ForegroundColor DarkGray
}

# DLLs de PostgreSQL (libpq) que FireDAC necesita junto al EXE.
$pgBin = $env:PG_BIN
if (-not $pgBin) { $pgBin = 'C:\Program Files\PostgreSQL\16\bin' }
$dlls = @('libpq.dll','libssl-3-x64.dll','libcrypto-3-x64.dll',
          'libiconv-2.dll','libintl-9.dll','libwinpthread-1.dll','zlib1.dll')
if (Test-Path $pgBin) {
  foreach ($dll in $dlls) {
    $target = Join-Path $out $dll
    if (-not (Test-Path $target)) {
      $source = Join-Path $pgBin $dll
      if (Test-Path $source) { Copy-Item $source $target -Force }
    }
  }
} else {
  Write-Warning "No se encontró PostgreSQL en $pgBin. Copie libpq.dll y dependencias a $out"
}

Write-Host ''
Write-Host 'Build OK' -ForegroundColor Green
Write-Host "  EXE: $(Join-Path $out 'UnionBackend.exe')"
Write-Host "  Web: $(Join-Path $out 'web')"
Write-Host ''
Write-Host 'Ejecutar:  powershell -ExecutionPolicy Bypass -File backend\run.ps1'
