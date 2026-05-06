-- Tablet ticket detail quote add-row support for non-inventory lines.
CREATE TABLE IF NOT EXISTS ticket_device_quote_lines (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_device_id  INTEGER NOT NULL REFERENCES ticket_devices(id) ON DELETE CASCADE,
  kind              TEXT NOT NULL CHECK (kind IN ('service', 'misc')),
  repair_service_id INTEGER REFERENCES repair_services(id),
  description       TEXT NOT NULL DEFAULT '',
  quantity          INTEGER NOT NULL DEFAULT 1,
  unit_price        REAL NOT NULL DEFAULT 0,
  line_discount     REAL NOT NULL DEFAULT 0,
  tax_amount        REAL NOT NULL DEFAULT 0,
  tax_class_id      INTEGER REFERENCES tax_classes(id),
  tax_inclusive     INTEGER NOT NULL DEFAULT 0,
  total             REAL NOT NULL DEFAULT 0,
  created_at        TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at        TEXT NOT NULL DEFAULT (datetime('now')),
  CHECK (
    (kind = 'service' AND repair_service_id IS NOT NULL)
    OR (kind = 'misc' AND repair_service_id IS NULL)
  )
);

CREATE INDEX IF NOT EXISTS idx_ticket_device_quote_lines_device_id
  ON ticket_device_quote_lines(ticket_device_id);

CREATE INDEX IF NOT EXISTS idx_ticket_device_quote_lines_kind
  ON ticket_device_quote_lines(kind);

CREATE INDEX IF NOT EXISTS idx_ticket_device_quote_lines_repair_service
  ON ticket_device_quote_lines(repair_service_id);
