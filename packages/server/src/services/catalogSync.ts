import Database from 'better-sqlite3';
import { config } from '../config.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('catalog-sync');

// SCAN-1077: shape of the rows we actually read — mirrors the
// supplier_catalog table plus the device-compat join rows. Both use unknown
// timestamps/strings in a few columns, so `unknown` is the honest type and
// the insert call does one narrow cast per column.
interface SupplierCatalogRow {
  id: number;
  source: string;
  external_id: string | null;
  sku: string | null;
  name: string;
  price: number | null;
  compare_price: number | null;
  image_url: string | null;
  product_url: string | null;
  category: string | null;
  compatible_devices: string | null;
  in_stock: number | null;
  last_synced: string | null;
  created_at: string | null;
}

interface CompatRow {
  supplier_catalog_id: number;
  device_model_id: number;
}

interface CatalogLookupRow {
  id: number;
  source: string;
  external_id: string | null;
}

/**
 * Copy supplier_catalog rows from template DB to a tenant DB.
 * Uses INSERT OR IGNORE to avoid duplicates (keyed by source + external_id).
 */
export function copyTemplateCatalogToTenant(tenantDb: Database.Database): { copied: number } {
  let copied = 0;
  try {
    const templateDb = new Database(config.templateDbPath, { readonly: true });

    const rows = templateDb.prepare('SELECT * FROM supplier_catalog').all() as SupplierCatalogRow[];
    if (rows.length === 0) {
      templateDb.close();
      return { copied: 0 };
    }

    const insert = tenantDb.prepare(`
      INSERT OR IGNORE INTO supplier_catalog
      (source, external_id, sku, name, price, compare_price, image_url, product_url, category, compatible_devices, in_stock, last_synced, created_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);

    tenantDb.transaction(() => {
      for (const row of rows) {
        const result = insert.run(
          row.source, row.external_id, row.sku, row.name, row.price, row.compare_price,
          row.image_url, row.product_url, row.category, row.compatible_devices,
          row.in_stock, row.last_synced, row.created_at
        );
        if (result.changes > 0) copied++;
      }
    })();

    // Also copy device compatibility links
    const compatRows = templateDb.prepare('SELECT * FROM catalog_device_compatibility').all() as CompatRow[];
    if (compatRows.length > 0) {
      // We need to map template catalog IDs to tenant catalog IDs
      // Since we used INSERT OR IGNORE, the tenant IDs may differ from template IDs
      // Use (source, external_id) as the join key
      const templateCatalogLookup = templateDb.prepare('SELECT id, source, external_id FROM supplier_catalog WHERE id = ?');

      tenantDb.transaction(() => {
        for (const cr of compatRows) {
          const templateItem = templateCatalogLookup.get(cr.supplier_catalog_id) as CatalogLookupRow | undefined;
          if (templateItem) {
            try {
              tenantDb.prepare(`
                INSERT OR IGNORE INTO catalog_device_compatibility (supplier_catalog_id, device_model_id)
                SELECT sc.id, ? FROM supplier_catalog sc WHERE sc.source = ? AND sc.external_id = ?
              `).run(cr.device_model_id, templateItem.source, templateItem.external_id);
            } catch { /* skip incompatible rows */ }
          }
        }
      })();
    }

    templateDb.close();
    logger.info('copied catalog items from template', { copied });
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    logger.warn('copy from template failed', { error: msg });
  }
  return { copied };
}

/**
 * Check if template DB has a populated catalog. If not, it needs scraping.
 */
export function getTemplateCatalogCount(): number {
  try {
    const templateDb = new Database(config.templateDbPath, { readonly: true });
    const row = templateDb.prepare('SELECT COUNT(*) as c FROM supplier_catalog').get() as { c: number } | undefined;
    templateDb.close();
    return row?.c ?? 0;
  } catch {
    return 0;
  }
}
