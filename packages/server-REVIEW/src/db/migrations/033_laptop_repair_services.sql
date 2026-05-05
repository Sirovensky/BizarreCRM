-- Add missing laptop repair services
INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  ('Charging Port Repair', 'laptop-charging-port', 'laptop', 7),
  ('Hinge Repair', 'laptop-hinge', 'laptop', 8),
  ('OS Reinstall', 'os-reinstall', 'laptop', 9),
  ('Virus Removal', 'virus-removal', 'laptop', 10),
  ('Data Transfer/Recovery', 'data-recovery', 'laptop', 11),
  ('Diagnostic', 'laptop-diagnostic', 'laptop', 12),
  ('Other Repair', 'laptop-other', 'laptop', 13);
