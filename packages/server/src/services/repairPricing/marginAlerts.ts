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

export interface TierProfitThreshold {
  green: number;
  amber: number;
  red: number;
}

export type TierProfitThresholdMap = Record<string, TierProfitThreshold>;

export interface MarginAlertDigestResult {
  queued: number;
  recipients: number;
  alerts: number;
  skipped_reason: string | null;
}

const DEFAULT_TIER_PROFIT_THRESHOLDS: TierProfitThresholdMap = {
  tier_a: { green: 100, amber: 60, red: 30 },
  tier_b: { green: 80, amber: 40, red: 20 },
  tier_c: { green: 60, amber: 30, red: 10 },
  unknown: { green: 80, amber: 40, red: 20 },
};

function configNumber(db: Database.Database, key: string, fallback: number): number {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  const parsed = Number(row?.value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function configString(db: Database.Database, key: string): string | null {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  return row?.value ?? null;
}

function upsertConfig(db: Database.Database, key: string, value: string): void {
  db.prepare(`
    INSERT INTO store_config (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value
  `).run(key, value);
}

function tableExists(db: Database.Database, tableName: string): boolean {
  const row = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?").get(tableName);
  return !!row;
}

function normalizedThreshold(value: unknown, fallback: TierProfitThreshold): TierProfitThreshold {
  const source = typeof value === 'object' && value !== null ? value as Record<string, unknown> : {};
  const green = Number(source.green ?? fallback.green);
  const amber = Number(source.amber ?? fallback.amber);
  const red = Number(source.red ?? fallback.red);
  const safeGreen = Number.isFinite(green) && green >= 0 ? Math.round(green * 100) / 100 : fallback.green;
  const safeAmber = Number.isFinite(amber) && amber >= 0 ? Math.round(amber * 100) / 100 : fallback.amber;
  const safeRed = Number.isFinite(red) && red >= 0 ? Math.round(red * 100) / 100 : fallback.red;
  const finalAmber = Math.min(safeGreen, safeAmber);
  return {
    green: safeGreen,
    amber: finalAmber,
    red: Math.min(finalAmber, safeRed),
  };
}

export function getTierProfitThresholds(db: Database.Database): TierProfitThresholdMap {
  const legacyGreen = configNumber(db, 'repair_pricing_target_profit_green', DEFAULT_TIER_PROFIT_THRESHOLDS.tier_b.green);
  const legacyAmber = configNumber(db, 'repair_pricing_target_profit_amber', DEFAULT_TIER_PROFIT_THRESHOLDS.tier_b.amber);
  const fallback: TierProfitThresholdMap = {
    ...DEFAULT_TIER_PROFIT_THRESHOLDS,
    unknown: { green: legacyGreen, amber: Math.min(legacyGreen, legacyAmber), red: Math.min(legacyAmber, Math.floor(legacyAmber / 2)) },
  };

  const raw = configString(db, 'repair_pricing_tier_profit_thresholds');
  if (!raw) return fallback;
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    return {
      tier_a: normalizedThreshold(parsed.tier_a, fallback.tier_a),
      tier_b: normalizedThreshold(parsed.tier_b, fallback.tier_b),
      tier_c: normalizedThreshold(parsed.tier_c, fallback.tier_c),
      unknown: normalizedThreshold(parsed.unknown, fallback.unknown),
    };
  } catch {
    return fallback;
  }
}

function thresholdForTier(thresholds: TierProfitThresholdMap, tier: string | null): TierProfitThreshold {
  return thresholds[tier || 'unknown'] ?? thresholds.unknown ?? DEFAULT_TIER_PROFIT_THRESHOLDS.unknown;
}

export function evaluateMarginAlerts(db: Database.Database): MarginAlertResult {
  const thresholds = getTierProfitThresholds(db);

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
      const amberThreshold = thresholdForTier(thresholds, row.tier_label).amber;
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

function htmlEscape(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

function isoWeekKey(date: Date): string {
  const d = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
  const day = d.getUTCDay() || 7;
  d.setUTCDate(d.getUTCDate() + 4 - day);
  const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1));
  const week = Math.ceil((((d.getTime() - yearStart.getTime()) / 86_400_000) + 1) / 7);
  return `${d.getUTCFullYear()}-W${String(week).padStart(2, '0')}`;
}

function buildMarginAlertDigestHtml(alerts: MarginAlertRow[]): string {
  const rows = alerts.slice(0, 50).map((alert) => {
    const device = alert.device_model_name ?? `Device #${alert.device_model_id}`;
    const service = alert.repair_service_name ?? `Service #${alert.repair_service_id}`;
    const profit = alert.profit_estimate == null ? 'unknown' : `$${alert.profit_estimate.toFixed(2)}`;
    const cost = alert.supplier_cost == null ? 'unknown' : `$${alert.supplier_cost.toFixed(2)}`;
    const days = alert.days_active ?? 0;
    return `
      <tr>
        <td style="padding:8px;border-bottom:1px solid #e2e8f0">${htmlEscape(device)}</td>
        <td style="padding:8px;border-bottom:1px solid #e2e8f0">${htmlEscape(service)}</td>
        <td style="padding:8px;border-bottom:1px solid #e2e8f0;text-align:right">${htmlEscape(profit)}</td>
        <td style="padding:8px;border-bottom:1px solid #e2e8f0;text-align:right">${htmlEscape(cost)}</td>
        <td style="padding:8px;border-bottom:1px solid #e2e8f0;text-align:right">${days}</td>
      </tr>`;
  }).join('');

  return `
    <div style="font-family:system-ui,-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;line-height:1.5;color:#0f172a">
      <p style="margin:0 0 16px">${alerts.length} repair pricing row${alerts.length === 1 ? '' : 's'} have been below the amber profit floor for 7+ days.</p>
      <table style="width:100%;border-collapse:collapse;font-size:14px">
        <thead>
          <tr style="background:#f8fafc">
            <th style="padding:8px;text-align:left;border-bottom:1px solid #cbd5e1">Device</th>
            <th style="padding:8px;text-align:left;border-bottom:1px solid #cbd5e1">Service</th>
            <th style="padding:8px;text-align:right;border-bottom:1px solid #cbd5e1">Profit</th>
            <th style="padding:8px;text-align:right;border-bottom:1px solid #cbd5e1">Supplier cost</th>
            <th style="padding:8px;text-align:right;border-bottom:1px solid #cbd5e1">Days</th>
          </tr>
        </thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

export function queueMarginAlertDigest(
  db: Database.Database,
  opts: { now?: Date } = {},
): MarginAlertDigestResult {
  if (!tableExists(db, 'notification_queue')) {
    return { queued: 0, recipients: 0, alerts: 0, skipped_reason: 'notification_queue_missing' };
  }
  if (!tableExists(db, 'users')) {
    return { queued: 0, recipients: 0, alerts: 0, skipped_reason: 'users_missing' };
  }

  const mode = (configString(db, 'notification_digest_mode') || 'immediate').toLowerCase();
  if (mode === 'off' || mode === 'disabled' || mode === 'none') {
    return { queued: 0, recipients: 0, alerts: 0, skipped_reason: 'notification_digest_disabled' };
  }

  const now = opts.now ?? new Date();
  const weekKey = isoWeekKey(now);
  if (configString(db, 'repair_pricing_margin_alert_digest_last_week') === weekKey) {
    return { queued: 0, recipients: 0, alerts: 0, skipped_reason: 'already_sent_this_week' };
  }

  const alerts = getActiveMarginAlerts(db, { limit: 50, minDays: 7 });
  if (alerts.length === 0) {
    return { queued: 0, recipients: 0, alerts: 0, skipped_reason: 'no_critical_alerts' };
  }

  const recipients = db.prepare(`
    SELECT email
    FROM users
    WHERE is_active = 1
      AND role = 'admin'
      AND email IS NOT NULL
      AND TRIM(email) != ''
    ORDER BY id ASC
  `).all() as { email: string }[];

  if (recipients.length === 0) {
    return { queued: 0, recipients: 0, alerts: alerts.length, skipped_reason: 'no_admin_recipients' };
  }

  const subject = `Repair pricing margin digest: ${alerts.length} row${alerts.length === 1 ? '' : 's'} need review`;
  const body = buildMarginAlertDigestHtml(alerts);
  const insert = db.prepare(`
    INSERT INTO notification_queue (type, recipient, subject, body, status, scheduled_at)
    VALUES ('email', ?, ?, ?, 'pending', datetime('now'))
  `);

  let queued = 0;
  const tx = db.transaction(() => {
    for (const recipient of recipients) {
      insert.run(recipient.email, subject, body);
      queued += 1;
    }
    upsertConfig(db, 'repair_pricing_margin_alert_digest_last_week', weekKey);
  });
  tx();

  return { queued, recipients: recipients.length, alerts: alerts.length, skipped_reason: null };
}
