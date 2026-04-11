/**
 * Electron Main Process — BizarreCRM Management Dashboard
 *
 * Creates a desktop window that connects to the local CRM server
 * and displays real-time stats, crash logs, and management controls.
 * All communication goes through localhost:443 (the Express server).
 */
const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');
const https = require('https');

// Self-signed cert handling is done per-request via rejectUnauthorized: false
// in apiRequest(). We do NOT set NODE_TLS_REJECT_UNAUTHORIZED globally.

const SERVER_URL = 'https://localhost';
let mainWindow = null;
let managementToken = null;

let closeAllowed = false;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 750,
    title: 'BizarreCRM Server Dashboard',
    icon: path.join(__dirname, 'renderer', 'icon.png'),
    closable: false,     // Remove the X button from title bar
    minimizable: true,
    maximizable: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  // Block close unless explicitly allowed via the dashboard button
  mainWindow.on('close', (e) => {
    if (!closeAllowed) {
      e.preventDefault();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    closeAllowed = false; // Reset so reopened windows can't be closed without confirmation
  });
}

// ── API Helper ─────────────────────────────────────────────────────────

function apiRequest(method, endpoint, body = null) {
  return new Promise((resolve, reject) => {
    const url = new URL(`${SERVER_URL}/api/v1/management${endpoint}`);
    const options = {
      method,
      hostname: url.hostname,
      port: url.port || 443,
      path: url.pathname,
      rejectUnauthorized: false,
      headers: {
        'Content-Type': 'application/json',
      },
    };

    if (managementToken) {
      options.headers['X-Management-Token'] = managementToken;
    }

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => { data += chunk; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: JSON.parse(data) });
        } catch {
          resolve({ status: res.statusCode, body: { success: false, message: data } });
        }
      });
    });

    req.on('error', (err) => reject(err));
    req.setTimeout(30000, () => { req.destroy(); reject(new Error('Request timeout')); });

    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

// ── Server Health Polling ──────────────────────────────────────────────
// The management dashboard uses REST polling (every 5 seconds from the renderer)
// instead of WebSocket. The WS server requires JWT auth which the Electron app
// doesn't have — it uses its own management token auth via REST API.

// ── IPC Handlers ───────────────────────────────────────────────────────

ipcMain.handle('management:login', async (_event, username, password) => {
  try {
    const res = await apiRequest('POST', '/login', { username, password });
    if (res.body.success && res.body.data?.token) {
      managementToken = res.body.data.token;
    }
    return res.body;
  } catch (err) {
    return { success: false, message: 'Server not reachable: ' + err.message };
  }
});

ipcMain.handle('management:get-stats', async () => {
  try {
    const res = await apiRequest('GET', '/stats');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:get-crashes', async () => {
  try {
    const res = await apiRequest('GET', '/crashes');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:get-disabled-routes', async () => {
  try {
    const res = await apiRequest('GET', '/disabled-routes');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:reenable-route', async (_event, route) => {
  try {
    const res = await apiRequest('POST', '/reenable-route', { route });
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:clear-crashes', async () => {
  try {
    const res = await apiRequest('POST', '/clear-crashes');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:get-update-status', async () => {
  try {
    const res = await apiRequest('GET', '/update-status');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:check-updates', async () => {
  try {
    const res = await apiRequest('POST', '/check-updates');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:perform-update', async () => {
  try {
    const res = await apiRequest('POST', '/perform-update');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:restart-server', async () => {
  try {
    const res = await apiRequest('POST', '/restart');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

ipcMain.handle('management:stop-server', async () => {
  try {
    const res = await apiRequest('POST', '/stop');
    return res.body;
  } catch (err) {
    return { success: false, message: err.message };
  }
});

// NOTE (T6): This file (src/main.js) is the legacy v1 entrypoint and has been
// superseded by src/main/index.ts. It is kept only so old references don't
// break. The handlers below previously returned { success: true } for
// features that were never fully wired here — they now return an honest
// NOT_IMPLEMENTED error and direct callers to the new IPC channels defined
// in src/main/ipc/management-api.ts and src/main/ipc/system-info.ts.

ipcMain.handle('management:open-browser', () => {
  return {
    success: false,
    error: 'NOT_IMPLEMENTED',
    code: 501,
    message:
      'management:open-browser is not implemented in the legacy main.js entrypoint. ' +
      'Use system:open-browser from the v2 dashboard (src/main/index.ts).',
  };
});

ipcMain.handle('management:view-logs', () => {
  return {
    success: false,
    error: 'NOT_IMPLEMENTED',
    code: 501,
    message:
      'management:view-logs is not implemented in the legacy main.js entrypoint. ' +
      'Use system:open-log-file from the v2 dashboard (src/main/index.ts).',
  };
});

ipcMain.handle('management:close-dashboard', () => {
  return {
    success: false,
    error: 'NOT_IMPLEMENTED',
    code: 501,
    message:
      'management:close-dashboard is not implemented in the legacy main.js entrypoint. ' +
      'Use system:close-dashboard from the v2 dashboard (src/main/index.ts).',
  };
});

// ── App Lifecycle ──────────────────────────────────────────────────────

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  app.quit();
});
