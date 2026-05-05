/**
 * Crash Tracker Service
 *
 * Persists crash data to a JSON file (not SQLite — survives DB corruption).
 * Tracks per-route consecutive crash counts and auto-disables routes that
 * crash 3+ times in a row. Protected routes (auth, health, admin, management)
 * can never be auto-disabled to prevent DoS via intentional crash-to-disable.
 */
import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// ── Types ──────────────────────────────────────────────────────────────

export interface CrashEntry {
  id: string;
  timestamp: string;
  route: string;       // e.g. "GET:/api/v1/inventory"
  errorMessage: string;
  errorStack: string;
  type: 'uncaughtException' | 'unhandledRejection';
  recovered: boolean;
}

export interface DisabledRoute {
  route: string;
  disabledAt: string;
  crashCount: number;
  lastError: string;
}

interface CrashData {
  crashes: CrashEntry[];
  disabledRoutes: DisabledRoute[];
  consecutiveCrashCounts: Record<string, number>;
}

// ── Constants ──────────────────────────────────────────────────────────

const CRASH_LOG_PATH = path.resolve(__dirname, '../../data/crash-log.json');
const MAX_CONSECUTIVE_CRASHES = 3;
const MAX_CRASH_LOG_ENTRIES = 500;

/**
 * Protected routes that can NEVER be auto-disabled.
 * Disabling auth = total lockout. Disabling health = breaks monitoring.
 * If these crash repeatedly, we log a warning but keep them running.
 */
const PROTECTED_ROUTES: RegExp[] = [
  /^[A-Z]+:\/api\/v1\/auth\//,        // All auth endpoints — any method
  /^GET:\/api\/v1\/health$/,
  /^GET:\/health$/,
  /^[A-Z]+:\/api\/v1\/management\//,   // All management endpoints — any method
  /^[A-Z]+:\/api\/v1\/admin\//,        // All admin endpoints — any method
];

// ── State ──────────────────────────────────────────────────────────────

let crashData: CrashData = { crashes: [], disabledRoutes: [], consecutiveCrashCounts: {} };

// ── File I/O ───────────────────────────────────────────────────────────

function loadCrashData(): CrashData {
  try {
    if (fs.existsSync(CRASH_LOG_PATH)) {
      const raw = fs.readFileSync(CRASH_LOG_PATH, 'utf-8');
      const parsed = JSON.parse(raw);
      return {
        crashes: Array.isArray(parsed.crashes) ? parsed.crashes : [],
        disabledRoutes: Array.isArray(parsed.disabledRoutes) ? parsed.disabledRoutes : [],
        consecutiveCrashCounts: parsed.consecutiveCrashCounts || {},
      };
    }
  } catch {
    console.error('[CrashTracker] Failed to load crash log, starting fresh');
  }
  return { crashes: [], disabledRoutes: [], consecutiveCrashCounts: {} };
}

function saveCrashData(data: CrashData): void {
  try {
    const dir = path.dirname(CRASH_LOG_PATH);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    // Atomic write: temp file then rename
    // @audit-fixed: still synchronous because callers expect crash recording to
    // happen before process exit (uncaughtException handler), but at least the
    // tmp+rename pattern guarantees we never leave a half-written file. Switching
    // to async would require chaining callbacks before letting Node die, which is
    // a bigger refactor — flagged as a follow-up. Use a unique tmp suffix to
    // tolerate concurrent crashes.
    const tmpPath = CRASH_LOG_PATH + '.tmp.' + process.pid + '.' + Date.now();
    fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2));
    fs.renameSync(tmpPath, CRASH_LOG_PATH);
  } catch (err) {
    console.error('[CrashTracker] Failed to save crash log:', err);
  }
}

// ── Initialize on module load ──────────────────────────────────────────

crashData = loadCrashData();

/**
 * SEC-L22: Sweep stale `.tmp.*` files from the crash-log directory on startup.
 *
 * `saveCrashData()` writes `crash-log.json.tmp.<pid>.<ts>` then renames it, so a
 * crash mid-rename can leave the tmp file behind. These never get cleaned up
 * on their own and accumulate on long-running instances with repeated restarts.
 *
 * Only removes tmp files older than 24h so we don't race a concurrent writer
 * in another worker thread. Best-effort — a failure here is non-fatal.
 */
function cleanupStaleTmpFiles(): void {
  try {
    const dir = path.dirname(CRASH_LOG_PATH);
    if (!fs.existsSync(dir)) return;
    const prefix = path.basename(CRASH_LOG_PATH) + '.tmp.';
    const cutoffMs = Date.now() - 24 * 60 * 60 * 1000;
    for (const name of fs.readdirSync(dir)) {
      if (!name.startsWith(prefix)) continue;
      const full = path.join(dir, name);
      try {
        const st = fs.statSync(full);
        if (st.mtimeMs < cutoffMs) fs.unlinkSync(full);
      } catch { /* best-effort */ }
    }
  } catch { /* best-effort */ }
}

cleanupStaleTmpFiles();

// ── Public API ─────────────────────────────────────────────────────────

function isProtectedRoute(route: string): boolean {
  return PROTECTED_ROUTES.some((pattern) => pattern.test(route));
}

/**
 * @audit-fixed: error stacks and messages can contain secrets (Authorization headers,
 * Bearer tokens, JWT contents, query string credentials, password fields echoed in
 * better-sqlite3 errors, file paths leaking customer names, etc.) and we persist them
 * to a JSON file on disk that the admin panel surfaces. Redact the most common
 * leak vectors before writing. The pattern list is conservative and OK if it
 * occasionally over-redacts — the goal is to prevent secrets from landing in
 * crash-log.json where they'd survive log rotation and be visible to anyone with
 * filesystem or admin-UI access.
 */
function redactSecrets(text: string): string {
  if (!text) return text;
  return text
    // Bearer / Token authorization headers
    .replace(/Bearer\s+[A-Za-z0-9._\-+/=]{8,}/gi, 'Bearer [REDACTED]')
    .replace(/Authorization:\s*[^\s,]+/gi, 'Authorization: [REDACTED]')
    // Common secret query params
    .replace(/(api[_-]?key|access[_-]?token|auth[_-]?token|password|passwd|secret|jwt)=[^&\s"',}]+/gi, '$1=[REDACTED]')
    // Long hex strings (likely tokens / hashes)
    .replace(/\b[A-Fa-f0-9]{40,}\b/g, '[REDACTED_HEX]')
    // JWT-shaped strings
    .replace(/\beyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}\b/g, '[REDACTED_JWT]')
    // Twilio account SIDs and bearer-style IDs
    .replace(/\bAC[a-f0-9]{32}\b/g, '[REDACTED_TWILIO_SID]');
}

export function recordCrash(route: string, error: Error, type: CrashEntry['type']): CrashEntry {
  const entry: CrashEntry = {
    id: crypto.randomUUID(),
    timestamp: new Date().toISOString(),
    route,
    // @audit-fixed: redact common secret patterns before persisting to disk.
    errorMessage: redactSecrets(error.message || 'Unknown error'),
    errorStack: redactSecrets((error.stack || '').slice(0, 2000)),
    type,
    recovered: true,
  };

  // Append crash entry (immutable pattern: new array)
  const updatedCrashes = [...crashData.crashes, entry];
  // Trim to max entries (keep most recent)
  const trimmedCrashes = updatedCrashes.length > MAX_CRASH_LOG_ENTRIES
    ? updatedCrashes.slice(updatedCrashes.length - MAX_CRASH_LOG_ENTRIES)
    : updatedCrashes;

  // Increment consecutive crash count for this route
  const prevCount = crashData.consecutiveCrashCounts[route] || 0;
  const newCount = prevCount + 1;
  const updatedCounts = { ...crashData.consecutiveCrashCounts, [route]: newCount };

  // Check if route should be auto-disabled
  let updatedDisabled = [...crashData.disabledRoutes];
  if (newCount >= MAX_CONSECUTIVE_CRASHES && !isRouteDisabled(route)) {
    if (isProtectedRoute(route)) {
      console.error(`[CrashTracker] WARNING: Protected route ${route} has crashed ${newCount} times consecutively. NOT disabling — this route is protected.`);
    } else {
      const disabledEntry: DisabledRoute = {
        route,
        disabledAt: new Date().toISOString(),
        crashCount: newCount,
        lastError: entry.errorMessage,
      };
      updatedDisabled = [...updatedDisabled, disabledEntry];
      console.error(`[CrashTracker] Route ${route} auto-disabled after ${newCount} consecutive crashes`);
    }
  }

  crashData = {
    crashes: trimmedCrashes,
    disabledRoutes: updatedDisabled,
    consecutiveCrashCounts: updatedCounts,
  };
  saveCrashData(crashData);

  return entry;
}

export function resetRouteCrashCount(route: string): void {
  if (crashData.consecutiveCrashCounts[route] === undefined) return;
  const { [route]: _removed, ...rest } = crashData.consecutiveCrashCounts;
  crashData = { ...crashData, consecutiveCrashCounts: rest };
  // Don't save on every successful request — only on crash events
}

export function isRouteDisabled(route: string): boolean {
  return crashData.disabledRoutes.some((d) => d.route === route);
}

export function reenableRoute(route: string): boolean {
  const exists = crashData.disabledRoutes.some((d) => d.route === route);
  if (!exists) return false;

  crashData = {
    ...crashData,
    disabledRoutes: crashData.disabledRoutes.filter((d) => d.route !== route),
    consecutiveCrashCounts: (() => {
      const { [route]: _removed, ...rest } = crashData.consecutiveCrashCounts;
      return rest;
    })(),
  };
  saveCrashData(crashData);
  console.log(`[CrashTracker] Route ${route} re-enabled`);
  return true;
}

export function getCrashLog(): readonly CrashEntry[] {
  return crashData.crashes;
}

export function getDisabledRoutes(): readonly DisabledRoute[] {
  return crashData.disabledRoutes;
}

export function clearCrashLog(): void {
  crashData = {
    ...crashData,
    crashes: [],
  };
  saveCrashData(crashData);
}

/**
 * Reset transient crash state on server startup.
 *
 * Clears `disabledRoutes` and `consecutiveCrashCounts` while PRESERVING the
 * full `crashes` history (needed for forensics and the Dashboard crash monitor
 * UI). The rationale: a fresh server restart means all routes get a clean
 * chance to succeed. If a route is genuinely still broken, the crash tracker
 * will re-disable it within three requests anyway.
 *
 * This unblocks the common operator flow: "I fixed the root cause, I restarted
 * the server, why are my routes still disabled?" Without this, disabled routes
 * from previous server sessions persist across code fixes and force the operator
 * to manually edit crash-log.json.
 *
 * Called from index.ts early in startup.
 */
export function resetDisabledRoutesOnStartup(): void {
  const hadDisabled = crashData.disabledRoutes.length > 0;
  const hadCounts = Object.keys(crashData.consecutiveCrashCounts).length > 0;
  if (!hadDisabled && !hadCounts) return;

  if (hadDisabled) {
    console.log(`[CrashTracker] Cleared ${crashData.disabledRoutes.length} previously-disabled route(s) on startup:`);
    for (const r of crashData.disabledRoutes) {
      console.log(`  - ${r.route} (was disabled at ${r.disabledAt}, lastError: ${r.lastError})`);
    }
  }

  crashData = {
    ...crashData,
    disabledRoutes: [],
    consecutiveCrashCounts: {},
    // crashes array is intentionally preserved for forensic history
  };
  saveCrashData(crashData);
}

export function getCrashStats(): { totalCrashes: number; disabledCount: number; recentCrashes: CrashEntry[] } {
  return {
    totalCrashes: crashData.crashes.length,
    disabledCount: crashData.disabledRoutes.length,
    recentCrashes: crashData.crashes.slice(-10),
  };
}
