import { config } from '../config.js';

let masterDb: any = null;

export function setMasterDb(db: any): void {
  masterDb = db;
}

// @audit-fixed: Strip control chars from any string before persisting to the
// audit table so attacker-controlled headers/usernames cannot inject fake
// records or break log parsing.
// eslint-disable-next-line no-control-regex
const CONTROL_CHARS = /[\x00-\x1F\x7F]/g;
function stripControl(v: string, maxLen = 500): string {
  return v.replace(CONTROL_CHARS, '').slice(0, maxLen);
}

// @audit-fixed: Cap details JSON so a caller passing 5MB can't bloat the
// audit store or OOM the server.
const MAX_MASTER_AUDIT_DETAILS_BYTES = 16 * 1024;
function serializeDetails(details: Record<string, unknown> | undefined): string | null {
  if (!details) return null;
  let json: string;
  try { json = JSON.stringify(details); }
  catch { return JSON.stringify({ error: 'unserializable' }); }
  if (json.length > MAX_MASTER_AUDIT_DETAILS_BYTES) {
    return JSON.stringify({ truncated: true, bytes: json.length });
  }
  return json;
}

export function logTenantAuthEvent(
  event: string,
  req: any,
  userId: number | null,
  username: string | null,
  details?: Record<string, unknown>
): void {
  if (!config.multiTenant || !masterDb) return;
  try {
    const tenantSlug = req.tenantSlug ? stripControl(String(req.tenantSlug), 64) : null;
    const tenantId = req.tenantId || null;
    const ip = stripControl(String(req.ip || req.socket?.remoteAddress || 'unknown'), 64);
    const ua = stripControl(String(req.headers?.['user-agent'] || ''), 500);
    const safeEvent = stripControl(String(event || 'unknown'), 128);
    const safeUsername = username ? stripControl(String(username), 128) : null;
    const safeDetails = serializeDetails(details);

    masterDb.prepare(`
      INSERT INTO tenant_auth_events (tenant_id, tenant_slug, event, user_id, username, ip_address, user_agent, details)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(tenantId, tenantSlug, safeEvent, userId, safeUsername, ip, ua, safeDetails);

    // Check brute force thresholds on failure events
    if (safeEvent.includes('failed') || safeEvent.includes('locked')) {
      checkBruteForce(ip, tenantId, tenantSlug);
    }
  } catch (err: any) {
    console.warn('[MasterAudit] Failed to log:', err.message);
  }
}

function checkBruteForce(ip: string, tenantId: number | null, tenantSlug: string | null): void {
  if (!masterDb) return;
  try {
    const fifteenMinAgo = new Date(Date.now() - 15 * 60 * 1000).toISOString();
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();

    // Check IP-wide failures (across all tenants)
    const ipFailures = (masterDb.prepare(
      `SELECT COUNT(*) as c FROM tenant_auth_events WHERE ip_address = ? AND event LIKE '%failed%' AND created_at > ?`
    ).get(ip, fifteenMinAgo) as any).c;

    if (ipFailures >= 15) {
      // Dedup: don't create if similar alert exists within 1 hour
      const existing = masterDb.prepare(
        `SELECT id FROM security_alerts WHERE type = 'brute_force_ip' AND ip_address = ? AND created_at > ?`
      ).get(ip, oneHourAgo);
      if (!existing) {
        masterDb.prepare(
          `INSERT INTO security_alerts (type, severity, ip_address, details) VALUES ('brute_force_ip', 'critical', ?, ?)`
        ).run(ip, JSON.stringify({ failure_count: ipFailures, window_minutes: 15 }));
        console.warn(`[Security] ALERT: Brute force from IP ${ip} — ${ipFailures} failures in 15 min`);
      }
    }

    // Check tenant-specific failures
    if (tenantId) {
      const tenantFailures = (masterDb.prepare(
        `SELECT COUNT(*) as c FROM tenant_auth_events WHERE tenant_id = ? AND event LIKE '%failed%' AND created_at > ?`
      ).get(tenantId, fifteenMinAgo) as any).c;

      if (tenantFailures >= 10) {
        const existing = masterDb.prepare(
          `SELECT id FROM security_alerts WHERE type = 'brute_force_tenant' AND tenant_id = ? AND created_at > ?`
        ).get(tenantId, oneHourAgo);
        if (!existing) {
          masterDb.prepare(
            `INSERT INTO security_alerts (type, severity, tenant_id, tenant_slug, details) VALUES ('brute_force_tenant', 'warning', ?, ?, ?)`
          ).run(tenantId, tenantSlug, JSON.stringify({ failure_count: tenantFailures, window_minutes: 15 }));
          console.warn(`[Security] ALERT: Brute force on tenant ${tenantSlug} — ${tenantFailures} failures in 15 min`);
        }
      }
    }
  } catch (err: any) {
    console.warn('[MasterAudit] Brute force check failed:', err.message);
  }
}

/**
 * Log a security alert to the master database.
 * Alerts are surfaced to super-admins on the management dashboard.
 */
export function logSecurityAlert(
  type: string,
  severity: 'info' | 'warning' | 'critical',
  details: Record<string, unknown>,
  req?: any
): void {
  if (!config.multiTenant || !masterDb) return;
  try {
    const safeType = stripControl(String(type || 'unknown'), 128);
    const safeSeverity = stripControl(String(severity || 'warning'), 32);
    const safeDetails = serializeDetails(details);

    // Extract metadata from request if available
    const tenantId = req?.tenantId || null;
    const tenantSlug = req?.tenantSlug ? stripControl(String(req.tenantSlug), 64) : null;
    const ip = req ? stripControl(String(req.ip || req.socket?.remoteAddress || 'unknown'), 64) : null;

    masterDb.prepare(`
      INSERT INTO security_alerts (type, severity, tenant_id, tenant_slug, ip_address, details)
      VALUES (?, ?, ?, ?, ?, ?)
    `).run(safeType, safeSeverity, tenantId, tenantSlug, ip, safeDetails);

    if (severity === 'critical') {
      console.warn(`[Security] CRITICAL ALERT: ${type} - ${JSON.stringify(details)}`);
    } else {
      console.log(`[Security] Alert: ${type}`);
    }
  } catch (err: any) {
    console.warn('[MasterAudit] Failed to log security alert:', err.message);
  }
}
