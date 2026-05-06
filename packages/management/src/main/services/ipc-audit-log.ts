import { app, type IpcMainInvokeEvent } from 'electron';
import fs from 'node:fs';
import path from 'node:path';

type AuditStatus = 'success' | 'failure' | 'error';

interface AuditDetails {
  [key: string]: unknown;
}

interface AuditRecord {
  timestamp: string;
  operation: string;
  status: AuditStatus;
  origin: string;
  url: string;
  duration_ms?: number;
  details?: AuditDetails;
}

const DEFAULT_MAX_BYTES = 10 * 1024 * 1024;

function configuredMaxBytes(): number {
  const raw = Number.parseInt(process.env['DASHBOARD_AUDIT_LOG_MAX_BYTES'] ?? '', 10);
  return Number.isFinite(raw) && raw >= 1024 ? raw : DEFAULT_MAX_BYTES;
}

function auditLogPath(): string {
  const dir = app.getPath('userData');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  return path.join(dir, 'audit.log');
}

function rotateIfLarge(filePath: string): void {
  try {
    const stat = fs.statSync(filePath);
    if (stat.size <= configuredMaxBytes()) return;
    const backupPath = `${filePath}.1`;
    try { fs.unlinkSync(backupPath); } catch { /* no previous backup */ }
    fs.renameSync(filePath, backupPath);
  } catch {
    /* absent/unreadable logs should never block the IPC operation */
  }
}

function senderUrl(event: IpcMainInvokeEvent): string {
  const frameUrl = event.senderFrame?.url;
  if (frameUrl) return frameUrl;
  try { return event.sender.getURL(); } catch { return 'unknown'; }
}

function senderOrigin(event: IpcMainInvokeEvent): string {
  const url = senderUrl(event);
  try { return new URL(url).origin; } catch { return 'unknown'; }
}

function sanitizeValue(value: unknown): unknown {
  if (value === null || value === undefined) return value;
  if (typeof value === 'string') return value.length > 256 ? `${value.slice(0, 253)}...` : value;
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (Array.isArray(value)) return value.slice(0, 20).map(sanitizeValue);
  if (typeof value === 'object') {
    const out: AuditDetails = {};
    for (const [key, nested] of Object.entries(value as Record<string, unknown>).slice(0, 30)) {
      if (/password|secret|token|key|pin|credential/i.test(key)) {
        out[key] = '[REDACTED]';
      } else {
        out[key] = sanitizeValue(nested);
      }
    }
    return out;
  }
  return String(value);
}

export function writeIpcAuditRecord(record: AuditRecord): void {
  try {
    const filePath = auditLogPath();
    rotateIfLarge(filePath);
    fs.appendFileSync(filePath, `${JSON.stringify(sanitizeValue(record))}\n`, { encoding: 'utf-8', mode: 0o600 });
  } catch (err) {
    try {
      console.warn('[IPC audit] write failed:', err instanceof Error ? err.message : String(err));
    } catch {
      /* nothing else to do */
    }
  }
}

export async function auditIpcOperation<T>(
  event: IpcMainInvokeEvent,
  operation: string,
  details: AuditDetails | undefined,
  action: () => Promise<T>,
  isSuccess: (result: T) => boolean = () => true,
): Promise<T> {
  const startedAt = Date.now();
  try {
    const result = await action();
    writeIpcAuditRecord({
      timestamp: new Date().toISOString(),
      operation,
      status: isSuccess(result) ? 'success' : 'failure',
      origin: senderOrigin(event),
      url: senderUrl(event),
      duration_ms: Date.now() - startedAt,
      details,
    });
    return result;
  } catch (err) {
    writeIpcAuditRecord({
      timestamp: new Date().toISOString(),
      operation,
      status: 'error',
      origin: senderOrigin(event),
      url: senderUrl(event),
      duration_ms: Date.now() - startedAt,
      details: {
        ...details,
        error: err instanceof Error ? err.message : String(err),
      },
    });
    throw err;
  }
}
