-- SEC-L7: Add soft delete (is_deleted) to leads, estimates, appointments
-- Previously these tables used hard DELETE which destroys audit trail.

ALTER TABLE leads ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_leads_is_deleted ON leads(is_deleted);

ALTER TABLE estimates ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_estimates_is_deleted ON estimates(is_deleted);

ALTER TABLE appointments ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_appointments_is_deleted ON appointments(is_deleted);
