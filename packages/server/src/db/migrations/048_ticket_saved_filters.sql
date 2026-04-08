-- Saved ticket filter presets per user
CREATE TABLE IF NOT EXISTS ticket_saved_filters (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    user_id    INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    filters    TEXT NOT NULL DEFAULT '{}',  -- JSON: { status_id, assigned_to, date_filter, keyword, sort_by, sort_order }
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_ticket_saved_filters_user ON ticket_saved_filters(user_id);
