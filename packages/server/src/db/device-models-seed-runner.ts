/**
 * Seeds manufacturers and device_models from the static dataset.
 * Runs on every startup (idempotent — uses INSERT OR IGNORE).
 *
 * Device-model seeding is gated by the shop's `shop_type` (set in onboarding):
 * a phone repair shop doesn't need 40 TVs, a watch repair shop doesn't need
 * Xbox consoles. Manufacturers are always seeded fully — they're cheap rows
 * that the "Add new device" modal needs in its dropdown regardless of focus.
 *
 * Re-running after shop_type changes is safe: INSERT OR IGNORE additively
 * fills in newly-allowed categories without touching existing rows.
 */
import { MANUFACTURERS, DEVICE_MODELS, type DeviceModelSeed } from './device-models-seed.js';

type DeviceCategory = DeviceModelSeed['category'];

const ALL_CATEGORIES: DeviceCategory[] = [
  'phone', 'tablet', 'laptop', 'desktop', 'console', 'tv', 'watch', 'xr', 'other',
];

// shop_type → allowed device categories. Keys cover both the onboarding enum
// (phone_repair / computer_repair / watch_repair / general_electronics) and
// the looser strings seedDefaults.ts normalises around (it_service, mixed,
// console_pc, etc.) so any historical store_config value resolves cleanly.
const SHOP_TYPE_CATEGORIES: Record<string, DeviceCategory[]> = {
  phone_repair:        ['phone', 'tablet', 'other'],
  phone:               ['phone', 'tablet', 'other'],
  computer_repair:     ['laptop', 'desktop', 'other'],
  it_service:          ['laptop', 'desktop', 'other'],
  it:                  ['laptop', 'desktop', 'other'],
  computer:            ['laptop', 'desktop', 'other'],
  laptop:              ['laptop', 'desktop', 'other'],
  console_pc:          ['laptop', 'desktop', 'console', 'other'],
  console:             ['console', 'other'],
  tv:                  ['tv', 'other'],
  watch_repair:        ['watch', 'other'],
  watch:               ['watch', 'other'],
  xr:                  ['xr', 'other'],
  general_electronics: ALL_CATEGORIES,
  mixed:               ALL_CATEGORIES,
  multi_device:        ALL_CATEGORIES,
  'multi-device':      ALL_CATEGORIES,
  all:                 ALL_CATEGORIES,
};

// Conservative baseline before shop_type is configured: phone-only.
// Phone repair is ~70% of independent shops; expanding later is one
// `set-shop-type` POST + a server restart away.
const DEFAULT_CATEGORIES: DeviceCategory[] = ['phone', 'tablet', 'other'];

function readShopType(db: any): string | null {
  // Prefer store_config (the canonical key writers use after onboarding); fall
  // back to onboarding_state for shops still mid-wizard.
  try {
    const row = db.prepare("SELECT value FROM store_config WHERE key = 'shop_type'").get() as { value?: string } | undefined;
    if (row?.value) return row.value.trim();
  } catch { /* table may not exist yet on a brand-new DB */ }
  try {
    const row = db.prepare("SELECT shop_type FROM onboarding_state WHERE id = 1").get() as { shop_type?: string } | undefined;
    if (row?.shop_type) return row.shop_type.trim();
  } catch { /* same */ }
  return null;
}

function allowedCategoriesFor(shopType: string | null): Set<DeviceCategory> {
  if (!shopType) return new Set(DEFAULT_CATEGORIES);
  const normalised = shopType.toLowerCase().replace(/\s+/g, '_');
  const list = SHOP_TYPE_CATEGORIES[normalised];
  return new Set(list ?? DEFAULT_CATEGORIES);
}

export function seedDeviceModels(db: any): void {
  const shopType = readShopType(db);
  const allowed = allowedCategoriesFor(shopType);
  const eligibleModels = DEVICE_MODELS.filter((d) => allowed.has(d.category));

  const mfrCount = (db.prepare('SELECT COUNT(*) as n FROM manufacturers').get() as { n: number }).n;
  const modelCount = (db.prepare('SELECT COUNT(*) as n FROM device_models').get() as { n: number }).n;
  const seededSlugs = eligibleModels.map((d) => d.slug);
  const missingReleaseYears = seededSlugs.length === 0
    ? 0
    : (db.prepare(`
        SELECT COUNT(*) as n
        FROM device_models
        WHERE release_year IS NULL
          AND slug IN (${seededSlugs.map(() => '?').join(',')})
      `).get(...seededSlugs) as { n: number }).n;

  // INSERT OR IGNORE is cheap, but skipping the prepare/transaction work
  // when there's no diff keeps boot logs quiet on warm starts.
  const eligibleAlreadyPresent = seededSlugs.length === 0
    ? 0
    : (db.prepare(`
        SELECT COUNT(*) as n
        FROM device_models
        WHERE slug IN (${seededSlugs.map(() => '?').join(',')})
      `).get(...seededSlugs) as { n: number }).n;

  if (
    mfrCount >= MANUFACTURERS.length
    && eligibleAlreadyPresent >= eligibleModels.length
    && missingReleaseYears === 0
  ) return;

  console.log(
    `[seed] Seeding device models for shop_type=${shopType ?? '(unset → phone baseline)'} `
    + `(have ${mfrCount} mfrs/${modelCount} models; eligible ${eligibleModels.length} of ${DEVICE_MODELS.length})...`,
  );

  const insertMfr = db.prepare(
    `INSERT OR IGNORE INTO manufacturers (name, slug) VALUES (?, ?)`
  );
  const insertModel = db.prepare(
    `INSERT OR IGNORE INTO device_models
       (manufacturer_id, name, slug, category, release_year, is_popular)
     VALUES (?, ?, ?, ?, ?, ?)`
  );
  const backfillReleaseYear = db.prepare(
    `UPDATE device_models
        SET release_year = ?
      WHERE slug = ?
        AND release_year IS NULL`
  );
  const lookupMfr = db.prepare('SELECT id FROM manufacturers WHERE slug = ?');

  const seed = db.transaction(() => {
    for (const m of MANUFACTURERS) {
      insertMfr.run(m.name, m.slug);
    }

    for (const d of eligibleModels) {
      const mfr = lookupMfr.get(d.manufacturer_slug) as { id: number } | undefined;
      if (!mfr) {
        console.warn(`[seed] Unknown manufacturer slug: ${d.manufacturer_slug}`);
        continue;
      }
      insertModel.run(mfr.id, d.name, d.slug, d.category, d.release_year, d.is_popular ? 1 : 0);
      backfillReleaseYear.run(d.release_year, d.slug);
    }
  });

  seed();
  console.log(`[seed] Seeded ${MANUFACTURERS.length} manufacturers, ${eligibleModels.length} device models (skipped ${DEVICE_MODELS.length - eligibleModels.length} out-of-scope).`);
}
