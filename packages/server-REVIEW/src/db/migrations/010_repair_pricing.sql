-- Repair service types (problems): Screen Replacement, Battery Replacement, Charging Port, etc.
CREATE TABLE IF NOT EXISTS repair_services (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  name TEXT NOT NULL,
  slug TEXT NOT NULL UNIQUE,
  category TEXT,
  description TEXT,
  is_active INTEGER NOT NULL DEFAULT 1,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Repair pricing: device_model + repair_service -> labor price + default part
CREATE TABLE IF NOT EXISTS repair_prices (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_model_id INTEGER NOT NULL REFERENCES device_models(id),
  repair_service_id INTEGER NOT NULL REFERENCES repair_services(id),
  labor_price REAL NOT NULL DEFAULT 0,
  default_grade TEXT DEFAULT 'aftermarket',
  is_active INTEGER NOT NULL DEFAULT 1,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now')),
  UNIQUE(device_model_id, repair_service_id)
);

-- Grade options per repair price (e.g. iPhone 15 Screen has 3 grades with different parts/prices)
CREATE TABLE IF NOT EXISTS repair_price_grades (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  repair_price_id INTEGER NOT NULL REFERENCES repair_prices(id) ON DELETE CASCADE,
  grade TEXT NOT NULL,
  grade_label TEXT NOT NULL,
  part_inventory_item_id INTEGER REFERENCES inventory_items(id),
  part_catalog_item_id INTEGER REFERENCES supplier_catalog(id),
  part_price REAL NOT NULL DEFAULT 0,
  labor_price_override REAL,
  is_default INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Seed common repair services
INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  ('Screen Replacement', 'screen-replacement', 'phone', 0),
  ('Battery Replacement', 'battery-replacement', 'phone', 1),
  ('Charging Port Repair', 'charging-port', 'phone', 2),
  ('Back Glass Replacement', 'back-glass', 'phone', 3),
  ('Camera Repair', 'camera-repair', 'phone', 4),
  ('Speaker Repair', 'speaker-repair', 'phone', 5),
  ('Microphone Repair', 'microphone-repair', 'phone', 6),
  ('Water Damage Repair', 'water-damage', 'phone', 7),
  ('Button Repair', 'button-repair', 'phone', 8),
  ('Diagnostic', 'diagnostic', 'phone', 9),
  ('Other Repair', 'other-repair', 'phone', 10),
  ('Screen Replacement', 'laptop-screen', 'laptop', 0),
  ('Battery Replacement', 'laptop-battery', 'laptop', 1),
  ('Keyboard Replacement', 'keyboard', 'laptop', 2),
  ('Fan Repair/Replace', 'fan-repair', 'laptop', 3),
  ('SSD/HDD Upgrade', 'storage-upgrade', 'laptop', 4),
  ('RAM Upgrade', 'ram-upgrade', 'laptop', 5),
  ('Motherboard Repair', 'motherboard', 'laptop', 6),
  ('Charging Port Repair', 'laptop-charging-port', 'laptop', 7),
  ('Hinge Repair', 'laptop-hinge', 'laptop', 8),
  ('OS Reinstall', 'os-reinstall', 'laptop', 9),
  ('Virus Removal', 'virus-removal', 'laptop', 10),
  ('Data Transfer/Recovery', 'data-recovery', 'laptop', 11),
  ('Diagnostic', 'laptop-diagnostic', 'laptop', 12),
  ('Other Repair', 'laptop-other', 'laptop', 13),
  ('HDMI Port Repair', 'hdmi-port', 'console', 0),
  ('Disc Drive Repair', 'disc-drive', 'console', 1),
  ('Controller Repair', 'controller', 'console', 2),
  ('Overheating Fix', 'overheating', 'console', 3),
  ('Screen Replacement', 'tablet-screen', 'tablet', 0),
  ('Battery Replacement', 'tablet-battery', 'tablet', 1),
  -- TV
  ('Screen Replacement', 'tv-screen', 'tv', 0),
  ('Backlight Repair', 'tv-backlight', 'tv', 1),
  ('Power Supply Repair', 'tv-power-supply', 'tv', 2),
  ('Mainboard Repair', 'tv-mainboard', 'tv', 3),
  ('HDMI Port Repair', 'tv-hdmi', 'tv', 4),
  ('Speaker Repair', 'tv-speaker', 'tv', 5),
  ('Other TV Repair', 'tv-other', 'tv', 6),
  -- Desktop
  ('Screen Replacement', 'desktop-screen', 'desktop', 0),
  ('Power Supply Repair', 'desktop-power', 'desktop', 1),
  ('Motherboard Repair', 'desktop-motherboard', 'desktop', 2),
  ('RAM Upgrade', 'desktop-ram', 'desktop', 3),
  ('SSD/HDD Upgrade', 'desktop-storage', 'desktop', 4),
  ('GPU Repair/Replace', 'desktop-gpu', 'desktop', 5),
  ('OS Install/Repair', 'desktop-os', 'desktop', 6),
  ('Virus Removal', 'desktop-virus', 'desktop', 7),
  ('Other Desktop Repair', 'desktop-other', 'desktop', 8),
  -- Other
  ('Diagnostic', 'other-diagnostic', 'other', 0),
  ('Data Recovery', 'other-data-recovery', 'other', 1),
  ('Water Damage Repair', 'other-water-damage', 'other', 2),
  ('Other Repair', 'other-other', 'other', 3);

-- Global price adjustments are stored in store_config:
-- 'repair_price_flat_adjustment' -> e.g. "10" means +$10 on all labor
-- 'repair_price_pct_adjustment' -> e.g. "5" means +5% on all labor
