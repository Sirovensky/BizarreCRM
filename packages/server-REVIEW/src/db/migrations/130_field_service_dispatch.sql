-- Migration 130: Field Service + Dispatch domain
-- SCAN-466: Mobile field service / dispatch (android §59 / ios §57)
-- Tables: field_service_jobs, dispatch_routes, dispatch_status_history

-- ---------------------------------------------------------------------------
-- Table: field_service_jobs
-- One row per on-site job (linked to a ticket or standalone customer visit).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS field_service_jobs (
  id                          INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id                   INTEGER REFERENCES tickets(id) ON DELETE CASCADE,
  customer_id                 INTEGER REFERENCES customers(id),
  address_line                TEXT    NOT NULL,
  city                        TEXT,
  state                       TEXT,
  postcode                    TEXT,
  lat                         REAL    NOT NULL,
  lng                         REAL    NOT NULL,
  scheduled_window_start      TEXT,
  scheduled_window_end        TEXT,
  priority                    TEXT    NOT NULL DEFAULT 'normal'
                                      CHECK (priority IN ('low','normal','high','emergency')),
  status                      TEXT    NOT NULL DEFAULT 'unassigned'
                                      CHECK (status IN ('unassigned','assigned','en_route','on_site','completed','canceled','deferred')),
  assigned_technician_id      INTEGER REFERENCES users(id),
  estimated_duration_minutes  INTEGER,
  actual_duration_minutes     INTEGER,
  technician_notes            TEXT,
  notes                       TEXT,
  created_by_user_id          INTEGER NOT NULL REFERENCES users(id),
  created_at                  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at                  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_fsj_status_window
  ON field_service_jobs (status, scheduled_window_start);

CREATE INDEX IF NOT EXISTS idx_fsj_tech_status
  ON field_service_jobs (assigned_technician_id, status);

CREATE INDEX IF NOT EXISTS idx_fsj_latlng
  ON field_service_jobs (lat, lng);

-- ---------------------------------------------------------------------------
-- Table: dispatch_routes
-- Ordered job list for a technician on a given date.
-- UNIQUE(technician_id, route_date) — one active plan per tech per day.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dispatch_routes (
  id                      INTEGER PRIMARY KEY AUTOINCREMENT,
  technician_id           INTEGER NOT NULL REFERENCES users(id),
  route_date              TEXT    NOT NULL,
  job_order_json          TEXT    NOT NULL,          -- JSON array of field_service_job ids in visit order
  total_distance_km       REAL,
  total_duration_minutes  INTEGER,
  status                  TEXT    NOT NULL DEFAULT 'draft'
                                  CHECK (status IN ('draft','active','completed')),
  created_at              TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now')),
  updated_at              TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

CREATE UNIQUE INDEX IF NOT EXISTS uidx_dispatch_routes_tech_date
  ON dispatch_routes (technician_id, route_date);

CREATE INDEX IF NOT EXISTS idx_dispatch_routes_date_status
  ON dispatch_routes (route_date, status);

-- ---------------------------------------------------------------------------
-- Table: dispatch_status_history
-- Immutable audit trail — one row per status transition on a job.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS dispatch_status_history (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  job_id        INTEGER NOT NULL REFERENCES field_service_jobs(id) ON DELETE CASCADE,
  status        TEXT    NOT NULL,
  actor_user_id INTEGER REFERENCES users(id),
  location_lat  REAL,
  location_lng  REAL,
  notes         TEXT,
  created_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now'))
);

CREATE INDEX IF NOT EXISTS idx_dsh_job_created
  ON dispatch_status_history (job_id, created_at);
