/**
 * Electron Main Process — BizarreCRM Management Dashboard v2
 *
 * Creates a desktop window running a React dashboard that communicates
 * with the local CRM server via REST API. The server runs as a separate
 * Windows Service — dashboard crash/close never affects the server.
 *
 * @audit-fixed (audit issue #10): UAC model
 * ----------------------------------------
 * Prior to this fix the app declared `requestedExecutionLevel:
 * requireAdministrator` in electron-builder.yml, so every dashboard launch
 * forced a UAC consent prompt — even though viewing stats, editing settings,
 * or reading logs never needed admin. Only a tiny subset of actions (restart
 * the Windows service / PM2 process) actually required elevation.
 *
 * New model: the .exe runs as `asInvoker` (no prompt on launch). When a
 * privileged action is requested, `spawnElevated()` below shells out via
 * `powershell Start-Process -Verb RunAs`, which triggers a single UAC prompt
 * just-in-time for THAT action. The user consents once, the elevated child
 * runs, the dashboard itself stays unelevated.
 *
 * Trade-off: everyday dashboard use is admin-free (major UX win). Actions
 * that need admin — currently only service restart — show a UAC consent
 * prompt at click-time instead of at launch-time.
 */
import { app, BrowserWindow, Menu } from 'electron';
import { spawn } from 'node:child_process';
import fs from 'fs';
import path from 'path';
import { createWindow, getMainWindow } from './window.js';
import { registerManagementIpc } from './ipc/management-api.js';
import { registerServiceControlIpc } from './ipc/service-control.js';
import { registerSystemInfoIpc } from './ipc/system-info.js';
import { setSuperAdminToken } from './services/api-client.js';

// ── Console redirect (packaged app only) ────────────────────────────
// When launched from setup.bat via `start ""`, the EXE inherits the CMD's
// console handles. Any console.log keeps the pipe alive, preventing the
// CMD window from closing. Redirect to a log file to break the pipe.

// ── MGT-020: Log rotation ────────────────────────────────────────────
// Rotate dashboard.log before opening it so a single run never grows
// unboundedly. Keeps at most one backup (.log.1). Silently skips if the
// file doesn't exist yet or can't be stat'd (first run, read-only fs).
//
// Retention policy (DASH-ELEC-113):
//   - Active file: dashboard.log  — max 10 MB before rotation
//   - Single backup: dashboard.log.1 — retained until the next rotation
//   - Total on-disk budget: ~20 MB for log data
//   - On a busy install (hundreds of IPC calls/min) the active file can fill
//     in under a day; the backup holds the immediately preceding segment.
//   - If more history is needed, configure a host-level log rotation tool
//     (e.g. logrotate on Linux, pm2-logrotate on Node, Task Scheduler on
//     Windows) pointing at the userData directory. The app itself does not
//     purge older archives to avoid destroying operator evidence.
//   - To increase the backup count or rotate threshold, pass different
//     maxBytes to rotateLogIfLarge() in the call below (future: expose via
//     platform_config / settings.json).
function rotateLogIfLarge(logPath: string, maxBytes = 10 * 1024 * 1024): void {
  try {
    const s = fs.statSync(logPath);
    if (s.size > maxBytes) {
      const bak = logPath + '.1';
      try { fs.unlinkSync(bak); } catch { /* no existing backup — fine */ }
      fs.renameSync(logPath, bak);
    }
  } catch { /* file absent or unreadable — nothing to rotate */ }
}

if (app.isPackaged) {
  try {
    const logDir = app.getPath('userData');
    if (!fs.existsSync(logDir)) fs.mkdirSync(logDir, { recursive: true });
    const logPath = path.join(logDir, 'dashboard.log');
    // MGT-020: rotate before opening so a single run never grows unboundedly.
    rotateLogIfLarge(logPath);
    const logStream = fs.createWriteStream(logPath, { flags: 'a' });
    // @audit-fixed: previously the redirected console methods silently
    // dropped writes if `logStream.write()` failed (disk full, ENOSPC,
    // permission revoked, etc.) — the original `console.log/error/warn`
    // were lost forever once reassigned, so failures had nowhere to go.
    // We now keep references to the originals and route any write error
    // back through them so at least the underlying ENOSPC shows up in
    // the inherited cmd console (or stderr) instead of vanishing.
    // The `unhandled` listener on logStream itself catches stream-level
    // errors that occur outside the synchronous write call.
    const originalLog = console.log.bind(console);
    const originalError = console.error.bind(console);
    const originalWarn = console.warn.bind(console);
    logStream.on('error', (err) => {
      try {
        originalError('[Dashboard] log stream error:', err.message);
      } catch {
        /* nothing else we can do */
      }
    });
    const ts = () => new Date().toISOString().replace('T', ' ').substring(0, 19);
    const safeWrite = (
      prefix: string,
      original: (...args: unknown[]) => void,
      args: unknown[],
    ): void => {
      try {
        const writable = logStream.write(`${ts()} ${prefix}${args.join(' ')}\n`);
        if (!writable) {
          // backpressure — let it drain on its own; we don't await here.
        }
      } catch (err) {
        try {
          original('[fallback]', ...args);
          original('[fallback-reason]', err instanceof Error ? err.message : String(err));
        } catch {
          /* nothing else we can do */
        }
      }
    };
    console.log = (...args: unknown[]) => { safeWrite('', originalLog, args); };
    console.error = (...args: unknown[]) => { safeWrite('[ERROR] ', originalError, args); };
    console.warn = (...args: unknown[]) => { safeWrite('[WARN] ', originalWarn, args); };
  } catch (err) {
    // Even setup itself failed (e.g. read-only filesystem). Surface this
    // to the inherited console exactly once and continue without the
    // file-based log — the dashboard still boots.
    try {
      console.error('[Dashboard] log redirect failed:', err instanceof Error ? err.message : String(err));
    } catch {
      /* nothing else we can do */
    }
  }
}

// ── Crash safety: log but don't crash the dashboard ─────────────────

process.on('uncaughtException', (error) => {
  console.error('[Dashboard] Uncaught exception:', error.message);
  console.error(error.stack);
});

process.on('unhandledRejection', (reason) => {
  // Log only the message string, never the raw object — it may carry
  // Authorization headers, JWT payloads, or cleartext passwords from
  // failed Zod parses (DASH-ELEC-110).
  const msg = reason instanceof Error ? reason.message : String(reason);
  console.error('[Dashboard] Unhandled rejection:', msg);
});

// ── Elevated spawn (UAC on-demand) ──────────────────────────────────
// @audit-fixed (audit issue #10): just-in-time elevation helper.
//
// The dashboard launches as `asInvoker` (no UAC on startup). When a
// privileged action is requested (pm2 restart, sc start, etc.) the IPC
// handler should call `spawnElevated(command, args)` instead of
// `spawnSync(command, args)`. That routes the call through PowerShell's
// `Start-Process -Verb RunAs`, which pops a Windows UAC consent dialog
// for THAT action only. The user approves, the elevated child runs, and
// the dashboard process itself stays unelevated.
//
// Security notes:
//   * `shell: false` — we hand PowerShell an explicit argv array, so args
//     reach the child verbatim. No shell interpolation.
//   * The caller is responsible for ensuring `command` and `args` come
//     from trusted in-app constants, never from user input or from IPC
//     parameters supplied by the renderer. (Same policy as
//     service-control.ts's existing `runArgs()`.)
//   * PowerShell's `Start-Process` is fire-and-forget from our perspective
//     — we can't block on it synchronously because the UAC prompt is
//     asynchronous. Callers that need to know whether the elevated child
//     succeeded must poll state afterwards (e.g. re-query service status).
//
// Usage (from service-control.ts, once wired up):
//   import { spawnElevated } from '../index.js';
//   spawnElevated('pm2', ['restart', 'bizarre-crm']);
//   spawnElevated('sc',  ['start', 'BizarreCRM']);
//
// The helper is exported so service-control.ts can import it without us
// having to touch that file in this change.
interface SpawnElevatedResult {
  readonly started: boolean;
  readonly message: string;
}

// DASH-ELEC-003: Hard-coded whitelist of executables that may be launched via
// spawnElevated. Only the service-management binaries this app actually uses
// are listed. Any caller that passes a command not in this set is rejected
// immediately, so a future maintainer cannot accidentally route variable/user
// input through the elevated-spawn path.
const ELEVATED_COMMAND_ALLOWLIST = new Set<string>([
  'pm2',
  'pm2.cmd',
  'sc',          // Windows Service Control Manager
  'sc.exe',
  'net',         // `net start/stop <ServiceName>`
  'net.exe',
  'powershell',
  'powershell.exe',
]);

export function spawnElevated(
  command: string,
  args: readonly string[],
): SpawnElevatedResult {
  // Reject commands that are not in the allowlist before doing anything else.
  // path.basename strips any directory prefix so callers using an absolute
  // path to pm2.cmd still resolve correctly against the set.
  const commandBasename = path.basename(command).toLowerCase();
  if (!ELEVATED_COMMAND_ALLOWLIST.has(commandBasename)) {
    const msg = `[Dashboard] spawnElevated rejected: '${command}' is not in the elevated-command allowlist.`;
    console.error(msg);
    return { started: false, message: msg };
  }

  // Build the PowerShell -ArgumentList as a single quoted string. Each
  // argument is wrapped in single quotes and any embedded single quotes
  // are doubled up, matching PowerShell's literal-string escaping rules.
  // This keeps the argv intact even when args contain spaces.
  const psQuote = (arg: string): string => `'${arg.replace(/'/g, "''")}'`;
  const argumentList = args.map(psQuote).join(',');

  // Start-Process parameters: -FilePath, -ArgumentList, -Verb RunAs.
  // -Verb RunAs is what triggers the UAC consent prompt. -WindowStyle
  // Hidden keeps the elevated console from flashing up.
  const psCommand = argumentList.length > 0
    ? `Start-Process -FilePath ${psQuote(command)} -ArgumentList ${argumentList} -Verb RunAs -WindowStyle Hidden`
    : `Start-Process -FilePath ${psQuote(command)} -Verb RunAs -WindowStyle Hidden`;

  try {
    // `detached: true` + `unref()` so the elevated child outlives us if
    // the dashboard is closed mid-operation (the user may click restart
    // and immediately close the window — the restart should still run).
    const child = spawn(
      'powershell.exe',
      ['-NoProfile', '-NonInteractive', '-Command', psCommand],
      {
        shell: false,
        detached: true,
        stdio: 'ignore',
        windowsHide: true,
      },
    );
    child.unref();
    child.on('error', (err) => {
      console.error('[Dashboard] spawnElevated failed to launch:', err.message);
    });
    return {
      started: true,
      message: `Elevation requested for: ${command} ${args.join(' ')}`,
    };
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error('[Dashboard] spawnElevated threw:', message);
    return { started: false, message };
  }
}

// ── IPC Registration ────────────────────────────────────────────────

registerManagementIpc();
registerServiceControlIpc();
registerSystemInfoIpc();

// ── MGT-017: Custom-protocol handler stub ────────────────────────────
// Infrastructure only — no renderer code consumes this URL scheme yet.
// Registers the `bizarrecrm-dashboard://` deep-link scheme so the OS
// can route protocol links to this app. Actual link handling is done in:
//   • macOS: `open-url` event below
//   • Windows: `second-instance` argv scanner (in MGT-016 handler below)
//
// Security: only URLs whose scheme is exactly 'bizarrecrm-dashboard:'
// are accepted. Any other scheme is logged and ignored.
const ALLOWED_PROTOCOL_SCHEME = 'bizarrecrm-dashboard:';

function handleProtocolUrl(url: string): void {
  try {
    const parsed = new URL(url);
    if (parsed.protocol !== ALLOWED_PROTOCOL_SCHEME) {
      console.warn('[Dashboard] MGT-017: rejected unknown protocol URL scheme:', parsed.protocol);
      return;
    }
    // Placeholder — renderer integration is a future task.
    console.log('[Dashboard] MGT-017: received protocol URL:', url);
  } catch {
    console.warn('[Dashboard] MGT-017: malformed protocol URL received');
  }
}

// macOS: system fires `open-url` for deep links (app may already be running).
app.on('open-url', (event, url) => {
  event.preventDefault();
  handleProtocolUrl(url);
});

app.setAsDefaultProtocolClient('bizarrecrm-dashboard');

// ── MGT-016: Single-instance lock ────────────────────────────────────
// Prevent two copies of the dashboard from running at the same time.
// The second instance immediately quits; the first instance's window is
// brought to the foreground instead.
const gotLock = app.requestSingleInstanceLock();
if (!gotLock) {
  app.quit();
  process.exit(0);
}

app.on('second-instance', (_event, argv) => {
  // MGT-016: bring the existing window to front.
  const win = getMainWindow();
  if (win) {
    if (win.isMinimized()) win.restore();
    win.show();
    win.focus();
  }
  // MGT-017 (Windows): scan argv for a deep-link URL forwarded by the OS.
  const url = argv.find((arg) => arg.startsWith('bizarrecrm-dashboard:'));
  if (url) handleProtocolUrl(url);
});

// ── App Lifecycle ───────────────────────────────────────────────────

// Fix horizontal line flickering on some GPUs (common Electron/Chromium issue)
app.disableHardwareAcceleration();

// EL8: Kill the default application menu in packaged builds so the
// Ctrl+Shift+I / F12 / Cmd+Option+I shortcuts stop opening DevTools.
// The renderer ships its own frameless UI — the native menu is unused.
if (app.isPackaged) {
  Menu.setApplicationMenu(null);
}

app.whenReady().then(() => {
  // SEC: Only log path/packaging details in development — avoids leaking the
  // local username and install layout to disk in packaged (production) builds.
  if (!app.isPackaged) {
    console.log('[Dashboard] App path:', app.getAppPath());
    console.log('[Dashboard] isPackaged:', app.isPackaged);
  }
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

// DASH-ELEC-262: zero-out the in-memory super-admin token before the process
// terminates so it cannot be read from a process snapshot / core dump taken
// in the brief window between the last IPC call and process exit.
app.on('before-quit', () => {
  setSuperAdminToken(null);
});
