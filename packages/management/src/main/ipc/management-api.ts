/**
 * IPC handlers for the server dashboard.
 * Authentication uses the super admin 2FA flow exclusively.
 * Management API calls use the super admin JWT as Bearer token.
 */
import { ipcMain, shell, app, dialog, BrowserWindow } from 'electron';
import { spawn, spawnSync } from 'child_process';
import path from 'path';
import fs from 'fs';
import { pathToFileURL } from 'url';
import { z } from 'zod';
import {
  apiRequest,
  setSuperAdminToken,
  setServerPort,
  getCertPinningStatus,
} from '../services/api-client.js';
import { allowClose, getMainWindow } from '../window.js';

// ── IPC Input Schemas (validated before any handler logic) ────────────

const SchemaLogin = z.object({
  username: z.string().min(1).max(256),
  password: z.string().min(1).max(1024),
});

const Schema2faVerify = z.object({
  challengeToken: z.string().min(1).max(2048),
  code: z.string().min(1).max(16),
});

const Schema2faSetup = z.object({
  challengeToken: z.string().min(1).max(2048),
});

const SchemaSetPassword = z.object({
  challengeToken: z.string().min(1).max(2048),
  password: z.string().min(1).max(1024),
});

const SchemaSetup = z.object({
  username: z.string().min(1).max(256),
  password: z.string().min(1).max(1024),
});

const SchemaRange = z.object({
  range: z.enum(['1h', '6h', '24h', '7d', '30d']),
});

const SchemaSlug = z.object({
  slug: z.string().min(1).max(256).regex(/^[a-zA-Z0-9_-]+$/),
});

const SchemaId = z.object({
  id: z.string().min(1).max(256),
});

const SchemaRoute = z.object({
  route: z.string().min(1).max(512),
});

const SchemaFilename = z.object({
  filename: z.string().min(1).max(512).regex(/^[^/\\:*?"<>|]+$/),
});

const SchemaAuditUpdateResult = z.object({
  afterSha: z.string().regex(/^[a-f0-9]{7,40}$/i).optional(),
  success: z.boolean(),
  errorMessage: z.string().max(2048).optional(),
});

// AUDIT-MGT-008: Typed audit-log query params. Replaces the raw string
// passthrough (SchemaAuditLogParams accepted any URL-encoded string ≤ 1024 chars
// and forwarded it verbatim as `?${p}`, allowing arbitrary query-string injection).
// Each field is now individually validated; the query string is built main-side
// from the validated fields so the renderer can never inject extra parameters.
const SchemaAuditLogParams = z.object({
  limit: z.number().int().min(1).max(500).optional(),
  offset: z.number().int().min(0).optional(),
  action: z.string().max(128).optional(),
  startDate: z.string().datetime().optional(),
  endDate: z.string().datetime().optional(),
}).strict();

const SchemaBrowseDrive = z.object({
  drivePath: z.string().min(1).max(4096),
});

const SchemaCreateFolder = z.object({
  parentPath: z.string().min(1).max(4096),
  name: z.string().min(1).max(255).regex(/^[^/\\:*?"<>|]+$/),
});

// AUDIT-MGT-003: Zod schemas for super-admin mutation IPC handlers.
// Previously these handlers forwarded raw renderer blobs to the server
// without any IPC-layer validation, allowing arbitrary data to be injected.
// These schemas are the first line of defence — invalid payloads are
// rejected in the main process before the server ever sees them.

// AUDIT-MGT-022: Field names aligned with the canonical server schema
// (super-admin.routes.ts POST /tenants). The server reads `shop_name` and
// `admin_email`; it does NOT accept `company_name` (typo in the prior schema)
// or `admin_password` (the shop admin sets their own password on first login
// via the setup token — no password is provisioned at creation time).
// The renderer (TenantsPage.tsx) already sends `shop_name`, so fixing the
// schema here closes the silent drop that caused tenant creation to always
// fail at the server's `shop_name` required-field check.
const SchemaCreateTenant = z.object({
  slug: z.string().regex(/^[a-z0-9-]{3,64}$/, 'slug must be 3-64 lowercase alphanumeric/hyphen characters'),
  shop_name: z.string().min(1).max(256),
  admin_email: z.string().email().max(256),
  plan: z.enum(['free', 'pro']).optional(),
  admin_first_name: z.string().min(1).max(256).optional(),
  admin_last_name: z.string().min(1).max(256).optional(),
}).strict();

// Mirrors the ALLOWED_CONFIG_KEYS whitelist on the server (super-admin.routes.ts PUT /config).
const SchemaUpdateConfig = z.object({
  management_api_enabled: z.string().optional(),
  management_rate_limit_bypass: z.string().optional(),
}).strict().refine(
  (obj) => Object.keys(obj).length > 0,
  { message: 'At least one config key must be provided' }
);

const SchemaBackupSettings = z.object({
  backup_path: z.string().min(1).max(4096),
  schedule: z.string().max(256),
  retention_days: z.number().int().min(1).max(365),
  encryption_enabled: z.boolean(),
}).strict();

// ── ALLOWED_FILE_ROOTS ────────────────────────────────────────────────
// Only these roots are accepted for admin:browse-drive / admin:create-folder.
// On Windows the common form is a drive letter root (C:\, D:\, ...).
// The list is intentionally conservative and can be extended via config.
const WINDOWS_DRIVE_ROOT_RE = /^[a-zA-Z]:[/\\]$/;

/**
 * SEC-H97 / AUDIT-MGT-002: Validate that the IPC call originates from the
 * trusted renderer that ships with this app. Prevents a compromised or
 * spoofed renderer (e.g., via a navigation exploit) from using privileged
 * main-process channels.
 *
 * Packaged mode: the renderer is always a local file:// URL whose path must
 * resolve to `<appPath>/dist/renderer/`. A mere `startsWith('file://')` is
 * insufficient — an attacker with filesystem write access could load a
 * different file:// page, so we also verify the path prefix.
 *
 * Dev mode: the renderer is served from Vite's dev server. We accept only the
 * exact origin carried in VITE_DEV_SERVER_URL (scheme + host + port). Any
 * other http/https origin is rejected.
 */
export function assertRendererOrigin(event: Electron.IpcMainInvokeEvent): void {
  const url = event.senderFrame?.url ?? '';

  if (app.isPackaged) {
    // Packaged: only a file:// URL under the app's dist/renderer directory.
    // Use pathToFileURL so Windows paths get the correct `file:///C:/…` form
    // (three slashes). A naive `'file://' + path` yields `file://C:/…` and
    // will never match Electron's WHATWG-normalised sender URL.
    // Append path.sep so the resulting URL ends in `/`, preventing a sibling
    // directory like `…/renderer-evil/` from passing the prefix check.
    const rendererDir = path.resolve(app.getAppPath(), 'dist', 'renderer');
    const rendererPrefix = pathToFileURL(rendererDir + path.sep).href;
    if (!url.startsWith(rendererPrefix)) {
      throw new Error(
        `IPC_ORIGIN_REJECTED: expected file:// renderer under "${rendererDir}", got "${url.slice(0, 256)}"`
      );
    }
  } else {
    // Dev: accept only the exact origin of the Vite dev server.
    const devServerUrl = process.env['VITE_DEV_SERVER_URL'];
    if (devServerUrl) {
      try {
        const allowed = new URL(devServerUrl);
        const sender = new URL(url);
        if (
          sender.protocol !== allowed.protocol ||
          sender.hostname !== allowed.hostname ||
          sender.port !== allowed.port
        ) {
          throw new Error(
            `IPC_ORIGIN_REJECTED: expected dev origin "${allowed.origin}", got "${url.slice(0, 256)}"`
          );
        }
      } catch (err) {
        if ((err as Error).message.startsWith('IPC_ORIGIN_REJECTED')) throw err;
        throw new Error(
          `IPC_ORIGIN_REJECTED: could not parse sender URL "${url.slice(0, 256)}": ${(err as Error).message}`
        );
      }
    } else {
      // No dev server URL configured — fall back to file:// only.
      if (!url.startsWith('file://')) {
        throw new Error(
          `IPC_ORIGIN_REJECTED: expected file:// renderer (no VITE_DEV_SERVER_URL set), got "${url.slice(0, 256)}"`
        );
      }
    }
  }
}

/**
 * SEC-H97 / Path-traversal gate for admin:browse-drive and
 * admin:create-folder. Rules:
 *   1. Normalize + resolve the path.
 *   2. Reject UNC paths (\\server\share).
 *   3. Reject any path that still contains ".." after resolution
 *      (belt-and-suspenders; path.resolve() removes them but we
 *      double-check the raw form before resolution).
 *   4. Require the resolved root to be a known drive-letter root on
 *      Windows (C:\, D:\, …). Only paths that begin with an accepted
 *      drive root are forwarded to the server.
 *
 * Returns the normalized absolute path on success; throws on any
 * violation so the calling handler can surface the error to the
 * renderer without touching the server.
 */
function assertSafePath(rawPath: string): string {
  // Pre-normalization: reject UNC patterns immediately.
  if (rawPath.startsWith('\\\\') || rawPath.startsWith('//')) {
    throw new Error('PATH_REJECTED: UNC paths are not permitted');
  }

  // Reject traversal sequences in the raw input before normalization.
  if (rawPath.includes('..')) {
    throw new Error('PATH_REJECTED: path traversal sequences ("..") are not permitted');
  }

  const normalized = path.normalize(rawPath);
  const resolved = path.resolve(normalized);

  // Post-resolution: re-check UNC (path.resolve can produce \\ on Windows).
  if (resolved.startsWith('\\\\')) {
    throw new Error('PATH_REJECTED: resolved path is a UNC path');
  }

  // Post-resolution: ".." should be gone, but re-verify for belt-and-suspenders.
  if (resolved.includes('..')) {
    throw new Error('PATH_REJECTED: path traversal sequences remain after normalization');
  }

  // Require a Windows drive-letter root or a Unix-style root ("/").
  const driveRoot = resolved.slice(0, 3); // e.g. "C:\"
  const isWindowsDrive = WINDOWS_DRIVE_ROOT_RE.test(driveRoot);
  const isUnixRoot = resolved.startsWith('/');
  if (!isWindowsDrive && !isUnixRoot) {
    throw new Error(
      `PATH_REJECTED: path root "${driveRoot}" is not an allowlisted drive root`
    );
  }

  return resolved;
}

/** File used by UP5 rollback: pre-update git commit SHA. */
const PRE_UPDATE_SNAPSHOT_FILE = 'update-pre-commit.txt';

function getSnapshotFilePath(): string {
  return path.join(app.getPath('userData'), PRE_UPDATE_SNAPSHOT_FILE);
}

/** UP5: Capture the current git HEAD so we can roll back a failed update. */
function captureGitHead(root: string): { ok: true; sha: string } | { ok: false; error: string } {
  try {
    const result = spawnSync('git', ['rev-parse', 'HEAD'], {
      cwd: root,
      encoding: 'utf-8',
      timeout: 10_000,
    });
    if (result.status !== 0) {
      return { ok: false, error: result.stderr?.trim() || `git rev-parse exited ${result.status}` };
    }
    const sha = result.stdout.trim();
    if (!/^[a-f0-9]{7,40}$/i.test(sha)) {
      return { ok: false, error: `Unexpected git SHA format: ${sha}` };
    }
    return { ok: true, sha };
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : 'Unknown error' };
  }
}

function writeSnapshot(sha: string): void {
  try {
    const dir = app.getPath('userData');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    fs.writeFileSync(getSnapshotFilePath(), sha, 'utf-8');
  } catch (err) {
    console.error('[Update] Failed to persist rollback snapshot:', err);
  }
}

function readSnapshot(): string | null {
  try {
    const p = getSnapshotFilePath();
    if (!fs.existsSync(p)) return null;
    const raw = fs.readFileSync(p, 'utf-8').trim();
    if (!/^[a-f0-9]{7,40}$/i.test(raw)) return null;
    return raw;
  } catch {
    return null;
  }
}

function clearSnapshot(): void {
  try {
    const p = getSnapshotFilePath();
    if (fs.existsSync(p)) fs.unlinkSync(p);
  } catch {
    /* ignore */
  }
}

// ── SEC-H95: Signed-tag verification ─────────────────────────────────
//
// AUDIT-MGT-018: UPDATE_SKIP_TAG_VERIFY is evaluated per-call (inside
// verifyLatestSignedTag) rather than at module-load time. Module-load
// evaluation locks in the value at startup, preventing an operator from
// toggling the env var for a single update session without restarting the
// whole dashboard. More importantly, a static module-level constant is
// invisible to runtime audit tooling — moving the check into the handler
// body means every bypass is logged and reported to the audit server.

/**
 * SEC-H95 / AUDIT-MGT-018: Fetch remote tags and verify the latest semver
 * tag carries a valid GPG signature.
 *
 * Flow:
 *   1. `git fetch --tags --quiet` — pull tag objects from origin.
 *   2. `git describe --tags --abbrev=0 --match 'v*'` — find the latest tag
 *      reachable from HEAD or any fetched ref.  Falls back to
 *      `git tag --sort=-version:refname` if describe finds nothing.
 *   3. `git verify-tag <tag>` — exits 0 iff the tag object carries a good
 *      GPG signature.  Exits non-zero for unsigned, expired, or revoked.
 *
 * AUDIT-MGT-018: UPDATE_SKIP_TAG_VERIFY is evaluated HERE (per-call), not
 * at module load. When the bypass is active the fact is logged to
 * dashboard.log. The caller is responsible for also reporting to the audit
 * server with `tagVerifyBypass: true`.
 *
 * Returns `{ ok: true, tag, bypassed? }` on success, or
 * `{ ok: false, error, tag? }` when the gate fires or GPG is unavailable.
 */
function verifyLatestSignedTag(root: string): {
  ok: boolean;
  tag: string | null;
  bypassed?: boolean;
  error?: string;
} {
  // AUDIT-MGT-018: Evaluate per-call so the bypass cannot be baked in at
  // startup and must be present in the process environment at the moment
  // the operator clicks "Install Update".
  const skipTagVerify = process.env['UPDATE_SKIP_TAG_VERIFY'] === 'true';
  if (skipTagVerify) {
    console.warn(
      '[Update] SEC-H95 / AUDIT-MGT-018: UPDATE_SKIP_TAG_VERIFY is set — ' +
      'signed-tag gate BYPASSED. This bypass is being reported to the audit log.'
    );
    return { ok: true, tag: null, bypassed: true };
  }

  // Step 1: fetch tags from origin (already verified remote by githubUpdater).
  const fetchResult = spawnSync('git', ['fetch', '--tags', '--quiet'], {
    cwd: root,
    encoding: 'utf-8',
    timeout: 30_000,
  });
  if (fetchResult.status !== 0) {
    return {
      ok: false,
      tag: null,
      error: `git fetch --tags failed: ${fetchResult.stderr?.trim() || `exit ${fetchResult.status}`}`,
    };
  }

  // Step 2: find the latest semver tag.
  let tag: string | null = null;
  const describeResult = spawnSync(
    'git',
    ['describe', '--tags', '--abbrev=0', '--match', 'v*'],
    { cwd: root, encoding: 'utf-8', timeout: 10_000 }
  );
  if (describeResult.status === 0) {
    tag = describeResult.stdout.trim();
  } else {
    // Fallback: list tags sorted by version, pick highest.
    const listResult = spawnSync(
      'git',
      ['tag', '--sort=-version:refname', '--list', 'v*'],
      { cwd: root, encoding: 'utf-8', timeout: 10_000 }
    );
    if (listResult.status === 0) {
      const first = listResult.stdout.trim().split('\n')[0]?.trim();
      if (first) tag = first;
    }
  }

  if (!tag || !/^v\d/.test(tag)) {
    return {
      ok: false,
      tag: null,
      error:
        'Update blocked: no semver tag found in repository. ' +
        'Create and sign a release tag (e.g. git tag -s v1.0.0) before updating.',
    };
  }

  // Step 3: cryptographic signature check on the tag object.
  const verifyResult = spawnSync('git', ['verify-tag', tag], {
    cwd: root,
    encoding: 'utf-8',
    timeout: 15_000,
  });

  if (verifyResult.status !== 0) {
    return {
      ok: false,
      tag,
      error:
        `Update blocked: latest git tag "${tag}" is not signed or signature invalid. ` +
        `GPG output: ${(verifyResult.stderr || verifyResult.stdout || '').trim().slice(0, 512)}`,
    };
  }

  console.log(`[Update] SEC-H95: tag "${tag}" signature verified OK`);
  return { ok: true, tag };
}

/** True if `child` is inside (or equal to) `parent`, using resolved absolute paths. */
function isPathUnder(child: string, parent: string): boolean {
  const resolvedChild = path.resolve(child);
  const resolvedParent = path.resolve(parent);
  if (resolvedChild === resolvedParent) return true;
  const rel = path.relative(resolvedParent, resolvedChild);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

/**
 * MGT-031: Replace occurrences of the trusted project root path in error
 * messages with the placeholder `<root>` so that absolute filesystem paths
 * are never forwarded to the renderer or audit log.
 *
 * Apply ONLY to messages returned from git operations and fs operations where
 * the path may appear verbatim (e.g. git's stderr output on a failed reset,
 * or Node.js error messages that include the file path). Do NOT apply to
 * every error — only to those where the path could realistically appear.
 */
function sanitizeErrorMessage(msg: string, root: string): string {
  return msg.replace(
    new RegExp(root.replace(/[/\\]/g, '[/\\\\]'), 'g'),
    '<root>'
  );
}

/**
 * AUD-20260414-M2 / SECURITY (EL3 / EL7): Locate the project root for
 * `update.bat` from TRUSTED electron anchors only.
 *
 * Prior implementations walked upward from `process.execPath` (or
 * `app.getAppPath()`) looking for a marker file and then only verified that
 * the candidate still sat under the filesystem DRIVE root (`C:\`). That is
 * effectively no check at all: a marker-bearing ancestor anywhere on the
 * same drive would be accepted, letting a misplaced install silently run
 * from arbitrary locations with no integrity gate.
 *
 * This implementation uses deterministic, layout-specific candidates and
 * requires the resolved root to sit INSIDE the trusted anchor itself:
 *
 *   - Packaged (`app.isPackaged === true`): the only accepted root is
 *     `<process.resourcesPath>/crm-source`, populated by electron-builder
 *     `extraResources` (see electron-builder.yml). If resourcesPath is
 *     missing or crm-source doesn't exist, we fail loudly with an
 *     installation-integrity error rather than walking the filesystem.
 *
 *   - Dev (`app.isPackaged === false`): the repo root is reached by
 *     `app.getAppPath()` + `../..` (monorepo layout `packages/management`
 *     -> repo root). We verify the project-root marker set is present AND
 *     that the resolved path is inside the resolved app-path's parent
 *     chain (no `..`-escapes past the anchor parent).
 *
 * Both branches require the full project-root marker set (package.json,
 * packages/server/package.json, and at least one of
 * ecosystem.config.js / install.bat / setup.bat) — sibling-marker
 * scenarios are explicitly rejected.
 */
function hasProjectRootMarkers(dir: string): boolean {
  const coreMarkers =
    fs.existsSync(path.join(dir, 'package.json')) &&
    fs.existsSync(path.join(dir, 'packages', 'server', 'package.json'));
  if (!coreMarkers) return false;
  const auxMarker =
    fs.existsSync(path.join(dir, 'ecosystem.config.js')) ||
    fs.existsSync(path.join(dir, 'install.bat')) ||
    fs.existsSync(path.join(dir, 'setup.bat'));
  return auxMarker;
}

function resolveTrustedProjectRoot(): string | null {
  // Packaged build: only the bundled crm-source directory is trusted.
  if (app.isPackaged) {
    const resourcesPath = typeof process.resourcesPath === 'string' ? process.resourcesPath : null;
    if (!resourcesPath || !fs.existsSync(resourcesPath)) {
      throw new Error(
        'Installation integrity check failed — reinstall required (process.resourcesPath missing or inaccessible).'
      );
    }
    const anchor = path.resolve(resourcesPath);
    const candidate = path.resolve(path.join(anchor, 'crm-source'));
    if (!isPathUnder(candidate, anchor)) return null;
    if (!fs.existsSync(candidate)) {
      throw new Error(
        'Installation integrity check failed — reinstall required (crm-source missing from packaged resources).'
      );
    }
    return hasProjectRootMarkers(candidate) ? candidate : null;
  }

  // Dev build: monorepo layout — app.getAppPath() === <repo>/packages/management.
  // The legitimate repo root is two levels above. We do NOT walk the
  // filesystem; the candidate is fixed by the known monorepo layout and
  // rejected unless the full marker set is present (sibling / ancestor
  // marker files elsewhere on disk are never accepted).
  const appPath = typeof app.getAppPath === 'function' ? app.getAppPath() : null;
  if (!appPath) return null;
  const resolvedAppPath = path.resolve(appPath);
  const devRepoRoot = path.resolve(resolvedAppPath, '..', '..');
  if (!hasProjectRootMarkers(devRepoRoot)) return null;
  return devRepoRoot;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function wrapHandler(fn: (...args: any[]) => Promise<any>) {
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  return async (...args: any[]) => {
    try {
      return await fn(...args);
    } catch (err: any) {
      // MGT-021: Differentiate network errors from generic handler failures.
      // Callers can inspect `offline: true` to show a "server offline" state
      // rather than a generic error toast.
      const code = err?.code || err?.cause?.code;
      const isNetwork =
        code === 'ECONNREFUSED' ||
        code === 'ETIMEDOUT' ||
        code === 'ENOTFOUND' ||
        code === 'ENETUNREACH';
      return {
        success: false,
        message: String(err?.message || 'Unknown error'),
        offline: isNetwork,
      };
    }
  };
}

export function registerManagementIpc(): void {
  // ── Discover server port from .env so the API client connects to the
  // right port in both local (PORT=443) and hosted (PORT=8443, etc.) setups.
  //
  // NOTE: resolveTrustedProjectRoot() throws on a broken packaged install
  // (missing resourcesPath / missing crm-source). We catch that here so
  // the dashboard can still start up and surface a real error in the UI
  // rather than dying during module init; the handlers below that need a
  // root will re-call the resolver and return a structured error instead.
  let root: string | null = null;
  try {
    root = resolveTrustedProjectRoot();
  } catch (err) {
    console.error(
      '[Dashboard] Installation integrity check failed during IPC init:',
      err instanceof Error ? err.message : String(err)
    );
  }
  if (root) {
    const envPath = path.resolve(path.join(root, '.env'));
    // Belt-and-braces: assert the resolved .env path is inside the root.
    if (!isPathUnder(envPath, root)) {
      console.warn('[Dashboard] .env path escaped trusted root; refusing to read:', envPath);
    } else if (fs.existsSync(envPath)) {
      try {
        const content = fs.readFileSync(envPath, 'utf-8');
        const match = content.match(/^PORT\s*=\s*['"]?(\d+)['"]?/m);
        if (match) {
          const port = parseInt(match[1], 10);
          if (port > 0 && port < 65536) {
            setServerPort(port);
            console.log(`[Dashboard] API client targeting port ${port} (from .env)`);
          }
        }
      } catch { /* ignore — falls back to 443 */ }
    }
  }

  // ── Setup Status (no auth needed) ──────────────────────────────

  ipcMain.handle('management:setup-status', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/setup-status', null, 'none');
    return res.body;
  }));

  // ── Super-Admin Auth (2FA flow) ────────────────────────────────

  ipcMain.handle('super-admin:login', wrapHandler(async (event, username: unknown, password: unknown) => {
    assertRendererOrigin(event);
    const args = SchemaLogin.parse({ username, password });
    const res = await apiRequest('POST', '/super-admin/api/login', args, 'none');
    return res.body;
  }));

  ipcMain.handle('super-admin:2fa-verify', wrapHandler(async (event, challengeToken: unknown, code: unknown) => {
    assertRendererOrigin(event);
    const args = Schema2faVerify.parse({ challengeToken, code });
    const res = await apiRequest('POST', '/super-admin/api/login/2fa-verify', args, 'none');
    if (res.body.success && (res.body.data as { token?: string })?.token) {
      setSuperAdminToken((res.body.data as { token: string }).token);
    }
    return res.body;
  }));

  ipcMain.handle('super-admin:2fa-setup', wrapHandler(async (event, challengeToken: unknown) => {
    assertRendererOrigin(event);
    const { challengeToken: ct } = Schema2faSetup.parse({ challengeToken });
    const res = await apiRequest('POST', '/super-admin/api/login/2fa-setup', { challengeToken: ct }, 'none');
    return res.body;
  }));

  ipcMain.handle('super-admin:set-password', wrapHandler(async (event, challengeToken: unknown, password: unknown) => {
    assertRendererOrigin(event);
    const args = SchemaSetPassword.parse({ challengeToken, password });
    const res = await apiRequest('POST', '/super-admin/api/login/set-password', args, 'none');
    return res.body;
  }));

  // Local-only mutation: clears the cached super-admin JWT in this process.
  // (Server-side invalidation is a TODO — the server doesn't yet expose a
  // logout endpoint for super-admin sessions.)
  ipcMain.handle('management:logout', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    setSuperAdminToken(null);
    return { success: true, data: { local: true } };
  }));

  // ── Stats (management API — needs super admin JWT) ─────────────

  ipcMain.handle('management:setup', wrapHandler(async (event, username: unknown, password: unknown) => {
    assertRendererOrigin(event);
    const args = SchemaSetup.parse({ username, password });
    const res = await apiRequest('POST', '/api/v1/management/setup', args, 'none');
    return res.body;
  }));

  ipcMain.handle('management:get-stats', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/stats');
    return res.body;
  }));

  ipcMain.handle('management:get-stats-history', wrapHandler(async (event, range: unknown) => {
    assertRendererOrigin(event);
    const { range: r } = SchemaRange.parse({ range });
    const res = await apiRequest('GET', `/api/v1/management/stats/history?range=${encodeURIComponent(r)}`);
    return res.body;
  }));

  // ── Super-Admin Dashboard ──────────────────────────────────────

  ipcMain.handle('super-admin:get-dashboard', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/super-admin/api/dashboard');
    return res.body;
  }));

  // ── Tenants (super-admin API) ──────────────────────────────────

  ipcMain.handle('super-admin:list-tenants', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/super-admin/api/tenants');
    return res.body;
  }));

  ipcMain.handle('super-admin:create-tenant', wrapHandler(async (event, data: unknown) => {
    assertRendererOrigin(event);
    // AUDIT-MGT-003: Validate at the IPC boundary — reject unknown/invalid
    // fields before forwarding anything to the server.
    const parsed = SchemaCreateTenant.safeParse(data);
    if (!parsed.success) {
      return { success: false, message: parsed.error.errors[0]?.message ?? 'Invalid tenant data' };
    }
    const res = await apiRequest('POST', '/super-admin/api/tenants', parsed.data);
    return res.body;
  }));

  ipcMain.handle('super-admin:get-tenant', wrapHandler(async (event, slug: unknown) => {
    assertRendererOrigin(event);
    const { slug: s } = SchemaSlug.parse({ slug });
    const res = await apiRequest('GET', `/super-admin/api/tenants/${encodeURIComponent(s)}`);
    return res.body;
  }));

  ipcMain.handle('super-admin:suspend-tenant', wrapHandler(async (event, slug: unknown) => {
    assertRendererOrigin(event);
    const { slug: s } = SchemaSlug.parse({ slug });
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(s)}/suspend`);
    return res.body;
  }));

  ipcMain.handle('super-admin:activate-tenant', wrapHandler(async (event, slug: unknown) => {
    assertRendererOrigin(event);
    const { slug: s } = SchemaSlug.parse({ slug });
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(s)}/activate`);
    return res.body;
  }));

  ipcMain.handle('super-admin:delete-tenant', wrapHandler(async (event, slug: unknown) => {
    assertRendererOrigin(event);
    const { slug: s } = SchemaSlug.parse({ slug });
    const res = await apiRequest('DELETE', `/super-admin/api/tenants/${encodeURIComponent(s)}`);
    return res.body;
  }));

  // TPH6: additive repair for any tenant not in 'active' status.
  ipcMain.handle('super-admin:repair-tenant', wrapHandler(async (event, slug: unknown) => {
    assertRendererOrigin(event);
    const { slug: s } = SchemaSlug.parse({ slug });
    const res = await apiRequest('POST', `/super-admin/api/tenants/${encodeURIComponent(s)}/repair`);
    return res.body;
  }));

  // ── Platform Config ────────────────────────────────────────────

  ipcMain.handle('super-admin:get-config', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/super-admin/api/config');
    return res.body;
  }));

  ipcMain.handle('super-admin:update-config', wrapHandler(async (event, updates: unknown) => {
    assertRendererOrigin(event);
    // AUDIT-MGT-003: Validate at the IPC boundary — only the server's known
    // ALLOWED_CONFIG_KEYS are accepted (management_api_enabled,
    // management_rate_limit_bypass). Unknown keys are rejected here before
    // they reach the server's own whitelist check.
    const parsed = SchemaUpdateConfig.safeParse(updates);
    if (!parsed.success) {
      return { success: false, message: parsed.error.errors[0]?.message ?? 'Invalid config update' };
    }
    const res = await apiRequest('PUT', '/super-admin/api/config', parsed.data);
    return res.body;
  }));

  // ── Audit Log ──────────────────────────────────────────────────

  ipcMain.handle('super-admin:get-audit-log', wrapHandler(async (event, params?: unknown) => {
    assertRendererOrigin(event);
    // AUDIT-MGT-008: Validate each field individually; build the query string
    // here in the main process from validated values only, so the renderer
    // cannot inject arbitrary query parameters.
    const validated = SchemaAuditLogParams.parse(params ?? {});
    const qs = new URLSearchParams();
    if (validated.limit !== undefined) qs.set('limit', String(validated.limit));
    if (validated.offset !== undefined) qs.set('offset', String(validated.offset));
    if (validated.action !== undefined) qs.set('action', validated.action);
    if (validated.startDate !== undefined) qs.set('startDate', validated.startDate);
    if (validated.endDate !== undefined) qs.set('endDate', validated.endDate);
    const qsStr = qs.toString();
    const res = await apiRequest('GET', `/super-admin/api/audit-log${qsStr ? `?${qsStr}` : ''}`);
    return res.body;
  }));

  // ── Sessions ───────────────────────────────────────────────────

  ipcMain.handle('super-admin:get-sessions', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/super-admin/api/sessions');
    return res.body;
  }));

  ipcMain.handle('super-admin:revoke-session', wrapHandler(async (event, id: unknown) => {
    assertRendererOrigin(event);
    const { id: sessionId } = SchemaId.parse({ id });
    const res = await apiRequest('DELETE', `/super-admin/api/sessions/${encodeURIComponent(sessionId)}`);
    return res.body;
  }));

  // ── Crashes (management API) ───────────────────────────────────

  ipcMain.handle('management:get-crashes', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/crashes');
    return res.body;
  }));

  ipcMain.handle('management:get-crash-stats', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/crash-stats');
    return res.body;
  }));

  ipcMain.handle('management:get-disabled-routes', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/disabled-routes');
    return res.body;
  }));

  ipcMain.handle('management:reenable-route', wrapHandler(async (event, route: unknown) => {
    assertRendererOrigin(event);
    const { route: r } = SchemaRoute.parse({ route });
    const res = await apiRequest('POST', '/api/v1/management/reenable-route', { route: r });
    return res.body;
  }));

  ipcMain.handle('management:clear-crashes', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('POST', '/api/v1/management/clear-crashes');
    return res.body;
  }));

  // ── Updates ────────────────────────────────────────────────────

  ipcMain.handle('management:get-update-status', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/management/update-status');
    return res.body;
  }));

  ipcMain.handle('management:check-updates', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('POST', '/api/v1/management/check-updates');
    return res.body;
  }));

  ipcMain.handle('management:perform-update', async (event) => {
    assertRendererOrigin(event);
    // SECURITY (EL3 / EL7 / AUD-20260414-M2): Resolve project root from
    // trusted Electron anchors only. Integrity failures on a packaged
    // install surface as INSTALLATION_INTEGRITY_FAILED rather than a
    // silent "root not found".
    let root: string | null;
    try {
      root = resolveTrustedProjectRoot();
    } catch (err) {
      return {
        success: false,
        error: 'INSTALLATION_INTEGRITY_FAILED',
        message: err instanceof Error ? err.message : 'Installation integrity check failed — reinstall required.',
      };
    }
    if (!root) {
      return {
        success: false,
        error: 'PROJECT_ROOT_NOT_FOUND',
        message: 'Could not locate a trusted project root containing ecosystem.config.js or setup.bat.',
      };
    }

    const updateBat = path.resolve(path.join(root, 'scripts', 'update.bat'));

    // Guard against `..` escapes / symlink trickery — the resolved script
    // must still live under the trusted root.
    if (!isPathUnder(updateBat, root)) {
      return {
        success: false,
        error: 'UNTRUSTED_UPDATE_PATH',
        message: `Resolved update script "${updateBat}" is outside the trusted root "${root}".`,
      };
    }

    if (!fs.existsSync(updateBat)) {
      return {
        success: false,
        error: 'UPDATE_SCRIPT_MISSING',
        message: `Update script not found at: ${updateBat}`,
      };
    }

    // SEC-H95 (supply-chain): Verify the latest signed git tag BEFORE we
    // touch the file system or spawn anything. An unsigned or tampered tag
    // means the release was not approved by the key holder — abort hard.
    const tagCheck = verifyLatestSignedTag(root);
    if (!tagCheck.ok) {
      console.error('[Update] SEC-H95 tag verification failed:', tagCheck.error);
      return {
        success: false,
        error: 'TAG_VERIFICATION_FAILED',
        message: tagCheck.error ?? 'Update blocked: latest git tag is not signed or signature invalid',
      };
    }

    // SEC-H95: Explicit operator confirmation before any destructive change.
    // Default button is Cancel so an accidental keyboard press cannot trigger.
    const tagLabel = tagCheck.tag ?? 'latest';
    const ownerWindow = BrowserWindow.getFocusedWindow() ?? BrowserWindow.getAllWindows()[0] ?? null;
    const msgBoxOptions: Electron.MessageBoxOptions = {
      type: 'question',
      buttons: ['Install', 'Cancel'],
      defaultId: 1,         // Cancel is the safe default
      cancelId: 1,
      title: 'Confirm Update',
      message: `Install update to ${tagLabel}?`,
      detail:
        'The server will stop, rebuild from the latest signed tag, and restart. ' +
        'This dashboard will close and reopen automatically.\n\n' +
        'Click Install only if you intend to apply this update now.',
      noLink: true,
    };
    // Use the window-scoped overload when a window is available so the dialog
    // is modal to the window; fall back to the global overload otherwise.
    const confirmResult = ownerWindow
      ? await dialog.showMessageBox(ownerWindow, msgBoxOptions)
      : await dialog.showMessageBox(msgBoxOptions);

    if (confirmResult.response !== 0) {
      console.log('[Update] Operator cancelled update at confirm dialog.');
      return {
        success: false,
        error: 'UPDATE_CANCELLED',
        message: 'Update cancelled by operator.',
      };
    }

    // UP5: Snapshot the current git HEAD before we spawn update.bat. If the
    // update crashes (failed build, bad merge, etc.) the UpdatesPage can
    // trigger `management:rollback-update` to restore this commit.
    const head = captureGitHead(root);
    if (head.ok) {
      writeSnapshot(head.sha);
      console.log('[Update] Captured pre-update commit:', head.sha);
    } else {
      console.warn('[Update] Could not capture pre-update commit (rollback disabled):', head.error);
    }

    // UP6 / AUDIT-MGT-018: Tell the server to record a 'launched' audit
    // entry BEFORE we spawn update.bat. This guarantees that if the new
    // server never comes back up, the master audit log still has a row
    // showing "update attempted from <ip> at <ts> starting from <sha>".
    // When the signed-tag bypass was active, we include `tagVerifyBypass: true`
    // so the audit record reflects the degraded security state.
    //
    // We fire-and-forget: if the local server is unreachable or returns an
    // error we still want the update to run. The worst case is an audit
    // row is missing — the update itself is not security-gated by this
    // call.
    try {
      const beforeSha = head.ok ? head.sha : null;
      const res = await apiRequest(
        'POST',
        '/api/v1/management/audit-update-launch',
        {
          beforeSha,
          source: 'dashboard',
          // AUDIT-MGT-018: Flag bypass so it is recorded in the audit trail.
          ...(tagCheck.bypassed ? { tagVerifyBypass: true } : {}),
        }
      );
      if (!res.body?.success) {
        console.warn('[Update] audit-update-launch endpoint returned failure:', res.body?.message);
      }
    } catch (err) {
      console.warn(
        '[Update] Failed to record audit-update-launch (continuing with update):',
        err instanceof Error ? err.message : String(err)
      );
    }

    // UP4: We need to report honest spawn success/failure before the dashboard
    // quits. Launch the child, then await either a synchronous spawn error or
    // the 'spawn' event (fired once the process is actually created). On
    // success we schedule the dashboard to close so the bat script can kill
    // the server cleanly and rebuild.
    try {
      // AUDIT-MGT-014: Strip env vars that can alter Node.js / Electron
      // behaviour and allow privilege escalation via a spawned script.
      // eslint-disable-next-line @typescript-eslint/no-unused-vars
      const { ELECTRON_RUN_AS_NODE, NODE_OPTIONS, NODE_PATH, ...cleanEnv } = process.env;
      const child = spawn('cmd.exe', ['/c', updateBat], {
        cwd: root,
        detached: true,
        stdio: 'ignore',
        // Inherit Electron's environment (has PATH with git, npm, node)
        // minus the vars that can redirect / override Node execution.
        env: cleanEnv,
      });

      const spawnResult = await new Promise<{ ok: true } | { ok: false; error: string }>((resolve) => {
        let settled = false;
        const done = (value: { ok: true } | { ok: false; error: string }): void => {
          if (settled) return;
          settled = true;
          resolve(value);
        };

        child.once('error', (err: Error) => {
          done({ ok: false, error: err.message });
        });
        child.once('spawn', () => {
          done({ ok: true });
        });
        // Child may exit immediately with non-zero before we detach.
        child.once('exit', (code, signal) => {
          if (code !== null && code !== 0) {
            done({ ok: false, error: `update.bat exited immediately with code ${code}` });
          } else if (signal) {
            done({ ok: false, error: `update.bat killed with signal ${signal}` });
          } else {
            done({ ok: true });
          }
        });

        // Safety timeout — if neither spawn nor error fire in 5s, assume it
        // actually started (detached cmd windows usually have).
        setTimeout(() => done({ ok: true }), 5_000);
      });

      if (!spawnResult.ok) {
        console.error('[Update] Failed to launch:', spawnResult.error);
        return {
          success: false,
          error: 'UPDATE_LAUNCH_FAILED',
          message: spawnResult.error,
        };
      }

      child.unref();
      console.log('[Update] Launched update.bat (PID:', child.pid, ')');

      // Close the dashboard after a short delay so the update script can kill it cleanly
      setTimeout(() => {
        allowClose();
        app.quit();
      }, 2000);

      return {
        success: true,
        data: {
          success: true,
          output: 'Update started. Dashboard will close and reopen after rebuild.',
        },
      };
    } catch (err: unknown) {
      const rawMessage = err instanceof Error ? err.message : 'Unknown error';
      console.error('[Update] Failed to launch:', rawMessage);
      return {
        success: false,
        error: 'UPDATE_LAUNCH_FAILED',
        // MGT-031: sanitize — spawn errors may include the script path.
        message: 'Failed to launch update: ' + sanitizeErrorMessage(rawMessage, root),
      };
    }
  });

  // UP5: Rollback support ─────────────────────────────────────────
  // After a failed update the dashboard reopens with an option to restore
  // the previous git checkout. `get-rollback-info` tells the renderer
  // whether a snapshot exists; `rollback-update` executes the restore.

  ipcMain.handle('management:get-rollback-info', async (event) => {
    assertRendererOrigin(event);
    const sha = readSnapshot();
    if (!sha) {
      return { success: true, data: { available: false } };
    }
    return { success: true, data: { available: true, sha } };
  });

  ipcMain.handle('management:rollback-update', async (event) => {
    assertRendererOrigin(event);
    const sha = readSnapshot();
    if (!sha) {
      return {
        success: false,
        error: 'NO_ROLLBACK_SNAPSHOT',
        code: 404,
        message: 'No rollback snapshot is available.',
      };
    }

    let root: string | null;
    try {
      root = resolveTrustedProjectRoot();
    } catch (err) {
      return {
        success: false,
        error: 'INSTALLATION_INTEGRITY_FAILED',
        code: 500,
        message: err instanceof Error ? err.message : 'Installation integrity check failed — reinstall required.',
      };
    }
    if (!root) {
      return {
        success: false,
        error: 'PROJECT_ROOT_NOT_FOUND',
        code: 500,
        message: 'Could not locate a trusted project root for rollback.',
      };
    }

    // Strict SHA validation — the only value we pass to git is the SHA we
    // captured before the update. Re-validate at the point of use.
    if (!/^[a-f0-9]{7,40}$/i.test(sha)) {
      return {
        success: false,
        error: 'INVALID_SNAPSHOT',
        code: 500,
        message: `Stored rollback SHA is malformed: ${sha}`,
      };
    }

    try {
      const result = spawnSync('git', ['reset', '--hard', sha], {
        cwd: root,
        encoding: 'utf-8',
        timeout: 30_000,
      });
      if (result.status !== 0) {
        // MGT-031: strip the absolute root path from git's stderr before
        // forwarding to the renderer.
        const rawMsg = result.stderr?.trim() || `git reset --hard exited ${result.status}`;
        return {
          success: false,
          error: 'ROLLBACK_FAILED',
          code: 500,
          message: sanitizeErrorMessage(rawMsg, root),
        };
      }
      clearSnapshot();
      console.log('[Update] Rolled back to', sha);
      return { success: true, data: { sha, stdout: result.stdout.trim() } };
    } catch (err) {
      const rawMessage = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'ROLLBACK_FAILED',
        code: 500,
        // MGT-031: sanitize — catch messages may include the cwd path.
        message: sanitizeErrorMessage(rawMessage, root),
      };
    }
  });

  ipcMain.handle('management:clear-rollback', async (event) => {
    assertRendererOrigin(event);
    clearSnapshot();
    return { success: true };
  });

  // UP6: Called by the UpdatesPage after the dashboard reopens so the
  // server can record the final outcome (success/failure + after_sha).
  // Renderer passes `{ afterSha?, success, errorMessage? }`. The before_sha
  // is looked up from the persisted rollback snapshot so the renderer
  // doesn't have to thread it through.
  ipcMain.handle(
    'management:audit-update-result',
    wrapHandler(async (event, payload: unknown) => {
      assertRendererOrigin(event);
      const validated = SchemaAuditUpdateResult.parse(payload);
      const beforeSha = readSnapshot();
      const res = await apiRequest(
        'POST',
        '/api/v1/management/audit-update-result',
        {
          beforeSha,
          afterSha: validated.afterSha ?? null,
          success: validated.success,
          errorMessage: validated.errorMessage ?? null,
        }
      );
      return res.body;
    })
  );

  // ── Server Control (REST fallback) ─────────────────────────────

  ipcMain.handle('management:restart-server', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('POST', '/api/v1/management/restart');
    return res.body;
  }));

  ipcMain.handle('management:stop-server', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('POST', '/api/v1/management/stop');
    return res.body;
  }));

  // ── Backup ─────────────────────────────────────────────────────

  ipcMain.handle('admin:get-status', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/admin/status');
    return res.body;
  }));

  ipcMain.handle('admin:list-drives', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/admin/drives');
    return res.body;
  }));

  ipcMain.handle('admin:browse-drive', wrapHandler(async (event, drivePath: unknown) => {
    assertRendererOrigin(event);
    // SEC-H97: validate input shape, then apply path normalization + UNC/traversal gate.
    const { drivePath: rawPath } = SchemaBrowseDrive.parse({ drivePath });
    const safePath = assertSafePath(rawPath);
    const res = await apiRequest('GET', `/api/v1/admin/drives/browse?path=${encodeURIComponent(safePath)}`);
    return res.body;
  }));

  ipcMain.handle('admin:create-folder', wrapHandler(async (event, parentPath: unknown, name: unknown) => {
    assertRendererOrigin(event);
    // SEC-H97: validate input shape, then apply path normalization + UNC/traversal gate.
    const { parentPath: rawParent, name: folderName } = SchemaCreateFolder.parse({ parentPath, name });
    const safePath = assertSafePath(rawParent);
    const res = await apiRequest('POST', '/api/v1/admin/drives/mkdir', { path: safePath, name: folderName });
    return res.body;
  }));

  ipcMain.handle('admin:list-backups', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('GET', '/api/v1/admin/backups');
    return res.body;
  }));

  ipcMain.handle('admin:run-backup', wrapHandler(async (event) => {
    assertRendererOrigin(event);
    const res = await apiRequest('POST', '/api/v1/admin/backup');
    return res.body;
  }));

  ipcMain.handle('admin:update-backup-settings', wrapHandler(async (event, settings: unknown) => {
    assertRendererOrigin(event);
    // AUDIT-MGT-003/004: Validate at the IPC boundary — reject unknown keys
    // and enforce types before forwarding to the server.
    const parsed = SchemaBackupSettings.safeParse(settings);
    if (!parsed.success) {
      return { success: false, message: parsed.error.errors[0]?.message ?? 'Invalid backup settings' };
    }
    const res = await apiRequest('PUT', '/api/v1/admin/backup-settings', parsed.data);
    return res.body;
  }));

  ipcMain.handle('admin:delete-backup', wrapHandler(async (event, filename: unknown) => {
    assertRendererOrigin(event);
    const { filename: f } = SchemaFilename.parse({ filename });
    const res = await apiRequest('DELETE', `/api/v1/admin/backups/${encodeURIComponent(f)}`);
    return res.body;
  }));

  // ── Utilities ──────────────────────────────────────────────────

  // T7: previously these all returned { success: true } unconditionally.
  // They now report real failure when there is no window or when the
  // underlying Electron call throws.
  ipcMain.handle('system:open-browser', async (event) => {
    assertRendererOrigin(event);
    try {
      await shell.openExternal('https://localhost');
      return { success: true };
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      return {
        success: false,
        error: 'OPEN_BROWSER_FAILED',
        code: 500,
        message: `Failed to open browser: ${message}`,
      };
    }
  });

  ipcMain.handle('system:close-dashboard', (event) => {
    assertRendererOrigin(event);
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to close.',
      };
    }
    allowClose();
    win.close();
    return { success: true };
  });

  ipcMain.handle('system:minimize', (event) => {
    assertRendererOrigin(event);
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to minimize.',
      };
    }
    win.minimize();
    return { success: true };
  });

  // AUDIT-MGT-006: Expose cert-pinning status so the renderer can warn the
  // operator when TLS fingerprint pinning is disabled (server.cert absent on
  // first run). The renderer shows a visible banner — operators then know the
  // connection to the local CRM is unverified until the server generates certs.
  ipcMain.handle('system:get-cert-pinning-status', (event) => {
    assertRendererOrigin(event);
    const status = getCertPinningStatus();
    return { success: true, data: status };
  });

  // AUDIT-MGT-018: Expose signed-tag verification bypass status so the
  // renderer can surface a persistent warning banner when
  // UPDATE_SKIP_TAG_VERIFY=true is active. The value is evaluated per-call
  // (not cached) so the renderer always reflects the live env var state.
  ipcMain.handle('system:get-tag-verify-status', (event) => {
    assertRendererOrigin(event);
    const bypass = process.env['UPDATE_SKIP_TAG_VERIFY'] === 'true';
    return { success: true, data: { bypass } };
  });

  ipcMain.handle('system:maximize', (event) => {
    assertRendererOrigin(event);
    const win = getMainWindow();
    if (!win) {
      return {
        success: false,
        error: 'NO_WINDOW',
        code: 500,
        message: 'No main window available to maximize.',
      };
    }
    if (win.isMaximized()) {
      win.unmaximize();
      return { success: true, data: { maximized: false } };
    }
    win.maximize();
    return { success: true, data: { maximized: true } };
  });
}
