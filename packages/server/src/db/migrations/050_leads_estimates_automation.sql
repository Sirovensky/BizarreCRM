-- ENR-LE2: Lead follow-up reminders
CREATE TABLE IF NOT EXISTS lead_reminders (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    lead_id    INTEGER NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    remind_at  TEXT NOT NULL,
    note       TEXT,
    completed  INTEGER NOT NULL DEFAULT 0,
    created_by INTEGER REFERENCES users(id),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_lead_reminders_lead_id   ON lead_reminders(lead_id);
CREATE INDEX IF NOT EXISTS idx_lead_reminders_remind_at ON lead_reminders(remind_at) WHERE completed = 0;

-- ENR-LE5: Lost reason tracking on leads
ALTER TABLE leads ADD COLUMN lost_reason TEXT DEFAULT NULL;

-- ENR-LE6: Estimate version history
CREATE TABLE IF NOT EXISTS estimate_versions (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    estimate_id     INTEGER NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
    version_number  INTEGER NOT NULL DEFAULT 1,
    data            TEXT NOT NULL,
    created_at      TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_estimate_versions_estimate_id ON estimate_versions(estimate_id);

-- ENR-LE11: Appointment no-show tracking
ALTER TABLE appointments ADD COLUMN no_show INTEGER NOT NULL DEFAULT 0;

-- ENR-A1 / ENR-A2: Track last auto-SMS sent per ticket/invoice to avoid spam
-- stall_followup_sent: 1 = stale-ticket SMS already sent for this ticket
ALTER TABLE tickets ADD COLUMN stall_followup_sent INTEGER NOT NULL DEFAULT 0;

-- invoice_reminder_sent_at: timestamp of last auto-reminder sent for this invoice
ALTER TABLE invoices ADD COLUMN reminder_sent_at TEXT DEFAULT NULL;
