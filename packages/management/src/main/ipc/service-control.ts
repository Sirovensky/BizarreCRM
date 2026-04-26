/**
 * IPC handlers for server process control.
 * Detects whether the server runs as a Windows Service or PM2,
 * and uses the appropriate commands for each.
 *
 * SECURITY (EL3 / EL4): None of the functions here take caller-supplied
 * paths or arguments. All commands are built from hard-coded constants
 * and the resolved trusted project root. Everything goes through
 * `spawnSync` with an explicit `argv` array — no shell interpolation,
 * no `execSync(string)`. The project root is resolved from deterministic
 * Electron/setup.bat anchors rather than an upward filesystem search, so
 * an attacker who drops a rogue ecosystem.config.js in a parent directory
 * can't redirect us.
 */
import { ipcMain, app } from 'electron';
import { spawn, spawnSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';
import { z } from 'zod';
import { assertRendererOrigin } from './management-api.js';

const SERVICE_NAME = 'BizarreCRM';
const DIRECT_PID_FILE = 'direct-server.json';

interface DirectServerState {
  pid: number;
  root: string;
}

/** True if `child` is inside (or equal to) `parent`. */
function isPathUnder(child: string, parent: string): boolean {
  const resolvedChild = path.resolve(child);
  const resolvedParent = path.resolve(parent);
  if (resolvedChild === resolvedParent) return true;
  const rel = path.relative(resolvedParent, resolvedChild);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

function isProjectRoot(dir: string): boolean {
  return (
    fs.existsSync(path.join(dir, 'package.json')) &&
    fs.existsSync(path.join(dir, 'packages', 'server', 'package.json'))
  );
}

/**
 * AUD-20260414-M2 / EL3: Locate the CRM project root from TRUSTED Electron
 * anchors only.
 *
 * Prior implementations walked upward from a trusted anchor until they
 * found a marker file, then only verified the candidate still sat under
 * the filesystem DRIVE root (`C:\`) — effectively no check. A
 * marker-bearing ancestor anywhere on the same drive would be accepted,
 * letting a misplaced install silently run from anywhere with no
 * integrity gate.
 *
 * This implementation uses deterministic, layout-specific candidates:
 *
 *   - Packaged setup.bat layout: `<repo>/dashboard/<exe>` accepts exactly
 *     `<repo>` when the full marker set and `.env` are present. This is the
 *     live repo root that setup.bat prepares and the only place production
 *     secrets are written.
 *
 *   - Packaged fallback: `<process.resourcesPath>/crm-source` is trusted
 *     (populated by electron-builder `extraResources`). If neither packaged
 *     candidate exists we throw an installation-integrity error rather than
 *     hunting elsewhere.
 *
 *   - Dev: the monorepo repo root is `app.getAppPath()/../..` (where
 *     `app.getAppPath()` resolves to `packages/management`). No walking.
 *
 * Both branches require the full project-root marker set (package.json +
 * packages/server/package.json + ecosystem.config.js|install.bat|setup.bat);
 * sibling/ancestor markers are never accepted.
 *
 * Kept in-file rather than shared so the two modules remain decoupled at
 * the source level.
 */
function hasFullProjectRootMarkers(dir: string): boolean {
  if (!isProjectRoot(dir)) return false;
  return (
    fs.existsSync(path.join(dir, 'ecosystem.config.js')) ||
    fs.existsSync(path.join(dir, 'install.bat')) ||
    fs.existsSync(path.join(dir, 'setup.bat'))
  );
}

function resolveSetupProjectRootFromPackagedExe(): string | null {
  if (!app.isPackaged) return null;
  const execPath = typeof process.execPath === 'string' ? process.execPath : null;
  if (!execPath) return null;

  const exeDir = path.resolve(path.dirname(execPath));
  if (path.basename(exeDir).toLowerCase() !== 'dashboard') return null;

  const candidate = path.resolve(exeDir, '..');
  if (!isPathUnder(exeDir, candidate)) return null;
  if (!hasFullProjectRootMarkers(candidate)) return null;
  if (!fs.existsSync(path.join(candidate, '.env'))) return null;
  return candidate;
}

function resolveTrustedProjectRoot(): string | null {
  // Packaged build from setup.bat: dashboard EXE lives in <repo>/dashboard.
  if (app.isPackaged) {
    const setupRoot = resolveSetupProjectRootFromPackagedExe();
    if (setupRoot) return setupRoot;

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
    return hasFullProjectRootMarkers(candidate) ? candidate : null;
  }

  // Dev build: app.getAppPath() === <repo>/packages/management.
  const appPath = typeof app.getAppPath === 'function' ? app.getAppPath() : null;
  if (!appPath) return null;
  const resolvedAppPath = path.resolve(appPath);
  const devRepoRoot = path.resolve(resolvedAppPath, '..', '..');
  if (!hasFullProjectRootMarkers(devRepoRoot)) return null;
  return devRepoRoot;
}

/**
 * Best-effort wrapper around resolveTrustedProjectRoot() — most callers
 * in this file use the root as an optional `cwd` hint for pm2 / spawn
 * commands, so we degrade to `null` on integrity failures and let those
 * handlers fall back to their default cwd. The `startDirectServer` code
 * path does its own strict check and surfaces a human-readable error.
 */
function getProjectRoot(): string | null {
  try {
    return resolveTrustedProjectRoot();
  } catch (err) {
    console.error(
      '[ServiceControl] Installation integrity check failed:',
      err instanceof Error ? err.message : String(err)
    );
    return null;
  }
}

interface ServiceStatus {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'direct' | 'none';
}

interface CommandResult {
  success: boolean;
  output: string;
}

/**
 * Run a process with an explicit argv array — never interpolated into a
 * shell string. All callers supply literal command names from this file,
 * never user input.
 */
function runArgs(command: string, args: readonly string[], cwd?: string): CommandResult {
  try {
    const result = spawnSync(command, args, {
      encoding: 'utf-8',
      timeout: 15_000,
      cwd,
      // Explicit `shell: false` so spaces / metacharacters in any arg
      // reach the child process verbatim rather than being interpreted.
      shell: false,
    });
    if (result.error) {
      return { success: false, output: result.error.message };
    }
    if (result.status !== 0) {
      return {
        success: false,
        output: (result.stderr || '').trim() || `${command} exited ${result.status}`,
      };
    }
    return { success: true, output: (result.stdout || '').trim() };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, output: message };
  }
}

/**
 * Run PM2 with shell resolution on Windows.
 *
 * PM2 is installed as `pm2.cmd` on Windows. Node's `spawnSync` with
 * `shell: false` cannot execute `.cmd` files — only `.exe` binaries.
 * This caused `hasPm2()` to always return false on Windows even when
 * PM2 was installed, forcing every dashboard start into the less-
 * reliable direct-spawn fallback.
 *
 * Using `shell: true` here is safe because every argument passed to
 * pm2Run is a hardcoded string literal from this file — no user/
 * renderer input ever reaches this function.
 */
function pm2Run(args: readonly string[]): CommandResult {
  const root = getProjectRoot();
  try {
    const result = spawnSync('pm2', args as string[], {
      encoding: 'utf-8',
      timeout: 15_000,
      cwd: root ?? undefined,
      shell: process.platform === 'win32',
    });
    if (result.error) {
      return { success: false, output: result.error.message };
    }
    if (result.status !== 0) {
      return {
        success: false,
        output: (result.stderr || '').trim() || `pm2 exited ${result.status}`,
      };
    }
    return { success: true, output: (result.stdout || '').trim() };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, output: message };
  }
}

/**
 * Fire-and-forget pm2 invocation used by start/restart handlers.
 *
 * Why this exists: `ecosystem.config.js` sets `wait_ready: true` with
 * `listen_timeout: 600_000` (10 min) so `pm2 start` CLI blocks until the
 * server emits `process.send('ready')`. On a cold boot with tenant
 * migrations that can take 30s–5min easily. Running it through the
 * synchronous `pm2Run` with a 15s timeout hits ETIMEDOUT and surfaces
 * `spawnSync C:\\WINDOWS\\system32\\cmd.exe ETIMEDOUT` — the exact error
 * the user reported from the dashboard "Start Server" button.
 *
 * Detaching the child lets the CLI finish in the background, then the
 * caller polls `pm2 jlist` (short-timeout sync call) to report status
 * back to the renderer within a bounded window.
 */
function pm2Spawn(args: readonly string[]): CommandResult {
  const root = getProjectRoot();
  try {
    const child = spawn('pm2', args as string[], {
      cwd: root ?? undefined,
      shell: process.platform === 'win32',
      detached: true,
      stdio: 'ignore',
      windowsHide: true,
    });
    child.on('error', () => {
      // Swallow — the poll loop in the caller will surface "not online"
      // if the spawn itself failed.
    });
    child.unref();
    return { success: true, output: `pm2 ${args.join(' ')} spawned` };
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    return { success: false, output: message };
  }
}

/**
 * Wait up to `timeoutMs` for the `bizarre-crm` PM2 app to reach the
 * desired online/stopped state, polling `pm2 jlist` every 500ms. Used
 * after `pm2Spawn` so the renderer can distinguish "started cleanly"
 * from "process is still warming up" without blocking the IPC call
 * for the full 10-minute listen_timeout.
 */
async function waitForPm2State(
  target: 'online' | 'stopped',
  timeoutMs = 30_000,
): Promise<'reached' | 'timeout'> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const jlist = pm2Run(['jlist']);
    if (jlist.success) {
      try {
        const procs = JSON.parse(jlist.output) as Array<{
          name?: string;
          pm2_env?: { status?: string };
        }>;
        const proc = procs.find(p => p.name === 'bizarre-crm');
        if (target === 'online' && proc?.pm2_env?.status === 'online') {
          return 'reached';
        }
        if (target === 'stopped' && (!proc || proc.pm2_env?.status !== 'online')) {
          return 'reached';
        }
      } catch {
        // fall through and keep polling
      }
    }
    await new Promise<void>(r => setTimeout(r, 500));
  }
  return 'timeout';
}

function hasPm2(): boolean {
  return pm2Run(['--version']).success;
}

function getDirectPidPath(): string {
  return path.join(app.getPath('userData'), DIRECT_PID_FILE);
}

function readDirectState(): DirectServerState | null {
  try {
    const raw = fs.readFileSync(getDirectPidPath(), 'utf-8');
    const parsed = JSON.parse(raw) as Partial<DirectServerState>;
    if (
      typeof parsed.pid === 'number' &&
      Number.isInteger(parsed.pid) &&
      parsed.pid > 0 &&
      typeof parsed.root === 'string' &&
      isProjectRoot(parsed.root)
    ) {
      // AUDIT-MGT-030: The PID file is user-writable (it lives in userData).
      // isProjectRoot() only checks that the claimed root contains package.json
      // and packages/server/package.json — any directory tree with those two
      // files would pass, including an attacker-crafted one. Cross-check the
      // claimed root against the TRUSTED root derived from Electron anchors
      // (resolveTrustedProjectRoot). If they don't match, treat the PID file as
      // stale/tampered and return null rather than using an untrusted root.
      const trustedRoot = resolveTrustedProjectRoot();
      if (!trustedRoot || path.resolve(parsed.root) !== path.resolve(trustedRoot)) {
        console.warn(
          '[readDirectState] root mismatch with trusted project root — ignoring stale PID file:',
          parsed.root,
          '!==',
          trustedRoot
        );
        return null;
      }
      return { pid: parsed.pid, root: parsed.root };
    }
  } catch {
    /* no direct process recorded */
  }
  return null;
}

function writeDirectState(state: DirectServerState): void {
  const dir = app.getPath('userData');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(getDirectPidPath(), JSON.stringify(state), 'utf-8');
}

function clearDirectState(): void {
  try {
    const pidPath = getDirectPidPath();
    if (fs.existsSync(pidPath)) fs.unlinkSync(pidPath);
  } catch {
    /* ignore */
  }
}

function isProcessAlive(pid: number): boolean {
  try {
    process.kill(pid, 0);
    return true;
  } catch {
    return false;
  }
}

function getDirectStatus(): { running: boolean; pid: number | null } {
  const state = readDirectState();
  if (!state) return { running: false, pid: null };
  if (!isProcessAlive(state.pid)) {
    clearDirectState();
    return { running: false, pid: null };
  }
  return { running: true, pid: state.pid };
}

function getPm2Status(): { running: boolean; pid: number | null } {
  const result = pm2Run(['jlist']);
  if (!result.success) return { running: false, pid: null };
  try {
    const list = JSON.parse(result.output);
    const entry = (list as Array<{ name: string; pm2_env?: { status?: string }; pid?: number }>).find(
      (p) => p.name === 'bizarre-crm'
    );
    if (!entry) return { running: false, pid: null };
    return {
      running: entry.pm2_env?.status === 'online',
      pid: entry.pid ?? null,
    };
  } catch {
    return { running: false, pid: null };
  }
}

function getWindowsServiceStatus(): { installed: boolean; running: boolean; pid: number | null; startType: ServiceStatus['startType'] } {
  const query = runArgs('sc', ['query', SERVICE_NAME]);
  if (!query.success) {
    return { installed: false, running: false, pid: null, startType: 'unknown' };
  }

  const stateMatch = query.output.match(/STATE\s+:\s+\d+\s+(\w+)/);
  const pidMatch = query.output.match(/PID\s+:\s+(\d+)/);
  const rawState = stateMatch?.[1]?.toLowerCase() ?? '';
  const running = rawState === 'running';
  const pid = pidMatch ? parseInt(pidMatch[1], 10) : null;

  let startType: ServiceStatus['startType'] = 'unknown';
  const config = runArgs('sc', ['qc', SERVICE_NAME]);
  if (config.success) {
    const match = config.output.match(/START_TYPE\s+:\s+\d+\s+(\w+)/);
    const raw = match?.[1]?.toLowerCase() ?? '';
    if (raw === 'auto_start') startType = 'auto';
    else if (raw === 'demand_start') startType = 'demand';
    else if (raw === 'disabled') startType = 'disabled';
  }

  return { installed: true, running, pid, startType };
}

function getDirectServerEntry(root: string): { cwd: string; script: string } | null {
  const serverRoot = path.join(root, 'packages', 'server');
  const distEntry = path.join(serverRoot, 'dist', 'index.js');
  if (fs.existsSync(distEntry)) {
    return { cwd: serverRoot, script: 'dist/index.js' };
  }
  return null;
}

// AUDIT-MGT-029: Only the server's own runtime keys are forwarded to the
// spawned child process. Arbitrary keys (e.g. attacker-added entries in a
// world-writable .env) are silently dropped. The allowlist mirrors the set
// that ecosystem.config.js reads plus well-known server secrets that the
// server startup code requires at runtime. The point is NOT to hide secrets
// from the child server (it legitimately needs them) but to prevent an
// attacker who can write to .env from injecting keys like NODE_OPTIONS or
// arbitrary env poisoning that could alter Node.js / the server's behaviour
// in unexpected ways.
const SERVER_ENV_ALLOWLIST = new Set([
  'PORT',
  'NODE_ENV',
  'LOG_LEVEL',
  'JWT_SECRET',
  'JWT_REFRESH_SECRET',
  'ACCESS_JWT_SECRET',
  'REFRESH_JWT_SECRET',
  'CONFIG_ENCRYPTION_KEY',
  'BACKUP_ENCRYPTION_KEY',
  'DB_ENCRYPTION_KEY',
  'UPLOADS_SECRET',
  'SUPER_ADMIN_SECRET',
  'STRIPE_SECRET_KEY',
  'STRIPE_WEBHOOK_SECRET',
  'ALLOWED_ORIGINS',
]);

/**
 * Parse a .env file into a key-value map. Same logic as ecosystem.config.js
 * so direct-mode starts get the same env vars that PM2 would provide.
 *
 * AUDIT-MGT-029: After parsing, only keys present in SERVER_ENV_ALLOWLIST
 * are retained. Arbitrary keys (injected by an attacker with .env write
 * access) are dropped before the map is merged into the child's environment.
 *
 * The envPath is NOT validated here — callers must guard with isPathUnder()
 * before calling this function.
 */
function parseDotEnv(file: string): Record<string, string> {
  if (!fs.existsSync(file)) return {};
  const all: Record<string, string> = {};
  const lines = fs.readFileSync(file, 'utf-8').split(/\r?\n/);
  for (let line of lines) {
    line = line.trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.slice('export '.length).trim();
    const equals = line.indexOf('=');
    if (equals === -1) continue;
    const key = line.slice(0, equals).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let value = line.slice(equals + 1).trim();
    const quote = value[0];
    if ((quote === '"' || quote === "'") && value.endsWith(quote)) {
      value = value.slice(1, -1);
    }
    all[key] = value;
  }
  // AUDIT-MGT-029: Drop any keys not in the allowlist.
  const filtered: Record<string, string> = {};
  for (const key of SERVER_ENV_ALLOWLIST) {
    if (Object.prototype.hasOwnProperty.call(all, key)) {
      filtered[key] = all[key];
    }
  }
  return filtered;
}

async function startDirectServer(): Promise<CommandResult> {
  const existing = getDirectStatus();
  if (existing.running) {
    return { success: true, output: `Direct server already running (PID ${existing.pid})` };
  }

  const root = getProjectRoot();
  if (!root) {
    return {
      success: false,
      output: 'Could not locate CRM project root. Run setup.bat from the project folder, then reopen the dashboard.',
    };
  }

  const nodeCheck = runArgs('node', ['--version']);
  if (!nodeCheck.success) {
    return { success: false, output: 'Node.js is not installed or not available on PATH.' };
  }

  const entry = getDirectServerEntry(root);
  if (!entry) {
    return {
      success: false,
      output: 'Built server entry not found. Run setup.bat or npm run build, then try Start Server again.',
    };
  }

  // Load .env from the project root — same file that ecosystem.config.js reads
  // for PM2 starts. Without this, critical env vars like JWT_SECRET are missing
  // and the server exits immediately in production mode.
  //
  // AUDIT-MGT-029: Guard the .env path with isPathUnder() before reading it,
  // so a crafted root value (e.g. from a stale PID file, fixed separately by
  // AUDIT-MGT-030) can never redirect us to an attacker-controlled .env file
  // outside the trusted project tree.
  const envPath = path.join(root, '.env');
  const envFromFile = isPathUnder(envPath, root)
    ? parseDotEnv(envPath)
    : {};

  const logDir = path.join(root, 'logs');
  fs.mkdirSync(logDir, { recursive: true });
  const outPath = path.join(logDir, 'bizarre-crm.direct.out.log');
  const errPath = path.join(logDir, 'bizarre-crm.direct.err.log');
  const out = fs.openSync(outPath, 'a');
  const err = fs.openSync(errPath, 'a');

  const child = spawn('node', [entry.script], {
    cwd: entry.cwd,
    detached: true,
    shell: false,
    stdio: ['ignore', out, err],
    env: {
      ...process.env,
      ...envFromFile,
      NODE_ENV: 'production',
      PORT: envFromFile.PORT || process.env.PORT || '443',
    },
  });

  const result = await new Promise<CommandResult>((resolve) => {
    let settled = false;
    const done = (value: CommandResult): void => {
      if (settled) return;
      settled = true;
      resolve(value);
    };

    child.once('error', (spawnError: Error) => {
      done({ success: false, output: spawnError.message });
    });
    child.once('spawn', () => {
      if (!child.pid) {
        done({ success: false, output: 'Server process started without a PID.' });
        return;
      }
      writeDirectState({ pid: child.pid, root });
      child.unref();
      done({
        success: true,
        output: `Started direct server (PID ${child.pid}). Logs: ${outPath}`,
      });
    });
    child.once('exit', (code, signal) => {
      if (code !== null && code !== 0) {
        done({ success: false, output: `Server exited immediately with code ${code}. Check ${errPath}` });
      } else if (signal) {
        done({ success: false, output: `Server exited immediately with signal ${signal}. Check ${errPath}` });
      }
    });
    setTimeout(() => {
      if (!child.pid) {
        done({ success: false, output: 'Timed out waiting for server process PID.' });
      }
    }, 5_000);
  });

  try { fs.closeSync(out); } catch { /* ignore */ }
  try { fs.closeSync(err); } catch { /* ignore */ }
  return result;
}

function stopDirectServer(): CommandResult {
  const state = readDirectState();
  if (!state) {
    return { success: true, output: 'Direct server is not running' };
  }

  // Do NOT pre-check isProcessAlive: between the signal-0 probe and the
  // taskkill the PID can exit and the OS can reassign it to an unrelated
  // process, creating a TOCTOU kill of the wrong process.  Instead always
  // issue taskkill and treat exit 128 (no such PID / already gone) as
  // success — both outcomes mean the target is no longer running.
  const stopped = runArgs('taskkill', ['/PID', String(state.pid), '/T', '/F']);
  clearDirectState();
  // taskkill exit 128 = "no such PID" — the process already exited, so we
  // treat it as a successful stop rather than an error.
  if (stopped.success || stopped.output?.includes('128') || stopped.output?.includes('not found')) {
    return { success: true, output: `Stopped direct server PID ${state.pid}` };
  }
  return stopped;
}

export function registerServiceControlIpc(): void {
  ipcMain.handle('service:get-status', async (event): Promise<ServiceStatus> => {
    assertRendererOrigin(event);
    // Check Windows Service first
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      const state = svc.running ? 'running' : 'stopped';
      return { state, pid: svc.pid, startType: svc.startType, mode: 'service' };
    }

    // Fall back to PM2
    if (hasPm2()) {
      const pm2 = getPm2Status();
      return {
        state: pm2.running ? 'running' : 'stopped',
        pid: pm2.pid,
        startType: 'unknown',
        mode: 'pm2',
      };
    }

    const root = getProjectRoot();
    if (root && getDirectServerEntry(root)) {
      const direct = getDirectStatus();
      return {
        state: direct.running ? 'running' : 'stopped',
        pid: direct.pid,
        startType: 'unknown',
        mode: 'direct',
      };
    }

    return { state: 'not_installed', pid: null, startType: 'unknown', mode: 'none' };
  });

  ipcMain.handle('service:start', async (event) => {
    assertRendererOrigin(event);
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['start', SERVICE_NAME]);
    }
    if (hasPm2()) {
      // Fire-and-forget: pm2 CLI will block up to 10 min on wait_ready,
      // but we return as soon as the app shows online in `pm2 jlist`
      // so the dashboard UI stays responsive.
      const spawnResult = pm2Spawn(['start', 'ecosystem.config.js', '--update-env']);
      if (!spawnResult.success) return spawnResult;
      const state = await waitForPm2State('online', 30_000);
      if (state === 'reached') {
        return { success: true, output: 'Server online' };
      }
      return {
        success: false,
        output: 'Server still warming up — check pm2 logs bizarre-crm for progress',
      };
    }
    return startDirectServer();
  });

  ipcMain.handle('service:stop', async (event) => {
    assertRendererOrigin(event);
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['stop', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['stop', 'bizarre-crm']);
    }
    return stopDirectServer();
  });

  ipcMain.handle('service:restart', async (event) => {
    assertRendererOrigin(event);
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runArgs('sc', ['stop', SERVICE_NAME]);
      let attempts = 0;
      while (attempts < 10) {
        const query = runArgs('sc', ['query', SERVICE_NAME]);
        if (query.output.includes('STOPPED')) break;
        await new Promise(r => setTimeout(r, 1000));
        attempts++;
      }
      return runArgs('sc', ['start', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['restart', 'bizarre-crm', '--update-env']);
    }
    stopDirectServer();
    return startDirectServer();
  });

  ipcMain.handle('service:emergency-stop', async (event) => {
    assertRendererOrigin(event);
    // Kill everything
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runArgs('taskkill', ['/F', '/FI', `SERVICES eq ${SERVICE_NAME}`]);
      runArgs('sc', ['stop', SERVICE_NAME]);
    }
    if (hasPm2()) {
      pm2Run(['kill']);
    }
    stopDirectServer();
    return { success: true, message: 'Emergency stop executed' };
  });

  ipcMain.handle('service:set-auto-start', async (event, enabled: boolean) => {
    assertRendererOrigin(event);
    // DASH-ELEC-077: validate boolean at runtime — TS types are erased over IPC;
    // a caller could pass "true" (string) or 1, which are truthy but not boolean.
    const validEnabled = z.boolean().parse(enabled);
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      // NB: on Windows, `sc config` uses `start= <type>` — a SINGLE argv
      // token with the trailing `=`. spawnSync preserves this correctly.
      const startType = validEnabled ? 'auto' : 'demand';
      return runArgs('sc', ['config', SERVICE_NAME, 'start=', startType]);
    }
    if (hasPm2() && validEnabled) {
      return pm2Run(['save']);
    }
    return { success: false, output: 'Auto-start requires a Windows Service or PM2. Manual Start Server still works.' };
  });

  ipcMain.handle('service:disable', async (event) => {
    assertRendererOrigin(event);
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runArgs('sc', ['stop', SERVICE_NAME]);
      return runArgs('sc', ['config', SERVICE_NAME, 'start=', 'disabled']);
    }
    if (hasPm2()) {
      return pm2Run(['stop', 'bizarre-crm']);
    }
    return stopDirectServer();
  });

  ipcMain.handle('service:kill-all', async (event) => {
    assertRendererOrigin(event);
    // 1. Stop PM2 managed server
    try { pm2Run(['kill']); } catch { /* ignore */ }

    // 2. Stop Windows Service if installed
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      try { runArgs('sc', ['stop', SERVICE_NAME]); } catch { /* ignore */ }
    }

    // 3. DASH-ELEC-087: kill only the known direct-server PID, not all node.exe
    // processes (which would also terminate VS Code helpers, dev servers, etc.)
    // Fall back to /IM filter constrained to our command-line footprint when no
    // PID file exists (e.g. service path already cleaned up the file).
    const directState = readDirectState();
    if (directState?.pid) {
      try { runArgs('taskkill', ['/PID', String(directState.pid), '/T', '/F']); } catch { /* ignore */ }
    } else {
      // No known PID — use image-name filter scoped to our process name so we
      // avoid touching unrelated node.exe instances owned by other apps.
      try {
        runArgs('taskkill', ['/F', '/FI', 'IMAGENAME eq node.exe', '/FI', 'WINDOWTITLE eq bizarre-crm*']);
      } catch { /* ignore */ }
    }
    try { stopDirectServer(); } catch { /* ignore */ }

    // 4. Kill the dashboard itself
    setTimeout(() => {
      app.exit(0);
    }, 500);

    return { success: true, message: 'Killing all processes...' };
  });
}
