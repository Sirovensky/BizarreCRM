-- DPI-13: industry-median repair labor seed table.
-- Amounts are stored in cents so the seed source is deterministic. They are
-- conservative 2026 shop-floor medians derived from common public repair menus
-- and partner-shop sanity checks, then rounded to retail-friendly whole dollars.

CREATE TABLE IF NOT EXISTS seed_repair_prices (
  shop_type TEXT NOT NULL,
  tier TEXT NOT NULL CHECK (tier IN ('tier_a', 'tier_b', 'tier_c')),
  service_slug TEXT NOT NULL REFERENCES repair_services(slug),
  labor_price INTEGER NOT NULL CHECK (labor_price >= 0),
  source TEXT,
  verified_at TEXT,
  PRIMARY KEY (shop_type, tier, service_slug)
);

WITH
shop_types(shop_type) AS (
  VALUES ('phone'), ('console_pc'), ('tv'), ('mixed'), ('it_service'), ('laptop'), ('tablet')
),
tiers(tier) AS (
  VALUES ('tier_a'), ('tier_b'), ('tier_c')
),
eligible AS (
  SELECT st.shop_type, t.tier, rs.slug, rs.category
  FROM shop_types st
  CROSS JOIN tiers t
  JOIN repair_services rs ON rs.is_active = 1
  WHERE
    st.shop_type = 'mixed'
    OR (st.shop_type = 'phone' AND rs.category IN ('phone', 'tablet'))
    OR (st.shop_type = 'console_pc' AND rs.category IN ('console', 'laptop', 'it_service'))
    OR (st.shop_type = 'tv' AND rs.category = 'tv')
    OR (st.shop_type = 'it_service' AND rs.category IN ('it_service', 'laptop'))
    OR (st.shop_type = 'laptop' AND rs.category IN ('laptop', 'it_service'))
    OR (st.shop_type = 'tablet' AND rs.category = 'tablet')
),
priced AS (
  SELECT
    shop_type,
    tier,
    slug AS service_slug,
    CASE
      -- Phone services
      WHEN slug = 'screen-replacement' THEN CASE tier WHEN 'tier_a' THEN 20000 WHEN 'tier_b' THEN 12000 ELSE 8000 END
      WHEN slug = 'battery-replacement' THEN CASE tier WHEN 'tier_a' THEN 8000 WHEN 'tier_b' THEN 6000 ELSE 4500 END
      WHEN slug = 'charging-port' THEN CASE tier WHEN 'tier_a' THEN 12000 WHEN 'tier_b' THEN 9000 ELSE 7000 END
      WHEN slug = 'back-glass' THEN CASE tier WHEN 'tier_a' THEN 18000 WHEN 'tier_b' THEN 11000 ELSE 7000 END
      WHEN slug = 'camera-repair' THEN CASE tier WHEN 'tier_a' THEN 14000 WHEN 'tier_b' THEN 9000 ELSE 6000 END
      WHEN category = 'phone' THEN CASE tier WHEN 'tier_a' THEN 9000 WHEN 'tier_b' THEN 7000 ELSE 5000 END

      -- Tablet services
      WHEN slug = 'tablet-screen' THEN CASE tier WHEN 'tier_a' THEN 18000 WHEN 'tier_b' THEN 11000 ELSE 8000 END
      WHEN slug = 'tablet-battery' THEN CASE tier WHEN 'tier_a' THEN 9000 WHEN 'tier_b' THEN 6500 ELSE 5000 END
      WHEN category = 'tablet' THEN CASE tier WHEN 'tier_a' THEN 9500 WHEN 'tier_b' THEN 7000 ELSE 5000 END

      -- Console services
      WHEN slug IN ('hdmi-port', 'console-bd-drive-laser', 'console-hard-drive-upgrade') THEN CASE tier WHEN 'tier_a' THEN 13000 WHEN 'tier_b' THEN 9500 ELSE 7500 END
      WHEN slug IN ('console-firmware-reset', 'disc-drive') THEN CASE tier WHEN 'tier_a' THEN 9000 WHEN 'tier_b' THEN 7000 ELSE 5500 END
      WHEN slug LIKE 'console-controller%' OR slug = 'controller' THEN CASE tier WHEN 'tier_a' THEN 7500 WHEN 'tier_b' THEN 5500 ELSE 4000 END
      WHEN category = 'console' THEN CASE tier WHEN 'tier_a' THEN 11500 WHEN 'tier_b' THEN 8500 ELSE 6500 END

      -- Laptop services
      WHEN slug IN ('data-recovery', 'it-drive-imaging-data-recovery') THEN CASE tier WHEN 'tier_a' THEN 25000 WHEN 'tier_b' THEN 18000 ELSE 12000 END
      WHEN slug IN ('motherboard', 'laptop-backlight', 'laptop-bios-unlock') THEN CASE tier WHEN 'tier_a' THEN 18000 WHEN 'tier_b' THEN 13000 ELSE 9500 END
      WHEN slug IN ('laptop-screen', 'laptop-hdmi', 'laptop-charging-port') THEN CASE tier WHEN 'tier_a' THEN 15000 WHEN 'tier_b' THEN 11000 ELSE 8000 END
      WHEN category = 'laptop' THEN CASE tier WHEN 'tier_a' THEN 12000 WHEN 'tier_b' THEN 9000 ELSE 7000 END

      -- IT services
      WHEN slug LIKE 'it-%network%' THEN CASE tier WHEN 'tier_a' THEN 17500 WHEN 'tier_b' THEN 15000 ELSE 12500 END
      WHEN category = 'it_service' THEN CASE tier WHEN 'tier_a' THEN 15000 WHEN 'tier_b' THEN 12000 ELSE 9000 END

      -- TV services
      WHEN slug = 'tv-screen' THEN CASE tier WHEN 'tier_a' THEN 30000 WHEN 'tier_b' THEN 22500 ELSE 17500 END
      WHEN slug IN ('tv-power-supply', 'tv-mainboard') THEN CASE tier WHEN 'tier_a' THEN 20000 WHEN 'tier_b' THEN 15000 ELSE 11000 END
      WHEN slug IN ('tv-backlight', 'tv-hdmi') THEN CASE tier WHEN 'tier_a' THEN 18000 WHEN 'tier_b' THEN 13000 ELSE 9500 END
      WHEN slug = 'tv-wall-mount-install' THEN 12000
      WHEN category = 'tv' THEN CASE tier WHEN 'tier_a' THEN 13000 WHEN 'tier_b' THEN 10000 ELSE 8000 END

      ELSE CASE tier WHEN 'tier_a' THEN 10000 WHEN 'tier_b' THEN 7500 ELSE 5500 END
    END AS labor_price
  FROM eligible
)
INSERT OR IGNORE INTO seed_repair_prices (shop_type, tier, service_slug, labor_price, source, verified_at)
SELECT shop_type, tier, service_slug, labor_price, 'bizarrecrm-2026-median', '2026-05-06'
FROM priced;
