-- Add missing TV repair services
INSERT OR IGNORE INTO repair_services (name, slug, category, sort_order) VALUES
  ('T-Con Board Repair', 'tcon-board-repair', 'tv', 20),
  ('Diagnostic', 'tv-diagnostic', 'tv', 21);
