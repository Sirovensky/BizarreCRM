// WEB-UIUX-895 — point-in-time snapshot columns on `invoices`. Builds the
// four snapshot fields (customer_name, customer_address, store_name,
// tax_jurisdiction) from the live customers + store_config rows at invoice
// creation time. Future renames/edits to the customer or store record do
// NOT leak back through prior receipts because print pages prefer the
// snapshot column when populated and fall back to the live row when NULL
// (legacy / pre-migration invoices). Migration 192_invoices_pit_snapshot.sql.

import type { AsyncDb } from '../db/async-db.js';

export interface InvoicePitSnapshot {
  customer_name_snapshot: string | null;
  customer_address_snapshot: string | null;
  store_name_snapshot: string | null;
  tax_jurisdiction_snapshot: string | null;
}

const EMPTY: InvoicePitSnapshot = {
  customer_name_snapshot: null,
  customer_address_snapshot: null,
  store_name_snapshot: null,
  tax_jurisdiction_snapshot: null,
};

function composeCustomerName(row: { first_name?: string | null; last_name?: string | null; organization?: string | null }): string | null {
  const first = (row.first_name ?? '').trim();
  const last = (row.last_name ?? '').trim();
  const org = (row.organization ?? '').trim();
  const personal = [first, last].filter(Boolean).join(' ');
  if (personal && org) return `${personal} (${org})`;
  return personal || org || null;
}

function composeCustomerAddress(row: {
  address1?: string | null;
  address2?: string | null;
  city?: string | null;
  state?: string | null;
  postcode?: string | null;
  country?: string | null;
}): string | null {
  const parts = [
    row.address1,
    row.address2,
    [row.city, row.state, row.postcode].filter(Boolean).join(' '),
    row.country,
  ]
    .map((p) => (p ?? '').trim())
    .filter(Boolean);
  return parts.length > 0 ? parts.join(', ') : null;
}

function composeJurisdiction(
  state: string | null | undefined,
  country: string | null | undefined,
): string | null {
  const s = (state ?? '').trim();
  const c = (country ?? '').trim();
  if (s && c) return `${s}, ${c}`;
  return s || c || null;
}

export async function getInvoicePitSnapshot(
  adb: AsyncDb,
  customerId: number | null,
): Promise<InvoicePitSnapshot> {
  try {
    const customerRow = customerId
      ? await adb.get<{
          first_name: string | null;
          last_name: string | null;
          organization: string | null;
          address1: string | null;
          address2: string | null;
          city: string | null;
          state: string | null;
          postcode: string | null;
          country: string | null;
        }>(
          `SELECT first_name, last_name, organization, address1, address2, city, state, postcode, country
           FROM customers WHERE id = ?`,
          customerId,
        )
      : null;

    const configRows = await adb.all<{ key: string; value: string }>(
      `SELECT key, value FROM store_config
       WHERE key IN ('store_name', 'store_state', 'store_country')`,
    );
    const config = new Map(configRows.map((r) => [r.key, r.value]));

    return {
      customer_name_snapshot: customerRow ? composeCustomerName(customerRow) : null,
      customer_address_snapshot: customerRow ? composeCustomerAddress(customerRow) : null,
      store_name_snapshot: (config.get('store_name') ?? '').trim() || null,
      tax_jurisdiction_snapshot: composeJurisdiction(config.get('store_state'), config.get('store_country')),
    };
  } catch {
    // Snapshot is best-effort. Print pages already fall back to live row
    // when these are NULL, so a snapshot-fill failure must not block the
    // invoice INSERT itself.
    return EMPTY;
  }
}
