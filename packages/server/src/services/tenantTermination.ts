/**
 * PROD59 — Tenant self-service termination flow.
 *
 * CRITICAL: Tenant DBs are sacred. This module implements the ONE allowed
 * deletion path: explicit, user-initiated, multi-step confirmation.
 *
 * Flow (all three actions hit POST /api/v1/admin/terminate-tenant):
 *   Step 1 (action=request)  → mint token, email to tenant admin_email,
 *                              return { token, expires_at } to caller.
 *   Step 2 (action=confirm)  → client posts token + typed_slug; must match
 *                              the tenant's subdomain slug EXACTLY (case-
 *                              sensitive). On match the token is upgraded
 *                              to "slug_confirmed".
 *   Step 3 (action=finalize) → client posts token + typed_slug + typed_phrase.
 *                              typed_phrase must be literal
 *                              "DELETE ALL DATA PERMANENTLY". On match, we
 *                              perform the soft-delete:
 *                                  - close DB handle
 *                                  - rename tenant DB to deleted/<slug>-<ts>.db
 *                                  - mark tenant row in master DB
 *                                  - remove Cloudflare DNS record
 *                                  - invalidate all user sessions
 *                              Physical purge happens 30 days later via the
 *                              daily cron `purgeExpiredDeletions`.
 *
 * The deleted/ directory is a 30-day grace window — restoring is as simple
 * as moving the file back to tenants/<slug>.db and re-provisioning the
 * master row. The grace window is the whole point: users who change their
 * mind, billing goofs, and targeted-account-takeover recovery all rely on
 * the file not being `rm`d until the window elapses.
 */

import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import type Database from 'better-sqlite3';
import { config } from '../config.js';
import { getMasterDb } from '../db/master-connection.js';
import { closeTenantDb } from '../db/tenant-pool.js';
import { deleteTenantDnsRecord } from './cloudflareDns.js';
import { sendEmail } from './email.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('tenant-termination');

/** Grace window before a renamed tenant DB is physically unlinked. */
export const TERMINATION_GRACE_DAYS = 30;

/** Token lifetime for step 1 → step 3 (5 minutes). */
const TOKEN_TTL_MS = 5 * 60 * 1000;

/** Required literal phrase for step 3. Exact string match — whitespace-sensitive. */
export const TERMINATION_PHRASE = 'DELETE ALL DATA PERMANENTLY';

type TokenStage = 'issued' | 'slug_confirmed';

interface TerminationToken {
  token: string;
  slug: string;
  tenantId: number | null;      // null in single-tenant mode
  adminUserId: number;
  adminUsername: string;
  adminEmail: string | null;
  stage: TokenStage;
  expiresAt: number;
}

/**
 * In-memory token store. Tokens are short-lived (5 min) and high-value; a
 * process restart dropping them just forces the user to request a fresh one,
 * which is the safer default than persisting them to disk.
 */
const tokens = new Map<string, TerminationToken>();

/** Best-effort reaper so we don't hold expired tokens forever. */
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of tokens) {
    if (v.expiresAt < now) tokens.delete(k);
  }
}, 60_000).unref?.();

function newToken(): string {
  return crypto.randomBytes(32).toString('hex');
}

function timingSafeEquals(a: string, b: string): boolean {
  const aBuf = Buffer.from(a, 'utf8');
  const bBuf = Buffer.from(b, 'utf8');
  if (aBuf.length !== bBuf.length) return false;
  return crypto.timingSafeEqual(aBuf, bBuf);
}

export interface RequestTerminationInput {
  /** Tenant slug — in single-tenant mode this is the literal "__single__". */
  slug: string;
  /** null in single-tenant mode. */
  tenantId: number | null;
  adminUserId: number;
  adminUsername: string;
  adminEmail: string | null;
  /** Tenant DB handle — used to send the notification email via its SMTP config. */
  tenantDb: Database.Database;
  /** Public-facing URL of the app, for the email body. */
  appUrl: string;
  requestIp: string;
}

export interface RequestTerminationResult {
  token: string;
  expiresAt: string;
}

/**
 * Step 1: mint a one-shot termination token and email a copy to the
 * tenant admin_email (if SMTP is configured). The emailed copy is the
 * paper trail for the operator — if they didn't initiate this, they see
 * the email and can kill the token by restarting the server or waiting
 * 5 minutes for expiry.
 */
export async function requestTermination(
  input: RequestTerminationInput,
): Promise<RequestTerminationResult> {
  const token = newToken();
  const expiresAt = Date.now() + TOKEN_TTL_MS;

  tokens.set(token, {
    token,
    slug: input.slug,
    tenantId: input.tenantId,
    adminUserId: input.adminUserId,
    adminUsername: input.adminUsername,
    adminEmail: input.adminEmail,
    stage: 'issued',
    expiresAt,
  });

  // Best-effort email notification. Failure does NOT block token issue —
  // we still return the token to the requesting caller (who just proved
  // admin auth) so they can proceed even if SMTP is unconfigured.
  if (input.adminEmail) {
    try {
      await sendEmail(input.tenantDb, {
        to: input.adminEmail,
        subject: 'Account Termination Requested',
        html: buildTerminationEmailHtml({
          slug: input.slug,
          adminUsername: input.adminUsername,
          token,
          expiresAt: new Date(expiresAt).toISOString(),
          appUrl: input.appUrl,
          requestIp: input.requestIp,
        }),
      });
    } catch (err) {
      logger.warn('Failed to send termination-request email', {
        slug: input.slug,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return {
    token,
    expiresAt: new Date(expiresAt).toISOString(),
  };
}

/**
 * Step 2: caller must type the tenant slug EXACTLY (case-sensitive). On
 * match the token's stage advances to `slug_confirmed`. Case-sensitivity
 * is a deliberate friction increase — a mistyped capital letter means
 * the user has to slow down and read their own subdomain.
 */
export function confirmTerminationSlug(
  token: string,
  typedSlug: string,
): { ok: true } | { ok: false; error: string } {
  const entry = tokens.get(token);
  if (!entry) return { ok: false, error: 'Invalid or expired token' };
  if (entry.expiresAt < Date.now()) {
    tokens.delete(token);
    return { ok: false, error: 'Token expired' };
  }
  if (!timingSafeEquals(entry.slug, typedSlug)) {
    return { ok: false, error: 'Typed subdomain does not match your account' };
  }
  entry.stage = 'slug_confirmed';
  return { ok: true };
}

export interface FinalizeTerminationResult {
  deletionScheduledAt: string;
  permanentDeleteAt: string;
  archivedPath: string;
}

export interface FinalizeTerminationInput {
  token: string;
  typedSlug: string;
  typedPhrase: string;
  /** IP address of the caller. Null on cron-initiated paths. */
  requestIp: string | null;
}

/**
 * Step 3: final gate. Requires (a) a valid, unexpired, slug-confirmed
 * token, (b) the slug typed correctly AGAIN (defense-in-depth against a
 * token-theft scenario), and (c) the literal kill phrase. On all three
 * matches, we execute the termination against the master DB + filesystem
 * + Cloudflare + sessions.
 *
 * Single-tenant mode: we refuse — the tenant-termination endpoint only
 * makes sense for a hosted tenant-per-subdomain deployment. A single-
 * tenant self-hosted shop deletes their install by... deleting their
 * install. We surface that with a clear error.
 */
export async function finalizeTermination(
  input: FinalizeTerminationInput,
): Promise<{ ok: true; data: FinalizeTerminationResult } | { ok: false; error: string }> {
  const entry = tokens.get(input.token);
  if (!entry) return { ok: false, error: 'Invalid or expired token' };
  if (entry.expiresAt < Date.now()) {
    tokens.delete(input.token);
    return { ok: false, error: 'Token expired' };
  }
  if (entry.stage !== 'slug_confirmed') {
    return { ok: false, error: 'Slug confirmation step was not completed' };
  }
  if (!timingSafeEquals(entry.slug, input.typedSlug)) {
    return { ok: false, error: 'Typed subdomain does not match your account' };
  }
  if (!timingSafeEquals(TERMINATION_PHRASE, input.typedPhrase)) {
    return {
      ok: false,
      error: `Type the phrase exactly: ${TERMINATION_PHRASE}`,
    };
  }

  if (!config.multiTenant || entry.tenantId === null) {
    return {
      ok: false,
      error:
        'Self-service termination is only available in multi-tenant mode. Contact the platform administrator.',
    };
  }

  // ALL gates passed. Consume the token before any side-effect so a
  // caller that retries on timeout cannot double-execute.
  tokens.delete(input.token);

  return await executeTermination({
    slug: entry.slug,
    tenantId: entry.tenantId,
    requestIp: input.requestIp,
  });
}

/**
 * Perform the actual filesystem + master-DB + Cloudflare termination.
 * Ordering matters:
 *   1. Close the live DB handle so we can rename the file on Windows.
 *   2. Rename (not unlink) tenant DB into `<tenantDataDir>/deleted/`.
 *   3. Update the master `tenants` row with the scheduled delete time.
 *   4. Remove the Cloudflare DNS record (best-effort; a failure here
 *      does NOT roll back — the user's intent is already expressed and
 *      a dangling DNS record is a lesser evil than aborting mid-flow).
 *   5. Invalidate every session for users belonging to this tenant DB.
 */
async function executeTermination(opts: {
  slug: string;
  tenantId: number;
  requestIp: string | null;
}): Promise<{ ok: true; data: FinalizeTerminationResult } | { ok: false; error: string }> {
  const masterDb = getMasterDb();
  if (!masterDb) return { ok: false, error: 'Master database unavailable' };

  const row = masterDb
    .prepare(
      "SELECT id, slug, db_path, cloudflare_record_id FROM tenants WHERE id = ? AND status NOT IN ('deleted', 'pending_deletion')",
    )
    .get(opts.tenantId) as
    | { id: number; slug: string; db_path: string; cloudflare_record_id: string | null }
    | undefined;

  if (!row) return { ok: false, error: 'Tenant not found or already terminated' };

  const deletedDir = path.join(config.tenantDataDir, 'deleted');
  if (!fs.existsSync(deletedDir)) {
    fs.mkdirSync(deletedDir, { recursive: true });
  }

  const ts = new Date().toISOString().replace(/[:.]/g, '-');
  const archivedName = `${row.slug}-${ts}.db`;
  const archivedPath = path.join(deletedDir, archivedName);
  const srcPath = path.join(config.tenantDataDir, row.db_path);

  // 1. Close live DB handle before rename.
  try {
    closeTenantDb(row.slug);
  } catch (err) {
    logger.warn('closeTenantDb failed during termination (continuing)', {
      slug: row.slug,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // 2. Rename main DB + WAL/SHM sidecars into deleted/. If the source DB
  // file is missing we still proceed — the user's intent stands and the
  // rest of the cleanup (master row, Cloudflare, sessions) should run.
  if (fs.existsSync(srcPath)) {
    fs.renameSync(srcPath, archivedPath);
  } else {
    logger.warn('Tenant DB file missing at termination time', {
      slug: row.slug,
      srcPath,
    });
  }
  try { fs.renameSync(srcPath + '-wal', archivedPath + '-wal'); } catch {}
  try { fs.renameSync(srcPath + '-shm', archivedPath + '-shm'); } catch {}

  const scheduledAtMs = Date.now();
  const permanentDeleteAtMs = scheduledAtMs + TERMINATION_GRACE_DAYS * 24 * 60 * 60 * 1000;
  const scheduledAtIso = new Date(scheduledAtMs).toISOString();
  const permanentDeleteAtIso = new Date(permanentDeleteAtMs).toISOString();

  // 3. Flip master row to 'pending_deletion'. Keep db_path intact (the
  // tenant resolver already blocks the slug because status != 'active').
  // archived_db_path is set for operator visibility.
  try {
    masterDb
      .prepare(
        `UPDATE tenants
            SET status = 'pending_deletion',
                deletion_scheduled_at = ?,
                archived_db_path = ?,
                updated_at = datetime('now')
          WHERE id = ?`,
      )
      .run(permanentDeleteAtIso, archivedPath, row.id);
  } catch (err) {
    // This is bad — file is renamed but master row isn't updated. Log
    // loudly and let the operator reconcile. We don't try to rename back
    // because better-sqlite3 may have already released the handle in an
    // unknown state.
    logger.error('Failed to update master row after rename', {
      slug: row.slug,
      archivedPath,
      error: err instanceof Error ? err.message : String(err),
    });
  }

  // Audit trail entry so super-admin can see self-service terminations.
  try {
    masterDb
      .prepare(
        `INSERT INTO master_audit_log (super_admin_id, action, entity_type, entity_id, details, ip_address)
         VALUES (NULL, 'tenant_self_terminated', 'tenant', ?, ?, ?)`,
      )
      .run(
        row.slug,
        JSON.stringify({
          archivedPath,
          deletionScheduledAt: scheduledAtIso,
          permanentDeleteAt: permanentDeleteAtIso,
        }),
        opts.requestIp ?? null,
      );
  } catch {}

  // 4. Cloudflare DNS cleanup — best effort.
  if (row.cloudflare_record_id && config.cloudflareEnabled) {
    try {
      await deleteTenantDnsRecord(row.cloudflare_record_id);
    } catch (err) {
      logger.error('Cloudflare DNS delete failed during termination', {
        slug: row.slug,
        cloudflareRecordId: row.cloudflare_record_id,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  // 5. Session invalidation. The tenant DB was just renamed so the
  // sessions table lives inside the archived file — any outstanding
  // access token for this tenant will fail `authMiddleware`'s session
  // lookup on the NEXT request and be rejected cleanly. No server-side
  // action is needed to "log out" clients whose DB file is gone; this
  // comment is intentional documentation of the implicit behaviour.

  logger.info('Tenant self-terminated', {
    slug: row.slug,
    tenantId: row.id,
    archivedPath,
    permanentDeleteAt: permanentDeleteAtIso,
  });

  return {
    ok: true,
    data: {
      deletionScheduledAt: scheduledAtIso,
      permanentDeleteAt: permanentDeleteAtIso,
      archivedPath,
    },
  };
}

/**
 * Daily cron: unlink files in `deleted/` that are past their grace window.
 * Called from the index.ts cron block + once at startup so a server that was
 * offline through a scheduled purge still catches up.
 *
 * SCAN-595: eligibility is determined by querying `deletion_scheduled_at`
 * from the master `tenants` table (set at termination time). This is
 * authoritative and immune to filesystem mtime drift from backups, touches,
 * or restore operations.
 *
 * Fallback: if a .db file has no matching master-DB row (e.g. placed there by
 * a cold-backup restore before the row was re-created), we fall back to mtime
 * and log a warning so operators can investigate.
 */
export function purgeExpiredDeletions(): { scanned: number; purged: number } {
  const deletedDir = path.join(config.tenantDataDir, 'deleted');
  if (!fs.existsSync(deletedDir)) return { scanned: 0, purged: 0 };

  const masterDb = getMasterDb();
  const nowMs = Date.now();
  const GRACE_MS = TERMINATION_GRACE_DAYS * 24 * 60 * 60 * 1000;

  let scanned = 0;
  let purged = 0;

  for (const name of fs.readdirSync(deletedDir)) {
    // Only consider *.db entries — WAL/SHM sidecars are removed together.
    if (!/\.db$/.test(name)) continue;
    scanned += 1;
    const full = path.join(deletedDir, name);

    try {
      let deadlineMs: number | null = null;
      let deadlineSource: 'master_db' | 'mtime' = 'master_db';

      if (masterDb) {
        // Match by archived_db_path (exact) OR by slug extracted from filename.
        // Filename pattern: "<slug>-<iso-timestamp>.db"
        // e.g. "acme-2025-01-15T12-30-00-000Z.db" -> slug = "acme"
        const slugFromName = name.replace(/-\d{4}-\d{2}-\d{2}T[\d-]+Z\.db$/, '');
        const dbRow = masterDb
          .prepare(
            `SELECT deletion_scheduled_at FROM tenants
              WHERE archived_db_path = ? OR slug = ?
              LIMIT 1`,
          )
          .get(full, slugFromName) as { deletion_scheduled_at: string | null } | undefined;

        if (dbRow?.deletion_scheduled_at) {
          deadlineMs = new Date(dbRow.deletion_scheduled_at).getTime();
        }
      }

      if (deadlineMs === null) {
        // No authoritative master-DB record — fall back to mtime with a warning.
        const stat = fs.statSync(full);
        deadlineMs = stat.mtimeMs + GRACE_MS;
        deadlineSource = 'mtime';
        logger.warn(
          'purgeExpiredDeletions: no master-DB row for archived file; using mtime as fallback',
          { file: name, deadline: new Date(deadlineMs).toISOString() },
        );
      }

      if (nowMs >= deadlineMs) {
        fs.unlinkSync(full);
        try { fs.unlinkSync(full + '-wal'); } catch {}
        try { fs.unlinkSync(full + '-shm'); } catch {}
        purged += 1;
        logger.info('Purged expired terminated DB file', {
          file: name,
          deadlineSource,
          deadline: new Date(deadlineMs).toISOString(),
        });
      }
    } catch (err) {
      logger.warn('purgeExpiredDeletions: stat/unlink failed (skipping)', {
        file: name,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  if (scanned > 0) {
    logger.info('Purge sweep complete', { scanned, purged });
  }
  return { scanned, purged };
}

/** Email template for the step-1 notification. Kept verbose on purpose. */
function buildTerminationEmailHtml(opts: {
  slug: string;
  adminUsername: string;
  token: string;
  expiresAt: string;
  appUrl: string;
  requestIp: string;
}): string {
  return `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 560px; margin: 0 auto;">
      <h2 style="color: #b91c1c;">Account Termination Requested</h2>
      <p>Hello,</p>
      <p>
        Someone with admin credentials on your account just requested that your
        shop (<strong>${escapeHtml(opts.slug)}</strong>) be permanently deleted.
      </p>
      <ul>
        <li><strong>Admin:</strong> ${escapeHtml(opts.adminUsername)}</li>
        <li><strong>Requested from IP:</strong> ${escapeHtml(opts.requestIp)}</li>
        <li><strong>Token expires:</strong> ${escapeHtml(opts.expiresAt)}</li>
      </ul>
      <p>
        <strong>If this was you</strong>, return to the Settings → Danger Zone
        page and complete the next two confirmation steps within 5 minutes.
      </p>
      <p>
        <strong>If this was NOT you</strong>, ignore this email &mdash; the
        request expires automatically in 5 minutes, and the deletion will not
        go through without two further typed confirmations. Rotate your
        password immediately: <a href="${escapeHtml(opts.appUrl)}">${escapeHtml(opts.appUrl)}</a>
      </p>
      <hr />
      <p style="font-size: 12px; color: #666;">
        Your data will be soft-deleted for ${TERMINATION_GRACE_DAYS} days. During
        that window, contact support to restore your account. After
        ${TERMINATION_GRACE_DAYS} days, your database file will be permanently
        purged and cannot be recovered.
      </p>
    </div>
  `;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
