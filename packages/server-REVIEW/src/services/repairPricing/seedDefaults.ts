import type Database from 'better-sqlite3';
import {
  bulkApplyTier,
  type BulkApplyTierResult,
  type PricingTier,
} from './tierResolver.js';

export type RepairPricingSeedServiceKey = 'screen' | 'battery' | 'charge_port' | 'back_glass' | 'camera';
export type RepairPricingSeedTier = Exclude<PricingTier, 'unknown'>;

export type RepairPricingSeedPricing = Partial<
  Record<RepairPricingSeedServiceKey, Partial<Record<RepairPricingSeedTier, number>>>
>;

export interface SeedRepairPricingDefaultsOptions {
  /** Device/service category to seed. The setup wizard currently targets phone shops. */
  category?: string;
  /** Optional owner-edited values. Missing cells fall back to server medians below. */
  pricing?: RepairPricingSeedPricing;
  overwriteCustom?: boolean;
  changedByUserId?: number | null;
}

export interface SeedRepairPricingServiceResult {
  service_key: RepairPricingSeedServiceKey;
  repair_service_id: number | null;
  repair_service_slug: string | null;
  missing: boolean;
  tiers: BulkApplyTierResult[];
}

export interface SeedRepairPricingDefaultsResult {
  category: string;
  defaults: Record<RepairPricingSeedServiceKey, Record<RepairPricingSeedTier, number>>;
  services: SeedRepairPricingServiceResult[];
  summary: {
    services_matched: number;
    services_missing: number;
    matched_devices: number;
    inserted: number;
    updated: number;
    skipped_custom: number;
  };
}

interface RepairServiceRow {
  id: number;
  slug: string;
}

const SEED_TIERS: RepairPricingSeedTier[] = ['tier_a', 'tier_b', 'tier_c'];
const MAX_SETUP_LABOR_PRICE = 100_000;

/** Server-side day-1 labor medians for a phone repair shop.
 *  Clients may display these, but the backend remains the source that fans
 *  them into repair_prices and stores the tier defaults for future rebases. */
export const DEFAULT_REPAIR_PRICING_MEDIANS: Record<RepairPricingSeedServiceKey, Record<RepairPricingSeedTier, number>> = {
  screen: { tier_a: 200, tier_b: 120, tier_c: 80 },
  battery: { tier_a: 80, tier_b: 60, tier_c: 45 },
  charge_port: { tier_a: 120, tier_b: 90, tier_c: 70 },
  back_glass: { tier_a: 180, tier_b: 110, tier_c: 70 },
  camera: { tier_a: 140, tier_b: 90, tier_c: 60 },
};

const SERVICE_SLUGS: Record<RepairPricingSeedServiceKey, string[]> = {
  screen: ['screen-replacement', 'tablet-screen', 'laptop-screen', 'tv-screen', 'desktop-screen'],
  battery: ['battery-replacement', 'tablet-battery', 'laptop-battery'],
  charge_port: ['charging-port', 'laptop-charging-port'],
  back_glass: ['back-glass'],
  camera: ['camera-repair'],
};

function normalizeCategory(category: string | undefined): string {
  const trimmed = category?.trim();
  return trimmed || 'phone';
}

function normalizeLaborPrice(value: unknown, serviceKey: RepairPricingSeedServiceKey, tier: RepairPricingSeedTier): number {
  const n = Number(value);
  if (!Number.isFinite(n)) throw new Error(`Invalid labor price for ${serviceKey}/${tier}`);
  if (n < 0 || n > MAX_SETUP_LABOR_PRICE) {
    throw new Error(`Labor price for ${serviceKey}/${tier} must be between 0 and ${MAX_SETUP_LABOR_PRICE}`);
  }
  return Math.round(n * 100) / 100;
}

function mergedPricing(
  pricing: RepairPricingSeedPricing | undefined,
): Record<RepairPricingSeedServiceKey, Record<RepairPricingSeedTier, number>> {
  const merged = {} as Record<RepairPricingSeedServiceKey, Record<RepairPricingSeedTier, number>>;
  for (const serviceKey of Object.keys(DEFAULT_REPAIR_PRICING_MEDIANS) as RepairPricingSeedServiceKey[]) {
    merged[serviceKey] = { ...DEFAULT_REPAIR_PRICING_MEDIANS[serviceKey] };
    for (const tier of SEED_TIERS) {
      const override = pricing?.[serviceKey]?.[tier];
      if (override !== undefined && override !== null) {
        merged[serviceKey][tier] = normalizeLaborPrice(override, serviceKey, tier);
      }
    }
  }
  return merged;
}

function findSeedService(
  db: Database.Database,
  serviceKey: RepairPricingSeedServiceKey,
  category: string,
): RepairServiceRow | null {
  const slugs = SERVICE_SLUGS[serviceKey];
  const rows = db.prepare(`
    SELECT id, slug
    FROM repair_services
    WHERE is_active = 1
      AND category = ?
      AND slug IN (${slugs.map(() => '?').join(',')})
  `).all(category, ...slugs) as RepairServiceRow[];
  if (rows.length === 0) return null;
  rows.sort((a, b) => slugs.indexOf(a.slug) - slugs.indexOf(b.slug));
  return rows[0];
}

export function seedRepairPricingDefaults(
  db: Database.Database,
  opts: SeedRepairPricingDefaultsOptions = {},
): SeedRepairPricingDefaultsResult {
  const category = normalizeCategory(opts.category);
  const pricing = mergedPricing(opts.pricing);
  const services: SeedRepairPricingServiceResult[] = [];

  for (const serviceKey of Object.keys(pricing) as RepairPricingSeedServiceKey[]) {
    const service = findSeedService(db, serviceKey, category);
    if (!service) {
      services.push({
        service_key: serviceKey,
        repair_service_id: null,
        repair_service_slug: null,
        missing: true,
        tiers: [],
      });
      continue;
    }

    const tiers = SEED_TIERS.map((tier) => bulkApplyTier(db, {
      repairServiceId: service.id,
      tier,
      laborPrice: pricing[serviceKey][tier],
      category,
      overwriteCustom: opts.overwriteCustom ?? false,
      changedByUserId: opts.changedByUserId ?? null,
    }));

    services.push({
      service_key: serviceKey,
      repair_service_id: service.id,
      repair_service_slug: service.slug,
      missing: false,
      tiers,
    });
  }

  const allTierResults = services.flatMap((service) => service.tiers);
  return {
    category,
    defaults: pricing,
    services,
    summary: {
      services_matched: services.filter((service) => !service.missing).length,
      services_missing: services.filter((service) => service.missing).length,
      matched_devices: allTierResults.reduce((sum, result) => sum + result.matched_devices, 0),
      inserted: allTierResults.reduce((sum, result) => sum + result.inserted, 0),
      updated: allTierResults.reduce((sum, result) => sum + result.updated, 0),
      skipped_custom: allTierResults.reduce((sum, result) => sum + result.skipped_custom, 0),
    },
  };
}
