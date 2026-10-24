# UNION · Gestión de Transporte

Sistema web de gestión operativa y financiera para una empresa de transporte de pasajeros y cargas, construido a partir de la planilla **PLANILLAS PROGRAMADOR.xlsx**.

- **Backend:** Delphi 13 + Horse + FireDAC + PostgreSQL 16
- **Frontend:** SPA en HTML/CSS/JavaScript (sin dependencias externas), servida por el backend
- **Base de datos:** PostgreSQL 16 con `pgcrypto`
- **Reportes:** diario y mensual, con impresión/PDF del navegador y exportación CSV para Excel
- **Seguridad:** login, sesiones, roles (`superadmin`, `admin`, `supervisor`, `operator`, `viewer`), auditoría

---

## 1. Qué resuelve

| Módulo | Contenido |
|---|---|
| **Dashboard** | KPIs del día, evolución de 7 días, alertas, colectivos y camión |
| **Servicios** | Programación de horarios y turnos: ruta, ida/vuelta, hora de salida, coche, chofer y guarda |
| **Colectivos** | Libro diario de recaudación: boletos, recaudación, gasoil, deducciones, sobrante y cierre |
| **Combustible** | Cargas de gasoil por vehículo, litros, importe, odómetro y tanque lleno |
| **Gastos** | Oncológico, boleterías, Mercado Pago y otros, asociados o no a un servicio |
| **Camión** | Viajes con remitos, kilos, tarifa, neto, IVA 21 %, total y comisión del chofer 15 % |
| **Mantenimiento** | Programar, presupuestar y marcar realizado; taller y teléfono de contacto; alertas de vencimiento |
| **Maestros** | Vehículos, empleados (choferes/guardas), rutas, talleres, usuarios y configuración |
| **Reportes** | Vistas General / Colectivos / Camión, diaria y mensual, con impresión y CSV |
| **Auditoría** | Registro de accesos, altas, modificaciones, bajas y cierres |

La planilla original se migró completa:

- 8 servicios de mayo 2025 (hoja *Libro Diario Colectivos*).
- 18 registros de mantenimiento del coche 72 (hoja *REPARACIONES*).
- 11 viajes y 16 remitos del camión 4 (hoja *Planilla CAMION*).

---

## 2. Puesta en marcha

### Requisitos

- PostgreSQL 16 instalado y corriendo.
- Delphi 13 (RAD Studio 37) con `dcc64` para compilar.
- Windows x64.

### 2.1 Crear la base

```powershell
$env:PGPASSWORD='postgres'
$psql = 'C:\Program Files\PostgreSQL\16\bin\psql.exe'

& $psql -U postgres -h localhost -c "CREATE DATABASE union_transporte ENCODING 'UTF8' TEMPLATE template0"
& $psql -U postgres -h localhost -d union_transporte -f db\schema.sql
& $psql -U postgres -h localhost -d union_transporte -f db\seed.sql
```

> `db\seed.sql` se regenera desde la planilla con `python tools\import_planilla.py`.
> El seed **trunca** las tablas y vuelve a cargar los datos: úselo solo para inicializar o reiniciar la demo.

### 2.2 Compilar el backend

```powershell
powershell -ExecutionPolicy Bypass -File backend\build.ps1
```

El build copia la web a `backend\Win64\Release\web` y las DLL de `libpq` desde la instalación de PostgreSQL.

### 2.3 Ejecutar

```powershell
powershell -ExecutionPolicy Bypass -File backend\run.ps1
```

Abrir: **http://localhost:9020**

### Usuarios iniciales

| Usuario | Rol |
|---|---|
| `admin` | Superadmin |
| `operador` | Operador |
| `consulta` | Consulta (solo lectura) |

> Las claves iniciales se definen en `db/seed.sql` **solo para instalación local**. Antes de exponer el sistema por Cloudflare, cambie la clave de `admin` y de todos los usuarios. El sistema obliga a cambiar la clave cuando el usuario tiene `must_change_password = TRUE` y exige un mínimo de 10 caracteres.

---

## 3. Configuración

Variables de entorno (todas opcionales):

| Variable | Default | Descripción |
|---|---|---|
| `UNION_HOST` | `127.0.0.1` | Interfaz donde escucha el backend. Dejar localhost y publicar solo por Cloudflared. |
| `UNION_PG_HOST` | `localhost` | Host PostgreSQL |
| `UNION_PG_PORT` | `5432` | Puerto PostgreSQL |
| `UNION_PG_DATABASE` | `union_transporte` | Base |
| `UNION_PG_USER` | `postgres` | Usuario |
| `UNION_PG_PASSWORD` | `postgres` | Clave |
| `UNION_PORT` | `9020` | Puerto HTTP |
| `UNION_SESSION_HOURS` | `12` | Duración de sesión |
| `UNION_POOL_SIZE` | `10` | Conexiones simultáneas |
| `UNION_WEB_DIR` | `exe\web` o `backend\web` | Carpeta de la SPA |

Configuración funcional por empresa en **Maestros → Configuración**: días de alerta de mantenimiento, IVA %, comisión % y nombre comercial.

### Seguridad y Cloudflared

- El backend escucha por defecto en **127.0.0.1:9020**. No abrir el puerto en el router ni en el firewall; solo Cloudflared debe llegar a él.
- Cloudflared debe apuntar a `http://127.0.0.1:9020`.
- Usar HTTPS en Cloudflare, activar **Always Use HTTPS**, WAF y rate limiting para `/api/auth/login`.
- Las sesiones usan cookie `HttpOnly`, `SameSite=Lax` y `Secure` cuando Cloudflare informa HTTPS. El token no se devuelve al JavaScript.
- Cambio de clave obligatorio para usuarios marcados, mínimo 10 caracteres; al cambiarla se cierran las demás sesiones.
- Bloqueo temporal tras 10 intentos fallidos por usuario/IP en 15 minutos.
- No exponer PostgreSQL a Internet. Usar una clave distinta de `postgres` y escuchar solo en localhost.
- Revisar los logs y la auditoría. Para mayor protección, se puede poner **Cloudflare Access** delante del panel.
- Detalle completo en [`docs/seguridad.md`](docs/seguridad.md).

---

## 4. Estructura del repositorio

```
Union/
  PLANILLAS PROGRAMADOR.xlsx     Planilla origen
  db/
    schema.sql                   Esquema PostgreSQL + vistas de reporte
    seed.sql                     Datos migrados (generado)
  tools/
    import_planilla.py           Importador de la planilla a SQL
  backend/
    src/                         Código Delphi (Horse)
      UnionBackend.dpr
      UConfig, UDB, UHttp, UAuth, UApi
      UCatalogRoutes, UScheduleRoutes, UOpsRoutes, UFreightRoutes, UReportRoutes, UWeb
    web/                         SPA (HTML/CSS/JS)
    lib/horse/                   Horse
    build.ps1 / run.ps1
  docs/
    modelo-datos.md
    reportes.md
    seguridad.md
    api.md
    planilla-a-sistema.md
    permisos.md
```

---

## 5. Reglas de negocio principales

- **Sobrante del servicio** = recaudación − gasoil − oncológico − boleterías − Mercado Pago − otros.
- **Ida y vuelta:** una ruta es un corredor; cada salida se carga por separado con su dirección (`ida`/`vuelta`) y horario. La vuelta puede vincularse a su ida.
- **Servicios vs. Colectivos:** Servicios es la programación de horarios/turnos; Colectivos es la operación diaria con recaudación y cierre.
- **Camión:** neto = tarifa × kilos / 1000; IVA = neto × 21 %; total = neto + IVA; comisión chofer = neto × 15 % (configurable).
- **Cierre:** se registra el efectivo entregado y la diferencia contra el sobrante calculado.
- **Alertas:** vencimientos de mantenimiento, servicios programados/presupuestados, servicios abiertos y servicios con sobrante negativo. Las alertas de vencimiento permiten **Programar** directamente un nuevo servicio para el coche/camión.
- **Flujo de mantenimiento:** programar (fecha, vehículo, taller, presupuesto) → presupuestar → **Marcar realizado**. Al marcarlo, queda en el historial como servicio realizado y se usa para el próximo vencimiento.

Ver detalle en [`docs/reportes.md`](docs/reportes.md).

---

## 6. Roles y módulos

| Rol | Permisos |
|---|---|
| `superadmin` | Todo, empresas y superadmins |
| `admin` | Todo dentro de su empresa, usuarios y configuración |
| `supervisor` | Operación, maestros, reportes e importes |
| `operator` | Operación sin importes ni reportes por defecto |
| `viewer` | Solo lectura de la operación, sin importes ni reportes por defecto |

Además del rol, cada usuario tiene **módulos permitidos**. Se asignan en **Maestros → Usuarios** y controlan el menú, las pestañas y el acceso a la API. Un usuario puede tener, por ejemplo, solo el módulo Colectivos.

El permiso **“Ver importes y recaudación”** es independiente de los módulos. Si está desmarcado, la web oculta montos/totales y el backend elimina los campos monetarios de las respuestas; los reportes y exportaciones responden 403. Por defecto lo tienen `superadmin`, `admin` y `supervisor`; `operator` y `viewer` no.

Ver detalle y valores por defecto en [`docs/permisos.md`](docs/permisos.md).

---

## 7. Seguridad y operación

- Las claves se almacenan con **bcrypt** vía `pgcrypto` (`crypt`/`gen_salt`).
- Sesiones con token aleatorio, hash SHA-256 en base y cookie `HttpOnly`/`SameSite=Lax`.
- Todas las escrituras quedan en `audit_log`.
- El servidor está pensado para LAN. Para exponerlo a Internet: HTTPS, firewall, backups y cambiar las claves demo.
- Backup sugerido:

```powershell
& 'C:\Program Files\PostgreSQL\16\bin\pg_dump.exe' -U postgres -Fc union_transporte > union_transporte.dump
```

---

## 8. Estado y próximos pasos

Implementado: autenticación, roles, auditoría, maestros con talleres y teléfonos, servicios con combustible/gastos, cierre, combustible, gastos, mantenimiento con flujo **programar → presupuestar → marcar realizado**, alertas del dashboard con acceso directo a programar el servicio, listado completo de alertas, camión con remitos, reportes diario/mensual, CSV, impresión/PDF, migración de la planilla.

Pendiente / recomendado:

- Selector de empresa para superadmin (el backend ya es multiempresa).
- Importador de Excel desde la web (hoy es CLI: `tools/import_planilla.py`).
- PDF generado en servidor (hoy se imprime desde el navegador).
- HTTPS y despliegue como servicio de Windows (NSSM).
- Tests automatizados de reglas de negocio.
