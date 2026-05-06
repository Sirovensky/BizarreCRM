/**
 * Custom roles + permission matrix routes — criticalaudit.md §53.
 *
 * Mounted at /api/v1/roles (and a small companion under /api/v1/users for
 * assigning a role to a user). Finishes the "coming soon" custom-permissions
 * work flagged in the audit.
 *
 * The 4 default roles (admin/manager/technician/cashier) are seeded in the
 * 096 migration. The full canonical permission KEY list lives here so it's
 * easy to extend without a migration.
 */
import { Router } from 'express';
import { AppError } from '../middleware/errorHandler.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { audit } from '../utils/audit.js';
import { validateRequiredString, validateTextLength } from '../utils/validate.js';
import type { AsyncDb } from '../db/async-db.js';
import { PERMISSIONS, ROLE_PERMISSIONS } from '@bizarre-crm/shared';
import { hasPermission, resolveEffectivePermission, type AuthUser } from '../middleware/auth.js';

const router = Router();

// SCAN-1099 [HIGH]: this file previously hard-coded its OWN `PERMISSION_KEYS`
// list (e.g. `inventory.adjust`, `customers.export`, `team.shifts`,
// `admin.full`, `payroll.view`) that drifted from the shared `PERMISSIONS`
// object used by `requirePermission()` on every actual route. The real
// enforcement keys (`tickets.change_status`, `tickets.bulk_update`,
// `inventory.adjust_stock`, `invoices.void`, `invoices.record_payment`,
// `customers.gdpr_erase`, `sms.send`, `pos.access`, `users.manage`, …)
// never appeared in the admin's custom-role matrix UI, and none of the
// keys the admin *could* toggle were ever read by the middleware. Every
// custom-role matrix edit was silently ineffective — `requirePermission()`
// fell through to the hard-coded role fallback. Pull from the shared
// constants so there is exactly one canonical list.
export const PERMISSION_KEYS: readonly string[] = Object.values(PERMISSIONS);

// Default permission map for the 4 seeded roles — sourced from the shared
// `ROLE_PERMISSIONS` table so the matrix that seeds the DB matches the
// matrix that `requirePermission()` reads at runtime.
const DEFAULT_ROLE_PERMS: Record<string, ReadonlySet<string>> = Object.fromEntries(
  Object.entries(ROLE_PERMISSIONS).map(([role, perms]) => [role, new Set(perms)]),
);

interface RoleRow {
  id: number;
  name: string;
  description: string | null;
  is_active: number;
  created_at: string;
}

interface UserPermissionTargetRow {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  permissions: string | null;
}

interface UserPermissionOverrideRow {
  permission_key: string;
  allowed: number;
  updated_by_user_id: number | null;
  updated_at: string | null;
  updated_by_username: string | null;
}

/**
 * Lazy-seed the role_permissions matrix on first read so we never pin a stale
 * key list at migration time. Idempotent — only inserts missing rows.
 *
 * SCAN-1104: previously ran ~128 `INSERT OR IGNORE` statements every time
 * `GET /roles` or `GET /roles/:id/permissions` was called. The settings
 * page renders both on mount, doubling the work per page view on every
 * tenant. Cache a per-tenant DB path in a module-scope Set so subsequent
 * calls early-return after a single inexpensive check. If the process
 * restarts or the DB is swapped the set is rebuilt.
 */
const seededDbs = new Set<string>();
async function ensureDefaultPermsSeeded(adb: AsyncDb): Promise<void> {
  if (seededDbs.has(adb.dbPath)) return;
  const roles = await adb.all<RoleRow>('SELECT id, name FROM custom_roles WHERE name IN (?, ?, ?, ?)',
    'admin', 'manager', 'technician', 'cashier');
  for (const role of roles) {
    const allowed = DEFAULT_ROLE_PERMS[role.name];
    if (!allowed) continue;
    for (const key of PERMISSION_KEYS) {
      const isAllowed = allowed.has(key) ? 1 : 0;
      await adb.run(
        `INSERT OR IGNORE INTO role_permissions (role_id, permission_key, allowed)
         VALUES (?, ?, ?)`,
        role.id, key, isAllowed,
      );
    }
  }
  seededDbs.add(adb.dbPath);
}

function requireUserManagement(req: any): void {
  if (!hasPermission(req?.user, PERMISSIONS.USERS_MANAGE)) {
    throw new AppError('users.manage permission required', 403);
  }
}

function parseId(value: unknown, label = 'id'): number {
  const raw = Array.isArray(value) ? value[0] : value;
  const n = parseInt(String(raw ?? ''), 10);
  if (!n || isNaN(n) || n <= 0) throw new AppError(`Invalid ${label}`, 400);
  return n;
}

function safeParsePermissions(raw: string | null | undefined): Record<string, boolean> | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
    const safe: Record<string, boolean> = {};
    for (const [key, value] of Object.entries(parsed)) {
      if (typeof value === 'boolean') safe[key] = value;
    }
    return safe;
  } catch {
    return null;
  }
}

async function getUserPermissionState(adb: AsyncDb, userId: number) {
  const user = await adb.get<UserPermissionTargetRow>(
    `SELECT id, username, email, first_name, last_name, role, permissions
     FROM users
     WHERE id = ? AND is_active = 1`,
    userId,
  );
  if (!user) throw new AppError('User not found', 404);

  const customRole = await adb.get<{
    role_id: number;
    role_name: string | null;
    description: string | null;
    is_active: number | null;
  }>(
    `SELECT ucr.role_id, cr.name AS role_name, cr.description, cr.is_active
     FROM user_custom_roles ucr
     LEFT JOIN custom_roles cr ON cr.id = ucr.role_id
     WHERE ucr.user_id = ?`,
    userId,
  );

  let customRolePermissions: Set<string> | null = null;
  if (customRole?.role_id && customRole.is_active === 1) {
    const rows = await adb.all<{ permission_key: string }>(
      'SELECT permission_key FROM role_permissions WHERE role_id = ? AND allowed = 1',
      customRole.role_id,
    );
    customRolePermissions = new Set(rows.map(row => row.permission_key));
  }

  const overrideRows = await adb.all<UserPermissionOverrideRow>(
    `SELECT up.permission_key, up.allowed, up.updated_by_user_id, up.updated_at,
            u.username AS updated_by_username
     FROM user_permissions up
     LEFT JOIN users u ON u.id = up.updated_by_user_id
     WHERE up.user_id = ?
     ORDER BY up.permission_key ASC`,
    userId,
  );
  const permissionOverrides = overrideRows.length
    ? new Map(overrideRows.map(row => [row.permission_key, row.allowed === 1]))
    : null;

  const authUser: AuthUser = {
    id: user.id,
    username: user.username,
    email: user.email,
    first_name: user.first_name,
    last_name: user.last_name,
    role: user.role,
    permissions: safeParsePermissions(user.permissions),
    sessionId: '',
    customRolePermissions,
    permissionOverrides,
  };

  return {
    user: {
      id: user.id,
      username: user.username,
      email: user.email,
      first_name: user.first_name,
      last_name: user.last_name,
      role: user.role,
    },
    custom_role: customRole
      ? {
          role_id: customRole.role_id,
          name: customRole.role_name,
          description: customRole.description,
          is_active: customRole.is_active,
        }
      : null,
    overrides: overrideRows.map(row => ({
      key: row.permission_key,
      allowed: row.allowed === 1,
      updated_by_user_id: row.updated_by_user_id,
      updated_by_username: row.updated_by_username,
      updated_at: row.updated_at,
    })),
    effective: PERMISSION_KEYS.map(key => ({
      key,
      ...resolveEffectivePermission(authUser, key),
    })),
  };
}

// ── ROLES CRUD ──────────────────────────────────────────────────────────────

router.get(
  '/',
  asyncHandler(async (req, res) => {
    // SCAN-1113: role list was visible to any authenticated user. Keep this
    // behind the same effective users.manage gate as the write handlers.
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    await ensureDefaultPermsSeeded(adb);
    const rows = await adb.all<RoleRow>(
      `SELECT id, name, description, is_active, created_at
       FROM custom_roles
       ORDER BY id ASC`,
    );
    res.json({ success: true, data: rows });
  }),
);

router.get(
  '/permission-keys',
  asyncHandler(async (_req, res) => {
    res.json({ success: true, data: PERMISSION_KEYS });
  }),
);

router.post(
  '/',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const name = validateRequiredString(req.body?.name, 'name', 50).toLowerCase();
    const description = req.body?.description
      ? validateTextLength(req.body.description, 200, 'description')
      : null;
    try {
      const result = await adb.run(
        `INSERT INTO custom_roles (name, description) VALUES (?, ?)`,
        name, description,
      );
      audit(req.db, 'role_created', req.user!.id, req.ip || 'unknown', {
        role_id: Number(result.lastInsertRowid), name,
      });
      const row = await adb.get<RoleRow>('SELECT * FROM custom_roles WHERE id = ?', result.lastInsertRowid);
      res.json({ success: true, data: row });
    } catch (err: any) {
      if (String(err?.message || '').includes('UNIQUE')) {
        throw new AppError(`Role '${name}' already exists`, 409);
      }
      throw err;
    }
  }),
);

router.put(
  '/:id',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'role id');
    const description = req.body?.description !== undefined
      ? (req.body.description ? validateTextLength(req.body.description, 200, 'description') : null)
      : undefined;
    const isActive = req.body?.is_active !== undefined ? (req.body.is_active ? 1 : 0) : undefined;

    const fields: string[] = [];
    const params: unknown[] = [];
    if (description !== undefined) {
      fields.push('description = ?');
      params.push(description);
    }
    if (isActive !== undefined) {
      fields.push('is_active = ?');
      params.push(isActive);
    }
    if (!fields.length) throw new AppError('No fields to update', 400);
    params.push(id);
    const result = await adb.run(
      `UPDATE custom_roles SET ${fields.join(', ')} WHERE id = ?`,
      ...params,
    );
    if (result.changes === 0) throw new AppError('Role not found', 404);
    audit(req.db, 'role_updated', req.user!.id, req.ip || 'unknown', { role_id: id });
    const row = await adb.get<RoleRow>('SELECT * FROM custom_roles WHERE id = ?', id);
    res.json({ success: true, data: row });
  }),
);

router.delete(
  '/:id',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const id = parseId(req.params.id, 'role id');
    // Prevent deleting the 4 seeded roles — they're load-bearing.
    const role = await adb.get<RoleRow>('SELECT id, name FROM custom_roles WHERE id = ?', id);
    if (!role) throw new AppError('Role not found', 404);
    if (['admin', 'manager', 'technician', 'cashier'].includes(role.name)) {
      throw new AppError('Cannot delete a built-in role', 400);
    }
    await adb.run('DELETE FROM role_permissions WHERE role_id = ?', id);
    await adb.run('DELETE FROM user_custom_roles WHERE role_id = ?', id);
    await adb.run('DELETE FROM custom_roles WHERE id = ?', id);
    audit(req.db, 'role_deleted', req.user!.id, req.ip || 'unknown', { role_id: id });
    res.json({ success: true, data: { id } });
  }),
);

// ── PERMISSION MATRIX ───────────────────────────────────────────────────────

router.get(
  '/:id/permissions',
  asyncHandler(async (req, res) => {
    // SCAN-1113: permission matrix is user-management surface (settings page).
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    await ensureDefaultPermsSeeded(adb);
    const id = parseId(req.params.id, 'role id');
    const role = await adb.get<RoleRow>('SELECT * FROM custom_roles WHERE id = ?', id);
    if (!role) throw new AppError('Role not found', 404);
    const rows = await adb.all<{ permission_key: string; allowed: number }>(
      `SELECT permission_key, allowed FROM role_permissions WHERE role_id = ?`,
      id,
    );
    const map = new Map(rows.map(r => [r.permission_key, !!r.allowed]));
    const matrix = PERMISSION_KEYS.map(key => ({
      key,
      allowed: map.get(key) ?? false,
    }));
    res.json({ success: true, data: { role, matrix } });
  }),
);

router.put(
  '/:id/permissions',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const db = req.db;
    const id = parseId(req.params.id, 'role id');
    const role = await adb.get<RoleRow>('SELECT * FROM custom_roles WHERE id = ?', id);
    if (!role) throw new AppError('Role not found', 404);

    const updates: Array<{ key: string; allowed: boolean }> = Array.isArray(req.body?.updates)
      ? req.body.updates
      : [];
    if (updates.length === 0) throw new AppError('updates array is required', 400);
    if (updates.length > PERMISSION_KEYS.length) throw new AppError('updates exceeds permission count', 400);

    // Pre-validate every entry before any write so we don't half-apply a
    // matrix update that had a bad key halfway through.
    for (const u of updates) {
      if (typeof u?.key !== 'string' || !PERMISSION_KEYS.includes(u.key)) {
        throw new AppError(`Unknown permission key: ${u?.key}`, 400);
      }
      // Built-in admin must remain the full-access recovery role. User-level
      // denies can narrow a specific admin, but the role template stays whole.
      if (role.name === 'admin' && !u.allowed) {
        throw new AppError('Cannot revoke permissions from the built-in admin role', 400);
      }
    }

    // SCAN-1112: previously each upsert was a separate awaited adb.run, so
    // a failure at entry N left 0..N-1 applied and the admin saw a partial
    // matrix. Wrap the whole batch in a sync transaction via `db` so any
    // mid-loop failure rolls back every prior change.
    const applyTx = db.transaction((): number => {
      const stmt = db.prepare(
        `INSERT INTO role_permissions (role_id, permission_key, allowed)
         VALUES (?, ?, ?)
         ON CONFLICT(role_id, permission_key) DO UPDATE SET allowed = excluded.allowed`,
      );
      let n = 0;
      for (const u of updates) {
        stmt.run(id, u.key, u.allowed ? 1 : 0);
        n++;
      }
      return n;
    });
    const applied = applyTx();

    audit(req.db, 'role_permissions_updated', req.user!.id, req.ip || 'unknown', {
      role_id: id, count: applied,
    });
    res.json({ success: true, data: { role_id: id, applied } });
  }),
);

// ── USER ↔ ROLE ASSIGNMENT (mounted under /api/v1/roles for grouping) ───────

router.get(
  '/users/:userId/permissions',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const userId = parseId(req.params.userId, 'user id');
    const state = await getUserPermissionState(req.asyncDb, userId);
    res.json({ success: true, data: state });
  }),
);

router.put(
  '/users/:userId/permissions',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const db = req.db;
    const userId = parseId(req.params.userId, 'user id');
    const user = await adb.get<{ id: number; role: string }>(
      'SELECT id, role FROM users WHERE id = ? AND is_active = 1',
      userId,
    );
    if (!user) throw new AppError('User not found', 404);

    const updates: Array<{ key?: unknown; allowed?: unknown }> = Array.isArray(req.body?.updates)
      ? req.body.updates
      : [];
    if (updates.length === 0) throw new AppError('updates array is required', 400);
    if (updates.length > PERMISSION_KEYS.length) throw new AppError('updates exceeds permission count', 400);

    const normalized = updates.map((u) => {
      if (typeof u?.key !== 'string' || !PERMISSION_KEYS.includes(u.key)) {
        throw new AppError(`Unknown permission key: ${String(u?.key)}`, 400);
      }
      if (u.allowed !== true && u.allowed !== false && u.allowed !== null) {
        throw new AppError('allowed must be true, false, or null', 400);
      }
      return { key: u.key, allowed: u.allowed };
    });

    const deniesUserManagement = normalized.some(
      update => update.key === PERMISSIONS.USERS_MANAGE && update.allowed === false,
    );
    if (deniesUserManagement) {
      if (req.user?.id === userId) {
        throw new AppError('Cannot deny users.manage for your own account', 400);
      }
      if (user.role === 'admin') {
        const adminCount = await adb.get<{ n: number }>(
          `SELECT COUNT(*) AS n FROM users WHERE role = 'admin' AND is_active = 1`,
        );
        if ((adminCount?.n ?? 0) <= 1) {
          throw new AppError('Cannot deny users.manage for the last active admin', 400);
        }
      }
    }

    const applyTx = db.transaction((): number => {
      const upsert = db.prepare(
        `INSERT INTO user_permissions (user_id, permission_key, allowed, updated_by_user_id, updated_at)
         VALUES (?, ?, ?, ?, datetime('now'))
         ON CONFLICT(user_id, permission_key) DO UPDATE SET
           allowed = excluded.allowed,
           updated_by_user_id = excluded.updated_by_user_id,
           updated_at = datetime('now')`,
      );
      const remove = db.prepare(
        'DELETE FROM user_permissions WHERE user_id = ? AND permission_key = ?',
      );
      let applied = 0;
      for (const update of normalized) {
        if (update.allowed === null) {
          remove.run(userId, update.key);
        } else {
          upsert.run(userId, update.key, update.allowed ? 1 : 0, req.user!.id);
        }
        applied++;
      }
      return applied;
    });
    const applied = applyTx();

    audit(req.db, 'user_permissions_updated', req.user!.id, req.ip || 'unknown', {
      user_id: userId, count: applied,
    });
    const state = await getUserPermissionState(adb, userId);
    res.json({ success: true, data: { user_id: userId, applied, ...state } });
  }),
);

router.put(
  '/users/:userId/role',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = parseId(req.params.userId, 'user id');
    const roleId = parseId(String(req.body?.role_id ?? ''), 'role_id');

    const user = await adb.get<{ id: number; role: string }>(
      'SELECT id, role FROM users WHERE id = ? AND is_active = 1', userId,
    );
    if (!user) throw new AppError('User not found', 404);
    const role = await adb.get<RoleRow & { name: string }>(
      'SELECT id, name FROM custom_roles WHERE id = ? AND is_active = 1',
      roleId,
    );
    if (!role) throw new AppError('Role not found', 404);

    // SEC (post-enrichment audit §6): never allow the last active admin to
    // demote themselves — locks the org out of its own CRM. `users.role` is
    // the canonical role column used by authMiddleware, so we check that
    // table, not user_custom_roles.
    if (user.role === 'admin' && role.name !== 'admin') {
      const adminCount = await adb.get<{ n: number }>(
        `SELECT COUNT(*) AS n FROM users WHERE role = 'admin' AND is_active = 1`,
      );
      if ((adminCount?.n ?? 0) <= 1) {
        throw new AppError(
          'Cannot demote the last active admin — promote another user first',
          400,
        );
      }
    }

    await adb.run(
      `INSERT INTO user_custom_roles (user_id, role_id)
       VALUES (?, ?)
       ON CONFLICT(user_id) DO UPDATE SET role_id = excluded.role_id`,
      userId, roleId,
    );
    audit(req.db, 'user_role_assigned', req.user!.id, req.ip || 'unknown', {
      user_id: userId, role_id: roleId,
    });
    res.json({ success: true, data: { user_id: userId, role_id: roleId } });
  }),
);

router.get(
  '/users/:userId/role',
  asyncHandler(async (req, res) => {
    requireUserManagement(req);
    const adb: AsyncDb = req.asyncDb;
    const userId = parseId(req.params.userId, 'user id');
    const row = await adb.get(
      `SELECT ucr.user_id, ucr.role_id, cr.name AS role_name, cr.description
       FROM user_custom_roles ucr
       LEFT JOIN custom_roles cr ON cr.id = ucr.role_id
       WHERE ucr.user_id = ?`,
      userId,
    );
    res.json({ success: true, data: row || null });
  }),
);

export default router;
