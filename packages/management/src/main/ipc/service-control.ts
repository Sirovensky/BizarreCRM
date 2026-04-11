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
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import fs from 'node:fs';

const SERVICE_NAME = 'BizarreCRM';

/** True if `child` is inside (or equal to) `parent`. */
function isPathUnder(child: string, parent: string): boolean {
  const resolvedChild = path.resolve(child);
  const resolvedParent = path.resolve(parent);
  if (resolvedChild === resolvedParent) return true;
  const rel = path.relative(resolvedParent, resolvedChild);
  return !!rel && !rel.startsWith('..') && !path.isAbsolute(rel);
}

/**
 * EL3: Locate the CRM project root from TRUSTED anchors only. Walking up
 * from `process.execPath` lets anyone who can drop a file anywhere above
 * the Electron binary redirect us. We only trust `app.getAppPath()` and
 * `process.resourcesPath`, both of which live inside the installed app.
 *
 * Same algorithm as `management-api.ts.resolveTrustedProjectRoot()` — kept
 * in-file rather than shared so the two modules remain decoupled at the
 * source level.
 */
function resolveTrustedProjectRoot(): string | null {
  const anchors = [app.getAppPath(), process.resourcesPath].filter(
    (p): p is string => typeof p === 'string' && p.length > 0
  );

  for (const anchor of anchors) {
    let dir = path.resolve(anchor);
    const anchorRoot = dir;
    for (let i = 0; i < 6; i++) {
      const marker =
        fs.existsSync(path.join(dir, 'ecosystem.config.js')) ||
        fs.existsSync(path.join(dir, 'setup.bat'));
      if (marker) {
        if (isPathUnder(dir, path.parse(anchorRoot).root)) {
          return dir;
        }
      }
      const parent = path.dirname(dir);
      if (parent === dir) break;
      dir = parent;
    }
  }
  return null;
}

function getProjectRoot(): string | null {
  return resolveTrustedProjectRoot();
}

interface ServiceStatus {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'none';
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

function pm2Run(args: readonly string[]): CommandResult {
  const root = getProjectRoot();
  return runArgs('pm2', args, root ?? undefined);
}

function hasPm2(): boolean {
  return pm2Run(['--version']).success;
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

    return { state: 'not_installed', pid: null, startType: 'unknown', mode: 'none' };
  });

  ipcMain.handle('service:start', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['start', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['start', 'ecosystem.config.js']);
    }
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:stop', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runArgs('sc', ['stop', SERVICE_NAME]);
    }
    if (hasPm2()) {
      return pm2Run(['stop', 'bizarre-crm']);
    }
    return { success: false, output: 'No service or PM2 found' };
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
      return pm2Run(['restart', 'bizarre-crm']);
    }
    return { success: false, output: 'No service or PM2 found' };
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
    return { success: false, output: 'No Windows Service installed' };
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
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:kill-all', async () => {
    // 1. Stop PM2 managed server
    try { pm2Run(['kill']); } catch { /* ignore */ }

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
