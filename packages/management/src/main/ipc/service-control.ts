/**
 * IPC handlers for server process control.
 * Detects whether the server runs as a Windows Service or PM2,
 * and uses the appropriate commands for each.
 */
import { ipcMain, app } from 'electron';
import { execSync } from 'node:child_process';
import path from 'node:path';

const SERVICE_NAME = 'BizarreCRM';

/** Get the CRM project root directory */
function getProjectRoot(): string {
  // app.getAppPath() = .../dashboard/resources/app.asar (packaged)
  //                   = .../packages/management (dev)
  // Either way, go up to find the dir containing ecosystem.config.js
  let dir = path.dirname(process.execPath); // .../dashboard/
  for (let i = 0; i < 5; i++) {
    try {
      const fs = require('fs') as typeof import('fs');
      if (fs.existsSync(path.join(dir, 'ecosystem.config.js'))) return dir;
    } catch { /* ignore */ }
    dir = path.dirname(dir);
  }
  // Fallback: assume dashboard/ is inside project root
  return path.dirname(path.dirname(process.execPath));
}

interface ServiceStatus {
  state: 'running' | 'stopped' | 'starting' | 'stopping' | 'unknown' | 'not_installed';
  pid: number | null;
  startType: 'auto' | 'demand' | 'disabled' | 'unknown';
  mode: 'service' | 'pm2' | 'none';
}

function runCommand(command: string, cwd?: string): { success: boolean; output: string } {
  try {
    const output = execSync(command, { encoding: 'utf-8', timeout: 15_000, cwd });
    return { success: true, output };
  } catch (err) {
    const message = err instanceof Error ? (err as { stderr?: string }).stderr ?? err.message : 'Unknown error';
    return { success: false, output: message };
  }
}

function pm2Command(command: string): { success: boolean; output: string } {
  return runCommand(`pm2 ${command}`, getProjectRoot());
}

function hasPm2(): boolean {
  return runCommand('pm2 --version', getProjectRoot()).success;
}

function getPm2Status(): { running: boolean; pid: number | null } {
  const result = runCommand('pm2 jlist', getProjectRoot());
  if (!result.success) return { running: false, pid: null };
  try {
    const list = JSON.parse(result.output);
    const app = list.find((p: { name: string }) => p.name === 'bizarre-crm');
    if (!app) return { running: false, pid: null };
    return {
      running: app.pm2_env?.status === 'online',
      pid: app.pid ?? null,
    };
  } catch {
    return { running: false, pid: null };
  }
}

function getWindowsServiceStatus(): { installed: boolean; running: boolean; pid: number | null; startType: ServiceStatus['startType'] } {
  const query = runCommand(`sc query ${SERVICE_NAME}`);
  if (!query.success) {
    return { installed: false, running: false, pid: null, startType: 'unknown' };
  }

  const stateMatch = query.output.match(/STATE\s+:\s+\d+\s+(\w+)/);
  const pidMatch = query.output.match(/PID\s+:\s+(\d+)/);
  const rawState = stateMatch?.[1]?.toLowerCase() ?? '';
  const running = rawState === 'running';
  const pid = pidMatch ? parseInt(pidMatch[1], 10) : null;

  let startType: ServiceStatus['startType'] = 'unknown';
  const config = runCommand(`sc qc ${SERVICE_NAME}`);
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
      return runCommand(`sc start ${SERVICE_NAME}`);
    }
    if (hasPm2()) {
      return pm2Command('start ecosystem.config.js');
    }
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:stop', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      return runCommand(`sc stop ${SERVICE_NAME}`);
    }
    if (hasPm2()) {
      return pm2Command('stop bizarre-crm');
    }
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:restart', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runCommand(`sc stop ${SERVICE_NAME}`);
      let attempts = 0;
      while (attempts < 10) {
        const query = runCommand(`sc query ${SERVICE_NAME}`);
        if (query.output.includes('STOPPED')) break;
        await new Promise(r => setTimeout(r, 1000));
        attempts++;
      }
      return runCommand(`sc start ${SERVICE_NAME}`);
    }
    if (hasPm2()) {
      return pm2Command('restart bizarre-crm');
    }
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:emergency-stop', async () => {
    // Kill everything
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runCommand(`taskkill /F /FI "SERVICES eq ${SERVICE_NAME}"`);
      runCommand(`sc stop ${SERVICE_NAME}`);
    }
    if (hasPm2()) {
      pm2Command('kill');
    }
    return { success: true, message: 'Emergency stop executed' };
  });

  ipcMain.handle('service:set-auto-start', async (_event, enabled: boolean) => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      const startType = enabled ? 'auto' : 'demand';
      return runCommand(`sc config ${SERVICE_NAME} start= ${startType}`);
    }
    if (hasPm2() && enabled) {
      return pm2Command('save');
    }
    return { success: false, output: 'No Windows Service installed' };
  });

  ipcMain.handle('service:disable', async () => {
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      runCommand(`sc stop ${SERVICE_NAME}`);
      return runCommand(`sc config ${SERVICE_NAME} start= disabled`);
    }
    if (hasPm2()) {
      return pm2Command('stop bizarre-crm');
    }
    return { success: false, output: 'No service or PM2 found' };
  });

  ipcMain.handle('service:kill-all', async () => {
    // 1. Stop PM2 managed server
    try { pm2Command('kill'); } catch { /* ignore */ }

    // 2. Stop Windows Service if installed
    const svc = getWindowsServiceStatus();
    if (svc.installed) {
      try { runCommand(`sc stop ${SERVICE_NAME}`); } catch { /* ignore */ }
    }

    // 3. Force-kill any remaining node processes (same user, no admin needed)
    try { runCommand('taskkill /F /IM node.exe'); } catch { /* ignore */ }

    // 4. Kill the dashboard itself
    setTimeout(() => {
      app.exit(0);
    }, 500);

    return { success: true, message: 'Killing all processes...' };
  });
}
