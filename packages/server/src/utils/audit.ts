// @audit-fixed: Cap details JSON at 16KB and strip CR/LF from the event string
// so callers cannot blow up audit_logs storage with 1MB payloads or inject
// fake log lines via CRLF in the event name.
import { createLogger } from './logger.js';
const logger = createLogger('audit');
const MAX_AUDIT_DETAILS_BYTES = 16 * 1024;
const MAX_AUDIT_EVENT_LEN = 128;

function sanitizeEvent(event: unknown): string {
  if (typeof event !== 'string') return 'unknown';
  // @audit-fixed: Strip control chars that could inject fake log records.
  // eslint-disable-next-line no-control-regex
  const clean = event.replace(/[\x00-\x1F\x7F]/g, '');
  return clean.slice(0, MAX_AUDIT_EVENT_LEN) || 'unknown';
}

function serializeDetails(details: Record<string, unknown> | undefined): string | null {
  if (!details) return null;
  let json: string;
  try {
    json = JSON.stringify(details);
  } catch {
    // @audit-fixed: Circular refs/throwing toJSON no longer kill the caller.
    return JSON.stringify({ error: 'unserializable_audit_details' });
  }
  if (json.length > MAX_AUDIT_DETAILS_BYTES) {
    // @audit-fixed: Cap oversized details so a malicious payload can't fill
    // the audit_logs table. Keep a marker so the truncation is visible.
    return JSON.stringify({ truncated: true, bytes: json.length });
  }
  return json;
}

export function audit(db: any, event: string, userId: number | null, ip: string, details?: Record<string, unknown>) {
  try {
    const safeEvent = sanitizeEvent(event);
    // @audit-fixed: Truncate overly long IP values so a forged header can't
    // bloat the row or break prepared statements.
    const safeIp = typeof ip === 'string' ? ip.slice(0, 64) : 'unknown';
    const serialized = serializeDetails(details);
    db.prepare('INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)').run(safeEvent, userId, safeIp, serialized);
  } catch (err) {
    // Don't let audit failures break the app, but log them so they're visible
    logger.error('Failed to write audit log', { err });
  }
}
