-- Migration 129: Ticket Signatures + Expense Receipt OCR
-- SCAN-465: Ticket signature/waiver capture (android §4.14)
-- SCAN-490: Expense receipt OCR upload endpoint (ios §11.3)

-- ---------------------------------------------------------------------------
-- Table: ticket_signatures
-- Captures customer/technician/manager signatures on a ticket lifecycle event.
-- Kinds: check_in (device received), check_out (device returned),
--        waiver (liability waiver), payment (payment authorisation).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ticket_signatures (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id             INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
  signature_kind        TEXT    NOT NULL
    CHECK(signature_kind IN ('check_in','check_out','waiver','payment')),
  signer_name           TEXT    NOT NULL,
  signer_role           TEXT
    CHECK(signer_role IN ('customer','technician','manager')),
  -- Stored as a data URL (data:image/png;base64,... or data:image/jpeg;base64,...).
  -- Max 500 000 chars enforced at the application layer before insert.
  signature_data_url    TEXT    NOT NULL,
  waiver_text           TEXT,
  waiver_version        TEXT,
  captured_by_user_id   INTEGER REFERENCES users(id),
  captured_at           TEXT    NOT NULL DEFAULT (datetime('now')),
  ip_address            TEXT,
  user_agent            TEXT
);

CREATE INDEX IF NOT EXISTS idx_ticket_signatures_ticket_id
  ON ticket_signatures(ticket_id);

CREATE INDEX IF NOT EXISTS idx_ticket_signatures_captured_at
  ON ticket_signatures(captured_at);

-- ---------------------------------------------------------------------------
-- Expense receipt OCR columns (ALTER TABLE — idempotent via separate columns)
-- ---------------------------------------------------------------------------
ALTER TABLE expenses ADD COLUMN receipt_image_path    TEXT;
ALTER TABLE expenses ADD COLUMN receipt_ocr_text      TEXT;
ALTER TABLE expenses ADD COLUMN receipt_ocr_parsed_json TEXT;
ALTER TABLE expenses ADD COLUMN receipt_uploaded_at   TEXT;

-- ---------------------------------------------------------------------------
-- Table: expense_receipt_uploads
-- Tracks each file upload attempt + OCR job for an expense.
-- expense_id is nullable (SET NULL) so records survive if the parent expense
-- is deleted — useful for the audit trail.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS expense_receipt_uploads (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  expense_id            INTEGER REFERENCES expenses(id) ON DELETE SET NULL,
  uploaded_by_user_id   INTEGER REFERENCES users(id),
  file_path             TEXT    NOT NULL,
  mime_type             TEXT,
  file_size_bytes       INTEGER,
  ocr_status            TEXT    NOT NULL
    CHECK(ocr_status IN ('pending','processing','completed','failed'))
    DEFAULT 'pending',
  ocr_text              TEXT,
  parsed_json           TEXT,
  error_message         TEXT,
  created_at            TEXT    NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_expense_receipt_uploads_expense_id
  ON expense_receipt_uploads(expense_id);

CREATE INDEX IF NOT EXISTS idx_expense_receipt_uploads_user_id
  ON expense_receipt_uploads(uploaded_by_user_id);
