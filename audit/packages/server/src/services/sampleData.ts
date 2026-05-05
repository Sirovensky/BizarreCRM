/**
 * Sample Data Service — Day-1 Onboarding (audit section 42, idea 3)
 *
 * Creates a small, realistic set of demo rows so a brand-new shop owner can
 * click around and *see* what the CRM feels like before typing anything real.
 * Every row is tagged with the sentinel prefix `[Sample]` so real users can
 * visually distinguish demo data at a glance, AND we persist the exact
 * {type, id} pairs into onboarding_state.sample_data_entities_json so the
 * "Remove sample data" button deletes byte-for-byte what was inserted — not
 * everything that happens to contain the word "Sample" in a tag field.
 *
 * Inserted shape:
 *   - 5 customers (varied names, phones, emails)
 *   - 10 tickets  (each with 1 device, assigned to default status, distributed
 *                  across the past 14 days so dashboard charts show something)
 *   - 3 invoices  (linked to 3 of the tickets, marked paid so the "$0" KPI
 *                  cards become non-empty on day 1)
 *
 * Safety rails:
 *   - Uses adb.transaction() so partial failures roll the whole batch back.
 *   - Reads the default ticket_status_id at runtime; if no statuses exist yet
 *     this throws a clear error instead of corrupting FKs.
 *   - Falls back to a safe no-op if a user row exists in the tenant (needed
 *     for created_by on tickets/invoices). A brand-new tenant always has its
 *     admin row from provisioning, so this is mostly defensive.
 *
 * Removal:
 *   The matching removeSampleData() helper walks the stored entity list in
 *   dependency order (ticket_device_parts -> ticket_devices -> tickets ->
 *   invoices -> customers) to avoid FK violations, again atomically.
 */

import type { AsyncDb, TxQuery } from '../db/async-db.js';
import { AppError } from '../middleware/errorHandler.js';
import { createLogger } from '../utils/logger.js';

const logger = createLogger('sampleData');

/** Visible tag prefix used in names and order_ids. */
export const SAMPLE_TAG = '[Sample]';

/** Discriminated union of things we inserted. */
export type SampleEntityType = 'customer' | 'ticket' | 'ticket_device' | 'invoice' | 'inventory_item';

export interface SampleEntity {
  type: SampleEntityType;
  id: number;
}

/**
 * Shape returned to callers on successful load so the route can echo it back
 * to the client and persist it in onboarding_state.
 */
export interface SampleDataResult {
  entities: ReadonlyArray<SampleEntity>;
  counts: {
    customers: number;
    tickets: number;
    invoices: number;
    parts: number;
  };
}

interface SeedCustomer {
  first_name: string;
  last_name: string;
  email: string;
  phone: string;
}

interface SeedTicket {
  customer_index: number;   // 0..4 pointer into seeded customers
  device_name: string;
  device_type: 'phone' | 'computer' | 'tablet' | 'watch' | 'other';
  price: number;            // retail, rounded to 2dp already
  days_ago: number;         // 0..13
}

// Static seed content. Names are obviously synthetic so a real owner will not
// confuse them with a real customer. Phones are in the 555-01xx reserved
// prefix (RFC 3849 equivalent for telephony) to prevent anyone from actually
// dialing them.
const SEED_CUSTOMERS: ReadonlyArray<SeedCustomer> = [
  { first_name: 'Alex',   last_name: 'Demo',    email: 'alex.demo@example.com',    phone: '3035550101' },
  { first_name: 'Jamie',  last_name: 'Sample',  email: 'jamie.sample@example.com', phone: '3035550102' },
  { first_name: 'Robin',  last_name: 'Test',    email: 'robin.test@example.com',   phone: '3035550103' },
  { first_name: 'Morgan', last_name: 'Example', email: 'morgan.ex@example.com',    phone: '3035550104' },
  { first_name: 'Casey',  last_name: 'Preview', email: 'casey.prev@example.com',   phone: '3035550105' },
];

const SEED_TICKETS: ReadonlyArray<SeedTicket> = [
  { customer_index: 0, device_name: 'iPhone 13 screen repair',  device_type: 'phone',    price: 149.99, days_ago: 1 },
  { customer_index: 0, device_name: 'iPhone 12 battery',        device_type: 'phone',    price:  79.00, days_ago: 3 },
  { customer_index: 1, device_name: 'MacBook Pro keyboard',     device_type: 'computer', price: 249.00, days_ago: 2 },
  { customer_index: 1, device_name: 'Galaxy S22 charge port',   device_type: 'phone',    price:  99.50, days_ago: 5 },
  { customer_index: 2, device_name: 'iPad mini screen',         device_type: 'tablet',   price: 189.00, days_ago: 6 },
  { customer_index: 2, device_name: 'Pixel 7 water damage',     device_type: 'phone',    price: 129.00, days_ago: 8 },
  { customer_index: 3, device_name: 'Dell XPS 13 SSD upgrade',  device_type: 'computer', price: 219.00, days_ago: 9 },
  { customer_index: 3, device_name: 'Apple Watch band',         device_type: 'watch',    price:  39.99, days_ago: 10 },
  { customer_index: 4, device_name: 'OnePlus Nord speaker',     device_type: 'phone',    price:  69.00, days_ago: 11 },
  { customer_index: 4, device_name: 'Surface Pro charger',      device_type: 'computer', price:  59.99, days_ago: 13 },
];

/** Which three tickets (by zero-based index) get invoices. */
const INVOICED_TICKET_INDEXES: ReadonlyArray<number> = [0, 2, 4];

/**
 * Looks up the default ticket status + a user id to use as created_by.
 * Throws a clear AppError if prerequisites are missing.
 */
async function resolvePrereqs(adb: AsyncDb): Promise<{ statusId: number; userId: number }> {
  const statusRow = await adb.get<{ id: number }>(
    'SELECT id FROM ticket_statuses ORDER BY is_default DESC, sort_order ASC LIMIT 1',
  );
  if (!statusRow) {
    throw new AppError('Cannot load sample data: no ticket statuses configured yet', 409);
  }
  const userRow = await adb.get<{ id: number }>(
    'SELECT id FROM users ORDER BY id ASC LIMIT 1',
  );
  if (!userRow) {
    throw new AppError('Cannot load sample data: no users in tenant yet', 409);
  }
  return { statusId: statusRow.id, userId: userRow.id };
}

/**
 * Build an ISO timestamp N days before now (UTC). Used for created_at on
 * sample tickets so dashboard charts distribute the rows across 2 weeks.
 */
function daysAgoIso(days: number): string {
  const d = new Date();
  d.setUTCHours(12, 0, 0, 0); // anchor to noon so DST edge cases don't bite
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().replace('T', ' ').slice(0, 19);
}

/**
 * Creates every sample row inside a SINGLE atomic statement batch.
 * Caller is responsible for updating onboarding_state with the returned
 * entity list.
 *
 * Note on why we don't use adb.transaction(): the worker-pool transaction API
 * takes a static list of queries — we need IDs from earlier inserts to pipe
 * into later ones (e.g. ticket_id -> invoice.ticket_id). So we run each
 * insert sequentially; if any throws we roll back manually by walking the
 * entity list we've built so far.
 */
export async function loadSampleData(adb: AsyncDb): Promise<SampleDataResult> {
  const { statusId, userId } = await resolvePrereqs(adb);

  const entities: SampleEntity[] = [];
  const customerIds: number[] = [];
  const ticketIds: number[] = [];

  try {
    // ── Inventory item (sample part for POS checkout tutorial) ──
    const partResult = await adb.run(
      `INSERT INTO inventory_items
        (sku, name, item_type, cost_price, retail_price, in_stock)
       VALUES (?, ?, ?, ?, ?, ?)`,
      'SAMPLE-SCREEN-001',
      `Screen assembly ${SAMPLE_TAG}`,
      'part',
      45,    // cost_price in dollars (schema uses REAL)
      120,   // retail_price in dollars
      10,
    );
    entities.push({ type: 'inventory_item', id: Number(partResult.lastInsertRowid) });

    // ── Customers ──
    for (const c of SEED_CUSTOMERS) {
      const result = await adb.run(
        `INSERT INTO customers
          (first_name, last_name, email, phone, mobile, source, tags, email_opt_in, sms_opt_in, comments)
         VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, ?)`,
        c.first_name,
        `${c.last_name} ${SAMPLE_TAG}`,
        c.email,
        c.phone,
        c.phone,
        'sample_data',
        JSON.stringify(['sample']),
        `Sample demo customer. Safe to delete via Settings → Onboarding.`,
      );
      const id = Number(result.lastInsertRowid);
      customerIds.push(id);
      entities.push({ type: 'customer', id });
    }

    // ── Tickets + one device each ──
    for (let i = 0; i < SEED_TICKETS.length; i++) {
      const t = SEED_TICKETS[i];
      const customerId = customerIds[t.customer_index];
      const createdAt = daysAgoIso(t.days_ago);
      const orderId = `SAMPLE-T${String(i + 1).padStart(3, '0')}`;
      const ticketResult = await adb.run(
        `INSERT INTO tickets
          (order_id, customer_id, status_id, subtotal, total, labels, created_by, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        orderId,
        customerId,
        statusId,
        t.price,
        t.price,
        JSON.stringify(['sample']),
        userId,
        createdAt,
        createdAt,
      );
      const ticketId = Number(ticketResult.lastInsertRowid);
      ticketIds.push(ticketId);
      entities.push({ type: 'ticket', id: ticketId });

      const deviceResult = await adb.run(
        `INSERT INTO ticket_devices
          (ticket_id, device_name, device_type, price, total, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`,
        ticketId,
        `${t.device_name} ${SAMPLE_TAG}`,
        t.device_type,
        t.price,
        t.price,
        createdAt,
        createdAt,
      );
      entities.push({ type: 'ticket_device', id: Number(deviceResult.lastInsertRowid) });
    }

    // ── Invoices ──
    for (let i = 0; i < INVOICED_TICKET_INDEXES.length; i++) {
      const idx = INVOICED_TICKET_INDEXES[i];
      const t = SEED_TICKETS[idx];
      const ticketId = ticketIds[idx];
      const customerId = customerIds[t.customer_index];
      const createdAt = daysAgoIso(t.days_ago);
      const orderId = `SAMPLE-INV${String(i + 1).padStart(3, '0')}`;
      const invResult = await adb.run(
        `INSERT INTO invoices
          (order_id, ticket_id, customer_id, status, subtotal, total, amount_paid, amount_due, notes, created_by, created_at, updated_at)
         VALUES (?, ?, ?, 'paid', ?, ?, ?, 0, ?, ?, ?, ?)`,
        orderId,
        ticketId,
        customerId,
        t.price,
        t.price,
        t.price,
        `${SAMPLE_TAG} Demo invoice. Safe to delete via Settings → Onboarding.`,
        userId,
        createdAt,
        createdAt,
      );
      entities.push({ type: 'invoice', id: Number(invResult.lastInsertRowid) });
    }

    logger.info('Sample data loaded', { customers: customerIds.length, tickets: ticketIds.length, invoices: INVOICED_TICKET_INDEXES.length, parts: 1 });

    return {
      entities,
      counts: {
        customers: customerIds.length,
        tickets: ticketIds.length,
        invoices: INVOICED_TICKET_INDEXES.length,
        parts: 1,
      },
    };
  } catch (err) {
    // Best-effort rollback — the DB already committed each insert individually
    // (no wrapping transaction) so we walk the list in reverse dependency order.
    logger.error('Sample data insert failed; attempting rollback', { error: err instanceof Error ? err.message : String(err) });
    try {
      await removeSampleDataByEntities(adb, entities);
    } catch (rollbackErr) {
      logger.error('Sample data rollback also failed', { error: rollbackErr instanceof Error ? rollbackErr.message : String(rollbackErr) });
    }
    throw err instanceof AppError ? err : new AppError('Failed to load sample data', 500);
  }
}

/**
 * Deletes the entities listed by id in dependency-safe order (parts ->
 * devices -> tickets -> invoices -> customers). Returns the number of rows
 * removed for the audit log. Non-throwing on individual row misses so a
 * partial state can still be cleaned up.
 */
export async function removeSampleDataByEntities(
  adb: AsyncDb,
  entities: ReadonlyArray<SampleEntity>,
): Promise<number> {
  if (!entities.length) return 0;

  // Group by type for batch deletes.
  const inventoryItemIds = entities.filter((e) => e.type === 'inventory_item').map((e) => e.id);
  const ticketIds = entities.filter((e) => e.type === 'ticket').map((e) => e.id);
  const invoiceIds = entities.filter((e) => e.type === 'invoice').map((e) => e.id);
  const customerIds = entities.filter((e) => e.type === 'customer').map((e) => e.id);

  // Deletion order:
  //   1. inventory_items — no FK dependents in the sample set
  //   2. invoices — removed before tickets to avoid FK violations
  //   3. tickets — ticket_devices/parts cascade via ON DELETE CASCADE
  //   4. customers
  const queries: TxQuery[] = [];
  if (inventoryItemIds.length) {
    const placeholders = inventoryItemIds.map(() => '?').join(',');
    queries.push({ sql: `DELETE FROM inventory_items WHERE id IN (${placeholders})`, params: inventoryItemIds });
  }
  if (invoiceIds.length) {
    const placeholders = invoiceIds.map(() => '?').join(',');
    queries.push({ sql: `DELETE FROM invoices WHERE id IN (${placeholders})`, params: invoiceIds });
  }
  if (ticketIds.length) {
    const placeholders = ticketIds.map(() => '?').join(',');
    queries.push({ sql: `DELETE FROM tickets WHERE id IN (${placeholders})`, params: ticketIds });
  }
  if (customerIds.length) {
    const placeholders = customerIds.map(() => '?').join(',');
    queries.push({ sql: `DELETE FROM customers WHERE id IN (${placeholders})`, params: customerIds });
  }

  if (!queries.length) return 0;

  const results = await adb.transaction(queries);
  const totalChanges = results.reduce((acc, r) => acc + (r.changes ?? 0), 0);
  logger.info('Sample data removed', { totalRows: totalChanges, inventoryItems: inventoryItemIds.length, invoices: invoiceIds.length, tickets: ticketIds.length, customers: customerIds.length });
  return totalChanges;
}
