# Reportes

## Reporte diario

Fuente: `v_services`, `v_freight_trips`, `v_maintenance`.

### Colectivos

| Campo | Fórmula |
|---|---|
| Boletos | `ticket_to - ticket_from + 1` |
| Recaudación | `services.fare_total` |
| Gasoil | suma de `fuel_loads` del servicio |
| Deducciones | oncológico + boleterías + Mercado Pago + otros |
| Sobrante | recaudación − gasoil − deducciones |
| Km / litros | `services.km` y litros de gasoil |
| Rendimiento | `km / litros` |
| Costo por km | `(gasoil + deducciones) / km` |
| Dirección | `ida` = origen → destino; `vuelta` = destino → origen |
| Retorno | `return_of_id` vincula la vuelta con su ida |

### Camión

| Campo | Fórmula |
|---|---|
| Neto | `Σ round(tarifa × kilos / 1000, 2)` |
| IVA | `Σ round(neto × iva_pct / 100, 2)` |
| Total | neto + IVA |
| Comisión chofer | `Σ round(neto × comisión_pct / 100, 2)` |

### Consolidado

```
Ingreso neto = recaudación colectivos + neto camión
Costos       = gasoil + deducciones + comisión camión + mantenimiento del día
Margen       = ingreso neto − costos
Km totales   = km colectivos + km camión
```

> El margen de colectivos coincide con el sobrante cuando no hay camión ni mantenimiento en la fecha.

## Reporte mensual

- Serie diaria de recaudación, sobrante, gasoil, boletos, km, camión neto y mantenimiento.
- Totales por vehículo.
- Totales por chofer.
- Consolidado del mes.

## Alertas

| Tipo | Regla |
|---|---|
| Mantenimiento | `next_due <= current_date + maintenance_alert_days` |
| Sobrante negativo | servicio del día con `surplus < 0` |
| Servicio abierto | `status = 'open'` en la fecha |

## Exportación

- **Imprimir / PDF:** botón del navegador sobre la vista de reporte (CSS de impresión A4 horizontal).
- **Excel (CSV):** descarga UTF-8 con separador `;` y decimales con coma, lista para Excel en español.

## Ejemplo de la planilla original

Hoja **Libro Diario Colectivos**, 02/05/2025:

| Recaudación | Gasoil | Oncológico | Boleterías | MP | Otros | Sobró |
|---:|---:|---:|---:|---:|---:|---:|
| 121.800 | 0 | 0 | 1.000 | 9.700 | 8.900 | 102.200 |
| 151.200 | 235.000 | 0 | 6.700 | 0 | 5.300 | -95.800 |
| 133.700 | 0 | 0 | 3.800 | 10.000 | 6.800 | 113.100 |
| 367.200 | 178.000 | 5.500 | 4.550 | 13.000 | 6.100 | 160.050 |

Los cuatro valores de **Sobró** coinciden exactamente con la planilla original.
