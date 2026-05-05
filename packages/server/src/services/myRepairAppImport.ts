/**
 * MyRepairApp API Import Service
 *
 * Pulls customers, tickets, invoices, and inventory from
 * MyRepairApp's public API and inserts them into the local SQLite DB.
 *
 * Design:
 *  - Rate-limited fetching (60 req/min → 1000 ms delay between requests)
 *  - Idempotent via import_id_map lookups before insert
 *  - Progress tracked in import_runs rows (total_records, imported, skipped, errors)
 *  - Errors per-record are logged but never abort the whole run
 *  - Entities processed in dependency order: customers → inventory → tickets → invoices
 *
 * API details:
 *  - Auth: X-Api-Key header
 *  - Base URL: https://www.myrepairapp.com/api/v2/
 *  - Rate limit: 60 req/min (use 1000 ms delay between requests)
 *  - Pagination: Only on inventory search (page + pageSize). Others return all records.
 *  - Response shapes vary by endpoint.
 */

import { normalizePhone } from '../utils/phone.js';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface ImportRunRow {
  id: number;
  source: string;
  entity_type: string;
  status: string;
  total_records: number;
  imported: number;
  skipped: number;
  errors: number;
  error_log: string;
  started_at: string | null;
  completed_at: string | null;
}

interface ErrorEntry {
  record_id: string | number;
  message: string;
  timestamp: string;
}

type MraEntityType = 'customers' | 'tickets' | 'invoices' | 'inventory';

// Per-tenant cancellation flags (keyed by tenant slug; 'default' for single-tenant)
const cancelFlagsMRA = new Map<string, boolean>();
export function requestCancelMRA(tenantSlug?: string): void {
  cancelFlagsMRA.set(tenantSlug || 'default', true);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function now(): string {
  return new Date().toISOString().replace('T', ' ').substring(0, 19);
}

function sleep(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function safeStr(val: unknown): string | null {
  if (val === undefined || val === null || val === '') return null;
  return String(val);
}

function safeNum(val: unknown, fallback: number = 0): number {
  if (val === undefined || val === null || val === '') return fallback;
  const cleaned = typeof val === 'string' ? val.replace(/[$,]/g, '').trim() : val;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : fallback;
}

function safeInt(val: unknown, fallback: number = 0): number {
  return Math.round(safeNum(val, fallback));
}

/** Convert a date string or unix timestamp to ISO datetime string */
function toISODate(val: unknown): string | null {
  if (!val) return null;
  // Unix timestamp (number or numeric string)
  if (typeof val === 'number' || /^\d{10,13}$/.test(String(val))) {
    const ts = Number(val);
    const d = new Date(ts < 1e12 ? ts * 1000 : ts);
    if (!isNaN(d.getTime())) return d.toISOString().replace('T', ' ').substring(0, 19);
    return null;
  }
  // Already a date string
  const d = new Date(String(val));
  if (!isNaN(d.getTime())) return d.toISOString().replace('T', ' ').substring(0, 19);
  return null;
}

/** Strip HTML tags from a string (for MRA ticket notes that contain HTML) */
function stripHtml(html: string): string {
  return html
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<\/p>/gi, '\n')
    .replace(/<[^>]*>/g, '')
    .replace(/&nbsp;/g, ' ')
    .replace(/&amp;/g, '&')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .trim();
}

// ---------------------------------------------------------------------------
// MyRepairApp API Client
// ---------------------------------------------------------------------------

export class MraApiClient {
  private baseUrl: string;
  private apiKey: string;
  readonly tenantSlug: string;

  constructor(apiKey: string, baseUrl?: string, tenantSlug?: string) {
    this.apiKey = apiKey;
    this.baseUrl = (baseUrl || 'https://www.myrepairapp.com/api/v2').replace(/\/$/, '');
    this.tenantSlug = tenantSlug || 'default';
  }

  /** Common headers for all MRA API requests */
  private getHeaders(): Record<string, string> {
    return { 'X-Api-Key': this.apiKey, 'Accept': 'application/json' };
  }

  /** Test the API key by fetching customers (small payload check). */
  async testConnection(): Promise<{ ok: boolean; message: string; totalCustomers?: number }> {
    try {
      const url = `${this.baseUrl}/customers`;
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(15000),
        headers: this.getHeaders(),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        return { ok: false, message: `HTTP ${resp.status}: ${text.substring(0, 200)}` };
      }
      const json = await resp.json() as { data?: unknown[] };
      const customers = Array.isArray(json.data) ? json.data : [];
      return {
        ok: true,
        message: 'Connected successfully',
        totalCustomers: customers.length,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Connection failed';
      return { ok: false, message };
    }
  }

  /**
   * Fetch all customers. MRA returns all records in a single call.
   * Response shape: { "data": [...] }
   */
  async fetchCustomers(): Promise<unknown[]> {
    const url = `${this.baseUrl}/customers`;
    const resp = await fetch(url, {
      signal: AbortSignal.timeout(60000),
      headers: this.getHeaders(),
    });
    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      throw new Error(`MRA API /customers: HTTP ${resp.status} - ${text.substring(0, 300)}`);
    }
    const json = await resp.json() as { data?: unknown[] };
    return Array.isArray(json.data) ? json.data : [];
  }

  /**
   * Fetch all tickets. MRA requires a `query` param; use `*` to get all.
   * Must call twice: closed=false and closed=true.
   * Response shape: { "tickets": [...] }
   */
  async fetchTickets(): Promise<unknown[]> {
    const allTickets: unknown[] = [];

    // Fetch open tickets
    const openUrl = `${this.baseUrl}/checkin-ticket?query=*&closed=false`;
    const openResp = await fetch(openUrl, {
      signal: AbortSignal.timeout(120000),
      headers: this.getHeaders(),
    });
    if (!openResp.ok) {
      const text = await openResp.text().catch(() => '');
      throw new Error(`MRA API /checkin-ticket (open): HTTP ${openResp.status} - ${text.substring(0, 300)}`);
    }
    const openJson = await openResp.json() as { tickets?: unknown[] };
    if (Array.isArray(openJson.tickets)) {
      allTickets.push(...openJson.tickets);
    }

    await sleep(1000); // Rate limit: 60 req/min

    // Fetch closed tickets
    const closedUrl = `${this.baseUrl}/checkin-ticket?query=*&closed=true`;
    const closedResp = await fetch(closedUrl, {
      signal: AbortSignal.timeout(120000),
      headers: this.getHeaders(),
    });
    if (!closedResp.ok) {
      const text = await closedResp.text().catch(() => '');
      throw new Error(`MRA API /checkin-ticket (closed): HTTP ${closedResp.status} - ${text.substring(0, 300)}`);
    }
    const closedJson = await closedResp.json() as { tickets?: unknown[] };
    if (Array.isArray(closedJson.tickets)) {
      allTickets.push(...closedJson.tickets);
    }

    return allTickets;
  }

  /**
   * Fetch all invoices. MRA returns all records in a single call.
   * Response shape: { "data": [...] }
   */
  async fetchInvoices(): Promise<unknown[]> {
    const url = `${this.baseUrl}/invoice`;
    const resp = await fetch(url, {
      signal: AbortSignal.timeout(120000),
      headers: this.getHeaders(),
    });
    if (!resp.ok) {
      const text = await resp.text().catch(() => '');
      throw new Error(`MRA API /invoice: HTTP ${resp.status} - ${text.substring(0, 300)}`);
    }
    const json = await resp.json() as { data?: unknown[] };
    return Array.isArray(json.data) ? json.data : [];
  }

  /**
   * Fetch all inventory items. MRA paginates this endpoint (page + pageSize).
   * Yields arrays of records per page.
   */
  async *fetchInventoryPages(
    pageSize: number = 50,
  ): AsyncGenerator<{ records: unknown[]; page: number; hasMore: boolean }> {
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      if (cancelFlagsMRA.get(this.tenantSlug)) break;

      const url = `${this.baseUrl}/inventory/search?page=${page}&pageSize=${pageSize}`;
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(60000),
        headers: this.getHeaders(),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        throw new Error(`MRA API /inventory/search page ${page}: HTTP ${resp.status} - ${text.substring(0, 300)}`);
      }

      const json = await resp.json() as { data?: unknown[] };
      const records = Array.isArray(json.data) ? json.data : [];

      yield { records, page, hasMore: records.length >= pageSize };

      hasMore = records.length >= pageSize;
      page++;

      if (hasMore) await sleep(1000); // Rate limit: 60 req/min
    }
  }
}

// ---------------------------------------------------------------------------
// Prepared Statements (lazily created, reused across calls)
// ---------------------------------------------------------------------------

function getStatements(db: any) {
  return {
    // import_id_map
    findMapping: db.prepare(
      `SELECT local_id FROM import_id_map
       WHERE entity_type = ? AND source_id = ?
       ORDER BY id DESC LIMIT 1`
    ),
    insertMapping: db.prepare(
      `INSERT INTO import_id_map (import_run_id, entity_type, source_id, local_id)
       VALUES (?, ?, ?, ?)`
    ),

    // import_runs progress
    updateRunProgress: db.prepare(
      `UPDATE import_runs
       SET status = ?, total_records = ?, imported = ?, skipped = ?, errors = ?, error_log = ?
       WHERE id = ?`
    ),
    markRunRunning: db.prepare(
      `UPDATE import_runs SET status = 'running', started_at = ? WHERE id = ?`
    ),
    markRunComplete: db.prepare(
      `UPDATE import_runs SET status = ?, completed_at = ?, total_records = ?, imported = ?, skipped = ?, errors = ?, error_log = ? WHERE id = ?`
    ),

    // customers
    insertCustomer: db.prepare(
      `INSERT INTO customers
        (first_name, last_name, title, organization, type, email, phone, mobile,
         address1, address2, city, state, postcode, country,
         referred_by, comments, source, tags, email_opt_in, sms_opt_in, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?,
               ?, ?, ?, '[]', ?, ?, ?, ?)`
    ),
    updateCustomerCode: db.prepare(
      `UPDATE customers SET code = ? WHERE id = ?`
    ),
    insertCustomerPhone: db.prepare(
      `INSERT INTO customer_phones (customer_id, phone, label, is_primary) VALUES (?, ?, ?, ?)`
    ),
    insertCustomerEmail: db.prepare(
      `INSERT INTO customer_emails (customer_id, email, label, is_primary) VALUES (?, ?, ?, ?)`
    ),

    // ticket statuses
    findStatusByName: db.prepare(
      `SELECT id FROM ticket_statuses WHERE LOWER(name) = LOWER(?) LIMIT 1`
    ),
    defaultStatusId: db.prepare(
      `SELECT id FROM ticket_statuses WHERE is_default = 1 LIMIT 1`
    ),

    // tickets (OR IGNORE to handle duplicate order_ids gracefully)
    insertTicket: db.prepare(
      `INSERT OR IGNORE INTO tickets
        (order_id, customer_id, status_id, subtotal, discount, discount_reason,
         total_tax, total, source, referral_source, signature, labels,
         due_on, is_deleted, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?,
               ?, 0, 1, ?, ?)`
    ),
    findTicketByOrderId: db.prepare(
      `SELECT id FROM tickets WHERE order_id = ?`
    ),

    // ticket devices
    insertTicketDevice: db.prepare(
      `INSERT INTO ticket_devices
        (ticket_id, device_name, device_type, imei, serial, security_code, color, network,
         status_id, price, line_discount, tax_amount, tax_inclusive, total,
         warranty, warranty_days, due_on, collected_date, device_location, additional_notes,
         pre_conditions, post_conditions, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?)`
    ),

    // ticket device parts
    insertTicketPart: db.prepare(
      `INSERT INTO ticket_device_parts
        (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 'available', ?, ?)`
    ),

    // Find inventory item by name
    findInventoryByName: db.prepare(
      `SELECT id FROM inventory_items WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND is_active = 1 LIMIT 1`
    ),

    // ticket notes
    insertTicketNote: db.prepare(
      `INSERT INTO ticket_notes
        (ticket_id, ticket_device_id, user_id, type, content, is_flagged, created_at, updated_at)
       VALUES (?, ?, 1, ?, ?, ?, ?, ?)`
    ),

    // ticket history
    insertTicketHistory: db.prepare(
      `INSERT INTO ticket_history (ticket_id, user_id, action, description, created_at)
       VALUES (?, 1, ?, ?, ?)`
    ),

    // inventory
    findInventoryBySku: db.prepare(
      `SELECT id FROM inventory_items WHERE sku = ? LIMIT 1`
    ),
    insertInventoryItem: db.prepare(
      `INSERT OR IGNORE INTO inventory_items
        (sku, upc, name, description, item_type, category, manufacturer,
         cost_price, retail_price, in_stock, reorder_level, stock_warning,
         tax_inclusive, is_serialized, is_active, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?,
               ?, ?, 1, ?, ?)`
    ),

    // invoices
    insertInvoice: db.prepare(
      `INSERT INTO invoices
        (order_id, ticket_id, customer_id, status, subtotal, discount, discount_reason,
         total_tax, total, amount_paid, amount_due, due_on, notes, created_by, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?,
               ?, ?, ?, ?, ?, ?, 1, ?, ?)`
    ),
    insertInvoiceLineItem: db.prepare(
      `INSERT INTO invoice_line_items
        (invoice_id, inventory_item_id, description, quantity, unit_price, line_discount, tax_amount, total, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
    ),
    insertPayment: db.prepare(
      `INSERT INTO payments (invoice_id, amount, method, method_detail, transaction_id, notes, user_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 1, ?, ?)`
    ),
  };
}

// ---------------------------------------------------------------------------
// Status name -> local status ID mapping with caching
// ---------------------------------------------------------------------------

const statusCache = new Map<string, number>();

function resolveStatusId(
  db: any,
  statusName: string | null | undefined,
  stmts: ReturnType<typeof getStatements>,
): number {
  if (!statusName) {
    const def = stmts.defaultStatusId.get() as { id: number } | undefined;
    return def?.id ?? 1;
  }

  const key = statusName.toLowerCase().trim();
  if (statusCache.has(key)) return statusCache.get(key)!;

  const found = stmts.findStatusByName.get(key) as { id: number } | undefined;
  if (found) {
    statusCache.set(key, found.id);
    return found.id;
  }

  // Try partial match
  const allStatuses = db.prepare('SELECT id, name FROM ticket_statuses').all() as { id: number; name: string }[];
  for (const s of allStatuses) {
    if (s.name.toLowerCase().includes(key) || key.includes(s.name.toLowerCase())) {
      statusCache.set(key, s.id);
      return s.id;
    }
  }

  // Fallback to default
  const def = stmts.defaultStatusId.get() as { id: number } | undefined;
  const fallback = def?.id ?? 1;
  statusCache.set(key, fallback);
  return fallback;
}

// ---------------------------------------------------------------------------
// MRA category -> local item_type mapping
// ---------------------------------------------------------------------------

function mapMraCategory(category: string | null): { itemType: 'product' | 'part' | 'service'; localCategory: string } {
  if (!category) return { itemType: 'product', localCategory: '' };

  const lower = category.toLowerCase().trim();

  if (lower === 'repair' || lower === 'service') {
    return { itemType: 'service', localCategory: category };
  }
  if (lower === 'part') {
    return { itemType: 'part', localCategory: category };
  }
  // Accessory, Device -> product
  return { itemType: 'product', localCategory: category };
}

// ---------------------------------------------------------------------------
// Entity Importers
// ---------------------------------------------------------------------------

export async function importCustomersMRA(
  db: any,
  client: MraApiClient,
  runId: number,
  stmts: ReturnType<typeof getStatements>,
  tenantSlug: string,
): Promise<void> {
  stmts.markRunRunning.run(now(), runId);

  let totalRecords = 0;
  let imported = 0;
  let skipped = 0;
  let errors = 0;
  const errorLog: ErrorEntry[] = [];

  try {
    const records = await client.fetchCustomers() as any[];
    totalRecords = records.length;

    // Process in batches of 100 within a transaction
    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsMRA.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const mra of batch) {
          try {
            const mraId = String(mra.id || mra.customerId || '');
            if (!mraId) {
              errors++;
              errorLog.push({ record_id: 'unknown', message: 'No customer ID found', timestamp: now() });
              continue;
            }

            // Idempotent check
            const existing = stmts.findMapping.get('customer', mraId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            const createdAt = toISODate(mra.createdAt) || toISODate(mra.created_at) || now();
            const firstName = safeStr(mra.firstName) || safeStr(mra.first_name) || '';
            const lastName = safeStr(mra.lastName) || safeStr(mra.last_name) || '';
            const email = safeStr(mra.email);
            const phone = safeStr(mra.primaryPhone) || safeStr(mra.phone);
            const mobile = safeStr(mra.contactPhone) || safeStr(mra.mobile);
            const organization = safeStr(mra.company) || safeStr(mra.organization);

            const result = stmts.insertCustomer.run(
              firstName,
              lastName,
              null, // title (not in MRA)
              organization,
              organization ? 'business' : 'individual',
              email,
              phone,
              mobile,
              safeStr(mra.street1) || safeStr(mra.address1),
              safeStr(mra.street2) || safeStr(mra.address2),
              safeStr(mra.city),
              safeStr(mra.state),
              safeStr(mra.postalCode) || safeStr(mra.postcode),
              safeStr(mra.country),
              null, // referred_by
              safeStr(mra.notes) || safeStr(mra.comments),
              'myrepairapp',
              0, // email_opt_in
              0, // sms_opt_in
              createdAt,
              createdAt,
            );

            const localId = Number(result.lastInsertRowid);

            // Generate customer code
            const code = `C-${String(localId).padStart(4, '0')}`;
            stmts.updateCustomerCode.run(code, localId);

            // Insert mapping
            stmts.insertMapping.run(runId, 'customer', mraId, localId);

            // Insert phones
            if (phone) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(phone), 'Phone', 1);
            }
            if (mobile) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(mobile), 'Mobile', phone ? 0 : 1);
            }

            // Insert emails
            if (email) {
              stmts.insertCustomerEmail.run(localId, email, 'Primary', 1);
            }

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: mra.id || mra.customerId || 'unknown',
              message,
              timestamp: now(),
            });
          }
        }
      })();

      // Update progress after each batch
      stmts.updateRunProgress.run(
        'running', totalRecords, imported, skipped, errors,
        JSON.stringify(errorLog.slice(-100)),
        runId,
      );
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown fetch error';
    errorLog.push({ record_id: 'fatal', message: message.substring(0, 500), timestamp: now() });
    errors++;
  }

  const finalStatus = cancelFlagsMRA.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[MRA Import] Customers: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

export async function importTicketsMRA(
  db: any,
  client: MraApiClient,
  runId: number,
  stmts: ReturnType<typeof getStatements>,
  tenantSlug: string,
): Promise<void> {
  stmts.markRunRunning.run(now(), runId);

  let totalRecords = 0;
  let imported = 0;
  let skipped = 0;
  let errors = 0;
  const errorLog: ErrorEntry[] = [];

  try {
    const records = await client.fetchTickets() as any[];
    totalRecords = records.length;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsMRA.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const mra of batch) {
          try {
            const mraId = String(mra.id || mra.ticketId || '');
            if (!mraId) {
              errors++;
              errorLog.push({ record_id: 'unknown', message: 'No ticket ID found', timestamp: now() });
              continue;
            }

            // Idempotent check
            const existing = stmts.findMapping.get('ticket', mraId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve local customer_id from MRA customerId
            const mraCustomerId = safeStr(mra.customerId) || safeStr(mra.customer_id);
            let localCustId: number | null = null;
            if (mraCustomerId && mraCustomerId !== '0') {
              const custMap = stmts.findMapping.get('customer', mraCustomerId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }

            // Fallback: walk-in customer
            if (!localCustId) {
              const walkin = db.prepare(
                "SELECT id FROM customers WHERE first_name = 'Walk-in' AND last_name = 'Customer' AND is_deleted = 0 LIMIT 1"
              ).get() as any;
              if (walkin) {
                localCustId = walkin.id;
              } else {
                const r = db.prepare(
                  "INSERT INTO customers (first_name, last_name, type, source, created_at, updated_at) VALUES ('Walk-in', 'Customer', 'individual', 'import', datetime('now'), datetime('now'))"
                ).run();
                localCustId = Number(r.lastInsertRowid);
              }
            }

            const createdAt = toISODate(mra.createdAt) || toISODate(mra.created_at) || now();
            const orderId = safeStr(mra.ticketNumber) || safeStr(mra.ticket_number) || `T-MRA-${mraId}`;

            // Resolve status
            const statusName = safeStr(mra.status);
            const statusId = resolveStatusId(db, statusName, stmts);

            // Compute totals — MRA may not have all fields
            const mraTotal = safeNum(mra.total);
            const mraSubtotal = safeNum(mra.subtotal) || mraTotal;
            const mraDiscount = safeNum(mra.discount);
            const mraTax = safeNum(mra.tax);
            const mraFinal = mraTotal || (mraSubtotal - mraDiscount + mraTax);

            const result = stmts.insertTicket.run(
              orderId,
              localCustId,
              statusId,
              mraSubtotal,
              mraDiscount,
              null, // discount_reason
              mraTax,
              mraFinal,
              'myrepairapp',
              null, // referral_source
              null, // signature
              '[]', // labels
              toISODate(mra.dueDate) || toISODate(mra.due_on),
              createdAt,
              createdAt,
            );

            let localTicketId = Number(result.lastInsertRowid);

            // If OR IGNORE skipped (duplicate order_id), find existing ticket
            if (result.changes === 0) {
              const existingTicket = stmts.findTicketByOrderId.get(orderId) as { id: number } | undefined;
              if (existingTicket) {
                localTicketId = existingTicket.id;
              } else {
                errors++;
                errorLog.push({ record_id: mraId, message: `Ticket ${orderId} insert skipped and not found`, timestamp: now() });
                continue;
              }
            }

            stmts.insertMapping.run(runId, 'ticket', mraId, localTicketId);

            // Import devices (MRA: checkinDevices array)
            const devices = Array.isArray(mra.checkinDevices) ? mra.checkinDevices
              : (Array.isArray(mra.devices) ? mra.devices : []);

            for (const dev of devices) {
              try {
                // Build device name from model/type
                const model = safeStr(dev.model) || '';
                const deviceType = safeStr(dev.deviceType) || safeStr(dev.device_type) || '';
                const fullDeviceName = model || deviceType || 'Unknown Device';

                const devStatusId = resolveStatusId(db, safeStr(dev.status) || statusName, stmts);

                stmts.insertTicketDevice.run(
                  localTicketId,
                  fullDeviceName,
                  deviceType,
                  null, // imei
                  safeStr(dev.serialNumber) || safeStr(dev.serial_number),
                  safeStr(dev.password),
                  safeStr(dev.color),
                  safeStr(dev.carrier) || safeStr(dev.network),
                  devStatusId,
                  safeNum(dev.price),
                  0, // line_discount
                  0, // tax_amount
                  0, // tax_inclusive
                  safeNum(dev.price),
                  0, // warranty
                  0, // warranty_days
                  null, // due_on
                  null, // collected_date
                  null, // device_location
                  safeStr(dev.note) || safeStr(dev.condition),
                  JSON.stringify({}), // pre_conditions
                  JSON.stringify({}), // post_conditions
                  createdAt,
                  createdAt,
                );
              } catch (devErr: unknown) {
                const devMsg = devErr instanceof Error ? devErr.message.substring(0, 200) : 'Device insert error';
                errorLog.push({
                  record_id: `${mraId}/device/${dev.id || 'unknown'}`,
                  message: devMsg,
                  timestamp: now(),
                });
              }
            }

            // Import line items as device parts (MRA: checkinItems array)
            const lineItems = Array.isArray(mra.checkinItems) ? mra.checkinItems : [];
            if (lineItems.length > 0) {
              // Attach to first device if one exists
              const firstDevice = db.prepare(
                'SELECT id FROM ticket_devices WHERE ticket_id = ? ORDER BY id LIMIT 1'
              ).get(localTicketId) as any;
              const targetDeviceId = firstDevice?.id;

              if (targetDeviceId) {
                for (const li of lineItems) {
                  try {
                    const liName = safeStr(li.name) || safeStr(li.description) || '';
                    if (!liName) continue;

                    let invItemId: number | null = null;
                    if (li.inventoryItemId) {
                      const mapped = stmts.findMapping.get('inventory', String(li.inventoryItemId)) as { local_id: number } | undefined;
                      if (mapped) invItemId = mapped.local_id;
                    }
                    if (!invItemId && li.sku) {
                      const bySku = stmts.findInventoryBySku.get(li.sku) as { id: number } | undefined;
                      if (bySku) invItemId = bySku.id;
                    }
                    if (!invItemId) {
                      const byName = stmts.findInventoryByName.get(liName) as any;
                      if (byName) invItemId = byName.id;
                    }
                    // Create placeholder if not found
                    if (!invItemId) {
                      const placeholderSku = li.sku || `MRA-ITEM-${li.inventoryItemId || li.id || Date.now()}`;
                      const insertResult = db.prepare(
                        `INSERT OR IGNORE INTO inventory_items
                          (sku, upc, name, description, item_type, category, manufacturer,
                           cost_price, retail_price, in_stock, reorder_level, stock_warning,
                           tax_inclusive, is_serialized, is_active, created_at, updated_at)
                         VALUES (?, '', ?, '', 'part', 'Imported Parts', '',
                                 ?, ?, 0, 0, 0,
                                 0, 0, 1, ?, ?)`
                      ).run(placeholderSku, liName, safeNum(li.cost), safeNum(li.price), createdAt, createdAt);
                      if (insertResult.changes > 0) {
                        invItemId = Number(insertResult.lastInsertRowid);
                      } else {
                        const existingInv = db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(placeholderSku) as any;
                        if (existingInv) invItemId = existingInv.id;
                      }
                    }
                    if (!invItemId) continue;

                    stmts.insertTicketPart.run(
                      targetDeviceId,
                      invItemId,
                      safeInt(li.quantity, 1),
                      safeNum(li.price),
                      0, // warranty
                      null, // serial
                      createdAt,
                      createdAt,
                    );
                  } catch {
                    // Skip bad line items silently
                  }
                }
              }
            }

            // Import notes (MRA: checkinNotes array — may contain HTML)
            const notes = Array.isArray(mra.checkinNotes) ? mra.checkinNotes
              : (Array.isArray(mra.notes) ? mra.notes : []);

            for (const note of notes) {
              try {
                const rawContent = safeStr(note.note) || safeStr(note.content) || safeStr(note.text) || '';
                if (!rawContent) continue;

                // MRA notes may contain HTML — strip it
                const noteContent = stripHtml(rawContent);
                if (!noteContent) continue;

                const noteType = 'internal';
                const noteCreatedAt = toISODate(note.createdAt) || toISODate(note.created_at) || createdAt;

                stmts.insertTicketNote.run(
                  localTicketId,
                  null, // ticket_device_id
                  noteType,
                  noteContent,
                  0, // is_flagged
                  noteCreatedAt,
                  noteCreatedAt,
                );
              } catch {
                // Silently skip bad notes
              }
            }

            // Add import history entry
            stmts.insertTicketHistory.run(
              localTicketId,
              'import',
              `Imported from MyRepairApp (ticket ${orderId})`,
              createdAt,
            );

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: mra.id || mra.ticketId || 'unknown',
              message,
              timestamp: now(),
            });
          }
        }
      })();

      stmts.updateRunProgress.run(
        'running', totalRecords, imported, skipped, errors,
        JSON.stringify(errorLog.slice(-100)),
        runId,
      );
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown fetch error';
    errorLog.push({ record_id: 'fatal', message: message.substring(0, 500), timestamp: now() });
    errors++;
  }

  const finalStatus = cancelFlagsMRA.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[MRA Import] Tickets: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

export async function importInvoicesMRA(
  db: any,
  client: MraApiClient,
  runId: number,
  stmts: ReturnType<typeof getStatements>,
  tenantSlug: string,
): Promise<void> {
  stmts.markRunRunning.run(now(), runId);

  let totalRecords = 0;
  let imported = 0;
  let skipped = 0;
  let errors = 0;
  const errorLog: ErrorEntry[] = [];

  try {
    const records = await client.fetchInvoices() as any[];
    totalRecords = records.length;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsMRA.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const mra of batch) {
          try {
            const mraId = String(mra.id || mra.invoiceId || '');
            if (!mraId) {
              errors++;
              errorLog.push({ record_id: 'unknown', message: 'No invoice ID found', timestamp: now() });
              continue;
            }

            // Idempotent check
            const existing = stmts.findMapping.get('invoice', mraId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve customer
            const mraCustomerId = safeStr(mra.customerId) || safeStr(mra.customer_id);
            let localCustId: number | null = null;
            if (mraCustomerId && mraCustomerId !== '0') {
              const custMap = stmts.findMapping.get('customer', mraCustomerId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }

            // Resolve linked ticket
            let localTicketId: number | null = null;
            const mraTicketRef = safeStr(mra.ticketId) || safeStr(mra.ticket_id) || safeStr(mra.checkinTicketId);
            if (mraTicketRef) {
              const ticketMap = stmts.findMapping.get('ticket', mraTicketRef) as { local_id: number } | undefined;
              localTicketId = ticketMap?.local_id ?? null;
            }

            // Map status
            const mraStatus = (safeStr(mra.status) || 'draft').toLowerCase();
            let localStatus = 'draft';
            if (mraStatus === 'paid') localStatus = 'paid';
            else if (mraStatus === 'unpaid') localStatus = 'unpaid';
            else if (mraStatus === 'partial' || mraStatus === 'partially paid') localStatus = 'partial';
            else if (mraStatus === 'refunded') localStatus = 'refunded';
            else if (mraStatus === 'void' || mraStatus === 'voided') localStatus = 'void';
            else localStatus = mraStatus;

            const createdAt = toISODate(mra.createdAt) || toISODate(mra.created_at) || now();
            const orderId = safeStr(mra.invoiceNumber) || safeStr(mra.invoice_number) || `INV-MRA-${mraId}`;

            const total = safeNum(mra.total);
            const tax = safeNum(mra.tax);
            const subtotal = safeNum(mra.subtotal) || (total - tax);
            const amountPaid = safeNum(mra.amountPaid) || safeNum(mra.amount_paid) || 0;
            const amountDue = safeNum(mra.amountDue) || safeNum(mra.amount_due) || Math.max(0, total - amountPaid);

            const result = stmts.insertInvoice.run(
              orderId,
              localTicketId,
              localCustId,
              localStatus,
              subtotal,
              safeNum(mra.discount),
              null, // discount_reason
              tax,
              total,
              amountPaid,
              amountDue,
              toISODate(mra.dueDate) || toISODate(mra.due_on),
              safeStr(mra.notes),
              createdAt,
              createdAt,
            );

            const localInvId = Number(result.lastInsertRowid);
            stmts.insertMapping.run(runId, 'invoice', mraId, localInvId);

            // Import line items (MRA: invoiceItems array)
            const invoiceItems = Array.isArray(mra.invoiceItems) ? mra.invoiceItems
              : (Array.isArray(mra.items) ? mra.items : []);

            for (const li of invoiceItems) {
              try {
                // Try to resolve inventory item
                let inventoryItemId: number | null = null;
                const mraInvItemId = safeStr(li.inventoryItemId) || safeStr(li.inventory_item_id);
                if (mraInvItemId) {
                  const mapped = stmts.findMapping.get('inventory', mraInvItemId) as { local_id: number } | undefined;
                  inventoryItemId = mapped?.local_id ?? null;
                }
                if (!inventoryItemId && li.sku) {
                  const inv = stmts.findInventoryBySku.get(li.sku) as { id: number } | undefined;
                  inventoryItemId = inv?.id ?? null;
                }

                const liQty = safeInt(li.quantity, 1);
                const liPrice = safeNum(li.originalPrice) || safeNum(li.price) || safeNum(li.unitPrice);
                const liDiscount = safeNum(li.discount);
                const liTax = safeNum(li.tax);
                const liTotal = safeNum(li.total) || ((liPrice * liQty) - liDiscount + liTax);

                stmts.insertInvoiceLineItem.run(
                  localInvId,
                  inventoryItemId,
                  safeStr(li.name) || safeStr(li.description) || '',
                  liQty,
                  liPrice,
                  liDiscount,
                  liTax,
                  liTotal,
                  createdAt,
                  createdAt,
                );
              } catch {
                // Skip bad line items silently
              }
            }

            // Import payments if present
            const payments = Array.isArray(mra.payments) ? mra.payments : [];
            for (const pmt of payments) {
              try {
                const pmtDate = toISODate(pmt.paymentDate) || toISODate(pmt.created_at) || createdAt;
                stmts.insertPayment.run(
                  localInvId,
                  safeNum(pmt.amount),
                  safeStr(pmt.method) || safeStr(pmt.paymentMethod) || 'Other',
                  safeStr(pmt.type),
                  safeStr(pmt.transactionId) || safeStr(pmt.transaction_id),
                  safeStr(pmt.notes),
                  pmtDate,
                  pmtDate,
                );
              } catch {
                // Skip bad payments
              }
            }

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: mra.id || mra.invoiceId || 'unknown',
              message,
              timestamp: now(),
            });
          }
        }
      })();

      stmts.updateRunProgress.run(
        'running', totalRecords, imported, skipped, errors,
        JSON.stringify(errorLog.slice(-100)),
        runId,
      );
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown fetch error';
    errorLog.push({ record_id: 'fatal', message: message.substring(0, 500), timestamp: now() });
    errors++;
  }

  const finalStatus = cancelFlagsMRA.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[MRA Import] Invoices: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

export async function importInventoryMRA(
  db: any,
  client: MraApiClient,
  runId: number,
  stmts: ReturnType<typeof getStatements>,
  tenantSlug: string,
): Promise<void> {
  stmts.markRunRunning.run(now(), runId);

  let totalRecords = 0;
  let imported = 0;
  let skipped = 0;
  let errors = 0;
  const errorLog: ErrorEntry[] = [];

  try {
    for await (const { records } of client.fetchInventoryPages(50)) {
      if (cancelFlagsMRA.get(tenantSlug)) break;

      totalRecords += records.length;

      for (let i = 0; i < records.length; i += 100) {
        if (cancelFlagsMRA.get(tenantSlug)) break;

        const batch = records.slice(i, i + 100) as any[];
        db.transaction(() => {
          for (const mra of batch) {
            try {
              const mraId = String(mra.id || mra.inventoryItemId || '');
              if (!mraId) {
                errors++;
                errorLog.push({ record_id: 'unknown', message: 'No inventory item ID found', timestamp: now() });
                continue;
              }

              // Idempotent check
              const existing = stmts.findMapping.get('inventory', mraId) as { local_id: number } | undefined;
              if (existing) {
                skipped++;
                continue;
              }

              // Map MRA category to local item_type
              const categoryRaw = safeStr(mra.category);
              const { itemType, localCategory } = mapMraCategory(categoryRaw);

              const createdAt = toISODate(mra.createdAt) || toISODate(mra.created_at) || now();
              const sku = safeStr(mra.sku);
              const name = safeStr(mra.name) || 'Unnamed Item';

              const result = stmts.insertInventoryItem.run(
                sku,
                null, // upc
                name,
                safeStr(mra.description),
                itemType,
                localCategory,
                safeStr(mra.manufacturer),
                safeNum(mra.cost) || safeNum(mra.cost_price),
                safeNum(mra.price) || safeNum(mra.retail_price),
                safeInt(mra.instock) || safeInt(mra.in_stock),
                0, // reorder_level
                0, // stock_warning
                0, // tax_inclusive
                0, // is_serialized
                createdAt,
                createdAt,
              );

              let localId = Number(result.lastInsertRowid);
              // @audit-fixed: previously this branch only patched localId when sku was
              // truthy AND a row was found, otherwise it left `lastInsertRowid` (which is
              // 0 for OR IGNORE skips) wired into the import_id_map row. Subsequent
              // ticket / invoice imports would then look up the mapping, get local_id=0,
              // and silently link to a non-existent inventory row. Throw loudly so the
              // import surfaces the failure rather than corrupting the mapping table.
              if (result.changes === 0) {
                if (sku) {
                  const existingItem = db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(sku) as any;
                  if (existingItem) {
                    localId = existingItem.id;
                  } else {
                    throw new Error(`Inventory insert was skipped (OR IGNORE) for sku=${sku} but no existing row was found — refusing to write a stale mapping`);
                  }
                } else {
                  throw new Error('Inventory insert was skipped (OR IGNORE) and the source row had no sku — refusing to write a stale mapping');
                }
              }
              stmts.insertMapping.run(runId, 'inventory', mraId, localId);

              imported++;
            } catch (err: unknown) {
              errors++;
              const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
              errorLog.push({
                record_id: mra.id || mra.inventoryItemId || 'unknown',
                message,
                timestamp: now(),
              });
            }
          }
        })();

        stmts.updateRunProgress.run(
          'running', totalRecords, imported, skipped, errors,
          JSON.stringify(errorLog.slice(-100)),
          runId,
        );
      }
    }
  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : 'Unknown fetch error';
    errorLog.push({ record_id: 'fatal', message: message.substring(0, 500), timestamp: now() });
    errors++;
  }

  const finalStatus = cancelFlagsMRA.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[MRA Import] Inventory: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

// ---------------------------------------------------------------------------
// Test Connection (exported convenience wrapper)
// ---------------------------------------------------------------------------

export async function testConnectionMRA(
  apiKey: string,
  baseUrl?: string,
): Promise<{ ok: boolean; message: string; totalCustomers?: number }> {
  const client = new MraApiClient(apiKey, baseUrl);
  return client.testConnection();
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

export interface MraImportRequest {
  apiKey: string;
  baseUrl?: string;
  entities: MraEntityType[];
  runIds: Record<MraEntityType, number>;
  tenantSlug?: string;
}

/**
 * Run the full MRA import. Called as a background task (fire-and-forget).
 * Updates import_runs rows with progress as it goes.
 */
export async function runMyRepairAppImport(db: any, request: MraImportRequest): Promise<void> {
  const tenantSlug = request.tenantSlug || 'default';
  cancelFlagsMRA.set(tenantSlug, false);

  // Long-task registry: declare to the cross-platform watchdog. start() is
  // INSIDE the try-block so a throw before completion (e.g. MraApiClient
  // ctor, getStatements) still unwinds through finally → end() and avoids
  // leaking the registration.
  const longTaskRegistry = await import('../utils/longTaskRegistry.js');
  let longTaskActive = false;
  try {
  longTaskRegistry.start({
    kind: 'myrepairapp-import',
    expectedDurationMs: 60 * 60 * 1000,
    details: { tenantSlug, entities: request.entities },
  });
  longTaskActive = true;

  const client = new MraApiClient(request.apiKey, request.baseUrl, tenantSlug);
  const stmts = getStatements(db);

  // Order matters: customers first (referenced by tickets/invoices), then inventory, then tickets, then invoices
  const orderedEntities: MraEntityType[] = ['customers', 'inventory', 'tickets', 'invoices'];
  const toProcess = orderedEntities.filter(e => request.entities.includes(e));

  console.log(`[MRA Import] Starting MyRepairApp import for: ${toProcess.join(', ')}`);

  for (const entity of toProcess) {
    if (cancelFlagsMRA.get(tenantSlug)) {
      // Mark remaining runs as cancelled
      for (const e of toProcess) {
        const runId = request.runIds[e];
        if (runId) {
          const run = db.prepare('SELECT status FROM import_runs WHERE id = ?').get(runId) as { status: string } | undefined;
          if (run && (run.status === 'pending' || run.status === 'running')) {
            stmts.markRunComplete.run('cancelled', now(), 0, 0, 0, 0, '[]', runId);
          }
        }
      }
      break;
    }

    const runId = request.runIds[entity];
    if (!runId) continue;

    // Rate limit: 1000 ms between entity fetches
    await sleep(1000);

    try {
      switch (entity) {
        case 'customers':
          await importCustomersMRA(db, client, runId, stmts, tenantSlug);
          break;
        case 'tickets':
          await importTicketsMRA(db, client, runId, stmts, tenantSlug);
          break;
        case 'invoices':
          await importInvoicesMRA(db, client, runId, stmts, tenantSlug);
          break;
        case 'inventory':
          await importInventoryMRA(db, client, runId, stmts, tenantSlug);
          break;
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Unknown error';
      console.error(`[MRA Import] Fatal error importing ${entity}:`, message);
      stmts.markRunComplete.run(
        'failed', now(), 0, 0, 0, 1,
        JSON.stringify([{ record_id: 'fatal', message: message.substring(0, 500), timestamp: now() }]),
        runId,
      );
    }
  }

  console.log('[MRA Import] MyRepairApp import finished.');
  } finally {
    if (longTaskActive) longTaskRegistry.end();
  }
}
