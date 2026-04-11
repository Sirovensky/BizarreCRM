/**
 * Supplier catalog scraper — Mobilesentrix & PhoneLcdParts
 *
 * Both sites are Magento 2 stores. Their Shopify-style /products.json is NOT
 * available (returns 404). We scrape their HTML search result pages instead.
 *
 * Full-catalog sync strategy:
 *   scrapeCatalog(source) iterates through search queries for each major brand /
 *   device category so we capture the entire parts library in one background job.
 *
 * Live search strategy (for parts selection in tickets):
 *   liveSearchSupplier(source, query) fetches just the first page of search results
 *   in real time — used when the local supplier_catalog has no match.
 */

import * as cheerio from 'cheerio';
import { createHash } from 'crypto';
import { createLogger } from '../utils/logger.js';
import { escapeLike } from '../utils/query.js';

const logger = createLogger('catalog-scraper');

// SC1: Internal sentinel thrown from the scrapeCatalog concurrency guard so
// the outer catch can distinguish a "skip — another job is running" case from
// a genuine DB failure. Kept private to this module.
class AppError_ConcurrentScrape extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'AppError_ConcurrentScrape';
  }
}

export type CatalogSource = 'mobilesentrix' | 'phonelcdparts';

const BASE_URLS: Record<CatalogSource, string> = {
  mobilesentrix: 'https://www.mobilesentrix.com',
  phonelcdparts: 'https://www.phonelcdparts.com',
};

// Broad search terms that collectively cover a repair shop's entire parts catalog.
// Running all of these in sequence gives us a near-complete scrape.
const FULL_CATALOG_QUERIES = [
  // Device brands
  'apple', 'iphone', 'ipad', 'macbook',
  'samsung', 'galaxy',
  'google', 'pixel',
  'motorola', 'moto',
  'lg',
  'oneplus',
  'huawei',
  'sony',
  'nokia',
  'htc',
  // Part types (catch anything not covered by brand)
  'screen', 'lcd', 'oled', 'digitizer',
  'battery',
  'camera',
  'charging port', 'flex cable',
  'back cover', 'housing',
  'speaker', 'microphone',
  'button', 'volume',
  'board', 'logic',
  // Consoles
  'nintendo switch', 'playstation',
  'ps5', 'ps4', 'ps3', 'ps2',
  'xbox', 'series x', 'series s',
];

export interface ScrapedProduct {
  externalId: string;    // URL slug or SKU — unique key per source
  name: string;
  sku: string | null;
  price: number;
  comparePrice: number | null;
  imageUrl: string | null;
  productUrl: string;
  category: string | null;
  inStock: boolean;
  compatibleDevices: string[];
}

// ─── HTML Parsing ─────────────────────────────────────────────────────────────

/**
 * SC3: Smart multi-locale price parser.
 * Handles `$1,234.56`, `€1.234,56`, `1234`, `1,234`, `CHF 1'234.56`, etc.
 * Rule: if both `.` and `,` are present, whichever appears LAST is the decimal
 * separator and the other is a thousands separator.
 */
export function parsePrice(raw: string | null | undefined): number | null {
  if (!raw) return null;
  const cleaned = String(raw).replace(/[^\d.,]/g, '');
  if (!cleaned) return null;

  const lastDot = cleaned.lastIndexOf('.');
  const lastComma = cleaned.lastIndexOf(',');

  let normalized: string;
  if (lastDot > -1 && lastComma > -1) {
    if (lastDot > lastComma) {
      // US/UK: 1,234.56 — comma is thousands
      normalized = cleaned.replace(/,/g, '');
    } else {
      // EU: 1.234,56 — dot is thousands, comma is decimal
      normalized = cleaned.replace(/\./g, '').replace(',', '.');
    }
  } else if (lastComma > -1) {
    // Only comma present — treat as decimal separator
    // (e.g. "12,50" → 12.50). Two+ commas means thousands-only.
    const commaCount = (cleaned.match(/,/g) || []).length;
    if (commaCount > 1) {
      normalized = cleaned.replace(/,/g, '');
    } else {
      // If the fraction after comma is 3 digits and there's no earlier comma,
      // it's almost certainly a thousands separator ("1,234" not 1.234).
      const afterComma = cleaned.substring(lastComma + 1);
      normalized = afterComma.length === 3 && !/\./.test(cleaned)
        ? cleaned.replace(',', '')
        : cleaned.replace(',', '.');
    }
  } else {
    normalized = cleaned;
  }

  const num = parseFloat(normalized);
  if (isNaN(num) || !isFinite(num) || num < 0) return null;
  return num;
}

/**
 * SC6: Stable externalId fallback. Slugified 80-char truncation collides when
 * two long names share the first 80 chars; a SHA-256 (first 32 hex chars) is
 * effectively collision-free for a catalog of millions of rows.
 */
function hashExternalId(name: string): string {
  const trimmed = (name || '').trim();
  if (!trimmed) return createHash('sha256').update('anonymous-' + Date.now()).digest('hex').substring(0, 32);
  return createHash('sha256').update(trimmed).digest('hex').substring(0, 32);
}

/**
 * SC4: Selector fallback helper. Tries each selector in turn and returns the
 * first non-empty match. Logs a structured error with the HTML snippet when
 * all selectors miss so operators can diagnose supplier template changes.
 */
interface SelectorFallbackOptions {
  supplier: string;
  field: string;
  htmlSnippet?: string;
  silentOnMiss?: boolean;
}
function firstNonEmpty<T>(
  candidates: ReadonlyArray<() => T | null | undefined>,
  opts: SelectorFallbackOptions,
): T | null {
  for (const fn of candidates) {
    try {
      const value = fn();
      if (value !== null && value !== undefined && value !== '') return value;
    } catch {
      // continue to next fallback
    }
  }
  if (!opts.silentOnMiss) {
    logger.warn('catalog scraper: selector mismatch', {
      supplier: opts.supplier,
      field: opts.field,
      html_snippet: (opts.htmlSnippet || '').substring(0, 300),
    });
  }
  return null;
}

/**
 * Parse Magento 2 product listing HTML → ScrapedProduct[].
 *
 * We try multiple selector patterns because themes vary between MS and PLP.
 * If nothing matches we return an empty array — the caller simply moves on.
 */
export function parseProductsFromHtml(html: string, baseUrl: string, supplier: string = 'unknown'): ScrapedProduct[] {
  const $ = cheerio.load(html);
  const products: ScrapedProduct[] = [];

  // SC4: Selector fallback chain for the root item list.
  // Each chain entry is a selector that should return non-empty matches on a valid results page.
  const itemSelectorChains = [
    '.product-item, .item.product, [data-product-id]',
    '.products-grid li.item, .category-products li.item',
    'li.item',
    '[class*="product"][class*="item"]',
  ];

  let $items = $('');
  let matchedChain: string | null = null;
  for (const chain of itemSelectorChains) {
    const found = $(chain);
    if (found.length > 0) {
      $items = found;
      matchedChain = chain;
      break;
    }
  }

  if ($items.length === 0 || !matchedChain) {
    logger.error('catalog scraper: no product items matched any fallback selector', {
      supplier,
      field: 'product_items',
      html_snippet: html.substring(0, 500),
    });
    return products;
  }

  $items.each((_i, el) => {
    const $el = $(el);
    const elHtml = $.html(el) || '';

    // ── Name: priority chain of selectors ──
    let nameEl = $el.find('.product-item-link').first();
    let name = nameEl.text().trim();
    if (!name) {
      nameEl = $el.find('.product-item-name a, .product.name a').first();
      name = nameEl.text().trim();
    }
    if (!name) {
      nameEl = $el.find('h2.product-name, .product-name').first();
      name = nameEl.text().trim();
    }
    if (!name) {
      // Last resort: any anchor inside the item
      nameEl = $el.find('a[href]').first();
      name = nameEl.attr('title')?.trim() || nameEl.text().trim() || '';
    }
    if (!name) {
      logger.warn('catalog scraper: selector mismatch', { supplier, field: 'name', html_snippet: elHtml.substring(0, 200) });
      return; // skip malformed items
    }

    // ── Product URL ──
    const href = firstNonEmpty<string>([
      () => nameEl.attr('href'),
      () => $el.find('a.product-item-link, a.product-item-photo').first().attr('href'),
      () => $el.find('a.product-image').first().attr('href'),
      () => $el.find('a[href]').first().attr('href'),
    ], { supplier, field: 'product_url', htmlSnippet: elHtml, silentOnMiss: true }) || '';
    const productUrl = href.startsWith('http') ? href : `${baseUrl}${href}`;

    // ── Magento product id from data attributes ──
    const dataId = firstNonEmpty<string>([
      () => $el.attr('data-product-id'),
      () => $el.find('[data-product-id]').first().attr('data-product-id'),
      () => $el.find('form[data-product-id]').first().attr('data-product-id'),
      () => $el.find('.price-box[data-product-id]').first().attr('data-product-id'),
      () => $el.find('input[name="product"]').first().attr('value'),
    ], { supplier, field: 'data-product-id', htmlSnippet: elHtml, silentOnMiss: true });

    const urlSlug = productUrl.split('/').filter(Boolean).pop()?.split('?')[0] || '';
    // SC6: collision-free fallback using SHA-256 (first 32 hex chars)
    const externalId = dataId || urlSlug || hashExternalId(name);

    // ── Price: try data-price-amount first, then SC3 smart parser ──
    const priceAttrRaw = $el.find('[data-price-amount]').first().attr('data-price-amount');
    const priceTextRaw = $el.find('.price').first().text();
    const price = parsePrice(priceAttrRaw) ?? parsePrice(priceTextRaw) ?? 0;

    if (price === 0) {
      logger.warn('catalog scraper: price parse failed', {
        supplier,
        field: 'price',
        raw_attr: priceAttrRaw,
        raw_text: priceTextRaw?.substring(0, 80),
      });
    }

    const comparePriceAttrRaw = $el.find('[data-price-type="oldPrice"] [data-price-amount]').first().attr('data-price-amount');
    const comparePrice = parsePrice(comparePriceAttrRaw);

    // ── Image: fallback chain ──
    const imgEl = $el.find('.product-image-photo, img.small-img, img.lazyimage, img.product-image, img[loading]').first();
    let imageUrl = imgEl.attr('data-original') || imgEl.attr('data-src') || imgEl.attr('src') || null;
    if (imageUrl && imageUrl.includes('/wysiwyg/')) {
      const altImg = $el.find('img.small-img, img.lazyimage, .product-image-photo').first();
      imageUrl = altImg.attr('data-original') || altImg.attr('data-src') || altImg.attr('src') || null;
    }
    if (imageUrl && imageUrl.startsWith('//')) imageUrl = `https:${imageUrl}`;
    if (imageUrl && imageUrl.startsWith('/') && !imageUrl.startsWith('//')) imageUrl = `${baseUrl}${imageUrl}`;

    // ── SKU ──
    const skuFromAttr = $el.attr('data-sku')?.trim()
      || $el.find('[data-sku]').attr('data-sku')?.trim()
      || null;
    const skuEl = $el.find('.sku .value, .product-sku').first();
    const sku = skuFromAttr || skuEl.text().trim() || null;

    // ── Stock indicator ──
    const stockText = $el.find('.stock.available, .in-stock, .stock-available').text().toLowerCase();
    const outOfStockText = $el.find('.stock.unavailable, .out-of-stock, .stock-unavailable').text().toLowerCase();
    const inStock = outOfStockText.length === 0 || stockText.includes('in stock');

    const compatibleDevices = parseCompatibleDevices(name);

    products.push({
      externalId,
      name,
      sku: sku || null,
      price,
      comparePrice,
      imageUrl,
      productUrl,
      category: null, // filled in by caller when known
      inStock,
      compatibleDevices,
    });
  });

  return products;
}

/** Extract device model names from a part title.
 *  e.g. "LCD Assembly Compatible For iPhone 14 Pro" → ["iPhone 14 Pro"]
 *  e.g. "Screen For Samsung Galaxy S23 Ultra" → ["Galaxy S23 Ultra", "Samsung Galaxy S23 Ultra"]
 */
export function parseCompatibleDevices(title: string): string[] {
  const models = new Set<string>();

  // Pattern: "for <Model>" or "compatible for <Model>" or "compatible with <Model>"
  const patterns = [
    /(?:compatible\s+(?:for|with)|for)\s+([A-Za-z0-9][^,\-–\(]+?)(?:\s*[-–\(,]|$)/i,
    /([A-Za-z]+ (?:iPhone|iPad|Galaxy|Pixel|Moto|Switch|MacBook|Surface)\s+\S+)/i,
  ];

  for (const pat of patterns) {
    const m = title.match(pat);
    if (m) {
      const raw = m[1].trim().replace(/\s+/g, ' ');
      if (raw.length > 3) {
        models.add(raw);
        // Also without manufacturer prefix
        const stripped = raw.replace(/^(Apple|Samsung|Google|Motorola|LG|OnePlus|Sony|Nokia|HTC|Huawei|Microsoft|Nintendo)\s+/i, '');
        if (stripped !== raw) models.add(stripped);
      }
    }
  }

  return [...models];
}

/** Map parsed device name strings to device_model.id values in our DB */
function matchDeviceModels(db: any, deviceNames: string[]): number[] {
  const ids: number[] = [];
  for (const name of deviceNames) {
    const row = db.prepare(`
      SELECT id FROM device_models WHERE LOWER(name) = LOWER(?)
      UNION
      SELECT id FROM device_models WHERE LOWER(?) LIKE '%' || LOWER(name) || '%'
      LIMIT 1
    `).get(name, name) as { id: number } | undefined;
    if (row) ids.push(row.id);
  }
  return [...new Set(ids)];
}

// ─── HTTP helpers ─────────────────────────────────────────────────────────────

const REQUEST_HEADERS = {
  'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'en-US,en;q=0.9',
};

/** Fetch one page of Magento search results and return parsed products */
async function fetchSearchPage(
  source: CatalogSource,
  query: string,
  page: number,
): Promise<{ products: ScrapedProduct[]; hasMore: boolean }> {
  const baseUrl = BASE_URLS[source];
  const encoded = encodeURIComponent(query);

  // Mobilesentrix rejects `product_list_limit` param (returns 404).
  // PhoneLcdParts accepts it fine. Build URL accordingly.
  let url: string;
  if (source === 'mobilesentrix') {
    url = page > 1
      ? `${baseUrl}/catalogsearch/result/?q=${encoded}&p=${page}`
      : `${baseUrl}/catalogsearch/result/?q=${encoded}`;
  } else {
    url = `${baseUrl}/catalogsearch/result/?q=${encoded}&p=${page}&product_list_limit=36`;
  }

  const res = await fetch(url, { headers: REQUEST_HEADERS, signal: AbortSignal.timeout(15000) });
  if (!res.ok) {
    // MS sometimes returns 404 for valid searches with extra params — log and skip
    throw new Error(`HTTP ${res.status} fetching ${url}`);
  }
  const html = await res.text();
  const $ = cheerio.load(html);

  const products = parseProductsFromHtml(html, baseUrl, source);

  // Detect if there's a next page
  // MS: look for .pages-items a.next or numbered pagination links
  // PLP: standard Magento next button
  const nextBtn = $('a.next, .pages-item-next:not(.disabled), a[title="Next"]').length > 0;
  const hasMore = nextBtn || (page < 2 && products.length >= 30);

  return { products, hasMore };
}

// ─── DB persistence ───────────────────────────────────────────────────────────

/**
 * SC5 helper: Check if the linked inventory_items row has cost_locked = 1.
 * When the supplier_catalog row is joined to an inventory item by SKU or name,
 * a locked item MUST NOT have its cost overwritten on sync. We short-circuit
 * upsertProduct in that case so historical cost stays intact.
 */
function isLinkedInventoryCostLocked(db: any, p: ScrapedProduct): boolean {
  try {
    if (p.sku) {
      const bySku = db.prepare(
        `SELECT cost_locked FROM inventory_items WHERE sku = ? AND is_active = 1 LIMIT 1`
      ).get(p.sku) as { cost_locked?: number } | undefined;
      if (bySku && Number(bySku.cost_locked || 0) === 1) return true;
    }
    const byName = db.prepare(
      `SELECT cost_locked FROM inventory_items
       WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND is_active = 1 LIMIT 1`
    ).get(p.name) as { cost_locked?: number } | undefined;
    if (byName && Number(byName.cost_locked || 0) === 1) return true;
  } catch {
    // Table may not exist in tests / mocks — treat as unlocked.
  }
  return false;
}

/**
 * SC5 helper: Record a supplier_catalog price change into catalog_price_history
 * before overwriting the row. Tolerates the table being absent (older DBs that
 * have not yet run migration 079) by swallowing the insert error.
 */
function recordPriceHistory(
  db: any,
  catalogId: number,
  source: CatalogSource,
  existing: { external_id?: string; sku?: string | null; name?: string | null; price?: number | null },
  newPrice: number,
  changeSource: string,
  jobId: number | null,
): void {
  if (existing.price === newPrice || existing.price == null) return;
  try {
    db.prepare(`
      INSERT INTO catalog_price_history
        (supplier_catalog_id, source, external_id, sku, name, old_price, new_price, change_source, job_id)
      VALUES (?,?,?,?,?,?,?,?,?)
    `).run(
      catalogId, source, existing.external_id || null, existing.sku || null, existing.name || null,
      existing.price, newPrice, changeSource, jobId,
    );
  } catch (err: unknown) {
    logger.warn('catalog_price_history insert failed (migration 079 may be missing)', {
      catalog_id: catalogId,
      error: err instanceof Error ? err.message : String(err),
    });
  }
}

interface UpsertContext {
  changeSource: 'scrape' | 'bulk_import' | 'manual' | 'live_search';
  jobId: number | null;
}

function upsertProduct(
  db: any,
  source: CatalogSource,
  p: ScrapedProduct,
  ctx: UpsertContext = { changeSource: 'scrape', jobId: null },
): number {
  const existing = db.prepare(
    'SELECT id, external_id, sku, name, price FROM supplier_catalog WHERE source = ? AND external_id = ?'
  ).get(source, p.externalId) as { id: number; external_id: string; sku: string | null; name: string; price: number } | undefined;

  let catalogId: number;

  if (existing) {
    // SC5: Respect cost_locked on the downstream inventory item — skip the
    // price portion of the update (but still refresh name/image/compat).
    const locked = isLinkedInventoryCostLocked(db, p);
    const priceToWrite = locked ? existing.price : p.price;
    const comparePriceToWrite = locked ? undefined : p.comparePrice;

    if (!locked && existing.price !== p.price) {
      recordPriceHistory(db, existing.id, source, existing, p.price, ctx.changeSource, ctx.jobId);
    }

    if (locked) {
      db.prepare(`
        UPDATE supplier_catalog
        SET name=?, sku=?, category=?,
            image_url=?, product_url=?, compatible_devices=?,
            in_stock=?, last_synced=datetime('now')
        WHERE id=?
      `).run(
        p.name, p.sku, p.category,
        p.imageUrl, p.productUrl,
        JSON.stringify(p.compatibleDevices),
        p.inStock ? 1 : 0,
        existing.id,
      );
    } else {
      db.prepare(`
        UPDATE supplier_catalog
        SET name=?, sku=?, category=?, price=?, compare_price=?,
            image_url=?, product_url=?, compatible_devices=?,
            in_stock=?, last_synced=datetime('now')
        WHERE id=?
      `).run(
        p.name, p.sku, p.category, priceToWrite, comparePriceToWrite ?? null,
        p.imageUrl, p.productUrl,
        JSON.stringify(p.compatibleDevices),
        p.inStock ? 1 : 0,
        existing.id,
      );
    }
    catalogId = existing.id;
  } else {
    const r = db.prepare(`
      INSERT INTO supplier_catalog
        (source, external_id, name, sku, category, price, compare_price,
         image_url, product_url, compatible_devices, in_stock)
      VALUES (?,?,?,?,?,?,?,?,?,?,?)
    `).run(
      source, p.externalId, p.name, p.sku, p.category, p.price, p.comparePrice,
      p.imageUrl, p.productUrl,
      JSON.stringify(p.compatibleDevices),
      p.inStock ? 1 : 0,
    );
    catalogId = r.lastInsertRowid as number;
  }

  // Link device models
  if (p.compatibleDevices.length > 0) {
    const modelIds = matchDeviceModels(db, p.compatibleDevices);
    if (modelIds.length > 0) {
      db.prepare('DELETE FROM catalog_device_compatibility WHERE supplier_catalog_id = ?').run(catalogId);
      const ins = db.prepare(
        'INSERT OR IGNORE INTO catalog_device_compatibility (supplier_catalog_id, device_model_id) VALUES (?,?)'
      );
      for (const mid of modelIds) ins.run(catalogId, mid);
    }
  }

  return catalogId;
}

// ─── Public: full catalog scrape ─────────────────────────────────────────────

interface ScrapeError {
  query: string;
  page: number;
  message: string;
}

/**
 * Run a full catalog sync for a given source using broad search queries.
 * Runs as a background job — updates scrape_jobs row as it progresses.
 *
 * SC2: Track error count + successful upserts. Final status is:
 *   done             — successful_items > 0 AND errors.length < 50% of attempts
 *   partial_failure  — some successes but too many errors
 *   failed           — zero successful upserts (or hard exception)
 */
export async function scrapeCatalog(
  db: any,
  source: CatalogSource,
  jobId?: number,
): Promise<{ jobId: number; itemsUpserted: number; status: string }> {
  let jid: number = 0;
  if (jobId) {
    jid = jobId;
    db.prepare(`UPDATE scrape_jobs SET status='running', started_at=datetime('now') WHERE id=?`).run(jid);
  } else {
    // SC1: When called directly (cron path in index.ts without a pre-created
    // row), guard SELECT-then-INSERT in a single transaction so two concurrent
    // scheduled runs for the same source can't create parallel jobs. This is
    // belt-and-suspenders with catalog.routes.ts's `POST /sync` guard and with
    // the `idx_scrape_jobs_single_running` partial unique index added in 079.
    try {
      jid = db.transaction(() => {
        const active = db.prepare(
          `SELECT id FROM scrape_jobs WHERE source = ? AND status IN ('pending', 'running') LIMIT 1`
        ).get(source) as { id: number } | undefined;
        if (active) {
          // Reuse the existing pending row instead of failing — the scheduled
          // cron is allowed to pick up an orphaned pending job. But mark it
          // running first to prevent a second iteration of this function from
          // also picking it up.
          const claimed = db.prepare(
            `UPDATE scrape_jobs SET status='running', started_at=datetime('now')
             WHERE id = ? AND status = 'pending'`
          ).run(active.id);
          if (claimed.changes === 0) {
            throw new AppError_ConcurrentScrape(
              `scrapeCatalog concurrency: another job for ${source} is already running (id ${active.id})`,
            );
          }
          return active.id;
        }
        const r = db.prepare(
          `INSERT INTO scrape_jobs (source,status,started_at) VALUES (?,'running',datetime('now'))`
        ).run(source);
        return r.lastInsertRowid as number;
      })();
    } catch (err) {
      // Unique-index violation (idx_scrape_jobs_single_running) from a race
      // where two callers started at the same instant. Treat as "already
      // running" and bail with a non-throwing return so the cron can move on.
      if (err instanceof AppError_ConcurrentScrape || (err instanceof Error && /UNIQUE constraint/i.test(err.message))) {
        logger.warn('scrapeCatalog concurrent-run skipped', { source, error: err.message });
        return { jobId: 0, itemsUpserted: 0, status: 'skipped_concurrent' };
      }
      throw err;
    }
  }

  let totalUpserted = 0;
  let pagesTotal = 0;
  let totalAttempts = 0;
  let successfulItems = 0;
  const errors: ScrapeError[] = [];

  try {
    const seenExternalIds = new Set<string>();

    for (const query of FULL_CATALOG_QUERIES) {
      let page = 1;
      let hasMore = true;

      while (hasMore && page <= 50) { // safety cap 50 pages per query
        totalAttempts++;
        let products: ScrapedProduct[];
        try {
          ({ products, hasMore } = await fetchSearchPage(source, query, page));
        } catch (err: unknown) {
          const message = err instanceof Error ? err.message : String(err);
          logger.warn('scrape page fetch failed', { source, query, page, error: message });
          errors.push({ query, page, message });
          break;
        }

        if (products.length === 0) break;

        // Skip products we've already seen in this job run
        const fresh = products.filter((p) => !seenExternalIds.has(p.externalId));
        fresh.forEach((p) => seenExternalIds.add(p.externalId));

        if (fresh.length > 0) {
          try {
            const batch = db.transaction(() => fresh.forEach((p) =>
              upsertProduct(db, source, p, { changeSource: 'scrape', jobId: jid })
            ));
            batch();
            totalUpserted += fresh.length;
            successfulItems += fresh.length;
          } catch (err: unknown) {
            const message = err instanceof Error ? err.message : String(err);
            logger.error('scrape batch upsert failed', { source, query, page, error: message });
            errors.push({ query, page, message: `upsert: ${message}` });
          }
        }

        pagesTotal++;
        db.prepare(`
          UPDATE scrape_jobs
          SET pages_done=?, items_upserted=?, total_attempts=?, successful_items=?, errors_json=?
          WHERE id=?
        `).run(pagesTotal, totalUpserted, totalAttempts, successfulItems, JSON.stringify(errors.slice(-50)), jid);

        logger.info('scrape progress', {
          source, query, page, items: products.length, fresh: fresh.length, total: totalUpserted,
        });

        page++;
        // Polite delay — don't hammer the server
        await new Promise((r) => setTimeout(r, 800));
      }

      // Delay between queries
      await new Promise((r) => setTimeout(r, 1000));
    }

    // SC2: Decide final status based on success ratio.
    // Accept some failures as long as we got at least 50% success.
    const errorRatio = totalAttempts > 0 ? errors.length / totalAttempts : 1;
    let finalStatus: 'done' | 'partial_failure' | 'failed';
    if (successfulItems === 0) {
      finalStatus = 'failed';
    } else if (errorRatio >= 0.5) {
      finalStatus = 'partial_failure';
    } else {
      finalStatus = 'done';
    }

    const statusError = finalStatus === 'done'
      ? null
      : `status=${finalStatus}: ${successfulItems}/${totalAttempts} attempts succeeded, ${errors.length} errors`;

    db.prepare(`
      UPDATE scrape_jobs
      SET status=?, finished_at=datetime('now'),
          items_upserted=?, total_attempts=?, successful_items=?, errors_json=?, error=?
      WHERE id=?
    `).run(
      finalStatus, totalUpserted, totalAttempts, successfulItems,
      JSON.stringify(errors.slice(-50)), statusError, jid,
    );

    if (finalStatus !== 'done') {
      logger.error('scrape finished with non-success status', {
        source, status: finalStatus, successful_items: successfulItems,
        total_attempts: totalAttempts, error_count: errors.length,
      });
    } else {
      logger.info('scrape finished', { source, items: totalUpserted, attempts: totalAttempts });
    }

    // Auto-sync inventory cost prices from freshly scraped catalog
    // Only do this if we actually got new data — pointless after a failure.
    if (finalStatus !== 'failed') {
      try {
        const { syncCostPricesFromCatalog } = await import('../routes/catalog.routes.js');
        syncCostPricesFromCatalog(db);
      } catch (err: unknown) {
        logger.error('post-scrape cost sync failed', {
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    return { jobId: jid, itemsUpserted: totalUpserted, status: finalStatus };
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err);
    db.prepare(`
      UPDATE scrape_jobs
      SET status='failed', error=?, finished_at=datetime('now'),
          total_attempts=?, successful_items=?, errors_json=?
      WHERE id=?
    `).run(
      message, totalAttempts, successfulItems, JSON.stringify(errors.slice(-50)), jid,
    );
    logger.error('scrape threw unhandled error', { source, error: message });
    throw err;
  }
}

// ─── Public: live search (real-time, first page only) ────────────────────────

/**
 * Fetch and return live search results from the supplier website for a query.
 * Returns first page only (up to ~36 items). Results are also upserted into
 * supplier_catalog so future local searches will find them.
 */
export async function liveSearchSupplier(
  db: any,
  source: CatalogSource,
  query: string,
): Promise<ScrapedProduct[]> {
  const { products } = await fetchSearchPage(source, query, 1);

  if (products.length > 0) {
    const save = db.transaction(() => products.forEach((p) =>
      upsertProduct(db, source, p, { changeSource: 'live_search', jobId: null })
    ));
    save();
  }

  return products;
}

// ─── Public: local catalog search ────────────────────────────────────────────

/** Search the local supplier_catalog with optional filters */
export function searchCatalog(db: any, opts: {
  q?: string;
  source?: string;
  deviceModelId?: number;
  category?: string;
  limit?: number;
  offset?: number;
}) {
  const { q, source, deviceModelId, category, limit = 50, offset = 0 } = opts;
  const conditions: string[] = [];
  const params: unknown[] = [];

  if (source) { conditions.push('sc.source = ?'); params.push(source); }
  if (category) { conditions.push('sc.category = ?'); params.push(category); }
  if (deviceModelId) {
    conditions.push(`sc.id IN (
      SELECT supplier_catalog_id FROM catalog_device_compatibility WHERE device_model_id = ?
    )`);
    params.push(deviceModelId);
  }
  if (q?.trim()) {
    // Try exact SKU match first (for barcode scans), then word-based name+SKU search
    const trimmed = q.trim();
    const words = trimmed.split(/\s+/).filter(Boolean);
    if (words.length === 1) {
      // Single word/token: could be a SKU scan — match exact SKU or partial name/SKU.
      // escapeLike() + ESCAPE '\' stop users from smuggling raw %/_ wildcards.
      conditions.push("(sc.sku = ? OR sc.name LIKE ? ESCAPE '\\' OR sc.sku LIKE ? ESCAPE '\\')");
      params.push(trimmed, `%${escapeLike(trimmed)}%`, `%${escapeLike(trimmed)}%`);
    } else {
      // Multi-word: each word must match in name or SKU
      for (const word of words) {
        conditions.push("(sc.name LIKE ? ESCAPE '\\' OR sc.sku LIKE ? ESCAPE '\\')");
        params.push(`%${escapeLike(word)}%`, `%${escapeLike(word)}%`);
      }
    }
  }

  const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

  const total = (db.prepare(
    `SELECT COUNT(*) as n FROM supplier_catalog sc ${where}`
  ).get(...params) as { n: number }).n;

  const items = db.prepare(`
    SELECT sc.*,
      (SELECT GROUP_CONCAT(dm.name, ', ')
       FROM catalog_device_compatibility cdc
       JOIN device_models dm ON dm.id = cdc.device_model_id
       WHERE cdc.supplier_catalog_id = sc.id
       LIMIT 5) AS matched_models
    FROM supplier_catalog sc
    ${where}
    ORDER BY sc.price ASC, sc.name ASC
    LIMIT ? OFFSET ?
  `).all(...params, limit, offset);

  return { items, total };
}

// ─── Public: combined parts search (inventory first, then catalog) ────────────

/**
 * Unified parts search for ticket part selection.
 * Returns:
 *   - inventory_items where in_stock > 0 (green — available)
 *   - inventory_items where in_stock = 0 (orange — out of stock, we own it)
 *   - supplier_catalog items NOT already in inventory (yellow — not in stock, order from supplier)
 *
 * If local catalog has no results for the query, automatically does a live scrape.
 */
export async function searchPartsUnified(db: any, opts: {
  q: string;
  deviceModelId?: number;
  source?: string;
  liveFallback?: boolean;
}) {
  const { q, deviceModelId, source } = opts;
  const qTrim = q.trim();

  // 1. Search local inventory (fast, always first)
  const invConditions: string[] = ['ii.is_active = 1'];
  const invParams: unknown[] = [];
  if (qTrim) {
    invConditions.push("(ii.name LIKE ? ESCAPE '\\' OR ii.sku LIKE ? ESCAPE '\\' OR ii.sku = ?)");
    invParams.push(`%${escapeLike(qTrim)}%`, `%${escapeLike(qTrim)}%`, qTrim);
  }
  if (deviceModelId) {
    invConditions.push(`ii.id IN (SELECT inventory_item_id FROM inventory_device_compatibility WHERE device_model_id = ?)`);
    invParams.push(deviceModelId);
  }

  const inventoryItems = db.prepare(`
    SELECT ii.id, ii.name, ii.sku, ii.retail_price AS price, ii.cost_price,
           ii.in_stock, ii.item_type, ii.image_url,
           'inventory' AS result_source
    FROM inventory_items ii
    WHERE ${invConditions.join(' AND ')}
    ORDER BY ii.in_stock DESC, ii.name ASC
    LIMIT 50
  `).all(...invParams) as any[];

  // 2. Search local supplier catalog (no live scraping — catalog is synced periodically)
  const { items: catalogItems } = searchCatalog(db, { q: qTrim, source, deviceModelId, limit: 40 });

  // 3. Filter out catalog items already in inventory (by SKU or name)
  const inventorySkus = new Set(inventoryItems.map((i: any) => i.sku).filter(Boolean));
  const inventoryNames = new Set(inventoryItems.map((i: any) => i.name.toLowerCase()));
  const supplierItems = catalogItems.filter((c: any) => {
    if (c.sku && inventorySkus.has(c.sku)) return false;
    if (inventoryNames.has(c.name.toLowerCase())) return false;
    return true;
  });

  // 4. Score supplier items — exact matches or starts-with rank higher
  const qLower = qTrim.toLowerCase();
  const scoredSupplier = supplierItems.map((c: any) => {
    const nameLower = (c.name || '').toLowerCase();
    let score = 0;
    if (nameLower === qLower) score = 100;
    else if (nameLower.startsWith(qLower)) score = 80;
    else if (nameLower.includes(qLower)) score = 60;
    else score = 40;
    return { ...c, _score: score };
  });
  scoredSupplier.sort((a: any, b: any) => b._score - a._score);

  return {
    inventoryItems: inventoryItems.map((i: any) => ({ ...i, availability: i.in_stock > 0 ? 'in_stock' : 'out_of_stock' })),
    supplierItems: scoredSupplier.map((c: any) => {
      const { _score, ...rest } = c;
      return { ...rest, availability: 'supplier_only', result_source: 'catalog' };
    }),
  };
}
