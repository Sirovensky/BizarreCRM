-- WEB-UIUX-1001: dual-control / second-admin gate on large gift-card issuance.
-- Manager-tier user requesting >= threshold creates a pending row that an
-- admin (different user) approves before the card is minted. Admins can
-- still issue any amount directly without going through this queue.
CREATE TABLE IF NOT EXISTS gift_card_pending_issuances (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  amount              REAL NOT NULL CHECK (amount > 0),
  customer_id         INTEGER REFERENCES customers(id) ON DELETE SET NULL,
  recipient_name      TEXT,
  recipient_email     TEXT,
  expires_at          TEXT,
  notes               TEXT,
  requester_id        INTEGER NOT NULL REFERENCES users(id),
  approver_id         INTEGER REFERENCES users(id),
  status              TEXT NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'approved', 'declined', 'cancelled')),
  decline_reason      TEXT,
  created_at          TEXT NOT NULL DEFAULT (datetime('now')),
  decided_at          TEXT,
  -- The resulting gift_cards.id once approved; null until then.
  gift_card_id        INTEGER REFERENCES gift_cards(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_gc_pending_status_created
  ON gift_card_pending_issuances(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_gc_pending_requester
  ON gift_card_pending_issuances(requester_id);
