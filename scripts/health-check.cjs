#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const net = require('node:net');
const http = require('node:http');
const https = require('node:https');
const { spawnSync } = require('node:child_process');

const args = new Set(process.argv.slice(2));
const projectRoot = path.resolve(__dirname, '..');
const serverRoot = path.join(projectRoot, 'packages', 'server');
const dataDir = path.join(serverRoot, 'data');
const logsDir = path.join(projectRoot, 'logs');
const sourceMigrationsDir = path.join(serverRoot, 'src', 'db', 'migrations');
const distMigrationsDir = path.join(serverRoot, 'dist', 'db', 'migrations');
const checks = [];

if (args.has('--help') || args.has('-h')) {
  console.log(`BizarreCRM health check

Usage:
  node scripts/health-check.cjs [options]

Options:
  --skip-network      Skip local TCP/HTTPS probes.
  --full-integrity    Run SQLite PRAGMA integrity_check instead of quick_check.
  --fail-on-warn      Exit with code 1 when warnings are present.
  --json              Print machine-readable JSON.
`);
  process.exit(0);
}

function add(status, title, details = [], fix = []) {
  checks.push({
    status,
    title,
    details: Array.isArray(details) ? details.filter(Boolean) : [String(details)],
    fix: Array.isArray(fix) ? fix.filter(Boolean) : [String(fix)],
  });
}

const ok = (title, details = []) => add('OK', title, details);
const info = (title, details = []) => add('INFO', title, details);
const warn = (title, details = [], fix = []) => add('WARN', title, details, fix);
const fail = (title, details = [], fix = []) => add('FAIL', title, details, fix);

function formatError(err) {
  if (!err) return 'Unknown error';
  const parts = [];
  if (err.code) parts.push(err.code);
  if (err.message) parts.push(err.message);
  return parts.join(': ') || String(err);
}

function formatBytes(bytes) {
  if (!Number.isFinite(bytes)) return String(bytes);
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function readText(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch {
    return '';
  }
}

function safeStat(file) {
  try {
    return fs.statSync(file);
  } catch {
    return null;
  }
}

function listSqlFiles(dir) {
  try {
    return fs.readdirSync(dir).filter((file) => file.endsWith('.sql')).sort();
  } catch {
    return [];
  }
}

function parseEnvFile(file) {
  const vars = {};
  const warnings = [];
  if (!fs.existsSync(file)) {
    warnings.push(`No .env file found at ${file}`);
    return { vars, warnings };
  }
  const lines = readText(file).split(/\r?\n/);
  for (let i = 0; i < lines.length; i += 1) {
    let line = lines[i].trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.slice('export '.length).trim();
    const equals = line.indexOf('=');
    if (equals === -1) {
      warnings.push(`Ignoring .env line ${i + 1}: missing "="`);
      continue;
    }
    const key = line.slice(0, equals).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) {
      warnings.push(`Ignoring .env line ${i + 1}: invalid key "${key}"`);
      continue;
    }
    let value = line.slice(equals + 1).trim();
    const quote = value[0];
    if ((quote === '"' || quote === "'") && value.endsWith(quote)) value = value.slice(1, -1);
    vars[key] = value;
  }
  return { vars, warnings };
}

function parsePort(raw, fallback = 443) {
  const parsed = Number.parseInt(raw || String(fallback), 10);
  return Number.isFinite(parsed) && parsed > 0 && parsed < 65536 ? parsed : fallback;
}

function loadEcosystem() {
  const file = path.join(projectRoot, 'ecosystem.config.js');
  if (!fs.existsSync(file)) {
    fail('PM2 ecosystem config is missing', [file], ['Restore ecosystem.config.js or use direct startup only.']);
    return null;
  }
  try {
    delete require.cache[require.resolve(file)];
    const config = require(file);
    const app = Array.isArray(config.apps)
      ? config.apps.find((entry) => entry && entry.name === 'bizarre-crm') || config.apps[0]
      : null;
    if (!app) {
      fail('PM2 ecosystem config has no app entry', [file]);
      return null;
    }
    ok('PM2 ecosystem config loaded', [`App name: ${app.name}`, `Script: ${app.script}`, `CWD: ${app.cwd}`]);
    return app;
  } catch (err) {
    fail('PM2 ecosystem config cannot be loaded', [formatError(err)], ['Fix ecosystem.config.js syntax/runtime errors.']);
    return null;
  }
}

function getEffectiveEnv(appConfig, envFileVars) {
  return {
    ...envFileVars,
    ...(appConfig && appConfig.env ? appConfig.env : {}),
    ...process.env,
  };
}

function checkPathExists(label, file, type = 'file') {
  const stat = safeStat(file);
  if (!stat) {
    fail(`${label} is missing`, [file], ['Restore the missing file or rerun setup/build.']);
    return false;
  }
  if (type === 'file' && !stat.isFile()) {
    fail(`${label} is not a file`, [file]);
    return false;
  }
  if (type === 'dir' && !stat.isDirectory()) {
    fail(`${label} is not a directory`, [file]);
    return false;
  }
  ok(`${label} exists`, [`${file} (${type === 'dir' ? 'directory' : formatBytes(stat.size)})`]);
  return true;
}

function checkWritableDir(label, dir) {
  const stat = safeStat(dir);
  if (!stat || !stat.isDirectory()) {
    fail(`${label} directory is missing`, [dir], [`Create ${dir}.`]);
    return;
  }
  try {
    fs.accessSync(dir, fs.constants.R_OK | fs.constants.W_OK);
    ok(`${label} directory is readable/writable`, [dir]);
  } catch (err) {
    fail(`${label} directory is not writable`, [dir, formatError(err)], [
      'Fix folder permissions for the account that runs the server.',
    ]);
  }
}

function readPackageJson(file) {
  try {
    return JSON.parse(readText(file));
  } catch (err) {
    fail('package.json cannot be parsed', [file, formatError(err)]);
    return null;
  }
}

function checkNodeVersion(rootPkg) {
  const major = Number.parseInt(process.version.replace(/^v/, '').split('.')[0], 10);
  const required = rootPkg && rootPkg.engines && rootPkg.engines.node ? rootPkg.engines.node : '>=22.0.0';
  if (major >= 22) ok('Node.js version is supported', [`Current: ${process.version}`, `Required: ${required}`]);
  else fail('Node.js version is too old', [`Current: ${process.version}`, `Required: ${required}`], ['Install Node.js 22 LTS or newer.']);
}

function quoteForCmd(arg) {
  return `"${String(arg).replace(/"/g, '""')}"`;
}

function resolveBinary(names) {
  const dirs = (process.env.PATH || '').split(path.delimiter).filter(Boolean);
  if (process.env.APPDATA) dirs.push(path.join(process.env.APPDATA, 'npm'));
  if (process.env.ProgramFiles) dirs.push(path.join(process.env.ProgramFiles, 'nodejs'));
  for (const dir of dirs) {
    for (const name of names) {
      const candidate = path.join(dir, name);
      try {
        if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) return candidate;
      } catch {
        // Ignore unreadable PATH entries.
      }
    }
  }
  return null;
}

function runCommand(binary, commandArgs, options = {}) {
  let command = binary;
  let finalArgs = commandArgs;
  if (process.platform === 'win32' && /\.(cmd|bat)$/i.test(binary)) {
    const systemRoot = process.env.SystemRoot || 'C:\\Windows';
    command = path.join(systemRoot, 'System32', 'cmd.exe');
    finalArgs = ['/d', '/s', '/c', 'call', binary, ...commandArgs];
  }
  return spawnSync(command, finalArgs, {
    cwd: options.cwd || projectRoot,
    env: options.env || process.env,
    encoding: 'utf8',
    timeout: options.timeout || 15_000,
    shell: false,
  });
}

function checkToolCommand(label, names, commandArgs) {
  const binary = resolveBinary(names);
  if (!binary) {
    warn(`${label} was not found on PATH`, [`Searched for: ${names.join(', ')}`]);
    return null;
  }
  const result = runCommand(binary, commandArgs, { timeout: 20_000 });
  if (result.error) {
    warn(`${label} command failed to start`, [binary, formatError(result.error)]);
    return binary;
  }
  if (result.status !== 0) {
    warn(`${label} command returned an error`, [
      binary,
      (result.stderr || result.stdout || '').trim() || `Exit code ${result.status}`,
    ]);
    return binary;
  }
  ok(`${label} command works`, [binary, (result.stdout || '').trim()]);
  return binary;
}

function checkProjectFiles() {
  const rootPkgPath = path.join(projectRoot, 'package.json');
  const serverPkgPath = path.join(serverRoot, 'package.json');
  checkPathExists('Project package.json', rootPkgPath);
  checkPathExists('Server package.json', serverPkgPath);
  checkPathExists('Compiled server entry', path.join(serverRoot, 'dist', 'index.js'));
  checkPathExists('Server TLS private key', path.join(serverRoot, 'certs', 'server.key'));
  checkPathExists('Server TLS certificate', path.join(serverRoot, 'certs', 'server.cert'));
  checkWritableDir('Server data', dataDir);
  checkWritableDir('Server uploads', path.join(serverRoot, 'uploads'));
  checkWritableDir('Server logs', logsDir);
  return {
    rootPkg: readPackageJson(rootPkgPath),
    serverPkg: readPackageJson(serverPkgPath),
  };
}

function checkMigrations() {
  const sourceFiles = listSqlFiles(sourceMigrationsDir);
  const distFiles = listSqlFiles(distMigrationsDir);
  if (sourceFiles.length === 0) {
    fail('Source SQL migrations are missing', [sourceMigrationsDir], ['Restore packages/server/src/db/migrations.']);
    return { sourceFiles, distFiles };
  }
  ok('Source SQL migrations are present', [`${sourceFiles.length} files`]);
  if (distFiles.length === 0) {
    fail('Compiled build is missing SQL migrations', [distMigrationsDir], [
      'Run npm.cmd run build --workspace=packages/server.',
      'PM2 runs dist/index.js, and dist/db/migrations must exist for production startup.',
    ]);
    return { sourceFiles, distFiles };
  }
  const missingInDist = sourceFiles.filter((file) => !distFiles.includes(file));
  const extraInDist = distFiles.filter((file) => !sourceFiles.includes(file));
  if (missingInDist.length > 0) {
    fail('Compiled build is missing migration files', [
      `Missing in dist: ${missingInDist.slice(0, 10).join(', ')}${missingInDist.length > 10 ? '...' : ''}`,
    ], ['Rebuild the server package.']);
  } else if (extraInDist.length > 0) {
    warn('Compiled build has extra migration files', [
      `Extra in dist: ${extraInDist.slice(0, 10).join(', ')}${extraInDist.length > 10 ? '...' : ''}`,
    ]);
  } else {
    ok('Compiled SQL migrations match source', [`${distFiles.length} files`]);
  }
  return { sourceFiles, distFiles };
}

function hasReadySignal(file) {
  return /process\.send\s*\(\s*['"]ready['"]\s*\)/.test(readText(file));
}

function checkPm2ReadinessContract(appConfig) {
  if (!appConfig) return;
  if (appConfig.wait_ready !== true) {
    info('PM2 wait_ready is disabled', ['PM2 will consider the process online after spawn.']);
    return;
  }
  const sourceReady = hasReadySignal(path.join(serverRoot, 'src', 'index.ts'));
  const distReady = hasReadySignal(path.join(serverRoot, 'dist', 'index.js'));
  if (sourceReady && distReady) {
    ok('PM2 readiness signal is wired', [
      'ecosystem.config.js has wait_ready=true.',
      'Source and compiled server both send process.send("ready").',
    ]);
  } else if (sourceReady && !distReady) {
    fail('Compiled server is stale for PM2 wait_ready', [
      'Source sends process.send("ready"), but dist/index.js does not.',
    ], ['Run npm.cmd run build --workspace=packages/server.']);
  } else {
    fail('PM2 wait_ready is enabled but the server never sends ready', [
      'PM2 waits for process.send("ready") before it marks bizarre-crm online.',
      'Without that signal, PM2 can time out, restart, or leave the dashboard thinking the server never finished starting.',
    ], ['Send process.send("ready") after the listener and readiness promise complete, or remove wait_ready.']);
  }
}

function checkEnvironment(appConfig, envVars) {
  const nodeEnv = envVars.NODE_ENV || 'development';
  const port = parsePort(envVars.PORT, 443);
  const host = envVars.HOST || '0.0.0.0';
  const multiTenant = envVars.MULTI_TENANT === 'true';
  const insecure = new Set([
    'dev-secret-change-me',
    'dev-refresh-secret-change-me',
    'change-me-to-a-random-string',
    'change-me-to-another-random-string',
    'change-me',
    '',
  ]);
  ok('Effective server mode resolved', [
    `NODE_ENV=${nodeEnv}`,
    `HOST=${host}`,
    `PORT=${port}`,
    `MULTI_TENANT=${multiTenant}`,
    appConfig && appConfig.env ? 'PM2 env block was included in this evaluation.' : 'No PM2 env block was available.',
  ]);
  if (nodeEnv === 'production') {
    const jwtSecret = envVars.JWT_SECRET || '';
    const refreshSecret = envVars.JWT_REFRESH_SECRET || '';
    if (insecure.has(jwtSecret) || jwtSecret.length < 32) {
      fail('JWT_SECRET will block production startup', [
        'Production mode requires a non-default JWT_SECRET of at least 32 characters.',
        'The secret value was not printed.',
      ], ['Set JWT_SECRET in .env to a strong random value.']);
    } else {
      ok('JWT_SECRET passes production startup validation', ['Value is present and not printed.']);
    }
    if (insecure.has(refreshSecret) || refreshSecret.length < 32) {
      fail('JWT_REFRESH_SECRET will block production startup', [
        'Production mode requires a non-default JWT_REFRESH_SECRET of at least 32 characters.',
        'The secret value was not printed.',
      ], ['Set JWT_REFRESH_SECRET in .env to a strong random value.']);
    } else {
      ok('JWT_REFRESH_SECRET passes production startup validation', ['Value is present and not printed.']);
    }
  } else {
    warn('Server is not configured for production mode', [
      `NODE_ENV=${nodeEnv}`,
      'This is acceptable for local development, but PM2 normally starts this app with NODE_ENV=production.',
    ]);
  }
  if (multiTenant && !envVars.SUPER_ADMIN_SECRET) {
    fail('SUPER_ADMIN_SECRET is required in multi-tenant mode', [
      'The server exits during config loading when MULTI_TENANT=true and SUPER_ADMIN_SECRET is missing.',
    ], ['Set SUPER_ADMIN_SECRET in .env.']);
  }
  if (!envVars.PORT) warn('PORT is not set in the active environment', [`The server defaults to ${port}.`]);
  return { nodeEnv, host, port, multiTenant };
}

let sqliteModule = null;
let sqliteLoadAttempted = false;
let bcryptModule = null;
let bcryptLoadAttempted = false;

function getSqlite() {
  if (sqliteLoadAttempted) return sqliteModule;
  sqliteLoadAttempted = true;
  try {
    sqliteModule = require('better-sqlite3');
    ok('better-sqlite3 module loaded', ['Database health checks can run.']);
  } catch (err) {
    fail('better-sqlite3 module cannot be loaded', [formatError(err)], [
      'Run npm.cmd install from the project root, then retry.',
    ]);
  }
  return sqliteModule;
}

function getBcrypt() {
  if (bcryptLoadAttempted) return bcryptModule;
  bcryptLoadAttempted = true;
  try {
    bcryptModule = require('bcryptjs');
  } catch (err) {
    warn('bcryptjs module cannot be loaded', [formatError(err)], [
      'Default-password checks will be skipped until dependencies are installed.',
    ]);
  }
  return bcryptModule;
}

function getTableNames(db) {
  const rows = db.prepare("SELECT name FROM sqlite_master WHERE type = 'table'").all();
  return new Set(rows.map((row) => row.name));
}

function checkDatabaseMigrations(db, label, sourceFiles) {
  let appliedRows = [];
  try {
    appliedRows = db.prepare('SELECT name FROM _migrations ORDER BY name').all();
  } catch (err) {
    fail(`${label}: _migrations table cannot be read`, [formatError(err)]);
    return;
  }
  const applied = new Set(appliedRows.map((row) => row.name));
  const pending = sourceFiles.filter((file) => !applied.has(file));
  const unknown = [...applied].filter((file) => !sourceFiles.includes(file));
  if (pending.length === 0) {
    ok(`${label}: migrations are fully applied`, [`Applied: ${applied.size}`]);
  } else {
    warn(`${label}: pending migrations detected`, [
      `Applied: ${applied.size}`,
      `Pending: ${pending.length}`,
      `First pending: ${pending[0]}`,
    ], ['Start the server after confirming dist/db/migrations exists, or run the migrate script.']);
  }
  if (unknown.length > 0) {
    warn(`${label}: database contains migration names not present in source`, [
      unknown.slice(0, 10).join(', ') + (unknown.length > 10 ? '...' : ''),
    ]);
  }
}

function checkDefaultAdminPassword(db, label, config, blocksStartup) {
  const bcrypt = getBcrypt();
  if (!bcrypt) return;
  try {
    const admin = db.prepare("SELECT password_hash FROM users WHERE username = 'admin'").get();
    if (!admin || !admin.password_hash) {
      info(`${label}: default admin password check skipped`, ['No username=admin row exists.']);
      return;
    }
    const isDefault = bcrypt.compareSync('admin123', admin.password_hash);
    if (!isDefault) {
      ok(`${label}: admin password is not the default`, ['username=admin does not match admin123.']);
    } else if (config.nodeEnv === 'production' && blocksStartup) {
      fail(`${label}: default admin password blocks production startup`, [
        'username=admin still matches admin123.',
        'The server intentionally exits in production until this password is changed.',
      ], ['Change the admin password away from admin123, then restart PM2.']);
    } else {
      warn(`${label}: default admin password is still active`, [
        'username=admin still matches admin123.',
      ], ['Change the admin password before running in production.']);
    }
  } catch (err) {
    warn(`${label}: default admin password check could not run`, [formatError(err)]);
  }
}

function checkSqliteDatabase(label, file, requiredTables, sourceFiles, config = null, defaultPasswordBlocksStartup = false) {
  const Database = getSqlite();
  if (!Database) return;
  const stat = safeStat(file);
  if (!stat || !stat.isFile()) {
    fail(`${label}: database file is missing`, [file], [
      'Restore the database from backup or let setup create a new one if this is a fresh install.',
    ]);
    return;
  }
  ok(`${label}: database file exists`, [`${file} (${formatBytes(stat.size)})`]);
  const walStat = safeStat(`${file}-wal`);
  if (walStat && walStat.size > Math.max(64 * 1024 * 1024, stat.size * 3)) {
    warn(`${label}: WAL file is unusually large`, [
      `${file}-wal (${formatBytes(walStat.size)})`,
      'This can happen after a crash or long-running writer.',
    ], ['After the server is stopped cleanly, consider a SQLite checkpoint/backup workflow.']);
  } else if (walStat) {
    info(`${label}: WAL file present`, [`${file}-wal (${formatBytes(walStat.size)})`]);
  }

  let db = null;
  try {
    db = new Database(file, { readonly: true, fileMustExist: true, timeout: 5000 });
  } catch (err) {
    fail(`${label}: cannot open SQLite database`, [formatError(err)], [
      'Check file permissions and whether another process has the DB locked.',
    ]);
    return;
  }
  try {
    const pragma = args.has('--full-integrity') ? 'integrity_check' : 'quick_check';
    const rows = db.pragma(pragma);
    const result = rows.map((row) => Object.values(row)[0]).join('; ');
    if (result === 'ok') {
      ok(`${label}: SQLite ${pragma} passed`, ['ok']);
    } else {
      fail(`${label}: SQLite ${pragma} failed`, [result], [
        'Stop the server and restore from a known-good backup if integrity_check reports corruption.',
      ]);
    }
  } catch (err) {
    fail(`${label}: SQLite integrity check could not run`, [formatError(err)]);
  }
  try {
    const foreignKeyRows = db.pragma('foreign_key_check');
    if (foreignKeyRows.length === 0) {
      ok(`${label}: foreign key check passed`, ['No violations found.']);
    } else {
      fail(`${label}: foreign key violations found`, [
        JSON.stringify(foreignKeyRows.slice(0, 10)),
        foreignKeyRows.length > 10 ? `${foreignKeyRows.length - 10} more violations omitted.` : '',
      ]);
    }
  } catch (err) {
    warn(`${label}: foreign key check could not run`, [formatError(err)]);
  }
  try {
    const tables = getTableNames(db);
    const missing = requiredTables.filter((table) => !tables.has(table));
    if (missing.length === 0) ok(`${label}: required tables exist`, requiredTables);
    else fail(`${label}: required tables are missing`, [missing.join(', ')], [
      'This usually means migrations did not run or the wrong database file is being used.',
    ]);
  } catch (err) {
    fail(`${label}: cannot inspect tables`, [formatError(err)]);
  }
  if (sourceFiles.length > 0) checkDatabaseMigrations(db, label, sourceFiles);
  if (config && requiredTables.includes('users')) {
    checkDefaultAdminPassword(db, label, config, defaultPasswordBlocksStartup);
  }
  try {
    db.close();
  } catch {
    // Ignore close errors in a diagnostic script.
  }
}

function resolveTenantDbPath(row) {
  if (row.db_path && path.isAbsolute(row.db_path)) return row.db_path;
  if (row.db_path) return path.resolve(dataDir, 'tenants', row.db_path);
  return path.join(dataDir, 'tenants', `${row.slug}.db`);
}

function checkDatabases(config, sourceFiles) {
  const tenantTables = ['_migrations', 'store_config', 'users', 'customers', 'tickets', 'inventory_items', 'invoices'];
  const masterTables = ['tenants', 'super_admins', 'platform_config', 'rate_limits'];
  checkSqliteDatabase('Primary tenant database', path.join(dataDir, 'bizarre-crm.db'), tenantTables, sourceFiles, config, true);
  const masterDbPath = path.join(dataDir, 'master.db');
  if (!config.multiTenant) {
    if (fs.existsSync(masterDbPath)) info('Master database exists but multi-tenant mode is disabled', [masterDbPath]);
    return;
  }
  checkSqliteDatabase('Master database', masterDbPath, masterTables, []);
  const Database = getSqlite();
  if (!Database || !fs.existsSync(masterDbPath)) return;
  let master = null;
  try {
    master = new Database(masterDbPath, { readonly: true, fileMustExist: true, timeout: 5000 });
    const tenants = master.prepare("SELECT slug, db_path, status FROM tenants WHERE status = 'active' ORDER BY slug").all();
    if (tenants.length === 0) {
      warn('Multi-tenant mode has no active tenants', ['Master DB query returned zero active tenants.']);
    } else {
      ok('Active tenants found', [`${tenants.length} active tenant(s)`]);
      for (const tenant of tenants) {
        checkSqliteDatabase(`Tenant database "${tenant.slug}"`, resolveTenantDbPath(tenant), tenantTables, sourceFiles, config);
      }
    }
  } catch (err) {
    fail('Cannot inspect active tenants', [formatError(err)]);
  } finally {
    try {
      if (master) master.close();
    } catch {
      // Ignore close errors.
    }
  }
}

function checkPm2Runtime(pm2Binary) {
  if (!pm2Binary) return;
  const result = runCommand(pm2Binary, ['jlist'], { timeout: 20_000 });
  if (result.error) {
    warn('PM2 process list could not be read', [formatError(result.error)], [
      'Run pm2.cmd status in a normal terminal and check whether bizarre-crm is online.',
    ]);
    return;
  }
  if (result.status !== 0) {
    warn('PM2 process list returned an error', [
      (result.stderr || result.stdout || '').trim() || `Exit code ${result.status}`,
    ]);
    return;
  }
  let list = [];
  try {
    const trimmed = String(result.stdout || '').trim();
    list = trimmed ? JSON.parse(trimmed) : [];
  } catch (err) {
    warn('PM2 process list was not valid JSON', [formatError(err), result.stdout.trim()]);
    return;
  }
  const entry = list.find((processInfo) => processInfo && processInfo.name === 'bizarre-crm');
  if (!entry) {
    warn('PM2 does not currently manage bizarre-crm', ['No bizarre-crm process was found in pm2 jlist.'], [
      'Start it with pm2.cmd start ecosystem.config.js from the project root.',
    ]);
    return;
  }
  const env = entry.pm2_env || {};
  const details = [
    `status=${env.status || 'unknown'}`,
    `pid=${entry.pid || 'n/a'}`,
    `restart_time=${env.restart_time ?? 'n/a'}`,
    `unstable_restarts=${env.unstable_restarts ?? 'n/a'}`,
  ];
  if (env.status === 'online' && entry.pid && entry.pid > 0) ok('PM2 bizarre-crm process is online', details);
  else if (env.status === 'online') fail('PM2 reports online but has no active PID', details, [
    'Inspect logs/bizarre-crm.err.log and restart the process after fixing startup failures.',
  ]);
  else fail('PM2 bizarre-crm process is not online', details, [
    'Inspect logs/bizarre-crm.err.log and pm2.cmd logs bizarre-crm --lines 100.',
  ]);
}

function testTcp(host, port, timeoutMs = 2500) {
  return new Promise((resolve) => {
    const socket = net.createConnection({ host, port });
    const timer = setTimeout(() => socket.destroy(new Error('TCP timeout')), timeoutMs);
    socket.once('connect', () => {
      clearTimeout(timer);
      socket.end();
      resolve({ ok: true });
    });
    socket.once('error', (err) => {
      clearTimeout(timer);
      resolve({ ok: false, error: err });
    });
  });
}

function requestJson(protocol, host, port, requestPath) {
  return new Promise((resolve) => {
    const client = protocol === 'https' ? https : http;
    const req = client.request({
      protocol: `${protocol}:`,
      hostname: host,
      port,
      path: requestPath,
      method: 'GET',
      rejectUnauthorized: false,
      timeout: 5000,
      headers: { Host: 'localhost', Accept: 'application/json' },
    }, (res) => {
      let body = '';
      res.setEncoding('utf8');
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => {
        let parsed = null;
        try {
          parsed = body ? JSON.parse(body) : null;
        } catch {
          // Keep parsed null.
        }
        resolve({ ok: true, statusCode: res.statusCode, headers: res.headers, body, json: parsed });
      });
    });
    req.on('timeout', () => req.destroy(new Error('Request timed out')));
    req.on('error', (err) => resolve({ ok: false, error: err }));
    req.end();
  });
}

function getNetstatListeners(port) {
  if (process.platform !== 'win32') return [];
  const result = spawnSync('netstat.exe', ['-ano', '-p', 'tcp'], {
    encoding: 'utf8',
    timeout: 10_000,
    shell: false,
  });
  if (result.error || result.status !== 0) return [];
  const listeners = [];
  for (const line of result.stdout.split(/\r?\n/)) {
    const normalized = line.trim().replace(/\s+/g, ' ');
    if (!normalized.includes('LISTENING')) continue;
    const parts = normalized.split(' ');
    if (parts.length < 5) continue;
    if (parts[1].endsWith(`:${port}`)) listeners.push({ local: parts[1], pid: parts[4] });
  }
  return listeners;
}

async function checkNetwork(config) {
  if (args.has('--skip-network')) {
    info('Network checks skipped', ['--skip-network was provided.']);
    return;
  }
  const tcp = await testTcp('127.0.0.1', config.port);
  const listeners = getNetstatListeners(config.port);
  if (!tcp.ok) {
    fail('No local TCP listener on the configured server port', [
      `127.0.0.1:${config.port}`,
      formatError(tcp.error),
      listeners.length > 0 ? `netstat listener(s): ${JSON.stringify(listeners)}` : 'netstat found no LISTENING socket for this port.',
    ], ['Start the server, then rerun this script.', 'If another PID owns the port, stop that process or change PORT.']);
    return;
  }
  ok('Local TCP port is accepting connections', [
    `127.0.0.1:${config.port}`,
    listeners.length > 0 ? `netstat listener(s): ${JSON.stringify(listeners)}` : 'TCP probe succeeded.',
  ]);
  const live = await requestJson('https', '127.0.0.1', config.port, '/api/v1/health');
  if (!live.ok) {
    fail('HTTPS liveness probe failed', [
      `https://127.0.0.1:${config.port}/api/v1/health`,
      formatError(live.error),
    ], ['Check TLS certs and server logs.', 'The server is expected to serve HTTPS, not plain HTTP.']);
    return;
  }
  if (live.statusCode === 200 && live.json && live.json.success === true) {
    ok('HTTPS liveness probe passed', [`Status ${live.statusCode}`, JSON.stringify(live.json)]);
  } else {
    fail('HTTPS liveness probe returned an unexpected response', [`Status ${live.statusCode}`, live.body.slice(0, 500)]);
  }
  const ready = await requestJson('https', '127.0.0.1', config.port, '/api/v1/health/ready');
  if (!ready.ok) {
    fail('HTTPS readiness probe failed', [
      `https://127.0.0.1:${config.port}/api/v1/health/ready`,
      formatError(ready.error),
    ]);
    return;
  }
  if (ready.statusCode === 200 && ready.json && ready.json.success === true) {
    ok('HTTPS readiness probe passed', [`Status ${ready.statusCode}`, JSON.stringify(ready.json)]);
  } else if (ready.statusCode === 503) {
    warn('Server is alive but not ready yet', [`Status ${ready.statusCode}`, ready.body.slice(0, 500)], [
      'Wait for migrations/startup to finish, then rerun the script.',
    ]);
  } else {
    fail('HTTPS readiness probe returned an unexpected response', [`Status ${ready.statusCode}`, ready.body.slice(0, 500)]);
  }
}

function tailText(file, maxLines = 25) {
  try {
    return fs.readFileSync(file, 'utf8').split(/\r?\n/).filter(Boolean).slice(-maxLines);
  } catch {
    return [];
  }
}

function checkRecentLogs() {
  const logFiles = [
    path.join(logsDir, 'bizarre-crm.err.log'),
    path.join(logsDir, 'bizarre-crm.direct.err.log'),
  ];
  for (const file of logFiles) {
    const stat = safeStat(file);
    if (!stat || stat.size === 0) {
      info('Error log is empty or absent', [file]);
      continue;
    }
    warn('Error log contains content', [`${file} (${formatBytes(stat.size)})`, ...tailText(file, 15)], [
      'Review the latest error log lines above.',
    ]);
  }
  const crashLog = path.join(dataDir, 'crash-log.json');
  if (!fs.existsSync(crashLog)) {
    info('Crash tracker log is absent', [crashLog]);
    return;
  }
  try {
    const parsed = JSON.parse(readText(crashLog));
    const crashes = Array.isArray(parsed.crashes) ? parsed.crashes : [];
    if (crashes.length === 0) {
      ok('Crash tracker has no recorded crashes', [crashLog]);
      return;
    }
    const last = crashes[crashes.length - 1];
    const lastTime = Date.parse(last.timestamp || '');
    const ageMs = Number.isFinite(lastTime) ? Date.now() - lastTime : null;
    const recent = ageMs !== null && ageMs >= 0 && ageMs < 24 * 60 * 60 * 1000;
    const details = [
      `Total crashes recorded: ${crashes.length}`,
      `Last timestamp: ${last.timestamp || 'unknown'}`,
      `Last route: ${last.route || 'unknown'}`,
      `Last error: ${last.errorMessage || 'unknown'}`,
    ];
    if (recent) warn('Crash tracker has a crash from the last 24 hours', details);
    else info('Crash tracker has older crash history', details);
  } catch (err) {
    warn('Crash tracker log could not be parsed', [crashLog, formatError(err)]);
  }
}

function printHuman() {
  console.log('');
  console.log('BizarreCRM server/database health check');
  console.log(`Project: ${projectRoot}`);
  console.log(`Time: ${new Date().toISOString()}`);
  console.log('');
  for (const check of checks) {
    console.log(`[${check.status}] ${check.title}`);
    for (const detail of check.details) console.log(`  - ${detail}`);
    for (const fix of check.fix) console.log(`  Fix: ${fix}`);
  }
  const summary = checks.reduce((acc, check) => {
    acc[check.status] = (acc[check.status] || 0) + 1;
    return acc;
  }, {});
  console.log('');
  console.log(`Summary: ${summary.OK || 0} OK, ${summary.INFO || 0} info, ${summary.WARN || 0} warning(s), ${summary.FAIL || 0} failure(s)`);
  const issues = checks.filter((check) => check.status === 'FAIL' || check.status === 'WARN');
  if (issues.length > 0) {
    console.log('');
    console.log('Issues to fix:');
    for (const issue of issues) {
      console.log(`[${issue.status}] ${issue.title}`);
      for (const detail of issue.details.slice(0, 5)) console.log(`  - ${detail}`);
      if (issue.details.length > 5) console.log(`  - ${issue.details.length - 5} more detail line(s) above.`);
      for (const fix of issue.fix) console.log(`  Fix: ${fix}`);
    }
  } else {
    console.log('');
    console.log('Issues to fix: none');
  }
  console.log('');
}

async function main() {
  const envFile = parseEnvFile(path.join(projectRoot, '.env'));
  for (const envWarning of envFile.warnings) warn('Environment file warning', [envWarning]);
  const appConfig = loadEcosystem();
  const packages = checkProjectFiles();
  checkNodeVersion(packages.rootPkg);
  checkToolCommand('npm', process.platform === 'win32' ? ['npm.cmd', 'npm.exe', 'npm.bat', 'npm'] : ['npm'], ['--version']);
  const pm2Binary = checkToolCommand('PM2', process.platform === 'win32' ? ['pm2.cmd', 'pm2.exe', 'pm2.bat', 'pm2'] : ['pm2'], ['--version']);
  const migrationState = checkMigrations();
  checkPm2ReadinessContract(appConfig);
  const config = checkEnvironment(appConfig, getEffectiveEnv(appConfig, envFile.vars));
  checkDatabases(config, migrationState.sourceFiles);
  checkPm2Runtime(pm2Binary);
  await checkNetwork(config);
  checkRecentLogs();
  if (args.has('--json')) console.log(JSON.stringify({ projectRoot, checks }, null, 2));
  else printHuman();
  const failures = checks.filter((check) => check.status === 'FAIL').length;
  const warnings = checks.filter((check) => check.status === 'WARN').length;
  if (failures > 0 || (args.has('--fail-on-warn') && warnings > 0)) process.exitCode = 1;
}

main().catch((err) => {
  fail('Health check crashed', [formatError(err), err && err.stack ? err.stack : '']);
  if (args.has('--json')) console.log(JSON.stringify({ projectRoot, checks }, null, 2));
  else printHuman();
  process.exitCode = 1;
});
