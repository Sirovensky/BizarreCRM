-- Migration 173: Seed device_model_templates for the most-repaired phones.
--
-- Reported 2026-05-09 — Repair Templates picker showed "No templates yet"
-- for every device, defeating the whole point of templates. This migration
-- bootstraps the catalog with multi-tier templates for the top-volume
-- phones a US repair shop sees, so a tech opening a ticket on iPhone 13
-- gets one-click access to "Screen — Original", "Screen — FOG", "Screen
-- — Soft OLED", "Battery", "Charging port", "Back glass".
--
-- Pricing rationale (cents):
--   Screen tiers:
--     Original OEM (Tier A): $230 — premium, premium price
--     FOG / OEM-pull (Tier B): $150 — refurb glass on real OEM panel
--     Soft OLED (Tier C): $110 — XO7/QV8-grade aftermarket
--     LCD aftermarket (Tier D): $80 — budget option
--   Battery: $80
--   Charging port: $110
--   Back glass: $130 (laser-removal labor included)
--
-- These are independent of repair_prices (which key by device + service
-- slug); device_model_templates carries its own suggested_price for the
-- one-click ticket apply. Owner can edit any of these from
-- Settings → Device Templates after seed.
--
-- parts_json left as `[]` because inventory items vary per shop — the
-- template still apples labor + price; the tech can attach the actual
-- part SKU at quote time. A follow-up will hydrate parts_json from the
-- shop's own inventory + Mobilesentrix/PLP scrape.
--
-- INSERT OR IGNORE on (name) — the table has no unique constraint on
-- name yet, so to keep this idempotent we emulate it by checking
-- WHERE NOT EXISTS in a single transaction.

INSERT INTO device_model_templates
  (name, device_category, device_model, fault, est_labor_minutes, est_labor_cost, suggested_price, diagnostic_checklist_json, parts_json, warranty_days, sort_order)
SELECT name, device_category, device_model, fault, est_labor_minutes, est_labor_cost, suggested_price, diagnostic_checklist_json, parts_json, warranty_days, sort_order
FROM (
  -- ─── iPhone 16 ──────────────────────────────────────────────────────────
  SELECT 'iPhone 16 — Screen (Original OEM)'  AS name, 'phone' AS device_category, 'iPhone 16' AS device_model, 'screen'      AS fault, 30 AS est_labor_minutes, 0 AS est_labor_cost, 39900 AS suggested_price, '["Test touch","Test True Tone","Verify Face ID"]' AS diagnostic_checklist_json, '[]' AS parts_json, 30 AS warranty_days, 1 AS sort_order
  UNION ALL SELECT 'iPhone 16 — Screen (FOG / Refurb OEM)','phone','iPhone 16','screen',30,0,29900,'["Test touch","Test True Tone"]','[]',30,2
  UNION ALL SELECT 'iPhone 16 — Screen (Soft OLED)',     'phone','iPhone 16','screen',30,0,21900,'["Test touch"]','[]',30,3
  UNION ALL SELECT 'iPhone 16 — Battery',                'phone','iPhone 16','battery',25,0,12900,'["Verify max capacity ≥99%","Cycle count reset"]','[]',60,4
  UNION ALL SELECT 'iPhone 16 — Charging Port',          'phone','iPhone 16','charging_port',45,0,14900,'["Test wired charge","Test data sync"]','[]',30,5
  UNION ALL SELECT 'iPhone 16 — Back Glass',             'phone','iPhone 16','back_glass',60,0,16900,'["MagSafe alignment","Wireless charge"]','[]',30,6

  -- ─── iPhone 15 ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone 15 — Screen (Original OEM)',  'phone','iPhone 15','screen',30,0,32900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone 15 — Screen (FOG / Refurb OEM)','phone','iPhone 15','screen',30,0,24900,'["Test touch","Test True Tone"]','[]',30,2
  UNION ALL SELECT 'iPhone 15 — Screen (Soft OLED)',     'phone','iPhone 15','screen',30,0,17900,'["Test touch"]','[]',30,3
  UNION ALL SELECT 'iPhone 15 — Battery',                'phone','iPhone 15','battery',25,0,10900,'["Verify max capacity ≥99%"]','[]',60,4
  UNION ALL SELECT 'iPhone 15 — Charging Port',          'phone','iPhone 15','charging_port',45,0,12900,'["Test wired charge"]','[]',30,5
  UNION ALL SELECT 'iPhone 15 — Back Glass',             'phone','iPhone 15','back_glass',60,0,14900,'["MagSafe alignment"]','[]',30,6

  -- ─── iPhone 14 ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone 14 — Screen (Original OEM)',  'phone','iPhone 14','screen',30,0,27900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone 14 — Screen (FOG / Refurb OEM)','phone','iPhone 14','screen',30,0,19900,'["Test touch","Test True Tone"]','[]',30,2
  UNION ALL SELECT 'iPhone 14 — Screen (Soft OLED)',     'phone','iPhone 14','screen',30,0,14900,'["Test touch"]','[]',30,3
  UNION ALL SELECT 'iPhone 14 — Battery',                'phone','iPhone 14','battery',25,0,9900,'["Verify max capacity ≥99%"]','[]',60,4
  UNION ALL SELECT 'iPhone 14 — Charging Port',          'phone','iPhone 14','charging_port',45,0,11900,'["Test wired charge"]','[]',30,5
  UNION ALL SELECT 'iPhone 14 — Back Glass',             'phone','iPhone 14','back_glass',60,0,12900,'["MagSafe alignment"]','[]',30,6

  -- ─── iPhone 13 ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone 13 — Screen (Original OEM)',  'phone','iPhone 13','screen',30,0,22900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone 13 — Screen (FOG / Refurb OEM)','phone','iPhone 13','screen',30,0,15900,'["Test touch","Test True Tone"]','[]',30,2
  UNION ALL SELECT 'iPhone 13 — Screen (Soft OLED)',     'phone','iPhone 13','screen',30,0,11900,'["Test touch"]','[]',30,3
  UNION ALL SELECT 'iPhone 13 — Screen (Aftermarket LCD)','phone','iPhone 13','screen',30,0,7900,'["Test touch"]','[]',15,4
  UNION ALL SELECT 'iPhone 13 — Battery',                'phone','iPhone 13','battery',25,0,7900,'["Verify max capacity ≥99%"]','[]',60,5
  UNION ALL SELECT 'iPhone 13 — Charging Port',          'phone','iPhone 13','charging_port',45,0,9900,'["Test wired charge"]','[]',30,6
  UNION ALL SELECT 'iPhone 13 — Back Glass',             'phone','iPhone 13','back_glass',60,0,11900,'["MagSafe alignment"]','[]',30,7
  UNION ALL SELECT 'iPhone 13 — Camera (Rear)',          'phone','iPhone 13','camera',45,0,12900,'["Verify autofocus","Test flash"]','[]',30,8

  -- ─── iPhone 12 ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone 12 — Screen (Original OEM)',  'phone','iPhone 12','screen',30,0,19900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone 12 — Screen (FOG / Refurb OEM)','phone','iPhone 12','screen',30,0,13900,'["Test touch","Test True Tone"]','[]',30,2
  UNION ALL SELECT 'iPhone 12 — Screen (Soft OLED)',     'phone','iPhone 12','screen',30,0,9900,'["Test touch"]','[]',30,3
  UNION ALL SELECT 'iPhone 12 — Screen (Aftermarket LCD)','phone','iPhone 12','screen',30,0,6900,'["Test touch"]','[]',15,4
  UNION ALL SELECT 'iPhone 12 — Battery',                'phone','iPhone 12','battery',25,0,7900,'["Verify max capacity ≥99%"]','[]',60,5
  UNION ALL SELECT 'iPhone 12 — Charging Port',          'phone','iPhone 12','charging_port',45,0,9900,'["Test wired charge"]','[]',30,6
  UNION ALL SELECT 'iPhone 12 — Back Glass',             'phone','iPhone 12','back_glass',60,0,10900,'["MagSafe alignment"]','[]',30,7

  -- ─── iPhone 11 ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone 11 — Screen (Original LCD)',  'phone','iPhone 11','screen',30,0,12900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone 11 — Screen (Aftermarket)',   'phone','iPhone 11','screen',30,0,6900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone 11 — Battery',                'phone','iPhone 11','battery',25,0,6900,'["Verify max capacity ≥99%"]','[]',60,3
  UNION ALL SELECT 'iPhone 11 — Charging Port',          'phone','iPhone 11','charging_port',45,0,8900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'iPhone 11 — Back Glass',             'phone','iPhone 11','back_glass',60,0,9900,'[]','[]',30,5

  -- ─── Galaxy S24 ─────────────────────────────────────────────────────────
  UNION ALL SELECT 'Galaxy S24 — Screen (OEM Service Pack)','phone','Galaxy S24','screen',45,0,32900,'["Test touch","Verify display assembly seal","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Galaxy S24 — Screen (Aftermarket OLED)','phone','Galaxy S24','screen',45,0,21900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy S24 — Battery',               'phone','Galaxy S24','battery',30,0,11900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy S24 — Charging Port',         'phone','Galaxy S24','charging_port',45,0,11900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'Galaxy S24 — Back Glass',            'phone','Galaxy S24','back_glass',60,0,12900,'["Test wireless charge"]','[]',30,5

  -- ─── Galaxy S23 ─────────────────────────────────────────────────────────
  UNION ALL SELECT 'Galaxy S23 — Screen (OEM Service Pack)','phone','Galaxy S23','screen',45,0,27900,'["Test touch","Verify display assembly seal"]','[]',30,1
  UNION ALL SELECT 'Galaxy S23 — Screen (Aftermarket OLED)','phone','Galaxy S23','screen',45,0,17900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy S23 — Battery',               'phone','Galaxy S23','battery',30,0,10900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy S23 — Charging Port',         'phone','Galaxy S23','charging_port',45,0,10900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'Galaxy S23 — Back Glass',            'phone','Galaxy S23','back_glass',60,0,11900,'["Test wireless charge"]','[]',30,5

  -- ─── Galaxy S22 ─────────────────────────────────────────────────────────
  UNION ALL SELECT 'Galaxy S22 — Screen (OEM Service Pack)','phone','Galaxy S22','screen',45,0,23900,'["Test touch","Verify display assembly seal"]','[]',30,1
  UNION ALL SELECT 'Galaxy S22 — Screen (Aftermarket OLED)','phone','Galaxy S22','screen',45,0,15900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy S22 — Battery',               'phone','Galaxy S22','battery',30,0,9900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy S22 — Charging Port',         'phone','Galaxy S22','charging_port',45,0,9900,'["Test wired charge"]','[]',30,4

  -- ─── Galaxy S21 ─────────────────────────────────────────────────────────
  UNION ALL SELECT 'Galaxy S21 — Screen (OEM Service Pack)','phone','Galaxy S21','screen',45,0,19900,'["Test touch","Verify display assembly seal"]','[]',30,1
  UNION ALL SELECT 'Galaxy S21 — Screen (Aftermarket OLED)','phone','Galaxy S21','screen',45,0,12900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy S21 — Battery',               'phone','Galaxy S21','battery',30,0,8900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy S21 — Charging Port',         'phone','Galaxy S21','charging_port',45,0,8900,'["Test wired charge"]','[]',30,4

  -- ─── Pixel 8 / 7 ────────────────────────────────────────────────────────
  UNION ALL SELECT 'Pixel 8 — Screen (OEM)',             'phone','Pixel 8','screen',45,0,23900,'["Test touch","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Pixel 8 — Screen (Aftermarket OLED)','phone','Pixel 8','screen',45,0,14900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 8 — Battery',                  'phone','Pixel 8','battery',30,0,9900,'[]','[]',60,3
  UNION ALL SELECT 'Pixel 8 — Charging Port',            'phone','Pixel 8','charging_port',45,0,9900,'[]','[]',30,4
  UNION ALL SELECT 'Pixel 7 — Screen (OEM)',             'phone','Pixel 7','screen',45,0,19900,'["Test touch","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Pixel 7 — Screen (Aftermarket OLED)','phone','Pixel 7','screen',45,0,11900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 7 — Battery',                  'phone','Pixel 7','battery',30,0,8900,'[]','[]',60,3

  -- ─── OnePlus 12 / 11 ────────────────────────────────────────────────────
  UNION ALL SELECT 'OnePlus 12 — Screen (OEM)',          'phone','OnePlus 12','screen',45,0,21900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'OnePlus 12 — Screen (Aftermarket)',  'phone','OnePlus 12','screen',45,0,12900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'OnePlus 12 — Battery',               'phone','OnePlus 12','battery',30,0,8900,'[]','[]',60,3

  -- ─── iPad Pro 11 (M4) screen / battery ──────────────────────────────────
  UNION ALL SELECT 'iPad Pro 11" (M4) — Screen (OEM)',   'tablet','iPad Pro 11" (M4)','screen',60,0,49900,'["Test touch","Test Apple Pencil hover"]','[]',30,1
  UNION ALL SELECT 'iPad Pro 11" (M4) — Battery',        'tablet','iPad Pro 11" (M4)','battery',75,0,16900,'["Verify max capacity"]','[]',60,2
  UNION ALL SELECT 'iPad Pro 11" (M4) — Charging Port',  'tablet','iPad Pro 11" (M4)','charging_port',60,0,14900,'["Test wired charge"]','[]',30,3

  -- ─── MacBook Pro 14" (M3) screen / battery / keyboard ──────────────────
  UNION ALL SELECT 'MacBook Pro 14" (M3) — Screen (OEM)','laptop','MacBook Pro 14" (M3)','screen',120,0,69900,'["Test touch","Verify True Tone"]','[]',90,1
  UNION ALL SELECT 'MacBook Pro 14" (M3) — Battery',     'laptop','MacBook Pro 14" (M3)','battery',90,0,29900,'["Verify cycle count","Run battery diagnostic"]','[]',180,2
  UNION ALL SELECT 'MacBook Pro 14" (M3) — Keyboard',    'laptop','MacBook Pro 14" (M3)','keyboard',150,0,49900,'["All key test","Backlight test"]','[]',90,3
) AS seed
WHERE NOT EXISTS (
  SELECT 1 FROM device_model_templates t WHERE t.name = seed.name
);
