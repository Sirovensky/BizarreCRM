import { app } from 'electron';
import log from 'electron-log';
import path from 'node:path';
import { inspect } from 'node:util';

type LogLevel = 'error' | 'warn' | 'info' | 'debug' | 'verbose';

interface ElectronLogMessage {
  data: unknown[];
  date?: Date;
  level?: string;
  scope?: string;
}

const REDACTED_KEY_PATTERN = /authorization|cookie|credential|password|pin|secret|token/i;
const DASHBOARD_LOG_FILE = 'dashboard.log';

function safeInspect(value: unknown): string {
  return inspect(value, { breakLength: Infinity, depth: 2, maxArrayLength: 20 });
}

function messageText(value: unknown): string {
  if (typeof value === 'string') return value;
  if (value instanceof Error) return value.message;
  if (value === undefined) return '';
  return safeInspect(value);
}

function sanitizeValue(value: unknown, seen = new WeakSet<object>(), depth = 0): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return value.length > 2048 ? `${value.slice(0, 2045)}...` : value;
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (typeof value === 'bigint') return value.toString();
  if (typeof value === 'symbol' || typeof value === 'function') return String(value);
  if (value instanceof Date) return value.toISOString();
  if (value instanceof Error) {
    const out: Record<string, unknown> = {
      name: value.name,
      message: value.message,
    };
    if (value.stack) out.stack = value.stack;
    if ('code' in value) out.code = sanitizeValue((value as { code?: unknown }).code, seen, depth + 1);
    if ('cause' in value) out.cause = sanitizeValue((value as { cause?: unknown }).cause, seen, depth + 1);
    return out;
  }

  if (depth >= 6) return '[MaxDepth]';
  const objectValue = value as object;
  if (seen.has(objectValue)) return '[Circular]';
  seen.add(objectValue);

  if (Array.isArray(value)) {
    return value.slice(0, 50).map((item) => sanitizeValue(item, seen, depth + 1));
  }

  const out: Record<string, unknown> = {};
  for (const [key, nested] of Object.entries(value as Record<string, unknown>).slice(0, 50)) {
    out[key] = REDACTED_KEY_PATTERN.test(key) ? '[REDACTED]' : sanitizeValue(nested, seen, depth + 1);
  }
  return out;
}

function metadataFromData(data: unknown[]): unknown {
  if (data.length === 0) return undefined;
  const [first, ...rest] = data;
  if (rest.length === 0) {
    return first instanceof Error ? { error: first } : undefined;
  }
  return rest.length === 1 ? rest[0] : { args: rest };
}

function formatStructuredMessage(message: ElectronLogMessage): string {
  const data = message.data ?? [];
  const [first] = data;
  const record: Record<string, unknown> = {
    level: message.level ?? 'info',
    time: (message.date ?? new Date()).toISOString(),
    msg: messageText(first),
  };
  if (message.scope) record.scope = message.scope;

  const metadata = metadataFromData(data);
  if (metadata !== undefined) {
    record.meta = sanitizeValue(metadata);
  }

  return JSON.stringify(record);
}

function configureMainLogger(): void {
  log.transports.file.level = 'silly';
  log.transports.file.resolvePathFn = () => path.join(app.getPath('userData'), DASHBOARD_LOG_FILE);
  log.transports.file.format = ({ message }: { message: ElectronLogMessage }) => [formatStructuredMessage(message)];
  log.transports.file.maxSize = 0;
  log.transports.file.writeOptions = { flag: 'a', mode: 0o600, encoding: 'utf8' };

  log.transports.console.format = '{text}';
  log.transports.console.level = app.isPackaged ? false : 'silly';
  if (log.transports.ipc) log.transports.ipc.level = false;
  if (log.transports.remote) log.transports.remote.level = false;
}

function write(level: LogLevel, message: string, metadata?: unknown): void {
  if (metadata === undefined) {
    log[level](message);
    return;
  }
  log[level](message, metadata);
}

configureMainLogger();

export const logger = {
  error: (message: string, metadata?: unknown): void => { write('error', message, metadata); },
  warn: (message: string, metadata?: unknown): void => { write('warn', message, metadata); },
  info: (message: string, metadata?: unknown): void => { write('info', message, metadata); },
  debug: (message: string, metadata?: unknown): void => { write('debug', message, metadata); },
  verbose: (message: string, metadata?: unknown): void => { write('verbose', message, metadata); },
};
