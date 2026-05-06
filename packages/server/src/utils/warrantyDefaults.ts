import type { AsyncDb } from '../db/async-db.js';

type WarrantyCategory = 'screen' | 'battery' | 'charge_port' | 'back_glass' | 'camera';

const CATEGORY_KEYS: Record<WarrantyCategory, string> = {
  screen: 'warranty_default_months_screen',
  battery: 'warranty_default_months_battery',
  charge_port: 'warranty_default_months_charge_port',
  back_glass: 'warranty_default_months_back_glass',
  camera: 'warranty_default_months_camera',
};

const CONFIG_KEYS = [
  ...Object.values(CATEGORY_KEYS),
  'repair_default_warranty_value',
  'repair_default_warranty_unit',
];

export interface RepairWarrantyDefaults {
  categoryDays: Partial<Record<WarrantyCategory, number>>;
  fallbackDays: number;
}

function parseNonNegativeInt(value: string | null | undefined): number | null {
  if (value == null || value.trim() === '') return null;
  const parsed = Number.parseInt(value, 10);
  if (!Number.isFinite(parsed) || parsed < 0) return null;
  return parsed;
}

function legacyValueToDays(value: string | null | undefined, unit: string | null | undefined): number {
  const parsed = parseNonNegativeInt(value) ?? 0;
  if (unit === 'years') return parsed * 365;
  if (unit === 'months') return parsed * 30;
  if (unit === 'weeks') return parsed * 7;
  return parsed;
}

function detectWarrantyCategory(device: Record<string, any>): WarrantyCategory | null {
  const haystack = [
    device.service_name,
    device.service?.name,
    device.repair_service_name,
    device.device_type,
    device.category,
    device.issue,
  ]
    .filter((value) => typeof value === 'string')
    .join(' ')
    .toLowerCase();

  if (!haystack) return null;
  if (/\b(back|rear)\s+(glass|cover|housing)\b/.test(haystack)) return 'back_glass';
  if (/\b(charge|charging|charger|dock)\s*(port|connector)?\b/.test(haystack)) return 'charge_port';
  if (/\bbattery\b/.test(haystack)) return 'battery';
  if (/\b(camera|lens)\b/.test(haystack)) return 'camera';
  if (/\b(screen|display|lcd|digitizer)\b/.test(haystack)) return 'screen';
  return null;
}

export async function getRepairWarrantyDefaults(adb: AsyncDb): Promise<RepairWarrantyDefaults> {
  const rows = await adb.all<{ key: string; value: string }>(
    `SELECT key, value FROM store_config WHERE key IN (${CONFIG_KEYS.map(() => '?').join(',')})`,
    ...CONFIG_KEYS,
  );
  const values = new Map(rows.map((row) => [row.key, row.value]));
  const categoryDays: Partial<Record<WarrantyCategory, number>> = {};

  for (const [category, key] of Object.entries(CATEGORY_KEYS) as Array<[WarrantyCategory, string]>) {
    const months = parseNonNegativeInt(values.get(key));
    if (months != null) categoryDays[category] = months * 30;
  }

  return {
    categoryDays,
    fallbackDays: legacyValueToDays(
      values.get('repair_default_warranty_value'),
      values.get('repair_default_warranty_unit'),
    ),
  };
}

export function resolveRepairWarrantyDays(
  defaults: RepairWarrantyDefaults,
  device: Record<string, any>,
): number {
  const category = detectWarrantyCategory(device);
  if (category && defaults.categoryDays[category] != null) {
    return defaults.categoryDays[category] as number;
  }
  return defaults.fallbackDays;
}
