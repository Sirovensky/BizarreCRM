/**
 * Wallet Pass service (audit §49 — idea 12)
 *
 * Renders a customer loyalty/referral/membership card for Apple Wallet and
 * Google Pay. Full .pkpass generation requires an Apple Developer cert + a
 * signing step; we *can* support it later, but for the initial ship we fall
 * back to a dynamic HTML page that works in every mobile browser and still
 * exposes the customer's:
 *
 *   - Display name + store name
 *   - Loyalty point balance (from portal's loyalty_points ledger)
 *   - Referral code (from portal's referrals table, generated lazily)
 *   - Membership tier / ltv_tier / health_tier
 *
 * The HTML fallback is the DEFAULT path. The .pkpass path is stubbed with a
 * config-flag check (`wallet_pass_signing_enabled` on store_config) — when
 * the owner wires real certs via master admin, we read them and sign; until
 * then we always return HTML.
 *
 * SECURITY:
 *   - Route layer generates `wallet_pass_id` as a random UUID the first time
 *     a pass is requested and stores it on customers.wallet_pass_id. That
 *     UUID is the unguessable URL identifier — plain customer IDs would leak
 *     enumeration.
 *   - HTML is escaped via a small local helper to keep the surface tight.
 */

import crypto from 'crypto';
import type { AsyncDb } from '../db/async-db.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('walletPass');

type AnyRow = Record<string, unknown>;

export interface WalletPassData {
  readonly passId: string;
  readonly customerId: number;
  readonly customerName: string;
  readonly loyaltyPoints: number;
  readonly referralCode: string | null;
  readonly ltvTier: string | null;
  readonly healthTier: string | null;
  readonly storeName: string;
}

// -----------------------------------------------------------------------------
// Helpers
// -----------------------------------------------------------------------------

function escapeHtml(input: string): string {
  return input
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

/**
 * Generate a new wallet pass ID (uuid-like) for a customer that doesn't have
 * one yet. Stable per-customer — the route layer only ever calls this when
 * customers.wallet_pass_id is NULL.
 */
export function generateWalletPassId(): string {
  return crypto.randomUUID();
}

/**
 * Loyalty balance = SUM(points) from the portal-owned loyalty_points ledger.
 * Returns 0 if the customer has no entries or the table is missing (defensive
 * in case a shop is running an older db that hasn't hit migration 089 yet).
 */
async function fetchLoyaltyBalance(adb: AsyncDb, customerId: number): Promise<number> {
  try {
    const row = await adb.get<{ total: number | null }>(
      `SELECT COALESCE(SUM(points),0) AS total FROM loyalty_points WHERE customer_id = ?`,
      customerId,
    );
    return row?.total ?? 0;
  } catch (err) {
    // Defensive: missing loyalty_points table on pre-migration-089 tenants.
    // Log so a real SQLite error (corruption, locked db) is still visible.
    log.warn('fetchLoyaltyBalance failed — returning 0', {
      customerId,
      error: err instanceof Error ? err.message : String(err),
    });
    return 0;
  }
}

/**
 * Fetch the customer's most recent referral code. Does NOT auto-generate —
 * the CRM routes provide a dedicated POST /crm/customers/:id/referral-code
 * endpoint for that. Returns null if none has been minted yet.
 */
async function fetchReferralCode(adb: AsyncDb, customerId: number): Promise<string | null> {
  try {
    const row = await adb.get<{ referral_code: string | null }>(
      `SELECT referral_code FROM referrals
         WHERE referrer_customer_id = ?
         ORDER BY created_at DESC LIMIT 1`,
      customerId,
    );
    return row?.referral_code ?? null;
  } catch (err) {
    // Defensive: missing referrals table on pre-migration-089 tenants.
    log.warn('fetchReferralCode failed — returning null', {
      customerId,
      error: err instanceof Error ? err.message : String(err),
    });
    return null;
  }
}

/**
 * Gather everything we need to render a pass. Returns null if the customer
 * doesn't exist. The caller is responsible for minting wallet_pass_id on
 * customers.wallet_pass_id before invoking this.
 */
export async function loadWalletPassData(
  adb: AsyncDb,
  customerId: number,
): Promise<WalletPassData | null> {
  const customer = await adb.get<AnyRow>(
    `SELECT id, first_name, last_name, wallet_pass_id, ltv_tier, health_tier
       FROM customers WHERE id = ?`,
    customerId,
  );
  if (!customer) return null;
  const passId = (customer.wallet_pass_id as string | null) ?? '';
  if (!passId) return null;
  return assembleWalletPassData(adb, customer, passId, customerId);
}

/**
 * @audit-fixed: lookup by `wallet_pass_id` directly (not customer_id) so the
 * route layer doesn't have to translate UUID → customer ID first. This shrinks
 * the attack surface: callers cannot probe a customer ID range and infer pass
 * existence from the difference between "no customer" and "no pass" responses,
 * because the only public identifier is the random UUID.
 */
export async function loadWalletPassDataByPassId(
  adb: AsyncDb,
  passId: string,
): Promise<WalletPassData | null> {
  if (!passId || passId.length < 8) return null;
  const customer = await adb.get<AnyRow>(
    `SELECT id, first_name, last_name, wallet_pass_id, ltv_tier, health_tier
       FROM customers WHERE wallet_pass_id = ? LIMIT 1`,
    passId,
  );
  if (!customer) return null;
  const customerId = customer.id as number;
  return assembleWalletPassData(adb, customer, passId, customerId);
}

/** Shared finalization between the two lookup paths. */
async function assembleWalletPassData(
  adb: AsyncDb,
  customer: AnyRow,
  passId: string,
  customerId: number,
): Promise<WalletPassData> {
  const [loyaltyPoints, referralCode, storeNameRow] = await Promise.all([
    fetchLoyaltyBalance(adb, customerId),
    fetchReferralCode(adb, customerId),
    adb.get<{ value: string }>(
      `SELECT value FROM store_config WHERE key = 'store_name'`,
    ),
  ]);

  const firstName = (customer.first_name as string | null) ?? '';
  const lastName = (customer.last_name as string | null) ?? '';
  const customerName = `${firstName} ${lastName}`.trim() || 'Customer';

  return {
    passId,
    customerId,
    customerName,
    loyaltyPoints,
    referralCode,
    ltvTier: (customer.ltv_tier as string | null) ?? null,
    healthTier: (customer.health_tier as string | null) ?? null,
    storeName: storeNameRow?.value ?? 'Bizarre Electronics',
  };
}

// -----------------------------------------------------------------------------
// HTML fallback renderer
// -----------------------------------------------------------------------------

/**
 * Render a mobile-optimized wallet card. Not a pkpass — shows as a web page
 * but visually mimics one. Works on both iOS Safari and Android Chrome.
 */
export function renderWalletPassHtml(data: WalletPassData): string {
  const name = escapeHtml(data.customerName);
  const store = escapeHtml(data.storeName);
  const tier = escapeHtml(data.ltvTier ?? 'bronze');
  const points = data.loyaltyPoints.toLocaleString('en-US');
  const referral = data.referralCode ? escapeHtml(data.referralCode) : 'Ask at checkout';
  const passId = escapeHtml(data.passId);

  // Single-file, no external fonts, no JS — works offline once loaded.
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
  <title>${store} — ${name}</title>
  <meta name="theme-color" content="#0f172a">
  <style>
    :root { color-scheme: dark; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           background: #0b1220; color: #f8fafc; min-height: 100vh;
           display: flex; align-items: center; justify-content: center; padding: 16px; }
    .card { width: 100%; max-width: 360px; background: linear-gradient(135deg,#1e293b,#0f172a);
            border-radius: 22px; padding: 24px; box-shadow: 0 30px 60px rgba(2,6,23,.6);
            border: 1px solid rgba(148,163,184,.12); }
    .store { font-size: 12px; letter-spacing: 2px; text-transform: uppercase;
             color: #94a3b8; }
    .name  { font-size: 24px; font-weight: 700; margin: 4px 0 20px; }
    .row   { display: flex; justify-content: space-between; align-items: baseline;
             padding: 12px 0; border-top: 1px solid rgba(148,163,184,.15); }
    .label { font-size: 11px; text-transform: uppercase; letter-spacing: 1px; color: #64748b; }
    .value { font-size: 18px; font-weight: 600; }
    .tier  { display: inline-block; padding: 4px 10px; border-radius: 999px;
             font-size: 11px; text-transform: uppercase; letter-spacing: 1px;
             background: rgba(250,204,21,.16); color: #fde047; }
    .ref   { font-family: ui-monospace, monospace; background: rgba(148,163,184,.1);
             padding: 6px 10px; border-radius: 8px; display: inline-block; }
    .foot  { margin-top: 18px; font-size: 10px; color: #475569; text-align: center;
             letter-spacing: 1px; text-transform: uppercase; }
  </style>
</head>
<body>
  <div class="card" role="region" aria-label="Loyalty wallet pass">
    <div class="store">${store}</div>
    <div class="name">${name}</div>
    <div class="row"><span class="label">Tier</span><span class="tier">${tier}</span></div>
    <div class="row"><span class="label">Loyalty points</span><span class="value">${points}</span></div>
    <div class="row"><span class="label">Referral code</span><span class="ref">${referral}</span></div>
    <div class="foot">Pass ID ${passId.slice(0, 8)}</div>
  </div>
</body>
</html>`;
}

// -----------------------------------------------------------------------------
// .pkpass path (stubbed — real signing requires Apple Dev certs)
// -----------------------------------------------------------------------------

export interface PkPassConfig {
  readonly enabled: boolean;
  readonly teamId?: string;
  readonly passTypeId?: string;
  readonly certPath?: string;
}

/**
 * Read the pkpass signing config from store_config. Defaults to disabled.
 */
export async function getPkPassConfig(adb: AsyncDb): Promise<PkPassConfig> {
  try {
    const row = await adb.get<{ value: string }>(
      `SELECT value FROM store_config WHERE key = 'wallet_pass_signing_enabled'`,
    );
    const enabled = row?.value === 'true';
    if (!enabled) return { enabled: false };
    const [teamId, passTypeId, certPath] = await Promise.all([
      adb.get<{ value: string }>(`SELECT value FROM store_config WHERE key = 'wallet_pass_team_id'`),
      adb.get<{ value: string }>(`SELECT value FROM store_config WHERE key = 'wallet_pass_type_id'`),
      adb.get<{ value: string }>(`SELECT value FROM store_config WHERE key = 'wallet_pass_cert_path'`),
    ]);
    return {
      enabled: true,
      teamId: teamId?.value,
      passTypeId: passTypeId?.value,
      certPath: certPath?.value,
    };
  } catch (err) {
    // Defensive against missing store_config on very old tenants. Log the
    // real error instead of silently pretending pkpass is disabled.
    log.warn('getPkPassConfig failed — treating as disabled', {
      error: err instanceof Error ? err.message : String(err),
    });
    return { enabled: false };
  }
}

/**
 * Produce a signed .pkpass Buffer for the given customer. Throws if signing
 * isn't configured — callers should always check `getPkPassConfig()` first
 * and fall back to HTML on `{ enabled: false }`. The implementation is left
 * as a TODO until an owner wires real certs; returning a marker error keeps
 * the rest of the codebase type-safe.
 */
export async function generatePkPass(_data: WalletPassData): Promise<Buffer> {
  throw new Error('PKPASS_SIGNING_NOT_CONFIGURED');
}
