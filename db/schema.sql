-- ============================================================
-- UNION - Sistema de Gestión de Transporte
-- Esquema relacional PostgreSQL 16
-- ============================================================
-- Módulos:
--   companies / users / sessions / audit_log / settings
--   employees / vehicles / routes
--   services / fuel_loads / service_expenses / service_closings
--   maintenance
--   freight_trips / freight_items
--   vistas de reporte (v_services, v_freight_trips, ...)
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ------------------------------------------------------------
-- EMPRESAS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS companies (
  id            SERIAL PRIMARY KEY,
  name          VARCHAR(120) NOT NULL,
  legal_name    VARCHAR(160),
  cuit          VARCHAR(20),
  address       VARCHAR(200),
  phone         VARCHAR(40),
  email         VARCHAR(160),
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- USUARIOS / SESIONES / AUDITORÍA
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS users (
  id                    SERIAL PRIMARY KEY,
  company_id            INTEGER REFERENCES companies(id),
  username              VARCHAR(60) NOT NULL UNIQUE,
  full_name             VARCHAR(160) NOT NULL,
  email                 VARCHAR(160),
  password_hash         TEXT NOT NULL,
  role                  VARCHAR(20) NOT NULL DEFAULT 'operator'
                        CHECK (role IN ('superadmin','admin','supervisor','operator','viewer')),
  active                BOOLEAN NOT NULL DEFAULT TRUE,
  must_change_password  BOOLEAN NOT NULL DEFAULT FALSE,
  last_login            TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_users_company ON users(company_id);

CREATE TABLE IF NOT EXISTS sessions (
  token_hash  CHAR(64) PRIMARY KEY,
  user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at  TIMESTAMPTZ NOT NULL,
  ip          VARCHAR(60),
  user_agent  VARCHAR(255)
);
CREATE INDEX IF NOT EXISTS idx_sessions_user ON sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_sessions_exp  ON sessions(expires_at);

CREATE TABLE IF NOT EXISTS audit_log (
  id          BIGSERIAL PRIMARY KEY,
  company_id  INTEGER,
  user_id     INTEGER,
  username    VARCHAR(60),
  action      VARCHAR(30) NOT NULL,
  entity      VARCHAR(50) NOT NULL,
  entity_id   INTEGER,
  details     JSONB,
  ip          VARCHAR(60),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_audit_company_date ON audit_log(company_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_entity ON audit_log(entity, entity_id);

CREATE TABLE IF NOT EXISTS settings (
  company_id  INTEGER NOT NULL REFERENCES companies(id) ON DELETE CASCADE,
  key         VARCHAR(60) NOT NULL,
  value       TEXT,
  PRIMARY KEY (company_id, key)
);

-- ------------------------------------------------------------
-- MAESTROS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS employees (
  id          SERIAL PRIMARY KEY,
  company_id  INTEGER NOT NULL REFERENCES companies(id),
  full_name   VARCHAR(160) NOT NULL,
  dni         VARCHAR(20),
  kind        VARCHAR(20) NOT NULL DEFAULT 'driver'
              CHECK (kind IN ('driver','guard','other')),
  license     VARCHAR(40),
  phone       VARCHAR(40),
  address     VARCHAR(200),
  hire_date   DATE,
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_employees_company ON employees(company_id, kind);
CREATE UNIQUE INDEX IF NOT EXISTS ux_employees_dni ON employees(company_id, dni) WHERE dni IS NOT NULL AND dni <> '';

CREATE TABLE IF NOT EXISTS vehicles (
  id            SERIAL PRIMARY KEY,
  company_id    INTEGER NOT NULL REFERENCES companies(id),
  kind          VARCHAR(10) NOT NULL DEFAULT 'bus'
                CHECK (kind IN ('bus','truck','other')),
  internal_no   VARCHAR(20) NOT NULL,
  plate         VARCHAR(20),
  model         VARCHAR(80),
  model_year    INTEGER,
  seats         INTEGER,
  capacity_kg   NUMERIC(10,2),
  odometer      NUMERIC(12,1) NOT NULL DEFAULT 0,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  notes         VARCHAR(200),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (company_id, internal_no)
);
CREATE INDEX IF NOT EXISTS idx_vehicles_company ON vehicles(company_id, kind);

CREATE TABLE IF NOT EXISTS routes (
  id            SERIAL PRIMARY KEY,
  company_id    INTEGER NOT NULL REFERENCES companies(id),
  code          VARCHAR(20),
  name          VARCHAR(120) NOT NULL,
  origin        VARCHAR(120) NOT NULL,
  destination   VARCHAR(120) NOT NULL,
  distance_km   NUMERIC(10,2) NOT NULL DEFAULT 0,
  active        BOOLEAN NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_routes_company ON routes(company_id);
CREATE UNIQUE INDEX IF NOT EXISTS ux_routes_code ON routes(company_id, code) WHERE code IS NOT NULL AND code <> '';

-- ------------------------------------------------------------
-- OPERACIÓN COLECTIVOS
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS services (
  id              SERIAL PRIMARY KEY,
  company_id      INTEGER NOT NULL REFERENCES companies(id),
  service_date    DATE NOT NULL,
  route_id        INTEGER NOT NULL REFERENCES routes(id),
  vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
  driver_id       INTEGER REFERENCES employees(id),
  guard_id        INTEGER REFERENCES employees(id),
  departure_time  TIME,
  schedule_label  VARCHAR(60),
  km              NUMERIC(10,2) NOT NULL DEFAULT 0,
  ticket_from     INTEGER,
  ticket_to       INTEGER,
  fare_total      NUMERIC(14,2) NOT NULL DEFAULT 0,
  notes           VARCHAR(300),
  status          VARCHAR(20) NOT NULL DEFAULT 'open'
                  CHECK (status IN ('open','closed')),
  closed_at       TIMESTAMPTZ,
  closed_by       INTEGER REFERENCES users(id),
  created_by      INTEGER REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_ticket_range CHECK (
    ticket_from IS NULL OR ticket_to IS NULL OR ticket_to >= ticket_from
  )
);
CREATE INDEX IF NOT EXISTS idx_services_company_date ON services(company_id, service_date DESC);
CREATE INDEX IF NOT EXISTS idx_services_vehicle_date ON services(vehicle_id, service_date DESC);
CREATE INDEX IF NOT EXISTS idx_services_driver_date ON services(driver_id, service_date DESC);
CREATE INDEX IF NOT EXISTS idx_services_guard_date ON services(guard_id, service_date DESC);

CREATE TABLE IF NOT EXISTS fuel_loads (
  id              SERIAL PRIMARY KEY,
  company_id      INTEGER NOT NULL REFERENCES companies(id),
  vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
  service_id      INTEGER REFERENCES services(id) ON DELETE CASCADE,
  load_date       DATE NOT NULL,
  liters          NUMERIC(10,2) NOT NULL DEFAULT 0 CHECK (liters >= 0),
  price_per_liter NUMERIC(10,2) NOT NULL DEFAULT 0,
  amount          NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  odometer        NUMERIC(12,1),
  full_tank       BOOLEAN NOT NULL DEFAULT FALSE,
  station         VARCHAR(80),
  notes           VARCHAR(200),
  created_by      INTEGER REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_fuel_company_date ON fuel_loads(company_id, load_date DESC);
CREATE INDEX IF NOT EXISTS idx_fuel_vehicle_date ON fuel_loads(vehicle_id, load_date DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_fuel_service ON fuel_loads(service_id) WHERE service_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS service_expenses (
  id           SERIAL PRIMARY KEY,
  company_id   INTEGER NOT NULL REFERENCES companies(id),
  service_id   INTEGER REFERENCES services(id) ON DELETE CASCADE,
  vehicle_id   INTEGER REFERENCES vehicles(id),
  expense_date DATE NOT NULL,
  category     VARCHAR(30) NOT NULL
               CHECK (category IN ('oncology','ticket_office','mp','other')),
  description  VARCHAR(200),
  amount       NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  created_by   INTEGER REFERENCES users(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_expenses_company_date ON service_expenses(company_id, expense_date DESC);
CREATE INDEX IF NOT EXISTS idx_expenses_service ON service_expenses(service_id);

CREATE TABLE IF NOT EXISTS service_closings (
  id              SERIAL PRIMARY KEY,
  service_id      INTEGER NOT NULL UNIQUE REFERENCES services(id) ON DELETE CASCADE,
  revenue         NUMERIC(14,2) NOT NULL DEFAULT 0,
  fuel_amount     NUMERIC(14,2) NOT NULL DEFAULT 0,
  other_amount    NUMERIC(14,2) NOT NULL DEFAULT 0,
  surplus         NUMERIC(14,2) NOT NULL DEFAULT 0,
  cash_delivered  NUMERIC(14,2) NOT NULL DEFAULT 0,
  difference      NUMERIC(14,2) NOT NULL DEFAULT 0,
  notes           VARCHAR(300),
  closed_by       INTEGER REFERENCES users(id),
  closed_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ------------------------------------------------------------
-- MANTENIMIENTO
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maintenance (
  id                SERIAL PRIMARY KEY,
  company_id        INTEGER NOT NULL REFERENCES companies(id),
  vehicle_id        INTEGER NOT NULL REFERENCES vehicles(id),
  maintenance_date  DATE NOT NULL,
  category          VARCHAR(50) NOT NULL,
  concept           VARCHAR(200) NOT NULL,
  measures          VARCHAR(200),
  next_due          DATE,
  odometer          NUMERIC(12,1),
  cost              NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (cost >= 0),
  notes             VARCHAR(300),
  created_by        INTEGER REFERENCES users(id),
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_maint_company_date ON maintenance(company_id, maintenance_date DESC);
CREATE INDEX IF NOT EXISTS idx_maint_vehicle ON maintenance(vehicle_id, maintenance_date DESC);
CREATE INDEX IF NOT EXISTS idx_maint_due ON maintenance(next_due) WHERE next_due IS NOT NULL;

-- ------------------------------------------------------------
-- CAMIÓN / FLETES
-- ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS freight_trips (
  id              SERIAL PRIMARY KEY,
  company_id      INTEGER NOT NULL REFERENCES companies(id),
  trip_date       DATE NOT NULL,
  vehicle_id      INTEGER NOT NULL REFERENCES vehicles(id),
  driver_id       INTEGER REFERENCES employees(id),
  km              NUMERIC(10,2) NOT NULL DEFAULT 0,
  commission_pct  NUMERIC(5,2) NOT NULL DEFAULT 15
                  CHECK (commission_pct >= 0 AND commission_pct <= 100),
  notes           VARCHAR(300),
  created_by      INTEGER REFERENCES users(id),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_freight_trips_company_date ON freight_trips(company_id, trip_date DESC);
CREATE INDEX IF NOT EXISTS idx_freight_trips_vehicle ON freight_trips(vehicle_id, trip_date DESC);
CREATE INDEX IF NOT EXISTS idx_freight_trips_driver ON freight_trips(driver_id, trip_date DESC);

CREATE TABLE IF NOT EXISTS freight_items (
  id                 SERIAL PRIMARY KEY,
  trip_id            INTEGER NOT NULL REFERENCES freight_trips(id) ON DELETE CASCADE,
  remito             VARCHAR(40),
  origin             VARCHAR(120),
  destination        VARCHAR(120),
  kilos              NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (kilos >= 0),
  tariff             NUMERIC(14,2) NOT NULL DEFAULT 0 CHECK (tariff >= 0),
  vat_pct            NUMERIC(5,2) NOT NULL DEFAULT 21
                     CHECK (vat_pct >= 0 AND vat_pct <= 100),
  commission_pct     NUMERIC(5,2) NOT NULL DEFAULT 15
                     CHECK (commission_pct >= 0 AND commission_pct <= 100),
  net_amount         NUMERIC(14,2) GENERATED ALWAYS AS
                     (ROUND((tariff * kilos) / 1000.0, 2)) STORED,
  vat_amount         NUMERIC(14,2) GENERATED ALWAYS AS
                     (ROUND((ROUND((tariff * kilos) / 1000.0, 2) * vat_pct) / 100.0, 2)) STORED,
  total_amount       NUMERIC(14,2) GENERATED ALWAYS AS
                     (ROUND((tariff * kilos) / 1000.0, 2) +
                      ROUND((ROUND((tariff * kilos) / 1000.0, 2) * vat_pct) / 100.0, 2)) STORED,
  driver_commission  NUMERIC(14,2) GENERATED ALWAYS AS
                     (ROUND((ROUND((tariff * kilos) / 1000.0, 2) * commission_pct) / 100.0, 2)) STORED
);
CREATE INDEX IF NOT EXISTS idx_freight_items_trip ON freight_items(trip_id);

-- ------------------------------------------------------------
-- TRIGGER updated_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER
LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_companies_upd ON companies;
CREATE TRIGGER trg_companies_upd BEFORE UPDATE ON companies
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_users_upd ON users;
CREATE TRIGGER trg_users_upd BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_employees_upd ON employees;
CREATE TRIGGER trg_employees_upd BEFORE UPDATE ON employees
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_vehicles_upd ON vehicles;
CREATE TRIGGER trg_vehicles_upd BEFORE UPDATE ON vehicles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_routes_upd ON routes;
CREATE TRIGGER trg_routes_upd BEFORE UPDATE ON routes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_services_upd ON services;
CREATE TRIGGER trg_services_upd BEFORE UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_maint_upd ON maintenance;
CREATE TRIGGER trg_maint_upd BEFORE UPDATE ON maintenance
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
DROP TRIGGER IF EXISTS trg_freight_trips_upd ON freight_trips;
CREATE TRIGGER trg_freight_trips_upd BEFORE UPDATE ON freight_trips
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ============================================================
-- VISTAS DE LECTURA / REPORTE
-- ============================================================

CREATE OR REPLACE VIEW v_services AS
SELECT
  s.id,
  s.company_id,
  s.service_date,
  s.route_id,
  r.code            AS route_code,
  r.name            AS route_name,
  s.vehicle_id,
  v.internal_no     AS vehicle_no,
  v.plate           AS vehicle_plate,
  s.driver_id,
  d.full_name       AS driver_name,
  s.guard_id,
  g.full_name       AS guard_name,
  s.departure_time,
  s.schedule_label,
  s.km,
  s.ticket_from,
  s.ticket_to,
  CASE WHEN s.ticket_from IS NOT NULL AND s.ticket_to IS NOT NULL
       THEN GREATEST(s.ticket_to - s.ticket_from + 1, 0) ELSE 0 END AS tickets_count,
  s.fare_total      AS revenue,
  COALESCE(f.amount, 0)      AS fuel_amount,
  COALESCE(f.liters, 0)      AS fuel_liters,
  COALESCE(f.full_tank, FALSE) AS full_tank,
  COALESCE(x.oncology, 0)    AS oncology_amount,
  COALESCE(x.ticket_office, 0) AS ticket_office_amount,
  COALESCE(x.mp, 0)          AS mp_amount,
  COALESCE(x.other, 0)       AS other_amount,
  s.status,
  s.notes,
  s.closed_at,
  s.closed_by,
  s.created_by,
  s.created_at,
  s.updated_at,
  (s.fare_total
    - COALESCE(f.amount, 0)
    - COALESCE(x.oncology, 0)
    - COALESCE(x.ticket_office, 0)
    - COALESCE(x.mp, 0)
    - COALESCE(x.other, 0)) AS surplus
FROM services s
JOIN routes r   ON r.id = s.route_id
JOIN vehicles v ON v.id = s.vehicle_id
LEFT JOIN employees d ON d.id = s.driver_id
LEFT JOIN employees g ON g.id = s.guard_id
LEFT JOIN LATERAL (
  SELECT SUM(fl.amount) AS amount,
         SUM(fl.liters) AS liters,
         BOOL_OR(fl.full_tank) AS full_tank
  FROM fuel_loads fl
  WHERE fl.service_id = s.id
) f ON TRUE
LEFT JOIN LATERAL (
  SELECT
    SUM(CASE WHEN e.category = 'oncology'      THEN e.amount ELSE 0 END) AS oncology,
    SUM(CASE WHEN e.category = 'ticket_office' THEN e.amount ELSE 0 END) AS ticket_office,
    SUM(CASE WHEN e.category = 'mp'            THEN e.amount ELSE 0 END) AS mp,
    SUM(CASE WHEN e.category = 'other'         THEN e.amount ELSE 0 END) AS other
  FROM service_expenses e
  WHERE e.service_id = s.id
) x ON TRUE;

CREATE OR REPLACE VIEW v_fuel_loads AS
SELECT f.*, v.internal_no AS vehicle_no, v.plate,
       s.service_date, s.schedule_label
FROM fuel_loads f
JOIN vehicles v ON v.id = f.vehicle_id
LEFT JOIN services s ON s.id = f.service_id;

CREATE OR REPLACE VIEW v_expenses AS
SELECT e.*, s.service_date, s.schedule_label, v.internal_no AS vehicle_no
FROM service_expenses e
LEFT JOIN services s ON s.id = e.service_id
LEFT JOIN vehicles v ON v.id = e.vehicle_id;

CREATE OR REPLACE VIEW v_maintenance AS
SELECT m.*, v.internal_no AS vehicle_no, v.plate,
       CASE WHEN m.next_due IS NOT NULL THEN (m.next_due - CURRENT_DATE) ELSE NULL END AS days_left
FROM maintenance m
JOIN vehicles v ON v.id = m.vehicle_id;

CREATE OR REPLACE VIEW v_freight_items AS
SELECT i.*, t.trip_date, t.vehicle_id, t.driver_id,
       t.company_id, v.internal_no AS vehicle_no, d.full_name AS driver_name
FROM freight_items i
JOIN freight_trips t ON t.id = i.trip_id
JOIN vehicles v ON v.id = t.vehicle_id
LEFT JOIN employees d ON d.id = t.driver_id;

CREATE OR REPLACE VIEW v_freight_trips AS
SELECT
  t.id, t.company_id, t.trip_date, t.vehicle_id,
  v.internal_no AS vehicle_no, v.plate,
  t.driver_id, d.full_name AS driver_name,
  t.km, t.commission_pct, t.notes, t.created_by, t.created_at, t.updated_at,
  COUNT(i.id)                    AS items_count,
  COALESCE(SUM(i.kilos), 0)      AS kilos,
  COALESCE(SUM(i.net_amount), 0) AS net_amount,
  COALESCE(SUM(i.vat_amount), 0) AS vat_amount,
  COALESCE(SUM(i.total_amount), 0) AS total_amount,
  COALESCE(SUM(i.driver_commission), 0) AS driver_commission
FROM freight_trips t
JOIN vehicles v ON v.id = t.vehicle_id
LEFT JOIN employees d ON d.id = t.driver_id
LEFT JOIN freight_items i ON i.trip_id = t.id
GROUP BY t.id, v.internal_no, v.plate, d.full_name;

CREATE OR REPLACE VIEW v_users AS
SELECT u.id, u.company_id, c.name AS company_name, u.username, u.full_name,
       u.email, u.role, u.active, u.must_change_password, u.last_login,
       u.created_at, u.updated_at
FROM users u
LEFT JOIN companies c ON c.id = u.company_id;

CREATE OR REPLACE VIEW v_vehicles AS
SELECT v.*, c.name AS company_name
FROM vehicles v
JOIN companies c ON c.id = v.company_id;

CREATE OR REPLACE VIEW v_employees AS
SELECT e.*, c.name AS company_name
FROM employees e
JOIN companies c ON c.id = e.company_id;

CREATE OR REPLACE VIEW v_routes AS
SELECT r.*, c.name AS company_name
FROM routes r
JOIN companies c ON c.id = r.company_id;

-- ============================================================
-- FIN
-- ============================================================
