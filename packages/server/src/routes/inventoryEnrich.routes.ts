/**
 * Inventory enrichment routes — bundles the §48 enrichment features that
 * don't belong in the main inventory.routes.ts (which is owned by the
 * inventory agent). All endpoints here are mounted at /api/v1/inventory-enrich
 * EXCEPT the auto-reorder rule CRUD which is intentionally exposed on the
 * inventory namespace (see note in index.ts).
 *
 * Covers:
 *   - Bin locations (CRUD + heatmap + assignment)
 *   - Auto-reorder rules (CRUD) — surfaces the hidden endpoint
 *   - Serialized parts (create/list/update)
 *   - Shrinkage log
 *   - ABC analysis / dead-stock report
 *   - Age report
 *   - Supplier price comparison
 *   - Returns to supplier
 *   - Parts compatibility (bulk)
 *   - Label print job (ZPL)
 *
 * Cross-ref: criticalaudit.md §48.
 */
import { Router } from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs';
import crypto from 'crypto';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { qs } from '../utils/query.js';
import {
  validateIntegerQuantity,
  validatePrice,
  validateTextLength,
  validateEnum,
  validateArrayBounds,
} from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import { config } from '../config.js';
import { fileUploadValidator, releaseFileCount } from '../middleware/fileUploadValidator.js';
import { enforceUploadQuota } from '../middleware/uploadQuota.js';
import { reserveStorage } from '../services/usageTracker.js';
import type { AsyncDb } from '../db/async-db.js';

const logger = createLogger('inventory-enrich');
const router = Router();

// SEC (post-enrichment audit §6): manager/admin gate used on endpoints that
// can cost real money (auto-reorder rules, supplier returns, shrinkage).
// bin-locations + serials remain tech-writable per the audit scope.
function requireManagerOrAdmin(req: any): void {
  const role = req?.user?.role;
  if (role !== 'admin' && role !== 'manager') {
    throw new AppError('Admin or manager role required', 403);
  }
}

// Shrinkage photo upload — tenant-scoped /uploads/<tenant>/shrinkage.
//
// SEC (post-enrichment §13, F1-F4): the multer config is the FAST path
// (header-MIME filter, extension sanity check, 5MB cap, 1-file cap). The
// actual content validation (magic bytes + virus scan + per-tenant file
// count quota) is done by the fileUploadValidator middleware that this
// route mounts below. Per-tenant BYTE quota is enforced in the handler
// via reserveStorage after the middleware has passed.
const SHRINKAGE_MIMES = ['image/jpeg', 'image/png', 'image/webp'] as const;
const SHRINKAGE_EXTENSIONS = new Set(['.jpg', '.jpeg', '.png', '.webp']);

function shrinkageUploadDir(req: any): string {
  const tenantSlug = req.tenantSlug;
  return tenantSlug
    ? path.join(config.uploadsPath, tenantSlug, 'shrinkage')
    : path.join(config.uploadsPath, 'shrinkage');
}

const shrinkagePhotoUpload = multer({
  storage: multer.diskStorage({
    destination: (req: any, _file, cb) => {
      const dest = shrinkageUploadDir(req);
      if (!fs.existsSync(dest)) fs.mkdirSync(dest, { recursive: true });
      cb(null, dest);
    },
    filename: (_req, file, cb) => {
      const ext = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '');
      if (!ext || !SHRINKAGE_EXTENSIONS.has(ext)) {
        cb(new Error('Unsupported image extension'), '');
        return;
      }
      cb(null, `${crypto.randomBytes(16).toString('hex')}${ext}`);
    },
  }),
  limits: {
    fileSize: 5 * 1024 * 1024, // 5 MB
    files: 1, // shrinkage: single photo only
  },
  fileFilter: (_req, file, cb) => {
    if ((SHRINKAGE_MIMES as readonly string[]).includes(file.mimetype)) cb(null, true);
    else cb(new Error('Only JPEG/PNG/WebP allowed for shrinkage photos'));
  },
});

// ============================================================================
// BIN LOCATIONS
// ============================================================================

interface BinLocationRow {
  id: number;
  code: string;
  description: string | null;
  aisle: string | null;
  shelf: string | null;
  bin: string | null;
  is_active: number;
}

router.get(
  '/bin-locations',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const rows = await adb.all<BinLocationRow>(
      `SELECT * FROM bin_locations WHERE is_active = 1 ORDER BY code`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/bin-locations',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const code = validateTextLength(req.body?.code, 40, 'code');
    if (!code) throw new AppError('code is required', 400);
    const description = req.body?.description
      ? validateTextLength(req.body.description, 200, 'description')
      : null;
    const aisle = req.body?.aisle
      ? validateTextLength(req.body.aisle, 20, 'aisle')
      : null;
    const shelf = req.body?.shelf
      ? validateTextLength(req.body.shelf, 20, 'shelf')
      : null;
    const bin = req.body?.bin
      ? validateTextLength(req.body.bin, 20, 'bin')
      : null;

    try {
      const result = await adb.run(
        `INSERT INTO bin_locations (code, description, aisle, shelf, bin)
         VALUES (?, ?, ?, ?, ?)`,
        code,
        description,
        aisle,
        shelf,
        bin,
      );
      audit(req.db, 'bin_location_created', req.user!.id, req.ip || 'unknown', {
        id: Number(result.lastInsertRowid),
        code,
      });
      const row = await adb.get<BinLocationRow>(
        'SELECT * FROM bin_locations WHERE id = ?',
        result.lastInsertRowid,
      );
      res.json({ success: true, data: row });
    } catch (err: any) {
      if (String(err?.message || '').includes('UNIQUE')) {
        throw new AppError(`Bin code '${code}' already exists`, 409);
      }
      throw err;
    }
  }),
);

router.put(
  '/bin-locations/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid bin id', 400);
    const description = req.body?.description
      ? validateTextLength(req.body.description, 200, 'description')
      : null;
    const aisle = req.body?.aisle
      ? validateTextLength(req.body.aisle, 20, 'aisle')
      : null;
    const shelf = req.body?.shelf
      ? validateTextLength(req.body.shelf, 20, 'shelf')
      : null;
    const bin = req.body?.bin
      ? validateTextLength(req.body.bin, 20, 'bin')
      : null;
    await adb.run(
      `UPDATE bin_locations SET description = ?, aisle = ?, shelf = ?, bin = ? WHERE id = ?`,
      description,
      aisle,
      shelf,
      bin,
      id,
    );
    audit(req.db, 'bin_location_updated', req.user!.id, req.ip || 'unknown', { id });
    const row = await adb.get<BinLocationRow>(
      'SELECT * FROM bin_locations WHERE id = ?',
      id,
    );
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/bin-locations/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid bin id', 400);
    await adb.run(`UPDATE bin_locations SET is_active = 0 WHERE id = ?`, id);
    audit(req.db, 'bin_location_deleted', req.user!.id, req.ip || 'unknown', { id });
    res.json({ success: true, data: { id } });
  }),
);

/**
 * GET /bin-locations/heatmap — aggregated pick-activity per bin.
 *
 * "Hot" = a bin that ships a lot of items to POS/invoices. We measure this
 * by counting stock_movements with a negative quantity (outbound) and
 * grouping by bin_location via the inventory_bin_assignments junction.
 *
 * Window defaults to 90 days; caller can override with ?days=N.
 */
router.get(
  '/bin-locations/heatmap',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const days = Math.max(
      1,
      Math.min(365, parseInt(String(req.query.days || '90'), 10) || 90),
    );

    const rows = await adb.all<{
      bin_id: number;
      code: string;
      picks: number;
      items_tracked: number;
      aisle: string | null;
      shelf: string | null;
    }>(
      `SELECT
         b.id as bin_id,
         b.code,
         b.aisle,
         b.shelf,
         COUNT(DISTINCT iba.inventory_item_id) as items_tracked,
         COALESCE(
           (SELECT SUM(ABS(sm.quantity))
            FROM stock_movements sm
            WHERE sm.inventory_item_id IN (
              SELECT iba2.inventory_item_id
              FROM inventory_bin_assignments iba2
              WHERE iba2.bin_location_id = b.id
            )
              AND sm.quantity < 0
              AND sm.created_at >= datetime('now', '-' || ? || ' days')),
           0
         ) as picks
       FROM bin_locations b
       LEFT JOIN inventory_bin_assignments iba ON iba.bin_location_id = b.id
       WHERE b.is_active = 1
       GROUP BY b.id
       ORDER BY picks DESC`,
      days,
    );

    // Compute heat ratio 0..1 so the UI can color-map without re-scanning.
    const maxPicks = rows.reduce((m, r) => Math.max(m, r.picks || 0), 0);
    const withHeat = rows.map((r) => ({
      ...r,
      heat: maxPicks > 0 ? (r.picks || 0) / maxPicks : 0,
    }));

    // Suggest re-layout: bins with heat > 0.6 should be closest to the bench.
    const suggestions = withHeat
      .filter((r) => r.heat > 0.6)
      .map((r) => ({
        bin_code: r.code,
        reason: 'high_pick_volume',
        picks: r.picks,
        recommendation: 'move_closer_to_bench',
      }));

    res.json({
      success: true,
      data: {
        window_days: days,
        bins: withHeat,
        suggestions,
        max_picks: maxPicks,
      },
    });
  }),
);

// POST /inventory/:id/assign-bin — mounted at /inventory-enrich/assign-bin/:id
// for namespace clarity. Body: { bin_location_id: number | null }
router.post(
  '/assign-bin/:id',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const inventoryItemId = parseInt(qs(req.params.id), 10);
    if (!inventoryItemId || isNaN(inventoryItemId)) {
      throw new AppError('Invalid inventory item id', 400);
    }
    const binId = req.body?.bin_location_id;

    if (binId === null || binId === undefined) {
      await adb.run(
        `DELETE FROM inventory_bin_assignments WHERE inventory_item_id = ?`,
        inventoryItemId,
      );
      audit(req.db, 'inventory_bin_unassigned', req.user!.id, req.ip || 'unknown', {
        inventory_item_id: inventoryItemId,
      });
      res.json({ success: true, data: { inventory_item_id: inventoryItemId, bin_location_id: null } });
      return;
    }

    const parsedBinId = parseInt(String(binId), 10);
    if (!parsedBinId || isNaN(parsedBinId)) {
      throw new AppError('Invalid bin_location_id', 400);
    }

    const bin = await adb.get<BinLocationRow>(
      'SELECT id FROM bin_locations WHERE id = ? AND is_active = 1',
      parsedBinId,
    );
    if (!bin) throw new AppError('Bin location not found', 404);

    await adb.run(
      `INSERT INTO inventory_bin_assignments (inventory_item_id, bin_location_id)
       VALUES (?, ?)
       ON CONFLICT(inventory_item_id) DO UPDATE SET
         bin_location_id = excluded.bin_location_id,
         assigned_at = datetime('now')`,
      inventoryItemId,
      parsedBinId,
    );
    audit(req.db, 'inventory_bin_assigned', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: inventoryItemId,
      bin_location_id: parsedBinId,
    });
    res.json({
      success: true,
      data: { inventory_item_id: inventoryItemId, bin_location_id: parsedBinId },
    });
  }),
);

// ============================================================================
// AUTO-REORDER RULES — surfaces the hidden endpoint
// ============================================================================

interface AutoReorderRow {
  inventory_item_id: number;
  min_qty: number;
  reorder_qty: number;
  preferred_supplier_id: number | null;
  lead_time_days: number | null;
  is_enabled: number;
  updated_at: string;
}

router.get(
  '/auto-reorder-rules',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const rows = await adb.all<AutoReorderRow & { name: string; sku: string | null; in_stock: number; supplier_name: string | null }>(
      `SELECT r.*, i.name, i.sku, i.in_stock, s.name as supplier_name
       FROM inventory_auto_reorder_rules r
       JOIN inventory_items i ON i.id = r.inventory_item_id
       LEFT JOIN suppliers s ON s.id = r.preferred_supplier_id
       WHERE i.is_active = 1
       ORDER BY i.name`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/auto-reorder-rules',
  asyncHandler(async (req, res) => {
    // Auto-reorder can trigger real purchase orders — manager/admin only.
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const inventoryItemId = validateIntegerQuantity(
      req.body?.inventory_item_id,
      'inventory_item_id',
    );
    const minQty = validateIntegerQuantity(req.body?.min_qty, 'min_qty');
    const reorderQty = validateIntegerQuantity(req.body?.reorder_qty, 'reorder_qty');
    // preferred_supplier_id and lead_time_days are optional; when supplied,
    // they must be real finite integers — parseInt("foo") otherwise poisons
    // the DB with NaN.
    let preferredSupplierId: number | null = null;
    if (req.body?.preferred_supplier_id !== undefined && req.body?.preferred_supplier_id !== null) {
      preferredSupplierId = validateIntegerQuantity(
        req.body.preferred_supplier_id,
        'preferred_supplier_id',
      );
      const supplier = await adb.get(
        'SELECT id FROM suppliers WHERE id = ?',
        preferredSupplierId,
      );
      if (!supplier) throw new AppError('Supplier not found', 404);
    }
    let leadTimeDays: number | null = null;
    if (req.body?.lead_time_days !== undefined && req.body?.lead_time_days !== null) {
      leadTimeDays = validateIntegerQuantity(req.body.lead_time_days, 'lead_time_days');
    }
    const isEnabled = req.body?.is_enabled === false ? 0 : 1;

    const item = await adb.get(
      'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      inventoryItemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    await adb.run(
      `INSERT INTO inventory_auto_reorder_rules
         (inventory_item_id, min_qty, reorder_qty, preferred_supplier_id, lead_time_days, is_enabled, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(inventory_item_id) DO UPDATE SET
         min_qty = excluded.min_qty,
         reorder_qty = excluded.reorder_qty,
         preferred_supplier_id = excluded.preferred_supplier_id,
         lead_time_days = excluded.lead_time_days,
         is_enabled = excluded.is_enabled,
         updated_at = datetime('now')`,
      inventoryItemId,
      minQty,
      reorderQty,
      preferredSupplierId,
      leadTimeDays,
      isEnabled,
    );

    audit(req.db, 'auto_reorder_rule_upserted', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: inventoryItemId,
      min_qty: minQty,
      reorder_qty: reorderQty,
    });

    const row = await adb.get(
      'SELECT * FROM inventory_auto_reorder_rules WHERE inventory_item_id = ?',
      inventoryItemId,
    );
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/auto-reorder-rules/:itemId',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.itemId), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    await adb.run(
      `DELETE FROM inventory_auto_reorder_rules WHERE inventory_item_id = ?`,
      itemId,
    );
    audit(req.db, 'auto_reorder_rule_deleted', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: itemId,
    });
    res.json({ success: true, data: { inventory_item_id: itemId } });
  }),
);

// ============================================================================
// SERIALIZED PARTS
// ============================================================================

router.get(
  '/:id/serials',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    const status = req.query.status
      ? validateEnum(
          req.query.status,
          ['in_stock', 'sold', 'returned', 'defective', 'rma'] as const,
          'status',
          false,
        )
      : null;
    let where = 'WHERE inventory_item_id = ?';
    const params: any[] = [itemId];
    if (status) {
      where += ' AND status = ?';
      params.push(status);
    }
    const rows = await adb.all(
      `SELECT * FROM inventory_serial_numbers ${where} ORDER BY received_at DESC`,
      ...params,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/:id/serials',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);

    const serialsInput = Array.isArray(req.body?.serials)
      ? validateArrayBounds<unknown>(req.body.serials, 'serials', 1000)
      : [req.body?.serial_number];
    const serials = serialsInput
      .map((s: unknown) => (typeof s === 'string' ? s.trim() : ''))
      .filter((s: string) => s.length > 0 && s.length <= 120);
    if (serials.length === 0) {
      throw new AppError('At least one serial_number is required', 400);
    }

    const item = await adb.get(
      'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      itemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    const db = req.db;
    const inserted: string[] = [];
    const duplicates: string[] = [];

    const insertTx = db.transaction(() => {
      const stmt = db.prepare(
        `INSERT INTO inventory_serial_numbers (inventory_item_id, serial_number)
         VALUES (?, ?)`,
      );
      for (const s of serials) {
        try {
          stmt.run(itemId, s);
          inserted.push(s);
        } catch (err: any) {
          if (String(err?.message || '').includes('UNIQUE')) {
            duplicates.push(s);
          } else {
            throw err;
          }
        }
      }
    });
    insertTx();

    audit(req.db, 'serials_added', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: itemId,
      inserted_count: inserted.length,
      duplicate_count: duplicates.length,
    });

    res.json({
      success: true,
      data: { inserted, duplicates, count: inserted.length },
    });
  }),
);

router.put(
  '/serials/:serialId',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const serialId = parseInt(qs(req.params.serialId), 10);
    if (!serialId || isNaN(serialId)) throw new AppError('Invalid serial id', 400);
    const status = validateEnum(
      req.body?.status,
      ['in_stock', 'sold', 'returned', 'defective', 'rma'] as const,
      'status',
      true,
    )!;
    const notes = req.body?.notes
      ? validateTextLength(req.body.notes, 500, 'notes')
      : null;
    await adb.run(
      `UPDATE inventory_serial_numbers
       SET status = ?, notes = COALESCE(?, notes),
           sold_at = CASE WHEN ? = 'sold' AND sold_at IS NULL THEN datetime('now') ELSE sold_at END
       WHERE id = ?`,
      status,
      notes,
      status,
      serialId,
    );
    const row = await adb.get(
      'SELECT * FROM inventory_serial_numbers WHERE id = ?',
      serialId,
    );
    audit(req.db, 'serial_status_changed', req.user!.id, req.ip || 'unknown', {
      serial_id: serialId,
      status,
    });
    res.json({ success: true, data: row });
  }),
);

// ============================================================================
// SHRINKAGE LOG
// ============================================================================

router.get(
  '/shrinkage',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const rows = await adb.all(
      `SELECT s.*, i.name, i.sku
       FROM inventory_shrinkage s
       JOIN inventory_items i ON i.id = s.inventory_item_id
       ORDER BY s.reported_at DESC
       LIMIT 500`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/:id/shrinkage',
  enforceUploadQuota,
  shrinkagePhotoUpload.single('photo'),
  fileUploadValidator({
    allowedMimes: SHRINKAGE_MIMES,
    getTenantDir: (r) => shrinkageUploadDir(r),
  }),
  asyncHandler(async (req, res) => {
    // Shrinkage writes a negative stock movement — manager/admin only.
    requireManagerOrAdmin(req);
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    const quantity = validateIntegerQuantity(req.body?.quantity, 'quantity');
    const reason = validateEnum(
      req.body?.reason,
      ['damaged', 'stolen', 'lost', 'expired', 'other'] as const,
      'reason',
      true,
    )!;
    const notes = req.body?.notes
      ? validateTextLength(req.body.notes, 1000, 'notes')
      : null;

    // SEC (§13): reserve BYTE quota if a photo was attached. On failure
    // unlink the uploaded file AND roll back the file-count bump that
    // fileUploadValidator already applied.
    const photoFile = (req as any).file as Express.Multer.File | undefined;
    if (photoFile) {
      const bytes = photoFile.size ?? 0;
      if (
        !reserveStorage(
          (req as any).tenantId,
          bytes,
          (req as any).tenantLimits?.storageLimitMb ?? null,
        )
      ) {
        try { fs.unlinkSync(photoFile.path); } catch { /* ignore */ }
        releaseFileCount(req, 1);
        res.status(403).json({
          success: false,
          upgrade_required: true,
          feature: 'storage_limit',
          message: `Storage limit (${(req as any).tenantLimits?.storageLimitMb} MB) reached. Upgrade to Pro for more storage.`,
        });
        return;
      }
    }

    // Tenant slug is always set for the URL — the static /uploads route
    // cross-checks request tenantSlug against the directory prefix. If we
    // ever stored without a slug in single-tenant dev mode, the URL points
    // to the flat /uploads/shrinkage/ directory instead.
    const tenantSlug = (req as any).tenantSlug;
    const photoPath = photoFile
      ? tenantSlug
        ? `/uploads/${tenantSlug}/shrinkage/${photoFile.filename}`
        : `/uploads/shrinkage/${photoFile.filename}`
      : null;

    const db = req.db;
    const tx = db.transaction(() => {
      const item = db
        .prepare('SELECT in_stock FROM inventory_items WHERE id = ? AND is_active = 1')
        .get(itemId) as { in_stock: number } | undefined;
      if (!item) throw new AppError('Inventory item not found', 404);

      // Guarded decrement — never go negative.
      const upd = db
        .prepare(
          `UPDATE inventory_items
           SET in_stock = in_stock - ?, updated_at = datetime('now')
           WHERE id = ? AND in_stock >= ?`,
        )
        .run(quantity, itemId, quantity);
      if (upd.changes === 0) {
        throw new AppError(
          `Cannot record shrinkage of ${quantity} — only ${item.in_stock} in stock`,
          400,
        );
      }

      const result = db
        .prepare(
          `INSERT INTO inventory_shrinkage
             (inventory_item_id, quantity, reason, photo_path, reported_by_user_id, notes)
           VALUES (?, ?, ?, ?, ?, ?)`,
        )
        .run(itemId, quantity, reason, photoPath, req.user!.id, notes);

      db.prepare(
        `INSERT INTO stock_movements
           (inventory_item_id, type, quantity, reference_type, reference_id, notes, user_id)
         VALUES (?, 'shrinkage', ?, 'shrinkage', ?, ?, ?)`,
      ).run(itemId, -quantity, Number(result.lastInsertRowid), `Shrinkage: ${reason}`, req.user!.id);

      return Number(result.lastInsertRowid);
    });

    const shrinkageId = tx();
    audit(req.db, 'shrinkage_recorded', req.user!.id, req.ip || 'unknown', {
      shrinkage_id: shrinkageId,
      inventory_item_id: itemId,
      quantity,
      reason,
    });
    res.json({
      success: true,
      data: {
        id: shrinkageId,
        inventory_item_id: itemId,
        quantity,
        reason,
        photo_path: photoPath,
      },
    });
  }),
);

// ============================================================================
// ABC ANALYSIS — top sellers vs dead stock
// ============================================================================

router.get(
  '/abc-analysis',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const days = Math.max(
      30,
      Math.min(365, parseInt(String(req.query.days || '180'), 10) || 180),
    );

    // Pull revenue per item over the window from stock_movements outbound.
    // retail_price and cost_price are REAL columns — we ROUND every
    // multiplication at the SQL boundary so ABC classes are consistent
    // across runs. `CAST(... AS INTEGER)` alone truncates toward zero and
    // would let a $9.999 price read as 999 cents instead of 1000.
    const rows = await adb.all<{
      id: number;
      name: string;
      sku: string | null;
      in_stock: number;
      cost_price: number;
      retail_price: number;
      units_sold: number;
      revenue_cents: number;
      last_sold_at: string | null;
    }>(
      `SELECT
         i.id,
         i.name,
         i.sku,
         i.in_stock,
         i.cost_price,
         i.retail_price,
         COALESCE(ABS(SUM(CASE WHEN sm.quantity < 0 THEN sm.quantity ELSE 0 END)), 0) as units_sold,
         COALESCE(
           CAST(ROUND(ABS(SUM(CASE WHEN sm.quantity < 0 THEN sm.quantity ELSE 0 END)) * i.retail_price * 100) AS INTEGER),
           0
         ) as revenue_cents,
         MAX(CASE WHEN sm.quantity < 0 THEN sm.created_at ELSE NULL END) as last_sold_at
       FROM inventory_items i
       LEFT JOIN stock_movements sm
         ON sm.inventory_item_id = i.id
        AND sm.created_at >= datetime('now', '-' || ? || ' days')
       WHERE i.is_active = 1 AND i.item_type != 'service'
       GROUP BY i.id
       ORDER BY revenue_cents DESC`,
      days,
    );

    // Assign A/B/C classes using the 80/15/5 rule on cumulative revenue.
    const totalRev = rows.reduce((s, r) => s + r.revenue_cents, 0);
    let running = 0;
    const classified = rows.map((r) => {
      running += r.revenue_cents;
      const pct = totalRev > 0 ? running / totalRev : 0;
      let abc_class: 'A' | 'B' | 'C' | 'DEAD';
      if (r.units_sold === 0) abc_class = 'DEAD';
      else if (pct <= 0.8) abc_class = 'A';
      else if (pct <= 0.95) abc_class = 'B';
      else abc_class = 'C';
      return { ...r, abc_class };
    });

    const dead = classified.filter((c) => c.abc_class === 'DEAD');
    const aClass = classified.filter((c) => c.abc_class === 'A');
    const bClass = classified.filter((c) => c.abc_class === 'B');
    const cClass = classified.filter((c) => c.abc_class === 'C');

    res.json({
      success: true,
      data: {
        window_days: days,
        total_revenue_cents: totalRev,
        items: classified,
        summary: {
          A: aClass.length,
          B: bClass.length,
          C: cClass.length,
          DEAD: dead.length,
        },
        clearance_suggestions: dead
          .filter((d) => d.in_stock > 0)
          .slice(0, 50)
          .map((d) => ({
            id: d.id,
            name: d.name,
            in_stock: d.in_stock,
            // cost_price is a REAL column; convert to integer cents the
            // same way (ROUND after multiply) so a $9.999 wholesale price
            // rounds up to 1000 instead of the old CAST-truncation 999.
            tied_up_cost_cents: Math.round(d.in_stock * Number(d.cost_price || 0) * 100),
            suggestion: 'clearance_50_percent_off',
          })),
      },
    });
  }),
);

// ============================================================================
// INVENTORY AGE REPORT
// ============================================================================

router.get(
  '/age-report',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;

    // We approximate "age" by the oldest inbound stock_movement per item.
    // Items with no inbound movements fall back to created_at.
    const rows = await adb.all<{
      id: number;
      name: string;
      sku: string | null;
      in_stock: number;
      cost_price: number;
      first_received: string;
      age_days: number;
    }>(
      `SELECT
         i.id,
         i.name,
         i.sku,
         i.in_stock,
         i.cost_price,
         COALESCE(
           (SELECT MIN(created_at) FROM stock_movements sm WHERE sm.inventory_item_id = i.id AND sm.quantity > 0),
           i.created_at
         ) as first_received,
         CAST(
           (julianday('now') - julianday(COALESCE(
             (SELECT MIN(created_at) FROM stock_movements sm WHERE sm.inventory_item_id = i.id AND sm.quantity > 0),
             i.created_at
           ))) AS INTEGER
         ) as age_days
       FROM inventory_items i
       WHERE i.is_active = 1 AND i.item_type != 'service' AND i.in_stock > 0
       ORDER BY age_days DESC`,
    );

    const buckets = {
      fresh_0_3_months: [] as typeof rows,
      aging_3_12_months: [] as typeof rows,
      stale_12_plus: [] as typeof rows,
    };
    for (const r of rows) {
      if (r.age_days <= 90) buckets.fresh_0_3_months.push(r);
      else if (r.age_days <= 365) buckets.aging_3_12_months.push(r);
      else buckets.stale_12_plus.push(r);
    }

    // Round EACH row to integer cents BEFORE summing so 1000 rows of
    // $0.075 don't drift into $75.00000003. Matches criticalaudit.md §M7:
    // sum integers, never floats.
    const rowCostCents = (r: (typeof rows)[number]): number =>
      Math.round((Number(r.in_stock) || 0) * (Number(r.cost_price) || 0) * 100);
    const sumCostCents = (items: typeof rows): number =>
      items.reduce((s, r) => s + rowCostCents(r), 0);
    const totalCostByBucket = {
      fresh_0_3_months_cost_cents: sumCostCents(buckets.fresh_0_3_months),
      aging_3_12_months_cost_cents: sumCostCents(buckets.aging_3_12_months),
      stale_12_plus_cost_cents: sumCostCents(buckets.stale_12_plus),
    };

    res.json({
      success: true,
      data: {
        buckets,
        summary: {
          fresh_count: buckets.fresh_0_3_months.length,
          aging_count: buckets.aging_3_12_months.length,
          stale_count: buckets.stale_12_plus.length,
          ...totalCostByBucket,
        },
      },
    });
  }),
);

// ============================================================================
// SUPPLIER PRICE COMPARISON
// ============================================================================

router.get(
  '/:id/supplier-comparison',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    const rows = await adb.all(
      `SELECT sp.*, s.name as supplier_name
       FROM supplier_prices sp
       JOIN suppliers s ON s.id = sp.supplier_id
       WHERE sp.inventory_item_id = ?
       ORDER BY sp.price_cents ASC`,
      itemId,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/:id/supplier-prices',
  asyncHandler(async (req, res) => {
    // Updating supplier price feeds auto-reorder decisions — manager/admin only.
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    // FK: item must exist so a hand-crafted POST can't orphan supplier_prices.
    const itemRow = await adb.get(
      'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      itemId,
    );
    if (!itemRow) throw new AppError('Inventory item not found', 404);
    const supplierId = validateIntegerQuantity(req.body?.supplier_id, 'supplier_id');
    const supplierRow = await adb.get(
      'SELECT id FROM suppliers WHERE id = ?',
      supplierId,
    );
    if (!supplierRow) throw new AppError('Supplier not found', 404);
    const price = validatePrice(req.body?.price, 'price');
    const priceCents = Math.round(price * 100);
    const supplierSku = req.body?.supplier_sku
      ? validateTextLength(req.body.supplier_sku, 80, 'supplier_sku')
      : null;
    let leadTimeDays: number | null = null;
    if (req.body?.lead_time_days !== undefined && req.body?.lead_time_days !== null) {
      leadTimeDays = validateIntegerQuantity(req.body.lead_time_days, 'lead_time_days');
    }
    const moq = req.body?.moq !== undefined && req.body?.moq !== null
      ? Math.max(1, validateIntegerQuantity(req.body.moq, 'moq'))
      : 1;

    await adb.run(
      `INSERT INTO supplier_prices
         (inventory_item_id, supplier_id, supplier_sku, price_cents, lead_time_days, moq, last_updated_at)
       VALUES (?, ?, ?, ?, ?, ?, datetime('now'))
       ON CONFLICT(inventory_item_id, supplier_id) DO UPDATE SET
         supplier_sku = excluded.supplier_sku,
         price_cents = excluded.price_cents,
         lead_time_days = excluded.lead_time_days,
         moq = excluded.moq,
         last_updated_at = datetime('now')`,
      itemId,
      supplierId,
      supplierSku,
      priceCents,
      leadTimeDays,
      moq,
    );

    audit(req.db, 'supplier_price_upserted', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: itemId,
      supplier_id: supplierId,
      price_cents: priceCents,
    });

    const row = await adb.get(
      `SELECT sp.*, s.name as supplier_name
       FROM supplier_prices sp JOIN suppliers s ON s.id = sp.supplier_id
       WHERE sp.inventory_item_id = ? AND sp.supplier_id = ?`,
      itemId,
      supplierId,
    );
    res.json({ success: true, data: row });
  }),
);

// ============================================================================
// SUPPLIER RETURNS
// ============================================================================

router.get(
  '/supplier-returns',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const status = req.query.status
      ? validateEnum(
          req.query.status,
          ['pending', 'approved', 'shipped', 'credited', 'rejected'] as const,
          'status',
          false,
        )
      : null;
    const where = status ? 'WHERE sr.status = ?' : '';
    const params = status ? [status] : [];
    const rows = await adb.all(
      `SELECT sr.*, s.name as supplier_name, i.name as item_name, i.sku
       FROM supplier_returns sr
       JOIN suppliers s ON s.id = sr.supplier_id
       JOIN inventory_items i ON i.id = sr.inventory_item_id
       ${where}
       ORDER BY sr.created_at DESC`,
      ...params,
    );
    res.json({ success: true, data: rows });
  }),
);

router.post(
  '/supplier-returns',
  asyncHandler(async (req, res) => {
    // Supplier returns can trigger supplier credit flows — manager/admin only.
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const supplierId = validateIntegerQuantity(req.body?.supplier_id, 'supplier_id');
    const itemId = validateIntegerQuantity(req.body?.inventory_item_id, 'inventory_item_id');
    const quantity = validateIntegerQuantity(req.body?.quantity, 'quantity');
    const reason = req.body?.reason
      ? validateTextLength(req.body.reason, 500, 'reason')
      : null;

    // FK: both the supplier and the inventory item must exist before we
    // insert a supplier_returns row — otherwise we strand a dangling record.
    const supplier = await adb.get('SELECT id FROM suppliers WHERE id = ?', supplierId);
    if (!supplier) throw new AppError('Supplier not found', 404);
    const item = await adb.get(
      'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      itemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);

    const result = await adb.run(
      `INSERT INTO supplier_returns (supplier_id, inventory_item_id, quantity, reason)
       VALUES (?, ?, ?, ?)`,
      supplierId,
      itemId,
      quantity,
      reason,
    );

    audit(req.db, 'supplier_return_created', req.user!.id, req.ip || 'unknown', {
      id: Number(result.lastInsertRowid),
      supplier_id: supplierId,
      inventory_item_id: itemId,
    });

    const row = await adb.get(
      'SELECT * FROM supplier_returns WHERE id = ?',
      result.lastInsertRowid,
    );
    res.json({ success: true, data: row });
  }),
);

router.put(
  '/supplier-returns/:id',
  asyncHandler(async (req, res) => {
    requireManagerOrAdmin(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseInt(qs(req.params.id), 10);
    if (!id || isNaN(id)) throw new AppError('Invalid return id', 400);
    const status = validateEnum(
      req.body?.status,
      ['pending', 'approved', 'shipped', 'credited', 'rejected'] as const,
      'status',
      true,
    )!;
    const creditCents = req.body?.credit_amount
      ? Math.round(validatePrice(req.body.credit_amount, 'credit_amount') * 100)
      : null;
    await adb.run(
      `UPDATE supplier_returns
       SET status = ?, credit_amount_cents = COALESCE(?, credit_amount_cents)
       WHERE id = ?`,
      status,
      creditCents,
      id,
    );
    audit(req.db, 'supplier_return_updated', req.user!.id, req.ip || 'unknown', {
      id,
      status,
    });
    const row = await adb.get('SELECT * FROM supplier_returns WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

// ============================================================================
// PARTS COMPATIBILITY
// ============================================================================

router.get(
  '/:id/compatibility',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemId = parseInt(qs(req.params.id), 10);
    if (!itemId || isNaN(itemId)) throw new AppError('Invalid item id', 400);
    const rows = await adb.all<{ device_model: string }>(
      `SELECT device_model FROM inventory_compatibility WHERE inventory_item_id = ? ORDER BY device_model`,
      itemId,
    );
    res.json({ success: true, data: rows.map((r) => r.device_model) });
  }),
);

router.post(
  '/compatibility',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemId = validateIntegerQuantity(req.body?.inventory_item_id, 'inventory_item_id');
    // FK: can't map compatibility to a non-existent item.
    const item = await adb.get(
      'SELECT id FROM inventory_items WHERE id = ? AND is_active = 1',
      itemId,
    );
    if (!item) throw new AppError('Inventory item not found', 404);
    const modelsInput = validateArrayBounds<unknown>(
      req.body?.device_models ?? [],
      'device_models',
      500,
    );
    const models = modelsInput
      .map((m: unknown) => (typeof m === 'string' ? m.trim() : ''))
      .filter((m: string) => m.length > 0 && m.length <= 120);
    if (models.length === 0) {
      throw new AppError('device_models array is required', 400);
    }

    const db = req.db;
    const tx = db.transaction(() => {
      // Replace semantics: caller sends the full set for this item.
      db.prepare('DELETE FROM inventory_compatibility WHERE inventory_item_id = ?').run(itemId);
      const insert = db.prepare(
        'INSERT INTO inventory_compatibility (inventory_item_id, device_model) VALUES (?, ?)',
      );
      for (const m of models) insert.run(itemId, m);
    });
    tx();

    audit(req.db, 'compatibility_updated', req.user!.id, req.ip || 'unknown', {
      inventory_item_id: itemId,
      count: models.length,
    });
    res.json({ success: true, data: { inventory_item_id: itemId, device_models: models } });
  }),
);

// ============================================================================
// MASS BARCODE LABEL PRINTING
// ============================================================================

/**
 * POST /labels/print
 *
 * Body: { item_ids: number[], format?: 'zpl' | 'pdf', copies_per_item?: number }
 *
 * Returns a ZPL (Zebra Programming Language) batch by default — the shop
 * already uses ZPL-capable label printers per inventory.routes.ts. PDF is
 * a lighter "preview" mode that just dumps the label list as plain text;
 * the frontend can pipe it to window.print() for any printer.
 *
 * We do NOT actually render barcode images here — the inventory route
 * already has a /barcode/:sku endpoint that returns a PNG. For the batch
 * job we emit ZPL which the printer rasterizes natively.
 */
router.post(
  '/labels/print',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const itemIdsRaw = validateArrayBounds<unknown>(
      req.body?.item_ids ?? [],
      'item_ids',
      500,
    );
    const ids = itemIdsRaw
      .map((i: unknown) => parseInt(String(i), 10))
      .filter((i: number) => i > 0 && !isNaN(i));
    if (ids.length === 0) throw new AppError('item_ids array is required', 400);

    const copies = Math.max(
      1,
      Math.min(10, validateIntegerQuantity(req.body?.copies_per_item ?? 1, 'copies_per_item')),
    );
    const format = validateEnum(
      req.body?.format ?? 'zpl',
      ['zpl', 'pdf'] as const,
      'format',
      false,
    ) ?? 'zpl';

    const placeholders = ids.map(() => '?').join(',');
    const items = await adb.all<{
      id: number;
      sku: string | null;
      name: string;
      retail_price: number;
    }>(
      `SELECT id, sku, name, retail_price FROM inventory_items WHERE id IN (${placeholders}) AND is_active = 1`,
      ...ids,
    );

    if (items.length === 0) throw new AppError('No valid items found', 404);

    // ZPL template — 2x1 inch label (203dpi, 406x203 dots).
    // Name truncated to 28 chars, SKU barcoded, price printed.
    const zplChunks: string[] = [];
    for (const it of items) {
      const displayName = (it.name || '').slice(0, 28).replace(/[\^~]/g, ' ');
      const sku = it.sku || `ID${it.id}`;
      const price = (it.retail_price || 0).toFixed(2);
      for (let c = 0; c < copies; c++) {
        zplChunks.push(
          [
            '^XA',
            '^CF0,24',
            `^FO20,20^FD${displayName}^FS`,
            `^BY2,3,60`,
            `^FO20,60^BCN,60,Y,N,N`,
            `^FD${sku}^FS`,
            '^CF0,28',
            `^FO20,150^FD$${price}^FS`,
            '^XZ',
          ].join(''),
        );
      }
    }

    const zplBody = zplChunks.join('\n');
    const totalLabels = items.length * copies;

    audit(req.db, 'labels_printed', req.user!.id, req.ip || 'unknown', {
      item_count: items.length,
      total_labels: totalLabels,
      format,
    });

    if (format === 'pdf') {
      // Lightweight text fallback — frontend dumps into an <iframe> for print.
      const plain = items
        .map((it) => `${it.sku || `ID${it.id}`}\t${it.name}\t$${(it.retail_price || 0).toFixed(2)}`)
        .join('\n');
      res.json({
        success: true,
        data: {
          format: 'pdf',
          body: plain,
          total_labels: totalLabels,
        },
      });
      return;
    }

    res.json({
      success: true,
      data: {
        format: 'zpl',
        body: zplBody,
        total_labels: totalLabels,
        item_count: items.length,
      },
    });
  }),
);

// ============================================================================
// QUICK-ADD rapid form
// ============================================================================

/**
 * POST /quick-add
 *
 * Body: { input: string }
 * Parses "name @ price" — e.g. "iPhone 14 screen @ 89.99" — and creates
 * a minimal inventory_items row with sensible defaults. Anything more
 * detailed should use the full /inventory create endpoint.
 */
router.post(
  '/quick-add',
  asyncHandler(async (req, res) => {
    const adb: AsyncDb = req.asyncDb;
    const raw = String(req.body?.input || '').trim();
    if (!raw) throw new AppError('input is required', 400);
    if (raw.length > 200) throw new AppError('input too long', 400);

    // Very small parser: "<name> @ <price>" or "<name>" (price defaults to 0)
    const atIdx = raw.lastIndexOf('@');
    let name: string;
    let price = 0;
    if (atIdx > 0) {
      name = raw.slice(0, atIdx).trim();
      const priceStr = raw.slice(atIdx + 1).trim().replace(/[^0-9.]/g, '');
      price = validatePrice(priceStr || '0', 'price');
    } else {
      name = raw;
    }
    if (!name) throw new AppError('name is required', 400);
    if (name.length > 200) throw new AppError('name too long', 400);

    const result = await adb.run(
      `INSERT INTO inventory_items (name, retail_price, cost_price, item_type, is_active)
       VALUES (?, ?, 0, 'part', 1)`,
      name,
      price,
    );

    const id = Number(result.lastInsertRowid);
    audit(req.db, 'inventory_quick_add', req.user!.id, req.ip || 'unknown', {
      id,
      name,
      price,
    });
    const row = await adb.get('SELECT * FROM inventory_items WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

export default router;
