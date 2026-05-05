-- Customer feedback / review collection after repair
CREATE TABLE IF NOT EXISTS customer_feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ticket_id INTEGER NOT NULL REFERENCES tickets(id),
  customer_id INTEGER NOT NULL REFERENCES customers(id),
  rating INTEGER CHECK(rating BETWEEN 1 AND 5),  -- 1-5 stars
  comment TEXT,
  source TEXT DEFAULT 'sms',  -- sms, web, in_person
  requested_at TEXT,  -- when we asked for feedback
  responded_at TEXT,  -- when customer responded
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX IF NOT EXISTS idx_feedback_ticket ON customer_feedback(ticket_id);
CREATE INDEX IF NOT EXISTS idx_feedback_customer ON customer_feedback(customer_id);
