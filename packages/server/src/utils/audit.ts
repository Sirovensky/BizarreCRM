export function audit(db: any, event: string, userId: number | null, ip: string, details?: Record<string, unknown>) {
  try {
    db.prepare('INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)').run(event, userId, ip, details ? JSON.stringify(details) : null);
  } catch (err) {
    // Don't let audit failures break the app, but log them so they're visible
    console.error('[Audit] Failed to write audit log:', err);
  }
}
