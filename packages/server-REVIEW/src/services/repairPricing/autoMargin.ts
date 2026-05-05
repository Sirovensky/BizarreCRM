import type Database from 'better-sqlite3';

interface AutoMarginRow {
  id: number;
  device_model_id: number;
  repair_service_id: number;
  repair_service_slug: string;
  labor_price: number;
  last_supplier_cost: number;
  profit_estimate: number | null;
  tier_label: string | null;
}

export interface AutoMarginResult {
  evaluated: number;
  adjusted: number;
  skipped: number;
  preset: AutoMarginPreset;
  target_type: AutoMarginTargetType;
  target_margin_pct: number;
  target_profit_amount: number;
  calculation_basis: AutoMarginCalculationBasis;
  rounding_mode: AutoMarginRoundingMode;
  cap_pct: number;
}

export type AutoMarginRoundingMode = 'none' | 'ending_99' | 'whole_dollar' | 'ending_98';
export type AutoMarginCalculationBasis = 'gross_margin' | 'markup';
export type AutoMarginTargetType = 'percent' | 'fixed_amount';
export type AutoMarginPreset = 'high_traffic' | 'mid_traffic' | 'low_traffic' | 'custom' | 'value' | 'balanced' | 'premium';
export type AutoMarginRuleScope = 'global' | 'repair_service' | 'tier' | 'device';

export interface AutoMarginRule {
  id?: string;
  scope: AutoMarginRuleScope;
  label?: string;
  repair_service_id?: number | null;
  repair_service_slug?: string | null;
  tier?: string | null;
  device_model_id?: number | null;
  target_type?: AutoMarginTargetType;
  target_margin_pct: number;
  target_profit_amount?: number;
  calculation_basis?: AutoMarginCalculationBasis;
  rounding_mode?: AutoMarginRoundingMode;
  cap_pct?: number;
  enabled?: boolean;
}

export interface AutoMarginSettings {
  preset: AutoMarginPreset;
  target_type: AutoMarginTargetType;
  target_margin_pct: number;
  target_profit_amount: number;
  calculation_basis: AutoMarginCalculationBasis;
  rounding_mode: AutoMarginRoundingMode;
  cap_pct: number;
  rules: AutoMarginRule[];
}

export interface AutoMarginPreviewInput extends Partial<AutoMarginSettings> {
  supplier_cost: number;
  current_labor_price?: number;
  rule?: Partial<AutoMarginRule>;
}

export interface AutoMarginPreview {
  supplier_cost: number;
  current_labor_price: number | null;
  target_type: AutoMarginTargetType;
  target_margin_pct: number;
  target_profit_amount: number;
  calculation_basis: AutoMarginCalculationBasis;
  rounding_mode: AutoMarginRoundingMode;
  cap_pct: number;
  uncapped_labor_price: number;
  rounded_labor_price: number;
  capped_labor_price: number | null;
  profit_estimate: number;
  margin_pct: number;
}

const ROUNDING_MODES = new Set<AutoMarginRoundingMode>([
  'none',
  'ending_99',
  'whole_dollar',
  'ending_98',
]);
const CALCULATION_BASES = new Set<AutoMarginCalculationBasis>(['gross_margin', 'markup']);
const TARGET_TYPES = new Set<AutoMarginTargetType>(['percent', 'fixed_amount']);
const AUTO_MARGIN_PRESETS = new Set<AutoMarginPreset>([
  'high_traffic',
  'mid_traffic',
  'low_traffic',
  'custom',
  // Legacy names accepted so older web/mobile builds do not break.
  'value',
  'balanced',
  'premium',
]);

function configNumber(db: Database.Database, key: string, fallback: number): number {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  const parsed = Number(row?.value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function configString(db: Database.Database, key: string, fallback: string): string {
  const row = db.prepare('SELECT value FROM store_config WHERE key = ?').get(key) as { value?: string } | undefined;
  return typeof row?.value === 'string' && row.value.trim() ? row.value.trim() : fallback;
}

function roundMoney(value: number): number {
  return Math.round(value * 100) / 100;
}

function normalizePct(value: unknown, fallback: number, min: number, max: number): number {
  const parsed = Number(value);
  const source = Number.isFinite(parsed) ? parsed : fallback;
  return Math.max(min, Math.min(max, roundMoney(source)));
}

function normalizeCalculationBasis(value: unknown, fallback: AutoMarginCalculationBasis = 'gross_margin'): AutoMarginCalculationBasis {
  return typeof value === 'string' && CALCULATION_BASES.has(value as AutoMarginCalculationBasis)
    ? value as AutoMarginCalculationBasis
    : fallback;
}

function normalizeTargetType(value: unknown, fallback: AutoMarginTargetType = 'percent'): AutoMarginTargetType {
  return typeof value === 'string' && TARGET_TYPES.has(value as AutoMarginTargetType)
    ? value as AutoMarginTargetType
    : fallback;
}

function normalizePreset(value: unknown, fallback: AutoMarginPreset = 'custom'): AutoMarginPreset {
  return typeof value === 'string' && AUTO_MARGIN_PRESETS.has(value as AutoMarginPreset)
    ? value as AutoMarginPreset
    : fallback;
}

function normalizeRoundingMode(value: unknown, fallback: AutoMarginRoundingMode = 'ending_99'): AutoMarginRoundingMode {
  return typeof value === 'string' && ROUNDING_MODES.has(value as AutoMarginRoundingMode)
    ? value as AutoMarginRoundingMode
    : fallback;
}

function normalizeTargetPct(value: unknown, fallback: number, basis: AutoMarginCalculationBasis): number {
  return normalizePct(value, fallback, 0, basis === 'markup' ? 1000 : 95);
}

function normalizeMoney(value: unknown, fallback: number, min = 0, max = 10000): number {
  const parsed = Number(value);
  const source = Number.isFinite(parsed) ? parsed : fallback;
  return Math.max(min, Math.min(max, roundMoney(source)));
}

function readJsonArray<T>(db: Database.Database, key: string): T[] {
  const raw = configString(db, key, '[]');
  try {
    const parsed = JSON.parse(raw);
    return Array.isArray(parsed) ? parsed as T[] : [];
  } catch {
    return [];
  }
}

export function presetAutoMarginRules(
  preset: AutoMarginPreset,
  targetType: AutoMarginTargetType = 'percent',
): AutoMarginRule[] {
  const normalizedPreset = preset === 'value'
    ? 'high_traffic'
    : preset === 'premium'
      ? 'low_traffic'
      : preset === 'balanced'
        ? 'mid_traffic'
        : preset;
  const percentPresets: Record<Exclude<AutoMarginPreset, 'custom' | 'value' | 'balanced' | 'premium'>, Array<[string, number]>> = {
    high_traffic: [
      ['screen-replacement', 75],
      ['battery-replacement', 60],
      ['charging-port', 90],
      ['camera-repair', 100],
      ['back-glass', 120],
    ],
    mid_traffic: [
      ['screen-replacement', 100],
      ['battery-replacement', 80],
      ['charging-port', 120],
      ['camera-repair', 150],
      ['back-glass', 180],
    ],
    low_traffic: [
      ['screen-replacement', 150],
      ['battery-replacement', 100],
      ['charging-port', 180],
      ['camera-repair', 250],
      ['back-glass', 300],
    ],
  };
  const fixedPresets: Record<Exclude<AutoMarginPreset, 'custom' | 'value' | 'balanced' | 'premium'>, Array<[string, number]>> = {
    high_traffic: [
      ['screen-replacement', 60],
      ['battery-replacement', 35],
      ['charging-port', 55],
      ['camera-repair', 60],
      ['back-glass', 75],
    ],
    mid_traffic: [
      ['screen-replacement', 80],
      ['battery-replacement', 50],
      ['charging-port', 75],
      ['camera-repair', 90],
      ['back-glass', 105],
    ],
    low_traffic: [
      ['screen-replacement', 110],
      ['battery-replacement', 70],
      ['charging-port', 100],
      ['camera-repair', 125],
      ['back-glass', 150],
    ],
  };
  if (normalizedPreset === 'custom') return [];
  const percentValues = Object.fromEntries(percentPresets[normalizedPreset]);
  const fixedValues = Object.fromEntries(fixedPresets[normalizedPreset]);
  const source = targetType === 'fixed_amount' ? fixedPresets[normalizedPreset] : percentPresets[normalizedPreset];
  return source.map(([slug, value]) => ({
    id: `preset.${normalizedPreset}.${slug}`,
    scope: 'repair_service',
    repair_service_slug: slug,
    label: slug.replace(/-/g, ' '),
    target_type: targetType,
    target_margin_pct: percentValues[slug] ?? 100,
    target_profit_amount: targetType === 'fixed_amount' ? value : fixedValues[slug] ?? 80,
    calculation_basis: 'markup',
    rounding_mode: 'ending_99',
    cap_pct: 25,
    enabled: true,
  }));
}

function normalizeAutoMarginRule(input: Partial<AutoMarginRule>, fallback: AutoMarginSettings): AutoMarginRule | null {
  const scope = typeof input.scope === 'string' && ['global', 'repair_service', 'tier', 'device'].includes(input.scope)
    ? input.scope as AutoMarginRuleScope
    : 'global';
  const basis = normalizeCalculationBasis(input.calculation_basis, fallback.calculation_basis);
  const targetType = normalizeTargetType(input.target_type, fallback.target_type);
  const targetPct = normalizeTargetPct(input.target_margin_pct, fallback.target_margin_pct, basis);
  const rule: AutoMarginRule = {
    id: typeof input.id === 'string' && input.id.trim() ? input.id.trim() : undefined,
    scope,
    label: typeof input.label === 'string' && input.label.trim() ? input.label.trim() : undefined,
    repair_service_id: Number.isInteger(Number(input.repair_service_id)) && Number(input.repair_service_id) > 0
      ? Number(input.repair_service_id)
      : null,
    repair_service_slug: typeof input.repair_service_slug === 'string' && input.repair_service_slug.trim()
      ? input.repair_service_slug.trim()
      : null,
    tier: typeof input.tier === 'string' && input.tier.trim() ? input.tier.trim() : null,
    device_model_id: Number.isInteger(Number(input.device_model_id)) && Number(input.device_model_id) > 0
      ? Number(input.device_model_id)
      : null,
    target_type: targetType,
    target_margin_pct: targetPct,
    target_profit_amount: normalizeMoney(input.target_profit_amount, fallback.target_profit_amount),
    calculation_basis: basis,
    rounding_mode: normalizeRoundingMode(input.rounding_mode, fallback.rounding_mode),
    cap_pct: normalizePct(input.cap_pct, fallback.cap_pct, 0, 100),
    enabled: input.enabled !== false,
  };
  if (scope === 'repair_service' && !rule.repair_service_id && !rule.repair_service_slug) return null;
  if (scope === 'tier' && !rule.tier) return null;
  if (scope === 'device' && !rule.device_model_id) return null;
  return rule;
}

export function getAutoMarginSettings(db: Database.Database): AutoMarginSettings {
  const calculationBasis = normalizeCalculationBasis(
    configString(db, 'repair_pricing_auto_margin_calculation_basis', 'gross_margin'),
  );
  const settings: AutoMarginSettings = {
    preset: normalizePreset(configString(db, 'repair_pricing_auto_margin_preset', 'custom')),
    target_type: normalizeTargetType(configString(db, 'repair_pricing_auto_margin_target_type', 'percent')),
    target_margin_pct: normalizeTargetPct(
      configNumber(db, 'repair_pricing_auto_margin_target_pct', 60),
      60,
      calculationBasis,
    ),
    target_profit_amount: normalizeMoney(
      configNumber(db, 'repair_pricing_auto_margin_target_profit_amount', 80),
      80,
    ),
    calculation_basis: calculationBasis,
    rounding_mode: normalizeRoundingMode(
      configString(db, 'repair_pricing_rounding_mode', 'ending_99'),
    ),
    cap_pct: normalizePct(
      configNumber(db, 'repair_pricing_auto_margin_cap_pct', 25),
      25,
      0,
      100,
    ),
    rules: [],
  };
  settings.rules = readJsonArray<Partial<AutoMarginRule>>(db, 'repair_pricing_auto_margin_rules')
    .map(rule => normalizeAutoMarginRule(rule, settings))
    .filter((rule): rule is AutoMarginRule => Boolean(rule));
  return settings;
}

export function normalizeAutoMarginSettings(
  input: Partial<AutoMarginSettings>,
  fallback: AutoMarginSettings,
): AutoMarginSettings {
  const preset = normalizePreset(input.preset, fallback.preset);
  const calculationBasis = normalizeCalculationBasis(input.calculation_basis, fallback.calculation_basis);
  const targetType = normalizeTargetType(input.target_type, fallback.target_type);
  const baseSettings: AutoMarginSettings = {
    preset,
    target_type: targetType,
    target_margin_pct: normalizeTargetPct(input.target_margin_pct, fallback.target_margin_pct, calculationBasis),
    target_profit_amount: normalizeMoney(input.target_profit_amount, fallback.target_profit_amount),
    calculation_basis: calculationBasis,
    rounding_mode: normalizeRoundingMode(input.rounding_mode, fallback.rounding_mode),
    cap_pct: normalizePct(input.cap_pct, fallback.cap_pct, 0, 100),
    rules: [],
  };
  const inputRules = Array.isArray(input.rules) ? input.rules : undefined;
  const sourceRules = inputRules ?? ((preset !== fallback.preset || targetType !== fallback.target_type) && preset !== 'custom'
    ? presetAutoMarginRules(preset, targetType)
    : fallback.rules);
  return {
    ...baseSettings,
    preset,
    rules: sourceRules
      .map(rule => normalizeAutoMarginRule(rule, baseSettings))
      .filter((rule): rule is AutoMarginRule => Boolean(rule)),
  };
}

export function setAutoMarginSettings(
  db: Database.Database,
  input: Partial<AutoMarginSettings>,
): AutoMarginSettings {
  const settings = normalizeAutoMarginSettings(input, getAutoMarginSettings(db));
  const upsert = db.prepare('INSERT OR REPLACE INTO store_config (key, value) VALUES (?, ?)');
  const tx = db.transaction(() => {
    upsert.run('repair_pricing_auto_margin_preset', settings.preset);
    upsert.run('repair_pricing_auto_margin_target_type', settings.target_type);
    upsert.run('repair_pricing_auto_margin_target_pct', String(settings.target_margin_pct));
    upsert.run('repair_pricing_auto_margin_target_profit_amount', String(settings.target_profit_amount));
    upsert.run('repair_pricing_auto_margin_calculation_basis', settings.calculation_basis);
    upsert.run('repair_pricing_rounding_mode', settings.rounding_mode);
    upsert.run('repair_pricing_auto_margin_cap_pct', String(settings.cap_pct));
    upsert.run('repair_pricing_auto_margin_rules', JSON.stringify(settings.rules));
  });
  tx();
  return settings;
}

export function roundAutoMarginLabor(value: number, mode: AutoMarginRoundingMode): number {
  if (!Number.isFinite(value) || value <= 0) return 0;
  if (mode === 'none') return roundMoney(value);
  if (mode === 'whole_dollar') return Math.ceil(value);

  const ending = mode === 'ending_98' ? 0.98 : 0.99;
  const dollars = Math.floor(value);
  const candidate = dollars + ending;
  return roundMoney(candidate >= value ? candidate : dollars + 1 + ending);
}

export function targetLaborForMargin(
  supplierCost: number,
  targetMarginPct: number,
  roundingMode: AutoMarginRoundingMode,
  calculationBasis: AutoMarginCalculationBasis = 'gross_margin',
  targetType: AutoMarginTargetType = 'percent',
  targetProfitAmount = 0,
): { uncapped: number; rounded: number } {
  const parsedCost = Number(supplierCost);
  const cost = Number.isFinite(parsedCost) ? Math.max(0, parsedCost) : 0;
  const normalizedTargetType = normalizeTargetType(targetType);
  if (normalizedTargetType === 'fixed_amount') {
    const uncapped = roundMoney(cost + normalizeMoney(targetProfitAmount, 0));
    return {
      uncapped,
      rounded: roundAutoMarginLabor(uncapped, roundingMode),
    };
  }
  const basis = normalizeCalculationBasis(calculationBasis);
  const marginPct = normalizeTargetPct(targetMarginPct, basis === 'markup' ? 100 : 60, basis);
  const divisor = 1 - (marginPct / 100);
  const uncapped = basis === 'markup'
    ? roundMoney(cost * (1 + (marginPct / 100)))
    : divisor <= 0 ? cost : roundMoney(cost / divisor);
  return {
    uncapped,
    rounded: roundAutoMarginLabor(uncapped, roundingMode),
  };
}

export function cappedAutoMarginLabor(
  currentLabor: number,
  supplierCost: number,
  targetMarginPct: number,
  capPct: number,
  roundingMode: AutoMarginRoundingMode = 'ending_99',
  calculationBasis: AutoMarginCalculationBasis = 'gross_margin',
  targetType: AutoMarginTargetType = 'percent',
  targetProfitAmount = 0,
): number {
  const desired = targetLaborForMargin(
    supplierCost,
    targetMarginPct,
    roundingMode,
    calculationBasis,
    targetType,
    targetProfitAmount,
  ).rounded;
  if (currentLabor <= 0) return roundMoney(desired);
  const maxDelta = Math.abs(currentLabor * (capPct / 100));
  const rawDelta = desired - currentLabor;
  const cappedDelta = Math.max(-maxDelta, Math.min(maxDelta, rawDelta));
  return roundMoney(currentLabor + cappedDelta);
}

export function previewAutoMargin(
  input: AutoMarginPreviewInput,
  fallback: AutoMarginSettings,
): AutoMarginPreview {
  const settings = normalizeAutoMarginSettings({
    ...input,
    ...(input.rule ?? {}),
  }, fallback);
  const parsedSupplierCost = Number(input.supplier_cost);
  const supplierCost = roundMoney(Number.isFinite(parsedSupplierCost) ? Math.max(0, parsedSupplierCost) : 0);
  const currentLabor = input.current_labor_price === undefined || input.current_labor_price === null
    ? null
    : roundMoney(Math.max(0, Number(input.current_labor_price)));
  const target = targetLaborForMargin(
    supplierCost,
    settings.target_margin_pct,
    settings.rounding_mode,
    settings.calculation_basis,
    settings.target_type,
    settings.target_profit_amount,
  );
  const cappedLabor = currentLabor === null
    ? null
    : cappedAutoMarginLabor(
      currentLabor,
      supplierCost,
      settings.target_margin_pct,
      settings.cap_pct,
      settings.rounding_mode,
      settings.calculation_basis,
      settings.target_type,
      settings.target_profit_amount,
    );
  const finalLabor = cappedLabor ?? target.rounded;
  const profitEstimate = roundMoney(finalLabor - supplierCost);

  return {
    supplier_cost: supplierCost,
    current_labor_price: currentLabor,
    target_type: settings.target_type,
    target_margin_pct: settings.target_margin_pct,
    target_profit_amount: settings.target_profit_amount,
    calculation_basis: settings.calculation_basis,
    rounding_mode: settings.rounding_mode,
    cap_pct: settings.cap_pct,
    uncapped_labor_price: target.uncapped,
    rounded_labor_price: target.rounded,
    capped_labor_price: cappedLabor,
    profit_estimate: profitEstimate,
    margin_pct: finalLabor > 0 ? roundMoney((profitEstimate / finalLabor) * 100) : 0,
  };
}

function ruleSpecificity(row: AutoMarginRow, rule: AutoMarginRule): number {
  if (rule.enabled === false) return -1;
  let score = 0;
  if (rule.device_model_id) {
    if (rule.device_model_id !== row.device_model_id) return -1;
    score += 100;
  }
  if (rule.repair_service_id) {
    if (rule.repair_service_id !== row.repair_service_id) return -1;
    score += 20;
  }
  if (rule.repair_service_slug) {
    if (rule.repair_service_slug !== row.repair_service_slug) return -1;
    score += 15;
  }
  if (rule.tier) {
    if (rule.tier !== row.tier_label) return -1;
    score += 10;
  }
  if (rule.scope === 'repair_service' && score < 15) return -1;
  if (rule.scope === 'tier' && score < 10) return -1;
  if (rule.scope === 'device' && score < 100) return -1;
  return score;
}

function settingsForRow(row: AutoMarginRow, settings: AutoMarginSettings): AutoMarginSettings {
  let best: AutoMarginRule | null = null;
  let bestScore = -1;
  settings.rules.forEach((rule, index) => {
    const score = ruleSpecificity(row, rule);
    const tieBreaker = score >= 0 ? score + ((settings.rules.length - index) / 1000) : score;
    if (tieBreaker > bestScore) {
      bestScore = tieBreaker;
      best = rule;
    }
  });
  const selected = best as AutoMarginRule | null;
  if (!selected) return settings;
  return {
    ...settings,
    target_type: selected.target_type ?? settings.target_type,
    target_margin_pct: selected.target_margin_pct,
    target_profit_amount: selected.target_profit_amount ?? settings.target_profit_amount,
    calculation_basis: selected.calculation_basis ?? settings.calculation_basis,
    rounding_mode: selected.rounding_mode ?? settings.rounding_mode,
    cap_pct: selected.cap_pct ?? settings.cap_pct,
  };
}

export function runAutoMargin(db: Database.Database): AutoMarginResult {
  const settings = getAutoMarginSettings(db);
  const rows = db.prepare(`
    SELECT rp.id, rp.device_model_id, rp.repair_service_id, rs.slug AS repair_service_slug,
           rp.labor_price, rp.last_supplier_cost, rp.profit_estimate, rp.tier_label
    FROM repair_prices rp
    JOIN repair_services rs ON rs.id = rp.repair_service_id
    WHERE rp.auto_margin_enabled = 1
      AND rp.is_custom = 0
      AND rp.is_active = 1
      AND rp.last_supplier_cost IS NOT NULL
      AND rp.last_supplier_cost > 0
      AND rp.auto_margin_paused_at IS NULL
  `).all() as AutoMarginRow[];

  const updateStmt = db.prepare(`
    UPDATE repair_prices
    SET labor_price = ?,
        suggested_labor_price = ?,
        profit_estimate = ?,
        updated_at = datetime('now')
    WHERE id = ?
  `);
  const auditStmt = db.prepare(`
    INSERT INTO repair_prices_audit (
      repair_price_id, device_model_id, repair_service_id,
      old_labor_price, new_labor_price, old_is_custom, new_is_custom,
      supplier_cost, profit_estimate, source, note
    )
    VALUES (?, ?, ?, ?, ?, 0, 0, ?, ?, 'auto-margin', ?)
  `);

  let adjusted = 0;
  let skipped = 0;

  const tx = db.transaction(() => {
    for (const row of rows) {
      const rowSettings = settingsForRow(row, settings);
      const target = targetLaborForMargin(
        row.last_supplier_cost,
        rowSettings.target_margin_pct,
        rowSettings.rounding_mode,
        rowSettings.calculation_basis,
        rowSettings.target_type,
        rowSettings.target_profit_amount,
      );
      const nextLabor = cappedAutoMarginLabor(
        row.labor_price,
        row.last_supplier_cost,
        rowSettings.target_margin_pct,
        rowSettings.cap_pct,
        rowSettings.rounding_mode,
        rowSettings.calculation_basis,
        rowSettings.target_type,
        rowSettings.target_profit_amount,
      );
      if (Math.abs(nextLabor - row.labor_price) < 0.01) {
        skipped += 1;
        continue;
      }

      const nextProfit = roundMoney(nextLabor - row.last_supplier_cost);
      updateStmt.run(nextLabor, target.rounded, nextProfit, row.id);
      auditStmt.run(
        row.id,
        row.device_model_id,
        row.repair_service_id,
        row.labor_price,
        nextLabor,
        row.last_supplier_cost,
        nextProfit,
        rowSettings.target_type === 'fixed_amount'
          ? `Auto-margin target $${rowSettings.target_profit_amount} profit, ${rowSettings.rounding_mode}, capped at ${rowSettings.cap_pct}% per run`
          : `Auto-margin target ${rowSettings.target_margin_pct}% ${rowSettings.calculation_basis}, ${rowSettings.rounding_mode}, capped at ${rowSettings.cap_pct}% per run`,
      );
      adjusted += 1;
    }
  });

  tx();
  return {
    evaluated: rows.length,
    adjusted,
    skipped,
    preset: settings.preset,
    target_type: settings.target_type,
    target_margin_pct: settings.target_margin_pct,
    target_profit_amount: settings.target_profit_amount,
    calculation_basis: settings.calculation_basis,
    rounding_mode: settings.rounding_mode,
    cap_pct: settings.cap_pct,
  };
}
