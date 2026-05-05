/**
 * settingsDeadToggles — curated list of store_config keys whose UI toggle
 * exists but whose backend does NOTHING with the value. CLAUDE.md explicitly
 * warns that "65 of 70 settings toggles do nothing", and §50 of the pre-launch
 * audit calls this a "massive trust problem".
 *
 * The list here is authoritative for the UI: any key listed as dead is either
 *   1. Annotated with a "Coming Soon" badge (dev-mode default), OR
 *   2. Hidden from the UI entirely (production default).
 *
 * How it relates to settingsMetadata.ts:
 *   - settingsMetadata.ts already carries a `status` field ('live' | 'beta' |
 *     'coming_soon'). Everything here should ALSO be marked `coming_soon`
 *     there so the two sources agree — `collectDeadFromMetadata()` below
 *     performs a runtime reconciliation so drift shows up in the console.
 *   - This file exists so a product reviewer can scan a short, curated list
 *     (grouped by category) without having to `grep` the 1300-line metadata.
 *   - If you wire up a backend for one of these keys, DELETE the entry from
 *     this file AND flip its metadata `status` to 'live'. Both changes go in
 *     the same commit.
 *
 * The `FEATURE_FLAG_HIDE` export decides whether the renderer hides the
 * dead toggle entirely or just badges it — callers read this from
 * `import.meta.env.DEV` so local dev always shows the honest badges while
 * production quietly hides them.
 */

import { SETTINGS_METADATA } from './settingsMetadata';

/** Category hint used by the annotator to explain WHY the toggle is dead. */
export type DeadCategory =
  | 'not-wired'
  | 'partial-backend'
  | 'server-only'
  | 'planned'
  | 'deprecated';

export interface DeadToggleEntry {
  /** store_config key — must match settingsMetadata */
  key: string;
  /** Short reason shown in the "Coming Soon" tooltip */
  reason: string;
  /** Coarse categorization so the UI can colour/filter them */
  category: DeadCategory;
  /** Optional ticket / tracking reference if one exists */
  ticketRef?: string;
}

/**
 * Curated list — keep this short-lined and GROUPED so reviewers can eyeball
 * which subsystems are lying. Order is cosmetic only (rendering is by key).
 */
const DEAD_TOGGLES: DeadToggleEntry[] = [
  // ── Theme / branding ────────────────────────────────────────────────────
  {
    key: 'theme_primary_color',
    reason: 'UI stores the color but only a handful of components honor it.',
    category: 'partial-backend',
  },

  // ── 3CX voice integration ───────────────────────────────────────────────
  {
    key: 'tcx_host',
    reason: '3CX PBX client is not implemented on the server yet.',
    category: 'not-wired',
  },
  {
    key: 'tcx_username',
    reason: 'Stored but never read by any backend service.',
    category: 'not-wired',
  },
  {
    key: 'tcx_extension',
    reason: 'Stored but never read by any backend service.',
    category: 'not-wired',
  },

  // ── Leads / notifications automation ────────────────────────────────────
  {
    key: 'lead_auto_assign',
    reason: 'Leads module exists but round-robin assignment is not wired.',
    category: 'planned',
  },
  {
    key: 'estimate_followup_days',
    reason: 'Value is saved but no cron job reads it.',
    category: 'not-wired',
  },

  // ── Per-toggle receipt flags we know are UI-only ────────────────────────
  // These ship as 'coming_soon' in settingsMetadata. Add more as they are
  // discovered during the pre-launch audit sweep.
];

/** Quick lookup set for O(1) isDead() checks. */
const DEAD_KEYS: ReadonlySet<string> = new Set(DEAD_TOGGLES.map((t) => t.key));

/**
 * Feature flag driving the hide-vs-badge decision.
 *   - In production (`DEV=false`) we hide dead toggles entirely. Users should
 *     never have to see a "Coming Soon" switch in their live shop.
 *   - In development (`DEV=true`) we show them with a visible amber badge so
 *     engineers can audit coverage and product can triage.
 *
 * Tests can override this by importing `setHideDeadToggles` below.
 */
let hideFlag: boolean = typeof import.meta !== 'undefined' && 'env' in import.meta
  ? !(import.meta as unknown as { env?: { DEV?: boolean } }).env?.DEV
  : true;

/** Testing / storybook override — flip the hide flag at runtime. */
export function setHideDeadToggles(hide: boolean): void {
  hideFlag = hide;
}

/** Current value of the hide-vs-badge flag. */
export function shouldHideDeadToggles(): boolean {
  return hideFlag;
}

/** True if the given store_config key is on the curated dead-toggle list. */
export function isDeadToggle(key: string): boolean {
  return DEAD_KEYS.has(key);
}

/** Returns the curated entry for a given key, or null. */
export function getDeadToggleEntry(key: string): DeadToggleEntry | null {
  return DEAD_TOGGLES.find((t) => t.key === key) ?? null;
}

/** Full curated list — sorted by category for readability in the UI. */
export function getAllDeadToggles(): DeadToggleEntry[] {
  return [...DEAD_TOGGLES].sort((a, b) => {
    if (a.category === b.category) return a.key.localeCompare(b.key);
    return a.category.localeCompare(b.category);
  });
}

/**
 * Runtime reconciliation — pulls every setting in settingsMetadata.ts that
 * is marked `coming_soon` but is NOT in the curated list above. This lets
 * callers (e.g. a dev-tools panel) surface drift between the two sources so
 * the product team can triage.
 */
export function findMetadataOnlyDeadKeys(): string[] {
  const missing: string[] = [];
  for (const s of SETTINGS_METADATA) {
    if (s.status !== 'coming_soon') continue;
    if (!DEAD_KEYS.has(s.key)) missing.push(s.key);
  }
  return missing;
}

/**
 * Reverse check — curated entries that don't correspond to any real
 * settingsMetadata definition. Usually indicates a typo or a setting that
 * was renamed without updating this file.
 */
export function findOrphanDeadKeys(): string[] {
  const known = new Set(SETTINGS_METADATA.map((s) => s.key));
  return DEAD_TOGGLES.filter((t) => !known.has(t.key)).map((t) => t.key);
}
