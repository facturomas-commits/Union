# Base de datos

## Crear desde cero

```powershell
$env:PGPASSWORD='postgres'
$psql = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'

& $psql -U postgres -h localhost -c "CREATE DATABASE union_transporte ENCODING 'UTF8' TEMPLATE template0"
& $psql -U postgres -h localhost -d union_transporte -v ON_ERROR_STOP=1 -f schema.sql
& $psql -U postgres -h localhost -d union_transporte -v ON_ERROR_STOP=1 -f seed.sql
```

## Reiniciar datos de demo

`seed.sql` empieza con `TRUNCATE ... RESTART IDENTITY CASCADE`, así que volver a ejecutarlo deja la base en el estado de la planilla original.

```powershell
& $psql -U postgres -h localhost -d union_transporte -f seed.sql
```

## Regenerar el seed desde Excel

```powershell
python ..\tools\import_planilla.py
```

## Backup

```powershell
& 'C:\Program Files\PostgreSQL\16\bin\pg_dump.exe' -U postgres -Fc union_transporte > union_transporte.dump
```

## Restore

```powershell
& 'C:\Program Files\PostgreSQL\16\bin\pg_restore.exe' -U postgres -d union_transporte --clean --if-exists union_transporte.dump
```

## Notas

- `schema.sql` crea `pgcrypto` (necesario para `crypt`/`gen_salt`).
- `seed.sql` incluye usuarios demo con claves hasheadas por PostgreSQL.
- Las vistas `v_services`, `v_freight_trips`, etc. son la fuente de los reportes.
