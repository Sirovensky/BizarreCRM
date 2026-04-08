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

function buildEntry(level: LogLevel, module: string, message: string, meta?: Record<string, unknown>): LogEntry {
  return {
    level,
    message,
    timestamp: new Date().toISOString(),
    module,
    ...(meta || {}),
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
