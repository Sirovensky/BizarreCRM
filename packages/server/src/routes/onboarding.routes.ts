/**
 * Onboarding Routes — Day-1 Experience (audit section 42)
 *
 * All endpoints operate on the single `onboarding_state` row (id = 1). The
 * route prefix in index.ts is `/api/v1/onboarding` behind authMiddleware.
 *
 * Endpoints:
 *   GET    /state             — returns the single row (creates it lazily if missing).
 *   PATCH  /state             — allowlisted partial update of dismissible flags.
 *   POST   /sample-data       — inserts 5 customers + 10 tickets + 3 invoices.
 *   DELETE /sample-data       — removes everything tracked in sample_data_entities_json.
 *   POST   /set-shop-type     — applies a starter template for the chosen shop type.
 *
 * Response shape is the project-standard { success, data } envelope.
 * Writes are audited via utils/audit. User-facing errors throw AppError so
 * the existing error middleware surfaces a clean JSON error.
 */

import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { validateEnum } from '../utils/validate.js';
import { createLogger } from '../utils/logger.js';
import {
  loadSampleData,
  removeSampleDataByEntities,
  type SampleEntity,
} from '../services/sampleData.js';

const router = Router();
const logger = createLogger('onboarding');

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

/**
 * Shape as returned to the client. SQLite booleans are stored as 0/1; we
 * expose them as `boolean` so the React widgets can use them directly.
 */
interface OnboardingStateResponse {
  checklist_dismissed: boolean;
  shop_type: ShopType | null;
  sample_data_loaded: boolean;
  sample_data_counts: { customers: number; tickets: number; invoices: number } | null;
  first_customer_at: string | null;
  first_ticket_at: string | null;
  first_invoice_at: string | null;
  first_payment_at: string | null;
  first_review_at: string | null;
  nudge_day3_seen: boolean;
  nudge_day5_seen: boolean;
  nudge_day7_seen: boolean;
  advanced_settings_unlocked: boolean;
  intro_video_dismissed: boolean;
}

/** Raw row as stored in SQLite (0/1 ints for booleans). */
interface OnboardingRow {
  id: number;
  checklist_dismissed: number;
  shop_type: string | null;
  sample_data_loaded: number;
  sample_data_entities_json: string | null;
  first_customer_at: string | null;
  first_ticket_at: string | null;
  first_invoice_at: string | null;
  first_payment_at: string | null;
  first_review_at: string | null;
  nudge_day3_seen: number;
  nudge_day5_seen: number;
  nudge_day7_seen: number;
  advanced_settings_unlocked: number;
  intro_video_dismissed: number;
}

const SHOP_TYPES = ['phone_repair', 'computer_repair', 'watch_repair', 'general_electronics'] as const;
type ShopType = typeof SHOP_TYPES[number];

// Fields accepted by PATCH /state. Every entry here is a simple boolean flag
// that the UI toggles once and forgets. Milestone timestamps are NOT in the
// allowlist — they are set server-side by the relevant create-first-thing
// hooks (added in a future sweep) to prevent the client from faking "I have
// customers" and collecting celebration confetti.
const PATCHABLE_FLAGS = [
  'checklist_dismissed',
  'nudge_day3_seen',
  'nudge_day5_seen',
  'nudge_day7_seen',
  'advanced_settings_unlocked',
  'intro_video_dismissed',
] as const;
type PatchableFlag = typeof PATCHABLE_FLAGS[number];

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Parse the sample_data_entities_json column safely, returning []  on any error. */
function parseSampleEntities(json: string | null): SampleEntity[] {
  if (!json) return [];
  try {
    const parsed = JSON.parse(json);
    if (!Array.isArray(parsed)) return [];
    // Defensive: drop malformed items rather than throwing.
    return parsed.filter(
      (e): e is SampleEntity =>
        e && typeof e === 'object' && typeof e.id === 'number' && typeof e.type === 'string',
    );
  } catch (err) {
    logger.warn('Failed to parse sample_data_entities_json; treating as empty', {
      error: err instanceof Error ? err.message : String(err),
    });
    return [];
  }
}

/**
 * Fetch the single row, creating it lazily if the migration hasn't fired yet
 * (safety net for old tenants). Always returns a row.
 */
async function getOrCreateRow(adb: {
  get: <T = unknown>(sql: string, ...params: unknown[]) => Promise<T | undefined>;
  run: (sql: string, ...params: unknown[]) => Promise<{ changes: number; lastInsertRowid: number }>;
}): Promise<OnboardingRow> {
  let row = await adb.get<OnboardingRow>('SELECT * FROM onboarding_state WHERE id = 1');
  if (!row) {
    await adb.run('INSERT OR IGNORE INTO onboarding_state (id) VALUES (1)');
    row = await adb.get<OnboardingRow>('SELECT * FROM onboarding_state WHERE id = 1');
    if (!row) {
      throw new AppError('Failed to initialize onboarding state', 500);
    }
  }
  return row;
}

function rowToResponse(row: OnboardingRow): OnboardingStateResponse {
  const entities = parseSampleEntities(row.sample_data_entities_json);
  const counts = entities.length
    ? {
        customers: entities.filter((e) => e.type === 'customer').length,
        tickets: entities.filter((e) => e.type === 'ticket').length,
        invoices: entities.filter((e) => e.type === 'invoice').length,
      }
    : null;
  return {
    checklist_dismissed: Boolean(row.checklist_dismissed),
    shop_type: (row.shop_type as ShopType | null) ?? null,
    sample_data_loaded: Boolean(row.sample_data_loaded),
    sample_data_counts: counts,
    first_customer_at: row.first_customer_at,
    first_ticket_at: row.first_ticket_at,
    first_invoice_at: row.first_invoice_at,
    first_payment_at: row.first_payment_at,
    first_review_at: row.first_review_at,
    nudge_day3_seen: Boolean(row.nudge_day3_seen),
    nudge_day5_seen: Boolean(row.nudge_day5_seen),
    nudge_day7_seen: Boolean(row.nudge_day7_seen),
    advanced_settings_unlocked: Boolean(row.advanced_settings_unlocked),
    intro_video_dismissed: Boolean(row.intro_video_dismissed),
  };
}

// ---------------------------------------------------------------------------
// Shop-type starter templates
// ---------------------------------------------------------------------------
//
// Each shop type gets a tiny bundle of SMS templates. Anything richer
// (repair pricing catalog, device-model library) is a v2 enhancement — see
// the README "Onboarding & Day-1 Experience" section — because the agent
// explicitly wants to hand-curate the seed from a known-good production DB
// before rolling it out.

interface ShopTypeTemplate {
  smsTemplates: Array<{ name: string; content: string; category: string }>;
}

const SHOP_TYPE_TEMPLATES: Record<ShopType, ShopTypeTemplate> = {
  phone_repair: {
    smsTemplates: [
      {
        name: 'Phone Drop-off Confirmation',
        content: 'Hi {{customer_name}}, we received your {{device_name}} and will diagnose it shortly. Ticket #{{ticket_id}}. Reply STOP to opt out.',
        category: 'status_update',
      },
      {
        name: 'Phone Repair Quote',
        content: 'Hi {{customer_name}}, your {{device_name}} repair estimate is ${{estimate_total}}. Reply YES to approve or call us. Reply STOP to opt out.',
        category: 'estimate',
      },
    ],
  },
  computer_repair: {
    smsTemplates: [
      {
        name: 'Computer Diagnostic Complete',
        content: 'Hi {{customer_name}}, diagnostics on your {{device_name}} are finished. Please call us to discuss next steps. Ticket #{{ticket_id}}. Reply STOP to opt out.',
        category: 'status_update',
      },
      {
        name: 'Data Backup Reminder',
        content: 'Hi {{customer_name}}, before we proceed with your {{device_name}} repair, please confirm your data is backed up. Reply STOP to opt out.',
        category: 'status_update',
      },
    ],
  },
  watch_repair: {
    smsTemplates: [
      {
        name: 'Watch Service Estimate',
        content: 'Hi {{customer_name}}, your {{device_name}} service estimate is ${{estimate_total}}. Please approve to proceed. Reply STOP to opt out.',
        category: 'estimate',
      },
      {
        name: 'Watch Ready for Pickup',
        content: 'Hi {{customer_name}}, your {{device_name}} is serviced and ready for pickup. We look forward to seeing you! Reply STOP to opt out.',
        category: 'status_update',
      },
    ],
  },
  general_electronics: {
    smsTemplates: [
      {
        name: 'Device Received',
        content: 'Hi {{customer_name}}, we received your {{device_name}} for service. Ticket #{{ticket_id}}. Reply STOP to opt out.',
        category: 'status_update',
      },
      {
        name: 'Device Ready',
        content: 'Hi {{customer_name}}, your {{device_name}} is ready for pickup. Total: ${{total}}. Reply STOP to opt out.',
        category: 'status_update',
      },
    ],
  },
};

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

/**
 * GET /state — returns the single onboarding row, lazily seeding it if missing.
 */
router.get(
  '/state',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const row = await getOrCreateRow(adb);
    res.json({ success: true, data: rowToResponse(row) });
  }),
);

/**
 * PATCH /state — allowlisted partial update of boolean flags.
 *
 * Body: any subset of PATCHABLE_FLAGS with boolean values. Any unknown key is
 * rejected with 400 instead of silently ignored — otherwise a typo turns into
 * a "the button does nothing" bug that's very annoying to debug.
 */
router.patch(
  '/state',
  asyncHandler(async (req, res) => {
    const adb = req.asyncDb;
    const body = req.body as Record<string, unknown> | null | undefined;
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new AppError('Request body must be an object', 400);
    }

    const updates: Array<{ field: PatchableFlag; value: 0 | 1 }> = [];
    for (const [key, value] of Object.entries(body)) {
      if (!(PATCHABLE_FLAGS as readonly string[]).includes(key)) {
        throw new AppError(`Unknown field: ${key}`, 400);
      }
      if (typeof value !== 'boolean') {
        throw new AppError(`Field ${key} must be a boolean`, 400);
      }
      updates.push({ field: key as PatchableFlag, value: value ? 1 : 0 });
    }

    if (!updates.length) {
      // No-op PATCH — still return current state so the client can use this
      // as a cheap refresh endpoint if it wants.
      const row = await getOrCreateRow(adb);
      res.json({ success: true, data: rowToResponse(row) });
      return;
    }

    // Ensure row exists before updating.
    await getOrCreateRow(adb);

    const setClause = updates.map((u) => `${u.field} = ?`).join(', ');
    const params = updates.map((u) => u.value);
    await adb.run(
      `UPDATE onboarding_state SET ${setClause}, updated_at = datetime('now') WHERE id = 1`,
      ...params,
    );

    const updated = await getOrCreateRow(adb);
    audit(req.db, 'onboarding_state_patched', req.user?.id ?? null, req.ip || 'unknown', {
      fields: updates.map((u) => u.field),
    });
    res.json({ success: true, data: rowToResponse(updated) });
  }),
);

/**
 * POST /sample-data — inserts the demo rows and persists the entity list.
 *
 * Idempotent: if sample data is already loaded, returns the current state
 * without re-inserting (avoids duplicate [Sample] customers if the user
 * double-clicks the button).
 *
 * SEC (post-enrichment audit §6): admin only — sample data writes into
 * real tables (customers/tickets/invoices) and should not be reachable
 * from a cashier or technician account.
 */
router.post(
  '/sample-data',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') {
      audit(req.db, 'unauthorized_attempt', req.user?.id ?? null, req.ip || 'unknown', {
        route: 'POST /onboarding/sample-data',
        required_role: 'admin',
        actual_role: req.user?.role ?? 'anonymous',
      });
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const row = await getOrCreateRow(adb);
    if (row.sample_data_loaded) {
      res.json({ success: true, data: { state: rowToResponse(row), created: false } });
      return;
    }

    // Post-enrichment audit §9: atomic "claim" step prevents the check-then-set
    // race that would otherwise let two concurrent POSTs both pass the
    // `sample_data_loaded === 0` check and double-insert sample rows (bloating
    // the tenant DB and breaking the "Remove sample data" list). better-sqlite3
    // statements are atomic, so an `UPDATE ... WHERE sample_data_loaded = 0`
    // either claims the slot (changes === 1) or loses the race (changes === 0).
    const claim = req.db
      .prepare(
        `UPDATE onboarding_state
            SET sample_data_loaded = 1,
                updated_at = datetime('now')
          WHERE id = 1 AND sample_data_loaded = 0`,
      )
      .run();
    if (claim.changes === 0) {
      // Someone else just claimed the slot — return the current state.
      const latest = await getOrCreateRow(adb);
      res.json({ success: true, data: { state: rowToResponse(latest), created: false } });
      return;
    }

    try {
      const result = await loadSampleData(adb);
      // Persist the entity list AFTER the inserts succeed — the claim step
      // already set sample_data_loaded=1 so re-runs are blocked; we just
      // need to fill in what got created so DELETE /sample-data can undo it.
      await adb.run(
        `UPDATE onboarding_state
           SET sample_data_entities_json = ?,
               updated_at = datetime('now')
         WHERE id = 1`,
        JSON.stringify(result.entities),
      );

      const updated = await getOrCreateRow(adb);
      audit(req.db, 'onboarding_sample_data_loaded', req.user?.id ?? null, req.ip || 'unknown', {
        counts: result.counts,
      });
      res.status(201).json({
        success: true,
        data: { state: rowToResponse(updated), created: true, counts: result.counts },
      });
    } catch (err) {
      // Rollback the claim so the admin can try again after fixing whatever
      // broke the sample data loader (missing status row, etc.).
      try {
        req.db
          .prepare(
            `UPDATE onboarding_state
                SET sample_data_loaded = 0,
                    sample_data_entities_json = NULL,
                    updated_at = datetime('now')
              WHERE id = 1`,
          )
          .run();
      } catch (rollbackErr) {
        logger.error('Failed to roll back onboarding sample-data claim', {
          error: rollbackErr instanceof Error ? rollbackErr.message : String(rollbackErr),
        });
      }
      throw err;
    }
  }),
);

/**
 * DELETE /sample-data — removes every row we inserted.
 *
 * SEC (post-enrichment audit §6): admin only — destructive operation.
 */
router.delete(
  '/sample-data',
  asyncHandler(async (req, res) => {
    if (req.user?.role !== 'admin') {
      audit(req.db, 'unauthorized_attempt', req.user?.id ?? null, req.ip || 'unknown', {
        route: 'DELETE /onboarding/sample-data',
        required_role: 'admin',
        actual_role: req.user?.role ?? 'anonymous',
      });
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const row = await getOrCreateRow(adb);
    if (!row.sample_data_loaded) {
      res.json({ success: true, data: { state: rowToResponse(row), removed: 0 } });
      return;
    }
    const entities = parseSampleEntities(row.sample_data_entities_json);
    const removed = await removeSampleDataByEntities(adb, entities);
    await adb.run(
      `UPDATE onboarding_state
         SET sample_data_loaded = 0,
             sample_data_entities_json = NULL,
             updated_at = datetime('now')
       WHERE id = 1`,
    );
    const updated = await getOrCreateRow(adb);
    audit(req.db, 'onboarding_sample_data_removed', req.user?.id ?? null, req.ip || 'unknown', {
      removed_rows: removed,
      entity_count: entities.length,
    });
    res.json({ success: true, data: { state: rowToResponse(updated), removed } });
  }),
);

/**
 * POST /set-shop-type — records the shop type + applies its starter template.
 *
 * The starter template today is a small SMS template bundle; richer content
 * (repair pricing catalog, device-model library) is intentionally deferred
 * until a curated "seed" DB is built from real shop history — see the
 * "Onboarding & Day-1 Experience" section of the README.
 */
router.post(
  '/set-shop-type',
  asyncHandler(async (req, res) => {
    // SEC (post-enrichment audit §6): admin only — installs SMS templates
    // and sets a global shop_type flag that influences new-user flows.
    if (req.user?.role !== 'admin') {
      audit(req.db, 'unauthorized_attempt', req.user?.id ?? null, req.ip || 'unknown', {
        route: 'POST /onboarding/set-shop-type',
        required_role: 'admin',
        actual_role: req.user?.role ?? 'anonymous',
      });
      throw new AppError('Admin role required', 403);
    }
    const adb = req.asyncDb;
    const shopType = validateEnum<ShopType>(req.body?.shop_type, SHOP_TYPES, 'shop_type', true);
    if (!shopType) throw new AppError('shop_type is required', 400);

    await getOrCreateRow(adb); // ensure row exists
    await adb.run(
      `UPDATE onboarding_state SET shop_type = ?, updated_at = datetime('now') WHERE id = 1`,
      shopType,
    );

    // Install starter SMS templates. Using INSERT OR IGNORE on a natural key
    // (name) keeps this idempotent — running set-shop-type twice is safe.
    const template = SHOP_TYPE_TEMPLATES[shopType];
    let installed = 0;
    for (const t of template.smsTemplates) {
      try {
        const result = await adb.run(
          `INSERT OR IGNORE INTO sms_templates (name, content, category) VALUES (?, ?, ?)`,
          t.name,
          t.content,
          t.category,
        );
        if (result.changes) installed += 1;
      } catch (err) {
        // Don't let a single template failure block the whole operation —
        // log it and continue. The user can manually re-add the template
        // from Settings → SMS Templates.
        logger.warn('Failed to install starter SMS template', {
          name: t.name,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    const updated = await getOrCreateRow(adb);
    audit(req.db, 'onboarding_shop_type_set', req.user?.id ?? null, req.ip || 'unknown', {
      shop_type: shopType,
      templates_installed: installed,
    });
    res.json({
      success: true,
      data: { state: rowToResponse(updated), templates_installed: installed },
    });
  }),
);

export default router;
