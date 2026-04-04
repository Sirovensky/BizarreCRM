-- Notification templates for automated email/SMS on ticket events
CREATE TABLE IF NOT EXISTS notification_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event_key TEXT NOT NULL UNIQUE,
  event_label TEXT NOT NULL,
  category TEXT NOT NULL DEFAULT 'customer',
  subject TEXT NOT NULL DEFAULT '',
  email_body TEXT NOT NULL DEFAULT '',
  sms_body TEXT NOT NULL DEFAULT '',
  send_email_auto INTEGER NOT NULL DEFAULT 0,
  send_sms_auto INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

INSERT OR IGNORE INTO notification_templates (event_key, event_label, category, subject, sms_body, send_sms_auto) VALUES
  ('ticket_created', 'A new ticket is created', 'customer', 'Repair In Progress - {ticket_id} from {store_name}', 'Hi {customer_name}, your device has been checked in at {store_name}. Ticket: {ticket_id}', 1),
  ('parts_arrived', 'Parts arrived, need the device', 'customer', '', 'Hi {customer_name}. We got the parts for your {device_name}. Feel free to stop by and we''ll get that resolved.', 1),
  ('part_received_queue', 'Part received, in queue to fix', 'customer', '', 'Hi {customer_name}, we received the parts for your {device_name} and it''s in our repair queue. We''ll update you when it''s done!', 1),
  ('device_repaired', 'Repaired/need pickup', 'customer', 'Your device is Ready For Pickup', 'Hi {customer_name}, your {device_name} repair is complete! Please pick it up at {store_name}. Hours: 9-3:30, 5-8 Mon-Fri.', 1),
  ('device_unrepairable', 'A device cannot be repaired', 'customer', 'OOPS - Your Device cannot be repaired', 'Hi {customer_name}, unfortunately we were unable to repair your {device_name}. Please contact us for details.', 0),
  ('part_not_in_stock', 'Required part is not available in stock', 'customer', 'Pending Parts for Order - {ticket_id}', '', 0),
  ('waiting_approval', 'Waiting for customer approval', 'customer', '{device_name} Repair Order Pending Approval', '', 0),
  ('receipt_sent', 'Receipt against ticket sent to customer', 'customer', 'Ticket Receipt #{ticket_id} from {store_name}', '', 0),
  ('special_part_available', 'Part required to complete repair is available', 'customer', 'Special Ordered Part For {device_name} is in stock!', '', 0),
  ('status_changed', 'Ticket status changed', 'internal', '', '', 0),
  ('note_added', 'Note added to ticket', 'internal', '', '', 0);
