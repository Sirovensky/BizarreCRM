// @audit-fixed: Deployment audit (section 34)
//
// Fixes applied here:
//   1. `script` was `src/index.ts` running under `node --import tsx/esm`. tsx is a
//      DEV transpiler — it adds startup latency, holds extra memory for the
//      transformer, and skips tsc-time type checks. Production runs the compiled
//      `dist/index.js` directly under plain node. (`npm run build` must be invoked
//      first; the `update.bat` script in /scripts already does this.)
//   2. `env.NODE_ENV` was `development`, which silently disabled the production
//      JWT-secret guard, the Origin-required guard, and the no-default-password
//      kill-switch. Production environments now ship NODE_ENV=production.
//   3. Added `wait_ready` + `listen_timeout` so PM2 reload waits for the new
//      instance to actually be ready before killing the old one — without this,
//      `pm2 reload` causes a restart-style downtime instead of zero-downtime.
//   4. Added `kill_timeout` so SIGTERM-then-SIGKILL gives the server enough time
//      to flush in-flight DB writes (the existing shutdown handler closes the
//      tenant pool + worker pool which can take 2-3s).
//   5. Added explicit `out_file` / `error_file` paths so pm2 logs land somewhere
//      predictable. Operators are expected to install `pm2-logrotate` separately
//      (`pm2 install pm2-logrotate`) — this config does not include log rotation
//      because pm2-logrotate is its own pm2 module, not a field on apps[].
//
// @audit-fixed: #14 — log rotation. PM2 ships WITHOUT pm2-logrotate installed by
// default. Long-running shops will fill the disk with gigabytes of .log output
// within months. To enable rotation, run these commands once per machine:
//
//   pm2 install pm2-logrotate
//   pm2 set pm2-logrotate:max_size 50M
//   pm2 set pm2-logrotate:retain 30
//   pm2 set pm2-logrotate:compress true
//   pm2 set pm2-logrotate:dateFormat YYYY-MM-DD_HH-mm-ss
//
// This caps each log file at 50 MB, keeps 30 rotated archives (gzipped),
// and stamps filenames with second-precision timestamps so rotations in the
// same minute don't collide. These are the values recommended for a
// multi-tenant install with ~1k tickets/day of inbound SMS + webhook volume.
//   6. Increased `max_memory_restart` to 1G — the worker pool + better-sqlite3
//      caches can legitimately exceed 512M under load, and the previous limit
//      caused random restarts that masked real memory leaks.
const path = require('path');
const fs = require('fs');
const root = __dirname;
const envFile = path.join(root, '.env');

function parseDotEnv(file) {
  if (!fs.existsSync(file)) return {};
  const env = {};
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  for (let line of lines) {
    line = line.trim();
    if (!line || line.startsWith('#')) continue;
    if (line.startsWith('export ')) line = line.slice('export '.length).trim();
    const equals = line.indexOf('=');
    if (equals === -1) continue;
    const key = line.slice(0, equals).trim();
    if (!/^[A-Za-z_][A-Za-z0-9_]*$/.test(key)) continue;
    let value = line.slice(equals + 1).trim();
    const quote = value[0];
    if ((quote === '"' || quote === "'") && value.endsWith(quote)) {
      value = value.slice(1, -1);
    }
    env[key] = value;
  }
  return env;
}

const envFromFile = parseDotEnv(envFile);

module.exports = {
  apps: [
    {
      name: 'bizarre-crm',
      script: 'dist/index.js',
      interpreter: 'node',
      cwd: path.join(root, 'packages/server'),
      instances: 1,
      exec_mode: 'fork',
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      restart_delay: 2000,
      max_restarts: 10,
      min_uptime: '10s',
      // Graceful reload: PM2 will not consider the new instance up until it
      // emits `process.send('ready')`. The server's startup script already
      // calls this once the HTTPS listener is bound.
      wait_ready: true,
      // Production tenants can legitimately need several minutes on first boot
      // after a large migration backlog. The server sends "ready" only after
      // the HTTPS listener is bound and tenant migrations have finished, so a
      // 30s PM2 timeout causes restart loops on machines that are catching up
      // many tenant DBs at once.
      listen_timeout: 600_000,
      kill_timeout: 10_000,
      out_file: path.join(root, 'logs/bizarre-crm.out.log'),
      error_file: path.join(root, 'logs/bizarre-crm.err.log'),
      merge_logs: true,
      time: true,
      env: {
        ...envFromFile,
        // PM2 is the production process manager. Keep production safety checks
        // enabled even if an old .env accidentally says NODE_ENV=development.
        NODE_ENV: 'production',
        PORT: envFromFile.PORT || 443,
      },
      env_development: {
        ...envFromFile,
        NODE_ENV: 'development',
        PORT: envFromFile.PORT || 443,
      },
    },
  ],
};
