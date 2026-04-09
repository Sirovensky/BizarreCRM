/**
 * Electron Main Process — BizarreCRM Management Dashboard v2
 *
 * Creates a desktop window running a React dashboard that communicates
 * with the local CRM server via REST API. The server runs as a separate
 * Windows Service — dashboard crash/close never affects the server.
 */
import { app, BrowserWindow } from 'electron';
import { createWindow } from './window.js';
import { registerManagementIpc } from './ipc/management-api.js';
import { registerServiceControlIpc } from './ipc/service-control.js';
import { registerSystemInfoIpc } from './ipc/system-info.js';

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
