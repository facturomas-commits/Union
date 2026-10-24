# Modelo de datos

Base: `union_transporte` (PostgreSQL 16). Todas las tablas operativas tienen `company_id` para soporte multiempresa.

## Relaciones principales

```
companies
  ├── users ─────────────── sessions
  │      └── audit_log
  ├── employees (driver | guard | other)
  │      ├── services.driver_id
  │      ├── services.guard_id
  │      └── freight_trips.driver_id
  ├── vehicles (bus | truck | other)
  │      ├── services
  │      ├── fuel_loads
  │      ├── maintenance
  │      └── freight_trips
  ├── routes
  │      └── services
  └── settings
services
  ├── fuel_loads (1 carga vinculada por servicio)
  ├── service_expenses (oncology | ticket_office | mp | other)
  └── service_closings (1 cierre por servicio)
freight_trips
  └── freight_items (remitos)
```

## Tablas

| Tabla | Propósito | Campos clave |
|---|---|---|
| `companies` | Empresa | `name`, `legal_name`, `cuit` |
| `users` | Usuarios del sistema | `username`, `password_hash` (bcrypt), `role`, `active` |
| `sessions` | Sesiones activas | `token_hash` (SHA-256), `expires_at` |
| `audit_log` | Trazabilidad | `action`, `entity`, `entity_id`, `details` (JSONB), `ip` |
| `settings` | Configuración por empresa | `maintenance_alert_days`, `vat_pct`, `commission_pct` |
| `employees` | Choferes y guardas | `kind` (`driver`/`guard`), `full_name`, `dni` |
| `vehicles` | Colectivos y camiones | `kind` (`bus`/`truck`), `internal_no`, `plate`, `odometer` |
| `routes` | Rutas / líneas | `code`, `origin`, `destination`, `distance_km` |
| `services` | Servicio diario de colectivo | `service_date`, `route_id`, `vehicle_id`, `driver_id`, `guard_id`, `departure_time`, `km`, `ticket_from`, `ticket_to`, `fare_total`, `status` |
| `fuel_loads` | Cargas de gasoil | `vehicle_id`, `service_id`, `load_date`, `liters`, `amount`, `full_tank`, `odometer` |
| `service_expenses` | Deducciones del servicio | `category`, `amount`, `service_id` |
| `service_closings` | Cierre de caja | `cash_delivered`, `surplus`, `difference` |
| `maintenance` | Mantenimiento | `maintenance_date`, `category`, `concept`, `next_due`, `cost` |
| `freight_trips` | Viaje de camión | `trip_date`, `vehicle_id`, `driver_id`, `km`, `commission_pct` |
| `freight_items` | Remito del viaje | `remito`, `origin`, `destination`, `kilos`, `tariff`, importes calculados |

## Campos calculados

En `freight_items` (columnas generadas por PostgreSQL):

```
net_amount        = round(tariff * kilos / 1000, 2)
vat_amount        = round(round(tariff * kilos / 1000, 2) * vat_pct / 100, 2)
total_amount      = net_amount + vat_amount
driver_commission = round(net_amount * commission_pct / 100, 2)
```

En las vistas de reporte:

```
tickets_count = ticket_to - ticket_from + 1
surplus       = fare_total - gasoil - oncológico - boleterías - MP - otros
```

## Vistas

| Vista | Uso |
|---|---|
| `v_services` | Servicios con nombres, agregados de combustible/gastos y sobrante |
| `v_fuel_loads` | Combustible con vehículo y servicio |
| `v_expenses` | Gastos con servicio/vehículo |
| `v_maintenance` | Mantenimiento con `days_left` |
| `v_freight_trips` | Viajes con totales agregados de remitos |
| `v_freight_items` | Remitos con fecha, vehículo y chofer |
| `v_users` | Usuarios sin hash de clave |
| `v_vehicles`, `v_employees`, `v_routes` | Maestros con empresa |

## Índices relevantes

- `services(company_id, service_date DESC)`
- `services(vehicle_id, service_date DESC)`
- `fuel_loads(company_id, load_date DESC)`
- `maintenance(next_due) WHERE next_due IS NOT NULL`
- `freight_trips(company_id, trip_date DESC)`
- `audit_log(company_id, created_at DESC)`

## Decisiones

- Un servicio puede tener **una** carga de combustible vinculada (índice único parcial). Las cargas no vinculadas se registran por vehículo.
- Las deducciones del servicio se guardan como filas en `service_expenses` para poder auditar cada categoría.
- El cierre guarda una foto de los importes para conservar historia aunque luego se edite el servicio.
- Las bajas de maestros son lógicas (`active = false`); las operaciones se eliminan con cascada controlada.
