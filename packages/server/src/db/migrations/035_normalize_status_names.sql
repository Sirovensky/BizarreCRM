-- Normalize default repair status names to BizarreCRM wording.
-- Match by default slot metadata so this migration does not embed external
-- reference labels.

UPDATE ticket_statuses SET name = 'Parts quote needed'
WHERE sort_order = 1 AND color = '#ef4444' AND is_cancelled = 0;
UPDATE ticket_statuses SET name = 'Parts received - bench queue'
WHERE sort_order = 2 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Diagnostic underway'
WHERE sort_order = 3 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Bench work active'
WHERE sort_order = 4 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Diagnostic ready'
WHERE sort_order = 5 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Repair complete - final check'
WHERE sort_order = 6 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Final check passed'
WHERE sort_order = 7 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Final check needs review'
WHERE sort_order = 8 AND color = '#3b82f6';
UPDATE ticket_statuses SET name = 'Parts ready - device needed'
WHERE sort_order = 9 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Awaiting related device'
WHERE sort_order = 10 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'In transit'
WHERE sort_order = 11 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Estimate approval needed'
WHERE sort_order = 12 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Customer response needed'
WHERE sort_order = 13 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Customer approval pending'
WHERE sort_order = 14 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Parts on order'
WHERE sort_order = 15 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Complete - balance due'
WHERE sort_order = 16 AND color = '#f97316';
UPDATE ticket_statuses SET name = 'Ready after repair'
WHERE sort_order = 17 AND color = '#22c55e' AND is_closed = 1;
UPDATE ticket_statuses SET name = 'Paid - ready to ship'
WHERE sort_order = 18 AND color = '#22c55e' AND is_closed = 1;
UPDATE ticket_statuses SET name = 'Shipped'
WHERE sort_order = 19 AND color = '#22c55e' AND is_closed = 1;
UPDATE ticket_statuses SET name = 'Repaired and collected'
WHERE sort_order = 20 AND color = '#22c55e' AND is_closed = 1;
UPDATE ticket_statuses SET name = 'Paid and picked up'
WHERE sort_order = 21 AND color = '#22c55e' AND is_closed = 1;
UPDATE ticket_statuses SET name = 'Job cancelled'
WHERE sort_order = 22 AND color = '#ef4444' AND is_cancelled = 1;
UPDATE ticket_statuses SET name = 'Not economical to repair'
WHERE sort_order = 23 AND color = '#ef4444' AND is_cancelled = 1;
UPDATE ticket_statuses SET name = 'Disposal completed'
WHERE sort_order = 24 AND color = '#ef4444' AND is_cancelled = 1;
