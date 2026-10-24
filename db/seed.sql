-- ============================================================
-- UNION - Seed generado desde PLANILLAS PROGRAMADOR.xlsx
-- Generado por tools/import_planilla.py
-- ============================================================
BEGIN;
TRUNCATE audit_log, sessions, service_closings, service_expenses,
         fuel_loads, freight_items, freight_trips, maintenance, workshops,
         services, service_schedules, routes, vehicles, employees, settings, users, companies
         RESTART IDENTITY CASCADE;

-- Empresa
INSERT INTO companies (id, name, legal_name, cuit, address, phone, email) VALUES
  (1, 'Empresa Unión', 'De LS Transporte SRL', '33-71544123-9',
   'Misiones, Argentina', NULL, NULL);

-- Usuarios (cambiar claves al primer ingreso)
INSERT INTO users (id, company_id, username, full_name, email, password_hash, role, must_change_password) VALUES
  (1, 1, 'admin', 'Administrador', NULL,
   crypt('Admin123!', gen_salt('bf', 12)), 'superadmin', TRUE),
  (2, 1, 'operador', 'Operador de Tráfico', NULL,
   crypt('Operador123!', gen_salt('bf', 12)), 'operator', TRUE),
  (3, 1, 'consulta', 'Consulta / Auditoría', NULL,
   crypt('Consulta123!', gen_salt('bf', 12)), 'viewer', TRUE);

-- Configuración
INSERT INTO settings (company_id, key, value) VALUES
  (1, 'currency', 'ARS'),
  (1, 'vat_pct', '21'),
  (1, 'commission_pct', '15'),
  (1, 'maintenance_alert_days', '15'),
  (1, 'company_display_name', 'Empresa Unión');

-- Empleados
INSERT INTO employees (id, company_id, full_name, dni, kind, license, phone) VALUES
  (1, 1, 'Ezequiel G.', NULL, 'driver', NULL, NULL),
  (2, 1, 'Doprado', NULL, 'driver', NULL, NULL),
  (3, 1, 'Pereira Daniel', NULL, 'driver', NULL, NULL),
  (4, 1, 'Sosa', NULL, 'guard', NULL, NULL);

-- Vehículos
INSERT INTO vehicles (id, company_id, kind, internal_no, model, odometer) VALUES
  (1, 1, 'bus', '58', 'Coche 58', 0),
  (2, 1, 'bus', '70', 'Coche 70', 0),
  (3, 1, 'bus', '72', 'Coche 72', 0),
  (4, 1, 'truck', '4', 'Camión 4', 0);

-- Rutas
INSERT INTO routes (id, company_id, code, name, origin, destination, distance_km) VALUES
  (1, 1, 'SJ-PS', 'San Javier - Posadas', 'San Javier', 'Posadas', 130);

-- Servicios (Libro Diario Colectivos)
INSERT INTO services (id, company_id, service_date, route_id, vehicle_id, driver_id, guard_id,
  departure_time, schedule_label, km, ticket_from, ticket_to, fare_total, status,
  closed_at, closed_by, created_by, direction, return_of_id) VALUES
  (1, 1, '2025-05-01', 1, 2, 1, 4, '06:50:00', 'IDA 06.50 SJ-PS', 130.0, 11746, 11760, 154000.0, 'closed', '2025-05-01'::timestamp + time '23:59', 1, 1, 'ida', NULL),
  (2, 1, '2025-05-01', 1, 2, 1, 4, '11:20:00', 'VTA 11.20 PS-SJ', 130.0, 11761, 11797, 412600.0, 'closed', '2025-05-01'::timestamp + time '23:59', 1, 1, 'vuelta', 1),
  (3, 1, '2025-05-01', 1, 1, 1, 4, '13:50:00', 'IDA 13.50 SJ-PS', 130.0, 11798, 11823, 233600.0, 'closed', '2025-05-01'::timestamp + time '23:59', 1, 1, 'ida', NULL),
  (4, 1, '2025-05-01', 1, 1, 1, 4, '17:30:00', 'VTA 17.30 PS-SJ', 130.0, 11824, 11873, 475250.0, 'closed', '2025-05-01'::timestamp + time '23:59', 1, 1, 'vuelta', 3),
  (5, 1, '2025-05-02', 1, 1, 1, 4, '04:50:00', 'IDA 4.50 SJ-PS', 130.0, 11874, 11897, 121800.0, 'closed', '2025-05-02'::timestamp + time '23:59', 1, 1, 'ida', NULL),
  (6, 1, '2025-05-02', 1, 1, 1, 4, '09:50:00', 'VTA 9.50 PS-SJ', 130.0, 11898, 11921, 151200.0, 'closed', '2025-05-02'::timestamp + time '23:59', 1, 1, 'vuelta', 5),
  (7, 1, '2025-05-02', 1, 2, 2, 4, '12:45:00', 'IDA 12.45 SJ-PS', 130.0, 11922, 11942, 133700.0, 'closed', '2025-05-02'::timestamp + time '23:59', 1, 1, 'ida', NULL),
  (8, 1, '2025-05-02', 1, 2, 2, 4, '16:15:00', 'VTA 16.15 PS - SJ', 130.0, 11943, 12000, 367200.0, 'closed', '2025-05-02'::timestamp + time '23:59', 1, 1, 'vuelta', 7);

-- Programación de servicios (horarios/turnos) derivada del libro diario
INSERT INTO service_schedules (company_id, route_id, direction, departure_time, vehicle_id, driver_id, guard_id)
SELECT DISTINCT company_id, route_id, direction, departure_time, vehicle_id, driver_id, guard_id
FROM services;
UPDATE services s SET schedule_id = sc.id
FROM service_schedules sc
WHERE sc.company_id = s.company_id AND sc.route_id = s.route_id
  AND sc.direction = s.direction AND sc.departure_time = s.departure_time
  AND sc.vehicle_id = s.vehicle_id;

-- Combustible vinculado a cada servicio
INSERT INTO fuel_loads (company_id, vehicle_id, service_id, load_date, liters,
  price_per_liter, amount, odometer, full_tank, station, notes, created_by) VALUES
  (1, 2, 2, '2025-05-01', 0.0, 0, 59200.0, NULL, FALSE, NULL, 'Importado planilla', 1),
  (1, 1, 6, '2025-05-02', 187.02, 1256.55, 235000.0, NULL, FALSE, NULL, 'Importado planilla', 1),
  (1, 2, 8, '2025-05-02', 141.61, 1256.97, 178000.0, NULL, FALSE, NULL, 'Importado planilla', 1);

-- Gastos / deducciones del servicio
INSERT INTO service_expenses (company_id, service_id, vehicle_id, expense_date,
  category, description, amount, created_by) VALUES
  (1, 1, 2, '2025-05-01', 'ticket_office', 'Boleterías', 6800.0, 1),
  (1, 1, 2, '2025-05-01', 'mp', 'Mercado Pago', 7400.0, 1),
  (1, 1, 2, '2025-05-01', 'other', 'Otros', 17100.0, 1),
  (1, 2, 2, '2025-05-01', 'ticket_office', 'Boleterías', 20660.0, 1),
  (1, 2, 2, '2025-05-01', 'mp', 'Mercado Pago', 20700.0, 1),
  (1, 2, 2, '2025-05-01', 'other', 'Otros', 15000.0, 1),
  (1, 3, 1, '2025-05-01', 'ticket_office', 'Boleterías', 10300.0, 1),
  (1, 3, 1, '2025-05-01', 'other', 'Otros', 8100.0, 1),
  (1, 4, 1, '2025-05-01', 'ticket_office', 'Boleterías', 17610.0, 1),
  (1, 4, 1, '2025-05-01', 'mp', 'Mercado Pago', 25900.0, 1),
  (1, 4, 1, '2025-05-01', 'other', 'Otros', 28750.0, 1),
  (1, 5, 1, '2025-05-02', 'ticket_office', 'Boleterías', 1000.0, 1),
  (1, 5, 1, '2025-05-02', 'mp', 'Mercado Pago', 9700.0, 1),
  (1, 5, 1, '2025-05-02', 'other', 'Otros', 8900.0, 1),
  (1, 6, 1, '2025-05-02', 'ticket_office', 'Boleterías', 6700.0, 1),
  (1, 6, 1, '2025-05-02', 'other', 'Otros', 5300.0, 1),
  (1, 7, 2, '2025-05-02', 'ticket_office', 'Boleterías', 3800.0, 1),
  (1, 7, 2, '2025-05-02', 'mp', 'Mercado Pago', 10000.0, 1),
  (1, 7, 2, '2025-05-02', 'other', 'Otros', 6800.0, 1),
  (1, 8, 2, '2025-05-02', 'oncology', 'Oncológico', 5500.0, 1),
  (1, 8, 2, '2025-05-02', 'ticket_office', 'Boleterías', 4550.0, 1),
  (1, 8, 2, '2025-05-02', 'mp', 'Mercado Pago', 13000.0, 1),
  (1, 8, 2, '2025-05-02', 'other', 'Otros', 6100.0, 1);

-- Mantenimiento (REPARACIONES - Coche 72)
INSERT INTO maintenance (company_id, vehicle_id, maintenance_date, category,
  concept, measures, next_due, odometer, cost, notes, created_by) VALUES
  (1, 3, '2024-07-25', 'LUBRICANTES Y FILTROS', 'Aceite de motor y filtro', NULL, '2025-01-25', NULL, 0, NULL, 1),
  (1, 3, '2024-07-25', 'LUBRICANTES Y FILTROS', 'filtro de aire', NULL, '2025-01-25', NULL, 0, NULL, 1),
  (1, 3, '2024-07-25', 'LUBRICANTES Y FILTROS', 'filtro de gasoil y trampa de agua', NULL, '2025-01-25', NULL, 0, NULL, 1),
  (1, 3, '2024-07-25', 'CUBIERTAS', 'cubiertas delanteras nuevas', NULL, NULL, NULL, 0, NULL, 1),
  (1, 3, '2024-08-20', 'CUBIERTAS', 'cubiertas trasera izqueirda recapada', NULL, NULL, NULL, 0, NULL, 1),
  (1, 3, '2024-11-07', 'CAJA Y EMBRAGUE', 'se reparo el servo', NULL, NULL, NULL, 0, NULL, 1),
  (1, 3, '2024-11-07', 'mecanica en gral', 'se levantaron masas delanteras- bien', NULL, '2024-12-07', NULL, 0, NULL, 1),
  (1, 3, '2024-11-07', 'mecanica en gral', 'se levanto eje y se reviso cardan - bien', NULL, '2024-12-07', NULL, 0, NULL, 1),
  (1, 3, '2025-02-20', 'Aire Acondicionado', 'se reparo completo el aire acondicionado', 'marcelo', NULL, NULL, 0, NULL, 1),
  (1, 3, '2025-04-20', 'LUBRICANTES Y FILTROS', 'Aceite de motor y filtro', NULL, '2025-11-05', NULL, 0, NULL, 1),
  (1, 3, '2025-04-20', 'LUBRICANTES Y FILTROS', 'filtro de gasoil y trampa de agua', NULL, '2025-11-05', NULL, 0, NULL, 1),
  (1, 3, '2025-07-20', 'CARROCERÍA', 'Chapa y Pintura Completo, Chapas nuevas todo', NULL, NULL, NULL, 0, NULL, 1),
  (1, 3, '2025-09-04', 'CUBIERTAS', 'Cubiertas Trasera Der. Rec. (Vienen del 36 de atrás) Tipo Taco Fontana', 'Michelin 1° Rec. Tipo Taco', '2025-10-04', NULL, 0, NULL, 1),
  (1, 3, '2025-09-28', 'MECÁNICA EN GRAL.', 'Extremo Dirección - Brazo Corto Arriba del Eje', 'Cono 27, Rosca 32 Izq.', NULL, NULL, 0, NULL, 1),
  (1, 3, '2025-09-28', 'MECÁNICA EN GRAL.', 'se levantaron masas delanteras- bien', NULL, '2025-10-30', NULL, 0, NULL, 1),
  (1, 3, '2025-10-08', 'MECÁNICA EN GRAL.', 'Ruleman de Cardan Nuevo con Goma, el del primer tramo', NULL, NULL, NULL, 0, NULL, 1),
  (1, 3, '2025-10-14', 'CUBIERTAS', 'Cubiertas Tras. Izq. Recapadas Nuevas Tipo Taco Fontana', 'Michelin 1° Rec. Tipo Taco', '2025-11-20', NULL, 0, NULL, 1),
  (1, 3, '2025-10-14', 'CUBIERTAS', 'Rotación Cubiertas Delanteras - ambas sobre llantas (Gasta más Hombro Interno)', 'Continental', '2025-11-14', NULL, 0, NULL, 1);

-- Camión: viajes y remitos (Planilla CAMION)
INSERT INTO freight_trips (id, company_id, trip_date, vehicle_id, driver_id, km, commission_pct, notes, created_by) VALUES
  (1, 1, '2025-03-15', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (2, 1, '2025-03-16', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (3, 1, '2025-03-17', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (4, 1, '2025-03-18', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (5, 1, '2025-03-19', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (6, 1, '2025-03-20', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (7, 1, '2025-03-21', 4, 3, 0, 15, 'Importado Planilla CAMION', 1),
  (8, 1, '2025-03-26', 4, 3, 211.0, 15, 'Importado Planilla CAMION', 1),
  (9, 1, '2025-03-27', 4, 3, 99.0, 15, 'Importado Planilla CAMION', 1),
  (10, 1, '2025-03-29', 4, 3, 211.0, 15, 'Importado Planilla CAMION', 1),
  (11, 1, '2025-03-31', 4, 3, 0, 15, 'Importado Planilla CAMION', 1);

INSERT INTO freight_items (trip_id, remito, origin, destination, kilos, tariff, vat_pct, commission_pct) VALUES
  (1, '0005-9136', 'Santa Maria', 'Acontimber', 29699.0, 13000.0, 21, 15),
  (1, '001-14600', 'San Juan Cora', 'Acontimber', 27300.0, 15487.5, 21, 15),
  (2, '001-14659', 'San Juan Cora', 'Acontimber', 28500.0, 15487.5, 21, 15),
  (3, '005-9141', 'Santa Maria', 'Acontimber', 29620.0, 13000.0, 21, 15),
  (4, '005-9160', 'Santa Maria', 'Acontimber', 29619.0, 13000.0, 21, 15),
  (4, '022-22351', 'La Blanca', 'Acontimber', 29780.0, 5420.74, 21, 15),
  (5, '022-22353', 'La Blanca', 'Acontimber', 29480.0, 5420.74, 21, 15),
  (5, '005-9175', 'Santa Maria', 'Acontimber', 29920.0, 13000.0, 21, 15),
  (6, '005-9178', 'Santa Maria', 'Acontimber', 24960.0, 13000.0, 21, 15),
  (6, '022-22363', 'La Blanca', 'Acontimber', 29080.0, 5420.74, 21, 15),
  (7, '001-11857', 'San Charbel (Ruta 68)', 'Acontimber', 28920.0, 5420.74, 21, 15),
  (8, '005-9213', 'Santa Maria', 'Acontimber', 29820.0, 13000.0, 21, 15),
  (8, '0001-11874', 'San Charbel (Ruta 68)', 'Acontimber', 29820.0, 5420.74, 21, 15),
  (9, '006-2351', 'San Charbel (EL Boga)', 'Acontimber', 29780.0, 5420.74, 21, 15),
  (10, '005-9235', 'Santa Maria', 'Acontimber', 29200.0, 13000.0, 21, 15),
  (11, '005-9244', 'Santa Maria', 'Acontimber', 27900.0, 13000.0, 21, 15);

-- Ajuste de secuencias
SELECT setval(pg_get_serial_sequence('companies', 'id'), COALESCE((SELECT MAX(id) FROM companies), 1));
SELECT setval(pg_get_serial_sequence('users', 'id'), COALESCE((SELECT MAX(id) FROM users), 1));
SELECT setval(pg_get_serial_sequence('employees', 'id'), COALESCE((SELECT MAX(id) FROM employees), 1));
SELECT setval(pg_get_serial_sequence('vehicles', 'id'), COALESCE((SELECT MAX(id) FROM vehicles), 1));
SELECT setval(pg_get_serial_sequence('routes', 'id'), COALESCE((SELECT MAX(id) FROM routes), 1));
SELECT setval(pg_get_serial_sequence('services', 'id'), COALESCE((SELECT MAX(id) FROM services), 1));
SELECT setval(pg_get_serial_sequence('service_schedules', 'id'), COALESCE((SELECT MAX(id) FROM service_schedules), 1));
SELECT setval(pg_get_serial_sequence('maintenance', 'id'), COALESCE((SELECT MAX(id) FROM maintenance), 1));
SELECT setval(pg_get_serial_sequence('freight_trips', 'id'), COALESCE((SELECT MAX(id) FROM freight_trips), 1));
COMMIT;

-- Resumen de la importación
SELECT 'servicios' AS tabla, COUNT(*) FROM services
UNION ALL SELECT 'combustible', COUNT(*) FROM fuel_loads
UNION ALL SELECT 'gastos', COUNT(*) FROM service_expenses
UNION ALL SELECT 'mantenimiento', COUNT(*) FROM maintenance
UNION ALL SELECT 'viajes camión', COUNT(*) FROM freight_trips
UNION ALL SELECT 'remitos', COUNT(*) FROM freight_items;