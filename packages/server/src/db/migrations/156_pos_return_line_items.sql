-- Track POS return quantities per original invoice line so repeated returns
-- cannot credit more units than were sold.

CREATE TABLE IF NOT EXISTS pos_return_line_items (
    id                     INTEGER PRIMARY KEY AUTOINCREMENT,
    original_invoice_id    INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    original_line_item_id  INTEGER NOT NULL REFERENCES invoice_line_items(id) ON DELETE CASCADE,
    credit_note_id         INTEGER NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    quantity               INTEGER NOT NULL,
    reason                 TEXT NOT NULL,
    created_by             INTEGER REFERENCES users(id),
    created_at             TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_pos_return_line_items_original_invoice_id
    ON pos_return_line_items(original_invoice_id);

CREATE INDEX IF NOT EXISTS idx_pos_return_line_items_original_line_item_id
    ON pos_return_line_items(original_line_item_id);
