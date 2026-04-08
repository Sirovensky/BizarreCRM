import { config } from '../config.js';

let masterDb: any = null;

export function setMasterDb(db: any): void {
  masterDb = db;
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
    const tenantSlug = req.tenantSlug || null;
    const tenantId = req.tenantId || null;
    const ip = req.ip || req.socket?.remoteAddress || 'unknown';
    const ua = (req.headers?.['user-agent'] || '').slice(0, 500);

    masterDb.prepare(`
      INSERT INTO tenant_auth_events (tenant_id, tenant_slug, event, user_id, username, ip_address, user_agent, details)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    `).run(tenantId, tenantSlug, event, userId, username, ip, ua, details ? JSON.stringify(details) : null);

    // Check brute force thresholds on failure events
    if (event.includes('failed') || event.includes('locked')) {
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
