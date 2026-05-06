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
  ('parts_arrived', 'Parts ready for bench', 'customer', '', 'Hi {customer_name}. The part for your {device_name} is here, and we will continue when the device is ready for the bench.', 1),
  ('part_received_queue', 'Parts received and queued', 'customer', '', 'Hi {customer_name}, the parts for your {device_name} are in and your ticket is queued for repair. We will update you when it is complete.', 1),
  ('device_repaired', 'Repair complete for pickup', 'customer', 'Your device is ready', 'Hi {customer_name}, your {device_name} repair is complete. Please pick it up at {store_name}.', 1),
  ('device_unrepairable', 'A device cannot be repaired', 'customer', 'OOPS - Your Device cannot be repaired', 'Hi {customer_name}, unfortunately we were unable to repair your {device_name}. Please contact us for details.', 0),
  ('part_not_in_stock', 'Required part is not available in stock', 'customer', 'Pending Parts for Order - {ticket_id}', '', 0),
  ('waiting_approval', 'Waiting for customer approval', 'customer', '{device_name} Repair Order Pending Approval', '', 0),
  ('receipt_sent', 'Receipt against ticket sent to customer', 'customer', 'Ticket Receipt #{ticket_id} from {store_name}', '', 0),
  ('special_part_available', 'Part required to complete repair is available', 'customer', 'Special Ordered Part For {device_name} is in stock!', '', 0),
  ('status_changed', 'Ticket status changed', 'internal', '', '', 0),
  ('note_added', 'Note added to ticket', 'internal', '', '', 0);
