-- Migration 172: Seed common repair services for the new watch + xr device
-- categories. Without these, the POS Issue step shows "No catalog problems for
-- this device" for any Apple Watch / Quest / Vision Pro pick, forcing the
-- cashier into "Add custom problem" for every line.
--
-- Sort orders mirror the relative frequency of incoming work in real shops:
-- screen/lens damage first (drop tickets dominate), battery + charging next,
-- mechanical (crown/strap/controller hardware) after that, software/diag last.

INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  -- ─── Smartwatch services ────────────────────────────────────────────────
  ('Screen / Glass Replacement', 'watch-screen',                'watch',  1),
  ('Battery Replacement',         'watch-battery',               'watch',  2),
  ('Back Glass / Sensor Replacement', 'watch-back-glass',        'watch',  3),
  ('Digital Crown Repair',        'watch-digital-crown',         'watch',  4),
  ('Side Button Repair',          'watch-side-button',           'watch',  5),
  ('Charging Coil / Port Repair', 'watch-charging-coil',         'watch',  6),
  ('Water Damage Repair',         'watch-water-damage',          'watch',  7),
  ('Speaker Repair',              'watch-speaker',               'watch',  8),
  ('Microphone Repair',           'watch-microphone',            'watch',  9),
  ('Strap / Band Lug Repair',     'watch-strap-lug',             'watch', 10),
  ('Heart Rate Sensor Replacement', 'watch-heart-rate-sensor',   'watch', 11),
  ('Software Reset / Re-pair',    'watch-software-reset',        'watch', 12),
  ('Activation Lock Removal (proof of purchase)', 'watch-activation-lock', 'watch', 13),
  ('Diagnostic',                  'watch-diagnostic',            'watch', 14),
  ('Other Repair',                'watch-other',                 'watch', 15),

  -- ─── VR / XR headset services ───────────────────────────────────────────
  ('Lens Replacement',            'xr-lens-replacement',         'xr',  1),
  ('Lens Polishing / Scratch Repair', 'xr-lens-polish',          'xr',  2),
  ('Head Strap Replacement',      'xr-head-strap',               'xr',  3),
  ('Face Cushion / Interface Replacement', 'xr-face-cushion',    'xr',  4),
  ('Internal Battery Replacement', 'xr-battery',                 'xr',  5),
  ('External Battery Pack Repair (Vision Pro)', 'xr-battery-pack-vp', 'xr',  6),
  ('Charging Port Repair',        'xr-charging-port',            'xr',  7),
  ('Display / Panel Replacement', 'xr-display-panel',            'xr',  8),
  ('Speaker Repair',              'xr-speaker',                  'xr',  9),
  ('Microphone Repair',           'xr-microphone',               'xr', 10),
  ('Camera / Tracking Sensor Replacement', 'xr-camera-sensor',   'xr', 11),
  ('Controller Joystick Drift Fix', 'xr-controller-drift',       'xr', 12),
  ('Controller Tracking Ring Replacement', 'xr-controller-ring', 'xr', 13),
  ('Controller Battery / Charge Port Repair', 'xr-controller-charge', 'xr', 14),
  ('Controller Button Repair',    'xr-controller-button',        'xr', 15),
  ('Firmware Reset / Re-pair',    'xr-firmware-reset',           'xr', 16),
  ('Tracking / IPD Calibration',  'xr-tracking-calibration',     'xr', 17),
  ('Diagnostic',                  'xr-diagnostic',               'xr', 18),
  ('Other Repair',                'xr-other',                    'xr', 19);
