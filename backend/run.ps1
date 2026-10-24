param(
  [int]$Port = 9020
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $PSScriptRoot 'Win64\Release\UnionBackend.exe'
if (-not (Test-Path $exe)) {
  throw "No existe $exe. Ejecute primero backend\build.ps1"
}

$env:UNION_PG_HOST     = if ($env:UNION_PG_HOST)     { $env:UNION_PG_HOST }     else { 'localhost' }
$env:UNION_PG_PORT     = if ($env:UNION_PG_PORT)     { $env:UNION_PG_PORT }     else { '5432' }
$env:UNION_PG_DATABASE = if ($env:UNION_PG_DATABASE) { $env:UNION_PG_DATABASE } else { 'union_transporte' }
$env:UNION_PG_USER     = if ($env:UNION_PG_USER)     { $env:UNION_PG_USER }     else { 'postgres' }
$env:UNION_PG_PASSWORD = if ($env:UNION_PG_PASSWORD) { $env:UNION_PG_PASSWORD } else { 'postgres' }
$env:UNION_HOST        = if ($env:UNION_HOST)        { $env:UNION_HOST }        else { '127.0.0.1' }
$env:UNION_PORT        = $Port

Write-Host "UNION Backend -> http://$env:UNION_HOST`:$Port" -ForegroundColor Cyan
Push-Location (Split-Path -Parent $exe)
try {
  & $exe
} finally {
  Pop-Location
}
