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
import { existsSync, readFileSync, copyFileSync, mkdirSync, rmSync, cpSync } from 'node:fs';
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
const ANSI_OFF = process.env.NO_COLOR || !process.stdout.isTTY;
const c = {
  red: (s) => (ANSI_OFF ? s : `\x1b[31m${s}\x1b[0m`),
  green: (s) => (ANSI_OFF ? s : `\x1b[32m${s}\x1b[0m`),
  yellow: (s) => (ANSI_OFF ? s : `\x1b[33m${s}\x1b[0m`),
  cyan: (s) => (ANSI_OFF ? s : `\x1b[36m${s}\x1b[0m`),
  bold: (s) => (ANSI_OFF ? s : `\x1b[1m${s}\x1b[0m`),
  dim: (s) => (ANSI_OFF ? s : `\x1b[2m${s}\x1b[0m`),
};

const STEPS_TOTAL = 12;
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

/**
 * Run a command synchronously with inherited stdio (so the operator sees
 * progress). Returns { ok, code }. Never throws — callers branch on `.ok`.
 */
function run(cmd, args = [], opts = {}) {
  const r = spawnSync(cmd, args, {
    cwd: opts.cwd || REPO_ROOT,
    stdio: opts.stdio || 'inherit',
    env: { ...process.env, ...(opts.env || {}) },
    shell: opts.shell ?? false,
    encoding: 'utf8',
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
  // Gracefully stop both apps. Ignore errors — apps may not be running.
  capture('pm2', ['stop', 'bizarre-crm', 'bizarre-crm-watchdog']);
  ok('PM2 apps stopped (if running)');
}

// ─── 4. npm install ────────────────────────────────────────────────────────

function npmInstall() {
  step('Installing dependencies');
  const r = run('npm', ['install'], { shell: process.platform === 'win32' });
  if (!r.ok) fatal(`npm install failed (exit ${r.code}).`);
  ok('Dependencies installed');
}

// ─── 5. .env ───────────────────────────────────────────────────────────────

async function ensureEnv() {
  step('Ensuring .env');
  const envPath = path.join(REPO_ROOT, '.env');
  if (!existsSync(envPath)) {
    let domain = process.env.SETUP_DOMAIN;
    if (!domain) {
      if (input.isTTY) {
        const rl = readline.createInterface({ input, output });
        const answer = (await rl.question(
          '\n  Enter your domain (e.g. example.com), or press Enter for localhost: '
        )).trim();
        rl.close();
        domain = answer || 'localhost';
      } else {
        domain = 'localhost';
        warn('No TTY and SETUP_DOMAIN unset — defaulting to localhost.');
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
  const certPath = path.join(REPO_ROOT, 'packages/server/certs/server.cert');
  if (existsSync(certPath)) {
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
  const r = run('npm', ['run', 'build'], { shell: process.platform === 'win32' });
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
  const gradlew = process.platform === 'win32' ? 'gradlew.bat' : './gradlew';
  const r = run(gradlew, ['assembleRelease'], { cwd: androidDir, shell: true });
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

// ─── 9. Management dashboard (transitional, Electron) ──────────────────────

function buildDashboard() {
  step('Building management dashboard');
  const mgmtPkg = path.join(REPO_ROOT, 'packages/management/package.json');
  if (!existsSync(mgmtPkg)) {
    ok('packages/management/ absent — skipped (likely post-deprecation).');
    return;
  }

  // Sources build cross-platform via the workspace npm script.
  const r = run('npm', ['run', 'build', '-w', '@bizarre-crm/management'], { shell: process.platform === 'win32' });
  if (!r.ok) {
    warn(`Dashboard build failed (exit ${r.code}). Server still works. Browser dashboard will replace this in a future release (see docs/dashboard-migration-plan.md).`);
    return;
  }
  ok('Dashboard sources built');

  // Packaging the .exe is Windows-only because packages/management/package.json
  // hard-codes `electron-builder --win`. Per dashboard-migration-plan this is
  // transitional; once the browser dashboard ships, this whole step disappears.
  if (process.platform === 'win32') {
    const r2 = run('npm', ['run', 'package', '-w', '@bizarre-crm/management'], { shell: true });
    if (!r2.ok) {
      warn('Dashboard packaging (Electron .exe) failed. Sources built but no installable EXE.');
      return;
    }
    ok('Dashboard EXE packaged');

    // Copy unpacked EXE to <repo>/dashboard/ for the launch step + the
    // legacy operator workflow that bookmarks this path.
    const unpacked = path.join(REPO_ROOT, 'packages/management/release/win-unpacked');
    const target = path.join(REPO_ROOT, 'dashboard');
    if (existsSync(unpacked)) {
      // Node's recursive copy. cpSync exists on Node 16.7+; we're 22+.
      try {
        if (existsSync(target)) rmSync(target, { recursive: true, force: true });
        cpSync(unpacked, target, { recursive: true });
        ok(`Dashboard copied to ${target}`);
      } catch (err) {
        warn(`Dashboard copy failed: ${err.message}`);
      }
    }
  } else {
    ok('Dashboard packaging skipped on non-Windows (electron-builder --win is Windows-only). Run scripts/setup-windows.bat directly if you need the .exe.');
  }
}

// ─── 10. PM2 start + save ──────────────────────────────────────────────────

function startPm2() {
  step('Starting PM2 (server + watchdog)');
  if (!hasCmd('pm2')) {
    warn('pm2 not on PATH. Falling back to direct node launch (no auto-restart, no watchdog).');
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

  const r = run('pm2', ['start', path.join(REPO_ROOT, 'ecosystem.config.js'), '--update-env']);
  if (!r.ok) fatal(`pm2 start failed (exit ${r.code}).`);
  ok('PM2 apps started');

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

  // Operator consent — autostart adapters need sudo on Linux/macOS or
  // Administrator on Windows. Don't escalate without an explicit yes.
  let consent = true;
  if (input.isTTY) {
    const rl = readline.createInterface({ input, output });
    const answer = (await rl.question(
      '\n  Register BizarreCRM to start automatically at boot? [Y/n] '
    )).trim();
    rl.close();
    consent = !/^n/i.test(answer);
  }
  if (!consent) {
    ok('Operator declined autostart. Server will need manual `pm2 resurrect` after reboot.');
    return;
  }

  try {
    const { register } = await import('./scripts/autostart/index.mjs');
    // The spec is advisory for Linux/macOS (PM2 startup ignores command/args
    // and uses its own dump file). Windows reads command/args and writes a
    // Task Scheduler entry that spawns PM2 directly.
    const result = await register({
      name: 'BizarreCRM-PM2',
      description: 'Resurrects BizarreCRM PM2 apps at boot',
      command: process.execPath,
      args: [resolvePm2Bin(), 'resurrect'],
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
 * Resolve PM2's `bin/pm2` script path so the autostart task can invoke
 * `node <pm2-bin>` directly without depending on the SYSTEM-context PATH
 * (which won't include npm-global / nvm shims).
 */
function resolvePm2Bin() {
  // Try `npm root -g` first — most reliable.
  const r = capture('npm', ['root', '-g'], { shell: process.platform === 'win32' });
  if (r.ok && r.stdout) {
    const dir = r.stdout.trim();
    const candidate = path.join(dir, 'pm2/bin/pm2');
    if (existsSync(candidate)) return candidate;
  }
  // Fallback: try `which pm2` and walk the symlink. PM2's bin entry is
  // usually a wrapper that points to the JS file.
  const probe = process.platform === 'win32' ? 'where' : 'which';
  const w = capture(probe, ['pm2']);
  if (w.ok && w.stdout) {
    const found = w.stdout.split(/\r?\n/)[0].trim();
    if (found && existsSync(found)) return found;
  }
  // Last resort: just `pm2` and hope SYSTEM finds it.
  return 'pm2';
}

// ─── 12. Open browser ──────────────────────────────────────────────────────

async function openBrowser() {
  step('Opening dashboard in browser');
  if (process.env.SETUP_NO_BROWSER === '1') {
    ok('SETUP_NO_BROWSER=1 — skipped');
    return;
  }
  // Read PORT from .env so we don't guess. Falls back to 443 (server default).
  let port = '443';
  try {
    const env = readFileSync(path.join(REPO_ROOT, '.env'), 'utf8');
    const m = env.match(/^\s*PORT\s*=\s*"?(\d+)"?\s*$/m);
    if (m) port = m[1];
  } catch { /* .env may not exist on first run failure path */ }

  const url = port === '443' ? 'https://localhost/' : `https://localhost:${port}/`;

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
  buildDashboard();
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
