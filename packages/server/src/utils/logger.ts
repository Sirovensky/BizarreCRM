/**
 * Simple structured logger for the CRM server.
 * Wraps console methods with timestamps and log levels.
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

function shouldLog(level: LogLevel): boolean {
  return LOG_LEVELS[level] >= LOG_LEVELS[currentLevel];
}

function formatTimestamp(): string {
  return new Date().toISOString();
}

function formatMessage(level: LogLevel, module: string, message: string, data?: Record<string, unknown>): string {
  const parts = [`[${formatTimestamp()}]`, `[${level.toUpperCase()}]`, `[${module}]`, message];
  if (data && Object.keys(data).length > 0) {
    parts.push(JSON.stringify(data));
  }
  return parts.join(' ');
}

export function createLogger(module: string) {
  return {
    debug(message: string, data?: Record<string, unknown>) {
      if (shouldLog('debug')) console.debug(formatMessage('debug', module, message, data));
    },
    info(message: string, data?: Record<string, unknown>) {
      if (shouldLog('info')) console.info(formatMessage('info', module, message, data));
    },
    warn(message: string, data?: Record<string, unknown>) {
      if (shouldLog('warn')) console.warn(formatMessage('warn', module, message, data));
    },
    error(message: string, data?: Record<string, unknown>) {
      if (shouldLog('error')) console.error(formatMessage('error', module, message, data));
    },
  };
}

// Default logger for quick use
export const logger = createLogger('app');
