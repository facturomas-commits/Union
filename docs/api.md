# API REST

Base: `http://localhost:9020/api`

Autenticación por cookie `union_session` (HttpOnly) o cabecera `Authorization: Bearer <token>`.
Todas las respuestas son JSON. Errores: `{ "error": "mensaje" }`.

## Autenticación

| Método | Ruta | Descripción |
|---|---|---|
| POST | `/auth/login` | `{username, password}` → token, usuario y `modules` |
| POST | `/auth/logout` | Cierra sesión |
| GET | `/auth/me` | Usuario, empresa, configuración y `modules` |
| POST | `/auth/change-password` | `{current_password, new_password}` |

Los endpoints de cada módulo verifican `allowed_modules`. Si el módulo no está permitido, responden **403**.

## Maestros

| Método | Ruta |
|---|---|
| GET/POST | `/vehicles` |
| GET/PUT/DELETE | `/vehicles/:id` |
| GET/POST | `/employees?kind=driver|guard` |
| GET/PUT/DELETE | `/employees/:id` |
| GET/POST | `/routes` |
| GET/PUT/DELETE | `/routes/:id` |
| GET/POST | `/users` (admin) |
| PUT/DELETE | `/users/:id` (admin) || GET/POST | `/companies` (admin/super) |
| PUT/DELETE | `/companies/:id` (super) |
| GET/POST | `/settings` (admin) |

`POST/PUT /users` acepta `allowed_modules: ["dashboard","colectivos", ...]`. Si se envía `null` o se omite, se usan los módulos por defecto del rol.

## Programación de servicios

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/schedules?route_id&direction&active=1` | Horarios/turnos programados |
| GET/PUT/DELETE | `/schedules/:id` | Detalle / edición / baja lógica |
| POST | `/schedules` | Alta de horario (ruta, dirección, hora, coche, chofer, guarda) |

La ida y la vuelta son horarios separados dentro de la misma ruta.

## Operación

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/services?date_from&date_to&vehicle_id&status` | Lista |
| GET | `/services/:id` | Servicio + combustible + gastos |
| POST | `/services` | Alta con combustible/gastos anidados |
| PUT | `/services/:id` | Edición |
| DELETE | `/services/:id` | Baja |
| POST | `/services/:id/close` | Cierre con `cash_delivered` |
| POST | `/services/:id/reopen` | Reapertura |
| GET/POST | `/fuel` | Combustible |
| GET/PUT/DELETE | `/fuel/:id` | |
| GET/POST | `/expenses` | Gastos |
| PUT/DELETE | `/expenses/:id` | |
| GET | `/maintenance?vehicle_id&due=1&days=15` | Mantenimiento |
| GET/POST | `/maintenance` | |
| GET/PUT/DELETE | `/maintenance/:id` | |

## Camión

| Método | Ruta |
|---|---|
| GET | `/freight/trips?date_from&date_to&vehicle_id` |
| GET | `/freight/trips/:id` (viaje + remitos) |
| POST | `/freight/trips` (con `items[]`) |
| PUT/DELETE | `/freight/trips/:id` |
| GET | `/freight/items?trip_id=` |
| POST | `/freight/items` |
| PUT/DELETE | `/freight/items/:id` |

## Reportes

| Método | Ruta | Descripción |
|---|---|---|
| GET | `/reports/daily?date=YYYY-MM-DD` | Reporte diario completo |
| GET | `/reports/monthly?month=YYYY-MM` | Reporte mensual |
| GET | `/reports/maintenance-due?days=15` | Vencimientos |
| GET | `/reports/latest` | Última fecha con datos |
| GET | `/reports/audit?limit=200` | Auditoría (admin) |
| GET | `/reports/export/daily.csv?date=` | CSV diario |
| GET | `/reports/export/monthly.csv?month=` | CSV mensual |
| GET | `/dashboard?date=` | Dashboard |

## Ejemplos

### Alta de servicio

```json
POST /api/services
{
  "service_date": "2026-10-24",
  "route_id": 1,
  "vehicle_id": 1,
  "driver_id": 1,
  "guard_id": 4,
  "departure_time": "06:50",
  "schedule_label": "IDA 06.50 SJ-PS",
  "direction": "ida",
  "create_return": true,
  "return_departure_time": "11:20",
  "km": 130,
  "ticket_from": 20001,
  "ticket_to": 20040,
  "fare_total": 154000,
  "fuel_amount": 59200,
  "fuel_liters": 47.5,
  "full_tank": true,
  "oncology_amount": 0,
  "ticket_office_amount": 6800,
  "mp_amount": 7400,
  "other_amount": 17100
}
```

### Alta de viaje de camión

```json
POST /api/freight/trips
{
  "trip_date": "2026-10-24",
  "vehicle_id": 4,
  "driver_id": 3,
  "km": 211,
  "commission_pct": 15,
  "items": [
    {
      "remito": "005-9136",
      "origin": "Santa María",
      "destination": "Acontimber",
      "kilos": 29699,
      "tariff": 13000
    }
  ]
}
```

### Respuesta de reporte diario

```json
{
  "date": "2025-05-02",
  "services": [ ... ],
  "totals": {
    "services": 4, "revenue": 773900, "fuel_amount": 413000,
    "oncology_amount": 5500, "ticket_office_amount": 16050,
    "mp_amount": 32700, "other_amount": 27100,
    "surplus": 279550, "km": 520, "tickets": 127, "open_services": 0
  },
  "freight": [],
  "freight_totals": { "trips": 0, "kilos": 0, "net_amount": 0, ... },
  "maintenance": [],
  "maintenance_total": 0,
  "alerts": [ ... ],
  "consolidated": {
    "bus_revenue": 773900, "bus_surplus": 279550,
    "total_income_net": 773900, "total_costs": 494350,
    "margin": 279550, "total_km": 520, ...
  }
}
```
