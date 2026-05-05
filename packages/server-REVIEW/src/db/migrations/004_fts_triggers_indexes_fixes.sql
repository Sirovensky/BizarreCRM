-- Migration 004: FTS sync triggers for tickets, missing indexes, fix default values
-- ============================================================================

-- ─── FTS sync triggers for tickets_fts ──────────────────────────────────────
-- tickets_fts columns: order_id, device_names, customer_name, notes_text, labels

-- After INSERT on tickets: populate order_id, customer_name, labels
CREATE TRIGGER IF NOT EXISTS tickets_fts_ai AFTER INSERT ON tickets BEGIN
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

-- After UPDATE on tickets: re-sync all columns
CREATE TRIGGER IF NOT EXISTS tickets_fts_au AFTER UPDATE ON tickets BEGIN
  DELETE FROM tickets_fts WHERE rowid = OLD.id;
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

-- After DELETE on tickets: remove from FTS
CREATE TRIGGER IF NOT EXISTS tickets_fts_ad AFTER DELETE ON tickets BEGIN
  DELETE FROM tickets_fts WHERE rowid = OLD.id;
END;

-- Keep device_names in sync when ticket_devices change
CREATE TRIGGER IF NOT EXISTS tickets_fts_device_ai AFTER INSERT ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER IF NOT EXISTS tickets_fts_device_au AFTER UPDATE ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER IF NOT EXISTS tickets_fts_device_ad AFTER DELETE ON ticket_devices BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
END;

-- Keep notes_text in sync when ticket_notes change
CREATE TRIGGER IF NOT EXISTS tickets_fts_note_ai AFTER INSERT ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER IF NOT EXISTS tickets_fts_note_au AFTER UPDATE ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
END;

CREATE TRIGGER IF NOT EXISTS tickets_fts_note_ad AFTER DELETE ON ticket_notes BEGIN
  UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
END;

-- ─── Missing indexes ────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_invoices_created ON invoices(created_at);
CREATE INDEX IF NOT EXISTS idx_payments_created ON payments(created_at);
CREATE INDEX IF NOT EXISTS idx_payments_invoice ON payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_pos_transactions_created ON pos_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_clock_entries_clock_in ON clock_entries(clock_in);
CREATE INDEX IF NOT EXISTS idx_leads_created ON leads(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_created ON stock_movements(created_at);
CREATE INDEX IF NOT EXISTS idx_estimates_created ON estimates(created_at);
CREATE INDEX IF NOT EXISTS idx_parts_order_queue_catalog ON parts_order_queue(catalog_item_id);
CREATE INDEX IF NOT EXISTS idx_parts_order_queue_inventory ON parts_order_queue(inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_parts_order_queue_tickets_ticket ON parts_order_queue_tickets(ticket_id);

-- ─── Fix pre_conditions/post_conditions defaults ────────────────────────────

UPDATE ticket_devices SET pre_conditions = '[]' WHERE pre_conditions = '{}' OR pre_conditions IS NULL;
UPDATE ticket_devices SET post_conditions = '[]' WHERE post_conditions = '{}' OR post_conditions IS NULL;
