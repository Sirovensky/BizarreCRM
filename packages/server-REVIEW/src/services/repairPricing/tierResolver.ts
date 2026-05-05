import type Database from 'better-sqlite3';

export type PricingTier = 'tier_a' | 'tier_b' | 'tier_c' | 'unknown';

export interface TierThresholds {
  /** Models released within this many years are Tier A / Flagship. */
  tierAYears: number;
  /** Models newer than Tier A and within this many years are Tier B / Mainstream. */
  tierBYears: number;
}

export interface TierDescriptor {
  key: PricingTier;
  label: string;
  maxAgeYears: number | null;
}

export const DEFAULT_TIER_THRESHOLDS: TierThresholds = {
  tierAYears: 2,
  tierBYears: 5,
};

const TIER_LABELS: Record<PricingTier, string> = {
  tier_a: 'Flagship',
  tier_b: 'Mainstream',
  tier_c: 'Legacy',
  unknown: 'Unknown',
};

function configNumber(db: Database.Database, key: string, fallback: number): number {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  const parsed = Number(row?.value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function normalizeTierThresholds(input: Partial<TierThresholds>): TierThresholds {
  const tierAYears = Math.max(0, Math.min(50, Math.trunc(input.tierAYears ?? DEFAULT_TIER_THRESHOLDS.tierAYears)));
  const rawTierB = Math.max(0, Math.min(50, Math.trunc(input.tierBYears ?? DEFAULT_TIER_THRESHOLDS.tierBYears)));
  return {
    tierAYears,
    tierBYears: Math.max(tierAYears, rawTierB),
  };
}

export function getTierThresholds(db: Database.Database): TierThresholds {
  return normalizeTierThresholds({
    tierAYears: configNumber(db, 'repair_pricing_tier_a_years', DEFAULT_TIER_THRESHOLDS.tierAYears),
    tierBYears: configNumber(db, 'repair_pricing_tier_b_years', DEFAULT_TIER_THRESHOLDS.tierBYears),
  });
}

export function setTierThresholds(db: Database.Database, thresholds: TierThresholds): TierThresholds {
  const normalized = normalizeTierThresholds(thresholds);
  const upsert = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const tx = db.transaction(() => {
    upsert.run('repair_pricing_tier_a_years', String(normalized.tierAYears));
    upsert.run('repair_pricing_tier_b_years', String(normalized.tierBYears));
  });
  tx();
  return normalized;
}

export function pricingTierDescriptors(thresholds: TierThresholds): TierDescriptor[] {
  return [
    { key: 'tier_a', label: TIER_LABELS.tier_a, maxAgeYears: thresholds.tierAYears },
    { key: 'tier_b', label: TIER_LABELS.tier_b, maxAgeYears: thresholds.tierBYears },
    { key: 'tier_c', label: TIER_LABELS.tier_c, maxAgeYears: null },
    { key: 'unknown', label: TIER_LABELS.unknown, maxAgeYears: null },
  ];
}

export function tierLabel(tier: PricingTier): string {
  return TIER_LABELS[tier];
}

export function parsePricingTier(value: unknown): PricingTier | null {
  if (value === 'tier_a' || value === 'tier_b' || value === 'tier_c' || value === 'unknown') return value;
  return null;
}

export function tierForReleaseYear(
  releaseYear: number | null | undefined,
  thresholds: TierThresholds = DEFAULT_TIER_THRESHOLDS,
  currentYear = new Date().getFullYear(),
): PricingTier {
  if (!Number.isInteger(releaseYear) || releaseYear! <= 0 || releaseYear! > currentYear + 1) return 'unknown';
  const age = currentYear - releaseYear!;
  if (age <= thresholds.tierAYears) return 'tier_a';
  if (age <= thresholds.tierBYears) return 'tier_b';
  return 'tier_c';
}

export function tierDefaultConfigKey(repairServiceId: number, tier: PricingTier): string {
  return `repair_pricing_default.${repairServiceId}.${tier}`;
}

export function getTierDefaultLabor(db: Database.Database, repairServiceId: number, tier: PricingTier): number | null {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(tierDefaultConfigKey(repairServiceId, tier)) as { value?: string } | undefined;
  const parsed = Number(row?.value);
  return Number.isFinite(parsed) ? parsed : null;
}

function setTierDefaultLabor(db: Database.Database, repairServiceId: number, tier: PricingTier, laborPrice: number): void {
  db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)').run(
    tierDefaultConfigKey(repairServiceId, tier),
    String(laborPrice),
  );
}

interface DeviceTierRow {
  id: number;
  release_year: number | null;
  category: string;
}

interface ExistingPriceRow {
  id: number;
  labor_price: number;
  is_custom: number;
  tier_label: string | null;
}

export interface BulkApplyTierOptions {
  repairServiceId: number;
  tier: PricingTier;
  laborPrice: number;
  category?: string;
  overwriteCustom?: boolean;
  changedByUserId?: number | null;
}

export interface BulkApplyTierResult {
  tier: PricingTier;
  tier_label: string;
  repair_service_id: number;
  labor_price: number;
  matched_devices: number;
  inserted: number;
  updated: number;
  skipped_custom: number;
}

export function bulkApplyTier(db: Database.Database, opts: BulkApplyTierOptions): BulkApplyTierResult {
  const thresholds = getTierThresholds(db);
  const tier = opts.tier;
  const categoryClause = opts.category ? 'WHERE category = ?' : '';
  const devices = db.prepare(`SELECT id, release_year, category FROM device_models ${categoryClause}`)
    .all(...(opts.category ? [opts.category] : [])) as DeviceTierRow[];
  const tierDevices = devices.filter((device) => tierForReleaseYear(device.release_year, thresholds) === tier);
  const tierText = tierLabel(tier);

  const existingStmt = db.prepare(`
    SELECT id, labor_price, is_custom, tier_label
    FROM repair_prices
    WHERE device_model_id = ? AND repair_service_id = ?
  `);
  const insertStmt = db.prepare(`
    INSERT INTO repair_prices (
      device_model_id, repair_service_id, labor_price, default_grade,
      is_active, is_custom, tier_label, last_tier_rebase_at
    )
    VALUES (?, ?, ?, 'aftermarket', 1, 0, ?, datetime('now'))
  `);
  const updateStmt = db.prepare(`
    UPDATE repair_prices
    SET labor_price = ?,
        is_custom = 0,
        tier_label = ?,
        last_tier_rebase_at = datetime('now'),
        updated_at = datetime('now')
    WHERE id = ?
  `);
  const auditStmt = db.prepare(`
    INSERT INTO repair_prices_audit (
      repair_price_id, device_model_id, repair_service_id,
      old_labor_price, new_labor_price, old_is_custom, new_is_custom,
      old_tier_label, new_tier_label, source, changed_by_user_id, note
    )
    VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, 'tier', ?, ?)
  `);

  let inserted = 0;
  let updated = 0;
  let skippedCustom = 0;

  const tx = db.transaction(() => {
    setTierDefaultLabor(db, opts.repairServiceId, tier, opts.laborPrice);

    for (const device of tierDevices) {
      const existing = existingStmt.get(device.id, opts.repairServiceId) as ExistingPriceRow | undefined;
      if (existing && existing.is_custom === 1 && !opts.overwriteCustom) {
        skippedCustom += 1;
        continue;
      }

      if (existing) {
        updateStmt.run(opts.laborPrice, tier, existing.id);
        auditStmt.run(
          existing.id,
          device.id,
          opts.repairServiceId,
          existing.labor_price,
          opts.laborPrice,
          existing.is_custom,
          existing.tier_label,
          tier,
          opts.changedByUserId ?? null,
          'Tier default applied from repair-pricing matrix',
        );
        updated += 1;
      } else {
        const result = insertStmt.run(device.id, opts.repairServiceId, opts.laborPrice, tier);
        const priceId = Number(result.lastInsertRowid);
        auditStmt.run(
          priceId,
          device.id,
          opts.repairServiceId,
          null,
          opts.laborPrice,
          null,
          null,
          tier,
          opts.changedByUserId ?? null,
          'Tier default inserted from repair-pricing matrix',
        );
        inserted += 1;
      }
    }
  });

  tx();

  return {
    tier,
    tier_label: tierText,
    repair_service_id: opts.repairServiceId,
    labor_price: opts.laborPrice,
    matched_devices: tierDevices.length,
    inserted,
    updated,
    skipped_custom: skippedCustom,
  };
}

export interface RevertPriceResult {
  price: Record<string, unknown>;
  tier: PricingTier;
  tier_label: string;
  default_source: 'stored_default' | 'peer_average' | 'current_price';
}

export function revertPriceToTier(db: Database.Database, priceId: number, changedByUserId?: number | null): RevertPriceResult {
  const thresholds = getTierThresholds(db);
  const row = db.prepare(`
    SELECT rp.*, dm.release_year
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    WHERE rp.id = ?
  `).get(priceId) as (ExistingPriceRow & {
    device_model_id: number;
    repair_service_id: number;
    release_year: number | null;
  }) | undefined;

  if (!row) throw new Error('Price not found');

  const tier = tierForReleaseYear(row.release_year, thresholds);
  let labor = getTierDefaultLabor(db, row.repair_service_id, tier);
  let defaultSource: RevertPriceResult['default_source'] = 'stored_default';

  if (labor == null) {
    const avgRow = db.prepare(`
      SELECT AVG(labor_price) AS avg_labor
      FROM repair_prices
      WHERE repair_service_id = ?
        AND tier_label = ?
        AND is_custom = 0
        AND is_active = 1
        AND id != ?
        AND labor_price >= 0
    `).get(row.repair_service_id, tier, priceId) as { avg_labor?: number | null } | undefined;
    if (avgRow?.avg_labor != null && Number.isFinite(Number(avgRow.avg_labor))) {
      labor = Math.round(Number(avgRow.avg_labor) * 100) / 100;
      defaultSource = 'peer_average';
    }
  }

  if (labor == null) {
    labor = row.labor_price;
    defaultSource = 'current_price';
  }

  const tx = db.transaction(() => {
    db.prepare(`
      UPDATE repair_prices
      SET labor_price = ?,
          is_custom = 0,
          tier_label = ?,
          last_tier_rebase_at = datetime('now'),
          updated_at = datetime('now')
      WHERE id = ?
    `).run(labor, tier, priceId);

    db.prepare(`
      INSERT INTO repair_prices_audit (
        repair_price_id, device_model_id, repair_service_id,
        old_labor_price, new_labor_price, old_is_custom, new_is_custom,
        old_tier_label, new_tier_label, source, changed_by_user_id, note
      )
      VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?, 'revert', ?, ?)
    `).run(
      priceId,
      row.device_model_id,
      row.repair_service_id,
      row.labor_price,
      labor,
      row.is_custom,
      row.tier_label,
      tier,
      changedByUserId ?? null,
      `Reverted to tier default via ${defaultSource}`,
    );
  });
  tx();

  const price = db.prepare('SELECT * FROM repair_prices WHERE id = ?').get(priceId) as Record<string, unknown>;
  return { price, tier, tier_label: tierLabel(tier), default_source: defaultSource };
}
