/**
 * Super-admin management routes.
 * ==============================
 *
 * Mounted at `/super-admin/api/management/`. All routes require super-admin
 * authentication via the parent router's `superAdminAuth` middleware.
 *
 * These routes were previously Electron IPC handlers in
 * `packages/management/src/main/ipc/management-api.ts`. Ported here so the
 * browser-served super-admin SPA (also driven by the same renderer code)
 * has feature parity with the desktop Electron app. The IPC main process
 * accessed `.env`, `logs/`, and host info via Node fs / os modules; the
 * SAME logic now lives server-side and is reachable via authenticated HTTP.
 *
 * Coverage:
 *   GET  /env                       — list ENV_FIELDS with values (secrets masked)
 *   PUT  /env                       — atomic upsert of one or more fields
 *   GET  /logs                      — list whitelisted log files w/ stat
 *   GET  /logs/tail                 — tail last N lines of one log file
 *   GET  /watchdog-events           — JSONL tail (matches the prior Electron handler)
 *   DELETE /watchdog-events         — clear / acknowledge
 *   GET  /system/info               — host OS / Node / uptime
 *   GET  /system/disk-space         — disk free / total per repo + log paths
 *   GET  /service/status            — PM2 status of bizarre-crm + watchdog
 *   POST /service/start             — pm2 start (or fallback)
 *   POST /service/stop              — pm2 stop
 *   POST /service/restart           — pm2 restart
 *   POST /service/kill-all          — best-effort kill of all bizarre-crm
 *                                     PM2 entries (escape hatch)
 *   POST /service/auto-start        — toggle pm2 startup boot autostart
 *   POST /service/disable           — pm2 stop + delete (security kill switch)
 *   POST /service/emergency-stop    — pm2 stop --no-treekill (fast)
 *
 * Security:
 *   - localhostOnly applied at parent mount in index.ts
 *   - superAdminAuth applied at parent mount
 *   - Path-containment on every fs operation: every resolved path is
 *     validated to live inside the trusted repo root before any read/write
 *   - Env writes go through `writeEnvAtomic` (snapshot → write → fsync →
 *     rename) to avoid half-written .env on crash
 *   - Log file reads use a hard whitelist; no arbitrary path read
 *   - All destructive operations write to master_audit_log
 */
import { Router, Request, Response } from 'express';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync, execSync } from 'node:child_process';
import { z } from 'zod';
import { config } from '../config.js';
import { audit } from '../utils/audit.js';
import { getMasterDb } from '../db/master-connection.js';
import { createLogger } from '../utils/logger.js';
import { ERROR_CODES } from '../utils/errorCodes.js';

const router = Router();
const log = createLogger('super-admin-management');

// ─── Env editor helpers (ported from packages/management) ────────

interface EnvFieldDef {
  key: string;
  kind: 'flag' | 'value' | 'secret';
  category: 'killswitch' | 'captcha' | 'stripe' | 'cloudflare' | 'cors';
  label: string;
  description?: string;
  placeholder?: string;
  maxLength: number;
}

const ENV_FIELDS: readonly EnvFieldDef[] = [
  // Kill switches
  { key: 'DISABLE_OUTBOUND_EMAIL', kind: 'flag', category: 'killswitch', label: 'Disable outbound email',
    description: 'Suppresses every SMTP send process-wide. Use during incident response.', maxLength: 8 },
  { key: 'DISABLE_OUTBOUND_SMS', kind: 'flag', category: 'killswitch', label: 'Disable outbound SMS',
    description: 'Suppresses every SMS send. Inbound webhooks still process.', maxLength: 8 },
  { key: 'DISABLE_OUTBOUND_VOICE', kind: 'flag', category: 'killswitch', label: 'Disable outbound voice/calls',
    description: 'Suppresses click-to-call originations.', maxLength: 8 },
  // Captcha
  { key: 'SIGNUP_CAPTCHA_REQUIRED', kind: 'flag', category: 'captcha', label: 'Require hCaptcha on signup',
    description: 'When ON, server FATAL-exits if HCAPTCHA_SECRET is missing.', maxLength: 8 },
  { key: 'HCAPTCHA_SECRET', kind: 'secret', category: 'captcha', label: 'hCaptcha secret',
    description: 'Server-side secret from the hCaptcha dashboard.', placeholder: 'paste from hcaptcha.com',
    maxLength: 256 },
  // Stripe
  { key: 'STRIPE_SECRET_KEY', kind: 'secret', category: 'stripe', label: 'Stripe secret key',
    placeholder: 'sk_live_…', maxLength: 256 },
  { key: 'STRIPE_WEBHOOK_SECRET', kind: 'secret', category: 'stripe', label: 'Stripe webhook secret',
    placeholder: 'whsec_…', maxLength: 256 },
  { key: 'STRIPE_PRO_PRICE_ID', kind: 'value', category: 'stripe', label: 'Stripe Pro price ID',
    placeholder: 'price_…', maxLength: 128 },
  // Cloudflare
  { key: 'CLOUDFLARE_API_TOKEN', kind: 'secret', category: 'cloudflare', label: 'Cloudflare API token',
    description: 'Zone:DNS:Edit scope. Required for tenant subdomain auto-creation.', maxLength: 256 },
  { key: 'CLOUDFLARE_ZONE_ID', kind: 'value', category: 'cloudflare', label: 'Cloudflare Zone ID',
    maxLength: 64 },
  { key: 'SERVER_PUBLIC_IP', kind: 'value', category: 'cloudflare', label: 'Server public IP',
    description: 'Apex A record target. New tenant subdomains point here.',
    placeholder: '203.0.113.10', maxLength: 64 },
  // CORS
  { key: 'ALLOWED_ORIGINS', kind: 'value', category: 'cors', label: 'Additional allowed origins',
    description: 'Comma-separated absolute URLs. Empty = localhost + BASE_DOMAIN only.',
    placeholder: 'https://lan.example.com,https://crm.shop.com', maxLength: 4096 },
] as const;

const ENV_KEY_TO_FIELD = new Map(ENV_FIELDS.map((f) => [f.key, f]));

const SchemaEnvSettingsUpdate = z
  .record(z.string(), z.string().max(8192))
  .refine((obj) => Object.keys(obj).every((k) => ENV_KEY_TO_FIELD.has(k)), { message: 'Unknown env key' })
  .refine((obj) => Object.keys(obj).length > 0, { message: 'At least one key must be provided' });

const REPO_ROOT = path.resolve(process.cwd().endsWith(path.join('packages', 'server'))
  ? path.resolve(process.cwd(), '..', '..')
  : process.cwd());

function envFilePath(): string {
  return path.join(REPO_ROOT, '.env');
}

function readEnvFile(): { ok: true; content: string; path: string } | { ok: false; message: string } {
  const p = envFilePath();
  try {
    const content = fs.readFileSync(p, 'utf8');
    return { ok: true, content, path: p };
  } catch (err) {
    return { ok: false, message: `Cannot read .env: ${err instanceof Error ? err.message : String(err)}` };
  }
}

function readEnvKey(content: string, key: string): string | null {
  const re = new RegExp(`^\\s*${key}\\s*=\\s*(?:"([^"]*)"|'([^']*)'|([^#\\r\\n]*))`, 'm');
  const m = content.match(re);
  if (!m) return null;
  return (m[1] ?? m[2] ?? m[3] ?? '').trimEnd();
}

function upsertEnvKey(content: string, key: string, rawValue: string): string {
  // Quote if value contains whitespace, =, or #; else write raw.
  const needsQuotes = /[\s=#]/.test(rawValue);
  const formatted = needsQuotes ? `"${rawValue.replace(/"/g, '\\"')}"` : rawValue;
  const line = `${key}=${formatted}`;
  const re = new RegExp(`^(\\s*${key}\\s*=).*$`, 'm');
  if (re.test(content)) {
    return content.replace(re, line);
  }
  // Append at end with leading newline if file doesn't end with one.
  return content.replace(/\n*$/, '\n') + line + '\n';
}

function writeEnvAtomic(targetPath: string, content: string): void {
  // Snapshot to .env.bak-<epoch>, write to .env.tmp, fsync, rename.
  const tmp = `${targetPath}.tmp`;
  const bak = `${targetPath}.bak-${Date.now()}`;
  try {
    if (fs.existsSync(targetPath)) {
      fs.copyFileSync(targetPath, bak);
    }
    fs.writeFileSync(tmp, content, { encoding: 'utf8', mode: 0o600 });
    const fd = fs.openSync(tmp, 'r+');
    try { fs.fsyncSync(fd); } finally { fs.closeSync(fd); }
    fs.renameSync(tmp, targetPath);
  } catch (err) {
    try { if (fs.existsSync(tmp)) fs.unlinkSync(tmp); } catch { /* ignore */ }
    throw err;
  }
  // Prune old backups (keep last 10).
  try {
    const dir = path.dirname(targetPath);
    const base = path.basename(targetPath);
    const backups = fs.readdirSync(dir)
      .filter((n) => n.startsWith(`${base}.bak-`))
      .map((n) => ({ name: n, full: path.join(dir, n) }))
      .sort((a, b) => b.name.localeCompare(a.name));
    for (const { full } of backups.slice(10)) {
      try { fs.unlinkSync(full); } catch { /* ignore */ }
    }
  } catch { /* prune is best-effort */ }
}

// ─── Log viewer helpers ────────────────────────────────────────

const LOG_FILE_WHITELIST = [
  'bizarre-crm.out.log',
  'bizarre-crm.err.log',
  'bizarre-crm.direct.out.log',
  'bizarre-crm.direct.err.log',
  'bizarre-crm-watchdog.out.log',
  'bizarre-crm-watchdog.err.log',
  'pm2-bootstrap.out.log',
  'pm2-bootstrap.err.log',
] as const;
type LogName = typeof LOG_FILE_WHITELIST[number];

function resolveLogPath(name: string): { ok: true; path: string } | { ok: false; message: string } {
  if (!(LOG_FILE_WHITELIST as readonly string[]).includes(name)) {
    return { ok: false, message: 'Log file not in whitelist' };
  }
  const resolved = path.join(REPO_ROOT, 'logs', name);
  // Path containment: ensure the resolved path is under <repo>/logs/.
  const logsDir = path.join(REPO_ROOT, 'logs');
  const rel = path.relative(logsDir, resolved);
  if (rel.startsWith('..') || path.isAbsolute(rel)) {
    return { ok: false, message: 'Path traversal rejected' };
  }
  return { ok: true, path: resolved };
}

const SchemaTailLog = z.object({
  name: z.string().refine((n) => (LOG_FILE_WHITELIST as readonly string[]).includes(n), {
    message: 'Log file not in whitelist',
  }) as z.ZodType<LogName>,
  lines: z.coerce.number().int().min(1).max(2000),
});

function tailFile(filePath: string, lines: number): { content: string; size: number; truncated: boolean } {
  const stat = fs.statSync(filePath);
  // Cap read at 2 MB to avoid loading huge logs into memory; truncated flag
  // tells the renderer to surface a "see full log on disk" hint.
  const MAX_BYTES = 2 * 1024 * 1024;
  const fd = fs.openSync(filePath, 'r');
  try {
    const start = stat.size > MAX_BYTES ? stat.size - MAX_BYTES : 0;
    const buf = Buffer.alloc(stat.size - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const text = buf.toString('utf8');
    const allLines = text.split('\n');
    const tail = allLines.slice(-lines).join('\n');
    return {
      content: tail,
      size: stat.size,
      truncated: start > 0 || allLines.length > lines,
    };
  } finally {
    fs.closeSync(fd);
  }
}

// ─── Audit helper ──────────────────────────────────────────────

function auditOp(req: Request, action: string, details: Record<string, unknown>): void {
  const master = getMasterDb();
  if (!master) return;
  const actorId = req.superAdmin?.superAdminId ?? null;
  audit(master, action, actorId, req.ip || 'unknown', details);
}

// ─── ROUTES ────────────────────────────────────────────────────

router.get('/env', (_req: Request, res: Response) => {
  const env = readEnvFile();
  if (!env.ok) {
    res.status(500).json({ success: false, message: env.message });
    return;
  }
  const fields = ENV_FIELDS.map((f) => {
    const raw = readEnvKey(env.content, f.key);
    const trimmed = raw == null ? '' : raw.trim();
    const hasValue = trimmed.length > 0;
    const base = {
      key: f.key,
      kind: f.kind,
      category: f.category,
      label: f.label,
      description: f.description,
      placeholder: f.placeholder,
      hasValue,
    };
    if (f.kind === 'secret') {
      // Never round-trip secret values back to the renderer.
      return { ...base, length: trimmed.length };
    }
    const defaulted = f.kind === 'flag' && !hasValue && f.key === 'SIGNUP_CAPTCHA_REQUIRED' ? 'true' : trimmed;
    return { ...base, value: defaulted };
  });
  res.json({ success: true, data: { fields } });
});

router.put('/env', (req: Request, res: Response) => {
  const parsed = SchemaEnvSettingsUpdate.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ success: false, message: parsed.error.errors[0]?.message ?? 'Invalid env update' });
    return;
  }
  for (const [key, value] of Object.entries(parsed.data)) {
    const field = ENV_KEY_TO_FIELD.get(key)!;
    if (value.length > field.maxLength) {
      res.status(400).json({ success: false, message: `${key} exceeds max length of ${field.maxLength}` });
      return;
    }
    if (field.kind === 'flag' && value !== '' && value !== 'true' && value !== 'false') {
      res.status(400).json({ success: false, message: `${key} must be "true" or "false"` });
      return;
    }
    if (/[\r\n\t ]/.test(value)) {
      res.status(400).json({ success: false, message: `${key} contains forbidden characters` });
      return;
    }
  }
  const env = readEnvFile();
  if (!env.ok) {
    res.status(500).json({ success: false, message: env.message });
    return;
  }
  let content = env.content;
  for (const [key, value] of Object.entries(parsed.data)) {
    content = upsertEnvKey(content, key, value);
  }
  try {
    writeEnvAtomic(env.path, content);
    auditOp(req, 'super_admin_env_update', { keys: Object.keys(parsed.data) });
    res.json({ success: true, data: { keysUpdated: Object.keys(parsed.data), requiresRestart: true } });
  } catch (err) {
    log.error('env write failed', { error: err instanceof Error ? err.message : String(err) });
    res.status(500).json({ success: false, message: 'Failed to write .env' });
  }
});

router.get('/logs', (_req: Request, res: Response) => {
  const files = LOG_FILE_WHITELIST.map((name) => {
    const resolved = resolveLogPath(name);
    if (!resolved.ok) return { name, size: 0, mtime: null, exists: false, error: resolved.message };
    try {
      const stat = fs.statSync(resolved.path);
      return { name, size: stat.size, mtime: stat.mtime.toISOString(), exists: true };
    } catch {
      return { name, size: 0, mtime: null, exists: false };
    }
  });
  res.json({ success: true, data: { files } });
});

router.get('/logs/tail', (req: Request, res: Response) => {
  const parsed = SchemaTailLog.safeParse({ name: req.query.name, lines: req.query.lines ?? 200 });
  if (!parsed.success) {
    res.status(400).json({ success: false, message: parsed.error.errors[0]?.message ?? 'Invalid query' });
    return;
  }
  const resolved = resolveLogPath(parsed.data.name);
  if (!resolved.ok) {
    res.status(400).json({ success: false, message: resolved.message });
    return;
  }
  if (!fs.existsSync(resolved.path)) {
    res.json({ success: true, data: { content: '', size: 0, mtime: null, truncated: false } });
    return;
  }
  try {
    const stat = fs.statSync(resolved.path);
    const tail = tailFile(resolved.path, parsed.data.lines);
    res.json({
      success: true,
      data: { content: tail.content, size: tail.size, mtime: stat.mtime.toISOString(), truncated: tail.truncated },
    });
  } catch (err) {
    log.error('log tail failed', { name: parsed.data.name, error: err instanceof Error ? err.message : String(err) });
    res.status(500).json({ success: false, message: 'Failed to tail log file' });
  }
});

// ─── Watchdog events ───────────────────────────────────────────

const WATCHDOG_EVENTS_FILE = path.join(REPO_ROOT, 'logs', 'watchdog-events.jsonl');

router.get('/watchdog-events', (_req: Request, res: Response) => {
  // Bounded read: at most last 64 KB or 200 events. Same logic as the
  // earlier Electron IPC handler (management-api.ts management:get-watchdog-events).
  if (!fs.existsSync(WATCHDOG_EVENTS_FILE)) {
    res.json({ success: true, events: [] });
    return;
  }
  try {
    const stat = fs.statSync(WATCHDOG_EVENTS_FILE);
    const start = stat.size > 65_536 ? stat.size - 65_536 : 0;
    const fd = fs.openSync(WATCHDOG_EVENTS_FILE, 'r');
    let raw = '';
    try {
      const buf = Buffer.alloc(stat.size - start);
      fs.readSync(fd, buf, 0, buf.length, start);
      raw = buf.toString('utf8');
    } finally {
      fs.closeSync(fd);
    }
    const lines = raw.split('\n').filter((l) => l.trim().length > 0);
    const tail = lines.slice(-200);
    const events: unknown[] = [];
    for (const line of tail) {
      try { events.push(JSON.parse(line)); } catch { /* skip malformed */ }
    }
    res.json({ success: true, events });
  } catch (err) {
    res.status(500).json({ success: false, code: 'READ_ERROR', message: err instanceof Error ? err.message : String(err), events: [] });
  }
});

router.delete('/watchdog-events', (req: Request, res: Response) => {
  try {
    fs.writeFileSync(WATCHDOG_EVENTS_FILE, '', { encoding: 'utf8' });
    auditOp(req, 'super_admin_watchdog_events_clear', {});
    res.json({ success: true });
  } catch (err) {
    const code = (err as NodeJS.ErrnoException | null)?.code;
    if (code === 'ENOENT') {
      res.json({ success: true });
      return;
    }
    res.status(500).json({ success: false, message: err instanceof Error ? err.message : String(err) });
  }
});

// ─── System info / disk space ──────────────────────────────────

router.get('/system/info', (_req: Request, res: Response) => {
  res.json({
    success: true,
    data: {
      platform: process.platform,
      arch: process.arch,
      hostname: os.hostname(),
      nodeVersion: process.version,
      uptime: process.uptime(),
      hostUptime: os.uptime(),
      memory: {
        total: os.totalmem(),
        free: os.freemem(),
        rss: process.memoryUsage().rss,
        heap: process.memoryUsage().heapUsed,
      },
      cpus: os.cpus().length,
      loadAverage: os.loadavg(),
      env: {
        nodeEnv: process.env.NODE_ENV || 'production',
        port: process.env.PORT || '443',
      },
      repoRoot: REPO_ROOT,
    },
  });
});

router.get('/system/disk-space', (_req: Request, res: Response) => {
  // Use Node's statfsSync (Node 19+) for cross-platform free/total bytes.
  // Fall back to a parse of `df -k` if statfsSync throws on some odd FS.
  const targets = [
    { label: 'repo', path: REPO_ROOT },
    { label: 'logs', path: path.join(REPO_ROOT, 'logs') },
    { label: 'data', path: path.join(REPO_ROOT, 'packages', 'server', 'data') },
    { label: 'uploads', path: path.join(REPO_ROOT, 'packages', 'server', 'uploads') },
  ];
  const out: Array<{ label: string; path: string; free?: number; total?: number; error?: string }> = [];
  for (const t of targets) {
    if (!fs.existsSync(t.path)) {
      out.push({ ...t, error: 'path does not exist' });
      continue;
    }
    try {
      const s = (fs as unknown as { statfsSync?: (p: string) => { bsize: number; blocks: number; bavail: number } }).statfsSync;
      if (typeof s === 'function') {
        const r = s(t.path);
        out.push({ label: t.label, path: t.path, free: r.bavail * r.bsize, total: r.blocks * r.bsize });
        continue;
      }
      // Node < 19 fallback: shell out.
      const df = execSync(`df -k "${t.path}"`, { encoding: 'utf8' });
      const lastLine = df.trim().split('\n').pop() || '';
      const parts = lastLine.split(/\s+/);
      // 1k-blocks: parts[1] total, parts[3] free
      const total = (parseInt(parts[1] || '0', 10) || 0) * 1024;
      const free = (parseInt(parts[3] || '0', 10) || 0) * 1024;
      out.push({ label: t.label, path: t.path, free, total });
    } catch (err) {
      out.push({ ...t, error: err instanceof Error ? err.message : String(err) });
    }
  }
  res.json({ success: true, data: { targets: out } });
});

// ─── Service control (PM2 abstractions) ────────────────────────

const PM2_APP = 'bizarre-crm';
const PM2_WATCHDOG = 'bizarre-crm-watchdog';

function pm2(args: string[], opts?: { timeout?: number }): { ok: boolean; stdout: string; stderr: string; code: number | null } {
  const r = spawnSync('pm2', args, {
    encoding: 'utf8',
    timeout: opts?.timeout ?? 30_000,
    shell: process.platform === 'win32',
  });
  return { ok: r.status === 0, stdout: r.stdout || '', stderr: r.stderr || '', code: r.status };
}

router.get('/service/status', (_req: Request, res: Response) => {
  const r = pm2(['jlist']);
  if (!r.ok) {
    res.json({ success: true, data: { available: false, message: 'pm2 not available' } });
    return;
  }
  let entries: Array<{ name: string; pm2_env?: { status?: string }; pid?: number; monit?: { memory?: number; cpu?: number } }> = [];
  try { entries = JSON.parse(r.stdout); } catch { /* malformed jlist */ }
  const apps = [PM2_APP, PM2_WATCHDOG].map((name) => {
    const e = entries.find((x) => x.name === name);
    return {
      name,
      status: e?.pm2_env?.status ?? 'not-installed',
      pid: e?.pid ?? null,
      memory: e?.monit?.memory ?? null,
      cpu: e?.monit?.cpu ?? null,
    };
  });
  res.json({ success: true, data: { available: true, apps } });
});

router.post('/service/start', (req: Request, res: Response) => {
  // Start uses ecosystem.config.js; if pm2 already running, this is a no-op.
  const r = pm2(['start', path.join(REPO_ROOT, 'ecosystem.config.js'), '--update-env', '--listen-timeout', '60000']);
  auditOp(req, 'super_admin_service_start', { ok: r.ok, code: r.code });
  res.json({ success: r.ok, output: r.stdout + r.stderr });
});

router.post('/service/stop', (req: Request, res: Response) => {
  const r1 = pm2(['stop', PM2_APP]);
  const r2 = pm2(['stop', PM2_WATCHDOG]);
  const ok = r1.ok && r2.ok;
  auditOp(req, 'super_admin_service_stop', { ok });
  res.json({ success: ok, output: r1.stdout + r1.stderr + r2.stdout + r2.stderr });
});

router.post('/service/restart', (req: Request, res: Response) => {
  const r1 = pm2(['restart', PM2_APP]);
  const r2 = pm2(['restart', PM2_WATCHDOG]);
  const ok = r1.ok && r2.ok;
  auditOp(req, 'super_admin_service_restart', { ok });
  res.json({ success: ok, output: r1.stdout + r1.stderr + r2.stdout + r2.stderr });
});

router.post('/service/kill-all', (req: Request, res: Response) => {
  // Hard escape hatch: stop both apps + delete from PM2 registry.
  // pm2 daemon stays alive so the operator can later `start` again.
  const ops = [
    pm2(['stop', PM2_APP]),
    pm2(['stop', PM2_WATCHDOG]),
    pm2(['delete', PM2_APP]),
    pm2(['delete', PM2_WATCHDOG]),
  ];
  auditOp(req, 'super_admin_service_kill_all', { results: ops.map((o) => o.code) });
  res.json({ success: true, output: ops.map((o) => o.stdout + o.stderr).join('\n') });
});

router.post('/service/auto-start', (req: Request, res: Response) => {
  const enabledRaw = req.body?.enabled;
  const enable = enabledRaw === true || enabledRaw === 'true';
  // PM2's startup mechanism is per-platform and prints a sudo command we
  // can't run from inside the server process (would need NOPASSWD sudo,
  // which we are NOT going to require). Surface the command and instruct.
  if (enable) {
    const r = pm2(['startup']);
    res.json({
      success: false,
      output: r.stdout + r.stderr,
      message: 'Auto-start cannot be enabled from inside the server process — sudo escalation not available. Run the command printed in `output` from a terminal manually, then `pm2 save`.',
    });
  } else {
    const r = pm2(['unstartup']);
    res.json({
      success: false,
      output: r.stdout + r.stderr,
      message: 'Auto-start cannot be disabled from inside the server process — run the printed sudo command manually.',
    });
  }
  auditOp(req, 'super_admin_service_auto_start_request', { enable });
});

router.post('/service/disable', (req: Request, res: Response) => {
  // Security kill-switch: stop + delete. Same as kill-all but conceptually
  // "I want this off until I explicitly re-enable." Currently identical
  // implementation; kept as separate endpoint for audit clarity.
  const ops = [
    pm2(['stop', PM2_APP]),
    pm2(['stop', PM2_WATCHDOG]),
    pm2(['delete', PM2_APP]),
    pm2(['delete', PM2_WATCHDOG]),
  ];
  auditOp(req, 'super_admin_service_disable', { results: ops.map((o) => o.code) });
  res.json({ success: true, output: ops.map((o) => o.stdout + o.stderr).join('\n') });
});

router.post('/service/emergency-stop', (req: Request, res: Response) => {
  // Fast stop, no graceful shutdown. The server's own SIGTERM/SIGINT
  // handlers do graceful drains; this bypasses them. Use only when the
  // graceful path is wedged.
  const r1 = pm2(['stop', PM2_APP, '--kill-timeout', '500']);
  const r2 = pm2(['stop', PM2_WATCHDOG, '--kill-timeout', '500']);
  auditOp(req, 'super_admin_service_emergency_stop', { ok: r1.ok && r2.ok });
  res.json({ success: r1.ok && r2.ok, output: r1.stdout + r1.stderr + r2.stdout + r2.stderr });
});

export default router;
