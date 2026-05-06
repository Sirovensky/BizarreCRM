/**
 * Structured JSON logger for the CRM server.
 * Outputs one JSON object per line: { level, message, timestamp, module, ...meta }
 * Compatible with log aggregators (ELK, Loki, CloudWatch, etc.)
 * Can be replaced with pino/winston later without changing call sites.
 */

import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

type LogLevel = 'debug' | 'info' | 'warn' | 'error';

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

const currentLevel: LogLevel = (process.env.LOG_LEVEL as LogLevel) || 'info';

/** Whether to output structured JSON (true) or human-readable text (false). */
const jsonMode = process.env.LOG_FORMAT !== 'text';

const DEFAULT_LOG_FILE_MAX_BYTES = 50 * 1024 * 1024;
const DEFAULT_LOG_FILE_MAX_FILES = 10;

interface RotatingFileSinkConfig {
  enabled: boolean;
  filePath: string;
  maxBytes: number;
  maxFiles: number;
}

let fileSinkConfig = readRotatingFileSinkConfig();
let fileSinkSize: number | undefined;
let fileSinkDisabled = false;
let fileSinkFailureWarned = false;

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLevel];
}

function envFlag(value: string | undefined): boolean {
  return /^(1|true|yes|on)$/i.test((value || '').trim());
}

function parsePositiveInteger(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function parseByteSize(value: string | undefined, fallback: number): number {
  if (!value) return fallback;
  const match = value.trim().match(/^(\d+)(?:\s*([kmg])b?)?$/i);
  if (!match) return fallback;
  const amount = Number.parseInt(match[1], 10);
  if (!Number.isFinite(amount) || amount <= 0) return fallback;
  const unit = (match[2] || '').toLowerCase();
  const multiplier =
    unit === 'g' ? 1024 * 1024 * 1024 :
    unit === 'm' ? 1024 * 1024 :
    unit === 'k' ? 1024 :
    1;
  return amount * multiplier;
}

function findProjectRoot(): string {
  let dir = path.dirname(fileURLToPath(import.meta.url));
  for (let i = 0; i < 8; i += 1) {
    if (fs.existsSync(path.join(dir, 'ecosystem.config.js')) && fs.existsSync(path.join(dir, 'packages/server/package.json'))) {
      return dir;
    }
    const parent = path.dirname(dir);
    if (parent === dir) break;
    dir = parent;
  }
  return process.cwd();
}

function readRotatingFileSinkConfig(): RotatingFileSinkConfig {
  const rawPath = (process.env.LOG_FILE_PATH || '').trim();
  const enabled = envFlag(process.env.LOG_FILE_ENABLED) || rawPath.length > 0;
  const projectRoot = findProjectRoot();
  const filePath = rawPath
    ? (path.isAbsolute(rawPath) ? rawPath : path.resolve(projectRoot, rawPath))
    : path.join(projectRoot, 'logs', 'bizarre-crm.app.log');

  return {
    enabled,
    filePath,
    maxBytes: parseByteSize(process.env.LOG_FILE_MAX_SIZE || process.env.LOG_FILE_MAX_BYTES, DEFAULT_LOG_FILE_MAX_BYTES),
    maxFiles: parsePositiveInteger(process.env.LOG_FILE_MAX_FILES, DEFAULT_LOG_FILE_MAX_FILES),
  };
}

function rotatedPath(filePath: string, index: number): string {
  return `${filePath}.${index}`;
}

function rotateFileSink(config: RotatingFileSinkConfig): void {
  if (config.maxFiles <= 1) {
    if (fs.existsSync(config.filePath)) fs.unlinkSync(config.filePath);
    fileSinkSize = 0;
    return;
  }

  const oldest = rotatedPath(config.filePath, config.maxFiles - 1);
  if (fs.existsSync(oldest)) fs.unlinkSync(oldest);

  for (let i = config.maxFiles - 2; i >= 1; i -= 1) {
    const src = rotatedPath(config.filePath, i);
    if (fs.existsSync(src)) fs.renameSync(src, rotatedPath(config.filePath, i + 1));
  }

  if (fs.existsSync(config.filePath)) {
    fs.renameSync(config.filePath, rotatedPath(config.filePath, 1));
  }
  fileSinkSize = 0;
}

function disableFileSink(err: unknown): void {
  fileSinkDisabled = true;
  if (fileSinkFailureWarned) return;
  fileSinkFailureWarned = true;
  const message = err instanceof Error ? err.message : String(err);
  console.error(`[logger] rotating file sink disabled after write failure: ${message}`);
}

function writeRotatingFileLine(line: string): void {
  const config = fileSinkConfig;
  if (!config.enabled || fileSinkDisabled) return;

  try {
    fs.mkdirSync(path.dirname(config.filePath), { recursive: true });
    if (fileSinkSize === undefined) {
      fileSinkSize = fs.existsSync(config.filePath) ? fs.statSync(config.filePath).size : 0;
    }

    const payload = `${line}\n`;
    const bytes = Buffer.byteLength(payload);
    if (fileSinkSize > 0 && fileSinkSize + bytes > config.maxBytes) {
      rotateFileSink(config);
    }

    fs.appendFileSync(config.filePath, payload, 'utf8');
    fileSinkSize = (fileSinkSize || 0) + bytes;
  } catch (err) {
    disableFileSink(err);
  }
}

interface LogEntry {
  level: string;
  message: string;
  timestamp: string;
  module: string;
  [key: string]: unknown;
}

// PROD53: PII masking for non-debug logs. Customer phones / emails / street
// addresses end up in meta bags (webhook error payloads, sms failure logs,
// tenant-audit events). In production we redact them to last-4 / domain-only
// / placeholder so ops dashboards + log aggregators stay PII-free. Debug
// level keeps full values so developers can trace real data locally.
//
// Designed to be zero-alloc on the happy path (no masking work when the
// meta bag is empty, when level == 'debug', or when we're not in production).
const PII_PATTERNS = {
  email: /^[A-Za-z0-9._%+-]+@([A-Za-z0-9.-]+\.[A-Za-z]{2,})$/,
  phoneDigits: /^\+?\d{8,15}$/,
};
const PII_KEY_HINTS = ['email', 'phone', 'mobile', 'address', 'street', 'to', 'from', 'recipient', 'customer_email', 'customer_phone'];

function maskEmail(v: string): string {
  const m = v.match(PII_PATTERNS.email);
  return m ? `***@${m[1]}` : '[REDACTED:email]';
}
function maskPhone(v: string): string {
  const digits = v.replace(/\D/g, '');
  if (digits.length < 4) return '[REDACTED:phone]';
  return `***-***-${digits.slice(-4)}`;
}
function redactMetaValue(key: string, value: unknown): unknown {
  if (value == null || typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value !== 'string') {
    // Walk one level into objects so nested `{to: '...'}` in webhook payloads gets masked.
    if (typeof value === 'object' && !Array.isArray(value)) {
      const out: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
        out[k] = redactMetaValue(k, v);
      }
      return out;
    }
    return value;
  }
  const k = key.toLowerCase();
  if (k.includes('email')) return maskEmail(value);
  if (k.includes('phone') || k === 'to' || k === 'from' || k === 'mobile') {
    return PII_PATTERNS.phoneDigits.test(value) ? maskPhone(value) : value;
  }
  if (k.includes('address') || k.includes('street')) {
    return value.length > 4 ? `[REDACTED:address len=${value.length}]` : value;
  }
  return value;
}
function redactMetaForProduction(meta: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(meta)) {
    out[k] = redactMetaValue(k, v);
  }
  return out;
}

function buildEntry(level: LogLevel, module: string, message: string, meta?: Record<string, unknown>): LogEntry {
  const isProd = process.env.NODE_ENV === 'production';
  const shouldMask = isProd && level !== 'debug' && meta && Object.keys(meta).length > 0;
  const safeMeta = shouldMask ? redactMetaForProduction(meta!) : meta;
  return {
    level,
    message,
    timestamp: new Date().toISOString(),
    module,
    ...(safeMeta || {}),
  };
}

function formatOutput(entry: LogEntry): string {
  if (jsonMode) {
    return JSON.stringify(entry);
  }
  // Human-readable fallback
  const { level, message, timestamp, module, ...rest } = entry;
  const parts = [`[${timestamp}]`, `[${level.toUpperCase()}]`, `[${module}]`, message];
  if (Object.keys(rest).length > 0) {
    parts.push(JSON.stringify(rest));
  }
  return parts.join(' ');
}

function writeLogLine(level: LogLevel, line: string): void {
  if (level === 'debug') {
    console.debug(line);
  } else if (level === 'info') {
    console.info(line);
  } else if (level === 'warn') {
    console.warn(line);
  } else {
    console.error(line);
  }
  writeRotatingFileLine(line);
}

// Stable public contract for the app logger. Exporting this as an explicit
// interface means test doubles / mocks and future `logger.X = ...` sites
// don't silently drift from the real implementation.
export interface Logger {
  debug(message: string, meta?: Record<string, unknown>): void;
  info(message: string, meta?: Record<string, unknown>): void;
  warn(message: string, meta?: Record<string, unknown>): void;
  error(message: string, meta?: Record<string, unknown>): void;
}

export function createLogger(module: string): Logger {
  return {
    debug(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('debug')) writeLogLine('debug', formatOutput(buildEntry('debug', module, message, meta)));
    },
    info(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('info')) writeLogLine('info', formatOutput(buildEntry('info', module, message, meta)));
    },
    warn(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('warn')) writeLogLine('warn', formatOutput(buildEntry('warn', module, message, meta)));
    },
    error(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('error')) writeLogLine('error', formatOutput(buildEntry('error', module, message, meta)));
    },
  };
}

export function _resetLoggerFileSinkForTests(): void {
  fileSinkConfig = readRotatingFileSinkConfig();
  fileSinkSize = undefined;
  fileSinkDisabled = false;
  fileSinkFailureWarned = false;
}

// Default logger for quick use
export const logger = createLogger('app');
