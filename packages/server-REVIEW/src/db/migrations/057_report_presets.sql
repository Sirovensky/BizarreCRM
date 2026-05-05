-- ENR-R10: Saved report presets
CREATE TABLE IF NOT EXISTS report_presets (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id     INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name        TEXT NOT NULL,
    report_type TEXT NOT NULL,
    filters     TEXT NOT NULL DEFAULT '{}',
    is_default  INTEGER NOT NULL DEFAULT 0,
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_report_presets_user ON report_presets(user_id);
CREATE INDEX IF NOT EXISTS idx_report_presets_type ON report_presets(report_type);
