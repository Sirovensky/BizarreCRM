import type Database from 'better-sqlite3';

interface PriceProfitRow {
  id: number;
  device_model_id: number;
  device_model_name: string;
  repair_service_id: number;
  repair_service_name: string;
  repair_service_slug: string;
  service_category: string | null;
  labor_price: number;
  last_supplier_cost: number | null;
}

interface SupplierMatch {
  supplier_catalog_id: number | null;
  name: string | null;
  price: number;
  last_seen: string | null;
  method: 'grade' | 'compatibility' | 'fuzzy';
}

export interface SupplierSpike {
  repair_price_id: number;
  device_model_id: number;
  repair_service_id: number;
  old_cost: number;
  new_cost: number;
  pct_change: number;
}

export interface ProfitRecomputeResult {
  processed: number;
  updated: number;
  stale: number;
  spikes: SupplierSpike[];
  details: Array<{
    repair_price_id: number;
    supplier_catalog_id: number | null;
    supplier_name: string | null;
    supplier_cost: number | null;
    profit_estimate: number | null;
    method: SupplierMatch['method'] | null;
  }>;
}

const SERVICE_TERM_RULES: Array<{ test: RegExp; terms: string[]; excludes?: string[] }> = [
  { test: /screen|lcd|oled|display/i, terms: ['screen'], excludes: ['protector', 'mold', 'adhesive', 'tape', 'stencil'] },
  { test: /battery/i, terms: ['battery'], excludes: ['adhesive', 'sticker'] },
  { test: /charging|charge|port|dock/i, terms: ['charging', 'port'] },
  { test: /back glass|back cover|housing/i, terms: ['back'], excludes: ['camera'] },
  { test: /camera/i, terms: ['camera'], excludes: ['lens', 'glass', 'sticker'] },
  { test: /speaker/i, terms: ['speaker'] },
  { test: /microphone|mic/i, terms: ['microphone'] },
  { test: /keyboard/i, terms: ['keyboard'] },
  { test: /fan/i, terms: ['fan'] },
  { test: /hdmi/i, terms: ['hdmi'] },
];

function escapeLike(value: string): string {
  return value.replace(/[\\%_]/g, (ch) => `\\${ch}`);
}

function serviceTerms(service: PriceProfitRow): { terms: string[]; excludes: string[] } {
  const haystack = `${service.repair_service_slug} ${service.repair_service_name} ${service.service_category ?? ''}`;
  const rule = SERVICE_TERM_RULES.find((candidate) => candidate.test.test(haystack));
  return {
    terms: rule?.terms ?? [],
    excludes: rule?.excludes ?? [],
  };
}

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

function latestGradeMatch(db: Database.Database, repairPriceId: number): SupplierMatch | null {
  const row = db.prepare(`
    SELECT sc.id AS supplier_catalog_id,
           sc.name,
           sc.price,
           sc.last_synced AS last_seen
    FROM repair_price_grades rpg
    JOIN supplier_catalog sc ON sc.id = rpg.part_catalog_item_id
    WHERE rpg.repair_price_id = ?
      AND sc.price > 0
    ORDER BY sc.last_synced DESC, sc.price ASC
    LIMIT 1
  `).get(repairPriceId) as Omit<SupplierMatch, 'method'> | undefined;

  return row ? { ...row, method: 'grade' } : null;
}

function catalogMatchForPrice(db: Database.Database, price: PriceProfitRow, useCompatibility: boolean): SupplierMatch | null {
  const { terms, excludes } = serviceTerms(price);
  if (terms.length === 0) return null;

  let sql = `
    SELECT sc.id AS supplier_catalog_id,
           sc.name,
           sc.price,
           sc.last_synced AS last_seen
    FROM supplier_catalog sc
  `;
  const params: unknown[] = [];

  if (useCompatibility) {
    sql += ' JOIN catalog_device_compatibility cdc ON cdc.supplier_catalog_id = sc.id AND cdc.device_model_id = ?';
    params.push(price.device_model_id);
  }

  sql += ' WHERE sc.price > 0';

  if (!useCompatibility) {
    const deviceWords = price.device_model_name.split(/\s+/).filter((word) => word.length >= 2).slice(0, 4);
    for (const word of deviceWords) {
      sql += " AND LOWER(sc.name) LIKE ? ESCAPE '\\'";
      params.push(`%${escapeLike(word.toLowerCase())}%`);
    }
  }

  for (const term of terms) {
    sql += " AND LOWER(sc.name) LIKE ? ESCAPE '\\'";
    params.push(`%${escapeLike(term.toLowerCase())}%`);
  }

  for (const exclude of excludes) {
    sql += " AND LOWER(sc.name) NOT LIKE ? ESCAPE '\\'";
    params.push(`%${escapeLike(exclude.toLowerCase())}%`);
  }

  sql += ' ORDER BY sc.last_synced DESC, sc.price ASC LIMIT 1';

  const row = db.prepare(sql).get(...params) as Omit<SupplierMatch, 'method'> | undefined;
  if (!row) return null;
  return { ...row, method: useCompatibility ? 'compatibility' : 'fuzzy' };
}

function findSupplierMatch(db: Database.Database, price: PriceProfitRow): SupplierMatch | null {
  return latestGradeMatch(db, price.id)
    ?? catalogMatchForPrice(db, price, true)
    ?? catalogMatchForPrice(db, price, false);
}

const SPIKE_THRESHOLD_PCT = 50;

export function recomputeRepairPriceProfits(
  db: Database.Database,
  opts: { priceIds?: number[]; detailLimit?: number } = {},
): ProfitRecomputeResult {
  const params: unknown[] = [];
  let where = 'rp.is_active = 1';

  if (opts.priceIds && opts.priceIds.length > 0) {
    const ids = opts.priceIds.map((id) => Math.trunc(id)).filter((id) => Number.isInteger(id) && id > 0);
    if (ids.length === 0) {
      return { processed: 0, updated: 0, stale: 0, spikes: [], details: [] };
    }
    where += ` AND rp.id IN (${ids.map(() => '?').join(',')})`;
    params.push(...ids);
  }

  const rows = db.prepare(`
    SELECT rp.id,
           rp.device_model_id,
           dm.name AS device_model_name,
           rp.repair_service_id,
           rs.name AS repair_service_name,
           rs.slug AS repair_service_slug,
           rs.category AS service_category,
           rp.labor_price,
           rp.last_supplier_cost
    FROM repair_prices rp
    JOIN device_models dm ON dm.id = rp.device_model_id
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE ${where}
  `).all(...params) as PriceProfitRow[];

  const updateFresh = db.prepare(`
    UPDATE repair_prices
    SET last_supplier_cost = ?,
        last_supplier_seen_at = ?,
        profit_estimate = ?,
        profit_stale_at = NULL,
        suggested_labor_price = COALESCE(suggested_labor_price, labor_price),
        updated_at = datetime('now')
    WHERE id = ?
  `);
  const markStale = db.prepare(`
    UPDATE repair_prices
    SET profit_stale_at = COALESCE(profit_stale_at, datetime('now')),
        updated_at = datetime('now')
    WHERE id = ?
  `);
  const pauseAutoMargin = db.prepare(`
    UPDATE repair_prices
    SET auto_margin_paused_at = datetime('now'),
        updated_at = datetime('now')
    WHERE id = ? AND auto_margin_enabled = 1
  `);
  const spikeAudit = db.prepare(`
    INSERT INTO repair_prices_audit (
      repair_price_id, device_model_id, repair_service_id,
      old_labor_price, new_labor_price, supplier_cost, profit_estimate,
      source, note
    )
    VALUES (?, ?, ?, ?, ?, ?, ?, 'supplier-spike', ?)
  `);

  let updated = 0;
  let stale = 0;
  const spikes: SupplierSpike[] = [];
  const details: ProfitRecomputeResult['details'] = [];
  const detailLimit = opts.detailLimit ?? 50;

  const tx = db.transaction(() => {
    for (const row of rows) {
      const match = findSupplierMatch(db, row);
      if (!match) {
        markStale.run(row.id);
        stale += 1;
        if (details.length < detailLimit) {
          details.push({
            repair_price_id: row.id,
            supplier_catalog_id: null,
            supplier_name: null,
            supplier_cost: null,
            profit_estimate: null,
            method: null,
          });
        }
        continue;
      }

      const supplierCost = roundMoney(Number(match.price));
      const profitEstimate = roundMoney(Number(row.labor_price) - supplierCost);

      if (row.last_supplier_cost != null && row.last_supplier_cost > 0) {
        const rawPct = ((supplierCost - row.last_supplier_cost) / row.last_supplier_cost) * 100;
        if (rawPct > SPIKE_THRESHOLD_PCT) {
          const pctChange = roundMoney(rawPct);
          pauseAutoMargin.run(row.id);
          spikeAudit.run(
            row.id, row.device_model_id, row.repair_service_id,
            row.labor_price, row.labor_price,
            supplierCost, profitEstimate,
            `Supplier cost spike: $${row.last_supplier_cost} → $${supplierCost} (+${pctChange}%). Auto-margin paused pending review.`,
          );
          spikes.push({
            repair_price_id: row.id,
            device_model_id: row.device_model_id,
            repair_service_id: row.repair_service_id,
            old_cost: row.last_supplier_cost,
            new_cost: supplierCost,
            pct_change: pctChange,
          });
        }
      }

      updateFresh.run(supplierCost, match.last_seen, profitEstimate, row.id);
      updated += 1;

      if (details.length < detailLimit) {
        details.push({
          repair_price_id: row.id,
          supplier_catalog_id: match.supplier_catalog_id,
          supplier_name: match.name,
          supplier_cost: supplierCost,
          profit_estimate: profitEstimate,
          method: match.method,
        });
      }
    }
  });

  tx();
  return { processed: rows.length, updated, stale, spikes, details };
}
