-- AUDIT-S1/S2: Assign unique sort orders and distinct colors for the default
-- status vocabulary.

UPDATE ticket_statuses SET sort_order = 0, color = '#3b82f6' WHERE LOWER(name) = LOWER('Open');
UPDATE ticket_statuses SET sort_order = 1, color = '#6366f1' WHERE LOWER(name) = LOWER('Intake received');
UPDATE ticket_statuses SET sort_order = 2, color = '#0ea5e9' WHERE LOWER(name) = LOWER('Bench work active');
UPDATE ticket_statuses SET sort_order = 3, color = '#8b5cf6' WHERE LOWER(name) = LOWER('Diagnostic underway');
UPDATE ticket_statuses SET sort_order = 4, color = '#f59e0b' WHERE LOWER(name) = LOWER('Parts on order');
UPDATE ticket_statuses SET sort_order = 5, color = '#d97706' WHERE LOWER(name) = LOWER('Parts quote needed');
UPDATE ticket_statuses SET sort_order = 6, color = '#10b981' WHERE LOWER(name) = LOWER('Parts ready - device needed');
UPDATE ticket_statuses SET sort_order = 7, color = '#14b8a6' WHERE LOWER(name) = LOWER('Repair complete - final check');
UPDATE ticket_statuses SET sort_order = 8, color = '#a855f7' WHERE LOWER(name) = LOWER('Diagnostic ready');
UPDATE ticket_statuses SET sort_order = 9, color = '#f97316' WHERE LOWER(name) = LOWER('Customer response needed');
UPDATE ticket_statuses SET sort_order = 10, color = '#6b7280' WHERE LOWER(name) = LOWER('On Hold');
UPDATE ticket_statuses SET sort_order = 11, color = '#22c55e' WHERE LOWER(name) = LOWER('Paid and picked up');
UPDATE ticket_statuses SET sort_order = 12, color = '#16a34a' WHERE LOWER(name) = LOWER('Closed');
UPDATE ticket_statuses SET sort_order = 13, color = '#ef4444' WHERE LOWER(name) = LOWER('Job cancelled');
UPDATE ticket_statuses SET sort_order = 14, color = '#eab308' WHERE LOWER(name) = LOWER('Warranty repair');

-- AUDIT-S3: Catch any remaining generic all-caps statuses.
UPDATE ticket_statuses SET name = 'Open' WHERE name = 'OPEN';
UPDATE ticket_statuses SET name = 'Closed' WHERE name = 'CLOSED';
UPDATE ticket_statuses SET name = 'On Hold' WHERE name = 'ON HOLD';
UPDATE ticket_statuses SET name = 'Parts ready - device needed' WHERE name = 'PARTS READY - DEVICE NEEDED';
UPDATE ticket_statuses SET name = 'Warranty repair' WHERE name = 'WARRANTY REPAIR';
UPDATE ticket_statuses SET name = 'Special-order parts pending' WHERE name = 'SPECIAL-ORDER PARTS PENDING';
