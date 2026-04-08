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
 * Parse Magento 2 product listing HTML → ScrapedProduct[].
 *
 * We try multiple selector patterns because themes vary between MS and PLP.
 * If nothing matches we return an empty array — the caller simply moves on.
 */
export function parseProductsFromHtml(html: string, baseUrl: string): ScrapedProduct[] {
  const $ = cheerio.load(html);
  const products: ScrapedProduct[] = [];

  // Try Magento 2 standard selectors first, then Mobilesentrix custom theme.
  // Standard Magento 2: <li class="item product product-item">
  // Mobilesentrix: <li class="item "> inside .category-products / .products-grid
  let $items = $('.product-item, .item.product, [data-product-id]');
  const isMobilesentrixTheme = $items.length === 0 && $('li.item').length > 0 && $('.products-grid, .category-products').length > 0;
  if (isMobilesentrixTheme) {
    // Mobilesentrix uses plain li.item inside a .products-grid or .category-products container
    $items = $('.products-grid li.item, .category-products li.item');
  }

  if ($items.length === 0) return products;

  $items.each((_i, el) => {
    const $el = $(el);

    // Name — try several selectors in priority order:
    //   Standard Magento 2: .product-item-link
    //   Mobilesentrix custom: h2.product-name (text directly inside, NOT inside an <a>)
    let nameEl = $el.find('.product-item-link, .product-item-name a, .product.name a').first();
    let name = nameEl.text().trim();

    // Mobilesentrix fallback: h2.product-name contains text directly
    if (!name) {
      nameEl = $el.find('h2.product-name, .product-name');
      name = nameEl.first().text().trim();
    }
    if (!name) return; // skip malformed items

    // Product URL — try standard selectors then Mobilesentrix's a.product-image
    let href = nameEl.attr('href')
      || $el.find('a.product-item-link, a.product-item-photo').first().attr('href')
      || $el.find('a.product-image').first().attr('href')
      || $el.find('a[href]').first().attr('href')
      || '';
    const productUrl = href.startsWith('http') ? href : `${baseUrl}${href}`;

    // Extract Magento product ID from data attributes on the item, its forms, or child elements.
    // Magento 2 typically puts data-product-id on the <form> inside the product card,
    // or on a <div class="price-box">, or on the <li> item itself.
    const dataId = $el.attr('data-product-id')
      || $el.find('[data-product-id]').first().attr('data-product-id')
      || $el.find('form[data-product-id]').first().attr('data-product-id')
      || $el.find('.price-box[data-product-id]').first().attr('data-product-id')
      || $el.find('input[name="product"]').first().attr('value')  // hidden form field
      || null;
    const urlSlug = productUrl.split('/').filter(Boolean).pop()?.split('?')[0] || '';
    const externalId = dataId || urlSlug || name.toLowerCase().replace(/\s+/g, '-').substring(0, 80);

    // Price — prefer data-price-amount attribute (reliable), fall back to text
    const priceAttr = $el.find('[data-price-amount]').first().attr('data-price-amount');
    const priceText = $el.find('.price').first().text().replace(/[^0-9.]/g, '');
    const price = parseFloat(priceAttr || priceText || '0') || 0;

    const comparePriceAttr = $el.find('[data-price-type="oldPrice"] [data-price-amount]').first().attr('data-price-amount');
    const comparePrice = comparePriceAttr ? parseFloat(comparePriceAttr) || null : null;

    // Image — try multiple patterns:
    //   Standard Magento 2: .product-image-photo
    //   Mobilesentrix: img.small-img / img.lazyimage with data-original attr
    const imgEl = $el.find('.product-image-photo, img.small-img, img.lazyimage, img.product-image, img[loading]').first();
    let imageUrl = imgEl.attr('data-original') || imgEl.attr('data-src') || imgEl.attr('src') || null;
    // Skip badge images (small brand logos) — they're typically in /wysiwyg/ path
    if (imageUrl && imageUrl.includes('/wysiwyg/')) {
      // Try next img instead
      const altImg = $el.find('img.small-img, img.lazyimage, .product-image-photo').first();
      imageUrl = altImg.attr('data-original') || altImg.attr('data-src') || altImg.attr('src') || null;
    }
    if (imageUrl && imageUrl.startsWith('//')) imageUrl = `https:${imageUrl}`;
    if (imageUrl && imageUrl.startsWith('/') && !imageUrl.startsWith('//')) imageUrl = `${baseUrl}${imageUrl}`;

    // SKU — PLP puts data-sku on the <form> element itself; also check child spans
    const skuFromAttr = $el.attr('data-sku')?.trim()
      || $el.find('[data-sku]').attr('data-sku')?.trim()
      || null;
    const skuEl = $el.find('.sku .value, .product-sku').first();
    const sku = skuFromAttr || skuEl.text().trim() || null;

    // Stock indicator
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

  const res = await fetch(url, { headers: REQUEST_HEADERS });
  if (!res.ok) {
    // MS sometimes returns 404 for valid searches with extra params — log and skip
    throw new Error(`HTTP ${res.status} fetching ${url}`);
  }
  const html = await res.text();
  const $ = cheerio.load(html);

  const products = parseProductsFromHtml(html, baseUrl);

  // Detect if there's a next page
  // MS: look for .pages-items a.next or numbered pagination links
  // PLP: standard Magento next button
  const nextBtn = $('a.next, .pages-item-next:not(.disabled), a[title="Next"]').length > 0;
  const hasMore = nextBtn || (page < 2 && products.length >= 30);

  return { products, hasMore };
}

// ─── DB persistence ───────────────────────────────────────────────────────────

function upsertProduct(db: any, source: CatalogSource, p: ScrapedProduct): number {
  const existing = db.prepare(
    'SELECT id FROM supplier_catalog WHERE source = ? AND external_id = ?'
  ).get(source, p.externalId) as { id: number } | undefined;

  let catalogId: number;

  if (existing) {
    db.prepare(`
      UPDATE supplier_catalog
      SET name=?, sku=?, category=?, price=?, compare_price=?,
          image_url=?, product_url=?, compatible_devices=?,
          in_stock=?, last_synced=datetime('now')
      WHERE id=?
    `).run(
      p.name, p.sku, p.category, p.price, p.comparePrice,
      p.imageUrl, p.productUrl,
      JSON.stringify(p.compatibleDevices),
      p.inStock ? 1 : 0,
      existing.id,
    );
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

/**
 * Run a full catalog sync for a given source using broad search queries.
 * Runs as a background job — updates scrape_jobs row as it progresses.
 */
export async function scrapeCatalog(
  db: any,
  source: CatalogSource,
  jobId?: number,
): Promise<{ jobId: number; itemsUpserted: number }> {
  let jid: number;
  if (jobId) {
    jid = jobId;
    db.prepare(`UPDATE scrape_jobs SET status='running', started_at=datetime('now') WHERE id=?`).run(jid);
  } else {
    const r = db.prepare(`INSERT INTO scrape_jobs (source,status,started_at) VALUES (?,'running',datetime('now'))`).run(source);
    jid = r.lastInsertRowid as number;
  }

  let totalUpserted = 0;
  let pagesTotal = 0;

  try {
    const seenExternalIds = new Set<string>();

    for (const query of FULL_CATALOG_QUERIES) {
      let page = 1;
      let hasMore = true;

      while (hasMore && page <= 50) { // safety cap 50 pages per query
        let products: ScrapedProduct[];
        try {
          ({ products, hasMore } = await fetchSearchPage(source, query, page));
        } catch (err: any) {
          console.warn(`[catalog:${source}] query "${query}" page ${page} failed: ${err.message}`);
          break;
        }

        if (products.length === 0) break;

        // Skip products we've already seen in this job run
        const fresh = products.filter((p) => !seenExternalIds.has(p.externalId));
        fresh.forEach((p) => seenExternalIds.add(p.externalId));

        if (fresh.length > 0) {
          const batch = db.transaction(() => fresh.forEach((p) => upsertProduct(db, source, p)));
          batch();
          totalUpserted += fresh.length;
        }

        pagesTotal++;
        db.prepare(`UPDATE scrape_jobs SET pages_done=?,items_upserted=? WHERE id=?`)
          .run(pagesTotal, totalUpserted, jid);

        console.log(`[catalog:${source}] "${query}" p${page} → ${products.length} items (${fresh.length} new, total: ${totalUpserted})`);

        page++;
        // Polite delay — don't hammer the server
        await new Promise((r) => setTimeout(r, 800));
      }

      // Delay between queries
      await new Promise((r) => setTimeout(r, 1000));
    }

    db.prepare(`UPDATE scrape_jobs SET status='done',finished_at=datetime('now'),items_upserted=? WHERE id=?`)
      .run(totalUpserted, jid);

    // Auto-sync inventory cost prices from freshly scraped catalog
    try {
      const { syncCostPricesFromCatalog } = await import('../routes/catalog.routes.js');
      syncCostPricesFromCatalog(db);
    } catch (e) { console.error('[CatalogSync] Post-scrape sync failed:', e); }

    return { jobId: jid, itemsUpserted: totalUpserted };
  } catch (err: any) {
    db.prepare(`UPDATE scrape_jobs SET status='failed',error=?,finished_at=datetime('now') WHERE id=?`)
      .run(err.message || String(err), jid);
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
    const save = db.transaction(() => products.forEach((p) => upsertProduct(db, source, p)));
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
      // Single word/token: could be a SKU scan — match exact SKU or partial name/SKU
      conditions.push(`(sc.sku = ? OR sc.name LIKE ? OR sc.sku LIKE ?)`);
      params.push(trimmed, `%${trimmed}%`, `%${trimmed}%`);
    } else {
      // Multi-word: each word must match in name or SKU
      for (const word of words) {
        conditions.push(`(sc.name LIKE ? OR sc.sku LIKE ?)`);
        params.push(`%${word}%`, `%${word}%`);
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
  if (qTrim) { invConditions.push(`(ii.name LIKE ? OR ii.sku LIKE ? OR ii.sku = ?)`); invParams.push(`%${qTrim}%`, `%${qTrim}%`, qTrim); }
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
