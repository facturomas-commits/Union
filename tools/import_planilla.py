#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Importa PLANILLAS PROGRAMADOR.xlsx al modelo relacional de UNION.

Genera db/seed.sql con:
  - empresa, usuarios, settings
  - empleados, coches/camión, rutas
  - servicios diarios (hoja 1) + combustible + gastos
  - mantenimiento (hoja 2)
  - viajes/remitos del camión (hoja 3)

Uso:
  python tools/import_planilla.py
  psql -U postgres -d union_transporte -f db/seed.sql
"""
from __future__ import annotations

import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
XLSX = ROOT / "PLANILLAS PROGRAMADOR.xlsx"
OUT = ROOT / "db" / "seed.sql"
NS = "{http://schemas.openxmlformats.org/spreadsheetml/2006/main}"


def excel_date(value):
    if value in (None, ""):
        return None
    return (datetime(1899, 12, 30) + timedelta(days=float(value))).date()


def to_num(value, default=0.0):
    if value in (None, ""):
        return default
    try:
        return float(str(value).replace(",", "."))
    except ValueError:
        return default


def to_int(value, default=None):
    if value in (None, ""):
        return default
    try:
        return int(float(value))
    except ValueError:
        return default


def sql_str(value):
    if value is None:
        return "NULL"
    return "'" + str(value).replace("'", "''") + "'"


def sql_date(value):
    return "NULL" if value is None else "'" + value.isoformat() + "'"


def parse_time(label: str):
    m = re.search(r"(\d{1,2})[.:](\d{2})", label or "")
    if not m:
        return None
    return f"{int(m.group(1)):02d}:{m.group(2)}:00"


class Workbook:
    def __init__(self, path: Path):
        self.z = zipfile.ZipFile(path)
        ss = ET.fromstring(self.z.read("xl/sharedStrings.xml"))
        self.strings = [
            "".join(t.text or "" for t in si.iter(NS + "t"))
            for si in ss.findall(NS + "si")
        ]

    def sheet(self, index: int):
        root = ET.fromstring(self.z.read(f"xl/worksheets/sheet{index}.xml"))
        rows = {}
        for row in root.iter(NS + "row"):
            cells = {}
            for c in row.findall(NS + "c"):
                ref = c.attrib.get("r", "")
                col = re.match(r"([A-Z]+)", ref)
                if not col:
                    continue
                t = c.attrib.get("t")
                v = c.find(NS + "v")
                isel = c.find(NS + "is")
                if t == "s" and v is not None:
                    val = self.strings[int(v.text)]
                elif t == "inlineStr" and isel is not None:
                    val = "".join(x.text or "" for x in isel.iter(NS + "t"))
                elif v is not None:
                    val = v.text
                else:
                    val = None
                cells[col.group(1)] = val
            rows[int(row.attrib.get("r", "0"))] = cells
        return rows


def main():
    if not XLSX.exists():
        sys.exit(f"No existe {XLSX}")
    wb = Workbook(XLSX)
    s1 = wb.sheet(1)
    s2 = wb.sheet(2)
    s3 = wb.sheet(3)

    out = []
    add = out.append
    add("-- ============================================================")
    add("-- UNION - Seed generado desde PLANILLAS PROGRAMADOR.xlsx")
    add("-- Generado por tools/import_planilla.py")
    add("-- ============================================================")
    add("BEGIN;")
    add("TRUNCATE audit_log, sessions, service_closings, service_expenses,")
    add("         fuel_loads, freight_items, freight_trips, maintenance,")
    add("         services, service_schedules, routes, vehicles, employees, settings, users, companies")
    add("         RESTART IDENTITY CASCADE;")
    add("")

    # ---------------- Empresa ----------------
    add("-- Empresa")
    add("INSERT INTO companies (id, name, legal_name, cuit, address, phone, email) VALUES")
    add("  (1, 'Empresa Unión', 'De LS Transporte SRL', '33-71544123-9',")
    add("   'Misiones, Argentina', NULL, NULL);")
    add("")

    # ---------------- Usuarios ----------------
    add("-- Usuarios (cambiar claves al primer ingreso)")
    add("INSERT INTO users (id, company_id, username, full_name, email, password_hash, role, must_change_password) VALUES")
    add("  (1, 1, 'admin', 'Administrador', NULL,")
    add("   crypt('Admin123!', gen_salt('bf', 12)), 'superadmin', FALSE),")
    add("  (2, 1, 'operador', 'Operador de Tráfico', NULL,")
    add("   crypt('Operador123!', gen_salt('bf', 12)), 'operator', TRUE),")
    add("  (3, 1, 'consulta', 'Consulta / Auditoría', NULL,")
    add("   crypt('Consulta123!', gen_salt('bf', 12)), 'viewer', TRUE);")
    add("")

    add("-- Configuración")
    add("INSERT INTO settings (company_id, key, value) VALUES")
    add("  (1, 'currency', 'ARS'),")
    add("  (1, 'vat_pct', '21'),")
    add("  (1, 'commission_pct', '15'),")
    add("  (1, 'maintenance_alert_days', '15'),")
    add("  (1, 'company_display_name', 'Empresa Unión');")
    add("")

    # ---------------- Empleados ----------------
    employees = [
        # id, nombre, dni, kind, licencia, telefono
        (1, "Ezequiel G.", None, "driver", None, None),
        (2, "Doprado", None, "driver", None, None),
        (3, "Pereira Daniel", None, "driver", None, None),
        (4, "Sosa", None, "guard", None, None),
    ]
    add("-- Empleados")
    add("INSERT INTO employees (id, company_id, full_name, dni, kind, license, phone) VALUES")
    vals = []
    for eid, name, dni, kind, lic, phone in employees:
        vals.append(f"  ({eid}, 1, {sql_str(name)}, {sql_str(dni)}, {sql_str(kind)}, {sql_str(lic)}, {sql_str(phone)})")
    add(",\n".join(vals) + ";")
    add("")

    # ---------------- Vehículos ----------------
    vehicles = [
        (1, "bus", "58", "Coche 58"),
        (2, "bus", "70", "Coche 70"),
        (3, "bus", "72", "Coche 72"),
        (4, "truck", "4", "Camión 4"),
    ]
    add("-- Vehículos")
    add("INSERT INTO vehicles (id, company_id, kind, internal_no, model, odometer) VALUES")
    vals = []
    for vid, kind, no, model in vehicles:
        vals.append(f"  ({vid}, 1, {sql_str(kind)}, {sql_str(no)}, {sql_str(model)}, 0)")
    add(",\n".join(vals) + ";")
    add("")

    # ---------------- Rutas ----------------
    add("-- Rutas")
    add("INSERT INTO routes (id, company_id, code, name, origin, destination, distance_km) VALUES")
    add("  (1, 1, 'SJ-PS', 'San Javier - Posadas', 'San Javier', 'Posadas', 130);")
    add("")

    # ---------------- Servicios (hoja 1) ----------------
    add("-- Servicios (Libro Diario Colectivos)")
    service_rows = []
    fuel_rows = []
    expense_rows = []
    last_ida = {}
    for r in range(2, 10):
        row = s1.get(r, {})
        if not row.get("A"):
            continue
        sid = r - 1
        d = excel_date(row.get("A"))
        label = row.get("E", "") or ""
        t = parse_time(label)
        km = to_num(row.get("F"), 130)
        vehicle_no = row.get("G", "")
        driver = row.get("H", "") or ""
        guard = row.get("I", "") or ""
        tf = to_int(row.get("J"))
        tt = to_int(row.get("K"))
        revenue = to_num(row.get("L"))
        fuel_amount = to_num(row.get("M"))
        fuel_liters = to_num(row.get("N"))
        full_tank = str(row.get("O", "")).strip().upper() in ("SI", "SÍ", "TRUE", "1", "X")
        oncology = to_num(row.get("P"))
        ticket_office = to_num(row.get("Q"))
        mp = to_num(row.get("R"))
        other = to_num(row.get("S"))

        vid = {"58": 1, "70": 2, "72": 3, "4": 4}.get(str(vehicle_no).strip(), 1)
        did = {"Ezequiel G.": 1, "Doprado": 2, "Pereira Daniel": 3}.get(driver.strip())
        gid = {"Sosa": 4}.get(guard.strip())

        upper = label.upper().replace(" ", "")
        direction = "vuelta" if (upper.startswith("VTA") or "PS-SJ" in upper) else "ida"
        key = (d, str(vehicle_no).strip())
        return_of = "NULL"
        if direction == "ida":
            last_ida[key] = sid
        elif key in last_ida:
            return_of = str(last_ida[key])

        service_rows.append(
            f"  ({sid}, 1, {sql_date(d)}, 1, {vid}, {did if did else 'NULL'}, {gid if gid else 'NULL'}, "
            f"{sql_str(t)}, {sql_str(label)}, {km}, {tf if tf is not None else 'NULL'}, "
            f"{tt if tt is not None else 'NULL'}, {revenue}, 'closed', "
            f"{sql_date(d)}::timestamp + time '23:59', 1, 1, {sql_str(direction)}, {return_of})"
        )
        if fuel_amount > 0 or fuel_liters > 0:
            ppl = (fuel_amount / fuel_liters) if fuel_liters > 0 else 0
            fuel_rows.append(
                f"  (1, {vid}, {sid}, {sql_date(d)}, {fuel_liters}, {round(ppl, 2)}, {fuel_amount}, "
                f"NULL, {'TRUE' if full_tank else 'FALSE'}, NULL, 'Importado planilla', 1)"
            )
        for cat, amount, desc in (
            ("oncology", oncology, "Oncológico"),
            ("ticket_office", ticket_office, "Boleterías"),
            ("mp", mp, "Mercado Pago"),
            ("other", other, "Otros"),
        ):
            if amount > 0:
                expense_rows.append(
                    f"  (1, {sid}, {vid}, {sql_date(d)}, {sql_str(cat)}, {sql_str(desc)}, {amount}, 1)"
                )

    add("INSERT INTO services (id, company_id, service_date, route_id, vehicle_id, driver_id, guard_id,")
    add("  departure_time, schedule_label, km, ticket_from, ticket_to, fare_total, status,")
    add("  closed_at, closed_by, created_by, direction, return_of_id) VALUES")
    add(",\n".join(service_rows) + ";")
    add("")

    add("-- Programación de servicios (horarios/turnos) derivada del libro diario")
    add("INSERT INTO service_schedules (company_id, route_id, direction, departure_time, vehicle_id, driver_id, guard_id)")
    add("SELECT DISTINCT company_id, route_id, direction, departure_time, vehicle_id, driver_id, guard_id")
    add("FROM services;")
    add("UPDATE services s SET schedule_id = sc.id")
    add("FROM service_schedules sc")
    add("WHERE sc.company_id = s.company_id AND sc.route_id = s.route_id")
    add("  AND sc.direction = s.direction AND sc.departure_time = s.departure_time")
    add("  AND sc.vehicle_id = s.vehicle_id;")
    add("")

    if fuel_rows:
        add("-- Combustible vinculado a cada servicio")
        add("INSERT INTO fuel_loads (company_id, vehicle_id, service_id, load_date, liters,")
        add("  price_per_liter, amount, odometer, full_tank, station, notes, created_by) VALUES")
        add(",\n".join(fuel_rows) + ";")
        add("")

    if expense_rows:
        add("-- Gastos / deducciones del servicio")
        add("INSERT INTO service_expenses (company_id, service_id, vehicle_id, expense_date,")
        add("  category, description, amount, created_by) VALUES")
        add(",\n".join(expense_rows) + ";")
        add("")

    # ---------------- Mantenimiento (hoja 2) ----------------
    add("-- Mantenimiento (REPARACIONES - Coche 72)")
    maint_rows = []
    for r in range(3, 21):
        row = s2.get(r, {})
        if not row.get("A"):
            continue
        d = excel_date(row.get("A"))
        cat = row.get("B", "") or "OTROS"
        concept = row.get("C", "") or ""
        measures = row.get("D")
        next_due = excel_date(row.get("E"))
        maint_rows.append(
            f"  (1, 3, {sql_date(d)}, {sql_str(cat)}, {sql_str(concept)}, "
            f"{sql_str(measures)}, {sql_date(next_due)}, NULL, 0, NULL, 1)"
        )
    if maint_rows:
        add("INSERT INTO maintenance (company_id, vehicle_id, maintenance_date, category,")
        add("  concept, measures, next_due, odometer, cost, notes, created_by) VALUES")
        add(",\n".join(maint_rows) + ";")
        add("")

    # ---------------- Camión (hoja 3) ----------------
    add("-- Camión: viajes y remitos (Planilla CAMION)")
    trips = {}
    for r in range(3, 19):
        row = s3.get(r, {})
        if not row.get("A"):
            continue
        d = excel_date(row.get("A"))
        km = to_num(row.get("M"), 0)
        key = d
        trip = trips.setdefault(key, {"km": 0, "items": []})
        trip["km"] = max(trip["km"], km)
        trip["items"].append({
            "remito": row.get("F"),
            "origin": row.get("D"),
            "destination": row.get("E"),
            "kilos": to_num(row.get("H")),
            "tariff": to_num(row.get("G")),
        })

    trip_ids = []
    for i, (d, trip) in enumerate(sorted(trips.items()), start=1):
        trip_ids.append((i, d, trip))
    add("INSERT INTO freight_trips (id, company_id, trip_date, vehicle_id, driver_id, km, commission_pct, notes, created_by) VALUES")
    vals = []
    for tid, d, trip in trip_ids:
        vals.append(f"  ({tid}, 1, {sql_date(d)}, 4, 3, {trip['km']}, 15, 'Importado Planilla CAMION', 1)")
    add(",\n".join(vals) + ";")
    add("")

    add("INSERT INTO freight_items (trip_id, remito, origin, destination, kilos, tariff, vat_pct, commission_pct) VALUES")
    vals = []
    for tid, d, trip in trip_ids:
        for it in trip["items"]:
            vals.append(
                f"  ({tid}, {sql_str(it['remito'])}, {sql_str(it['origin'])}, {sql_str(it['destination'])}, "
                f"{it['kilos']}, {it['tariff']}, 21, 15)"
            )
    add(",\n".join(vals) + ";")
    add("")

    # ---------------- Secuencias ----------------
    add("-- Ajuste de secuencias")
    for table in ("companies", "users", "employees", "vehicles", "routes", "services",
                  "service_schedules", "maintenance", "freight_trips"):
        add(f"SELECT setval(pg_get_serial_sequence('{table}', 'id'), COALESCE((SELECT MAX(id) FROM {table}), 1));")
    add("COMMIT;")
    add("")
    add("-- Resumen de la importación")
    add("SELECT 'servicios' AS tabla, COUNT(*) FROM services")
    add("UNION ALL SELECT 'combustible', COUNT(*) FROM fuel_loads")
    add("UNION ALL SELECT 'gastos', COUNT(*) FROM service_expenses")
    add("UNION ALL SELECT 'mantenimiento', COUNT(*) FROM maintenance")
    add("UNION ALL SELECT 'viajes camión', COUNT(*) FROM freight_trips")
    add("UNION ALL SELECT 'remitos', COUNT(*) FROM freight_items;")

    OUT.write_text("\n".join(out), encoding="utf-8")
    print(f"OK -> {OUT}")
    print(f"Servicios: {len(service_rows)} | Combustible: {len(fuel_rows)} | "
          f"Gastos: {len(expense_rows)} | Mantenimiento: {len(maint_rows)} | "
          f"Viajes: {len(trip_ids)} | Remitos: {sum(len(t['items']) for _, _, t in trip_ids)}")


if __name__ == "__main__":
    main()
