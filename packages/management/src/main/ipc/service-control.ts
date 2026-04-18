/**
 * IPC handlers for server process control.
 * Detects whether the server runs as a Windows Service or PM2,
 * and uses the appropriate commands for each.
 *
 * SECURITY (EL3 / EL4): None of the functions here take caller-supplied
 * paths or arguments. All commands are built from hard-coded constants
 * and the resolved trusted project root. Everything goes through
 * `spawnSync` with an explicit `argv` array — no shell interpolation,
 * no `execSync(string)`. The project root is resolved from trusted
 * Electron anchors (app.getAppPath / process.resourcesPath) rather
 * than walking up from process.execPath, so an attacker who drops a
 * rogue ecosystem.config.js in a parent directory can't redirect us.
 */
import { ipcMain, app } from 'electron';
import { spawn, spawnSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

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
 * This implementation uses deterministic, layout-specific candidates and
 * requires the resolved root to sit INSIDE the trusted anchor itself:
 *
 *   - Packaged: only `<process.resourcesPath>/crm-source` is trusted
 *     (populated by electron-builder `extraResources`). If resourcesPath
 *     is missing or crm-source doesn't exist we throw an installation-
 *     integrity error rather than hunting elsewhere.
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

function resolveTrustedProjectRoot(): string | null {
  // Packaged build: the only accepted root is <resourcesPath>/crm-source.
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

/**
 * Parse a .env file into a key-value map. Same logic as ecosystem.config.js
 * so direct-mode starts get the same env vars that PM2 would provide.
 */
function parseDotEnv(file: string): Record<string, string> {
  if (!fs.existsSync(file)) return {};
  const env: Record<string, string> = {};
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
    env[key] = value;
  }
  return env;
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
  const envFromFile = parseDotEnv(path.join(root, '.env'));

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
  if (!state || !isProcessAlive(state.pid)) {
    clearDirectState();
    return { success: true, output: 'Direct server is not running' };
  }

  const stopped = runArgs('taskkill', ['/PID', String(state.pid), '/T', '/F']);
  clearDirectState();
  return stopped.success ? { success: true, output: `Stopped direct server PID ${state.pid}` } : stopped;
}

export function registerServiceControlIpc(): void {
  ipcMain.handle('service:get-status', async (): Promise<ServiceStatus> => {
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

  ipcMain.handle('service:start', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['start', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['start', 'ecosystem.config.js', '--update-env']);
    }
    return startDirectServer();
  });

  ipcMain.handle('service:stop', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['stop', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['stop', 'bizarre-crm']);
    }
    return stopDirectServer();
  });

  ipcMain.handle('service:restart', async () => {
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

  ipcMain.handle('service:emergency-stop', async () => {
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

  ipcMain.handle('service:set-auto-start', async (_event, enabled: boolean) => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      // NB: on Windows, `sc config` uses `start= <type>` — a SINGLE argv
      // token with the trailing `=`. spawnSync preserves this correctly.
      const startType = enabled ? 'auto' : 'demand';
      return runArgs('sc', ['config', SERVICE_NAME, 'start=', startType]);
    }
    if (hasPm2() && enabled) {
      return pm2Run(['save']);
    }
    return { success: false, output: 'Auto-start requires a Windows Service or PM2. Manual Start Server still works.' };
  });

  ipcMain.handle('service:disable', async () => {
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

  ipcMain.handle('service:kill-all', async () => {
    // 1. Stop PM2 managed server
    try { pm2Run(['kill']); } catch { /* ignore */ }
    try { stopDirectServer(); } catch { /* ignore */ }

    // 2. Stop Windows Service if installed
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      try { runArgs('sc', ['stop', SERVICE_NAME]); } catch { /* ignore */ }
    }

    // 3. Force-kill any remaining node processes (same user, no admin needed)
    try { runArgs('taskkill', ['/F', '/IM', 'node.exe']); } catch { /* ignore */ }

    // 4. Kill the dashboard itself
    setTimeout(() => {
      app.exit(0);
    }, 500);

    return { success: true, message: 'Killing all processes...' };
  });
}
