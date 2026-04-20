/**
 * BrowserWindow creation and lifecycle management.
 * The window is NOT closable by default — must use the dashboard's close button.
 *
 * Uses app.getAppPath() for reliable path resolution in both dev and packaged builds.
 *
 * Security (post-enrichment):
 *  - EL8: DevTools is blocked in packaged builds. The renderer only talks
 *    to the local CRM over IPC — there is no reason for a shipped dashboard
 *    to expose a DevTools panel, and leaving it open hands an attacker a
 *    console into `window.management` and the local API token.
 *  - EL9: `will-navigate`, `setWindowOpenHandler`, and `will-attach-webview`
 *    are locked down. The renderer is a single-page React app loaded from
 *    a local file; any navigation to a remote origin, popup, or webview
 *    is a prompt-injection attempt or a compromised dependency.
 */
import { BrowserWindow, app, shell, session } from 'electron';
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

/**
 * EL9 / AUDIT-MGT-027: Is this URL safe for the renderer to navigate to
 * in-place?
 *
 * Previously the packaged branch accepted ANY `file://` URL, which means a
 * compromised or injected navigation to any local file (e.g. an attacker-
 * written HTML dropped on disk) would have been allowed. We now require the
 * decoded path to start with the trusted `dist/renderer` directory inside the
 * app, mirroring the path-prefix check in `assertRendererOrigin`.
 *
 * In dev mode we still accept only the exact Vite dev-server origin.
 */
function isAllowedRendererUrl(target: string): boolean {
  try {
    const parsed = new URL(target);
    if (parsed.protocol === 'file:') {
      // AUDIT-MGT-027: Apply path-prefix check — bare `file://` is insufficient.
      const rendererDir = path.resolve(app.getAppPath(), 'dist', 'renderer');
      // URL pathnames use forward slashes on all platforms; decode percent-encoding.
      const decodedPath = decodeURIComponent(parsed.pathname);
      // Normalise separators so Windows paths compare correctly.
      const normalizedPath = decodedPath.replace(/\//g, path.sep);
      const resolvedPath = path.resolve(normalizedPath);
      if (resolvedPath === rendererDir || resolvedPath.startsWith(rendererDir + path.sep)) {
        return true;
      }
      return false;
    }
    if (!app.isPackaged && process.env.VITE_DEV_SERVER_URL) {
      const dev = new URL(process.env.VITE_DEV_SERVER_URL);
      return (
        parsed.protocol === dev.protocol &&
        parsed.hostname === dev.hostname &&
        parsed.port === dev.port
      );
    }
    return false;
  } catch {
    return false;
  }
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
      // EL8: In a packaged build we disable DevTools entirely. The renderer
      // has no need for it in production, and leaving it on lets an
      // attacker who lands arbitrary script in the renderer (e.g. via a
      // compromised dependency) open a full debugging console against
      // window.management. In dev builds we leave it on for debugging.
      devTools: !app.isPackaged,
      // Disable webview tag — we never embed third-party content.
      webviewTag: false,
      // Explicit: no remote loading via <script src> from http(s).
      webSecurity: true,
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

  // EL8: Even if an attacker finds a way to call `openDevTools()` from the
  // renderer, re-close it. In packaged builds `devTools: false` should
  // prevent this entirely; this is the belt to the `devTools: false` braces.
  if (app.isPackaged) {
    mainWindow.webContents.on('devtools-opened', () => {
      mainWindow?.webContents.closeDevTools();
    });
  }

  // EL9: Deny any attempt to navigate the main frame off the allowed
  // origins. A compromised script trying to loadURL('https://attacker/')
  // lands here and is rejected before it can run.
  mainWindow.webContents.on('will-navigate', (event, url) => {
    if (!isAllowedRendererUrl(url)) {
      event.preventDefault();
      console.warn('[window] Blocked navigation to:', url);
    }
  });

  // EL9: Any attempt to open a popup / target=_blank link is redirected
  // to the OS default browser via shell.openExternal, but only after we
  // check the URL is http(s) (no file:// or javascript: URIs).
  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    try {
      const parsed = new URL(url);
      if (parsed.protocol === 'http:' || parsed.protocol === 'https:') {
        void shell.openExternal(url);
      } else {
        console.warn('[window] Blocked window.open with non-http URL:', url);
      }
    } catch {
      console.warn('[window] Blocked window.open with invalid URL');
    }
    return { action: 'deny' };
  });

  // EL9: Webview creation is disabled by `webviewTag: false`, but if an
  // attacker ever tries to re-enable it by replacing the HTML, refuse at
  // the attach step as well.
  mainWindow.webContents.on('will-attach-webview', (event) => {
    event.preventDefault();
  });

  // EL9: Deny all permission requests (camera, mic, notifications, etc.).
  // A server-management dashboard should never ask for hardware access;
  // anything that does is almost certainly an injection attempt.
  session.defaultSession.setPermissionRequestHandler((_wc, _permission, callback) => {
    callback(false);
  });

  // Load the renderer
  if (!app.isPackaged && process.env.VITE_DEV_SERVER_URL) {
    mainWindow.loadURL(process.env.VITE_DEV_SERVER_URL);
  } else {
    mainWindow.loadFile(appPath('dist', 'renderer', 'index.html'));
  }

  return mainWindow;
}
