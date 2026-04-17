/**
 * Structured JSON logger for the CRM server.
 * Outputs one JSON object per line: { level, message, timestamp, module, ...meta }
 * Compatible with log aggregators (ELK, Loki, CloudWatch, etc.)
 * Can be replaced with pino/winston later without changing call sites.
 */

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

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLevel];
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

export function createLogger(module: string) {
  return {
    debug(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('debug')) console.debug(formatOutput(buildEntry('debug', module, message, meta)));
    },
    info(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('info')) console.info(formatOutput(buildEntry('info', module, message, meta)));
    },
    warn(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('warn')) console.warn(formatOutput(buildEntry('warn', module, message, meta)));
    },
    error(message: string, meta?: Record<string, unknown>) {
      if (shouldLog('error')) console.error(formatOutput(buildEntry('error', module, message, meta)));
    },
  };
}

// Default logger for quick use
export const logger = createLogger('app');
