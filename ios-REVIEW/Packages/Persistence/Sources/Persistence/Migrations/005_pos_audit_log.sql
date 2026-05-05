-- §16.11 Anti-theft / Loss Prevention — POS audit log.
--
-- Every security-sensitive POS event (void, no-sale, discount override,
-- price override, delete-line) lands here with the cashier id and, when a
-- manager approved the action, the manager id too.
--
-- cashier_id / manager_id are Int placeholders matching the 0-sentinel
-- scheme from §39 (auth/me plumbing deferred — they will be re-stamped on
-- server sync once the user-identity pipeline ships).
--
-- context_json stores a JSON object with event-specific detail:
--   void_line / delete_line: { sku, lineName, originalPriceCents }
--   no_sale:                 { reason }
--   discount_override:       { originalCents, appliedCents }
--   price_override:          { originalPriceCents, newPriceCents, sku, lineName }

CREATE TABLE pos_audit_entries (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  event_type    TEXT    NOT NULL,       -- 'void_line','no_sale','discount_override','price_override','delete_line'
  cashier_id    INTEGER NOT NULL,       -- 0 placeholder until auth/me ships
  manager_id    INTEGER,               -- nil when cashier stayed under threshold
  amount_cents  INTEGER,               -- price delta / discount amount / line value
  reason        TEXT,                  -- free-form reason / note
  context_json  TEXT,                  -- JSON: event-specific detail (see above)
  created_at    REAL    NOT NULL        -- Unix timestamp (seconds since epoch)
);

CREATE INDEX idx_pos_audit_created    ON pos_audit_entries(created_at DESC);
CREATE INDEX idx_pos_audit_event_type ON pos_audit_entries(event_type);
