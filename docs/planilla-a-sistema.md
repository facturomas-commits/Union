# De la planilla al sistema

## Módulos

| Hoja | Módulo |
|---|---|
| Libro Diario Colectivos | **Colectivos** (operación diaria) + **Servicios** (programación de horarios) |
| REPARACIONES | **Mantenimiento** |
| Planilla CAMION | **Camión** |

## Hoja 1 · Libro Diario Colectivos

| Columna planilla | Campo | Tabla |
|---|---|---|
| Fecha | `service_date` | `services` |
| Día / Periodo | derivados de la fecha | — (se calculan en reportes) |
| Línea | `route_id` | `routes` |
| Horario | `schedule_label` + `departure_time` | `services` |
| Sentido (IDA/VTA) | `direction` (`ida`/`vuelta`) | `services` |
| Retorno | `return_of_id` | `services` |
| Km. | `km` | `services` |
| Coche | `vehicle_id` (`internal_no`) | `vehicles` |
| Chofer | `driver_id` | `employees` |
| Guarda | `guard_id` | `employees` |
| Nº Boleto desde / hasta | `ticket_from` / `ticket_to` | `services` |
| Recaudac. | `fare_total` | `services` |
| Gasoil Pesos / Litros | `amount` / `liters` | `fuel_loads` |
| Lleno? | `full_tank` | `fuel_loads` |
| Oncológico | `category='oncology'` | `service_expenses` |
| Boleterías | `category='ticket_office'` | `service_expenses` |
| MP | `category='mp'` | `service_expenses` |
| Otros | `category='other'` | `service_expenses` |
| Sobró | `surplus` (vista) | `v_services` |

**Fórmula original:** `Sobró = Recaudac. − Gasoil Pesos − Oncológico − Boleterías − MP − Otros`.
Se implementó como columna calculada en `v_services`, por lo que se actualiza sola.

> En la fila con Oncológico, la planilla descontaba ese importe de Boleterías (`Q9 = 10050 - P9`). En el sistema se guardan **ambos** importes por separado y el sobrante se calcula restando los dos, dando el mismo resultado.

## Hoja 2 · REPARACIONES

| Columna | Campo |
|---|---|
| Coche 72 | `vehicle_id` |
| FECHA | `maintenance_date` |
| RUBRO | `category` |
| CONCEPTO | `concept` |
| MEDIDAS | `measures` |
| FECHA PROX. CAMBIO | `next_due` |
| (sin columna de costo) | `cost = 0` |

Los registros con `next_due` generan alertas cuando faltan menos días que `maintenance_alert_days`.

## Hoja 3 · Planilla CAMION

| Columna | Campo |
|---|---|
| Fecha | `freight_trips.trip_date` |
| Camión Nº | `freight_trips.vehicle_id` |
| Chofer | `freight_trips.driver_id` |
| Origen / Destino | `freight_items.origin` / `destination` |
| Nº Remito | `freight_items.remito` |
| Tarifa | `freight_items.tariff` |
| KILOS | `freight_items.kilos` |
| NETO | calculado: `tarifa × kilos / 1000` |
| IVA | calculado: 21 % del neto |
| Total final | calculado: neto + IVA |
| Pago Chofer 15 % | calculado: 15 % del neto |
| KM por Vuelta | `freight_trips.km` |

Cada fecha con remitos se agrupa en un **viaje**; cada fila de la planilla es un **remito**.

## Datos migrados

| Hoja | Registros |
|---|---:|
| Servicios | 8 |
| Cargas de combustible | 3 |
| Gastos / deducciones | 23 |
| Mantenimiento | 18 |
| Viajes de camión | 11 |
| Remitos | 16 |

## Regenerar la migración

```powershell
python tools\import_planilla.py
$env:PGPASSWORD='postgres'
& 'C:\Program Files\PostgreSQL\16\bin\psql.exe' -U postgres -d union_transporte -f db\seed.sql
```

El script lee el `.xlsx` sin dependencias externas (usa la librería estándar de Python) y genera `db/seed.sql`.
