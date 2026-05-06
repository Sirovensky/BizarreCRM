-- DPI-12 / DPI-14 / DPI-15: additive seed-data expansion.
-- Historical migration 158 already exists in this branch, so this work lands
-- in the next available migration number.

-- DPI-12: expand the repair service catalog without changing historical seeds.
INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  -- Console
  ('Joystick Repair', 'console-joystick-repair', 'console', 4),
  ('Joystick Drift Fix', 'console-joystick-drift', 'console', 5),
  ('Fan Replacement', 'console-fan-replacement', 'console', 6),
  ('Thermal Paste Service', 'console-thermal-paste', 'console', 7),
  ('Power Button Repair', 'console-power-button', 'console', 8),
  ('Eject Mechanism Repair', 'console-eject-mechanism', 'console', 9),
  ('BD Drive Laser Replacement', 'console-bd-drive-laser', 'console', 10),
  ('Hard Drive Upgrade', 'console-hard-drive-upgrade', 'console', 11),
  ('Controller Button Repair', 'console-controller-buttons', 'console', 12),
  ('Controller Charge Port Repair', 'console-controller-charge-port', 'console', 13),
  ('Controller Battery Replacement', 'console-controller-battery', 'console', 14),
  ('Firmware Reset', 'console-firmware-reset', 'console', 15),

  -- Tablet
  ('Charging Port Repair', 'tablet-charging-port', 'tablet', 2),
  ('Camera Repair', 'tablet-camera', 'tablet', 3),
  ('Button Repair', 'tablet-button-repair', 'tablet', 4),
  ('Water Damage Diagnostic', 'tablet-water-damage-diagnostic', 'tablet', 5),
  ('Back Glass Replacement', 'tablet-back-glass', 'tablet', 6),
  ('Speaker Repair', 'tablet-speaker', 'tablet', 7),
  ('Microphone Repair', 'tablet-microphone', 'tablet', 8),
  ('Software Reset', 'tablet-software-reset', 'tablet', 9),
  ('Jailbreak Removal', 'tablet-jailbreak-removal', 'tablet', 10),
  ('Glass-Only Repair', 'tablet-glass-only', 'tablet', 11),

  -- IT services
  ('Virus Removal', 'it-virus-removal', 'it_service', 0),
  ('Malware Cleanup', 'it-malware-cleanup', 'it_service', 1),
  ('OS Reinstall', 'it-os-reinstall', 'it_service', 2),
  ('Drive Imaging Data Recovery', 'it-drive-imaging-data-recovery', 'it_service', 3),
  ('Home Network Setup', 'it-home-network-setup', 'it_service', 4),
  ('Small Office Network Setup', 'it-small-office-network-setup', 'it_service', 5),
  ('Printer Setup', 'it-printer-setup', 'it_service', 6),
  ('Password Reset', 'it-password-reset', 'it_service', 7),
  ('In-Home Diagnostic Visit', 'it-in-home-diagnostic', 'it_service', 8),

  -- Phone
  ('Face ID Repair', 'face-id-repair', 'phone', 11),
  ('True Tone Calibration', 'true-tone-calibration', 'phone', 12),
  ('eSIM Activation Help', 'esim-activation-help', 'phone', 13),
  ('Jailbreak / De-Jailbreak Service', 'phone-jailbreak-service', 'phone', 14),
  ('MDM Unlock Verification', 'mdm-unlock-proof', 'phone', 15),

  -- Laptop
  ('Backlight Repair', 'laptop-backlight', 'laptop', 14),
  ('Trackpad Repair', 'laptop-trackpad', 'laptop', 15),
  ('HDMI Port Repair', 'laptop-hdmi', 'laptop', 16),
  ('Audio Jack Repair', 'laptop-audio-jack', 'laptop', 17),
  ('BIOS Unlock', 'laptop-bios-unlock', 'laptop', 18),
  ('Password Reset', 'laptop-password-reset', 'laptop', 19),

  -- TV. HDMI port repair already exists as tv-hdmi in migration 010.
  ('Audio Output Repair', 'tv-audio-output', 'tv', 22),
  ('Voice Remote Pairing', 'tv-voice-remote-pairing', 'tv', 23),
  ('Smart Feature Reset', 'tv-smart-feature-reset', 'tv', 24),
  ('Wall-Mount Install Service', 'tv-wall-mount-install', 'tv', 25);

-- DPI-14: seed the missing TV manufacturers/models. The current schema has no
-- dedicated screen_size or panel_type columns, so both are encoded in the name.
INSERT OR IGNORE INTO manufacturers (name, slug) VALUES
  ('Samsung', 'samsung'),
  ('LG', 'lg'),
  ('Sony', 'sony'),
  ('TCL', 'tcl'),
  ('Vizio', 'vizio'),
  ('Hisense', 'hisense'),
  ('Philips', 'philips');

WITH tv_model_seed(manufacturer_slug, name, slug, release_year, is_popular) AS (
  VALUES
    ('samsung', 'UN43TU7000 43" LED', 'samsung-un43tu7000-43-led', 2020, 0),
    ('samsung', 'UN50TU7000 50" LED', 'samsung-un50tu7000-50-led', 2020, 1),
    ('samsung', 'UN55TU7000 55" LED', 'samsung-un55tu7000-55-led', 2020, 1),
    ('samsung', 'QN55Q60A 55" QLED', 'samsung-qn55q60a-55-qled', 2021, 1),
    ('samsung', 'QN65Q60A 65" QLED', 'samsung-qn65q60a-65-qled', 2021, 1),
    ('samsung', 'QN65QN90A 65" Neo QLED', 'samsung-qn65qn90a-65-neo-qled', 2021, 1),
    ('samsung', 'QN85QN90A 85" Neo QLED', 'samsung-qn85qn90a-85-neo-qled', 2021, 0),
    ('samsung', 'QN65QN90B 65" Neo QLED', 'samsung-qn65qn90b-65-neo-qled', 2022, 1),
    ('samsung', 'QN77S95C 77" OLED', 'samsung-qn77s95c-77-oled', 2023, 0),
    ('samsung', 'PN60F5300 60" Plasma', 'samsung-pn60f5300-60-plasma', 2013, 0),
    ('lg', '43UP7000 43" LED', 'lg-43up7000-43-led', 2021, 0),
    ('lg', '50UP7000 50" LED', 'lg-50up7000-50-led', 2021, 1),
    ('lg', '55UP8000 55" LED', 'lg-55up8000-55-led', 2021, 1),
    ('lg', '65UP8000 65" LED', 'lg-65up8000-65-led', 2021, 1),
    ('lg', '65NANO90 65" NanoCell LED', 'lg-65nano90-65-nanocell-led', 2021, 0),
    ('lg', 'OLED55CX 55" OLED', 'lg-oled55cx-55-oled', 2020, 1),
    ('lg', 'OLED65C1 65" OLED', 'lg-oled65c1-65-oled', 2021, 1),
    ('lg', 'OLED65C2 65" OLED', 'lg-oled65c2-65-oled', 2022, 1),
    ('lg', 'OLED77C3 77" OLED', 'lg-oled77c3-77-oled', 2023, 0),
    ('lg', '50PN4500 50" Plasma', 'lg-50pn4500-50-plasma', 2013, 0),
    ('sony', 'XBR-43X800H 43" LED', 'sony-xbr-43x800h-43-led', 2020, 0),
    ('sony', 'XBR-55X900H 55" LED', 'sony-xbr-55x900h-55-led', 2020, 1),
    ('sony', 'XBR-65X900H 65" LED', 'sony-xbr-65x900h-65-led', 2020, 1),
    ('sony', 'XR-55X90J 55" LED', 'sony-xr-55x90j-55-led', 2021, 1),
    ('sony', 'XR-65X90J 65" LED', 'sony-xr-65x90j-65-led', 2021, 1),
    ('sony', 'XR-55A80J 55" OLED', 'sony-xr-55a80j-55-oled', 2021, 1),
    ('sony', 'XR-65A80J 65" OLED', 'sony-xr-65a80j-65-oled', 2021, 1),
    ('sony', 'XR-65X90K 65" LED', 'sony-xr-65x90k-65-led', 2022, 1),
    ('sony', 'XR-85X90K 85" LED', 'sony-xr-85x90k-85-led', 2022, 0),
    ('sony', 'XR-77A80L 77" OLED', 'sony-xr-77a80l-77-oled', 2023, 0),
    ('vizio', 'V405-H19 40" LED', 'vizio-v405-h19-40-led', 2020, 0),
    ('vizio', 'V505-J09 50" LED', 'vizio-v505-j09-50-led', 2021, 1),
    ('vizio', 'V555-J01 55" LED', 'vizio-v555-j01-55-led', 2021, 1),
    ('vizio', 'V655-J09 65" LED', 'vizio-v655-j09-65-led', 2021, 1),
    ('vizio', 'M50Q7-H1 50" QLED', 'vizio-m50q7-h1-50-qled', 2020, 0),
    ('vizio', 'M55Q7-J01 55" QLED', 'vizio-m55q7-j01-55-qled', 2021, 1),
    ('vizio', 'M65Q7-J01 65" QLED', 'vizio-m65q7-j01-65-qled', 2021, 1),
    ('vizio', 'P65Q9-H1 65" QLED', 'vizio-p65q9-h1-65-qled', 2020, 0),
    ('vizio', 'P75Q9-J01 75" QLED', 'vizio-p75q9-j01-75-qled', 2021, 0),
    ('vizio', 'OLED55-H1 55" OLED', 'vizio-oled55-h1-55-oled', 2020, 0),
    ('hisense', '43A6G 43" LED', 'hisense-43a6g-43-led', 2021, 0),
    ('hisense', '50A6G 50" LED', 'hisense-50a6g-50-led', 2021, 1),
    ('hisense', '55A6G 55" LED', 'hisense-55a6g-55-led', 2021, 1),
    ('hisense', '65A6G 65" LED', 'hisense-65a6g-65-led', 2021, 1),
    ('hisense', '55U6G 55" QLED', 'hisense-55u6g-55-qled', 2021, 1),
    ('hisense', '65U6G 65" QLED', 'hisense-65u6g-65-qled', 2021, 1),
    ('hisense', '55U7G 55" QLED', 'hisense-55u7g-55-qled', 2021, 0),
    ('hisense', '65U8G 65" QLED', 'hisense-65u8g-65-qled', 2021, 1),
    ('hisense', '65U8H 65" Mini-LED QLED', 'hisense-65u8h-65-mini-led-qled', 2022, 1),
    ('hisense', '75U8K 75" Mini-LED QLED', 'hisense-75u8k-75-mini-led-qled', 2023, 0),
    ('tcl', '40S325 40" LED', 'tcl-40s325-40-led', 2019, 0),
    ('tcl', '43S435 43" LED', 'tcl-43s435-43-led', 2020, 0),
    ('tcl', '50S435 50" LED', 'tcl-50s435-50-led', 2020, 1),
    ('tcl', '55S435 55" LED', 'tcl-55s435-55-led', 2020, 1),
    ('tcl', '65S435 65" LED', 'tcl-65s435-65-led', 2020, 1),
    ('tcl', '55R635 55" QLED', 'tcl-55r635-55-qled', 2020, 1),
    ('tcl', '65R635 65" QLED', 'tcl-65r635-65-qled', 2020, 1),
    ('tcl', '65R646 65" QLED', 'tcl-65r646-65-qled', 2021, 1),
    ('tcl', '75R655 75" QLED', 'tcl-75r655-75-qled', 2022, 0),
    ('philips', '43PFL5604/F7 43" LED', 'philips-43pfl5604-f7-43-led', 2019, 0),
    ('philips', '50PFL5604/F7 50" LED', 'philips-50pfl5604-f7-50-led', 2019, 0),
    ('philips', '55PFL5604/F7 55" LED', 'philips-55pfl5604-f7-55-led', 2019, 1),
    ('philips', '65PFL5504/F7 65" LED', 'philips-65pfl5504-f7-65-led', 2019, 0),
    ('philips', '50PFL5704/F7 50" LED', 'philips-50pfl5704-f7-50-led', 2020, 0),
    ('philips', '55PFL5756/F7 55" LED', 'philips-55pfl5756-f7-55-led', 2021, 0),
    ('philips', '65PFL5766/F7 65" LED', 'philips-65pfl5766-f7-65-led', 2021, 0),
    ('philips', '65OLED706 65" OLED', 'philips-65oled706-65-oled', 2021, 0)
)
INSERT OR IGNORE INTO device_models
  (manufacturer_id, name, slug, category, release_year, is_popular)
SELECT manufacturers.id, tv_model_seed.name, tv_model_seed.slug, 'tv',
       tv_model_seed.release_year, tv_model_seed.is_popular
FROM tv_model_seed
JOIN manufacturers ON manufacturers.slug = tv_model_seed.manufacturer_slug;

-- DPI-15: backfill release_year on any pre-existing copy of these TV seeds.
WITH tv_model_seed(manufacturer_slug, slug, release_year) AS (
  VALUES
    ('samsung', 'samsung-un43tu7000-43-led', 2020),
    ('samsung', 'samsung-un50tu7000-50-led', 2020),
    ('samsung', 'samsung-un55tu7000-55-led', 2020),
    ('samsung', 'samsung-qn55q60a-55-qled', 2021),
    ('samsung', 'samsung-qn65q60a-65-qled', 2021),
    ('samsung', 'samsung-qn65qn90a-65-neo-qled', 2021),
    ('samsung', 'samsung-qn85qn90a-85-neo-qled', 2021),
    ('samsung', 'samsung-qn65qn90b-65-neo-qled', 2022),
    ('samsung', 'samsung-qn77s95c-77-oled', 2023),
    ('samsung', 'samsung-pn60f5300-60-plasma', 2013),
    ('lg', 'lg-43up7000-43-led', 2021),
    ('lg', 'lg-50up7000-50-led', 2021),
    ('lg', 'lg-55up8000-55-led', 2021),
    ('lg', 'lg-65up8000-65-led', 2021),
    ('lg', 'lg-65nano90-65-nanocell-led', 2021),
    ('lg', 'lg-oled55cx-55-oled', 2020),
    ('lg', 'lg-oled65c1-65-oled', 2021),
    ('lg', 'lg-oled65c2-65-oled', 2022),
    ('lg', 'lg-oled77c3-77-oled', 2023),
    ('lg', 'lg-50pn4500-50-plasma', 2013),
    ('sony', 'sony-xbr-43x800h-43-led', 2020),
    ('sony', 'sony-xbr-55x900h-55-led', 2020),
    ('sony', 'sony-xbr-65x900h-65-led', 2020),
    ('sony', 'sony-xr-55x90j-55-led', 2021),
    ('sony', 'sony-xr-65x90j-65-led', 2021),
    ('sony', 'sony-xr-55a80j-55-oled', 2021),
    ('sony', 'sony-xr-65a80j-65-oled', 2021),
    ('sony', 'sony-xr-65x90k-65-led', 2022),
    ('sony', 'sony-xr-85x90k-85-led', 2022),
    ('sony', 'sony-xr-77a80l-77-oled', 2023),
    ('vizio', 'vizio-v405-h19-40-led', 2020),
    ('vizio', 'vizio-v505-j09-50-led', 2021),
    ('vizio', 'vizio-v555-j01-55-led', 2021),
    ('vizio', 'vizio-v655-j09-65-led', 2021),
    ('vizio', 'vizio-m50q7-h1-50-qled', 2020),
    ('vizio', 'vizio-m55q7-j01-55-qled', 2021),
    ('vizio', 'vizio-m65q7-j01-65-qled', 2021),
    ('vizio', 'vizio-p65q9-h1-65-qled', 2020),
    ('vizio', 'vizio-p75q9-j01-75-qled', 2021),
    ('vizio', 'vizio-oled55-h1-55-oled', 2020),
    ('hisense', 'hisense-43a6g-43-led', 2021),
    ('hisense', 'hisense-50a6g-50-led', 2021),
    ('hisense', 'hisense-55a6g-55-led', 2021),
    ('hisense', 'hisense-65a6g-65-led', 2021),
    ('hisense', 'hisense-55u6g-55-qled', 2021),
    ('hisense', 'hisense-65u6g-65-qled', 2021),
    ('hisense', 'hisense-55u7g-55-qled', 2021),
    ('hisense', 'hisense-65u8g-65-qled', 2021),
    ('hisense', 'hisense-65u8h-65-mini-led-qled', 2022),
    ('hisense', 'hisense-75u8k-75-mini-led-qled', 2023),
    ('tcl', 'tcl-40s325-40-led', 2019),
    ('tcl', 'tcl-43s435-43-led', 2020),
    ('tcl', 'tcl-50s435-50-led', 2020),
    ('tcl', 'tcl-55s435-55-led', 2020),
    ('tcl', 'tcl-65s435-65-led', 2020),
    ('tcl', 'tcl-55r635-55-qled', 2020),
    ('tcl', 'tcl-65r635-65-qled', 2020),
    ('tcl', 'tcl-65r646-65-qled', 2021),
    ('tcl', 'tcl-75r655-75-qled', 2022),
    ('philips', 'philips-43pfl5604-f7-43-led', 2019),
    ('philips', 'philips-50pfl5604-f7-50-led', 2019),
    ('philips', 'philips-55pfl5604-f7-55-led', 2019),
    ('philips', 'philips-65pfl5504-f7-65-led', 2019),
    ('philips', 'philips-50pfl5704-f7-50-led', 2020),
    ('philips', 'philips-55pfl5756-f7-55-led', 2021),
    ('philips', 'philips-65pfl5766-f7-65-led', 2021),
    ('philips', 'philips-65oled706-65-oled', 2021)
)
UPDATE device_models
SET release_year = (
  SELECT tv_model_seed.release_year
  FROM tv_model_seed
  JOIN manufacturers ON manufacturers.slug = tv_model_seed.manufacturer_slug
  WHERE manufacturers.id = device_models.manufacturer_id
    AND tv_model_seed.slug = device_models.slug
)
WHERE release_year IS NULL
  AND EXISTS (
    SELECT 1
    FROM tv_model_seed
    JOIN manufacturers ON manufacturers.slug = tv_model_seed.manufacturer_slug
    WHERE manufacturers.id = device_models.manufacturer_id
      AND tv_model_seed.slug = device_models.slug
  );

-- SQLite cannot add NOT NULL to an existing column without rebuilding the table.
-- This migration-level CHECK guard fails the migration if any TV row it owns is
-- absent or still has a NULL release_year after the additive insert/backfill.
CREATE TEMP TABLE dpi_162_release_year_guard (
  missing_or_null_count INTEGER NOT NULL CHECK (missing_or_null_count = 0)
);

WITH tv_model_seed(manufacturer_slug, slug) AS (
  VALUES
    ('samsung', 'samsung-un43tu7000-43-led'),
    ('samsung', 'samsung-un50tu7000-50-led'),
    ('samsung', 'samsung-un55tu7000-55-led'),
    ('samsung', 'samsung-qn55q60a-55-qled'),
    ('samsung', 'samsung-qn65q60a-65-qled'),
    ('samsung', 'samsung-qn65qn90a-65-neo-qled'),
    ('samsung', 'samsung-qn85qn90a-85-neo-qled'),
    ('samsung', 'samsung-qn65qn90b-65-neo-qled'),
    ('samsung', 'samsung-qn77s95c-77-oled'),
    ('samsung', 'samsung-pn60f5300-60-plasma'),
    ('lg', 'lg-43up7000-43-led'),
    ('lg', 'lg-50up7000-50-led'),
    ('lg', 'lg-55up8000-55-led'),
    ('lg', 'lg-65up8000-65-led'),
    ('lg', 'lg-65nano90-65-nanocell-led'),
    ('lg', 'lg-oled55cx-55-oled'),
    ('lg', 'lg-oled65c1-65-oled'),
    ('lg', 'lg-oled65c2-65-oled'),
    ('lg', 'lg-oled77c3-77-oled'),
    ('lg', 'lg-50pn4500-50-plasma'),
    ('sony', 'sony-xbr-43x800h-43-led'),
    ('sony', 'sony-xbr-55x900h-55-led'),
    ('sony', 'sony-xbr-65x900h-65-led'),
    ('sony', 'sony-xr-55x90j-55-led'),
    ('sony', 'sony-xr-65x90j-65-led'),
    ('sony', 'sony-xr-55a80j-55-oled'),
    ('sony', 'sony-xr-65a80j-65-oled'),
    ('sony', 'sony-xr-65x90k-65-led'),
    ('sony', 'sony-xr-85x90k-85-led'),
    ('sony', 'sony-xr-77a80l-77-oled'),
    ('vizio', 'vizio-v405-h19-40-led'),
    ('vizio', 'vizio-v505-j09-50-led'),
    ('vizio', 'vizio-v555-j01-55-led'),
    ('vizio', 'vizio-v655-j09-65-led'),
    ('vizio', 'vizio-m50q7-h1-50-qled'),
    ('vizio', 'vizio-m55q7-j01-55-qled'),
    ('vizio', 'vizio-m65q7-j01-65-qled'),
    ('vizio', 'vizio-p65q9-h1-65-qled'),
    ('vizio', 'vizio-p75q9-j01-75-qled'),
    ('vizio', 'vizio-oled55-h1-55-oled'),
    ('hisense', 'hisense-43a6g-43-led'),
    ('hisense', 'hisense-50a6g-50-led'),
    ('hisense', 'hisense-55a6g-55-led'),
    ('hisense', 'hisense-65a6g-65-led'),
    ('hisense', 'hisense-55u6g-55-qled'),
    ('hisense', 'hisense-65u6g-65-qled'),
    ('hisense', 'hisense-55u7g-55-qled'),
    ('hisense', 'hisense-65u8g-65-qled'),
    ('hisense', 'hisense-65u8h-65-mini-led-qled'),
    ('hisense', 'hisense-75u8k-75-mini-led-qled'),
    ('tcl', 'tcl-40s325-40-led'),
    ('tcl', 'tcl-43s435-43-led'),
    ('tcl', 'tcl-50s435-50-led'),
    ('tcl', 'tcl-55s435-55-led'),
    ('tcl', 'tcl-65s435-65-led'),
    ('tcl', 'tcl-55r635-55-qled'),
    ('tcl', 'tcl-65r635-65-qled'),
    ('tcl', 'tcl-65r646-65-qled'),
    ('tcl', 'tcl-75r655-75-qled'),
    ('philips', 'philips-43pfl5604-f7-43-led'),
    ('philips', 'philips-50pfl5604-f7-50-led'),
    ('philips', 'philips-55pfl5604-f7-55-led'),
    ('philips', 'philips-65pfl5504-f7-65-led'),
    ('philips', 'philips-50pfl5704-f7-50-led'),
    ('philips', 'philips-55pfl5756-f7-55-led'),
    ('philips', 'philips-65pfl5766-f7-65-led'),
    ('philips', 'philips-65oled706-65-oled')
)
INSERT INTO dpi_162_release_year_guard (missing_or_null_count)
SELECT COUNT(*)
FROM tv_model_seed
LEFT JOIN manufacturers ON manufacturers.slug = tv_model_seed.manufacturer_slug
LEFT JOIN device_models ON device_models.manufacturer_id = manufacturers.id
  AND device_models.slug = tv_model_seed.slug
WHERE device_models.id IS NULL
  OR device_models.release_year IS NULL;

DROP TABLE dpi_162_release_year_guard;
