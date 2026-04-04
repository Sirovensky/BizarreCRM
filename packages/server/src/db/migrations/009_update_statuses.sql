-- Replace ticket statuses with the full RepairDesk-style set
-- First delete old statuses that aren't referenced by any ticket
DELETE FROM ticket_statuses WHERE id NOT IN (SELECT DISTINCT status_id FROM tickets WHERE status_id IS NOT NULL)
  AND id NOT IN (SELECT DISTINCT status_id FROM ticket_devices WHERE status_id IS NOT NULL);

-- Now upsert all new statuses (insert if name doesn't exist, update color/sort if it does)

-- Open (blue)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Waiting for inspection'), NULL), 'Waiting for inspection', '#3b82f6', 0, 1, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='NEED TO ORDER PARTS'), NULL), 'NEED TO ORDER PARTS', '#ef4444', 1, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Part received, in queue to fix - SMS'), NULL), 'Part received, in queue to fix - SMS', '#3b82f6', 2, 0, 0, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Diagnosis - In progress'), NULL), 'Diagnosis - In progress', '#3b82f6', 3, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='In Progress'), NULL), 'In Progress', '#3b82f6', 4, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Diagnosis completed'), NULL), 'Diagnosis completed', '#3b82f6', 5, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired - Pending QC'), NULL), 'Repaired - Pending QC', '#3b82f6', 6, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired - QC Passed'), NULL), 'Repaired - QC Passed', '#3b82f6', 7, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired - QC Failed'), NULL), 'Repaired - QC Failed', '#3b82f6', 8, 0, 0, 0, 0;

-- On Hold (orange)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Parts arrived, need the device - SMS'), NULL), 'Parts arrived, need the device - SMS', '#f97316', 9, 0, 0, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Waiting for asset'), NULL), 'Waiting for asset', '#f97316', 10, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='In-transit'), NULL), 'In-transit', '#f97316', 11, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Approval required'), NULL), 'Approval required', '#f97316', 12, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Waiting on customer'), NULL), 'Waiting on customer', '#f97316', 13, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Pending for customer approval'), NULL), 'Pending for customer approval', '#f97316', 14, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Waiting for Parts'), NULL), 'Waiting for Parts', '#f97316', 15, 0, 0, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired - Waiting for payment'), NULL), 'Repaired - Waiting for payment', '#f97316', 16, 0, 0, 0, 0;

-- Closed (green)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired'), NULL), 'Repaired', '#22c55e', 17, 0, 1, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Payment Collected - Ready for shipment'), NULL), 'Payment Collected - Ready for shipment', '#22c55e', 18, 0, 1, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Device shipped'), NULL), 'Device shipped', '#22c55e', 19, 0, 1, 0, 1;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Repaired & Collected'), NULL), 'Repaired & Collected', '#22c55e', 20, 0, 1, 0, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Payment Received & Picked Up'), NULL), 'Payment Received & Picked Up', '#22c55e', 21, 0, 1, 0, 0;

-- Cancelled (red)
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Cancelled'), NULL), 'Cancelled', '#ef4444', 22, 0, 0, 1, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='BER (Beyond Economical Repair)'), NULL), 'BER (Beyond Economical Repair)', '#ef4444', 23, 0, 0, 1, 0;
INSERT OR REPLACE INTO ticket_statuses (id, name, color, sort_order, is_default, is_closed, is_cancelled, notify_customer)
  SELECT COALESCE((SELECT id FROM ticket_statuses WHERE name='Disposed'), NULL), 'Disposed', '#ef4444', 24, 0, 0, 1, 0;

-- Make sure exactly one status is default
UPDATE ticket_statuses SET is_default = 0 WHERE name != 'Waiting for inspection';
UPDATE ticket_statuses SET is_default = 1 WHERE name = 'Waiting for inspection';
