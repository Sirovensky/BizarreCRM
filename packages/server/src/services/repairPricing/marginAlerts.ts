import type Database from 'better-sqlite3';

interface AlertCandidate {
  id: number;
  device_model_id: number;
  repair_service_id: number;
  tier_label: string | null;
  labor_price: number;
  last_supplier_cost: number | null;
  profit_estimate: number | null;
}

export interface MarginAlertResult {
  evaluated: number;
  new_alerts: number;
  updated: number;
  resolved: number;
}

export interface MarginAlertRow {
  id: number;
  repair_price_id: number;
  device_model_id: number;
  repair_service_id: number;
  tier_label: string | null;
  labor_price: number;
  supplier_cost: number | null;
  profit_estimate: number | null;
  amber_threshold: number;
  first_seen_at: string;
  last_seen_at: string;
  resolved_at: string | null;
  acked_at: string | null;
  device_model_name?: string;
  repair_service_name?: string;
  days_active?: number;
}

function configNumber(db: Database.Database, key: string, fallback: number): number {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  const parsed = Number(row?.value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

export function evaluateMarginAlerts(db: Database.Database): MarginAlertResult {
  const amberThreshold = configNumber(db, 'repair_pricing_target_profit_amber', 40);

  const rows = db.prepare(`
    SELECT rp.id, rp.device_model_id, rp.repair_service_id,
           rp.tier_label, rp.labor_price, rp.last_supplier_cost, rp.profit_estimate
    FROM repair_prices rp
    WHERE rp.is_active = 1
      AND rp.profit_estimate IS NOT NULL
  `).all() as AlertCandidate[];

  const upsertAlert = db.prepare(`
    INSERT INTO margin_alerts (
      repair_price_id, device_model_id, repair_service_id,
      tier_label, labor_price, supplier_cost, profit_estimate,
      amber_threshold
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT (repair_price_id) WHERE resolved_at IS NULL
    DO UPDATE SET
      labor_price = excluded.labor_price,
      supplier_cost = excluded.supplier_cost,
      profit_estimate = excluded.profit_estimate,
      last_seen_at = datetime('now')
  `);
  const resolveAlert = db.prepare(`
    UPDATE margin_alerts
    SET resolved_at = datetime('now')
    WHERE repair_price_id = ?
      AND resolved_at IS NULL
  `);

  let newAlerts = 0;
  let updated = 0;
  let resolved = 0;

  const belowThresholdIds = new Set<number>();

  const tx = db.transaction(() => {
    for (const row of rows) {
      if (row.profit_estimate != null && row.profit_estimate < amberThreshold) {
        belowThresholdIds.add(row.id);

        const existing = db.prepare(`
          SELECT id FROM margin_alerts
          WHERE repair_price_id = ? AND resolved_at IS NULL
        `).get(row.id) as { id: number } | undefined;

        upsertAlert.run(
          row.id, row.device_model_id, row.repair_service_id,
          row.tier_label, row.labor_price, row.last_supplier_cost,
          row.profit_estimate, amberThreshold,
        );

        if (existing) {
          updated += 1;
        } else {
          newAlerts += 1;
        }
      }
    }

    const openAlerts = db.prepare(`
      SELECT repair_price_id FROM margin_alerts WHERE resolved_at IS NULL
    `).all() as { repair_price_id: number }[];

    for (const alert of openAlerts) {
      if (!belowThresholdIds.has(alert.repair_price_id)) {
        resolveAlert.run(alert.repair_price_id);
        resolved += 1;
      }
    }
  });

  tx();

  return { evaluated: rows.length, new_alerts: newAlerts, updated, resolved };
}

export function getActiveMarginAlerts(
  db: Database.Database,
  opts: { limit?: number; minDays?: number } = {},
): MarginAlertRow[] {
  const limit = Math.min(opts.limit ?? 100, 500);
  const minDays = opts.minDays ?? 0;

  return db.prepare(`
    SELECT ma.*,
           dm.name AS device_model_name,
           rs.name AS repair_service_name,
           CAST(
             (julianday('now') - julianday(ma.first_seen_at)) AS INTEGER
           ) AS days_active
    FROM margin_alerts ma
    JOIN device_models dm ON dm.id = ma.device_model_id
    JOIN repair_services rs ON rs.id = ma.repair_service_id
    WHERE ma.resolved_at IS NULL
      AND (julianday('now') - julianday(ma.first_seen_at)) >= ?
    ORDER BY ma.profit_estimate ASC, ma.first_seen_at ASC
    LIMIT ?
  `).all(minDays, limit) as MarginAlertRow[];
}

export function ackMarginAlert(db: Database.Database, alertId: number): boolean {
  const result = db.prepare(`
    UPDATE margin_alerts SET acked_at = datetime('now')
    WHERE id = ? AND resolved_at IS NULL
  `).run(alertId);
  return result.changes > 0;
}

export function getMarginAlertSummary(db: Database.Database): {
  total_active: number;
  unacked: number;
  critical: number;
} {
  const row = db.prepare(`
    SELECT
      COUNT(*) AS total_active,
      SUM(CASE WHEN acked_at IS NULL THEN 1 ELSE 0 END) AS unacked,
      SUM(CASE WHEN (julianday('now') - julianday(first_seen_at)) >= 7 THEN 1 ELSE 0 END) AS critical
    FROM margin_alerts
    WHERE resolved_at IS NULL
  `).get() as { total_active: number; unacked: number; critical: number };
  return {
    total_active: row.total_active ?? 0,
    unacked: row.unacked ?? 0,
    critical: row.critical ?? 0,
  };
}
