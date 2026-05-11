/**
 * SSW4: regression test. RepairDesk uses typo'd field names per CLAUDE.md.
 * If this test fails, you "corrected" a typo — DON'T. Their API expects them.
 */

import { describe, it, expect } from 'vitest';
import Database from 'better-sqlite3';
import {
  RD_SYNTHETIC_INVOICE_NOTE,
  canSynthesizePlaceholderInvoicesForUnlinkedTickets,
  importRdPartsForDevice,
  inferSyntheticInvoiceStateFromTicketStatus,
  mapRdCustomerTypoFields,
  mapRdTicketTypoFields,
  replaceSyntheticPlaceholderInvoiceForTicket,
  synthesizePlaceholderInvoicesForUnlinkedTickets,
} from '../repairDeskImport.js';
import fixture from './__fixtures__/repairdesk-customer.json';

describe('preserves RepairDesk API typo fields exactly', () => {
  it('mapRdCustomerTypoFields reads orgonization (not organization)', () => {
    const result = mapRdCustomerTypoFields(fixture.customer as Record<string, any>);
    expect(result.orgonization).toBe('Acme Phone Repair LLC');
  });

  it('mapRdCustomerTypoFields reads refered_by (not referred_by)', () => {
    const result = mapRdCustomerTypoFields(fixture.customer as Record<string, any>);
    expect(result.refered_by).toBe('Yelp');
  });

  it('mapRdTicketTypoFields reads hostory (not history)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.hostory).toHaveLength(2);
    expect(result.hostory[0].description).toBe('Ticket created');
  });

  it('mapRdTicketTypoFields reads createdd_date (not created_date)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.createdd_date).toBe('2024-08-15T10:00:00Z');
  });

  it('mapRdTicketTypoFields reads warrenty (not warranty)', () => {
    const result = mapRdTicketTypoFields(fixture.ticket as Record<string, any>);
    expect(result.warrenty).toBe('90');
  });

  it('mapRdTicketTypoFields reads tittle (not title) from note record', () => {
    const result = mapRdTicketTypoFields(fixture.note as Record<string, any>);
    expect(result.tittle).toBe('Screen Replacement');
  });

  it('mapRdTicketTypoFields reads suplied (not supplied) from device record', () => {
    const result = mapRdTicketTypoFields(fixture.device as Record<string, any>);
    expect(result.suplied).toHaveLength(1);
    expect(result.suplied[0].name).toBe('OEM Screen');
  });

  it('covers all 7 documented typo fields from CLAUDE.md', () => {
    // This test asserts the complete set so the count is explicit.
    // If you add a new typo field to CLAUDE.md, add a case above AND update this list.
    const coveredTypoFields = [
      'orgonization',   // customer.orgonization
      'refered_by',     // customer.refered_by
      'hostory',        // ticket.hostory
      'tittle',         // note.tittle
      'createdd_date',  // ticket.createdd_date
      'suplied',        // device.suplied
      'warrenty',       // ticket.warrenty
    ];
    expect(coveredTypoFields).toHaveLength(7);

    // Verify the fixture actually carries all 7 typo'd keys
    const customerKeys = Object.keys(fixture.customer);
    const ticketKeys = Object.keys(fixture.ticket);
    const noteKeys = Object.keys(fixture.note);
    const deviceKeys = Object.keys(fixture.device);
    const allFixtureKeys = [...customerKeys, ...ticketKeys, ...noteKeys, ...deviceKeys];

    for (const typoField of coveredTypoFields) {
      expect(allFixtureKeys).toContain(typoField);
    }
  });
});

function createImportBackfillDb() {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE import_runs (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      source TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      status TEXT NOT NULL,
      total_records INTEGER DEFAULT 0,
      imported INTEGER DEFAULT 0
    );
    CREATE TABLE import_id_map (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      import_run_id INTEGER NOT NULL,
      entity_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      local_id INTEGER NOT NULL
    );
    CREATE TABLE tickets (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      customer_id INTEGER,
      status_id INTEGER,
      subtotal REAL DEFAULT 0,
      discount REAL DEFAULT 0,
      total_tax REAL DEFAULT 0,
      total REAL DEFAULT 0,
      invoice_id INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at TEXT,
      updated_at TEXT
    );
    CREATE TABLE ticket_statuses (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      is_cancelled INTEGER NOT NULL DEFAULT 0
    );
    CREATE TABLE invoices (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL UNIQUE,
      ticket_id INTEGER,
      customer_id INTEGER,
      status TEXT NOT NULL DEFAULT 'draft',
      subtotal REAL NOT NULL DEFAULT 0,
      discount REAL NOT NULL DEFAULT 0,
      total_tax REAL NOT NULL DEFAULT 0,
      total REAL NOT NULL DEFAULT 0,
      amount_paid REAL NOT NULL DEFAULT 0,
      amount_due REAL NOT NULL DEFAULT 0,
      notes TEXT,
      created_by INTEGER,
      created_at TEXT,
      updated_at TEXT
    );
    CREATE TABLE invoice_line_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER
    );
    CREATE TABLE payments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_id INTEGER,
      amount REAL DEFAULT 0
    );
  `);
  return db;
}

describe('RepairDesk invoice placeholder backfill', () => {
  it('does not synthesize unpaid placeholders while the RD invoice import is still pending', () => {
    const db = createImportBackfillDb();
    db.prepare("INSERT INTO import_runs (source, entity_type, status) VALUES ('repairdesk', 'invoices', 'pending')").run();
    db.prepare(`
      INSERT INTO tickets (order_id, subtotal, total_tax, total, created_at)
      VALUES ('T-1', 100, 0, 100, '2026-05-01 00:00:00')
    `).run();

    const result = synthesizePlaceholderInvoicesForUnlinkedTickets(db);

    expect(result).toMatchObject({ created: 0, skipped: true, reason: 'repairdesk_invoice_import_pending' });
    expect(db.prepare('SELECT COUNT(*) AS count FROM invoices').get()).toMatchObject({ count: 0 });
  });

  it('synthesizes placeholders only after the latest RD invoice import completed', () => {
    const db = createImportBackfillDb();
    db.prepare("INSERT INTO import_runs (source, entity_type, status) VALUES ('repairdesk', 'invoices', 'completed')").run();
    db.prepare(`
      INSERT INTO tickets (order_id, subtotal, total_tax, total, created_at)
      VALUES ('T-1', 100, 8, 108, '2026-05-01 00:00:00')
    `).run();

    const result = synthesizePlaceholderInvoicesForUnlinkedTickets(db);
    const invoice = db.prepare('SELECT ticket_id, status, total, amount_paid, amount_due, notes FROM invoices').get();

    expect(result).toMatchObject({ created: 1 });
    expect(invoice).toMatchObject({
      ticket_id: 1,
      status: 'unpaid',
      total: 108,
      amount_paid: 0,
      amount_due: 108,
      notes: RD_SYNTHETIC_INVOICE_NOTE,
    });
  });

  it('replaces a synthetic placeholder when a real RD invoice for the ticket arrives later', () => {
    const db = createImportBackfillDb();
    db.prepare("INSERT INTO import_runs (source, entity_type, status) VALUES ('repairdesk', 'invoices', 'completed')").run();
    db.prepare(`
      INSERT INTO tickets (order_id, subtotal, total_tax, total, created_at)
      VALUES ('T-1', 100, 0, 100, '2026-05-01 00:00:00')
    `).run();
    synthesizePlaceholderInvoicesForUnlinkedTickets(db);
    const realInvoice = db.prepare(`
      INSERT INTO invoices (order_id, ticket_id, status, total, amount_paid, amount_due, notes)
      VALUES ('RD-INV-1', 1, 'paid', 100, 100, 0, NULL)
    `).run();

    const result = replaceSyntheticPlaceholderInvoiceForTicket(db, 1, Number(realInvoice.lastInsertRowid));
    const ticket = db.prepare('SELECT invoice_id FROM tickets WHERE id = 1').get();
    const invoices = db.prepare('SELECT order_id, status, amount_paid FROM invoices ORDER BY id').all();

    expect(result).toMatchObject({ replaced: true, placeholderId: 1 });
    expect(ticket).toMatchObject({ invoice_id: Number(realInvoice.lastInsertRowid) });
    expect(invoices).toEqual([{ order_id: 'RD-INV-1', status: 'paid', amount_paid: 100 }]);
  });

  it('uses the latest RD invoice run when deciding whether placeholder synthesis is safe', () => {
    const db = createImportBackfillDb();
    db.prepare("INSERT INTO import_runs (source, entity_type, status) VALUES ('repairdesk', 'invoices', 'pending')").run();
    db.prepare("INSERT INTO import_runs (source, entity_type, status) VALUES ('repairdesk', 'invoices', 'completed')").run();

    expect(canSynthesizePlaceholderInvoicesForUnlinkedTickets(db)).toEqual({ ok: true });
  });

  it('infers paid and void synthetic invoice state from clear ticket statuses', () => {
    expect(inferSyntheticInvoiceStateFromTicketStatus('Payment Received & Picked Up', 0, 125)).toEqual({
      status: 'paid',
      amountPaid: 125,
      amountDue: 0,
    });
    expect(inferSyntheticInvoiceStateFromTicketStatus('Cancelled', 1, 125)).toEqual({
      status: 'void',
      amountPaid: 0,
      amountDue: 0,
    });
  });
});

function createPartsImportDb() {
  const db = new Database(':memory:');
  db.exec(`
    CREATE TABLE import_id_map (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      import_run_id INTEGER NOT NULL,
      entity_type TEXT NOT NULL,
      source_id TEXT NOT NULL,
      local_id INTEGER NOT NULL
    );
    CREATE TABLE inventory_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      sku TEXT UNIQUE,
      upc TEXT,
      name TEXT NOT NULL,
      description TEXT,
      item_type TEXT NOT NULL DEFAULT 'product',
      category TEXT,
      manufacturer TEXT,
      cost_price REAL NOT NULL DEFAULT 0,
      retail_price REAL NOT NULL DEFAULT 0,
      in_stock INTEGER NOT NULL DEFAULT 0,
      reorder_level INTEGER NOT NULL DEFAULT 0,
      stock_warning INTEGER NOT NULL DEFAULT 0,
      tax_inclusive INTEGER NOT NULL DEFAULT 0,
      is_serialized INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT,
      updated_at TEXT
    );
    CREATE TABLE ticket_device_parts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      ticket_device_id INTEGER NOT NULL,
      inventory_item_id INTEGER NOT NULL,
      quantity INTEGER NOT NULL DEFAULT 1,
      price REAL NOT NULL DEFAULT 0,
      warranty INTEGER NOT NULL DEFAULT 0,
      serial TEXT,
      status TEXT NOT NULL DEFAULT 'available',
      created_at TEXT,
      updated_at TEXT
    );
  `);
  return db;
}

function createPartsImportStatements(db: any) {
  return {
    findMapping: db.prepare(
      `SELECT local_id FROM import_id_map
       WHERE entity_type = ? AND source_id = ?
       ORDER BY id DESC LIMIT 1`
    ),
    findInventoryBySku: db.prepare(`SELECT id FROM inventory_items WHERE sku = ? LIMIT 1`),
    findInventoryByName: db.prepare(
      `SELECT id FROM inventory_items WHERE LOWER(TRIM(name)) = LOWER(TRIM(?)) AND is_active = 1 LIMIT 1`
    ),
    insertTicketPart: db.prepare(
      `INSERT INTO ticket_device_parts
        (ticket_device_id, inventory_item_id, quantity, price, warranty, serial, status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, 'available', ?, ?)`
    ),
  };
}

describe('RepairDesk ticket part import', () => {
  it('resolves imported inventory through source_id mappings', () => {
    const db = createPartsImportDb();
    const inventory = db.prepare(`
      INSERT INTO inventory_items (sku, name, item_type, category, cost_price, retail_price, is_active)
      VALUES ('RD-SCREEN', 'OEM Screen', 'part', 'Screens', 47.5, 119.99, 1)
    `).run();
    db.prepare(`
      INSERT INTO import_id_map (import_run_id, entity_type, source_id, local_id)
      VALUES (1, 'inventory', '123', ?)
    `).run(Number(inventory.lastInsertRowid));

    const imported = importRdPartsForDevice(
      db,
      createPartsImportStatements(db) as any,
      7,
      [{ product_id: 123, name: 'OEM Screen', quantity: 2, price: 119.99, serial: 'ABC' }],
      '2026-05-01 10:00:00',
    );
    const part = db.prepare('SELECT inventory_item_id, quantity, price, serial FROM ticket_device_parts').get();

    expect(imported).toBe(1);
    expect(part).toMatchObject({
      inventory_item_id: Number(inventory.lastInsertRowid),
      quantity: 2,
      price: 119.99,
      serial: 'ABC',
    });
    expect(db.prepare('SELECT COUNT(*) AS count FROM inventory_items').get()).toMatchObject({ count: 1 });
  });

  it('creates placeholder inventory with part cost separate from ticket retail price', () => {
    const db = createPartsImportDb();

    const imported = importRdPartsForDevice(
      db,
      createPartsImportStatements(db) as any,
      8,
      [{ name: 'Special Order Battery', quantity: 1, price: 89, part_cost: 31.25 }],
      '2026-05-01 10:00:00',
    );
    const inventory = db.prepare('SELECT name, cost_price, retail_price FROM inventory_items').get();
    const part = db.prepare('SELECT price FROM ticket_device_parts').get();

    expect(imported).toBe(1);
    expect(inventory).toMatchObject({
      name: 'Special Order Battery',
      cost_price: 31.25,
      retail_price: 89,
    });
    expect(part).toMatchObject({ price: 89 });
  });
});
