-- AUDIT-S1: Fix duplicate sort orders — assign unique sort_order to all statuses
UPDATE ticket_statuses SET sort_order = 0 WHERE LOWER(name) = LOWER('Open');
UPDATE ticket_statuses SET sort_order = 1 WHERE LOWER(name) = LOWER('Waiting for inspection');
UPDATE ticket_statuses SET sort_order = 2 WHERE LOWER(name) = LOWER('In Progress');
UPDATE ticket_statuses SET sort_order = 3 WHERE LOWER(name) = LOWER('Diagnosis - In Progress');
UPDATE ticket_statuses SET sort_order = 4 WHERE LOWER(name) = LOWER('Waiting for Parts');
UPDATE ticket_statuses SET sort_order = 5 WHERE LOWER(name) = LOWER('Need to Order Parts');
UPDATE ticket_statuses SET sort_order = 6 WHERE LOWER(name) = LOWER('Parts Arrived');
UPDATE ticket_statuses SET sort_order = 7 WHERE LOWER(name) = LOWER('Repaired - Pending QC');
UPDATE ticket_statuses SET sort_order = 8 WHERE LOWER(name) = LOWER('Diagnosis Completed');
UPDATE ticket_statuses SET sort_order = 9 WHERE LOWER(name) = LOWER('Waiting on Customer');
UPDATE ticket_statuses SET sort_order = 10 WHERE LOWER(name) = LOWER('On Hold');
UPDATE ticket_statuses SET sort_order = 11 WHERE LOWER(name) = LOWER('Payment Received & Picked Up');
UPDATE ticket_statuses SET sort_order = 12 WHERE LOWER(name) = LOWER('Closed');
UPDATE ticket_statuses SET sort_order = 13 WHERE LOWER(name) = LOWER('Cancelled');
UPDATE ticket_statuses SET sort_order = 14 WHERE LOWER(name) = LOWER('Warranty Repair');

-- AUDIT-S2: Fix duplicate blue colors — assign distinct colors per status
UPDATE ticket_statuses SET color = '#3b82f6' WHERE LOWER(name) = LOWER('Open');
UPDATE ticket_statuses SET color = '#6366f1' WHERE LOWER(name) = LOWER('Waiting for inspection');
UPDATE ticket_statuses SET color = '#0ea5e9' WHERE LOWER(name) = LOWER('In Progress');
UPDATE ticket_statuses SET color = '#8b5cf6' WHERE LOWER(name) = LOWER('Diagnosis - In Progress');
UPDATE ticket_statuses SET color = '#f59e0b' WHERE LOWER(name) = LOWER('Waiting for Parts');
UPDATE ticket_statuses SET color = '#d97706' WHERE LOWER(name) = LOWER('Need to Order Parts');
UPDATE ticket_statuses SET color = '#10b981' WHERE LOWER(name) = LOWER('Parts Arrived');
UPDATE ticket_statuses SET color = '#14b8a6' WHERE LOWER(name) = LOWER('Repaired - Pending QC');
UPDATE ticket_statuses SET color = '#a855f7' WHERE LOWER(name) = LOWER('Diagnosis Completed');
UPDATE ticket_statuses SET color = '#f97316' WHERE LOWER(name) = LOWER('Waiting on Customer');
UPDATE ticket_statuses SET color = '#6b7280' WHERE LOWER(name) = LOWER('On Hold');
UPDATE ticket_statuses SET color = '#22c55e' WHERE LOWER(name) = LOWER('Payment Received & Picked Up');
UPDATE ticket_statuses SET color = '#16a34a' WHERE LOWER(name) = LOWER('Closed');
UPDATE ticket_statuses SET color = '#ef4444' WHERE LOWER(name) = LOWER('Cancelled');
UPDATE ticket_statuses SET color = '#eab308' WHERE LOWER(name) = LOWER('Warranty Repair');

-- AUDIT-S3: Catch any remaining ALL CAPS statuses not covered by migration 035
UPDATE ticket_statuses SET name = 'Open' WHERE name = 'OPEN';
UPDATE ticket_statuses SET name = 'Closed' WHERE name = 'CLOSED';
UPDATE ticket_statuses SET name = 'On Hold' WHERE name = 'ON HOLD';
UPDATE ticket_statuses SET name = 'Parts Arrived' WHERE name = 'PARTS ARRIVED';
UPDATE ticket_statuses SET name = 'Warranty Repair' WHERE name = 'WARRANTY REPAIR';
UPDATE ticket_statuses SET name = 'Special Part Order (Pending Parts)' WHERE name = 'SPECIAL PART ORDER (PENDING PARTS)';
