/**
 * DPI-9: End-to-end test for the Dynamic Repair-Pricing pipeline.
 *
 * In-memory SQLite with fixture device models, repair services, supplier catalog
 * entries, and repair prices. Exercises the full nightly pipeline:
 *   1. Wizard fan-out via bulkApplyTier
 *   2. Custom override (is_custom=1)
 *   3. Nightly rebase — non-custom rows updated, custom rows unchanged
 *   4. Profit recompute — supplier match + profit_estimate + spike detection
 *   5. Auto-margin — labor_price adjusted, capped at configured %
 *   6. Margin alerts — below-threshold rows flagged, recovery auto-resolves
 */

import { describe, it, expect, beforeEach } from 'vitest';
import Database from 'better-sqlite3';
import { bulkApplyTier, getTierThresholds, setTierThresholds, tierForReleaseYear } from '../services/repairPricing/tierResolver.js';
import { runNightlyRebase, getLastRebaseSummary, ackRebaseSummary } from '../services/repairPricing/nightlyRebase.js';
import { recomputeRepairPriceProfits } from '../services/repairPricing/profitRecompute.js';
import { runAutoMargin, setAutoMarginSettings, getAutoMarginSettings } from '../services/repairPricing/autoMargin.js';
import { evaluateMarginAlerts, getActiveMarginAlerts, getMarginAlertSummary, ackMarginAlert } from '../services/repairPricing/marginAlerts.js';
import { seedRepairPricingDefaults } from '../services/repairPricing/seedDefaults.js';

function buildSchema(db: Database.Database): void {
  db.exec(`
    CREATE TABLE IF NOT EXISTS store_config (
      key   TEXT PRIMARY KEY,
      value TEXT
    );

    CREATE TABLE IF NOT EXISTS manufacturers (
      id   INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS device_models (
      id              INTEGER PRIMARY KEY AUTOINCREMENT,
      name            TEXT NOT NULL,
      slug            TEXT NOT NULL,
      category        TEXT NOT NULL DEFAULT 'phone',
      release_year    INTEGER,
      is_popular      INTEGER NOT NULL DEFAULT 0,
      manufacturer_id INTEGER NOT NULL REFERENCES manufacturers(id)
    );

    CREATE TABLE IF NOT EXISTS repair_services (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      slug        TEXT NOT NULL UNIQUE,
      category    TEXT DEFAULT 'phone',
      description TEXT,
      is_active   INTEGER NOT NULL DEFAULT 1,
      sort_order  INTEGER NOT NULL DEFAULT 0,
      updated_at  TEXT
    );

    CREATE TABLE IF NOT EXISTS repair_prices (
      id                    INTEGER PRIMARY KEY AUTOINCREMENT,
      device_model_id       INTEGER NOT NULL REFERENCES device_models(id),
      repair_service_id     INTEGER NOT NULL REFERENCES repair_services(id),
      labor_price           REAL NOT NULL DEFAULT 0,
      default_grade         TEXT DEFAULT 'aftermarket',
      is_active             INTEGER NOT NULL DEFAULT 1,
      is_custom             INTEGER NOT NULL DEFAULT 0,
      tier_label            TEXT,
      last_tier_rebase_at   TEXT,
      profit_estimate       REAL,
      profit_stale_at       TEXT,
      auto_margin_enabled   INTEGER NOT NULL DEFAULT 0,
      auto_margin_paused_at TEXT,
      last_supplier_cost    REAL,
      last_supplier_seen_at TEXT,
      suggested_labor_price REAL,
      updated_at            TEXT,
      created_at            TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS repair_prices_audit (
      id                 INTEGER PRIMARY KEY AUTOINCREMENT,
      repair_price_id    INTEGER REFERENCES repair_prices(id) ON DELETE SET NULL,
      device_model_id    INTEGER,
      repair_service_id  INTEGER,
      old_labor_price    REAL,
      new_labor_price    REAL,
      old_is_custom      INTEGER,
      new_is_custom      INTEGER,
      old_tier_label     TEXT,
      new_tier_label     TEXT,
      supplier_cost      REAL,
      profit_estimate    REAL,
      source             TEXT NOT NULL,
      changed_by_user_id INTEGER,
      imported_filename  TEXT,
      note               TEXT,
      created_at         TEXT NOT NULL DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS repair_price_grades (
      id                     INTEGER PRIMARY KEY AUTOINCREMENT,
      repair_price_id        INTEGER NOT NULL REFERENCES repair_prices(id),
      grade                  TEXT NOT NULL,
      grade_label            TEXT NOT NULL,
      part_inventory_item_id INTEGER,
      part_catalog_item_id   INTEGER,
      part_price             REAL NOT NULL DEFAULT 0,
      labor_price_override   REAL,
      is_default             INTEGER NOT NULL DEFAULT 0,
      sort_order             INTEGER NOT NULL DEFAULT 0
    );

    CREATE TABLE IF NOT EXISTS supplier_catalog (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      name        TEXT NOT NULL,
      price       REAL NOT NULL DEFAULT 0,
      url         TEXT,
      source      TEXT,
      external_id TEXT,
      last_synced TEXT DEFAULT (datetime('now'))
    );

    CREATE TABLE IF NOT EXISTS catalog_device_compatibility (
      id                  INTEGER PRIMARY KEY AUTOINCREMENT,
      supplier_catalog_id INTEGER NOT NULL REFERENCES supplier_catalog(id),
      device_model_id     INTEGER NOT NULL REFERENCES device_models(id)
    );

    CREATE TABLE IF NOT EXISTS margin_alerts (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      repair_price_id   INTEGER NOT NULL REFERENCES repair_prices(id) ON DELETE CASCADE,
      device_model_id   INTEGER NOT NULL REFERENCES device_models(id) ON DELETE CASCADE,
      repair_service_id INTEGER NOT NULL REFERENCES repair_services(id) ON DELETE CASCADE,
      tier_label        TEXT,
      labor_price       REAL NOT NULL,
      supplier_cost     REAL,
      profit_estimate   REAL,
      amber_threshold   REAL NOT NULL,
      first_seen_at     TEXT NOT NULL DEFAULT (datetime('now')),
      last_seen_at      TEXT NOT NULL DEFAULT (datetime('now')),
      resolved_at       TEXT,
      acked_at          TEXT,
      created_at        TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE UNIQUE INDEX IF NOT EXISTS idx_margin_alerts_active_price
      ON margin_alerts(repair_price_id) WHERE resolved_at IS NULL;

    -- Default tier thresholds
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_tier_a_years', '2');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_tier_b_years', '5');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_target_profit_amber', '40');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_preset', 'custom');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_target_type', 'percent');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_target_pct', '100');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_target_profit_amount', '80');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_calculation_basis', 'markup');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_rounding_mode', 'ending_99');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_rules', '[]');
    INSERT INTO store_config (key, value) VALUES ('repair_pricing_auto_margin_cap_pct', '25');
  `);
}

const CURRENT_YEAR = new Date().getFullYear();

function seedFixtures(db: Database.Database): void {
  db.exec(`
    INSERT INTO manufacturers (id, name) VALUES (1, 'Apple');

    -- Tier A: flagship (released within 2 years)
    INSERT INTO device_models (id, name, slug, category, release_year, manufacturer_id)
    VALUES (1, 'iPhone 16 Pro', 'iphone-16-pro', 'phone', ${CURRENT_YEAR}, 1);

    -- Tier B: mainstream (released 3-5 years ago)
    INSERT INTO device_models (id, name, slug, category, release_year, manufacturer_id)
    VALUES (2, 'iPhone 13', 'iphone-13', 'phone', ${CURRENT_YEAR - 4}, 1);

    -- Tier C: legacy (released >5 years ago)
    INSERT INTO device_models (id, name, slug, category, release_year, manufacturer_id)
    VALUES (3, 'iPhone X', 'iphone-x', 'phone', ${CURRENT_YEAR - 8}, 1);

    INSERT INTO repair_services (id, name, slug, category, sort_order)
    VALUES (1, 'Screen Replacement', 'screen-replacement', 'phone', 1);

    -- Supplier catalog: one entry for each device's screen
    INSERT INTO supplier_catalog (id, name, price, source, last_synced)
    VALUES (1, 'iPhone 16 Pro Screen OLED', 85.00, 'mobilesentrix', datetime('now'));
    INSERT INTO supplier_catalog (id, name, price, source, last_synced)
    VALUES (2, 'iPhone 13 Screen LCD', 35.00, 'mobilesentrix', datetime('now'));
    INSERT INTO supplier_catalog (id, name, price, source, last_synced)
    VALUES (3, 'iPhone X Screen OLED', 20.00, 'phonelcdparts', datetime('now'));

    INSERT INTO catalog_device_compatibility (supplier_catalog_id, device_model_id)
    VALUES (1, 1), (2, 2), (3, 3);
  `);
}

let db: Database.Database;

beforeEach(() => {
  db = new Database(':memory:');
  buildSchema(db);
  seedFixtures(db);
});

describe('DPI Pipeline', () => {
  it('bulkApplyTier fans out wizard pricing to correct tier devices', () => {
    const resultA = bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });
    const resultB = bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_b', laborPrice: 120 });
    const resultC = bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 80 });

    expect(resultA.matched_devices).toBe(1);
    expect(resultA.inserted).toBe(1);
    expect(resultB.matched_devices).toBe(1);
    expect(resultB.inserted).toBe(1);
    expect(resultC.matched_devices).toBe(1);
    expect(resultC.inserted).toBe(1);

    const prices = db.prepare('SELECT * FROM repair_prices ORDER BY device_model_id').all() as any[];
    expect(prices).toHaveLength(3);
    expect(prices[0].labor_price).toBe(200);
    expect(prices[0].tier_label).toBe('tier_a');
    expect(prices[1].labor_price).toBe(120);
    expect(prices[1].tier_label).toBe('tier_b');
    expect(prices[2].labor_price).toBe(80);
    expect(prices[2].tier_label).toBe('tier_c');
  });

  it('custom override persists through nightly rebase', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_b', laborPrice: 120 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 80 });

    // Override device 1 (tier_a) with custom price
    db.prepare('UPDATE repair_prices SET labor_price = 250, is_custom = 1 WHERE device_model_id = 1').run();

    // Age device 1 so it crosses tier_a → tier_b, triggering a rebase attempt
    db.prepare(`UPDATE device_models SET release_year = ${CURRENT_YEAR - 4} WHERE id = 1`).run();

    const rebase = runNightlyRebase(db);
    expect(rebase.skipped_custom).toBeGreaterThanOrEqual(1);

    const customRow = db.prepare('SELECT labor_price, is_custom FROM repair_prices WHERE device_model_id = 1').get() as any;
    expect(customRow.labor_price).toBe(250);
    expect(customRow.is_custom).toBe(1);
  });

  it('nightly rebase detects tier boundary crossings', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_b', laborPrice: 120 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 80 });

    // Simulate device 1 aging: change release_year so it crosses from A → B
    db.prepare(`UPDATE device_models SET release_year = ${CURRENT_YEAR - 4} WHERE id = 1`).run();

    const rebase = runNightlyRebase(db);
    expect(rebase.rebased).toBe(1);
    expect(rebase.crossings).toHaveLength(1);
    expect(rebase.crossings[0].old_tier).toBe('tier_a');
    expect(rebase.crossings[0].new_tier).toBe('tier_b');
    expect(rebase.crossings[0].new_labor).toBe(120);

    const summary = getLastRebaseSummary(db);
    expect(summary).not.toBeNull();
    expect(summary!.device_count).toBe(1);
    expect(summary!.acked_at).toBeNull();

    ackRebaseSummary(db);
    const acked = getLastRebaseSummary(db);
    expect(acked!.acked_at).not.toBeNull();
  });

  it('profit recompute matches supplier catalog and computes profit', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_b', laborPrice: 120 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 80 });

    const result = recomputeRepairPriceProfits(db);
    expect(result.processed).toBe(3);
    expect(result.updated).toBe(3);
    expect(result.spikes).toHaveLength(0);

    const prices = db.prepare('SELECT * FROM repair_prices ORDER BY device_model_id').all() as any[];
    // Device 1: labor=$200, supplier=$85, profit=$115
    expect(prices[0].profit_estimate).toBe(115);
    expect(prices[0].last_supplier_cost).toBe(85);
    // Device 2: labor=$120, supplier=$35, profit=$85
    expect(prices[1].profit_estimate).toBe(85);
    // Device 3: labor=$80, supplier=$20, profit=$60
    expect(prices[2].profit_estimate).toBe(60);
  });

  it('detects supplier cost spike >50% and pauses auto-margin', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });

    // First recompute sets baseline supplier cost
    recomputeRepairPriceProfits(db);
    const baseline = db.prepare('SELECT last_supplier_cost FROM repair_prices WHERE device_model_id = 1').get() as any;
    expect(baseline.last_supplier_cost).toBe(85);

    // Enable auto-margin on this price
    db.prepare('UPDATE repair_prices SET auto_margin_enabled = 1 WHERE device_model_id = 1').run();

    // Spike: supplier cost jumps from $85 → $170 (100% increase)
    db.prepare('UPDATE supplier_catalog SET price = 170.00 WHERE id = 1').run();

    const result = recomputeRepairPriceProfits(db);
    expect(result.spikes).toHaveLength(1);
    expect(result.spikes[0].old_cost).toBe(85);
    expect(result.spikes[0].new_cost).toBe(170);
    expect(result.spikes[0].pct_change).toBe(100);

    const paused = db.prepare('SELECT auto_margin_paused_at FROM repair_prices WHERE device_model_id = 1').get() as any;
    expect(paused.auto_margin_paused_at).not.toBeNull();

    const audits = db.prepare("SELECT * FROM repair_prices_audit WHERE source = 'supplier-spike'").all() as any[];
    expect(audits).toHaveLength(1);
  });

  it('auto-margin adjusts labor_price capped at configured percentage', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });

    // Set supplier cost and enable auto-margin
    db.prepare(`
      UPDATE repair_prices
      SET auto_margin_enabled = 1, last_supplier_cost = 85, profit_estimate = 115
      WHERE device_model_id = 1
    `).run();

    // Target 100% markup on supplier cost → desired = $85 * 2 = $170
    // But current is $200, cap at 25% → max decrease = $50 → capped at $150
    setAutoMarginSettings(db, {
      preset: 'custom',
      target_type: 'percent',
      target_margin_pct: 100,
      calculation_basis: 'markup',
      rounding_mode: 'none',
      cap_pct: 25,
    });

    const result = runAutoMargin(db);
    expect(result.evaluated).toBe(1);
    expect(result.adjusted).toBe(1);

    const price = db.prepare('SELECT labor_price FROM repair_prices WHERE device_model_id = 1').get() as any;
    // $200 → target $170 → delta -$30 within 25% cap ($50), full adjustment applies
    expect(price.labor_price).toBe(170);
  });

  it('margin alerts fire when profit below amber threshold', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 50 });

    // Set profit_estimate to $30, which is below the $40 amber threshold
    db.prepare(`
      UPDATE repair_prices
      SET profit_estimate = 30, last_supplier_cost = 20
      WHERE device_model_id = 3
    `).run();

    const result = evaluateMarginAlerts(db);
    expect(result.new_alerts).toBe(1);

    const alerts = getActiveMarginAlerts(db);
    expect(alerts).toHaveLength(1);
    expect(alerts[0].profit_estimate).toBe(30);
    expect(alerts[0].amber_threshold).toBe(40);

    const summary = getMarginAlertSummary(db);
    expect(summary.total_active).toBe(1);
    expect(summary.unacked).toBe(1);

    // Ack the alert
    ackMarginAlert(db, alerts[0].id);
    const postAck = getMarginAlertSummary(db);
    expect(postAck.unacked).toBe(0);
  });

  it('margin alerts auto-resolve when profit recovers', () => {
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 50 });
    db.prepare('UPDATE repair_prices SET profit_estimate = 30, last_supplier_cost = 20 WHERE device_model_id = 3').run();

    evaluateMarginAlerts(db);
    expect(getMarginAlertSummary(db).total_active).toBe(1);

    // Profit recovers above amber threshold
    db.prepare('UPDATE repair_prices SET profit_estimate = 50 WHERE device_model_id = 3').run();
    const result = evaluateMarginAlerts(db);
    expect(result.resolved).toBe(1);
    expect(getMarginAlertSummary(db).total_active).toBe(0);
  });

  it('full nightly pipeline: scrape → profit → rebase → auto-margin → alerts', () => {
    // Step 1: Wizard seeds prices
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 200 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_b', laborPrice: 120 });
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_c', laborPrice: 80 });

    // Step 2: Profit recompute
    const recompute = recomputeRepairPriceProfits(db);
    expect(recompute.updated).toBe(3);

    // Step 3: Enable auto-margin on all rows
    db.prepare('UPDATE repair_prices SET auto_margin_enabled = 1').run();
    setAutoMarginSettings(db, {
      preset: 'custom',
      target_type: 'percent',
      target_margin_pct: 100,
      calculation_basis: 'markup',
      rounding_mode: 'none',
      cap_pct: 25,
    });

    // Step 4: Auto-margin run
    const autoMargin = runAutoMargin(db);
    expect(autoMargin.evaluated).toBe(3);

    // Step 5: Nightly rebase (no crossings expected — tiers match)
    const rebase = runNightlyRebase(db);
    expect(rebase.rebased).toBe(0);

    // Step 6: Margin alerts
    const alerts = evaluateMarginAlerts(db);
    expect(alerts.evaluated).toBeGreaterThan(0);

    // Verify audit trail exists
    const auditCount = db.prepare('SELECT COUNT(*) AS c FROM repair_prices_audit').get() as any;
    expect(auditCount.c).toBeGreaterThan(0);
  });
});
