-- Migration 194: Extend device_model_templates coverage (REPAIR-TEMPLATES-SEED-1 follow-up).
--
-- Migration 173 seeded the top 17 devices (iPhone 11–16, Galaxy S21–S24,
-- Pixel 7/8, OnePlus 11/12, iPad Pro 11" M4, MacBook Pro 14" M3). Bench
-- volume reports show several high-traffic devices still rendered
-- "No templates yet": iPhone SE, iPhone X-series, mid-Pixel (6/6a/7a/8a),
-- Galaxy A-series, iPad/iPad Air/iPad Mini, and Galaxy foldables.
--
-- Same constraints as 173:
--   - parts_json stays `[]`; per-shop inventory hydration is the SEED-2
--     follow-up gated on the scrape worker + tier_label storage.
--   - suggested_price defaults reflect U.S. market median list prices the
--     owner can edit from Settings → Device Templates.
--   - INSERT … WHERE NOT EXISTS on name keeps the migration idempotent
--     and lets it co-exist with shop overrides created since 173.

INSERT INTO device_model_templates
  (name, device_category, device_model, fault, est_labor_minutes, est_labor_cost, suggested_price, diagnostic_checklist_json, parts_json, warranty_days, sort_order)
SELECT name, device_category, device_model, fault, est_labor_minutes, est_labor_cost, suggested_price, diagnostic_checklist_json, parts_json, warranty_days, sort_order
FROM (
  -- ─── iPhone SE (3rd gen, 2022) ──────────────────────────────────────────
  SELECT 'iPhone SE (3rd gen) — Screen (Original LCD)' AS name, 'phone' AS device_category, 'iPhone SE (3rd gen)' AS device_model, 'screen' AS fault, 30 AS est_labor_minutes, 0 AS est_labor_cost, 11900 AS suggested_price, '["Test touch","Verify Touch ID"]' AS diagnostic_checklist_json, '[]' AS parts_json, 30 AS warranty_days, 1 AS sort_order
  UNION ALL SELECT 'iPhone SE (3rd gen) — Screen (Aftermarket)','phone','iPhone SE (3rd gen)','screen',30,0,6900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone SE (3rd gen) — Battery',             'phone','iPhone SE (3rd gen)','battery',25,0,5900,'["Verify max capacity ≥99%"]','[]',60,3
  UNION ALL SELECT 'iPhone SE (3rd gen) — Charging Port',       'phone','iPhone SE (3rd gen)','charging_port',45,0,7900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'iPhone SE (3rd gen) — Back Glass',          'phone','iPhone SE (3rd gen)','back_glass',45,0,7900,'[]','[]',30,5

  -- ─── iPhone SE (2nd gen, 2020) ──────────────────────────────────────────
  UNION ALL SELECT 'iPhone SE (2nd gen) — Screen (Original LCD)','phone','iPhone SE (2nd gen)','screen',30,0,9900,'["Test touch","Verify Touch ID"]','[]',30,1
  UNION ALL SELECT 'iPhone SE (2nd gen) — Screen (Aftermarket)','phone','iPhone SE (2nd gen)','screen',30,0,5900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone SE (2nd gen) — Battery',             'phone','iPhone SE (2nd gen)','battery',25,0,5900,'["Verify max capacity ≥99%"]','[]',60,3
  UNION ALL SELECT 'iPhone SE (2nd gen) — Charging Port',       'phone','iPhone SE (2nd gen)','charging_port',45,0,7900,'["Test wired charge"]','[]',30,4

  -- ─── iPhone XR ──────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone XR — Screen (Original LCD)',   'phone','iPhone XR','screen',30,0,10900,'["Test touch","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone XR — Screen (Aftermarket)',    'phone','iPhone XR','screen',30,0,5900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone XR — Battery',                 'phone','iPhone XR','battery',25,0,6900,'["Verify max capacity ≥99%"]','[]',60,3
  UNION ALL SELECT 'iPhone XR — Charging Port',           'phone','iPhone XR','charging_port',45,0,8900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'iPhone XR — Back Glass',              'phone','iPhone XR','back_glass',60,0,9900,'[]','[]',30,5

  -- ─── iPhone XS / XS Max ─────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone XS — Screen (Original OEM)',   'phone','iPhone XS','screen',30,0,13900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone XS — Screen (Soft OLED)',      'phone','iPhone XS','screen',30,0,7900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone XS — Battery',                 'phone','iPhone XS','battery',25,0,6900,'["Verify max capacity ≥99%"]','[]',60,3
  UNION ALL SELECT 'iPhone XS — Charging Port',           'phone','iPhone XS','charging_port',45,0,8900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'iPhone XS Max — Screen (Original OEM)','phone','iPhone XS Max','screen',30,0,15900,'["Test touch","Test True Tone","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone XS Max — Screen (Soft OLED)',  'phone','iPhone XS Max','screen',30,0,9900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone XS Max — Battery',             'phone','iPhone XS Max','battery',25,0,7900,'["Verify max capacity ≥99%"]','[]',60,3

  -- ─── iPhone X ───────────────────────────────────────────────────────────
  UNION ALL SELECT 'iPhone X — Screen (Original OEM)',    'phone','iPhone X','screen',30,0,12900,'["Test touch","Verify Face ID"]','[]',30,1
  UNION ALL SELECT 'iPhone X — Screen (Soft OLED)',       'phone','iPhone X','screen',30,0,7900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPhone X — Battery',                  'phone','iPhone X','battery',25,0,6900,'["Verify max capacity ≥99%"]','[]',60,3

  -- ─── Pixel 8a / 7a / 6a / 6 ─────────────────────────────────────────────
  UNION ALL SELECT 'Pixel 8a — Screen (OEM)',             'phone','Pixel 8a','screen',45,0,17900,'["Test touch","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Pixel 8a — Screen (Aftermarket OLED)','phone','Pixel 8a','screen',45,0,10900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 8a — Battery',                  'phone','Pixel 8a','battery',30,0,8900,'[]','[]',60,3
  UNION ALL SELECT 'Pixel 7a — Screen (OEM)',             'phone','Pixel 7a','screen',45,0,15900,'["Test touch","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Pixel 7a — Screen (Aftermarket OLED)','phone','Pixel 7a','screen',45,0,9900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 7a — Battery',                  'phone','Pixel 7a','battery',30,0,7900,'[]','[]',60,3
  UNION ALL SELECT 'Pixel 6a — Screen (OEM)',             'phone','Pixel 6a','screen',45,0,12900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Pixel 6a — Screen (Aftermarket OLED)','phone','Pixel 6a','screen',45,0,7900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 6a — Battery',                  'phone','Pixel 6a','battery',30,0,6900,'[]','[]',60,3
  UNION ALL SELECT 'Pixel 6 — Screen (OEM)',              'phone','Pixel 6','screen',45,0,16900,'["Test touch","Test fingerprint reader"]','[]',30,1
  UNION ALL SELECT 'Pixel 6 — Screen (Aftermarket OLED)', 'phone','Pixel 6','screen',45,0,9900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Pixel 6 — Battery',                   'phone','Pixel 6','battery',30,0,7900,'[]','[]',60,3
  UNION ALL SELECT 'Pixel 6 — Charging Port',             'phone','Pixel 6','charging_port',45,0,8900,'[]','[]',30,4

  -- ─── Galaxy A-series (budget volume) ────────────────────────────────────
  UNION ALL SELECT 'Galaxy A15 — Screen (OEM)',           'phone','Galaxy A15','screen',45,0,11900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Galaxy A15 — Screen (Aftermarket)',   'phone','Galaxy A15','screen',45,0,6900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy A15 — Battery',                'phone','Galaxy A15','battery',30,0,5900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy A14 — Screen (OEM)',           'phone','Galaxy A14','screen',45,0,9900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Galaxy A14 — Screen (Aftermarket)',   'phone','Galaxy A14','screen',45,0,5900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy A14 — Battery',                'phone','Galaxy A14','battery',30,0,5900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy A55 — Screen (OEM)',           'phone','Galaxy A55','screen',45,0,16900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Galaxy A55 — Screen (Aftermarket OLED)','phone','Galaxy A55','screen',45,0,10900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy A55 — Battery',                'phone','Galaxy A55','battery',30,0,7900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy A54 — Screen (OEM)',           'phone','Galaxy A54','screen',45,0,14900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Galaxy A54 — Screen (Aftermarket OLED)','phone','Galaxy A54','screen',45,0,8900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy A54 — Battery',                'phone','Galaxy A54','battery',30,0,6900,'["Verify charge cycle reset"]','[]',60,3

  -- ─── Galaxy Note 20 / S20 (legacy still in service) ─────────────────────
  UNION ALL SELECT 'Galaxy Note 20 — Screen (OEM)',       'phone','Galaxy Note 20','screen',45,0,21900,'["Test touch","Verify S Pen"]','[]',30,1
  UNION ALL SELECT 'Galaxy Note 20 — Screen (Aftermarket OLED)','phone','Galaxy Note 20','screen',45,0,13900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy Note 20 — Battery',            'phone','Galaxy Note 20','battery',30,0,8900,'["Verify charge cycle reset"]','[]',60,3
  UNION ALL SELECT 'Galaxy S20 — Screen (OEM)',           'phone','Galaxy S20','screen',45,0,17900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'Galaxy S20 — Screen (Aftermarket OLED)','phone','Galaxy S20','screen',45,0,10900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'Galaxy S20 — Battery',                'phone','Galaxy S20','battery',30,0,7900,'["Verify charge cycle reset"]','[]',60,3

  -- ─── Galaxy Z Flip / Fold (premium folds, high-margin) ──────────────────
  UNION ALL SELECT 'Galaxy Z Flip 5 — Screen (OEM)',      'phone','Galaxy Z Flip 5','screen',90,0,44900,'["Test hinge","Test inner display fold","Verify fingerprint"]','[]',30,1
  UNION ALL SELECT 'Galaxy Z Flip 5 — Battery',           'phone','Galaxy Z Flip 5','battery',60,0,14900,'["Verify charge cycle reset"]','[]',60,2
  UNION ALL SELECT 'Galaxy Z Fold 5 — Screen (OEM)',      'phone','Galaxy Z Fold 5','screen',120,0,69900,'["Test hinge","Test inner display fold","Test outer display"]','[]',30,1
  UNION ALL SELECT 'Galaxy Z Fold 5 — Battery',           'phone','Galaxy Z Fold 5','battery',75,0,17900,'["Verify charge cycle reset"]','[]',60,2

  -- ─── OnePlus 10 / 9 ─────────────────────────────────────────────────────
  UNION ALL SELECT 'OnePlus 10 Pro — Screen (OEM)',       'phone','OnePlus 10 Pro','screen',45,0,18900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'OnePlus 10 Pro — Screen (Aftermarket)','phone','OnePlus 10 Pro','screen',45,0,10900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'OnePlus 10 Pro — Battery',            'phone','OnePlus 10 Pro','battery',30,0,7900,'[]','[]',60,3
  UNION ALL SELECT 'OnePlus 9 — Screen (OEM)',            'phone','OnePlus 9','screen',45,0,15900,'["Test touch"]','[]',30,1
  UNION ALL SELECT 'OnePlus 9 — Battery',                 'phone','OnePlus 9','battery',30,0,6900,'[]','[]',60,2

  -- ─── iPad (10th/9th gen), iPad Air, iPad Mini ───────────────────────────
  UNION ALL SELECT 'iPad (10th gen) — Screen (OEM)',      'tablet','iPad (10th gen)','screen',60,0,24900,'["Test touch","Test Apple Pencil hover"]','[]',30,1
  UNION ALL SELECT 'iPad (10th gen) — Screen (Aftermarket)','tablet','iPad (10th gen)','screen',60,0,14900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPad (10th gen) — Battery',           'tablet','iPad (10th gen)','battery',75,0,10900,'["Verify max capacity"]','[]',60,3
  UNION ALL SELECT 'iPad (10th gen) — Charging Port',     'tablet','iPad (10th gen)','charging_port',60,0,11900,'["Test wired charge"]','[]',30,4
  UNION ALL SELECT 'iPad (9th gen) — Screen (OEM)',       'tablet','iPad (9th gen)','screen',60,0,18900,'["Test touch","Test Apple Pencil"]','[]',30,1
  UNION ALL SELECT 'iPad (9th gen) — Screen (Aftermarket)','tablet','iPad (9th gen)','screen',60,0,10900,'["Test touch"]','[]',15,2
  UNION ALL SELECT 'iPad (9th gen) — Battery',            'tablet','iPad (9th gen)','battery',75,0,8900,'["Verify max capacity"]','[]',60,3
  UNION ALL SELECT 'iPad Air (5th gen) — Screen (OEM)',   'tablet','iPad Air (5th gen)','screen',60,0,32900,'["Test touch","Test Apple Pencil"]','[]',30,1
  UNION ALL SELECT 'iPad Air (5th gen) — Battery',        'tablet','iPad Air (5th gen)','battery',75,0,12900,'["Verify max capacity"]','[]',60,2
  UNION ALL SELECT 'iPad Mini (6th gen) — Screen (OEM)',  'tablet','iPad Mini (6th gen)','screen',60,0,28900,'["Test touch","Test Apple Pencil"]','[]',30,1
  UNION ALL SELECT 'iPad Mini (6th gen) — Battery',       'tablet','iPad Mini (6th gen)','battery',75,0,11900,'["Verify max capacity"]','[]',60,2

  -- ─── iPad Pro 12.9" (M2/M4) ─────────────────────────────────────────────
  UNION ALL SELECT 'iPad Pro 12.9" (M2) — Screen (OEM)',  'tablet','iPad Pro 12.9" (M2)','screen',75,0,59900,'["Test touch","Test Apple Pencil hover"]','[]',30,1
  UNION ALL SELECT 'iPad Pro 12.9" (M2) — Battery',       'tablet','iPad Pro 12.9" (M2)','battery',90,0,19900,'["Verify max capacity"]','[]',60,2

  -- ─── Apple Watch Series 7 / 8 / 9 ───────────────────────────────────────
  UNION ALL SELECT 'Apple Watch Series 9 — Screen (OEM)', 'watch','Apple Watch Series 9','screen',60,0,21900,'["Test touch","Verify Digital Crown"]','[]',30,1
  UNION ALL SELECT 'Apple Watch Series 9 — Battery',      'watch','Apple Watch Series 9','battery',75,0,11900,'["Verify charge cycle reset"]','[]',60,2
  UNION ALL SELECT 'Apple Watch Series 8 — Screen (OEM)', 'watch','Apple Watch Series 8','screen',60,0,18900,'["Test touch","Verify Digital Crown"]','[]',30,1
  UNION ALL SELECT 'Apple Watch Series 8 — Battery',      'watch','Apple Watch Series 8','battery',75,0,10900,'["Verify charge cycle reset"]','[]',60,2
  UNION ALL SELECT 'Apple Watch Series 7 — Screen (OEM)', 'watch','Apple Watch Series 7','screen',60,0,15900,'["Test touch","Verify Digital Crown"]','[]',30,1
  UNION ALL SELECT 'Apple Watch Series 7 — Battery',      'watch','Apple Watch Series 7','battery',75,0,9900,'["Verify charge cycle reset"]','[]',60,2

  -- ─── MacBook Air M2 / M1 ────────────────────────────────────────────────
  UNION ALL SELECT 'MacBook Air (M2) — Screen (OEM)',     'laptop','MacBook Air (M2)','screen',120,0,49900,'["Verify True Tone"]','[]',90,1
  UNION ALL SELECT 'MacBook Air (M2) — Battery',          'laptop','MacBook Air (M2)','battery',90,0,21900,'["Verify cycle count","Run battery diagnostic"]','[]',180,2
  UNION ALL SELECT 'MacBook Air (M2) — Keyboard',         'laptop','MacBook Air (M2)','keyboard',150,0,34900,'["All key test","Backlight test"]','[]',90,3
  UNION ALL SELECT 'MacBook Air (M1) — Screen (OEM)',     'laptop','MacBook Air (M1)','screen',120,0,42900,'["Verify True Tone"]','[]',90,1
  UNION ALL SELECT 'MacBook Air (M1) — Battery',          'laptop','MacBook Air (M1)','battery',90,0,18900,'["Verify cycle count","Run battery diagnostic"]','[]',180,2
  UNION ALL SELECT 'MacBook Air (M1) — Keyboard',         'laptop','MacBook Air (M1)','keyboard',150,0,29900,'["All key test","Backlight test"]','[]',90,3
) AS seed
WHERE NOT EXISTS (
  SELECT 1 FROM device_model_templates t WHERE t.name = seed.name
);
