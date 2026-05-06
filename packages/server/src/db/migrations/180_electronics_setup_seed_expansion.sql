-- 180_electronics_setup_seed_expansion.sql
-- Enrich electronics setup presets with practical repair-service coverage.
--
-- These are generic BizarreCRM service names. They are intentionally not copied
-- from any customer reference sheet, and this migration does not seed prices.

-- Keep current major phone/tablet models available for existing installs. The
-- startup seed is idempotent, but this migration avoids relying on model counts
-- when a shop already has custom device rows.
INSERT OR IGNORE INTO manufacturers (name, slug) VALUES
  ('Apple', 'apple'),
  ('Samsung', 'samsung'),
  ('Google', 'google'),
  ('OnePlus', 'oneplus');

WITH model_seed(manufacturer_slug, name, slug, category, release_year, is_popular) AS (
  VALUES
    ('apple', 'iPhone 17 Pro Max', 'iphone-17-pro-max', 'phone', 2025, 1),
    ('apple', 'iPhone 17 Pro', 'iphone-17-pro', 'phone', 2025, 1),
    ('apple', 'iPhone Air', 'iphone-air', 'phone', 2025, 1),
    ('apple', 'iPhone 17', 'iphone-17', 'phone', 2025, 1),
    ('apple', 'iPhone 17e', 'iphone-17e', 'phone', 2026, 1),
    ('apple', 'iPhone 16e', 'iphone-16e', 'phone', 2025, 1),
    ('apple', 'iPad Pro 13" (M5)', 'ipad-pro-13-m5', 'tablet', 2025, 1),
    ('apple', 'iPad Pro 11" (M5)', 'ipad-pro-11-m5', 'tablet', 2025, 1),
    ('apple', 'iPad Air 13" (M4)', 'ipad-air-13-m4', 'tablet', 2026, 1),
    ('apple', 'iPad Air 11" (M4)', 'ipad-air-11-m4', 'tablet', 2026, 1),
    ('apple', 'iPad (A16)', 'ipad-a16', 'tablet', 2025, 1),
    ('apple', 'iPad mini (A17 Pro)', 'ipad-mini-a17-pro', 'tablet', 2024, 1),
    ('samsung', 'Galaxy S26 Ultra', 'galaxy-s26-ultra', 'phone', 2026, 1),
    ('samsung', 'Galaxy S26+', 'galaxy-s26-plus', 'phone', 2026, 1),
    ('samsung', 'Galaxy S26', 'galaxy-s26', 'phone', 2026, 1),
    ('samsung', 'Galaxy S25 Ultra', 'galaxy-s25-ultra', 'phone', 2025, 1),
    ('samsung', 'Galaxy S25 Edge', 'galaxy-s25-edge', 'phone', 2025, 1),
    ('samsung', 'Galaxy S25+', 'galaxy-s25-plus', 'phone', 2025, 1),
    ('samsung', 'Galaxy S25', 'galaxy-s25', 'phone', 2025, 1),
    ('samsung', 'Galaxy S25 FE', 'galaxy-s25-fe', 'phone', 2025, 1),
    ('samsung', 'Galaxy Z Fold 7', 'galaxy-z-fold-7', 'phone', 2025, 1),
    ('samsung', 'Galaxy Z Flip 7', 'galaxy-z-flip-7', 'phone', 2025, 1),
    ('samsung', 'Galaxy Z Flip 7 FE', 'galaxy-z-flip-7-fe', 'phone', 2025, 1),
    ('samsung', 'Galaxy Z Fold 6', 'galaxy-z-fold-6', 'phone', 2024, 1),
    ('samsung', 'Galaxy Z Flip 6', 'galaxy-z-flip-6', 'phone', 2024, 1),
    ('samsung', 'Galaxy A56 5G', 'galaxy-a56-5g', 'phone', 2025, 1),
    ('samsung', 'Galaxy A36 5G', 'galaxy-a36-5g', 'phone', 2025, 0),
    ('samsung', 'Galaxy A26 5G', 'galaxy-a26-5g', 'phone', 2025, 0),
    ('samsung', 'Galaxy A16 5G', 'galaxy-a16-5g', 'phone', 2024, 0),
    ('samsung', 'Galaxy Tab S11 Ultra', 'galaxy-tab-s11-ultra', 'tablet', 2025, 1),
    ('samsung', 'Galaxy Tab S11', 'galaxy-tab-s11', 'tablet', 2025, 1),
    ('samsung', 'Galaxy Tab S10 Ultra', 'galaxy-tab-s10-ultra', 'tablet', 2024, 1),
    ('samsung', 'Galaxy Tab S10+', 'galaxy-tab-s10-plus', 'tablet', 2024, 1),
    ('google', 'Pixel 10 Pro Fold', 'pixel-10-pro-fold', 'phone', 2025, 1),
    ('google', 'Pixel 10 Pro XL', 'pixel-10-pro-xl', 'phone', 2025, 1),
    ('google', 'Pixel 10 Pro', 'pixel-10-pro', 'phone', 2025, 1),
    ('google', 'Pixel 10', 'pixel-10', 'phone', 2025, 1),
    ('google', 'Pixel 9a', 'pixel-9a', 'phone', 2025, 1),
    ('google', 'Pixel 9 Pro Fold', 'pixel-9-pro-fold', 'phone', 2024, 1),
    ('oneplus', 'OnePlus 13', 'oneplus-13', 'phone', 2025, 0),
    ('oneplus', 'OnePlus 13R', 'oneplus-13r', 'phone', 2025, 0)
)
INSERT OR IGNORE INTO device_models
  (manufacturer_id, name, slug, category, release_year, is_popular)
SELECT manufacturers.id, model_seed.name, model_seed.slug, model_seed.category,
       model_seed.release_year, model_seed.is_popular
FROM model_seed
JOIN manufacturers ON manufacturers.slug = model_seed.manufacturer_slug;

-- Reword the default status slots into BizarreCRM language. The match uses
-- sort/color/flags instead of external reference labels so the migration does
-- not embed customer-provided status names.
UPDATE ticket_statuses SET name = 'Intake received'
WHERE sort_order = 0 AND is_default = 1 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Intake received');
UPDATE ticket_statuses SET name = 'Parts quote needed'
WHERE sort_order = 1 AND color = '#ef4444' AND is_cancelled = 0
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Parts quote needed');
UPDATE ticket_statuses SET name = 'Parts received - bench queue'
WHERE sort_order = 2 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Parts received - bench queue');
UPDATE ticket_statuses SET name = 'Diagnostic underway'
WHERE sort_order = 3 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Diagnostic underway');
UPDATE ticket_statuses SET name = 'Bench work active'
WHERE sort_order = 4 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Bench work active');
UPDATE ticket_statuses SET name = 'Diagnostic ready'
WHERE sort_order = 5 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Diagnostic ready');
UPDATE ticket_statuses SET name = 'Repair complete - final check'
WHERE sort_order = 6 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Repair complete - final check');
UPDATE ticket_statuses SET name = 'Final check passed'
WHERE sort_order = 7 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Final check passed');
UPDATE ticket_statuses SET name = 'Final check needs review'
WHERE sort_order = 8 AND color = '#3b82f6'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Final check needs review');
UPDATE ticket_statuses SET name = 'Parts ready - device needed'
WHERE sort_order = 9 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Parts ready - device needed');
UPDATE ticket_statuses SET name = 'Awaiting related device'
WHERE sort_order = 10 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Awaiting related device');
UPDATE ticket_statuses SET name = 'In transit'
WHERE sort_order = 11 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'In transit');
UPDATE ticket_statuses SET name = 'Estimate approval needed'
WHERE sort_order = 12 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Estimate approval needed');
UPDATE ticket_statuses SET name = 'Customer response needed'
WHERE sort_order = 13 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Customer response needed');
UPDATE ticket_statuses SET name = 'Customer approval pending'
WHERE sort_order = 14 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Customer approval pending');
UPDATE ticket_statuses SET name = 'Parts on order'
WHERE sort_order = 15 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Parts on order');
UPDATE ticket_statuses SET name = 'Complete - balance due'
WHERE sort_order = 16 AND color = '#f97316'
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Complete - balance due');
UPDATE ticket_statuses SET name = 'Ready after repair'
WHERE sort_order = 17 AND color = '#22c55e' AND is_closed = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Ready after repair');
UPDATE ticket_statuses SET name = 'Paid - ready to ship'
WHERE sort_order = 18 AND color = '#22c55e' AND is_closed = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Paid - ready to ship');
UPDATE ticket_statuses SET name = 'Shipped'
WHERE sort_order = 19 AND color = '#22c55e' AND is_closed = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Shipped');
UPDATE ticket_statuses SET name = 'Repaired and collected'
WHERE sort_order = 20 AND color = '#22c55e' AND is_closed = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Repaired and collected');
UPDATE ticket_statuses SET name = 'Paid and picked up'
WHERE sort_order = 21 AND color = '#22c55e' AND is_closed = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Paid and picked up');
UPDATE ticket_statuses SET name = 'Job cancelled'
WHERE sort_order = 22 AND color = '#ef4444' AND is_cancelled = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Job cancelled');
UPDATE ticket_statuses SET name = 'Not economical to repair'
WHERE sort_order = 23 AND color = '#ef4444' AND is_cancelled = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Not economical to repair');
UPDATE ticket_statuses SET name = 'Disposal completed'
WHERE sort_order = 24 AND color = '#ef4444' AND is_cancelled = 1
  AND NOT EXISTS (SELECT 1 FROM ticket_statuses WHERE name = 'Disposal completed');

INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  -- Phone service families
  ('Camera Lens Cover Service', 'phone-camera-lens-cover', 'phone', 11),
  ('Liquid Exposure Cleaning', 'phone-liquid-cleaning', 'phone', 12),
  ('Board-Level Diagnostic', 'phone-board-diagnostic', 'phone', 13),
  ('Data Transfer', 'phone-data-transfer', 'phone', 14),
  ('Software Restore / Update', 'phone-software-restore', 'phone', 15),
  ('Activation / SIM Assistance', 'phone-activation-sim', 'phone', 16),
  ('Post-Repair Calibration', 'phone-post-repair-calibration', 'phone', 17),
  ('Small Component Service', 'phone-small-components', 'phone', 18),
  ('Port Cleaning', 'phone-port-cleaning', 'phone', 19),
  ('Protective Film Install', 'phone-protective-film-install', 'phone', 20),

  -- Tablet service families
  ('Diagnostic', 'tablet-diagnostic', 'tablet', 2),
  ('Charging Port Service', 'tablet-charging-port', 'tablet', 3),
  ('Glass / Digitizer Service', 'tablet-glass-digitizer', 'tablet', 4),
  ('Camera Service', 'tablet-camera-service', 'tablet', 5),
  ('Speaker Service', 'tablet-speaker-service', 'tablet', 6),
  ('Button Service', 'tablet-button-service', 'tablet', 7),
  ('Software Restore / Update', 'tablet-software-restore', 'tablet', 8),
  ('Keyboard / Accessory Connector Service', 'tablet-keyboard-connector', 'tablet', 9),
  ('Frame / Housing Service', 'tablet-frame-housing', 'tablet', 10),
  ('Data Transfer', 'tablet-data-transfer', 'tablet', 11),
  ('Other Tablet Repair', 'tablet-other', 'tablet', 12),

  -- Laptop and computer bench service families
  ('Data Backup', 'laptop-data-backup', 'laptop', 14),
  ('Data Recovery Triage', 'laptop-data-recovery-triage', 'laptop', 15),
  ('Malware Cleanup', 'laptop-malware-cleanup', 'laptop', 16),
  ('Password / Account Assistance', 'laptop-password-account-help', 'laptop', 17),
  ('System Tune-Up', 'laptop-system-tune-up', 'laptop', 18),
  ('Top Case Service', 'laptop-top-case-service', 'laptop', 19),
  ('Liquid Diagnostic', 'laptop-liquid-diagnostic', 'laptop', 20),
  ('Diagnostic', 'desktop-diagnostic', 'desktop', 9),
  ('Data Backup', 'desktop-data-backup', 'desktop', 10),
  ('Data Recovery Triage', 'desktop-data-recovery-triage', 'desktop', 11),
  ('Malware Cleanup', 'desktop-malware-cleanup', 'desktop', 12),
  ('Custom PC Build / Rebuild', 'desktop-custom-build', 'desktop', 13),
  ('Thermal Service', 'desktop-thermal-service', 'desktop', 14),
  ('Network Setup', 'desktop-network-setup', 'desktop', 15),
  ('Printer Setup', 'desktop-printer-setup', 'desktop', 16),

  -- Console and handheld gaming service families
  ('Diagnostic', 'console-diagnostic', 'console', 4),
  ('USB-C / Charge Port Service', 'console-usb-c-port', 'console', 5),
  ('Fan / Thermal Service', 'console-fan-thermal', 'console', 6),
  ('Deep Cleaning', 'console-deep-cleaning', 'console', 7),
  ('Storage Service', 'console-storage-service', 'console', 8),
  ('Controller Stick Service', 'console-controller-stick', 'console', 9),
  ('Controller Button Service', 'console-controller-buttons', 'console', 10),
  ('Controller Charge Port Service', 'console-controller-charge-port', 'console', 11),
  ('Controller Battery Service', 'console-controller-battery', 'console', 12),
  ('Handheld Display Service', 'console-handheld-display', 'console', 13),
  ('Power Module Service', 'console-power-module', 'console', 14),
  ('Board-Level Diagnostic', 'console-board-diagnostic', 'console', 15),
  ('Firmware / System Recovery', 'console-firmware-recovery', 'console', 16),
  ('Game Card Slot Service', 'console-game-card-slot', 'console', 17),

  -- TV, monitor, projector, and consumer-electronics service families
  ('Panel Assessment', 'tv-panel-assessment', 'tv', 22),
  ('Input Board Service', 'tv-input-board', 'tv', 23),
  ('Firmware / Smart Reset', 'tv-firmware-smart-reset', 'tv', 24),
  ('Remote / IR Service', 'tv-remote-ir', 'tv', 25),
  ('Wi-Fi Module Service', 'tv-wifi-module', 'tv', 26),
  ('Projector Lamp Service', 'tv-projector-lamp', 'tv', 27),
  ('Monitor Input Service', 'tv-monitor-input', 'tv', 28),
  ('Pickup / Remount Handling', 'tv-pickup-remount', 'tv', 29);

-- Add richer default condition checks without duplicating labels on re-run.

INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Rear cover condition', 15 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Rear cover condition');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Frame bend or separation', 16 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Frame bend or separation');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Wireless charging', 17 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Wireless charging');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Cellular / SIM read', 18 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Cellular / SIM read');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Liquid indicator checked', 19 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Liquid indicator checked');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Prior repair signs', 20 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Prior repair signs');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Intake photos taken', 21 FROM condition_templates ct
WHERE ct.category = 'phone' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Intake photos taken');

INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Stylus / pencil included', 8 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Stylus / pencil included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Keyboard / case connector', 9 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Keyboard / case connector');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Touch dead zones', 10 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Touch dead zones');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Rotation sensor', 11 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Rotation sensor');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Managed profile visible', 12 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Managed profile visible');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Charger included', 13 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Charger included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Intake photos taken', 14 FROM condition_templates ct
WHERE ct.category = 'tablet' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Intake photos taken');

INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'External display output', 12 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'External display output');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Storage health / SMART status', 13 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Storage health / SMART status');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Fan noise / thermal symptom', 14 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Fan noise / thermal symptom');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Liquid signs', 15 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Liquid signs');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Encryption or lock screen noted', 16 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Encryption or lock screen noted');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Charger included', 17 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Charger included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Intake photos taken', 18 FROM condition_templates ct
WHERE ct.category = 'laptop' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Intake photos taken');

INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Display output', 8 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Display output');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Storage detected', 9 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Storage detected');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Game card slot tested', 10 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Game card slot tested');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Dock / controller accessory tested', 11 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Dock / controller accessory tested');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Power supply or cable included', 12 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Power supply or cable included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Save data risk acknowledged', 13 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Save data risk acknowledged');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Intake photos taken', 14 FROM condition_templates ct
WHERE ct.category = 'console' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Intake photos taken');

INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Screen size recorded', 8 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Screen size recorded');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Remote included', 9 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Remote included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Stand included', 10 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Stand included');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Wall mount status', 11 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Wall mount status');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Backlight symptom check', 12 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Backlight symptom check');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'HDMI / input behavior', 13 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'HDMI / input behavior');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Panel crack or pressure mark', 14 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Panel crack or pressure mark');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Pickup / delivery note', 15 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Pickup / delivery note');
INSERT INTO condition_checks (template_id, label, sort_order)
SELECT ct.id, 'Intake photos taken', 16 FROM condition_templates ct
WHERE ct.category = 'tv' AND ct.is_default = 1
  AND NOT EXISTS (SELECT 1 FROM condition_checks cc WHERE cc.template_id = ct.id AND cc.label = 'Intake photos taken');
