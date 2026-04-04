import { Router } from 'express';
import db from '../db/connection.js';
import { asyncHandler } from '../middleware/asyncHandler.js';

const router = Router();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Sanitise an FTS5 MATCH term – strip special chars and quote each token. */
function ftsMatchExpr(keyword: string): string {
  const cleaned = keyword.replace(/[^a-zA-Z0-9\s\-@.]/g, '').trim();
  const tokens = cleaned.split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return '';
  return tokens.map(t => `"${t}"*`).join(' OR ');
}

interface SearchResult {
  id: number;
  display: string;
  type: string;
  subtitle?: string;
}

// ---------------------------------------------------------------------------
// GET /?q=term – Global search across customers, tickets, inventory, invoices
// ---------------------------------------------------------------------------
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const q = (req.query.q as string || '').trim();
    if (!q) {
      return void res.json({
        success: true,
        data: { customers: [], tickets: [], inventory: [], invoices: [] },
      });
    }

    const like = `%${q}%`;
    const limit = 10;

    // --- Customers: FTS search with fallback to LIKE ---
    let customers: SearchResult[] = [];
    const matchExpr = ftsMatchExpr(q);
    if (matchExpr) {
      try {
        customers = db.prepare(`
          SELECT c.id, c.first_name || ' ' || c.last_name AS display, 'customer' AS type,
                 COALESCE(c.phone, c.mobile, c.email) AS subtitle
          FROM customers c
          INNER JOIN customers_fts fts ON fts.rowid = c.id
          WHERE fts.customers_fts MATCH ? AND c.is_deleted = 0
          LIMIT ?
        `).all(matchExpr, limit) as SearchResult[];
      } catch {
        // FTS can fail on odd characters — fall through to LIKE
      }
    }

    if (customers.length === 0) {
      customers = db.prepare(`
        SELECT id, first_name || ' ' || last_name AS display, 'customer' AS type,
               COALESCE(phone, mobile, email) AS subtitle
        FROM customers
        WHERE is_deleted = 0
          AND (first_name LIKE ? OR last_name LIKE ? OR phone LIKE ? OR mobile LIKE ?
               OR email LIKE ? OR organization LIKE ?)
        LIMIT ?
      `).all(like, like, like, like, like, like, limit) as SearchResult[];
    }

    // --- Tickets: search by order_id or device name ---
    const tickets = db.prepare(`
      SELECT t.id, t.order_id AS display, 'ticket' AS type,
             ts.name AS subtitle
      FROM tickets t
      LEFT JOIN ticket_statuses ts ON ts.id = t.status_id
      WHERE t.is_deleted = 0
        AND (t.order_id LIKE ? OR EXISTS (
          SELECT 1 FROM ticket_devices td WHERE td.ticket_id = t.id AND td.device_name LIKE ?
        ))
      ORDER BY t.created_at DESC
      LIMIT ?
    `).all(like, like, limit) as SearchResult[];

    // --- Inventory: search by name or SKU ---
    const inventory = db.prepare(`
      SELECT id, name AS display, 'inventory' AS type,
             sku AS subtitle
      FROM inventory_items
      WHERE is_active = 1 AND (name LIKE ? OR sku LIKE ?)
      LIMIT ?
    `).all(like, like, limit) as SearchResult[];

    // --- Invoices: search by order_id ---
    const invoices = db.prepare(`
      SELECT id, order_id AS display, 'invoice' AS type,
             status AS subtitle
      FROM invoices
      WHERE order_id LIKE ?
      ORDER BY created_at DESC
      LIMIT ?
    `).all(like, limit) as SearchResult[];

    res.json({
      success: true,
      data: { customers, tickets, inventory, invoices },
    });
  }),
);

// ---------------------------------------------------------------------------
// GET /notes — Knowledge base: search across all ticket notes
// ---------------------------------------------------------------------------
router.get(
  '/notes',
  asyncHandler(async (req, res) => {
    const q = (req.query.q as string || '').trim();
    const type = (req.query.type as string || '').trim(); // internal, diagnostic, email
    const page = Math.max(1, parseInt(req.query.page as string) || 1);
    const pageSize = Math.min(50, parseInt(req.query.pagesize as string) || 20);

    if (!q || q.length < 2) {
      return void res.json({ success: true, data: { notes: [], total: 0 } });
    }

    const conditions: string[] = ['tn.content LIKE ?'];
    const params: any[] = [`%${q}%`];
    if (type) { conditions.push('tn.type = ?'); params.push(type); }

    const whereClause = conditions.join(' AND ');
    const total = (db.prepare(`SELECT COUNT(*) as c FROM ticket_notes tn WHERE ${whereClause}`).get(...params) as any).c;

    const notes = db.prepare(`
      SELECT tn.id, tn.ticket_id, tn.type, tn.content, tn.created_at,
             t.order_id, td.device_name,
             u.first_name AS author_first, u.last_name AS author_last,
             c.first_name AS customer_first, c.last_name AS customer_last
      FROM ticket_notes tn
      JOIN tickets t ON t.id = tn.ticket_id
      LEFT JOIN ticket_devices td ON td.ticket_id = t.id
      LEFT JOIN users u ON u.id = tn.user_id
      LEFT JOIN customers c ON c.id = t.customer_id
      WHERE ${whereClause}
      GROUP BY tn.id
      ORDER BY tn.created_at DESC
      LIMIT ? OFFSET ?
    `).all(...params, pageSize, (page - 1) * pageSize);

    res.json({ success: true, data: { notes, pagination: { page, per_page: pageSize, total, total_pages: Math.ceil(total / pageSize) } } });
  }),
);

export default router;
