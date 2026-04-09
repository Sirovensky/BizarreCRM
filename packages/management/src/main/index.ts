/**
 * Electron Main Process — BizarreCRM Management Dashboard v2
 *
 * Creates a desktop window running a React dashboard that communicates
 * with the local CRM server via REST API. The server runs as a separate
 * Windows Service — dashboard crash/close never affects the server.
 */
import { app, BrowserWindow } from 'electron';
import fs from 'fs';
import path from 'path';
import { createWindow } from './window.js';
import { registerManagementIpc } from './ipc/management-api.js';
import { registerServiceControlIpc } from './ipc/service-control.js';
import { registerSystemInfoIpc } from './ipc/system-info.js';

// ── Console redirect (packaged app only) ────────────────────────────
// When launched from setup.bat via `start ""`, the EXE inherits the CMD's
// console handles. Any console.log keeps the pipe alive, preventing the
// CMD window from closing. Redirect to a log file to break the pipe.

if (app.isPackaged) {
  try {
    const logDir = app.getPath('userData');
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
    const logPath = path.join(logDir, 'dashboard.log');
    const logStream = fs.createWriteStream(logPath, { flags: 'a' });
    const ts = () => new Date().toISOString().replace('T', ' ').substring(0, 19);
    console.log = (...args: unknown[]) => { logStream.write(`${ts()} ${args.join(' ')}\n`); };
    console.error = (...args: unknown[]) => { logStream.write(`${ts()} [ERROR] ${args.join(' ')}\n`); };
    console.warn = (...args: unknown[]) => { logStream.write(`${ts()} [WARN] ${args.join(' ')}\n`); };
  } catch { /* if logging fails, continue silently */ }
}

// ── Crash safety: log but don't crash the dashboard ─────────────────

process.on('uncaughtException', (error) => {
  console.error('[Dashboard] Uncaught exception:', error.message);
  console.error(error.stack);
});

process.on('unhandledRejection', (reason) => {
  console.error('[Dashboard] Unhandled rejection:', reason);
});

// ── IPC Registration ────────────────────────────────────────────────

registerManagementIpc();
registerServiceControlIpc();
registerSystemInfoIpc();

// ── App Lifecycle ───────────────────────────────────────────────────

// Fix horizontal line flickering on some GPUs (common Electron/Chromium issue)
app.disableHardwareAcceleration();

app.whenReady().then(() => {
  console.log('[Dashboard] App path:', app.getAppPath());
  console.log('[Dashboard] isPackaged:', app.isPackaged);
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  app.quit();
});
