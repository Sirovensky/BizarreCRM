-- Fix ticket_notes type CHECK constraint to allow 'customer' type for portal messages
-- Must drop and recreate FTS triggers that reference ticket_notes

-- Step 1: Drop triggers that reference ticket_notes
DROP TRIGGER IF EXISTS tickets_fts_note_ai;
DROP TRIGGER IF EXISTS tickets_fts_note_au;
DROP TRIGGER IF EXISTS tickets_fts_note_ad;
DROP TRIGGER IF EXISTS tickets_fts_au;

-- Step 2: Recreate table with expanded CHECK constraint
CREATE TABLE ticket_notes_new (
    id               INTEGER PRIMARY KEY AUTOINCREMENT,
    ticket_id        INTEGER NOT NULL REFERENCES tickets(id) ON DELETE CASCADE,
    ticket_device_id INTEGER REFERENCES ticket_devices(id),
    user_id          INTEGER NOT NULL REFERENCES users(id),
    type             TEXT NOT NULL DEFAULT 'internal' CHECK (type IN ('internal', 'diagnostic', 'email', 'customer')),
    content          TEXT NOT NULL,
    is_flagged       INTEGER NOT NULL DEFAULT 0,
    parent_id        INTEGER REFERENCES ticket_notes(id),
    created_at       TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at       TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT INTO ticket_notes_new SELECT * FROM ticket_notes;

DROP TABLE ticket_notes;

ALTER TABLE ticket_notes_new RENAME TO ticket_notes;

CREATE INDEX IF NOT EXISTS idx_ticket_notes_ticket ON ticket_notes(ticket_id);
CREATE INDEX IF NOT EXISTS idx_ticket_notes_type ON ticket_notes(type);

-- Step 3: Recreate triggers
CREATE TRIGGER tickets_fts_au AFTER UPDATE ON tickets BEGIN
  INSERT INTO tickets_fts (tickets_fts, rowid, order_id, device_names, customer_name, notes_text, labels)
  VALUES ('delete', OLD.id, '', '', '', '', '');
  INSERT INTO tickets_fts (rowid, order_id, device_names, customer_name, notes_text, labels)
  VALUES (
    NEW.id,
    COALESCE(NEW.order_id, ''),
    COALESCE((
      SELECT GROUP_CONCAT(device_name, ', ')
      FROM ticket_devices WHERE ticket_id = NEW.id
    ), ''),
    COALESCE((SELECT first_name || ' ' || last_name FROM customers WHERE id = NEW.customer_id), ''),
    COALESCE((
      SELECT GROUP_CONCAT(content, ' ')
      FROM ticket_notes WHERE ticket_id = NEW.id
    ), ''),
    COALESCE(NEW.labels, '')
  );
END;

CREATE TRIGGER tickets_fts_note_ai AFTER INSERT ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER tickets_fts_note_au AFTER UPDATE ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER tickets_fts_note_ad AFTER DELETE ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
END;
