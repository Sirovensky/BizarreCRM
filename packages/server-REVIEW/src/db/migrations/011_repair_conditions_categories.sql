-- Configurable condition checklists per device category
CREATE TABLE IF NOT EXISTS condition_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  category TEXT NOT NULL,           -- 'phone', 'tablet', 'laptop', 'desktop', 'console', 'tv', 'other'
  name TEXT NOT NULL,               -- 'Default', 'Trade In', etc.
  is_default INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE IF NOT EXISTS condition_checks (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER NOT NULL REFERENCES condition_templates(id) ON DELETE CASCADE,
  label TEXT NOT NULL,              -- 'Power Button', 'Volume Button', 'Touch Functionality', etc.
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active INTEGER NOT NULL DEFAULT 1
);

-- Seed default conditions for each device category
INSERT INTO condition_templates (category, name, is_default) VALUES
  ('phone', 'Default', 1),
  ('tablet', 'Default', 1),
  ('laptop', 'Default', 1),
  ('desktop', 'Default', 1),
  ('console', 'Default', 1),
  ('tv', 'Default', 1),
  ('other', 'Default', 1);

-- Phone default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Volume Buttons', 1),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Mute Switch', 2),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Touch Functionality', 3),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Proximity Sensor', 4),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Home Button', 5),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Face ID / Touch ID', 6),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Front Camera', 7),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Rear Camera', 8),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Speaker', 9),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Microphone', 10),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Charging Port', 11),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'WiFi', 12),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Bluetooth', 13),
  ((SELECT id FROM condition_templates WHERE category='phone' AND is_default=1), 'Battery Health', 14);

-- Laptop default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Keyboard', 1),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Trackpad', 2),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Display', 3),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Webcam', 4),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Speakers', 5),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'USB Ports', 6),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Charging Port', 7),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'WiFi', 8),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Bluetooth', 9),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Battery', 10),
  ((SELECT id FROM condition_templates WHERE category='laptop' AND is_default=1), 'Hinge', 11);

-- Console default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'HDMI Port', 1),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'USB Ports', 2),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'Disc Drive', 3),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'Fan / Cooling', 4),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'Controller Ports', 5),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'WiFi', 6),
  ((SELECT id FROM condition_templates WHERE category='console' AND is_default=1), 'Bluetooth', 7);

-- Tablet default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Display', 1),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Touch/Input', 2),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Speakers', 3),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Charging Port', 4),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'WiFi', 5),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Bluetooth', 6),
  ((SELECT id FROM condition_templates WHERE category='tablet' AND is_default=1), 'Camera', 7);

-- Desktop default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Display', 1),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Touch/Input', 2),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Speakers', 3),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Charging Port', 4),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'WiFi', 5),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Bluetooth', 6),
  ((SELECT id FROM condition_templates WHERE category='desktop' AND is_default=1), 'Camera', 7);

-- TV default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Display', 1),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Touch/Input', 2),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Speakers', 3),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Charging Port', 4),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'WiFi', 5),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Bluetooth', 6),
  ((SELECT id FROM condition_templates WHERE category='tv' AND is_default=1), 'Camera', 7);

-- Other default checks
INSERT INTO condition_checks (template_id, label, sort_order) VALUES
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Power Button', 0),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Display', 1),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Touch/Input', 2),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Speakers', 3),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Charging Port', 4),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'WiFi', 5),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Bluetooth', 6),
  ((SELECT id FROM condition_templates WHERE category='other' AND is_default=1), 'Camera', 7);
