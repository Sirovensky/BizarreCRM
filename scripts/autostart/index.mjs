/**
 * Cross-platform auto-startup adapter — public API.
 *
 * setup.mjs (and any future caller) imports `register`, `unregister`, and
 * `status` from this module. Internally these dispatch by `process.platform`
 * to a per-OS adapter (linux.mjs / darwin.mjs / win32.mjs) which is the only
 * file in the codebase allowed to contain OS-specific install logic.
 *
 * Each adapter exposes the same three functions so the caller never knows
 * which OS it is running on. Adding a new OS = one new adapter file + one
 * new entry in the `adapters` map below; nothing else in the codebase changes.
 *
 * Spec passed to register():
 *
 *   {
 *     name:        'BizarreCRM-PM2',         // task / service identifier
 *     description: 'BizarreCRM PM2 ...',     // human-readable, optional
 *     command:     '/abs/path/to/node',      // executable
 *     args:        [pm2BinPath, 'resurrect'],// argv after the executable
 *     env:         { PM2_HOME: '...' },      // env vars baked into the unit
 *     workingDir:  '/abs/path/to/repo',      // process cwd at boot
 *   }
 *
 * Caller is responsible for resolving absolute paths (Node, pm2) and the
 * tenant / repo root. Adapters do NOT touch the filesystem outside of their
 * OS-mandated locations (Task Scheduler XML, systemd unit, launchd plist).
 */

const adapters = {
  linux: () => import('./linux.mjs'),
  darwin: () => import('./darwin.mjs'),
  win32: () => import('./win32.mjs'),
};

async function adapter() {
  const load = adapters[process.platform];
  if (!load) {
    throw new Error(`Auto-startup not supported on platform: ${process.platform}`);
  }
  return await load();
}

/**
 * Install (or reinstall) the boot-time auto-startup hook for `spec`.
 * Returns `{ ok, mechanism, message }`.
 *
 * Idempotent: if the hook already exists with identical config, the adapter
 * is allowed to no-op + return `{ ok: true }`. If the existing hook differs,
 * the adapter must replace it cleanly (stop existing, install new).
 */
export async function register(spec) {
  if (!spec || typeof spec !== 'object') {
    throw new Error('register(spec) requires a non-null spec object');
  }
  const required = ['name', 'command', 'args', 'workingDir'];
  for (const key of required) {
    if (spec[key] === undefined || spec[key] === null) {
      throw new Error(`register(spec) missing required field: ${key}`);
    }
  }
  return (await adapter()).register(spec);
}

/**
 * Remove the boot-time auto-startup hook installed by `register({ name })`.
 * Returns `{ ok, message }`. Returns `{ ok: true }` even if the hook was
 * already absent — uninstall is idempotent.
 */
export async function unregister(name) {
  if (typeof name !== 'string' || name.length === 0) {
    throw new Error('unregister(name) requires a non-empty string');
  }
  return (await adapter()).unregister(name);
}

/**
 * Read whether the boot-time hook for `name` is currently installed.
 * Returns `{ enabled: boolean, mechanism, raw? }` where `raw` is the
 * adapter's underlying status output for debugging.
 */
export async function status(name) {
  if (typeof name !== 'string' || name.length === 0) {
    throw new Error('status(name) requires a non-empty string');
  }
  return (await adapter()).status(name);
}

/**
 * Best-effort cross-platform `open <url>` helper. Used by setup.mjs's
 * post-install browser launch. Returns true on apparent success, false
 * if the OS-native opener is missing or the spawn errored — caller can
 * fall back to printing the URL.
 */
export async function openInBrowser(url) {
  if (typeof url !== 'string' || !/^https?:\/\//i.test(url)) {
    throw new Error('openInBrowser(url) requires an http(s) URL');
  }
  const { spawn } = await import('node:child_process');
  return new Promise((resolve) => {
    let cmd;
    let argv;
    if (process.platform === 'darwin') {
      cmd = 'open';
      argv = [url];
    } else if (process.platform === 'win32') {
      // Windows `start` is a cmd.exe builtin; the empty-string second arg is
      // a `start` quirk — it's the window title, otherwise the URL is taken
      // as the title and nothing opens.
      cmd = 'cmd.exe';
      argv = ['/c', 'start', '', url];
    } else {
      // Linux + WSL + BSD all use xdg-open.
      cmd = 'xdg-open';
      argv = [url];
    }
    try {
      const proc = spawn(cmd, argv, { stdio: 'ignore', detached: true });
      proc.on('error', () => resolve(false));
      proc.on('spawn', () => {
        // Detach so the OS opener survives our process exiting.
        proc.unref();
        resolve(true);
      });
    } catch {
      resolve(false);
    }
  });
}
