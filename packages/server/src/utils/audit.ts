import { db } from '../db/connection.js';

let stmt: any = null;

export function audit(event: string, userId: number | null, ip: string, details?: Record<string, unknown>) {
  try {
    if (!stmt) {
      stmt = db.prepare('INSERT INTO audit_logs (event, user_id, ip_address, details) VALUES (?, ?, ?, ?)');
    }
    stmt.run(event, userId, ip, details ? JSON.stringify(details) : null);
  } catch {
    // Don't let audit failures break the app
  }
}
