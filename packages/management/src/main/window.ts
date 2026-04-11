/**
 * BrowserWindow creation and lifecycle management.
 * The window is NOT closable by default — must use the dashboard's close button.
 *
 * Uses app.getAppPath() for reliable path resolution in both dev and packaged builds.
 */
import { BrowserWindow, app } from 'electron';
import path from 'node:path';

let mainWindow: BrowserWindow | null = null;
let closeAllowed = false;

/** Resolve a path relative to the app root (works in asar and dev) */
function appPath(...segments: string[]): string {
  return path.join(app.getAppPath(), ...segments);
}

export function getMainWindow(): BrowserWindow | null {
  return mainWindow;
}

export function allowClose(): void {
  closeAllowed = true;
}

export function createWindow(): BrowserWindow {
  const preloadPath = appPath('dist', 'preload', 'index.cjs');

  mainWindow = new BrowserWindow({
    width: 1200,
    height: 850,
    minWidth: 900,
    minHeight: 600,
    title: 'BizarreCRM Server Dashboard',
    icon: appPath('assets', 'icon.ico'),
    frame: false,
    show: true,
    backgroundColor: '#09090b',
    webPreferences: {
      preload: preloadPath,
      contextIsolation: true,
      nodeIntegration: false,
      // SECURITY (EL2): sandboxed renderer. The preload script only uses
      // `contextBridge` + `ipcRenderer.invoke`, both of which work inside
      // sandboxed preloads. If you add Node-module imports to the preload
      // (`fs`, `path`, etc.) you will need to refactor those into IPC
      // handlers in the main process — do NOT disable the sandbox.
      sandbox: true,
    },
  });

  // Block close unless explicitly allowed via dashboard button
  mainWindow.on('close', (e) => {
    if (!closeAllowed) {
      e.preventDefault();
    }
  });

  mainWindow.on('closed', () => {
    mainWindow = null;
    closeAllowed = false;
  });

  // Load the renderer
  if (!app.isPackaged && process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(appPath('dist', 'renderer', 'index.html'));
  }

  return mainWindow;
}
