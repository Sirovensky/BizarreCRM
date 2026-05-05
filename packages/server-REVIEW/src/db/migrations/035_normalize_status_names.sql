-- Normalize ALL CAPS status names to title case
-- SQLite has no built-in title case function, so we list known ALL CAPS statuses explicitly

UPDATE ticket_statuses SET name = 'Need to Order Parts' WHERE name = 'NEED TO ORDER PARTS';
UPDATE ticket_statuses SET name = 'Payment Received & Picked Up' WHERE name = 'PAYMENT RECEIVED & PICKED UP';
UPDATE ticket_statuses SET name = 'Payment Collected - Ready for Shipment' WHERE name = 'PAYMENT COLLECTED - READY FOR SHIPMENT';
UPDATE ticket_statuses SET name = 'Device Shipped' WHERE name = 'DEVICE SHIPPED';
UPDATE ticket_statuses SET name = 'Repaired & Collected' WHERE name = 'REPAIRED & COLLECTED';
UPDATE ticket_statuses SET name = 'Waiting for Inspection' WHERE name = 'WAITING FOR INSPECTION';
UPDATE ticket_statuses SET name = 'Diagnosis - In Progress' WHERE name = 'DIAGNOSIS - IN PROGRESS';
UPDATE ticket_statuses SET name = 'Diagnosis Completed' WHERE name = 'DIAGNOSIS COMPLETED';
UPDATE ticket_statuses SET name = 'In Progress' WHERE name = 'IN PROGRESS';
UPDATE ticket_statuses SET name = 'Repaired - Pending QC' WHERE name = 'REPAIRED - PENDING QC';
UPDATE ticket_statuses SET name = 'Repaired - QC Passed' WHERE name = 'REPAIRED - QC PASSED';
UPDATE ticket_statuses SET name = 'Repaired - QC Failed' WHERE name = 'REPAIRED - QC FAILED';
UPDATE ticket_statuses SET name = 'Parts Arrived, Need the Device - SMS' WHERE name = 'PARTS ARRIVED, NEED THE DEVICE - SMS';
UPDATE ticket_statuses SET name = 'Part Received, In Queue to Fix - SMS' WHERE name = 'PART RECEIVED, IN QUEUE TO FIX - SMS';
UPDATE ticket_statuses SET name = 'Waiting for Asset' WHERE name = 'WAITING FOR ASSET';
UPDATE ticket_statuses SET name = 'In-Transit' WHERE name = 'IN-TRANSIT';
UPDATE ticket_statuses SET name = 'Approval Required' WHERE name = 'APPROVAL REQUIRED';
UPDATE ticket_statuses SET name = 'Waiting on Customer' WHERE name = 'WAITING ON CUSTOMER';
UPDATE ticket_statuses SET name = 'Pending for Customer Approval' WHERE name = 'PENDING FOR CUSTOMER APPROVAL';
UPDATE ticket_statuses SET name = 'Waiting for Parts' WHERE name = 'WAITING FOR PARTS';
UPDATE ticket_statuses SET name = 'Repaired - Waiting for Payment' WHERE name = 'REPAIRED - WAITING FOR PAYMENT';
UPDATE ticket_statuses SET name = 'Repaired' WHERE name = 'REPAIRED';
UPDATE ticket_statuses SET name = 'Cancelled' WHERE name = 'CANCELLED';
UPDATE ticket_statuses SET name = 'Disposed' WHERE name = 'DISPOSED';
UPDATE ticket_statuses SET name = 'BER (Beyond Economical Repair)' WHERE name = 'BER (BEYOND ECONOMICAL REPAIR)';
