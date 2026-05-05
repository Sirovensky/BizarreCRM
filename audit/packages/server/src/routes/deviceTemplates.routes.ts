/**
 * Device-model repair templates (audit 44.1, cross-cutting across POS + Inventory)
 *
 * Flow:
 *   1. Admin edits templates in /settings/device-templates (CRUD here).
 *   2. Tech opens a ticket, hits the DeviceTemplatePicker.
 *   3. Picker hits POST /device-templates/:id/apply-to-ticket/:ticketId
 *      which copies the template's parts onto the target device row, stamps
 *      labor / suggested price, and drops the diagnostic checklist into the
 *      ticket's checklist column. Everything is idempotent — applying twice
 *      appends parts rather than dropping existing work.
 *
 * Response shape is always { success: true, data: X }.
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { createLogger } from '../utils/logger.js';
import {
  validateRequiredString,
  validateTextLength,
  validateArrayBounds,
  validateIntegerQuantity,
} from '../utils/validate.js';

const logger = createLogger('deviceTemplates.routes');

const router = Router();

// ────────────────────────────────────────────────────────────────────────────
// Types
// ────────────────────────────────────────────────────────────────────────────

interface DeviceTemplateRow {
  id: number;
  name: string;
  device_category: string | null;
  device_model: string | null;
  fault: string | null;
  est_labor_minutes: number;
  est_labor_cost: number;
  suggested_price: number;
  diagnostic_checklist_json: string | null;
  parts_json: string | null;
  warranty_days: number;
  is_active: number;
  sort_order: number;
  created_at: string;
  updated_at: string | null;
}

interface TemplatePart {
  inventory_item_id: number;
  qty: number;
}

interface EnrichedPart extends TemplatePart {
  name: string;
  sku: string | null;
  cost_price: number;
  retail_price: number;
  in_stock: number;
  stock_badge: 'green' | 'yellow' | 'red';
}

// ────────────────────────────────────────────────────────────────────────────
// Helpers
// ────────────────────────────────────────────────────────────────────────────

function parseJson<T>(val: string | null | undefined, fallback: T): T {
  if (!val) return fallback;
  try {
    return JSON.parse(val) as T;
  } catch {
    return fallback;
  }
}

function stockBadge(inStock: number, required: number): 'green' | 'yellow' | 'red' {
  if (inStock >= required) return 'green';
  if (inStock > 0) return 'yellow';
  return 'red';
}

function validateParts(raw: unknown): TemplatePart[] {
  if (raw === undefined || raw === null) return [];
  const bounded = validateArrayBounds<Record<string, unknown>>(raw, 'parts', 100);
  return bounded
    .filter((p): p is Record<string, unknown> => typeof p === 'object' && p !== null)
    .map((p) => ({
      inventory_item_id: Number(p.inventory_item_id),
      qty: Math.max(1, Number(p.qty) || 1),
    }))
    .filter((p) => Number.isFinite(p.inventory_item_id) && p.inventory_item_id > 0);
}

function validateChecklist(raw: unknown): string[] {
  if (raw === undefined || raw === null) return [];
  const bounded = validateArrayBounds<unknown>(raw, 'diagnostic_checklist', 100);
  return bounded
    .map((s: unknown) => (typeof s === 'string' ? s.trim() : ''))
    .filter((s) => s.length > 0 && s.length <= 200)
    .slice(0, 50);
}

async function enrichTemplate(
  adb: any,
  row: DeviceTemplateRow,
): Promise<DeviceTemplateRow & { parts: EnrichedPart[]; diagnostic_checklist: string[] }> {
  const parts = parseJson<TemplatePart[]>(row.parts_json, []);
  const checklist = parseJson<string[]>(row.diagnostic_checklist_json, []);

  const enriched: EnrichedPart[] = [];
  for (const p of parts) {
    const item = await adb.get(
      'SELECT id, name, sku, cost_price, retail_price, in_stock FROM inventory_items WHERE id = ?',
      p.inventory_item_id,
    );
    if (!item) continue;
    enriched.push({
      ...p,
      name: item.name,
      sku: item.sku ?? null,
      cost_price: Number(item.cost_price) || 0,
      retail_price: Number(item.retail_price) || 0,
      in_stock: Number(item.in_stock) || 0,
      stock_badge: stockBadge(Number(item.in_stock) || 0, p.qty),
    });
  }

  return { ...row, parts: enriched, diagnostic_checklist: checklist };
}

// ────────────────────────────────────────────────────────────────────────────
// GET / — list templates with optional filters
// ────────────────────────────────────────────────────────────────────────────
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const category = typeof req.query.category === 'string' ? req.query.category.trim() : '';
    const model = typeof req.query.model === 'string' ? req.query.model.trim() : '';
    const activeOnly = req.query.active !== 'false';

    let sql = 'SELECT * FROM device_model_templates WHERE 1=1';
    const args: unknown[] = [];
    if (activeOnly) sql += ' AND is_active = 1';
    if (category) {
      sql += ' AND device_category = ?';
      args.push(category);
    }
    if (model) {
      sql += ' AND device_model = ?';
      args.push(model);
    }
    sql += ' ORDER BY sort_order, name';

    const rows = (await adb.all(sql, ...args)) as DeviceTemplateRow[];
    const enriched = await Promise.all(rows.map((r) => enrichTemplate(adb, r)));

    res.json({ success: true, data: enriched });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// GET /:id
// ────────────────────────────────────────────────────────────────────────────
router.get(
  '/:id',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid template id', 400);

    const row = (await adb.get('SELECT * FROM device_model_templates WHERE id = ?', id)) as
      | DeviceTemplateRow
      | undefined;
    if (!row) throw new AppError('Template not found', 404);

    const enriched = await enrichTemplate(adb, row);
    res.json({ success: true, data: enriched });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// POST / — create (admin only)
// ────────────────────────────────────────────────────────────────────────────
router.post(
  '/',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): device templates affect every ticket
    // that uses them — restrict mutations to admins.
    if (req.user?.role !== 'admin') {
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const body = req.body ?? {};
    const name = validateRequiredString(body.name, 'name', 200);
    const deviceCategory = body.device_category
      ? validateTextLength(body.device_category, 80, 'device_category')
      : null;
    const deviceModel = body.device_model
      ? validateTextLength(body.device_model, 120, 'device_model')
      : null;
    const fault = body.fault
      ? validateTextLength(body.fault, 500, 'fault')
      : null;

    const parts = validateParts(body.parts);
    const checklist = validateChecklist(body.diagnostic_checklist);

    const result = await adb.run(
      `INSERT INTO device_model_templates
        (name, device_category, device_model, fault,
         est_labor_minutes, est_labor_cost, suggested_price,
         diagnostic_checklist_json, parts_json,
         warranty_days, is_active, sort_order)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      name,
      deviceCategory || null,
      deviceModel || null,
      fault || null,
      Math.max(0, Number(body.est_labor_minutes) || 0),
      Math.max(0, Math.round(Number(body.est_labor_cost) || 0)),
      Math.max(0, Math.round(Number(body.suggested_price) || 0)),
      JSON.stringify(checklist),
      JSON.stringify(parts),
      Math.max(0, Number(body.warranty_days) || 30),
      body.is_active === false ? 0 : 1,
      Math.max(0, Number(body.sort_order) || 0),
    );

    const newId = Number(result.lastInsertRowid);
    const row = (await adb.get(
      'SELECT * FROM device_model_templates WHERE id = ?',
      newId,
    )) as DeviceTemplateRow;
    const enriched = await enrichTemplate(adb, row);

    audit(req.db, 'device_template_created', req.user?.id ?? null, req.ip ?? 'unknown', {
      template_id: newId,
      name,
    });

    res.status(201).json({ success: true, data: enriched });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// PUT /:id — update (partial allowed, admin only)
// ────────────────────────────────────────────────────────────────────────────
router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') {
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid template id', 400);

    const existing = (await adb.get(
      'SELECT * FROM device_model_templates WHERE id = ?',
      id,
    )) as DeviceTemplateRow | undefined;
    if (!existing) throw new AppError('Template not found', 404);

    const body = req.body ?? {};
    const name =
      body.name !== undefined
        ? validateRequiredString(body.name, 'name', 200)
        : existing.name;
    const deviceCategory =
      body.device_category !== undefined
        ? body.device_category
          ? validateTextLength(body.device_category, 80, 'device_category') || null
          : null
        : existing.device_category;
    const deviceModel =
      body.device_model !== undefined
        ? body.device_model
          ? validateTextLength(body.device_model, 120, 'device_model') || null
          : null
        : existing.device_model;
    const fault =
      body.fault !== undefined
        ? body.fault
          ? validateTextLength(body.fault, 500, 'fault') || null
          : null
        : existing.fault;

    const parts =
      body.parts !== undefined
        ? validateParts(body.parts)
        : parseJson<TemplatePart[]>(existing.parts_json, []);
    const checklist =
      body.diagnostic_checklist !== undefined
        ? validateChecklist(body.diagnostic_checklist)
        : parseJson<string[]>(existing.diagnostic_checklist_json, []);

    await adb.run(
      `UPDATE device_model_templates SET
        name = ?, device_category = ?, device_model = ?, fault = ?,
        est_labor_minutes = ?, est_labor_cost = ?, suggested_price = ?,
        diagnostic_checklist_json = ?, parts_json = ?,
        warranty_days = ?, is_active = ?, sort_order = ?,
        updated_at = datetime('now')
       WHERE id = ?`,
      name,
      deviceCategory,
      deviceModel,
      fault,
      body.est_labor_minutes !== undefined
        ? Math.max(0, Number(body.est_labor_minutes) || 0)
        : existing.est_labor_minutes,
      body.est_labor_cost !== undefined
        ? Math.max(0, Math.round(Number(body.est_labor_cost) || 0))
        : existing.est_labor_cost,
      body.suggested_price !== undefined
        ? Math.max(0, Math.round(Number(body.suggested_price) || 0))
        : existing.suggested_price,
      JSON.stringify(checklist),
      JSON.stringify(parts),
      body.warranty_days !== undefined
        ? Math.max(0, Number(body.warranty_days) || 30)
        : existing.warranty_days,
      body.is_active !== undefined ? (body.is_active ? 1 : 0) : existing.is_active,
      body.sort_order !== undefined ? Math.max(0, Number(body.sort_order) || 0) : existing.sort_order,
      id,
    );

    const row = (await adb.get(
      'SELECT * FROM device_model_templates WHERE id = ?',
      id,
    )) as DeviceTemplateRow;
    const enriched = await enrichTemplate(adb, row);

    audit(req.db, 'device_template_updated', req.user?.id ?? null, req.ip ?? 'unknown', {
      template_id: id,
    });

    res.json({ success: true, data: enriched });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// DELETE /:id (admin only)
// ────────────────────────────────────────────────────────────────────────────
router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') {
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const id = Number(req.params.id);
    if (!Number.isFinite(id) || id <= 0) throw new AppError('Invalid template id', 400);

    const existing = await adb.get('SELECT id FROM device_model_templates WHERE id = ?', id);
    if (!existing) throw new AppError('Template not found', 404);

    await adb.run('DELETE FROM device_model_templates WHERE id = ?', id);

    audit(req.db, 'device_template_deleted', req.user?.id ?? null, req.ip ?? 'unknown', {
      template_id: id,
    });

    res.json({ success: true, data: { message: 'Template deleted' } });
  }),
);

// ────────────────────────────────────────────────────────────────────────────
// POST /:id/apply-to-ticket/:ticketId
//
// Copies template parts onto the ticket's device, adds the labor estimate,
// and appends the diagnostic checklist to the ticket. Idempotent-ish: we
// don't dedupe parts (two clicks = double parts) because a tech might
// legitimately want to order spares — but we do log each application.
// ────────────────────────────────────────────────────────────────────────────
router.post(
  '/:id/apply-to-ticket/:ticketId',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin' && req.user?.role !== 'manager') {
      throw new AppError('Manager or admin required', 403);
    }
    const adb = req.asyncDb;
    const templateId = Number(req.params.id);
    const ticketId = Number(req.params.ticketId);
    if (!Number.isFinite(templateId) || !Number.isFinite(ticketId)) {
      throw new AppError('Invalid id', 400);
    }

    const template = (await adb.get(
      'SELECT * FROM device_model_templates WHERE id = ?',
      templateId,
    )) as DeviceTemplateRow | undefined;
    if (!template) throw new AppError('Template not found', 404);
    if (!template.is_active) throw new AppError('Template is inactive', 400);

    const ticket = await adb.get('SELECT id FROM tickets WHERE id = ?', ticketId);
    if (!ticket) throw new AppError('Ticket not found', 404);

    // Target device: user can specify one, else we pick the first device on
    // the ticket. Adding a device first is the caller's responsibility.
    let targetDeviceId: number | null = null;
    if (req.body?.ticket_device_id !== undefined && req.body?.ticket_device_id !== null) {
      targetDeviceId = validateIntegerQuantity(req.body.ticket_device_id, 'ticket_device_id');
    }
    const device = targetDeviceId
      ? await adb.get<any>(
          'SELECT id FROM ticket_devices WHERE id = ? AND ticket_id = ?',
          targetDeviceId,
          ticketId,
        )
      : await adb.get<any>(
          'SELECT id FROM ticket_devices WHERE ticket_id = ? ORDER BY id LIMIT 1',
          ticketId,
        );
    if (!device) throw new AppError('No device on ticket to apply template to', 400);

    const parts = parseJson<TemplatePart[]>(template.parts_json, []);
    const checklist = parseJson<string[]>(template.diagnostic_checklist_json, []);

    let insertedParts = 0;
    for (const p of parts) {
      const item = await adb.get<any>(
        'SELECT id, name, retail_price, cost_price FROM inventory_items WHERE id = ?',
        p.inventory_item_id,
      );
      if (!item) continue;

      await adb.run(
        `INSERT INTO ticket_device_parts
          (ticket_device_id, inventory_item_id, name, quantity, price, cost_price, status)
         VALUES (?, ?, ?, ?, ?, ?, 'available')`,
        device.id,
        item.id,
        item.name,
        p.qty,
        Number(item.retail_price) || 0,
        Number(item.cost_price) || 0,
      );
      insertedParts += 1;
    }

    // Append checklist items to the ticket's existing checklist column, if it
    // exists. We don't fail the whole request if the column is missing —
    // older schemas may not have it.
    try {
      const checklistRow = (await adb.get(
        'SELECT checklist_json FROM tickets WHERE id = ?',
        ticketId,
      )) as { checklist_json: string | null } | undefined;
      const existing = parseJson<Array<{ text: string; done: boolean }>>(
        checklistRow?.checklist_json ?? null,
        [],
      );
      const merged = [
        ...existing,
        ...checklist.map((text) => ({ text, done: false, source: 'template' })),
      ];
      await adb.run(
        "UPDATE tickets SET checklist_json = ? WHERE id = ?",
        JSON.stringify(merged),
        ticketId,
      );
    } catch (err) {
      logger.warn('apply-to-ticket: checklist column not present, skipping', {
        ticket_id: ticketId,
        error: err instanceof Error ? err.message : String(err),
      });
    }

    audit(req.db, 'device_template_applied', req.user?.id ?? null, req.ip ?? 'unknown', {
      template_id: templateId,
      ticket_id: ticketId,
      ticket_device_id: device.id,
      inserted_parts: insertedParts,
    });

    res.json({
      success: true,
      data: {
        message: 'Template applied',
        ticket_id: ticketId,
        ticket_device_id: device.id,
        inserted_parts: insertedParts,
        suggested_price_cents: template.suggested_price,
        est_labor_minutes: template.est_labor_minutes,
        est_labor_cost_cents: template.est_labor_cost,
        diagnostic_checklist: checklist,
      },
    });
  }),
);

export default router;
