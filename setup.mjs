#!/usr/bin/env node
/**
 * BizarreCRM Universal Setup — Phase 1
 * =====================================
 *
 * Cross-platform install/update flow. Invoked by the three OS gateway shims
 * (`setup.bat` / `setup.command` / `setup.sh`) AFTER each gateway has
 * verified Node.js >= v22 is on PATH.
 *
 * What this does, in order:
 *
 *   1. Preflight: Node version + repo-root markers + git availability.
 *   2. git pull (best effort — silent if not a git repo).
 *   3. Stop running PM2 apps gracefully (no taskkill blanket).
 *   4. npm install.
 *   5. Ensure / upgrade `.env` (domain prompt on first install).
 *   6. Generate self-signed SSL certs if missing.
 *   7. Build shared + web + server (root npm script).
 *   8. (Optional, conditional) Build Android APK if ANDROID_HOME is set.
 *   9. (Transitional) Build management dashboard sources cross-platform;
 *      package .exe on Windows ONLY (the only OS where electron-builder
 *      is currently configured). Per docs/dashboard-migration-plan.md the
 *      Electron app is being deprecated; this step goes away in Phase E.
 *  10. PM2 start ecosystem.config.js + pm2 save.
 *  11. Optional autostart registration via scripts/autostart adapter set.
 *  12. Open default browser to https://localhost (skippable in non-TTY).
 *
 * The only OS-specific code outside scripts/autostart/ is the Windows-only
 * Electron-package step in (9), which is documented as transitional.
 *
 * Environment overrides:
 *
 *   SETUP_NO_PULL=1            skip step 2 (useful for offline / pinned
 *                              installs)
 *   SETUP_BUILD_ANDROID=1      force-attempt Android APK build even if
 *                              ANDROID_HOME is unset (will fail if no SDK)
 *   SETUP_NO_BROWSER=1         skip step 12
 *   SETUP_NO_AUTOSTART=1       skip step 11
 *   SETUP_DOMAIN=<host>        non-interactive domain for first-install
 *                              .env generation (e.g. CI)
 *
 * Args: any extra flags the operator passes to setup.bat / setup.sh /
 * setup.command are forwarded here unchanged. Currently no flags are read.
 */

import { spawn, spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync, copyFileSync, mkdirSync, rmSync, cpSync } from 'node:fs';
import path from 'node:path';
import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const REPO_ROOT = path.dirname(__filename);
// Mirrors packages/server/package.json + root package.json `engines.node`.
// Server: >=22.11.0 <25. Root: >=22.12.0 <25. Use the more permissive
// floor (server) and the same ceiling (both agree).
const REQUIRED_NODE_MAJOR = 22;
const REJECTED_NODE_MAJOR = 25;

// ─── Tiny ANSI helpers (no chalk dep) ──────────────────────────────────────
// NO_COLOR convention (https://no-color.org): disable color when the env var
// is PRESENT, regardless of value. Empty string `NO_COLOR=""` should still
// disable color — checking truthiness misses that case.
const ANSI_OFF = 'NO_COLOR' in process.env || !process.stdout.isTTY;
const c = {
  red: (s) => (ANSI_OFF ? s : `\x1b[31m${s}\x1b[0m`),
  green: (s) => (ANSI_OFF ? s : `\x1b[32m${s}\x1b[0m`),
  yellow: (s) => (ANSI_OFF ? s : `\x1b[33m${s}\x1b[0m`),
  cyan: (s) => (ANSI_OFF ? s : `\x1b[36m${s}\x1b[0m`),
  bold: (s) => (ANSI_OFF ? s : `\x1b[1m${s}\x1b[0m`),
  dim: (s) => (ANSI_OFF ? s : `\x1b[2m${s}\x1b[0m`),
};

const STEPS_TOTAL = 11;
let stepNum = 0;
function step(label) {
  stepNum += 1;
  console.log(`\n${c.cyan(`[${stepNum}/${STEPS_TOTAL}]`)} ${c.bold(label)}`);
}
function ok(msg) { console.log(c.green('  OK ') + msg); }
function warn(msg) { console.log(c.yellow('  WARN ') + msg); }
function fail(msg) { console.log(c.red('  FAIL ') + msg); }
function fatal(msg) {
  console.error(`\n${c.red('FATAL')} ${msg}\n`);
  process.exit(1);
}

// ─── Process helpers ───────────────────────────────────────────────────────

const IS_WIN = process.platform === 'win32';

/**
 * Cross-platform spawn shim. On Windows, npm/pm2/git/node all ship as
 * `.cmd` shims (e.g. `pm2.cmd`); spawnSync without `shell: true` fails
 * with ENOENT for them. The `winShell` set lists commands that are known
 * to be `.cmd` on Windows so callers don't have to remember to flip
 * `shell: true` per call.
 *
 * Verified to be `.cmd` on Windows: pm2, npm, npx, electron, electron-builder.
 * `node.exe` itself is a real exe and does NOT need shell:true; never put
 * 'node' in this set.
 */
const WIN_CMD_SHIMS = new Set(['pm2', 'npm', 'npx']);
function needsShell(cmd, opts) {
  if (typeof opts?.shell === 'boolean') return opts.shell;
  return IS_WIN && WIN_CMD_SHIMS.has(cmd);
}

/**
 * Run a command synchronously with inherited stdio (so the operator sees
 * progress). Returns { ok, code }. Never throws — callers branch on `.ok`.
 *
 * `shell` flips automatically based on `cmd` on Windows (see WIN_CMD_SHIMS);
 * callers can override by passing `shell: true|false`.
 */
function run(cmd, args = [], opts = {}) {
  const r = spawnSync(cmd, args, {
    cwd: opts.cwd || REPO_ROOT,
    stdio: opts.stdio || 'inherit',
    env: { ...process.env, ...(opts.env || {}) },
    shell: needsShell(cmd, opts),
    encoding: 'utf8',
    timeout: opts.timeout,
  });
  return { ok: r.status === 0, code: r.status, stdout: r.stdout, stderr: r.stderr };
}

/** Same as run() but captures stdout/stderr to strings (stdio: pipe). */
function capture(cmd, args = [], opts = {}) {
  return run(cmd, args, { ...opts, stdio: ['ignore', 'pipe', 'pipe'] });
}

/** True if `cmd` resolves on PATH. Cross-platform via spawnSync + which/where. */
function hasCmd(cmd) {
  const probe = process.platform === 'win32' ? 'where' : 'which';
  const r = spawnSync(probe, [cmd], { stdio: 'ignore' });
  return r.status === 0;
}

// ─── 1. Preflight ──────────────────────────────────────────────────────────

function preflight() {
  step('Preflight checks');
  const nodeMajor = parseInt(process.versions.node.split('.')[0], 10);
  if (!Number.isFinite(nodeMajor) || nodeMajor < REQUIRED_NODE_MAJOR) {
    fatal(`Node.js v${REQUIRED_NODE_MAJOR}.x or newer required; you have v${process.versions.node}.`);
  }
  if (nodeMajor >= REJECTED_NODE_MAJOR) {
    fatal(`Node.js v${process.versions.node} is too new — repo engines require <v${REJECTED_NODE_MAJOR}. Install Node 22 LTS.`);
  }
  ok(`Node.js v${process.versions.node}`);

  // Verify we're actually in a BizarreCRM checkout. Cheap markers — same set
  // the existing service-control trusted-anchor check uses.
  const markers = ['package.json', 'packages/server/package.json', 'ecosystem.config.js'];
  for (const m of markers) {
    if (!existsSync(path.join(REPO_ROOT, m))) {
      fatal(`Repo marker missing: ${m}. Are you running setup from the BizarreCRM root?`);
    }
  }
  ok(`Repo root: ${REPO_ROOT}`);

  if (!hasCmd('git')) {
    warn('git not found on PATH — step 2 (pull) will be skipped.');
  } else {
    ok('git available');
  }
}

// ─── 2. git pull ───────────────────────────────────────────────────────────

function gitPull() {
  step('Pulling latest code');
  if (process.env.SETUP_NO_PULL === '1') {
    ok('SETUP_NO_PULL=1 — skipped');
    return;
  }
  if (!hasCmd('git')) {
    warn('git missing — skipped');
    return;
  }
  // Reset package-lock.json so npm can resolve updates cleanly. NEVER reset
  // .env, *.db, uploads/, certs/, data/ — those are .gitignored and contain
  // operator data that survives upgrades.
  capture('git', ['checkout', '--', 'package-lock.json']);
  const r = capture('git', ['pull', 'origin', 'main']);
  if (!r.ok) {
    warn(`git pull failed (exit ${r.code}). Continuing with local code.`);
    if (r.stderr) console.log(c.dim(r.stderr.trim().split('\n').slice(0, 5).join('\n')));
  } else {
    ok('Latest code pulled');
  }
}

// ─── 3. Stop running PM2 apps ──────────────────────────────────────────────

function stopRunning() {
  step('Stopping running PM2 apps');
  if (!hasCmd('pm2')) {
    warn('pm2 not on PATH — nothing to stop. Will install/use PM2 in step 10.');
    return;
  }
  // Gracefully stop each app individually. Some PM2 versions only act on
  // the first positional arg when multiple names are passed to `pm2 stop`,
  // silently leaving the second app running.
  capture('pm2', ['stop', 'bizarre-crm']);
  capture('pm2', ['stop', 'bizarre-crm-watchdog']);
  ok('PM2 apps stopped (if running)');
}

// ─── 4. npm install ────────────────────────────────────────────────────────

function npmInstall() {
  step('Installing dependencies');

  // Native-module ABI mismatch detection. Modules like better-sqlite3,
  // sharp, canvas compile a `.node` binary against a specific
  // NODE_MODULE_VERSION (Node 22 = 127, Node 25 = 141). When the operator
  // switches Node major (brew downgrade after our too-new install path,
  // nvm use, fresh Node MSI install), existing .node binaries fail to
  // load with ERR_DLOPEN_FAILED at runtime. `npm install` does NOT
  // rebuild native modules unless package.json or package-lock changes
  // — operators get a server that crashes on every boot with a confusing
  // node-loader stack trace.
  //
  // Stamp the current Node major into node_modules/ on every install.
  // If the stamp differs from the current Node major, force `npm rebuild`
  // after the regular install completes.
  const stampPath = path.join(REPO_ROOT, 'node_modules', '.bizarre-crm-node-major');
  const currentMajor = process.versions.node.split('.')[0];
  // Marker for any installed native binding. better-sqlite3 is the
  // most commonly-broken one and is always installed on a working
  // BizarreCRM checkout, so it's a reliable proxy for "node_modules
  // contains compiled native code that may be ABI-locked to a
  // specific Node major."
  const nativeMarker = path.join(REPO_ROOT, 'node_modules', 'better-sqlite3', 'build', 'Release', 'better_sqlite3.node');
  let needsRebuild = false;
  try {
    if (existsSync(stampPath)) {
      const stamped = readFileSync(stampPath, 'utf8').trim();
      if (stamped && stamped !== currentMajor) {
        needsRebuild = true;
        console.log(c.yellow(`  Node major changed since last install (was v${stamped}, now v${currentMajor}) — will rebuild native modules.`));
      }
    } else if (existsSync(nativeMarker)) {
      // First setup.mjs run with the stamp logic, but native bindings
      // already exist from a prior install. We don't know which Node
      // major they were built against, and we cannot cheaply load the
      // .node binary from this ESM context to test it. Rebuild
      // defensively to guarantee ABI alignment with current Node. One-
      // time cost; subsequent runs use the stamp file.
      needsRebuild = true;
      console.log(c.yellow(`  Native bindings present but no Node-major stamp — rebuilding defensively against current Node v${currentMajor}.`));
    }
  } catch { /* stamp read errors are non-fatal */ }

  const r = run('npm', ['install']);
  if (!r.ok) fatal(`npm install failed (exit ${r.code}).`);
  ok('Dependencies installed');

  if (needsRebuild) {
    const r2 = run('npm', ['rebuild']);
    if (!r2.ok) {
      // Don't fatal — let setup.mjs proceed, but the operator will see
      // ERR_DLOPEN_FAILED at server boot. The error message tells them
      // what to do (run npm rebuild) which they're now one step closer
      // to having tried.
      warn(`npm rebuild failed (exit ${r2.code}). Native modules (better-sqlite3, sharp, etc.) likely have ABI mismatches and will fail at server boot. Try \`xcode-select --install\` (macOS) or \`apt install build-essential\` (Linux) and re-run setup.`);
    } else {
      ok('Native modules rebuilt against current Node major');
    }
  }

  // Update stamp regardless of whether we rebuilt — captures the major
  // that node_modules is currently aligned to.
  try {
    mkdirSync(path.dirname(stampPath), { recursive: true });
    writeFileSync(stampPath, currentMajor, 'utf8');
  } catch { /* stamp write errors are non-fatal */ }
}

// ─── 5. .env ───────────────────────────────────────────────────────────────

async function ensureEnv() {
  step('Ensuring .env');
  const envPath = path.join(REPO_ROOT, '.env');
  if (!existsSync(envPath)) {
    let domain = process.env.SETUP_DOMAIN;
    if (!domain) {
      // Both ends must be TTY for an interactive prompt. If stdout is piped
      // (e.g. `setup.mjs | tee setup.log`), the question lands in the log
      // and the operator never sees it — they hit Enter blindly and we'd
      // accept a default they didn't intend. Treat piped stdout as
      // non-interactive.
      if (input.isTTY && output.isTTY) {
        const rl = readline.createInterface({ input, output });
        const answer = (await rl.question(
          '\n  Enter your domain (e.g. example.com), or press Enter for localhost: '
        )).trim();
        rl.close();
        domain = answer || 'localhost';
      } else {
        domain = 'localhost';
        warn('Non-interactive (TTY check failed) and SETUP_DOMAIN unset — defaulting to localhost. Set SETUP_DOMAIN=<host> to override.');
      }
    }
    const r = run('node', ['packages/server/scripts/generate-env.cjs', domain]);
    if (!r.ok) fatal(`generate-env.cjs failed (exit ${r.code}).`);
    ok(`.env generated for domain "${domain}"`);
  } else {
    // Idempotent run — generate-env.cjs APPENDS new sections (JWT_SECRET,
    // UPLOADS_SECRET, BACKUP_ENCRYPTION_KEY, etc.) added in releases since
    // the last setup. Without this, post-upgrade boots crash-loop on the
    // missing FATAL-in-prod gates.
    const r = run('node', ['packages/server/scripts/generate-env.cjs']);
    if (!r.ok) warn('generate-env.cjs returned non-zero — continuing.');
    ok('.env existing — checked for upgrade-added sections');
  }
  const r2 = run('node', ['packages/server/scripts/ensure-env-secrets.cjs']);
  if (!r2.ok) fatal(`ensure-env-secrets.cjs failed (exit ${r2.code}).`);
  ok('.env auth secrets ensured');
}

// ─── 6. SSL certs ──────────────────────────────────────────────────────────

function ensureCerts() {
  step('Ensuring SSL certificates');
  // Server boots only when BOTH cert + key are present. Checking only one
  // and skipping generation leaves a partial-state install where the
  // server FATALs on the missing file and operators see no clear cause.
  const certPath = path.join(REPO_ROOT, 'packages/server/certs/server.cert');
  const keyPath = path.join(REPO_ROOT, 'packages/server/certs/server.key');
  if (existsSync(certPath) && existsSync(keyPath)) {
    ok('SSL certs already present');
    return;
  }
  const r = run('node', ['packages/server/scripts/generate-certs.cjs']);
  if (!r.ok) {
    warn('generate-certs.cjs failed. The server ships with self-signed dev certs that still work. Replace with real certs in packages/server/certs/ for production.');
  } else {
    ok('Self-signed SSL certs generated');
  }
}

// ─── 7. Build (shared + web + server) ──────────────────────────────────────

function buildApp() {
  step('Building shared + web + server');
  const r = run('npm', ['run', 'build']);
  if (!r.ok) fatal(`Root build failed (exit ${r.code}).`);

  // tsc does not emit non-TS files; copy the piscina worker manually. The
  // server's own build script already does this, but the root `npm run
  // build` calls it for us, so this is belt-and-suspenders.
  const src = path.join(REPO_ROOT, 'packages/server/src/db/db-worker.mjs');
  const dst = path.join(REPO_ROOT, 'packages/server/dist/db/db-worker.mjs');
  if (existsSync(src) && !existsSync(dst)) {
    try {
      mkdirSync(path.dirname(dst), { recursive: true });
      copyFileSync(src, dst);
    } catch { /* best effort */ }
  }
  ok('Build complete');
}

// ─── 8. Android APK (optional, conditional) ────────────────────────────────

function buildAndroid() {
  step('Android APK (conditional)');
  const wantBuild = process.env.SETUP_BUILD_ANDROID === '1' || process.env.ANDROID_HOME || process.env.ANDROID_SDK_ROOT;
  if (!wantBuild) {
    ok('Android SDK not detected (ANDROID_HOME unset) — skipped. Set SETUP_BUILD_ANDROID=1 to force.');
    return;
  }
  const androidDir = path.join(REPO_ROOT, 'android');
  if (!existsSync(androidDir)) {
    warn('android/ directory missing — skipping APK build.');
    return;
  }
  // gradlew.bat is a .bat file (needs shell:true on Windows); ./gradlew is a
  // real shell script and runs natively without shell:true. Quoted-via-shell
  // would also break paths with spaces on POSIX; keep shell off there.
  const gradlew = IS_WIN ? 'gradlew.bat' : './gradlew';
  const r = run(gradlew, ['assembleRelease'], { cwd: androidDir, shell: IS_WIN });
  if (!r.ok) {
    warn(`Android APK build failed (exit ${r.code}). Mobile app will not be updated.`);
    return;
  }
  ok('Android APK built');

  // Copy the APK into packages/server/downloads so the in-app install link works.
  const downloads = path.join(REPO_ROOT, 'packages/server/downloads');
  mkdirSync(downloads, { recursive: true });
  const release = path.join(androidDir, 'app/build/outputs/apk/release/app-release.apk');
  const debug = path.join(androidDir, 'app/build/outputs/apk/debug/app-debug.apk');
  const target = path.join(downloads, 'BizarreCRM.apk');
  if (existsSync(release)) {
    copyFileSync(release, target);
    ok('Release APK copied to packages/server/downloads/');
  } else if (existsSync(debug)) {
    copyFileSync(debug, target);
    ok('Debug APK copied to packages/server/downloads/ (release build not found)');
  } else {
    warn('No APK artifact found after build.');
  }
}

// ─── 9. (REMOVED) Management dashboard build ─────────────────────────────
//
// The old step 9 built the Electron management app + packaged it as a
// Windows .exe. That dashboard has been replaced by the browser-served
// super-admin SPA which is built as part of `npm run build` at the root
// (the root build script's last step is `build:renderer:web --workspace=
// packages/management`, which emits the SPA bundle into
// packages/server/dist/super-admin-spa/ that the server serves at
// /super-admin/).
//
// Removing this step:
//   - eliminates the slow `electron-builder --win` packaging path
//   - drops the brittle NSIS code-signing failure mode
//   - aligns with docs/dashboard-migration-plan.md Phase E (Electron
//     deletion) — the package.json in packages/management can stay for
//     now; setup just doesn't invoke its `package` script anymore.
//
// Operators who still need the Electron .exe can run it manually:
//   cd packages/management && npm run package
// Most should switch to the browser dashboard at /super-admin/.

// ─── 10. PM2 start + save ──────────────────────────────────────────────────

/**
 * Ensure PM2 is on PATH. If not, attempt a global npm install. On Linux/
 * macOS the npm prefix often defaults to a system path requiring sudo;
 * retry under sudo IF interactive. Returns true if PM2 is usable after
 * the call, false if the install failed and the caller should use the
 * direct-node fallback.
 *
 * Why this matters: without PM2 the operator gets the worst possible
 * UX — a detached node spawn with stdio:'ignore', no logs, no restart,
 * no watchdog, no autostart. On macOS with default PORT=443 the spawn
 * silently dies on EACCES. New operators end up with "Firefox can't
 * connect" and zero diagnostics. PM2 makes every failure visible.
 */
function ensurePm2() {
  if (hasCmd('pm2')) return true;
  console.log(c.yellow('  PM2 not on PATH — installing globally via npm.'));
  console.log(c.dim('  Command: npm install -g pm2'));

  let r = run('npm', ['install', '-g', 'pm2']);
  if (!r.ok) {
    // Most common cause on Linux/macOS: npm prefix defaults to
    // /usr/local/lib/node_modules which is owned by root. Retry under
    // sudo only if interactive — CI-style invocations would hang on
    // sudo's password prompt.
    if (!IS_WIN && process.stdin.isTTY && process.stdout.isTTY) {
      console.log(c.yellow('  Global install failed (likely permission error). Retrying with sudo...'));
      console.log(c.dim('  Command: sudo npm install -g pm2'));
      r = run('sudo', ['npm', 'install', '-g', 'pm2']);
    }
    if (!r.ok) {
      warn('Failed to install PM2 globally. Run `npm install -g pm2` manually (or with sudo on Linux/macOS), then re-run setup.');
      return false;
    }
  }
  // npm install of a global cmd usually puts it on PATH because the
  // npm prefix bin dir is typically already there. If not, the operator
  // needs a fresh shell so PATH reloads.
  if (!hasCmd('pm2')) {
    warn('PM2 installed but not on PATH for this shell. Close this terminal and re-run setup from a NEW terminal.');
    return false;
  }
  ok('PM2 installed globally');
  return true;
}

function startPm2() {
  step('Starting PM2 (server + watchdog)');
  if (!ensurePm2()) {
    warn('PM2 unavailable. Falling back to direct node launch (no auto-restart, no watchdog).');
    // Detach a node process so setup.mjs can return. NB: this is a fallback;
    // the operator should `npm install -g pm2` and re-run setup for the
    // full supervised flow.
    const child = spawn('node', ['packages/server/dist/index.js'], {
      cwd: path.join(REPO_ROOT, 'packages/server'),
      stdio: 'ignore',
      detached: true,
    });
    child.unref();
    ok(`Direct node launch (PID ${child.pid}). Install pm2 globally for supervised runs.`);
    return;
  }

  // Clean up any stale entry from a prior failed run before start.
  capture('pm2', ['delete', 'bizarre-crm']);
  capture('pm2', ['delete', 'bizarre-crm-watchdog']);

  // ecosystem.config.js sets `wait_ready: true` + `listen_timeout: 600_000`
  // for bizarre-crm so PM2 will block this `pm2 start` call for up to
  // TEN MINUTES waiting for the server's `process.send('ready')`. On a
  // real failure (crash loop, EACCES on bind) the operator stares at a
  // hung setup with no output for 10 minutes.
  //
  // CLI override: `--listen-timeout 60000` caps the wait at 60s.
  // PM2 keeps trying to start the app in the background regardless;
  // we just stop blocking setup.mjs after a reasonable wait. Operator
  // can `pm2 logs` to debug whatever the underlying crash is.
  const r = run('pm2', [
    'start',
    path.join(REPO_ROOT, 'ecosystem.config.js'),
    '--update-env',
    '--listen-timeout', '60000',
  ]);
  if (!r.ok) {
    // Non-fatal: PM2 may have started the apps but timed out waiting
    // for ready. Leave them in PM2 and let setup proceed; the operator
    // will see the actual state via `pm2 list`.
    warn(`pm2 start returned non-zero (exit ${r.code}). Apps may still be in PM2 but in a crashed/launching state — check \`pm2 logs bizarre-crm\` for the real error.`);
  } else {
    ok('PM2 apps started');
  }

  const r2 = run('pm2', ['save']);
  if (!r2.ok) warn(`pm2 save failed (exit ${r2.code}). Autostart may not survive reboot.`);
  else ok('PM2 process list saved');
}

// ─── 11. Boot autostart registration ───────────────────────────────────────

async function registerAutostart() {
  step('Registering boot autostart');
  if (process.env.SETUP_NO_AUTOSTART === '1') {
    ok('SETUP_NO_AUTOSTART=1 — skipped');
    return;
  }
  if (!hasCmd('pm2')) {
    warn('pm2 not on PATH — autostart skipped. Re-run after `npm install -g pm2`.');
    return;
  }

  // Skip the consent prompt if autostart is already registered with
  // the OS. Re-running setup.mjs (e.g. for a code update) shouldn't
  // pester operators who already opted in. The OS is the source of
  // truth: if the operator manually disabled the unit in System
  // Settings → Login Items / Background, status() reports disabled
  // and we re-prompt — which is the correct UX (operator removed it
  // for a reason; ask again).
  try {
    const { status: getStatus } = await import('./scripts/autostart/index.mjs');
    const existing = await getStatus('BizarreCRM-PM2');
    if (existing.enabled) {
      ok(`Autostart already registered (${existing.mechanism}) — refreshing pm2 save.`);
      // Refresh the dump file so the boot resurrect picks up any
      // app-list changes since last setup (e.g. operator added /
      // removed apps, ecosystem.config.js changed instances).
      const save = run('pm2', ['save']);
      if (!save.ok) warn(`pm2 save failed (exit ${save.code}). Existing autostart may resurrect a stale app list.`);
      return;
    }
  } catch {
    /* status() failure is non-fatal — fall through to consent + register */
  }

  // Operator consent — autostart adapters need sudo on Linux/macOS or
  // Administrator on Windows. Don't escalate without an explicit yes.
  // Both stdin AND stdout must be TTY: a piped stdout means the prompt
  // lands in the log file and a blind Enter would silently default to
  // "yes", auto-running sudo. Treat any non-TTY end as a hard skip.
  let consent = false;
  if (input.isTTY && output.isTTY) {
    const rl = readline.createInterface({ input, output });
    const answer = (await rl.question(
      '\n  Register BizarreCRM to start automatically at boot? [Y/n] '
    )).trim();
    rl.close();
    consent = !/^n/i.test(answer);
  } else {
    ok('Non-interactive (TTY check failed) — autostart skipped. Set SETUP_NO_AUTOSTART=0 + run interactively to enable, or pre-install the unit manually.');
    return;
  }
  if (!consent) {
    ok('Operator declined autostart. Server will need manual `pm2 resurrect` after reboot.');
    return;
  }

  // PM2 JS entry resolution. Win32 adapter REQUIRES a working JS path —
  // its launcher does `"node.exe" "<pm2-bin>" resurrect`. Linux/macOS
  // ignore this field (PM2's own startup unit handles paths internally),
  // but resolution failure on those platforms is still a useful signal
  // that the operator's PM2 install is broken.
  const pm2Bin = resolvePm2Bin();
  if (!pm2Bin && IS_WIN) {
    warn('Could not resolve PM2 JS entry — autostart skipped. Install PM2 globally: npm install -g pm2');
    return;
  }
  if (!pm2Bin) {
    warn('Could not resolve PM2 JS entry. Linux/macOS autostart will still work via pm2 startup, but a fallback path is missing — proceeding.');
  }

  try {
    const { register } = await import('./scripts/autostart/index.mjs');
    // The spec is advisory for Linux/macOS (PM2 startup ignores
    // command/args/env and uses its own dump file). Windows reads
    // command/args/env and writes a launcher .cmd + Task Scheduler entry
    // that exec's it.
    const result = await register({
      name: 'BizarreCRM-PM2',
      description: 'Resurrects BizarreCRM PM2 apps at boot',
      command: process.execPath,
      args: pm2Bin ? [pm2Bin, 'resurrect'] : ['resurrect'],
      env: { PM2_HOME: process.env.PM2_HOME || path.join(REPO_ROOT, '.pm2') },
      workingDir: REPO_ROOT,
    });
    if (result.ok) ok(`${result.mechanism}: ${result.message}`);
    else warn(`Autostart not configured: ${result.message}`);
  } catch (err) {
    warn(`Autostart adapter error: ${err.message}`);
  }
}

/**
 * Resolve PM2's `bin/pm2` JS entry point so the autostart task can invoke
 * `node <pm2-bin> resurrect` without depending on the SYSTEM-context PATH
 * (which won't include npm-global / nvm shims). The Task Scheduler task
 * runs `node.exe <pm2-js-entry>` — note `node.exe`, NOT `pm2.cmd`. The
 * cmd shim wraps the JS file but cannot be invoked by `node.exe` directly.
 *
 * Returns null if PM2's JS entry cannot be located. Caller should warn
 * and skip autostart rather than registering a broken task.
 */
function resolvePm2Bin() {
  // Primary: `npm root -g`. On most stock Node installs, PM2 is installed
  // globally and `npm root -g` returns the global node_modules dir; the
  // JS entry is at <dir>/pm2/bin/pm2.
  const r = capture('npm', ['root', '-g']);
  if (r.ok && r.stdout) {
    const dir = r.stdout.trim();
    const candidate = path.join(dir, 'pm2', 'bin', 'pm2');
    if (existsSync(candidate)) return candidate;
  }
  // Fallback: `which pm2` returns the bin shim. Read the shim's first
  // line to find the JS entry it wraps.
  // - On POSIX, the shim is `#!/usr/bin/env node\nrequire(...)/pm2.js`
  //   OR the shim itself IS the JS file. We accept either if it parses
  //   as a JS file.
  // - On Windows, `where pm2` returns `pm2.cmd`. Reading the .cmd file's
  //   contents reveals the JS path it spawns. We match `node "*pm2*"`
  //   inside the .cmd to extract the underlying JS path.
  const probe = IS_WIN ? 'where' : 'which';
  const w = capture(probe, ['pm2']);
  if (w.ok && w.stdout) {
    const lines = w.stdout.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
    for (const found of lines) {
      if (!existsSync(found)) continue;
      // POSIX: a JS file ends with no extension OR `.js`; .cmd shim is Windows-only.
      if (!IS_WIN && !found.endsWith('.cmd') && !found.endsWith('.bat') && !found.endsWith('.ps1')) {
        return found;
      }
      // Windows: read the .cmd shim and pull out the JS entry.
      if (IS_WIN && found.endsWith('.cmd')) {
        try {
          const txt = readFileSync(found, 'utf8');
          // Match `node ... "<path>\\pm2\\bin\\pm2"` or `"%~dp0\\node_modules\\pm2\\bin\\pm2"`.
          const m = txt.match(/"([^"]*pm2[\\/]+bin[\\/]+pm2)"/i);
          if (m && m[1]) {
            // `%~dp0\\...` → resolve relative to the .cmd's directory.
            let resolved = m[1].replace(/%~dp0/gi, path.dirname(found) + path.sep);
            if (existsSync(resolved)) return resolved;
          }
        } catch { /* fall through */ }
      }
    }
  }
  return null;
}

// ─── 12. Open browser ──────────────────────────────────────────────────────

async function openBrowser() {
  step('Opening dashboard in browser');
  if (process.env.SETUP_NO_BROWSER === '1') {
    ok('SETUP_NO_BROWSER=1 — skipped');
    return;
  }
  // Read PORT from .env so we don't guess. Falls back to 443 (server default).
  // Regex tolerates an inline `# comment` after the value — operators
  // commonly annotate their .env this way; the prior `\s*$` anchor refused
  // to match those lines and silently fell back to 443.
  let port = '443';
  try {
    const env = readFileSync(path.join(REPO_ROOT, '.env'), 'utf8');
    const m = env.match(/^\s*PORT\s*=\s*"?(\d+)"?/m);
    if (m) port = m[1];
  } catch { /* .env may not exist on first run failure path */ }

  // Open the super-admin dashboard, NOT the customer-facing CRM landing.
  // Post-setup the operator needs to (a) finish first-run super-admin
  // password + 2FA setup, OR (b) hit their existing super-admin login.
  // /super-admin serves admin/super-admin.html (see server/src/index.ts
  // mounting at line ~1472). Opening the root `/` lands on the customer
  // login page which is the wrong destination at the end of an install.
  const base = port === '443' ? 'https://localhost' : `https://localhost:${port}`;
  const url = `${base}/super-admin`;

  try {
    const { openInBrowser } = await import('./scripts/autostart/index.mjs');
    const opened = await openInBrowser(url);
    if (opened) {
      ok(`Browser opened to ${url}`);
    } else {
      warn(`Could not open browser automatically. Visit ${url} manually.`);
    }
  } catch (err) {
    warn(`Browser launch failed: ${err.message}`);
  }
}

// ─── Main ──────────────────────────────────────────────────────────────────

(async () => {
  console.log(c.bold('\n============================================'));
  console.log(c.bold('   BizarreCRM Universal Setup'));
  console.log(c.bold('============================================'));

  preflight();
  gitPull();
  stopRunning();
  npmInstall();
  await ensureEnv();
  ensureCerts();
  buildApp();
  buildAndroid();
  // Step 9 (Electron management dashboard build) was removed — the
  // browser-served super-admin SPA is built as part of buildApp()'s
  // root `npm run build` (which calls build:renderer:web for the
  // management package). See dashboard-migration-plan.md Phase E.
  startPm2();
  await registerAutostart();
  await openBrowser();

  console.log(`\n${c.green(c.bold('Setup complete.'))} Server running supervised by PM2.`);
  console.log(c.dim('  Logs:        pm2 logs bizarre-crm'));
  console.log(c.dim('  Watchdog:    pm2 logs bizarre-crm-watchdog'));
  console.log(c.dim('  Status:      pm2 list'));
  console.log();
  process.exit(0);
})().catch((err) => {
  fatal(`Unhandled error: ${err && (err.stack || err.message) || err}`);
});
