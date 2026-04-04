/**
 * Seeds manufacturers and device_models from the static dataset.
 * Runs on every startup (idempotent — uses INSERT OR IGNORE).
 */
import db from './connection.js';
import { MANUFACTURERS, DEVICE_MODELS } from './device-models-seed.js';

export function seedDeviceModels(): void {
  const mfrCount = (db.prepare('SELECT COUNT(*) as n FROM manufacturers').get() as { n: number }).n;
  const modelCount = (db.prepare('SELECT COUNT(*) as n FROM device_models').get() as { n: number }).n;

  // Always run if there are new manufacturers or models to add (INSERT OR IGNORE is idempotent)
  if (mfrCount >= MANUFACTURERS.length && modelCount >= DEVICE_MODELS.length) return;

  console.log(`[seed] Seeding device models (have ${mfrCount} mfrs/${modelCount} models, want ${MANUFACTURERS.length}/${DEVICE_MODELS.length})...`);

  const insertMfr = db.prepare(
    `INSERT OR IGNORE INTO manufacturers (name, slug) VALUES (?, ?)`
  );
  const insertModel = db.prepare(
    `INSERT OR IGNORE INTO device_models
       (manufacturer_id, name, slug, category, release_year, is_popular)
     VALUES (?, ?, ?, ?, ?, ?)`
  );

  const seed = db.transaction(() => {
    for (const m of MANUFACTURERS) {
      insertMfr.run(m.name, m.slug);
    }

    for (const d of DEVICE_MODELS) {
      const mfr = db.prepare('SELECT id FROM manufacturers WHERE slug = ?').get(d.manufacturer_slug) as { id: number } | undefined;
      if (!mfr) {
        console.warn(`[seed] Unknown manufacturer slug: ${d.manufacturer_slug}`);
        continue;
      }
      insertModel.run(mfr.id, d.name, d.slug, d.category, d.release_year ?? null, d.is_popular ? 1 : 0);
    }
  });

  seed();
  console.log(`[seed] Seeded ${MANUFACTURERS.length} manufacturers, ${DEVICE_MODELS.length} device models.`);
}
