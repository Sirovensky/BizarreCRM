-- Fix tickets_fts: remove content='tickets' sync since FTS columns don't match tickets table columns
-- The triggers handle all sync manually, so we use contentless FTS (content='')

DROP TRIGGER IF EXISTS tickets_fts_ai;
DROP TRIGGER IF EXISTS tickets_fts_au;
DROP TRIGGER IF EXISTS tickets_fts_ad;
DROP TRIGGER IF EXISTS tickets_fts_device_ai;
DROP TRIGGER IF EXISTS tickets_fts_device_au;
DROP TRIGGER IF EXISTS tickets_fts_device_ad;
DROP TRIGGER IF EXISTS tickets_fts_note_ai;
DROP TRIGGER IF EXISTS tickets_fts_note_au;
DROP TRIGGER IF EXISTS tickets_fts_note_ad;

DROP TABLE IF EXISTS tickets_fts;

CREATE VIRTUAL TABLE tickets_fts USING fts5(
    order_id,
    device_names,
    customer_name,
    notes_text,
    labels,
    content=''
);

-- Re-create triggers for manual sync

CREATE TRIGGER tickets_fts_ai AFTER INSERT ON tickets BEGIN
  INSERT INTO tickets_fts (rowid, order_id, device_names, customer_name, notes_text, labels)
  VALUES (
    NEW.id,
    COALESCE(NEW.order_id, ''),
    '',
    COALESCE((SELECT first_name || ' ' || last_name FROM customers WHERE id = NEW.customer_id), ''),
    '',
    COALESCE(NEW.labels, '')
  );
END;

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

CREATE TRIGGER tickets_fts_ad AFTER DELETE ON tickets BEGIN
  INSERT INTO tickets_fts (tickets_fts, rowid, order_id, device_names, customer_name, notes_text, labels)
  VALUES ('delete', OLD.id, '', '', '', '', '');
END;

-- Cascade triggers from ticket_devices and ticket_notes
CREATE TRIGGER tickets_fts_device_ai AFTER INSERT ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER tickets_fts_device_au AFTER UPDATE ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER tickets_fts_device_ad AFTER DELETE ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
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

-- Backfill existing tickets into FTS
INSERT INTO tickets_fts (rowid, order_id, device_names, customer_name, notes_text, labels)
SELECT
  t.id,
  COALESCE(t.order_id, ''),
  COALESCE((SELECT GROUP_CONCAT(td.device_name, ', ') FROM ticket_devices td WHERE td.ticket_id = t.id), ''),
  COALESCE((SELECT c.first_name || ' ' || c.last_name FROM customers c WHERE c.id = t.customer_id), ''),
  COALESCE((SELECT GROUP_CONCAT(tn.content, ' ') FROM ticket_notes tn WHERE tn.ticket_id = t.id), ''),
  COALESCE(t.labels, '')
FROM tickets t
WHERE t.is_deleted = 0;
