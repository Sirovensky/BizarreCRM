import { describe, expect, it } from 'vitest';
import Database from 'better-sqlite3';
import {
  bulkApplyTier,
  revertPriceToTier,
  tierForReleaseYear,
} from '../repairPricing/tierResolver.js';
import { recomputeRepairPriceProfits } from '../repairPricing/profitRecompute.js';
import {
  cappedAutoMarginLabor,
  roundAutoMarginLabor,
  runAutoMargin,
  setAutoMarginSettings,
  targetLaborForMargin,
} from '../repairPricing/autoMargin.js';
import { seedRepairPricingDefaults } from '../repairPricing/seedDefaults.js';

function buildDb(): Database.Database {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE store_config (key TEXT PRIMARY KEY, value TEXT);
    CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT);
    CREATE TABLE manufacturers (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE device_models (
      id INTEGER PRIMARY KEY,
      manufacturer_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'phone',
      release_year INTEGER
    );
    CREATE TABLE repair_services (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      slug TEXT NOT NULL,
      category TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      sort_order INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE repair_prices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      device_model_id INTEGER NOT NULL,
      repair_service_id INTEGER NOT NULL,
      labor_price REAL NOT NULL DEFAULT 0,
      default_grade TEXT DEFAULT 'aftermarket',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      is_custom INTEGER NOT NULL DEFAULT 0,
      tier_label TEXT,
      last_tier_rebase_at TEXT,
      profit_estimate REAL,
      profit_stale_at TEXT,
      auto_margin_enabled INTEGER NOT NULL DEFAULT 0,
      auto_margin_paused_at TEXT,
      last_supplier_cost REAL,
      last_supplier_seen_at TEXT,
      suggested_labor_price REAL,
      UNIQUE(device_model_id, repair_service_id)
    );
    CREATE TABLE repair_price_grades (
      id INTEGER PRIMARY KEY,
      repair_price_id INTEGER NOT NULL,
      part_catalog_item_id INTEGER,
      grade TEXT,
      grade_label TEXT,
      part_price REAL DEFAULT 0
    );
    CREATE TABLE repair_prices_audit (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      repair_price_id INTEGER,
      device_model_id INTEGER,
      repair_service_id INTEGER,
      old_labor_price REAL,
      new_labor_price REAL,
      old_is_custom INTEGER,
      new_is_custom INTEGER,
      old_tier_label TEXT,
      new_tier_label TEXT,
      supplier_cost REAL,
      profit_estimate REAL,
      source TEXT NOT NULL,
      changed_by_user_id INTEGER,
      imported_filename TEXT,
      note TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now'))
    );
    CREATE TABLE supplier_catalog (
      id INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      price REAL NOT NULL,
      last_synced TEXT DEFAULT (datetime('now'))
    );
    CREATE TABLE catalog_device_compatibility (
      id INTEGER PRIMARY KEY,
      supplier_catalog_id INTEGER NOT NULL,
      device_model_id INTEGER NOT NULL
    );
  `);

  db.prepare('INSERT INTO store_config (key, value) VALUES (?, ?)').run('repair_pricing_tier_a_years', '2');
  db.prepare('INSERT INTO store_config (key, value) VALUES (?, ?)').run('repair_pricing_tier_b_years', '5');
  db.prepare('INSERT INTO manufacturers (id, name) VALUES (1, ?)').run('Apple');
  db.prepare('INSERT INTO repair_services (id, name, slug, category) VALUES (1, ?, ?, ?)').run('Screen Replacement', 'screen-replacement', 'phone');
  db.prepare('INSERT INTO device_models (id, manufacturer_id, name, slug, category, release_year) VALUES (?, 1, ?, ?, ?, ?)').run(1, 'iPhone Current', 'iphone-current', 'phone', 2026);
  db.prepare('INSERT INTO device_models (id, manufacturer_id, name, slug, category, release_year) VALUES (?, 1, ?, ?, ?, ?)').run(2, 'iPhone Middle', 'iphone-middle', 'phone', 2023);
  db.prepare('INSERT INTO device_models (id, manufacturer_id, name, slug, category, release_year) VALUES (?, 1, ?, ?, ?, ?)').run(3, 'iPhone Old', 'iphone-old', 'phone', 2019);
  return db;
}

describe('dynamic repair pricing services', () => {
  it('classifies device models into configurable age tiers', () => {
    const thresholds = { tierAYears: 2, tierBYears: 5 };
    expect(tierForReleaseYear(2026, thresholds, 2026)).toBe('tier_a');
    expect(tierForReleaseYear(2023, thresholds, 2026)).toBe('tier_b');
    expect(tierForReleaseYear(2019, thresholds, 2026)).toBe('tier_c');
    expect(tierForReleaseYear(null, thresholds, 2026)).toBe('unknown');
  });

  it('bulk applies a tier default and preserves custom cells by default', () => {
    const db = buildDb();
    db.prepare(`
      INSERT INTO repair_prices (device_model_id, repair_service_id, labor_price, is_custom, tier_label)
      VALUES (1, 1, 299, 1, 'tier_a')
    `).run();

    const result = bulkApplyTier(db, {
      repairServiceId: 1,
      tier: 'tier_a',
      laborPrice: 249,
      changedByUserId: 7,
    });

    expect(result.matched_devices).toBe(1);
    expect(result.skipped_custom).toBe(1);
    expect(db.prepare('SELECT labor_price FROM repair_prices WHERE device_model_id = 1').get()).toMatchObject({ labor_price: 299 });

    const overwrite = bulkApplyTier(db, {
      repairServiceId: 1,
      tier: 'tier_a',
      laborPrice: 249,
      overwriteCustom: true,
    });

    expect(overwrite.updated).toBe(1);
    expect(db.prepare('SELECT labor_price, is_custom FROM repair_prices WHERE device_model_id = 1').get()).toMatchObject({
      labor_price: 249,
      is_custom: 0,
    });
    expect(db.prepare('SELECT COUNT(*) AS c FROM repair_prices_audit').get()).toMatchObject({ c: 1 });
  });

  it('seeds first-run pricing defaults through the server fan-out helper', () => {
    const db = buildDb();
    db.prepare('INSERT INTO repair_services (id, name, slug, category) VALUES (2, ?, ?, ?)').run('Battery Replacement', 'battery-replacement', 'phone');
    db.prepare('INSERT INTO repair_services (id, name, slug, category) VALUES (3, ?, ?, ?)').run('Charging Port Repair', 'charging-port', 'phone');
    db.prepare('INSERT INTO repair_services (id, name, slug, category) VALUES (4, ?, ?, ?)').run('Back Glass Replacement', 'back-glass', 'phone');
    db.prepare('INSERT INTO repair_services (id, name, slug, category) VALUES (5, ?, ?, ?)').run('Camera Repair', 'camera-repair', 'phone');

    const result = seedRepairPricingDefaults(db, {
      category: 'phone',
      pricing: {
        screen: { tier_a: 211, tier_b: 122, tier_c: 88 },
      },
      changedByUserId: 9,
    });

    expect(result.summary.services_matched).toBe(5);
    expect(result.summary.services_missing).toBe(0);
    expect(result.summary.inserted).toBe(15);
    expect(db.prepare(`
      SELECT labor_price, is_custom, tier_label
      FROM repair_prices
      WHERE device_model_id = 1 AND repair_service_id = 1
    `).get()).toMatchObject({ labor_price: 211, is_custom: 0, tier_label: 'tier_a' });
    expect(db.prepare(`
      SELECT value
      FROM store_config
      WHERE key = 'repair_pricing_default.1.tier_a'
    `).get()).toMatchObject({ value: '211' });
  });

  it('recomputes profit from an explicitly linked supplier grade', () => {
    const db = buildDb();
    const priceId = Number(db.prepare(`
      INSERT INTO repair_prices (device_model_id, repair_service_id, labor_price)
      VALUES (1, 1, 249)
    `).run().lastInsertRowid);
    db.prepare('INSERT INTO supplier_catalog (id, name, price, last_synced) VALUES (10, ?, 88.5, ?)').run('iPhone Current Screen Assembly', '2026-04-30T00:00:00Z');
    db.prepare('INSERT INTO repair_price_grades (repair_price_id, part_catalog_item_id, grade, grade_label) VALUES (?, 10, ?, ?)').run(priceId, 'aftermarket', 'Aftermarket');

    const result = recomputeRepairPriceProfits(db);

    expect(result.updated).toBe(1);
    expect(result.stale).toBe(0);
    expect(db.prepare('SELECT last_supplier_cost, profit_estimate, profit_stale_at FROM repair_prices WHERE id = ?').get(priceId)).toMatchObject({
      last_supplier_cost: 88.5,
      profit_estimate: 160.5,
      profit_stale_at: null,
    });
  });

  it('reverts a custom price to the stored tier default', () => {
    const db = buildDb();
    bulkApplyTier(db, { repairServiceId: 1, tier: 'tier_a', laborPrice: 249, overwriteCustom: true });
    const row = db.prepare('SELECT id FROM repair_prices WHERE device_model_id = 1').get() as { id: number };
    db.prepare('UPDATE repair_prices SET labor_price = 289, is_custom = 1 WHERE id = ?').run(row.id);

    const result = revertPriceToTier(db, row.id, 99);

    expect(result.default_source).toBe('stored_default');
    expect(db.prepare('SELECT labor_price, is_custom, tier_label FROM repair_prices WHERE id = ?').get(row.id)).toMatchObject({
      labor_price: 249,
      is_custom: 0,
      tier_label: 'tier_a',
    });
  });

  it('caps auto-margin changes per run', () => {
    expect(targetLaborForMargin(41, 60, 'ending_99')).toMatchObject({ uncapped: 102.5, rounded: 102.99 });
    expect(roundAutoMarginLabor(102.5, 'whole_dollar')).toBe(103);
    expect(roundAutoMarginLabor(102.5, 'ending_98')).toBe(102.98);
    expect(cappedAutoMarginLabor(100, 200, 60, 25, 'ending_99')).toBe(125);

    const db = buildDb();
    setAutoMarginSettings(db, {
      target_margin_pct: 60,
      rounding_mode: 'ending_99',
      cap_pct: 25,
    });
    db.prepare(`
      INSERT INTO repair_prices (
        device_model_id, repair_service_id, labor_price, is_custom,
        auto_margin_enabled, last_supplier_cost
      )
      VALUES (1, 1, 100, 0, 1, 200)
    `).run();

    const result = runAutoMargin(db);

    expect(result.adjusted).toBe(1);
    expect(result).toMatchObject({ target_margin_pct: 60, rounding_mode: 'ending_99' });
    expect(db.prepare('SELECT labor_price, suggested_labor_price, profit_estimate FROM repair_prices').get()).toMatchObject({
      labor_price: 125,
      suggested_labor_price: 500.99,
      profit_estimate: -75,
    });
  });

  it('applies service-specific auto-margin markup rules', () => {
    const db = buildDb();
    setAutoMarginSettings(db, {
      preset: 'custom',
      target_margin_pct: 60,
      calculation_basis: 'gross_margin',
      rounding_mode: 'ending_99',
      cap_pct: 100,
      rules: [{
        scope: 'repair_service',
        repair_service_slug: 'screen-replacement',
        target_margin_pct: 100,
        calculation_basis: 'markup',
        rounding_mode: 'ending_99',
        cap_pct: 100,
      }],
    });
    db.prepare(`
      INSERT INTO repair_prices (
        device_model_id, repair_service_id, labor_price, is_custom,
        auto_margin_enabled, last_supplier_cost
      )
      VALUES (1, 1, 50, 0, 1, 40)
    `).run();

    const result = runAutoMargin(db);

    expect(result.adjusted).toBe(1);
    expect(db.prepare('SELECT labor_price, suggested_labor_price, profit_estimate FROM repair_prices').get()).toMatchObject({
      labor_price: 80.99,
      suggested_labor_price: 80.99,
      profit_estimate: 40.99,
    });
  });

  it('supports fixed-dollar auto-margin profit targets', () => {
    expect(targetLaborForMargin(40, 100, 'ending_99', 'markup', 'fixed_amount', 55)).toMatchObject({
      uncapped: 95,
      rounded: 95.99,
    });

    const db = buildDb();
    setAutoMarginSettings(db, {
      preset: 'custom',
      target_type: 'fixed_amount',
      target_profit_amount: 55,
      rounding_mode: 'ending_99',
      cap_pct: 100,
    });
    db.prepare(`
      INSERT INTO repair_prices (
        device_model_id, repair_service_id, labor_price, is_custom,
        auto_margin_enabled, last_supplier_cost
      )
      VALUES (1, 1, 50, 0, 1, 40)
    `).run();

    const result = runAutoMargin(db);

    expect(result).toMatchObject({ preset: 'custom', target_type: 'fixed_amount', target_profit_amount: 55 });
    expect(db.prepare('SELECT labor_price, profit_estimate FROM repair_prices').get()).toMatchObject({
      labor_price: 95.99,
      profit_estimate: 55.99,
    });
  });
});
