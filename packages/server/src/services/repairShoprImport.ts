/**
 * RepairShopr API Import Service
 *
 * Pulls customers, tickets, invoices, and inventory from
 * RepairShopr's public API and inserts them into the local SQLite DB.
 *
 * Design:
 *  - Paginated fetching (page-based, 200 ms delay between pages for 180 req/min limit)
 *  - Idempotent via import_id_map lookups before insert
 *  - Progress tracked in import_runs rows (total_records, imported, skipped, errors)
 *  - Errors per-record are logged but never abort the whole run
 *  - Entities processed in dependency order: customers -> inventory -> tickets -> invoices
 *
 * RepairShopr API specifics:
 *  - Auth: API key as query param ?api_key=KEY or Bearer token header
 *  - Base URL: https://SUBDOMAIN.repairshopr.com/api/v1/
 *  - Rate limit: 180 req/min (200ms delay between pages)
 *  - Pagination: ?page=N, response has meta: { total_pages, total_entries, per_page }
 *  - Response envelope: { "customers": [...], "meta": {...} } (plural entity name as key)
 */

import { normalizePhone } from '../utils/phone.js';

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

interface RsMeta {
  total_pages: number;
  total_entries: number;
  per_page: number;
  page: number;
}

interface ErrorEntry {
  record_id: string | number;
  message: string;
  timestamp: string;
}

type RsEntityType = 'customers' | 'tickets' | 'invoices' | 'inventory';

// Per-tenant cancellation flags (keyed by tenant slug; 'default' for single-tenant)
const cancelFlagsRS = new Map<string, boolean>();
export function requestCancelRS(tenantSlug?: string): void {
  cancelFlagsRS.set(tenantSlug || 'default', true);
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

/** Convert a RepairShopr date string to ISO datetime string */
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

// ---------------------------------------------------------------------------
// RepairShopr API Client
// ---------------------------------------------------------------------------

export class RsApiClient {
  private baseUrl: string;
  private apiKey: string;
  readonly tenantSlug: string;

  constructor(apiKey: string, subdomain: string, tenantSlug?: string) {
    this.apiKey = apiKey;
    this.baseUrl = `https://${subdomain}.repairshopr.com/api/v1`;
    this.tenantSlug = tenantSlug || 'default';
  }

  /** Test the API key by fetching page 1 of customers with a small page size. */
  async testConnection(): Promise<{ ok: boolean; message: string; totalCustomers?: number }> {
    try {
      const url = `${this.baseUrl}/customers?page=1`;
      const resp = await fetch(url, {
        headers: { 'Authorization': `Bearer ${this.apiKey}` },
        signal: AbortSignal.timeout(15000),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        return { ok: false, message: `HTTP ${resp.status}: ${text.substring(0, 200)}` };
      }
      const json = await resp.json() as { customers?: unknown[]; meta?: RsMeta };
      if (!json.customers) {
        return { ok: false, message: 'Unexpected response shape: no "customers" key' };
      }
      return {
        ok: true,
        message: 'Connected successfully',
        totalCustomers: json.meta?.total_entries ?? json.customers.length,
      };
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Connection failed';
      return { ok: false, message };
    }
  }

  /**
   * Fetch all pages of an entity. Yields arrays of records per page.
   *
   * RepairShopr response shape: { "<plural_key>": [...], "meta": { total_pages, total_entries, per_page, page } }
   * The plural_key varies by endpoint: customers, tickets, invoices, products
   */
  async *fetchAllPages(
    endpoint: string,
    pluralKey: string,
    extraParams: Record<string, string> = {},
  ): AsyncGenerator<{ records: unknown[]; meta: RsMeta }> {
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      if (cancelFlagsRS.get(this.tenantSlug)) break;

      const params = new URLSearchParams({
        page: String(page),
        ...extraParams,
      });

      const url = `${this.baseUrl}/${endpoint.replace(/^\//, '')}?${params}`;

      const resp = await fetch(url, {
        headers: { 'Authorization': `Bearer ${this.apiKey}` },
        signal: AbortSignal.timeout(60000),
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        throw new Error(`RS API ${endpoint} page ${page}: HTTP ${resp.status} — ${text.substring(0, 300)}`);
      }

      const json = await resp.json() as Record<string, unknown>;

      const records = Array.isArray(json[pluralKey]) ? json[pluralKey] as unknown[] : [];
      const meta: RsMeta = (json.meta as RsMeta) || {
        page,
        per_page: 25,
        total_entries: records.length,
        total_pages: 1,
      };

      yield { records, meta };

      hasMore = page < meta.total_pages && records.length > 0;
      page++;

      if (hasMore) await sleep(200); // 180 req/min rate limit
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

    // Find existing ticket by order_id (for duplicate handling)
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

    // Find or create inventory item by name
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

  // Try partial match for RS statuses that may not match exactly
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
// Entity Importers
// ---------------------------------------------------------------------------

async function importCustomersRS(
  db: any,
  client: RsApiClient,
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

  for await (const { records, meta } of client.fetchAllPages('customers', 'customers')) {
    if (cancelFlagsRS.get(tenantSlug)) break;

    totalRecords = meta.total_entries;

    // Process in batches of 100 within a transaction
    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsRS.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const raw of batch) {
          const rs = raw as Record<string, any>;
          try {
            const rsId = String(rs.id);

            // Idempotent check
            const existing = stmts.findMapping.get('customer', rsId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            const createdAt = toISODate(rs.created_at) || now();
            // RS uses firstname/lastname (no underscore)
            const firstName = safeStr(rs.firstname) || safeStr(rs.first_name) || '';
            const lastName = safeStr(rs.lastname) || safeStr(rs.last_name) || '';
            const email = safeStr(rs.email);
            const phone = safeStr(rs.phone);
            const mobile = safeStr(rs.mobile);
            // RS uses business_name for organization
            const organization = safeStr(rs.business_name);

            // @audit-fixed: previously imported customers as opted-IN by default
            // (`rs.opt_out !== true ? 1 : 0`), which means a missing/undefined opt_out
            // field would silently grant consent. Under US TCPA, the safe default is
            // opt-OUT — operators MUST re-collect consent before sending marketing.
            // Use strict equality on `opt_out === false` (explicit consent) instead.
            const optedIn = rs.opt_out === false ? 1 : 0;
            const result = stmts.insertCustomer.run(
              firstName,
              lastName,
              null, // title -- RS doesn't have a title field
              organization,
              organization ? 'business' : 'individual',
              email,
              phone,
              mobile,
              safeStr(rs.address), // RS: address -> address1
              safeStr(rs.address_2),
              safeStr(rs.city),
              safeStr(rs.state),
              safeStr(rs.zip), // RS: zip -> postcode
              safeStr(rs.country),
              safeStr(rs.referred_by),
              safeStr(rs.notes),
              'repairshopr',
              optedIn, // email_opt_in: default OFF unless RS explicitly says opt_out=false
              optedIn, // sms_opt_in
              createdAt,
              createdAt,
            );

            const localId = Number(result.lastInsertRowid);

            // Generate customer code
            const code = `C-${String(localId).padStart(4, '0')}`;
            stmts.updateCustomerCode.run(code, localId);

            // Insert mapping
            stmts.insertMapping.run(runId, 'customer', rsId, localId);

            // Insert phones
            if (mobile) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(mobile), 'Mobile', 1);
            }
            if (phone) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(phone), 'Phone', mobile ? 0 : 1);
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
              record_id: (rs as any).id || 'unknown',
              message,
              timestamp: now(),
            });
          }
        }
      })();

      // Update progress after each batch
      stmts.updateRunProgress.run(
        'running', totalRecords, imported, skipped, errors,
        JSON.stringify(errorLog.slice(-100)), // Keep last 100 errors
        runId,
      );
    }
  }

  const finalStatus = cancelFlagsRS.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[RS Import] Customers: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importTicketsRS(
  db: any,
  client: RsApiClient,
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

  for await (const { records, meta } of client.fetchAllPages('tickets', 'tickets')) {
    if (cancelFlagsRS.get(tenantSlug)) break;

    totalRecords = meta.total_entries;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsRS.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const raw of batch) {
          const rs = raw as Record<string, any>;
          try {
            const rsId = String(rs.id);

            // Idempotent check
            const existing = stmts.findMapping.get('ticket', rsId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve local customer_id from RS customer_id
            let localCustId: number | null = null;
            const rsCustId = rs.customer_id ? String(rs.customer_id) : null;
            if (rsCustId && rsCustId !== '0') {
              const custMap = stmts.findMapping.get('customer', rsCustId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }

            // Allow tickets without customers (walk-in repairs)
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

            const createdAt = toISODate(rs.created_at) || now();
            // RS: number is the ticket number (like "12345")
            const orderId = safeStr(rs.number) ? `T-RS-${rs.number}` : `T-RS-${rsId}`;

            // RS: status is a string
            const statusName = safeStr(rs.status);
            const statusId = resolveStatusId(db, statusName, stmts);

            // RS ticket doesn't have subtotal/discount/tax at top level typically
            const rsTotal = safeNum(rs.total);

            const result = stmts.insertTicket.run(
              orderId,
              localCustId,
              statusId,
              rsTotal,       // subtotal
              0,             // discount
              null,          // discount_reason
              0,             // total_tax
              rsTotal,       // total
              'repairshopr',
              null,          // referral_source
              null,          // signature
              '[]',          // labels
              toISODate(rs.due_date),
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
                errorLog.push({ record_id: rsId, message: `Ticket ${orderId} insert skipped and not found`, timestamp: now() });
                continue;
              }
            }

            stmts.insertMapping.run(runId, 'ticket', rsId, localTicketId);

            // RS: subject is typically the device/problem description
            // Create a single ticket_device from the subject
            const deviceName = safeStr(rs.subject) || 'Unknown Device';
            const devStatusId = statusId;

            stmts.insertTicketDevice.run(
              localTicketId,
              deviceName,
              null,          // device_type
              null,          // imei
              null,          // serial
              null,          // security_code
              null,          // color
              null,          // network
              devStatusId,
              rsTotal,       // price
              0,             // line_discount
              0,             // tax_amount
              0,             // tax_inclusive
              rsTotal,       // total
              0,             // warranty
              0,             // warranty_days
              toISODate(rs.due_date),
              null,          // collected_date
              null,          // device_location
              safeStr(rs.problem_type),
              '{}',          // pre_conditions
              '{}',          // post_conditions
              createdAt,
              createdAt,
            );

            // Import comments as ticket notes
            // RS: comments is an array of { id, subject, body, tech, hidden, created_at }
            const comments = Array.isArray(rs.comments) ? rs.comments : [];
            for (const comment of comments) {
              try {
                const noteContent = safeStr(comment.body) || safeStr(comment.subject) || '';
                if (!noteContent) continue;

                // RS: hidden comments are internal notes, non-hidden are diagnostic/customer-visible
                const noteType = comment.hidden ? 'internal' : 'diagnostic';
                const noteCreatedAt = toISODate(comment.created_at) || createdAt;

                stmts.insertTicketNote.run(
                  localTicketId,
                  null, // ticket_device_id
                  noteType,
                  noteContent,
                  0, // is_flagged
                  noteCreatedAt,
                  noteCreatedAt,
                );
              } catch (_noteErr) {
                // Silently skip bad notes
              }
            }

            // Import ticket history if available
            stmts.insertTicketHistory.run(
              localTicketId,
              'import',
              `Imported from RepairShopr (ticket #${rs.number || rsId})`,
              createdAt,
            );

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: (rs as any).id || 'unknown',
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

  const finalStatus = cancelFlagsRS.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[RS Import] Tickets: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importInvoicesRS(
  db: any,
  client: RsApiClient,
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

  for await (const { records, meta } of client.fetchAllPages('invoices', 'invoices')) {
    if (cancelFlagsRS.get(tenantSlug)) break;

    totalRecords = meta.total_entries;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsRS.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const raw of batch) {
          const rs = raw as Record<string, any>;
          try {
            const rsId = String(rs.id);

            const existing = stmts.findMapping.get('invoice', rsId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve customer
            const rsCustId = rs.customer_id ? String(rs.customer_id) : null;
            let localCustId: number | null = null;
            if (rsCustId && rsCustId !== '0') {
              const custMap = stmts.findMapping.get('customer', rsCustId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }

            // Resolve linked ticket
            let localTicketId: number | null = null;
            if (rs.ticket_id) {
              const ticketMap = stmts.findMapping.get('ticket', String(rs.ticket_id)) as { local_id: number } | undefined;
              localTicketId = ticketMap?.local_id ?? null;
            }

            // Map RS status to local
            // RS uses "paid" boolean or status field
            let localStatus = 'draft';
            if (rs.paid === true || rs.status === 'paid') {
              localStatus = 'paid';
            } else if (rs.status === 'partial') {
              localStatus = 'partial';
            } else if (rs.status === 'unpaid' || rs.paid === false) {
              localStatus = 'unpaid';
            } else if (rs.status === 'refunded') {
              localStatus = 'refunded';
            } else if (rs.status) {
              localStatus = String(rs.status).toLowerCase();
            }

            const createdAt = toISODate(rs.created_at) || now();
            const orderId = safeStr(rs.number) ? `INV-RS-${rs.number}` : `INV-RS-${rsId}`;

            const total = safeNum(rs.total);
            const amountPaid = safeNum(rs.amount_paid) || (localStatus === 'paid' ? total : 0);
            const amountDue = safeNum(rs.due) || Math.max(0, total - amountPaid);

            const result = stmts.insertInvoice.run(
              orderId,
              localTicketId,
              localCustId,
              localStatus,
              safeNum(rs.subtotal) || total,
              safeNum(rs.discount),
              null, // discount_reason
              safeNum(rs.tax),
              total,
              amountPaid,
              amountDue,
              toISODate(rs.due_date),
              safeStr(rs.note),
              createdAt,
              createdAt,
            );

            const localInvId = Number(result.lastInsertRowid);
            stmts.insertMapping.run(runId, 'invoice', rsId, localInvId);

            // Import line items
            // RS: line_items is an array of { id, name, description, quantity, price, cost, product_id, ... }
            const lineItems = Array.isArray(rs.line_items) ? rs.line_items : [];
            for (const li of lineItems) {
              try {
                // Try to find a matching inventory item by product_id mapping
                let inventoryItemId: number | null = null;
                if (li.product_id) {
                  const mapped = stmts.findMapping.get('inventory', String(li.product_id)) as { local_id: number } | undefined;
                  inventoryItemId = mapped?.local_id ?? null;
                }
                if (!inventoryItemId && li.sku) {
                  const inv = stmts.findInventoryBySku.get(li.sku) as { id: number } | undefined;
                  inventoryItemId = inv?.id ?? null;
                }

                const liTotal = safeNum(li.price) * safeInt(li.quantity, 1);

                stmts.insertInvoiceLineItem.run(
                  localInvId,
                  inventoryItemId,
                  safeStr(li.name) || safeStr(li.description) || '',
                  safeInt(li.quantity, 1),
                  safeNum(li.price),
                  safeNum(li.discount),
                  safeNum(li.tax),
                  liTotal,
                  createdAt,
                  createdAt,
                );
              } catch (_liErr) {
                // Skip bad line items silently
              }
            }

            // Import payments if available
            // RS: payments may be in a separate field or embedded
            const payments = Array.isArray(rs.payments) ? rs.payments : [];
            for (const pmt of payments) {
              try {
                const pmtDate = toISODate(pmt.created_at) || toISODate(pmt.date) || createdAt;
                stmts.insertPayment.run(
                  localInvId,
                  safeNum(pmt.amount),
                  safeStr(pmt.payment_method) || safeStr(pmt.method) || 'Other',
                  safeStr(pmt.payment_method),
                  safeStr(pmt.transaction_id),
                  safeStr(pmt.notes),
                  pmtDate,
                  pmtDate,
                );
              } catch (_pmtErr) {
                // Skip bad payments
              }
            }

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: (rs as any).id || 'unknown',
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

  const finalStatus = cancelFlagsRS.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[RS Import] Invoices: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importInventoryRS(
  db: any,
  client: RsApiClient,
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

  // RS: products endpoint returns { "products": [...], "meta": {...} }
  for await (const { records, meta } of client.fetchAllPages('products', 'products')) {
    if (cancelFlagsRS.get(tenantSlug)) break;

    totalRecords = meta.total_entries;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlagsRS.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const raw of batch) {
          const rs = raw as Record<string, any>;
          try {
            const rsId = String(rs.id);

            const existing = stmts.findMapping.get('inventory', rsId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Determine item_type: RS products are generic, try to infer
            let itemType: 'product' | 'part' | 'service' = 'product';
            const category = (safeStr(rs.product_category) || '').toLowerCase();
            if (category.includes('service') || category.includes('repair') || category.includes('labor')) {
              itemType = 'service';
            } else if (category.includes('part')) {
              itemType = 'part';
            }

            const createdAt = toISODate(rs.created_at) || now();
            const sku = safeStr(rs.sku) || safeStr(rs.id ? `RS-${rs.id}` : null);
            const name = safeStr(rs.name) || 'Unnamed Item';

            const result = stmts.insertInventoryItem.run(
              sku,
              safeStr(rs.upc_code),
              name,
              safeStr(rs.description),
              itemType,
              safeStr(rs.product_category),     // RS: product_category -> category
              safeStr(rs.manufacturer),
              safeNum(rs.price_cost),            // RS: price_cost -> cost_price
              safeNum(rs.price_retail),           // RS: price_retail -> retail_price
              safeInt(rs.quantity),               // RS: quantity -> in_stock
              safeInt(rs.reorder_point),          // reorder_level
              safeInt(rs.reorder_point),          // stock_warning (use same as reorder)
              0,                                  // tax_inclusive
              rs.serialized ? 1 : 0,             // is_serialized
              createdAt,
              createdAt,
            );

            let localId = Number(result.lastInsertRowid);
            // @audit-fixed: same `OR IGNORE` mapping bug as the MRA importer — fail loud
            // if we cannot resolve the existing row, otherwise we corrupt import_id_map
            // by mapping rsId → 0 / stale rowid.
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
            stmts.insertMapping.run(runId, 'inventory', rsId, localId);

            imported++;
          } catch (err: unknown) {
            errors++;
            const message = err instanceof Error ? err.message.substring(0, 300) : 'Unknown error';
            errorLog.push({
              record_id: (rs as any).id || 'unknown',
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

  const finalStatus = cancelFlagsRS.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[RS Import] Inventory: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

export interface RsImportRequest {
  apiKey: string;
  subdomain: string;
  entities: RsEntityType[];
  runIds: Record<RsEntityType, number>;
  tenantSlug?: string;
}

/**
 * Run the full import. Called as a background task (fire-and-forget).
 * Updates import_runs rows with progress as it goes.
 */
export async function runRepairShoprImport(db: any, request: RsImportRequest): Promise<void> {
  const tenantSlug = request.tenantSlug || 'default';
  cancelFlagsRS.set(tenantSlug, false);

  // Long-task registry: declare to the cross-platform watchdog that this is a
  // legitimate long operation, so the watchdog extends its wedge-failure
  // grace period instead of restarting the server mid-import. start() is
  // INSIDE the try-block so that any throw between start() and end() always
  // unwinds through the finally clause and clears the registry — otherwise
  // a thrown getStatements() or RsApiClient ctor would leak the long-task
  // declaration and the watchdog would refuse to restart for 90 minutes.
  const longTaskRegistry = await import('../utils/longTaskRegistry.js');
  let longTaskActive = false;
  try {
  longTaskRegistry.start({
    kind: 'repairshopr-import',
    expectedDurationMs: 60 * 60 * 1000,
    details: { tenantSlug, entities: request.entities },
  });
  longTaskActive = true;

  const client = new RsApiClient(request.apiKey, request.subdomain, tenantSlug);
  const stmts = getStatements(db);

  // Order matters: customers first (referenced by tickets/invoices), then inventory, then tickets, then invoices
  const orderedEntities: RsEntityType[] = ['customers', 'inventory', 'tickets', 'invoices'];
  const toProcess = orderedEntities.filter(e => request.entities.includes(e));

  console.log(`[RS Import] Starting RepairShopr import for: ${toProcess.join(', ')}`);

  for (const entity of toProcess) {
    if (cancelFlagsRS.get(tenantSlug)) {
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

    try {
      switch (entity) {
        case 'customers':
          await importCustomersRS(db, client, runId, stmts, tenantSlug);
          break;
        case 'tickets':
          await importTicketsRS(db, client, runId, stmts, tenantSlug);
          break;
        case 'invoices':
          await importInvoicesRS(db, client, runId, stmts, tenantSlug);
          break;
        case 'inventory':
          await importInventoryRS(db, client, runId, stmts, tenantSlug);
          break;
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message.substring(0, 500) : 'Unknown error';
      console.error(`[RS Import] Fatal error importing ${entity}:`, message);
      stmts.markRunComplete.run(
        'failed', now(), 0, 0, 0, 1,
        JSON.stringify([{ record_id: 'fatal', message, timestamp: now() }]),
        runId,
      );
    }
  }

  console.log('[RS Import] RepairShopr import finished.');
  } finally {
    // Always clear the long-task registration so the watchdog reverts to
    // the default wedge threshold once the import is done — even on throw.
    // longTaskActive guards against the (unlikely) case that start() itself
    // threw before assigning, in which case there's no registration to clear.
    if (longTaskActive) longTaskRegistry.end();
  }
}

/**
 * Test the API connection without importing anything.
 */
export async function testConnectionRS(
  apiKey: string,
  subdomain: string,
): Promise<{ ok: boolean; message: string; totalCustomers?: number }> {
  const client = new RsApiClient(apiKey, subdomain);
  return client.testConnection();
}
