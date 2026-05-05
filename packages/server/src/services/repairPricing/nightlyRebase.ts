import type Database from 'better-sqlite3';
import {
  getTierThresholds,
  tierForReleaseYear,
  tierLabel,
  getTierDefaultLabor,
  type PricingTier,
} from './tierResolver.js';

interface RebaseCandidate {
  id: number;
  device_model_id: number;
  repair_service_id: number;
  labor_price: number;
  is_custom: number;
  tier_label: string | null;
  release_year: number | null;
}

export interface TierCrossing {
  device_model_id: number;
  device_name: string;
  repair_service_id: number;
  service_name: string;
  old_tier: string | null;
  new_tier: PricingTier;
  old_labor: number;
  new_labor: number;
}

export interface NightlyRebaseResult {
  evaluated: number;
  rebased: number;
  skipped_custom: number;
  crossings: TierCrossing[];
  crossing_count: number;
}

export function runNightlyRebase(db: Database.Database): NightlyRebaseResult {
  const thresholds = getTierThresholds(db);
  const currentYear = new Date().getFullYear();

  const rows = db.prepare(`
    SELECT rp.id, rp.device_model_id, rp.repair_service_id,
           rp.labor_price, rp.is_custom, rp.tier_label,
           dm.release_year
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    WHERE rp.is_active = 1
  `).all() as RebaseCandidate[];

  const updateStmt = db.prepare(`
    UPDATE repair_prices
    SET labor_price = ?,
        tier_label = ?,
        last_tier_rebase_at = datetime('now'),
        updated_at = datetime('now')
    WHERE id = ?
  `);
  const auditStmt = db.prepare(`
    INSERT INTO repair_prices_audit (
      repair_price_id, device_model_id, repair_service_id,
      old_labor_price, new_labor_price, old_is_custom, new_is_custom,
      old_tier_label, new_tier_label, source, note
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 'tier', ?)
  `);
  const updateTierOnlyStmt = db.prepare(`
    UPDATE repair_prices
    SET tier_label = ?,
        last_tier_rebase_at = datetime('now'),
        updated_at = datetime('now')
    WHERE id = ?
  `);

  let rebased = 0;
  let skippedCustom = 0;
  const crossings: TierCrossing[] = [];

  const deviceNames = new Map<number, string>();
  const serviceNames = new Map<number, string>();

  const tx = db.transaction(() => {
    for (const row of rows) {
      const currentTier = tierForReleaseYear(row.release_year, thresholds, currentYear);
      if (currentTier === row.tier_label) continue;

      if (row.is_custom === 1) {
        updateTierOnlyStmt.run(currentTier, row.id);
        skippedCustom += 1;
        continue;
      }

      const defaultLabor = getTierDefaultLabor(db, row.repair_service_id, currentTier);
      if (defaultLabor == null) {
        updateTierOnlyStmt.run(currentTier, row.id);
        skippedCustom += 1;
        continue;
      }

      updateStmt.run(defaultLabor, currentTier, row.id);
      auditStmt.run(
        row.id,
        row.device_model_id,
        row.repair_service_id,
        row.labor_price,
        defaultLabor,
        row.is_custom,
        0,
        row.tier_label,
        currentTier,
        `Nightly rebase: ${row.tier_label ?? 'unknown'} → ${currentTier}`,
      );
      rebased += 1;

      if (!deviceNames.has(row.device_model_id)) {
        const d = db.prepare('SELECT name FROM device_models WHERE id = ?').get(row.device_model_id) as { name: string } | undefined;
        deviceNames.set(row.device_model_id, d?.name ?? `Device #${row.device_model_id}`);
      }
      if (!serviceNames.has(row.repair_service_id)) {
        const s = db.prepare('SELECT name FROM repair_services WHERE id = ?').get(row.repair_service_id) as { name: string } | undefined;
        serviceNames.set(row.repair_service_id, s?.name ?? `Service #${row.repair_service_id}`);
      }

      crossings.push({
        device_model_id: row.device_model_id,
        device_name: deviceNames.get(row.device_model_id)!,
        repair_service_id: row.repair_service_id,
        service_name: serviceNames.get(row.repair_service_id)!,
        old_tier: row.tier_label,
        new_tier: currentTier,
        old_labor: row.labor_price,
        new_labor: defaultLabor,
      });
    }
  });

  tx();

  const uniqueDevices = new Set(crossings.map((c) => c.device_model_id));

  if (crossings.length > 0) {
    const upsert = db.prepare(`
      INSERT OR REPLACE INTO store_config (key, value)
      VALUES (?, ?)
    `);
    const summary = {
      date: new Date().toISOString().slice(0, 10),
      device_count: uniqueDevices.size,
      crossing_count: crossings.length,
      crossings: crossings.slice(0, 50),
    };
    upsert.run('repair_pricing_last_rebase_summary', JSON.stringify(summary));
  }

  return {
    evaluated: rows.length,
    rebased,
    skipped_custom: skippedCustom,
    crossings,
    crossing_count: uniqueDevices.size,
  };
}

export interface RebaseSummary {
  date: string;
  device_count: number;
  crossing_count: number;
  crossings: TierCrossing[];
  acked_at: string | null;
}

export function getLastRebaseSummary(db: Database.Database): RebaseSummary | null {
  const row = db.prepare("SELECT value FROM store_config WHERE key = 'repair_pricing_last_rebase_summary'")
    .get() as { value?: string } | undefined;
  if (!row?.value) return null;
  try {
    const parsed = JSON.parse(row.value) as RebaseSummary;
    const ackRow = db.prepare("SELECT value FROM store_config WHERE key = 'repair_pricing_last_rebase_acked_at'")
      .get() as { value?: string } | undefined;
    parsed.acked_at = ackRow?.value ?? null;
    return parsed;
  } catch {
    return null;
  }
}

export function ackRebaseSummary(db: Database.Database): void {
  db.prepare("INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)")
    .run('repair_pricing_last_rebase_acked_at', new Date().toISOString());
}
