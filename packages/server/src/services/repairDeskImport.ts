/**
 * RepairDesk API Import Service
 *
 * Pulls customers, tickets, invoices, inventory, and SMS from
 * RepairDesk's public API and inserts them into the local SQLite DB.
 *
 * Design:
 *  - Paginated fetching (pagesize=1000, 200 ms delay between pages)
 *  - Idempotent via import_id_map lookups before insert
 *  - Progress tracked in import_runs rows (total_records, imported, skipped, errors)
 *  - Errors per-record are logged but never abort the whole run
 *  - Entities processed in dependency order: customers → tickets → invoices
 */

import { normalizePhone } from '../utils/phone.js';
import { createLogger } from '../utils/logger.js';
import { buildJobId, resumeJobState } from './importJobState.js';
// Per-tenant config is read from store_config DB, not from env vars
//
// TENANT SCOPING (SEC-T1): Every public function in this module accepts
// `db` as the first parameter. Callers (routes, jobs) are responsible for
// obtaining the correct tenant DB handle via `getTenantDb(tenantSlug)` in the
// multi-tenant bootstrap and passing it through. This service NEVER imports
// from `db/connection.js` directly — all state lives on the caller-provided
// handle. Do not change that contract.

const log = createLogger('repairDeskImport');

// SEC-M3 / Q1+Q2: Strict whitelists of table/trigger names allowed in dynamic
// SQL. These are the ONLY identifiers permitted in any interpolated DDL/DML
// statement in this file. Adding a new table or trigger to the wipe logic MUST
// also add the name to the corresponding whitelist — there is no regex fallback.
const ALLOWED_WIPE_TABLES: ReadonlySet<string> = new Set([
  // Import tracking
  'import_id_map', 'import_runs',
  // SMS + comms
  'sms_messages', 'sms_conversation_flags', 'sms_conversation_reads', 'call_logs', 'email_messages',
  // Payments + invoices
  'gift_card_transactions', 'gift_cards', 'store_credit_transactions', 'store_credits', 'refunds',
  'payments', 'invoice_line_items', 'invoices',
  // Tickets + related
  'customer_feedback',
  'parts_order_queue_tickets', 'parts_order_queue',
  'ticket_device_parts', 'ticket_photos', 'ticket_notes', 'ticket_history',
  'ticket_checklists', 'ticket_devices', 'tickets',
  // Customers
  'portal_sessions', 'portal_verification_codes',
  'customer_phones', 'customer_emails', 'customer_assets', 'customers',
  // Inventory
  'stock_movements', 'inventory_serials', 'inventory_group_prices', 'inventory_device_compatibility', 'inventory_items',
  'purchase_order_items', 'purchase_orders', 'suppliers',
  // Leads + estimates
  'lead_devices', 'appointments', 'leads',
  'estimate_line_items', 'estimates',
  // POS
  'pos_transactions', 'cash_register',
  // RMA + trade-ins + loaners
  'rma_items', 'rma_requests', 'trade_ins',
  'loaner_history', 'loaner_devices',
  // Employee + expenses
  'clock_entries', 'commissions', 'expenses',
  // Notifications + misc
  'notifications', 'device_otps',
  'custom_field_values',
  // System / settings resets (selectiveWipe)
  'store_config', 'sessions', 'users', 'ticket_statuses', 'tax_classes',
  'payment_methods', 'sms_templates', 'notification_templates', 'checklist_templates',
  // FTS shadow tables
  'customers_fts', 'tickets_fts', 'device_models_fts', 'supplier_catalog_fts',
]);

const ALLOWED_WIPE_TRIGGERS: ReadonlySet<string> = new Set([
  'customers_fts_insert', 'customers_fts_delete', 'customers_fts_update',
  'tickets_fts_ai', 'tickets_fts_au', 'tickets_fts_ad',
  'tickets_fts_device_ai', 'tickets_fts_device_au', 'tickets_fts_device_ad',
  'tickets_fts_note_ai', 'tickets_fts_note_au', 'tickets_fts_note_ad',
]);

// Q1 fix: previously the regex had inverted logic (`!ALLOWED.has(name) && !/.../.test(name)`)
// which permitted any `^[a-z_]+$` string even if not in the whitelist. Now we
// reject anything not explicitly whitelisted, full stop.
function assertValidTableName(name: string): void {
  if (typeof name !== 'string' || !ALLOWED_WIPE_TABLES.has(name)) {
    throw new Error(`Invalid table name (not in whitelist): ${String(name)}`);
  }
}

// Q2 fix: same strict whitelist applied to DROP TRIGGER identifiers.
function assertValidTriggerName(name: string): void {
  if (typeof name !== 'string' || !ALLOWED_WIPE_TRIGGERS.has(name)) {
    throw new Error(`Invalid trigger name (not in whitelist): ${String(name)}`);
  }
}

// Q5 helper: escape LIKE wildcards on user-supplied values. Combined with
// `ESCAPE '\'` on the SQL side this prevents a pattern like "__" or "%abc%"
// from becoming a wildcard search.
function escapeLikeLiteral(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/%/g, '\\%').replace(/_/g, '\\_');
}

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

interface RdPagination {
  page: number;
  per_page: number;
  total_records: number;
  total_pages: number;
  next_page_exist: number;
  next_page: number;
}

interface RdResponse<T = any> {
  success: boolean;
  statusCode: number;
  message: string;
  data: T[];
  pagination: RdPagination;
}

interface ErrorEntry {
  record_id: string | number;
  message: string;
  timestamp: string;
}

type EntityType = 'customers' | 'tickets' | 'invoices' | 'inventory' | 'sms';

// Per-tenant cancellation flags (keyed by tenant slug; 'default' for single-tenant)
const cancelFlags = new Map<string, boolean>();
export function requestCancel(tenantSlug?: string): void {
  cancelFlags.set(tenantSlug || 'default', true);
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

function safeStr(val: any): string | null {
  if (val === undefined || val === null || val === '') return null;
  return String(val);
}

function safeNum(val: any, fallback: number = 0): number {
  if (val === undefined || val === null || val === '') return fallback;
  // Strip currency symbols and commas: "$1,208.87" → "1208.87"
  const cleaned = typeof val === 'string' ? val.replace(/[$,]/g, '').trim() : val;
  const n = Number(cleaned);
  return Number.isFinite(n) ? n : fallback;
}

function safeInt(val: any, fallback: number = 0): number {
  return Math.round(safeNum(val, fallback));
}

/** Convert a RepairDesk date string or unix timestamp to ISO datetime string */
function toISODate(val: any): string | null {
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
// RepairDesk API Client
// ---------------------------------------------------------------------------

class RdApiClient {
  private baseUrl: string;
  private apiKey: string;
  readonly tenantSlug: string;

  constructor(apiKey: string, baseUrl?: string, tenantSlug?: string) {
    this.apiKey = apiKey;
    this.baseUrl = (baseUrl || 'https://api.repairdesk.co/api/web/v1').replace(/\/$/, '');
    this.tenantSlug = tenantSlug || 'default';
  }

  /** Test the API key by fetching page 1 of customers with pagesize=1. */
  async testConnection(): Promise<{ ok: boolean; message: string; totalCustomers?: number }> {
    try {
      const url = `${this.baseUrl}/customers?page=1&pagesize=1`;
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(15000),
        headers: { 'Authorization': `Bearer ${this.apiKey}` },
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        return { ok: false, message: `HTTP ${resp.status}: ${text.substring(0, 200)}` };
      }
      const json = await resp.json() as any;
      if (!json.success) {
        return { ok: false, message: json.message || 'API returned success=false' };
      }
      // RD nests pagination inside data, not at top level
      const pagination = json.data?.pagination || json.pagination || {};
      return {
        ok: true,
        message: 'Connected successfully',
        totalCustomers: pagination.total_records ?? 0,
      };
    } catch (err: any) {
      return { ok: false, message: err.message || 'Connection failed' };
    }
  }

  /** Fetch all pages of an entity. Yields arrays of records per page. */
  async *fetchAllPages(
    endpoint: string,
    pageSize: number = 1000,
    extraParams: Record<string, string> = {},
  ): AsyncGenerator<{ records: any[]; pagination: RdPagination }> {
    let page = 1;
    let hasMore = true;

    while (hasMore) {
      if (cancelFlags.get(this.tenantSlug)) break;

      const params = new URLSearchParams({
        page: String(page),
        ...extraParams,
      });

      // SMS endpoint uses per_page instead of pagesize, and max 100
      if (endpoint.includes('sms-inbox')) {
        params.set('per_page', String(Math.min(pageSize, 100)));
      } else {
        params.set('pagesize', String(pageSize));
      }

      const url = `${this.baseUrl}/${endpoint.replace(/^\//, '')}?${params}`;

      const resp = await fetch(url, {
        signal: AbortSignal.timeout(60000),
        headers: { 'Authorization': `Bearer ${this.apiKey}` },
      });
      if (!resp.ok) {
        const text = await resp.text().catch(() => '');
        throw new Error(`RD API ${endpoint} page ${page}: HTTP ${resp.status} — ${text.substring(0, 300)}`);
      }

      const json = await resp.json() as RdResponse;
      if (!json.success) {
        throw new Error(`RD API ${endpoint} page ${page}: ${json.message}`);
      }

      // RD API nests data: { success, data: { customerData: [...], pagination: {...} } }
      // or { success, data: { ticketData: [...], ... } }
      // Find the array in data — it's the first array-valued key
      const dataObj = json.data || {};
      let records: any[] = [];
      if (Array.isArray(dataObj)) {
        records = dataObj;
      } else if (typeof dataObj === 'object') {
        for (const val of Object.values(dataObj)) {
          if (Array.isArray(val)) { records = val; break; }
        }
      }
      const pagination: RdPagination = (dataObj as any).pagination || json.pagination || {
        page,
        per_page: pageSize,
        total_records: records.length,
        total_pages: 1,
        next_page_exist: 0,
        next_page: 0,
      };

      yield { records, pagination };

      hasMore = pagination.next_page_exist === 1 && records.length > 0;
      page = pagination.next_page || page + 1;

      if (hasMore) await sleep(200);
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

    // sms
    insertSms: db.prepare(
      `INSERT INTO sms_messages
        (from_number, to_number, conv_phone, message, status, direction, error, provider, entity_type, entity_id, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, 'repairdesk', ?, ?, ?, ?)`
    ),
  };
}

// ---------------------------------------------------------------------------
// Status name → local status ID mapping with caching
// ---------------------------------------------------------------------------

const statusCache = new Map<string, number>();

function resolveStatusId(db: any, statusName: string | null | undefined, stmts: ReturnType<typeof getStatements>): number {
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

  // Try partial match for RD statuses that may not match exactly
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

async function importCustomers(
  db: any,
  client: RdApiClient,
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

  for await (const { records, pagination } of client.fetchAllPages('customers', 1000)) {
    if (cancelFlags.get(tenantSlug)) break;

    totalRecords = pagination.total_records;

    // Process in batches of 100 within a transaction
    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlags.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const rd of batch) {
          try {
            const rdId = String(rd.cid || rd.id);

            // Idempotent check
            const existing = stmts.findMapping.get('customer', rdId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            const createdAt = toISODate(rd.created_on) || now();
            const firstName = safeStr(rd.first_name) || '';
            const lastName = safeStr(rd.last_name) || '';
            const email = safeStr(rd.email);
            const mobile = safeStr(rd.mobile);
            const phone = safeStr(rd.phone);
            const organization = safeStr(rd.orgonization); // RD typo

            const result = stmts.insertCustomer.run(
              firstName,
              lastName,
              safeStr(rd.title),
              organization,
              rd.type === 'business' ? 'business' : 'individual',
              email,
              phone,
              mobile,
              safeStr(rd.address1),
              safeStr(rd.address2),
              safeStr(rd.city),
              safeStr(rd.state),
              safeStr(rd.postcode),
              safeStr(rd.country),
              safeStr(rd.refered_by), // RD typo
              safeStr(rd.comments),
              'repairdesk',
              rd.email_opt_in ? 1 : 0,
              rd.sms_opt_in ? 1 : 0,
              createdAt,
              createdAt,
            );

            const localId = Number(result.lastInsertRowid);

            // Generate customer code
            const code = `C-${String(localId).padStart(4, '0')}`;
            stmts.updateCustomerCode.run(code, localId);

            // Insert mapping
            stmts.insertMapping.run(runId, 'customer', rdId, localId);

            // Insert phones
            if (mobile) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(mobile), 'Mobile', 1);
            }
            if (phone) {
              stmts.insertCustomerPhone.run(localId, normalizePhone(phone), 'Phone', mobile ? 0 : 1);
            }
            // Additional phones from arrays
            if (Array.isArray(rd.phones)) {
              for (const p of rd.phones) {
                const pNum = typeof p === 'string' ? p : p?.number || p?.phone;
                if (pNum && pNum !== phone) {
                  stmts.insertCustomerPhone.run(localId, normalizePhone(pNum), 'Other', 0);
                }
              }
            }
            if (Array.isArray(rd.mobiles)) {
              for (const m of rd.mobiles) {
                const mNum = typeof m === 'string' ? m : m?.number || m?.mobile;
                if (mNum && mNum !== mobile) {
                  stmts.insertCustomerPhone.run(localId, normalizePhone(mNum), 'Mobile', 0);
                }
              }
            }

            // Insert emails
            if (email) {
              stmts.insertCustomerEmail.run(localId, email, 'Primary', 1);
            }
            if (Array.isArray(rd.emails)) {
              for (const e of rd.emails) {
                const eAddr = typeof e === 'string' ? e : e?.email || e?.address;
                if (eAddr && eAddr !== email) {
                  stmts.insertCustomerEmail.run(localId, eAddr, 'Other', 0);
                }
              }
            }

            imported++;
          } catch (err: any) {
            errors++;
            errorLog.push({
              record_id: rd.cid || rd.id || 'unknown',
              message: err.message?.substring(0, 300) || 'Unknown error',
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

  const finalStatus = cancelFlags.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[Import] Customers: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importTickets(
  db: any,
  client: RdApiClient,
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

  for await (const { records, pagination } of client.fetchAllPages('tickets', 1000)) {
    if (cancelFlags.get(tenantSlug)) break;

    totalRecords = pagination.total_records;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlags.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const rdRaw of batch) {
          const rd = rdRaw.summary || rdRaw;
          const rdDevices = rdRaw.devices || rd.devices || [];
          const rdId = String(rd.id);
          try {
            // Idempotent check
            const existing = stmts.findMapping.get('ticket', rdId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve local customer_id from RD customer object or id
            const rdCust = rd.customer || rd.customer_id;
            let rdCustId: string | null = null;
            if (typeof rdCust === 'number' || typeof rdCust === 'string') {
              rdCustId = String(rdCust);
            } else if (rdCust && typeof rdCust === 'object') {
              rdCustId = String(rdCust.cid || rdCust.id || rdCust.customer_id || '');
            }

            let localCustId: number | null = null;
            if (rdCustId && rdCustId !== '' && rdCustId !== '0') {
              const custMap = stmts.findMapping.get('customer', rdCustId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }

            // Allow tickets without customers (walk-in repairs)
            if (!localCustId) {
              // Try to find customer by name/phone if available in RD data
              if (rdCust && typeof rdCust === 'object') {
                const name = (rdCust.first_name || '') + ' ' + (rdCust.last_name || '');
                const phone = rdCust.mobile || rdCust.phone || '';
                if (phone) {
                  // Q5 fix: only keep digits (so %/_ can't reach here), then
                  // ALSO escape LIKE wildcards defensively and use ESCAPE '\'
                  // so any hypothetical bypass still cannot become a wildcard.
                  const digits = String(phone).replace(/\D/g, '').slice(-10);
                  if (digits.length > 0) {
                    const likeNeedle = '%' + escapeLikeLiteral(digits) + '%';
                    const found = db.prepare(
                      "SELECT id FROM customers WHERE " +
                      "REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(mobile,' ',''),'-',''),'(',''),')',''),'+','') LIKE ? ESCAPE '\\' " +
                      "OR REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(phone,' ',''),'-',''),'(',''),')',''),'+','') LIKE ? ESCAPE '\\' " +
                      "LIMIT 1"
                    ).get(likeNeedle, likeNeedle) as any;
                    if (found) localCustId = found.id;
                  }
                }
              }
              // Still no customer — use or create a "Walk-in" placeholder
              if (!localCustId) {
                const walkin = db.prepare("SELECT id FROM customers WHERE first_name = 'Walk-in' AND last_name = 'Customer' AND is_deleted = 0 LIMIT 1").get() as any;
                if (walkin) {
                  localCustId = walkin.id;
                } else {
                  const r = db.prepare("INSERT INTO customers (first_name, last_name, type, source, created_at, updated_at) VALUES ('Walk-in', 'Customer', 'individual', 'import', datetime('now'), datetime('now'))").run();
                  localCustId = Number(r.lastInsertRowid);
                }
              }
            }

            const createdAt = toISODate(rd.created_date) || now();
            const orderId = safeStr(rd.order_id) || `T-RD-${rdId}`;

            // Resolve status — RD stores status per-device as { name: "..." }
            let statusName: string | null = null;
            if (rdDevices.length > 0) {
              const devStatus = rdDevices[0].status;
              statusName = typeof devStatus === 'string' ? devStatus : devStatus?.name || null;
            }
            // Fallback: ticket-level status from RD (not always present)
            if (!statusName && rd.status) {
              statusName = typeof rd.status === 'string' ? rd.status : rd.status?.name;
            }
            const statusId = resolveStatusId(db, statusName, stmts);

            // Compute subtotal from devices if not on summary
            const rdTotal = safeNum(rd.total);
            const rdSubtotal = safeNum(rd.subtotal) || rdDevices.reduce((s: number, d: any) => s + safeNum(d.price), 0) || rdTotal;
            const rdDiscount = safeNum(rd.discount) || safeNum(rd.overall_discount_applied);
            const rdTax = safeNum(rd.total_tax) || safeNum(rd.gst);
            const rdTotalFinal = rdTotal || (rdSubtotal - rdDiscount + rdTax);

            const result = stmts.insertTicket.run(
              orderId,
              localCustId,
              statusId,
              rdSubtotal,
              rdDiscount,
              safeStr(rd.discount_reason),
              rdTax,
              rdTotalFinal,
              'repairdesk',
              safeStr(rd.how_did_u_find_us),
              safeStr(rd.signature),
              JSON.stringify(rd.ticketLabels || []),
              toISODate(rd.due_on),
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
                errorLog.push({ record_id: rdId, message: `Ticket ${orderId} insert skipped and not found`, timestamp: now() });
                continue;
              }
            }

            stmts.insertMapping.run(runId, 'ticket', rdId, localTicketId);

            // Import devices
            for (const dev of rdDevices) {
              try {
                const devStatusName = typeof dev.status === 'string' ? dev.status : dev.status?.name;
                const devStatusId = resolveStatusId(db, devStatusName, stmts);
                const devCreatedAt = createdAt;

                // Device name: prefer device.name (model), fallback to repairProdItems name
                const deviceModelName = safeStr(dev.device?.name) || safeStr(dev.name) || '';
                const firstRepairItem = dev.repairProdItems?.[0];
                const serviceName = firstRepairItem?.name ? (safeStr(firstRepairItem!.name) ?? '').trim() : '';
                const fullDeviceName = serviceName && deviceModelName
                  ? `${deviceModelName} - ${serviceName}`
                  : deviceModelName || serviceName || 'Unknown Device';

                const devInsertResult = stmts.insertTicketDevice.run(
                  localTicketId,
                  fullDeviceName,
                  safeStr(dev.device?.device_type) || safeStr(dev.deviceCategory) || safeStr(dev.task_type),
                  safeStr(dev.imei),
                  safeStr(dev.serial),
                  safeStr(dev.security_code),
                  safeStr(dev.color),
                  safeStr(dev.network),
                  devStatusId,
                  safeNum(dev.price),
                  safeNum(dev.line_discount),
                  safeNum(dev.gst),
                  dev.tax_inclusive ? 1 : 0,
                  safeNum(dev.total),
                  dev.warranty ? 1 : 0,
                  safeInt(dev.warranty_timeframe),
                  toISODate(dev.due_on),
                  toISODate(dev.collected_date),
                  safeStr(dev.device_location),
                  safeStr(dev.additional_notes),
                  JSON.stringify(dev.PreConditions || {}),
                  JSON.stringify(dev.PostConditions || {}),
                  devCreatedAt,
                  devCreatedAt,
                );
                // Import parts for this device
                const localDeviceId = Number(devInsertResult.lastInsertRowid);
                const rdParts = [...(Array.isArray(dev.parts) ? dev.parts : []), ...(Array.isArray(dev.suplied) ? dev.suplied : [])];
                for (const part of rdParts) {
                  try {
                    const partName = safeStr(part.name) || '';
                    if (!partName) continue;
                    const partPrice = safeNum(part.price);
                    const partQty = safeInt(part.quantity) || 1;
                    const partSerial = safeStr(part.serial || part.serials);
                    const partWarranty = part.warranty ? 1 : 0;

                    // Try to find matching inventory item
                    let invItemId: number | null = null;
                    if (part.product_id) {
                      const mapped = db.prepare('SELECT local_id FROM import_id_map WHERE entity_type = ? AND rd_id = ?').get('inventory', String(part.product_id)) as any;
                      if (mapped) invItemId = mapped.local_id;
                    }
                    if (!invItemId) {
                      const byName = stmts.findInventoryByName.get(partName) as any;
                      if (byName) invItemId = byName.id;
                    }
                    // If still no match, create a placeholder inventory item
                    if (!invItemId) {
                      const placeholderSku = `RD-PART-${part.product_id || Date.now()}`;
                      const result = db.prepare(
                        `INSERT OR IGNORE INTO inventory_items
                          (sku, upc, name, description, item_type, category, manufacturer,
                           cost_price, retail_price, in_stock, reorder_level, stock_warning,
                           tax_inclusive, is_serialized, is_active, created_at, updated_at)
                         VALUES (?, '', ?, '', 'part', 'Imported Parts', '',
                                 ?, ?, 0, 0, 0,
                                 0, 0, 1, ?, ?)`
                      ).run(placeholderSku, partName, partPrice, partPrice, devCreatedAt, devCreatedAt);
                      if (result.changes > 0) {
                        invItemId = Number(result.lastInsertRowid);
                      } else {
                        const existing = db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(placeholderSku) as any;
                        if (existing) invItemId = existing.id;
                      }
                    }

                    if (!invItemId) continue; // still no item, skip

                    stmts.insertTicketPart.run(
                      localDeviceId || 0,
                      invItemId,
                      partQty,
                      partPrice,
                      partWarranty,
                      partSerial,
                      devCreatedAt,
                      devCreatedAt,
                    );
                  } catch (_partErr) {
                    // Skip bad parts silently
                  }
                }

              } catch (devErr: any) {
                // Log device error but don't fail the whole ticket
                errorLog.push({
                  record_id: `${rdId}/device/${dev.id || 'unknown'}`,
                  message: devErr.message?.substring(0, 200) || 'Device insert error',
                  timestamp: now(),
                });
              }
            }

            // Import accessories (ticket-level parts not attached to a device in RD)
            const accessories = Array.isArray(rdRaw.accessory) ? rdRaw.accessory : (Array.isArray(rd.accessory) ? rd.accessory : []);
            if (accessories.length > 0) {
              // Find the first local device for this ticket to attach accessories to
              const firstDevice = db.prepare('SELECT id FROM ticket_devices WHERE ticket_id = ? ORDER BY id LIMIT 1').get(localTicketId) as any;
              const targetDeviceId = firstDevice?.id;
              if (targetDeviceId) {
                for (const acc of accessories) {
                  try {
                    const accName = safeStr(acc.name) || '';
                    if (!accName) continue;
                    const accPrice = safeNum(acc.price);
                    const accQty = safeInt(acc.quantity) || 1;
                    const accSerial = safeStr(acc.item_serials);
                    const accWarranty = acc.warranty ? 1 : 0;

                    let invItemId: number | null = null;
                    // Try to find by SKU first (accessories usually have SKUs)
                    if (acc.sku) {
                      const bySku = stmts.findInventoryBySku.get(acc.sku) as any;
                      if (bySku) invItemId = bySku.id;
                    }
                    if (!invItemId && acc.id) {
                      const mapped = db.prepare('SELECT local_id FROM import_id_map WHERE entity_type = ? AND rd_id = ?').get('inventory', String(acc.id)) as any;
                      if (mapped) invItemId = mapped.local_id;
                    }
                    if (!invItemId) {
                      const byName = stmts.findInventoryByName.get(accName) as any;
                      if (byName) invItemId = byName.id;
                    }
                    // Create placeholder if not found
                    if (!invItemId) {
                      const placeholderSku = acc.sku || `RD-ACC-${acc.id || Date.now()}`;
                      const insertResult = db.prepare(
                        `INSERT OR IGNORE INTO inventory_items
                          (sku, upc, name, description, item_type, category, manufacturer,
                           cost_price, retail_price, in_stock, reorder_level, stock_warning,
                           tax_inclusive, is_serialized, is_active, created_at, updated_at)
                         VALUES (?, '', ?, '', 'part', 'Imported Parts', '',
                                 ?, ?, 0, 0, 0,
                                 0, 0, 1, ?, ?)`
                      ).run(placeholderSku, accName, safeNum(acc.cost_price), accPrice, createdAt, createdAt);
                      if (insertResult.changes > 0) {
                        invItemId = Number(insertResult.lastInsertRowid);
                      } else {
                        const existing = db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(placeholderSku) as any;
                        if (existing) invItemId = existing.id;
                      }
                    }
                    if (!invItemId) continue;

                    stmts.insertTicketPart.run(
                      targetDeviceId,
                      invItemId,
                      accQty,
                      accPrice,
                      accWarranty,
                      accSerial,
                      createdAt,
                      createdAt,
                    );
                  } catch (_accErr) {
                    // Skip bad accessories silently
                  }
                }
              }
            }

            // Import notes (at top level of rdRaw, not inside summary)
            const notes = Array.isArray(rdRaw.notes) ? rdRaw.notes : (Array.isArray(rd.notes) ? rd.notes : []);
            for (const note of notes) {
              try {
                const noteContent = safeStr(note.msg_text) || safeStr(note.tittle) || ''; // RD typo: tittle
                if (!noteContent) continue;

                const noteType = note.type === 1 ? 'diagnostic' : 'internal';
                const noteCreatedAt = toISODate(note.created_on) || createdAt;

                stmts.insertTicketNote.run(
                  localTicketId,
                  null, // ticket_device_id — RD notes may reference deviceId but we skip linking for now
                  noteType,
                  noteContent,
                  note.is_flag ? 1 : 0,
                  noteCreatedAt,
                  noteCreatedAt,
                );
              } catch (_noteErr) {
                // Silently skip bad notes
              }
            }

            // Import history (RD typo: hostory) — at top level of rdRaw
            const history = Array.isArray(rdRaw.hostory) ? rdRaw.hostory : (Array.isArray(rd.hostory) ? rd.hostory : []);
            for (const h of history) {
              try {
                const desc = safeStr(h.description) || '';
                if (!desc) continue;
                const hDate = toISODate(h.creationdate) || createdAt;
                stmts.insertTicketHistory.run(localTicketId, 'import', desc, hDate);
              } catch (_hErr) {
                // Silently skip
              }
            }

            imported++;
          } catch (err: any) {
            errors++;
            errorLog.push({
              record_id: rd.id || 'unknown',
              message: err.message?.substring(0, 300) || 'Unknown error',
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

  const finalStatus = cancelFlags.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[Import] Tickets: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importInvoices(
  db: any,
  client: RdApiClient,
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

  for await (const { records, pagination } of client.fetchAllPages('invoices', 1000)) {
    if (cancelFlags.get(tenantSlug)) break;

    totalRecords = pagination.total_records;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlags.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const rdRaw of batch) {
          const rd = rdRaw.summary || rdRaw;
          const rdLineItems = rdRaw.line_items || rd.line_items || [];
          const rdId = String(rd.id);
          try {

            const existing = stmts.findMapping.get('invoice', rdId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Resolve customer — RD uses sale_to_customer_id or customer object
            const rdCust = rd.customer || rd.ref_customer;
            const rdCustIdRaw = rd.sale_to_customer_id || rdCust?.cid || rdCust?.id || rd.customer_id;
            const rdCustId = rdCustIdRaw && String(rdCustIdRaw) !== '0' && String(rdCustIdRaw) !== '' ? String(rdCustIdRaw) : null;
            let localCustId: number | null = null;
            if (rdCustId) {
              const custMap = stmts.findMapping.get('customer', rdCustId) as { local_id: number } | undefined;
              localCustId = custMap?.local_id ?? null;
            }
            // Allow invoices without a customer (walk-in POS sales)

            // Resolve linked ticket (RD uses ticket_number like "T-999")
            let localTicketId: number | null = null;
            const rdTicketRef = rd.ticket_id || rd.ticket_number || rd.ticket?.id;
            if (rdTicketRef) {
              // Try to find by RD ticket ID
              const ticketIdStr = String(rdTicketRef).replace(/^T-/, '');
              const ticketMap = stmts.findMapping.get('ticket', ticketIdStr) as { local_id: number } | undefined;
              localTicketId = ticketMap?.local_id ?? null;
            }

            // Map RD status to local
            const rdStatus = (safeStr(rd.status) || 'draft').toLowerCase();
            let localStatus = 'draft';
            if (rdStatus === 'paid') localStatus = 'paid';
            else if (rdStatus === 'unpaid') localStatus = 'unpaid';
            else if (rdStatus === 'partial') localStatus = 'partial';
            else if (rdStatus === 'refunded') localStatus = 'refunded';
            else localStatus = rdStatus; // pass through

            const createdAt = toISODate(rd.created_date) || now();
            const orderId = safeStr(rd.order_id) || `INV-RD-${rdId}`;

            const total = safeNum(rd.total);
            const amountPaid = safeNum(rd.amount_paid);
            const amountDue = safeNum(rd.amount_due) || Math.max(0, total - amountPaid);

            const result = stmts.insertInvoice.run(
              orderId,
              localTicketId,
              localCustId,
              localStatus,
              safeNum(rd.subtotal) || safeNum(rd.sub_total) || total, // RD uses sub_total
              safeNum(rd.discount),
              safeStr(rd.discount_reason),
              safeNum(rd.total_tax),
              total,
              amountPaid,
              amountDue,
              toISODate(rd.due_on),
              safeStr(rd.notes),
              createdAt,
              createdAt,
            );

            const localInvId = Number(result.lastInsertRowid);
            stmts.insertMapping.run(runId, 'invoice', rdId, localInvId);

            // Import line items (from rdLineItems extracted above, or fallback)
            const lineItems = rdLineItems.length > 0 ? rdLineItems : (Array.isArray(rd.items) ? rd.items : []);
            for (const li of lineItems) {
              try {
                // Try to find a matching inventory item by SKU
                let inventoryItemId: number | null = null;
                if (li.sku) {
                  const inv = stmts.findInventoryBySku.get(li.sku) as { id: number } | undefined;
                  inventoryItemId = inv?.id ?? null;
                }

                stmts.insertInvoiceLineItem.run(
                  localInvId,
                  inventoryItemId,
                  safeStr(li.name) || safeStr(li.description) || '',
                  safeInt(li.quantity, 1),
                  safeNum(li.price),
                  safeNum(li.line_discount),
                  safeNum(li.gst),
                  safeNum(li.total),
                  createdAt,
                  createdAt,
                );
              } catch (_liErr) {
                // Skip bad line items silently
              }
            }

            // Import payments
            const payments = Array.isArray(rd.payments) ? rd.payments : [];
            for (const pmt of payments) {
              try {
                const pmtDate = toISODate(pmt.payment_date) || createdAt;
                stmts.insertPayment.run(
                  localInvId,
                  safeNum(pmt.amount),
                  safeStr(pmt.method) || safeStr(pmt.type) || 'Other',
                  safeStr(pmt.type), // method_detail
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
          } catch (err: any) {
            errors++;
            errorLog.push({
              record_id: rd.id || 'unknown',
              message: err.message?.substring(0, 300) || 'Unknown error',
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

  const finalStatus = cancelFlags.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[Import] Invoices: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importInventory(
  db: any,
  client: RdApiClient,
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

  for await (const { records, pagination } of client.fetchAllPages('inventory', 1000)) {
    if (cancelFlags.get(tenantSlug)) break;

    totalRecords = pagination.total_records;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlags.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const rd of batch) {
          try {
            const rdId = String(rd.id);

            const existing = stmts.findMapping.get('inventory', rdId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            // Determine item_type from RD data
            let itemType: 'product' | 'part' | 'service' = 'product';
            const rdItemType = (safeStr(rd.item_type) || '').toLowerCase();
            if (rdItemType.includes('service') || rdItemType.includes('repair')) {
              itemType = 'service';
            } else if (rdItemType.includes('part')) {
              itemType = 'part';
            }

            const createdAt = toISODate(rd.created_on) || now();
            const sku = safeStr(rd.sku);
            const name = safeStr(rd.name) || 'Unnamed Item';

            const result = stmts.insertInventoryItem.run(
              sku,
              safeStr(rd.upc_code),
              name,
              safeStr(rd.description),
              itemType,
              safeStr(rd.category),
              safeStr(rd.manufacturer),
              safeNum(rd.cost_price),
              safeNum(rd.price), // RD: price is retail
              safeInt(rd.in_stock),
              safeInt(rd.reorder_level),
              safeInt(rd.stock_warning),
              rd.tax_inclusive ? 1 : 0,
              rd.is_serialize ? 1 : 0,
              createdAt,
              createdAt,
            );

            let localId = Number(result.lastInsertRowid);
            // If OR IGNORE skipped (duplicate SKU), find existing
            if (result.changes === 0 && sku) {
              const existing = db.prepare('SELECT id FROM inventory_items WHERE sku = ?').get(sku) as any;
              if (existing) localId = existing.id;
            }
            stmts.insertMapping.run(runId, 'inventory', rdId, localId);

            imported++;
          } catch (err: any) {
            errors++;
            errorLog.push({
              record_id: rd.id || 'unknown',
              message: err.message?.substring(0, 300) || 'Unknown error',
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

  const finalStatus = cancelFlags.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[Import] Inventory: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

async function importSms(
  db: any,
  client: RdApiClient,
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

  // SMS uses a slightly different endpoint path: /v1/sms-inbox
  // and per_page max 100
  for await (const { records, pagination } of client.fetchAllPages('sms-inbox', 100)) {
    if (cancelFlags.get(tenantSlug)) break;

    totalRecords = pagination.total_records;

    for (let i = 0; i < records.length; i += 100) {
      if (cancelFlags.get(tenantSlug)) break;

      const batch = records.slice(i, i + 100);
      db.transaction(() => {
        for (const rd of batch) {
          try {
            const rdId = String(rd.id);

            const existing = stmts.findMapping.get('sms', rdId) as { local_id: number } | undefined;
            if (existing) {
              skipped++;
              continue;
            }

            const fromNum = safeStr(rd.from) || '';
            const toNum = safeStr(rd.to) || '';
            const direction = (safeStr(rd.direction) || 'outbound').toLowerCase();
            const createdAt = toISODate(rd.date_time) || now();

            // conv_phone: the customer's phone number
            // For inbound, it's the from number; for outbound, it's the to number
            const convPhone = normalizePhone(direction === 'inbound' ? fromNum : toNum);

            // Map RD module to our entity_type
            let entityType: string | null = null;
            let entityId: number | null = null;
            if (rd.module && rd.module_id) {
              const moduleMap: Record<string, string> = {
                'Ticket': 'ticket',
                'Invoice': 'invoice',
                'Customer': 'customer',
                'Leads': 'lead',
                'Estimates': 'estimate',
              };
              entityType = moduleMap[rd.module] || null;
              if (entityType && rd.module_id) {
                // Try to resolve to local ID
                const mapped = stmts.findMapping.get(entityType, String(rd.module_id)) as { local_id: number } | undefined;
                entityId = mapped?.local_id ?? null;
              }
            }

            const result = stmts.insertSms.run(
              fromNum,
              toNum,
              convPhone,
              safeStr(rd.message) || '',
              safeStr(rd.status) || 'delivered',
              direction,
              safeStr(rd.error),
              entityType,
              entityId,
              createdAt,
              createdAt,
            );

            const localId = Number(result.lastInsertRowid);
            stmts.insertMapping.run(runId, 'sms', rdId, localId);

            imported++;
          } catch (err: any) {
            errors++;
            errorLog.push({
              record_id: rd.id || 'unknown',
              message: err.message?.substring(0, 300) || 'Unknown error',
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

  const finalStatus = cancelFlags.get(tenantSlug) ? 'cancelled' : 'completed';
  stmts.markRunComplete.run(
    finalStatus, now(), totalRecords, imported, skipped, errors,
    JSON.stringify(errorLog.slice(-100)),
    runId,
  );

  console.log(`[Import] SMS: ${imported} imported, ${skipped} skipped, ${errors} errors out of ${totalRecords}`);
}

// ---------------------------------------------------------------------------
// Orchestrator
// ---------------------------------------------------------------------------

export interface ImportRequest {
  apiKey: string;
  entities: EntityType[];
  runIds: Record<EntityType, number>;
  tenantSlug?: string;
}

/**
 * Run the full import. Called as a background task (fire-and-forget).
 * Updates import_runs rows with progress as it goes.
 */
export async function runRepairDeskImport(db: any, request: ImportRequest): Promise<void> {
  const tenantSlug = request.tenantSlug || 'default';
  cancelFlags.set(tenantSlug, false);

  const client = new RdApiClient(request.apiKey, undefined, tenantSlug);
  const stmts = getStatements(db);

  // Order matters: customers first (referenced by tickets/invoices), then tickets, then invoices
  const orderedEntities: EntityType[] = ['customers', 'inventory', 'tickets', 'invoices', 'sms'];
  const toProcess = orderedEntities.filter(e => request.entities.includes(e));

  console.log(`[Import] Starting RepairDesk import for: ${toProcess.join(', ')}`);

  for (const entity of toProcess) {
    if (cancelFlags.get(tenantSlug)) {
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
          await importCustomers(db, client, runId, stmts, tenantSlug);
          break;
        case 'tickets':
          await importTickets(db, client, runId, stmts, tenantSlug);
          break;
        case 'invoices':
          await importInvoices(db, client, runId, stmts, tenantSlug);
          break;
        case 'inventory':
          await importInventory(db, client, runId, stmts, tenantSlug);
          break;
        case 'sms':
          await importSms(db, client, runId, stmts, tenantSlug);
          break;
      }
    } catch (err: any) {
      console.error(`[Import] Fatal error importing ${entity}:`, err.message);
      stmts.markRunComplete.run(
        'failed', now(), 0, 0, 0, 1,
        JSON.stringify([{ record_id: 'fatal', message: err.message?.substring(0, 500), timestamp: now() }]),
        runId,
      );
    }
  }

  // Post-import: fetch notes/history per ticket (list endpoint returns empty arrays)
  if (toProcess.includes('tickets') && !cancelFlags.get(tenantSlug)) {
    console.log('[Import] Starting per-ticket notes/history fetch...');
    await importTicketNotesAndHistory(db, client, stmts, tenantSlug);
  }

  console.log('[Import] RepairDesk import finished.');
}

/**
 * Post-import: fetch notes + history per-ticket from individual ticket endpoints.
 * The list endpoint returns empty notes/hostory arrays — must fetch individually.
 *
 * SA7-1: checkpoint progress to `import_job_state` on every ticket. The
 * checkpoint write is inside the same transaction as the note/history
 * INSERTs, so partial progress is impossible. A crash mid-loop can be
 * recovered by re-calling this function — it will skip tickets it's
 * already processed via `shouldSkip`. The `startFresh` knob on callers
 * decides whether to wipe first.
 */
async function importTicketNotesAndHistory(
  db: any,
  client: RdApiClient,
  stmts: ReturnType<typeof getStatements>,
  tenantSlug: string,
  opts: { startFresh?: boolean } = {},
): Promise<{ notesImported: number; historyImported: number; errors: number }> {
  const mappings = db.prepare(
    `SELECT source_id, local_id FROM import_id_map WHERE entity_type = 'ticket' ORDER BY local_id`
  ).all() as Array<{ source_id: string; local_id: number }>;

  const countNotes = db.prepare(`SELECT COUNT(*) as cnt FROM ticket_notes WHERE ticket_id = ?`);
  const countHistory = db.prepare(`SELECT COUNT(*) as cnt FROM ticket_history WHERE ticket_id = ?`);

  // SA7-1 checkpoint handle. `startFresh` defaults to false here because
  // an in-process import should be resumable across a crash by default;
  // explicit callers (CLI scripts) override.
  const jobId = buildJobId('repairdesk', 'ticket-notes-history', tenantSlug);
  const jobState = resumeJobState(db, jobId, {
    total: mappings.length,
    startFresh: opts.startFresh ?? false,
  });
  jobState.markRunning();

  let notesImported = 0;
  let historyImported = 0;
  let errors = 0;
  let processed = jobState.currentStep();

  if (jobState.resumed) {
    console.log(
      `[Import] Resuming notes/history from checkpoint: step=${processed} ` +
      `cursor=${jobState.currentCursor()}`,
    );
  }
  console.log(`[Import] Fetching notes/history for ${mappings.length} tickets individually...`);

  for (let idx = 0; idx < mappings.length; idx++) {
    if (cancelFlags.get(tenantSlug)) {
      jobState.markPaused();
      break;
    }

    const { source_id: rdId, local_id: localTicketId } = mappings[idx];

    // SA7-1: cheap in-memory skip for rows already processed in a prior run.
    if (jobState.shouldSkip(rdId, idx)) continue;

    processed++;

    // Skip tickets that already have notes — still checkpoint so resume doesn't revisit.
    const existing = (countNotes.get(localTicketId) as { cnt: number }).cnt;
    if (existing > 0) {
      jobState.checkpoint({ step: processed, lastProcessedId: rdId });
      continue;
    }

    try {
      const url = `${client['baseUrl']}/tickets/${rdId}`;
      const resp = await fetch(url, {
        signal: AbortSignal.timeout(30000),
        headers: { 'Authorization': `Bearer ${client['apiKey']}` },
      });

      if (!resp.ok) {
        if (resp.status === 429) {
          await sleep(5000);
          // Don't checkpoint — we want to retry this ticket on the next loop iteration / restart.
          continue;
        }
        errors++;
        // Non-429 HTTP error: checkpoint so we don't get stuck on the same ticket.
        jobState.checkpoint({ step: processed, lastProcessedId: rdId });
        continue;
      }

      const json = await resp.json() as { success: boolean; data: any };
      if (!json.success) {
        jobState.checkpoint({ step: processed, lastProcessedId: rdId });
        continue;
      }

      const ticket = json.data;
      const notes = Array.isArray(ticket.notes) ? ticket.notes : [];
      const history = Array.isArray(ticket.hostory)
        ? ticket.hostory
        : (Array.isArray(ticket.history) ? ticket.history : []);

      // SA7-1: notes + history + checkpoint in ONE transaction.
      db.transaction(() => {
        for (const note of notes) {
          const content = safeStr(note.msg_text) || safeStr(note.tittle) || '';
          if (!content) continue;
          const noteType = note.type === 1 ? 'diagnostic' : 'internal';
          const noteDate = toISODate(note.created_on) || now();
          stmts.insertTicketNote.run(localTicketId, null, noteType, content, note.is_flag ? 1 : 0, noteDate, noteDate);
          notesImported++;
        }
        for (const h of history) {
          const desc = safeStr(h.description) || '';
          if (!desc) continue;
          const hDate = toISODate(h.creationdate) || now();
          stmts.insertTicketHistory.run(localTicketId, 'import', desc, hDate);
          historyImported++;
        }
        jobState.checkpoint({ step: processed, lastProcessedId: rdId });
      })();

      if (processed % 100 === 0) {
        console.log(`[Import] Notes progress: ${processed}/${mappings.length} | Notes: ${notesImported} | History: ${historyImported}`);
      }

      await sleep(200); // polite delay
    } catch (err: unknown) {
      errors++;
      // Best-effort record of the error — don't advance the cursor so
      // a restart can retry this ticket.
      const msg = err instanceof Error ? err.message : String(err);
      try { jobState.fail(msg); jobState.markRunning(); } catch { /* ignore */ }
    }
  }

  if (!cancelFlags.get(tenantSlug)) {
    jobState.complete(processed);
  }
  console.log(`[Import] Notes complete: ${notesImported} notes, ${historyImported} history entries, ${errors} errors`);
  return { notesImported, historyImported, errors };
}

/**
 * Factory wipe: delete ALL business data.
 * Preserves: users, store_config, ticket_statuses, tax_classes, payment_methods, migrations, device_models, manufacturers.
 */
export function factoryWipe(db: any): void {
  console.log('[Nuclear] Wiping all business data...');

  // Disable foreign keys AND triggers during wipe
  db.pragma('foreign_keys = OFF');

  // Drop ALL FTS and cascading triggers so DELETEs don't fire them
  const FTS_TRIGGER_NAMES = [
    'customers_fts_insert', 'customers_fts_delete', 'customers_fts_update',
    'tickets_fts_ai', 'tickets_fts_au', 'tickets_fts_ad',
    'tickets_fts_device_ai', 'tickets_fts_device_au', 'tickets_fts_device_ad',
    'tickets_fts_note_ai', 'tickets_fts_note_au', 'tickets_fts_note_ad',
  ];
  const allTriggers = FTS_TRIGGER_NAMES;
  for (const trigger of allTriggers) {
    try {
      assertValidTriggerName(trigger);
      db.prepare(`DROP TRIGGER IF EXISTS ${trigger}`).run();
      console.log(`[Nuclear]   Dropped trigger: ${trigger}`);
    } catch (e: any) {
      console.warn(`[Nuclear]   Could not drop trigger ${trigger}: ${e.message}`);
    }
  }

  // Clear FTS tables BEFORE deleting from main tables (triggers are gone)
  try { db.prepare("DELETE FROM customers_fts").run(); console.log('[Nuclear]   Cleared customers_fts'); } catch {}
  try { db.prepare("DELETE FROM tickets_fts").run(); console.log('[Nuclear]   Cleared tickets_fts'); } catch {}
  // Also try device_models_fts and supplier_catalog_fts
  try { db.prepare("DELETE FROM device_models_fts").run(); } catch {}
  try { db.prepare("DELETE FROM supplier_catalog_fts").run(); } catch {}

  db.transaction(() => {
    const tables = [
      // Import tracking
      'import_id_map', 'import_runs',
      // SMS + comms
      'sms_messages', 'sms_conversation_flags', 'sms_conversation_reads', 'email_messages',
      // Payments + invoices
      'gift_card_transactions', 'gift_cards', 'store_credit_transactions', 'store_credits', 'refunds',
      'payments', 'invoice_line_items', 'invoices',
      // Tickets + related
      'customer_feedback',
      'parts_order_queue_tickets', 'parts_order_queue',
      'ticket_device_parts', 'ticket_photos', 'ticket_notes', 'ticket_history',
      'ticket_checklists', 'ticket_devices', 'tickets',
      // Customers
      'customer_phones', 'customer_emails', 'customer_assets', 'customers',
      // Inventory
      'stock_movements', 'inventory_serials', 'inventory_group_prices', 'inventory_device_compatibility', 'inventory_items',
      'purchase_order_items', 'purchase_orders', 'suppliers',
      // Leads + estimates
      'lead_devices', 'appointments', 'leads',
      'estimate_line_items', 'estimates',
      // POS
      'pos_transactions', 'cash_register',
      // RMA + trade-ins + loaners
      'rma_items', 'rma_requests', 'trade_ins',
      'loaner_history', 'loaner_devices',
      // Employee + expenses
      'clock_entries', 'commissions', 'expenses',
      // Notifications + misc
      'notifications', 'device_otps',
      'custom_field_values',
    ];

    for (const table of tables) {
      try {
        assertValidTableName(table);
        const result = db.prepare(`DELETE FROM ${table}`).run();
        if (result.changes > 0) console.log(`[Nuclear]   Cleared ${table}: ${result.changes} rows`);
      } catch (e: any) {
        console.warn(`[Nuclear]   FAILED to clear ${table}: ${e.message}`);
      }
    }

    // Reset autoincrement sequences (keep system tables)
    db.prepare("DELETE FROM sqlite_sequence WHERE name NOT IN ('users', 'ticket_statuses', 'tax_classes', 'payment_methods', '_migrations', 'store_config', 'manufacturers', 'device_models', 'repair_services', 'repair_pricing', 'repair_pricing_grades', 'repair_price_grades', 'repair_prices', 'condition_templates', 'condition_checks', 'supplier_catalog', 'scrape_jobs', 'sms_templates', 'referral_sources', 'automations', 'custom_field_definitions', 'snippets', 'checklist_templates', 'notification_templates', 'customer_groups', 'user_preferences', 'audit_logs')").run();
  })();

  // Re-enable foreign keys
  db.pragma('foreign_keys = ON');

  // Recreate FTS triggers (they were dropped to prevent issues during wipe)
  recreateFtsTriggers(db);

  // Verify the wipe actually worked
  const remainingCustomers = (db.prepare('SELECT COUNT(*) as c FROM customers').get() as { c: number }).c;
  const remainingTickets = (db.prepare('SELECT COUNT(*) as c FROM tickets').get() as { c: number }).c;
  console.log(`[Nuclear] Verification — customers: ${remainingCustomers}, tickets: ${remainingTickets}`);
  if (remainingCustomers > 0 || remainingTickets > 0) {
    console.error('[Nuclear] WARNING: Wipe incomplete! Customers or tickets still remain.');
  }

  console.log('[Nuclear] Wipe complete. Ready for reimport.');
}

/**
 * Selective wipe: delete chosen categories of data while preserving others.
 * Handles cross-references safely:
 *   - Customers without tickets → nullify ticket.customer_id
 *   - Tickets without invoices → nullify invoice.ticket_id
 *   - Inventory without tickets → nullify ticket_device_parts.inventory_item_id
 */
export function selectiveWipe(
  db: any,
  categories: Record<string, boolean>,
  currentUserId: number,
): { deleted: Record<string, number> } {
  const deleted: Record<string, number> = {};
  const del = (table: string) => {
    try {
      assertValidTableName(table);
      const r = db.prepare(`DELETE FROM ${table}`).run();
      deleted[table] = (deleted[table] || 0) + r.changes;
      if (r.changes > 0) console.log(`[SelectiveWipe]   Cleared ${table}: ${r.changes} rows`);
    } catch (e: any) {
      console.warn(`[SelectiveWipe]   FAILED to clear ${table}: ${e.message}`);
    }
  };

  log.info('selectiveWipe starting', { categories: Object.keys(categories).filter(k => categories[k]) });

  // Drop FTS triggers before bulk deletes to avoid trigger errors
  const FTS_TRIGGER_NAMES: ReadonlyArray<string> = [
    'customers_fts_insert', 'customers_fts_delete', 'customers_fts_update',
    'tickets_fts_ai', 'tickets_fts_au', 'tickets_fts_ad',
    'tickets_fts_device_ai', 'tickets_fts_device_au', 'tickets_fts_device_ad',
    'tickets_fts_note_ai', 'tickets_fts_note_au', 'tickets_fts_note_ad',
  ];
  for (const trigger of FTS_TRIGGER_NAMES) {
    try {
      assertValidTriggerName(trigger);
      db.prepare(`DROP TRIGGER IF EXISTS ${trigger}`).run();
    } catch (e: any) {
      log.warn('selectiveWipe drop trigger failed', { trigger, error: e?.message });
    }
  }

  // Clear FTS tables that correspond to wiped categories
  if (categories.customers) {
    try { db.prepare('DELETE FROM customers_fts').run(); } catch {}
  }
  if (categories.tickets) {
    try { db.prepare('DELETE FROM tickets_fts').run(); } catch {}
  }

  // D8 fix: keep foreign_keys = ON so the relational contract stays intact.
  // The delete order inside the transaction is already child-first (parts
  // before devices, devices before tickets, etc). Anything that still trips
  // a FK means the wipe has a real bug, and we want it to fail loudly rather
  // than leave orphaned rows behind.
  db.pragma('foreign_keys = ON');

  db.transaction(() => {
    // ---- Business data (reverse dependency order) ----

    if (categories.sms) {
      del('sms_messages');
      del('sms_conversation_flags');
      del('sms_conversation_reads');
      del('call_logs');
      del('email_messages');
    }

    if (categories.expenses_pos) {
      del('expenses');
      del('pos_transactions');
      del('cash_register');
      del('commissions');
      del('clock_entries');
    }

    if (categories.leads_estimates) {
      del('estimate_line_items');
      del('estimates');
      del('lead_devices');
      del('appointments');
      del('leads');
    }

    if (categories.invoices) {
      del('gift_card_transactions');
      del('gift_cards');
      del('store_credit_transactions');
      del('store_credits');
      del('refunds');
      del('payments');
      del('invoice_line_items');
      del('invoices');
    }

    if (categories.tickets) {
      del('customer_feedback');
      del('parts_order_queue_tickets');
      del('parts_order_queue');
      del('ticket_device_parts');
      del('ticket_photos');
      del('ticket_notes');
      del('ticket_history');
      del('ticket_checklists');
      del('ticket_devices');
      del('tickets');
      del('device_otps');
      // If invoices NOT deleted, nullify the ticket reference on invoices
      if (!categories.invoices) {
        db.prepare('UPDATE invoices SET ticket_id = NULL WHERE ticket_id IS NOT NULL').run();
        console.log('[SelectiveWipe]   Nullified invoice.ticket_id references');
      }
    }

    if (categories.inventory) {
      del('stock_movements');
      del('inventory_serials');
      del('inventory_group_prices');
      del('inventory_device_compatibility');
      del('purchase_order_items');
      del('purchase_orders');
      del('rma_items');
      del('rma_requests');
      del('inventory_items');
      // If tickets NOT deleted, nullify inventory references on parts
      if (!categories.tickets) {
        db.prepare('UPDATE ticket_device_parts SET inventory_item_id = NULL WHERE inventory_item_id IS NOT NULL').run();
        console.log('[SelectiveWipe]   Nullified ticket_device_parts.inventory_item_id references');
      }
    }

    if (categories.customers) {
      del('portal_sessions');
      del('portal_verification_codes');
      del('customer_phones');
      del('customer_emails');
      del('customer_assets');
      del('loaner_history');
      del('trade_ins');
      // If tickets NOT deleted, nullify customer on tickets
      if (!categories.tickets) {
        db.prepare('UPDATE tickets SET customer_id = NULL WHERE customer_id IS NOT NULL').run();
        console.log('[SelectiveWipe]   Nullified tickets.customer_id references');
      }
      // If invoices NOT deleted, nullify customer on invoices
      if (!categories.invoices) {
        db.prepare('UPDATE invoices SET customer_id = NULL WHERE customer_id IS NOT NULL').run();
        console.log('[SelectiveWipe]   Nullified invoices.customer_id references');
      }
      del('customers');
    }

    // Clean up shared tables if any business data deleted
    if (categories.customers || categories.tickets || categories.invoices || categories.inventory || categories.sms) {
      del('import_id_map');
      del('import_runs');
      del('notifications');
      del('custom_field_values');
    }

    // ---- System resets ----

    if (categories.reset_settings) {
      del('store_config');
    }

    if (categories.reset_users) {
      // D5 fix: before deleting users, resolve every FK reference to them so
      // we don't create dangling rows (or, with foreign_keys=ON, crash the
      // wipe entirely). Strategy:
      //   * Nullable FKs  → set NULL.
      //   * NOT NULL FKs  → reassign to the surviving `currentUserId`
      //     so history/notes/invoices stay attributable to a real row.
      //
      // Tables below are derived from `grep user_id|created_by|assigned_to`
      // on the migration files. If a new migration adds a user FK, it MUST
      // be added here too.
      const survivor = currentUserId;

      // --- Nullable FK columns: set NULL for the deleted users ---
      const NULL_OUT: ReadonlyArray<{ table: string; col: string }> = [
        { table: 'audit_logs',      col: 'user_id' },
        { table: 'ticket_history',  col: 'user_id' },
        { table: 'tickets',         col: 'assigned_to' },
        { table: 'ticket_devices',  col: 'assigned_to' },
        { table: 'leads',           col: 'assigned_to' },
        { table: 'leads',           col: 'created_by' },
        { table: 'appointments',    col: 'assigned_to' },
        { table: 'estimates',       col: 'assigned_to' },
      ];
      for (const { table, col } of NULL_OUT) {
        try {
          assertValidTableName(table);
          if (!/^[a-z_]+$/.test(col)) throw new Error(`bad col: ${col}`);
          db.prepare(`UPDATE ${table} SET ${col} = NULL WHERE ${col} IS NOT NULL AND ${col} != ?`).run(survivor);
        } catch (e: any) {
          log.warn('selectiveWipe null-out skipped', { table, col, error: e?.message });
        }
      }

      // --- NOT NULL FK columns: reassign to the survivor ---
      const REASSIGN: ReadonlyArray<{ table: string; col: string }> = [
        { table: 'invoices',        col: 'created_by' },
        { table: 'estimates',       col: 'created_by' },
        { table: 'tickets',         col: 'created_by' },
        { table: 'ticket_notes',    col: 'user_id' },
        { table: 'pos_transactions', col: 'user_id' },
        { table: 'clock_entries',   col: 'user_id' },
        { table: 'commissions',     col: 'user_id' },
        { table: 'expenses',        col: 'user_id' },
        { table: 'notifications',   col: 'user_id' },
      ];
      for (const { table, col } of REASSIGN) {
        try {
          assertValidTableName(table);
          if (!/^[a-z_]+$/.test(col)) throw new Error(`bad col: ${col}`);
          db.prepare(`UPDATE ${table} SET ${col} = ? WHERE ${col} != ?`).run(survivor, survivor);
        } catch (e: any) {
          log.warn('selectiveWipe reassign skipped', { table, col, error: e?.message });
        }
      }

      // user_preferences has UNIQUE(user_id,key). Wipe rows for deleted users
      // — don't try to reassign (would violate UNIQUE).
      try {
        db.prepare('DELETE FROM user_preferences WHERE user_id != ?').run(survivor);
      } catch (e: any) {
        log.warn('selectiveWipe user_preferences delete skipped', { error: e?.message });
      }

      // Now it's finally safe to blow away sessions + users.
      db.prepare('DELETE FROM sessions WHERE user_id != ?').run(survivor);
      const userDel = db.prepare('DELETE FROM users WHERE id != ?').run(survivor);
      deleted['users'] = userDel.changes;
    }

    if (categories.reset_statuses) {
      del('ticket_statuses');
    }

    if (categories.reset_tax_classes) {
      del('tax_classes');
    }

    if (categories.reset_payment_methods) {
      del('payment_methods');
    }

    if (categories.reset_templates) {
      del('sms_templates');
      del('notification_templates');
      del('checklist_templates');
    }

    // Reset autoincrement sequences for deleted tables
    const deletedTables = Object.keys(deleted).filter(t => deleted[t] > 0);
    if (deletedTables.length > 0) {
      for (const table of deletedTables) {
        try { db.prepare('DELETE FROM sqlite_sequence WHERE name = ?').run(table); } catch {}
      }
    }
  })();

  // Idempotent safety net — already ON, but we want to guarantee it on exit.
  db.pragma('foreign_keys = ON');

  // Recreate FTS triggers
  recreateFtsTriggers(db);

  // Re-seed system tables that were reset
  if (categories.reset_settings || categories.reset_statuses || categories.reset_tax_classes ||
      categories.reset_payment_methods || categories.reset_templates) {
    try {
      const { seedDatabase } = require('../db/seed.js');
      seedDatabase(db);
      log.info('selectiveWipe re-seeded system defaults');
    } catch (e: any) {
      log.warn('selectiveWipe re-seed failed', { error: e?.message });
    }
  }

  log.info('selectiveWipe complete', { deleted });
  return { deleted };
}

/**
 * Nuclear wipe by source: delete ONLY data imported from a specific source (e.g. 'repairdesk').
 * Uses import_id_map + import_runs to identify which records came from that source,
 * then deletes them in reverse dependency order.
 */
export function nuclearWipeSource(db: any, source: string): void {
  const VALID_SOURCES = ['repairdesk', 'repairshopr', 'myrepairapp'];
  if (!VALID_SOURCES.includes(source)) throw new Error('Invalid source');

  console.log(`[NuclearWipe] Wiping data imported from ${source}...`);

  db.pragma('foreign_keys = OFF');

  db.transaction(() => {
    // Get all local IDs imported from this source, grouped by entity type
    const mappings = db.prepare(`
      SELECT im.entity_type, im.local_id
      FROM import_id_map im
      JOIN import_runs ir ON ir.id = im.import_run_id
      WHERE ir.source = ?
    `).all(source) as { entity_type: string; local_id: number }[];

    // Group by entity type
    const byType: Record<string, number[]> = {};
    for (const m of mappings) {
      if (!byType[m.entity_type]) byType[m.entity_type] = [];
      byType[m.entity_type].push(m.local_id);
    }

    // Helper to delete in batches (SQLite has a variable limit)
    const batchDelete = (table: string, column: string, ids: number[]) => {
      assertValidTableName(table);
      if (!/^[a-z_]+$/.test(column)) throw new Error(`Invalid column name: ${column}`);
      for (let i = 0; i < ids.length; i += 500) {
        const batch = ids.slice(i, i + 500);
        const placeholders = batch.map(() => '?').join(',');
        db.prepare(`DELETE FROM ${table} WHERE ${column} IN (${placeholders})`).run(...batch);
      }
    };

    // Delete in reverse dependency order
    // 1. SMS
    if (byType['sms']?.length) {
      batchDelete('sms_messages', 'id', byType['sms']);
      console.log(`[NuclearWipe]   Deleted ${byType['sms'].length} SMS messages`);
    }

    // 2. Invoices (+ cascade: payments, line items)
    if (byType['invoice']?.length) {
      const ids = byType['invoice'];
      batchDelete('payments', 'invoice_id', ids);
      batchDelete('invoice_line_items', 'invoice_id', ids);
      batchDelete('invoices', 'id', ids);
      console.log(`[NuclearWipe]   Deleted ${ids.length} invoices`);
    }

    // 3. Tickets (+ cascade: devices, parts, notes, history, photos, checklists)
    if (byType['ticket']?.length) {
      const ids = byType['ticket'];
      // Get device IDs for these tickets
      const deviceIds = db.prepare(
        `SELECT id FROM ticket_devices WHERE ticket_id IN (${ids.map(() => '?').join(',')})`
      ).all(...ids).map((r: any) => r.id);

      if (deviceIds.length > 0) {
        batchDelete('ticket_device_parts', 'ticket_device_id', deviceIds);
      }
      batchDelete('ticket_photos', 'ticket_id', ids);
      batchDelete('ticket_notes', 'ticket_id', ids);
      batchDelete('ticket_history', 'ticket_id', ids);
      batchDelete('ticket_checklists', 'ticket_id', ids);
      batchDelete('ticket_devices', 'ticket_id', ids);
      batchDelete('tickets', 'id', ids);
      console.log(`[NuclearWipe]   Deleted ${ids.length} tickets`);
    }

    // 4. Inventory (+ cascade: stock movements)
    if (byType['inventory']?.length) {
      const ids = byType['inventory'];
      batchDelete('stock_movements', 'inventory_item_id', ids);
      batchDelete('inventory_group_prices', 'inventory_item_id', ids);
      batchDelete('inventory_device_compatibility', 'inventory_item_id', ids);
      batchDelete('inventory_items', 'id', ids);
      console.log(`[NuclearWipe]   Deleted ${ids.length} inventory items`);
    }

    // 5. Customers (+ cascade: phones, emails, assets)
    if (byType['customer']?.length) {
      const ids = byType['customer'];
      batchDelete('customer_phones', 'customer_id', ids);
      batchDelete('customer_emails', 'customer_id', ids);
      batchDelete('customer_assets', 'customer_id', ids);
      batchDelete('customers', 'id', ids);
      console.log(`[NuclearWipe]   Deleted ${ids.length} customers`);
    }

    // Clean up import tracking for this source
    db.prepare('DELETE FROM import_id_map WHERE import_run_id IN (SELECT id FROM import_runs WHERE source = ?)').run(source);
    db.prepare('DELETE FROM import_runs WHERE source = ?').run(source);
  })();

  db.pragma('foreign_keys = ON');
  console.log(`[NuclearWipe] Wipe of ${source} data complete.`);
}

function recreateFtsTriggers(db: any): void {
  console.log('[Nuclear] Recreating FTS triggers...');

  // Customers FTS triggers (exact match from migration 004)
  db.exec(`
    CREATE TRIGGER IF NOT EXISTS customers_fts_insert AFTER INSERT ON customers BEGIN
      INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
      VALUES (NEW.id, NEW.first_name, NEW.last_name, NEW.email, NEW.phone, NEW.mobile, NEW.organization, NEW.city, NEW.postcode, NEW.tags);
    END;

    CREATE TRIGGER IF NOT EXISTS customers_fts_delete BEFORE DELETE ON customers BEGIN
      INSERT INTO customers_fts(customers_fts, rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
      VALUES ('delete', OLD.id, OLD.first_name, OLD.last_name, OLD.email, OLD.phone, OLD.mobile, OLD.organization, OLD.city, OLD.postcode, OLD.tags);
    END;

    CREATE TRIGGER IF NOT EXISTS customers_fts_update AFTER UPDATE ON customers BEGIN
      INSERT INTO customers_fts(customers_fts, rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
      VALUES ('delete', OLD.id, OLD.first_name, OLD.last_name, OLD.email, OLD.phone, OLD.mobile, OLD.organization, OLD.city, OLD.postcode, OLD.tags);
      INSERT INTO customers_fts(rowid, first_name, last_name, email, phone, mobile, organization, city, postcode, tags)
      VALUES (NEW.id, NEW.first_name, NEW.last_name, NEW.email, NEW.phone, NEW.mobile, NEW.organization, NEW.city, NEW.postcode, NEW.tags);
    END;
  `);

  // Tickets FTS triggers (exact match from migration 004)
  db.exec(`
    CREATE TRIGGER IF NOT EXISTS tickets_fts_ai AFTER INSERT ON tickets BEGIN
      INSERT INTO tickets_fts (rowid, order_id, device_names, customer_name, notes_text, labels)
      VALUES (
        NEW.id,
        COALESCE(NEW.order_id, ''),
        '',
        COALESCE((SELECT first_name || ' ' || last_name FROM customers WHERE id = NEW.customer_id), ''),
        '',
        COALESCE(NEW.labels, '')
      );
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_au AFTER UPDATE ON tickets BEGIN
      INSERT INTO tickets_fts (tickets_fts, rowid, order_id, device_names, customer_name, notes_text, labels)
      VALUES ('delete', OLD.id, '', '', '', '', '');
      INSERT INTO tickets_fts (rowid, order_id, device_names, customer_name, notes_text, labels)
      VALUES (
        NEW.id,
        COALESCE(NEW.order_id, ''),
        COALESCE((
          SELECT GROUP_CONCAT(device_name, ', ')
          FROM ticket_devices WHERE ticket_id = NEW.id
        ), ''),
        COALESCE((SELECT first_name || ' ' || last_name FROM customers WHERE id = NEW.customer_id), ''),
        COALESCE((
          SELECT GROUP_CONCAT(content, ' ')
          FROM ticket_notes WHERE ticket_id = NEW.id
        ), ''),
        COALESCE(NEW.labels, '')
      );
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_ad AFTER DELETE ON tickets BEGIN
      INSERT INTO tickets_fts (tickets_fts, rowid, order_id, device_names, customer_name, notes_text, labels)
      VALUES ('delete', OLD.id, '', '', '', '', '');
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_device_ai AFTER INSERT ON ticket_devices BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_device_au AFTER UPDATE ON ticket_devices BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_device_ad AFTER DELETE ON ticket_devices BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_note_ai AFTER INSERT ON ticket_notes BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_note_au AFTER UPDATE ON ticket_notes BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = NEW.ticket_id;
    END;

    CREATE TRIGGER IF NOT EXISTS tickets_fts_note_ad AFTER DELETE ON ticket_notes BEGIN
      UPDATE tickets SET updated_at = updated_at WHERE id = OLD.ticket_id;
    END;
  `);

  console.log('[Nuclear] FTS triggers recreated.');
}

/**
 * Test the API connection without importing anything.
 */
export async function testRepairDeskConnection(apiKey: string): Promise<{
  ok: boolean;
  message: string;
  totalCustomers?: number;
}> {
  const client = new RdApiClient(apiKey);
  return client.testConnection();
}
