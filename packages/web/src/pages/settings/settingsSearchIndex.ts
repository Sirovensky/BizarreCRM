/**
 * settingsSearchIndex — a flat, cached index of every searchable setting
 * (label, tab, tooltip, keywords) derived from settingsMetadata.ts plus local
 * browser preferences that do not live in store_config.
 *
 * Why a separate file?
 *   - settingsMetadata.ts already holds the full definitions, but its helper
 *     `searchSettings()` walks the full array on every keystroke. For the new
 *     command-palette style global search we want a tokenized/pre-lowered
 *     index so the search stays snappy even on a phone.
 *   - Keeping the index in its own module lets SettingsGlobalSearch stay dumb
 *     (it just filters over IndexEntry[]) and lets future work (URL deeplinks,
 *     hash-based jump-to-setting, keyboard-shortcut registration) hook in
 *     without touching the metadata file.
 *
 * The index is deliberately shallow — it ONLY contains what the search palette
 * needs to render a result card. The authoritative source of a store_config
 * setting's default / status / type is still settingsMetadata.
 */

import {
  SETTINGS_METADATA,
  type SettingDef,
  type SettingStatus,
} from './settingsMetadata';

/** One row in the static search index — compact, pre-lowered. */
export interface SettingsIndexEntry {
  /** store_config key (e.g. "receipt_footer") — stable identifier */
  key: string;
  /** Human-readable label shown in the result card */
  label: string;
  /** Tab ID the search palette should navigate to */
  tab: string;
  /** Short tooltip / description rendered under the label */
  description: string;
  /** Honest lifecycle — drives the Live / Beta / Soon pill */
  status: SettingStatus;
  /** Pre-lowered haystack — used once per keystroke */
  haystack: string;
  /** Optional keywords that only appear in the index (not shown to users) */
  keywords: string[];
}

type LocalSettingEntry = Omit<SettingsIndexEntry, 'haystack'>;

const LOCAL_SETTING_ENTRIES: readonly LocalSettingEntry[] = Object.freeze([
  {
    key: 'ui_theme',
    label: 'Appearance Theme',
    tab: 'store',
    description: 'Switch this browser between Light, Dark, or System theme.',
    status: 'live',
    keywords: [
      'appearance',
      'theme',
      'mode',
      'dark',
      'dark mode',
      'dark/light',
      'light',
      'light mode',
      'light/dark',
      'night mode',
      'day mode',
      'system',
      'system theme',
      'switch',
      'toggle',
      'display',
      'ui',
      'color scheme',
    ],
  },
  {
    key: 'keyboard_shortcuts_enabled',
    label: 'Keyboard Shortcuts',
    tab: 'store',
    description: 'Enable or disable single-key shortcuts for this browser.',
    status: 'live',
    keywords: [
      'hotkeys',
      'shortcuts',
      'keyboard',
      'f2',
      'f3',
      'f4',
      'f6',
      'assistive technology',
      'accessibility',
    ],
  },
]);

/** Module-scope index built once at import time and reused on every search. */
const INDEX: readonly SettingsIndexEntry[] = Object.freeze(
  [
    ...SETTINGS_METADATA.map(buildEntry),
    ...LOCAL_SETTING_ENTRIES.map(buildLocalEntry),
  ]
);

function buildEntry(setting: SettingDef): SettingsIndexEntry {
  const keywords = setting.keywords ?? [];
  const haystackTokens = [
    setting.label,
    setting.tooltip,
    setting.tab,
    setting.key,
    ...keywords,
  ].filter((t): t is string => typeof t === 'string' && t.length > 0);
  return {
    key: setting.key,
    label: setting.label,
    tab: setting.tab,
    description: setting.tooltip,
    status: setting.status,
    keywords,
    haystack: haystackTokens.join(' ').toLowerCase(),
  };
}

function buildLocalEntry(entry: LocalSettingEntry): SettingsIndexEntry {
  const haystackTokens = [
    entry.label,
    entry.description,
    entry.tab,
    entry.key,
    ...entry.keywords,
  ].filter((t): t is string => typeof t === 'string' && t.length > 0);
  return {
    ...entry,
    haystack: haystackTokens.join(' ').toLowerCase(),
  };
}

/** Returns the full static index. */
export function getSettingsIndex(): readonly SettingsIndexEntry[] {
  return INDEX;
}

/** Total number of searchable settings (useful for empty-state copy). */
export function getSettingsIndexSize(): number {
  return INDEX.length;
}

/**
 * Case-insensitive multi-token search — every whitespace-separated token in
 * the query must appear somewhere in the haystack. Matches are returned in
 * their original metadata order (stable across keystrokes).
 */
export function queryIndex(rawQuery: string, limit = 20): SettingsIndexEntry[] {
  const query = rawQuery.trim().toLowerCase();
  if (!query) return [];
  const tokens = query.split(/\s+/).filter((t) => t.length > 0);
  if (tokens.length === 0) return [];

  const out: SettingsIndexEntry[] = [];
  for (const entry of INDEX) {
    if (!matchesAllTokens(entry.haystack, tokens)) continue;
    out.push(entry);
    if (out.length >= limit) break;
  }
  return out;
}

function matchesAllTokens(haystack: string, tokens: readonly string[]): boolean {
  for (const token of tokens) {
    if (!haystack.includes(token)) return false;
  }
  return true;
}

/**
 * Convenience lookup used by tab-deep-linking: given a key, tell the caller
 * which tab to navigate to. Falls back to `null` for unknown keys so callers
 * can decide how to handle it (e.g., show a toast).
 */
export function findTabForSettingKey(key: string): string | null {
  const hit = INDEX.find((entry) => entry.key === key);
  return hit ? hit.tab : null;
}

/**
 * Returns the set of distinct tab IDs currently referenced by the index.
 * Useful for building tab-filter chips in the search palette UI without
 * hardcoding the list in two places.
 */
export function getIndexedTabIds(): string[] {
  const seen = new Set<string>();
  for (const entry of INDEX) seen.add(entry.tab);
  return Array.from(seen);
}
