-- Replace ticket statuses with the default BizarreCRM repair workflow set
-- First delete old statuses that aren't referenced by any ticket
DELETE FROM ticket_statuses WHERE id NOT IN (SELECT DISTINCT status_id FROM tickets WHERE status_id IS NOT NULL)
  AND id NOT IN (SELECT DISTINCT status_id FROM ticket_devices WHERE status_id IS NOT NULL);

-- Now upsert all new statuses (insert if name doesn't exist, update color/sort if it does)

-- Open (blue)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Intake received'), NULL), 'Intake received', '#3b82f6', 0, 1, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Parts quote needed'), NULL), 'Parts quote needed', '#ef4444', 1, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Parts received - bench queue'), NULL), 'Parts received - bench queue', '#3b82f6', 2, 0, 0, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Diagnostic underway'), NULL), 'Diagnostic underway', '#3b82f6', 3, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Bench work active'), NULL), 'Bench work active', '#3b82f6', 4, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Diagnostic ready'), NULL), 'Diagnostic ready', '#3b82f6', 5, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repair complete - final check'), NULL), 'Repair complete - final check', '#3b82f6', 6, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Final check passed'), NULL), 'Final check passed', '#3b82f6', 7, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Final check needs review'), NULL), 'Final check needs review', '#3b82f6', 8, 0, 0, 0, 0;

-- On Hold (orange)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Parts ready - device needed'), NULL), 'Parts ready - device needed', '#f97316', 9, 0, 0, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Awaiting related device'), NULL), 'Awaiting related device', '#f97316', 10, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='In transit'), NULL), 'In transit', '#f97316', 11, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Estimate approval needed'), NULL), 'Estimate approval needed', '#f97316', 12, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Customer response needed'), NULL), 'Customer response needed', '#f97316', 13, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Customer approval pending'), NULL), 'Customer approval pending', '#f97316', 14, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Parts on order'), NULL), 'Parts on order', '#f97316', 15, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Complete - balance due'), NULL), 'Complete - balance due', '#f97316', 16, 0, 0, 0, 0;

-- Closed (green)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Ready after repair'), NULL), 'Ready after repair', '#22c55e', 17, 0, 1, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Paid - ready to ship'), NULL), 'Paid - ready to ship', '#22c55e', 18, 0, 1, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Shipped'), NULL), 'Shipped', '#22c55e', 19, 0, 1, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired and collected'), NULL), 'Repaired and collected', '#22c55e', 20, 0, 1, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Paid and picked up'), NULL), 'Paid and picked up', '#22c55e', 21, 0, 1, 0, 0;

-- Cancelled (red)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Job cancelled'), NULL), 'Job cancelled', '#ef4444', 22, 0, 0, 1, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Not economical to repair'), NULL), 'Not economical to repair', '#ef4444', 23, 0, 0, 1, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Disposal completed'), NULL), 'Disposal completed', '#ef4444', 24, 0, 0, 1, 0;

-- Make sure exactly one status is default
UPDATE ticket_statuses SET is_default = 0 WHERE name != 'Intake received';
UPDATE ticket_statuses SET is_default = 1 WHERE name = 'Intake received';
