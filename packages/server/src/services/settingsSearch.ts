import type { AsyncDb } from '../db/async-db.js';
import { escapeLike } from '../utils/query.js';

export interface SettingsSearchResult {
  id: number;
  display: string;
  type: 'setting';
  subtitle: string;
  pagePath: string;
}

interface SettingsCatalogEntry {
  key: string;
  label: string;
  tab: string;
  tabLabel: string;
  description: string;
  keywords: string[];
}

const SETTINGS_TABS: readonly SettingsCatalogEntry[] = Object.freeze([
  tabEntry('setup-progress', 'Setup Progress', 'Track which setup tasks are finished or still need attention.', ['setup', 'wizard', 'onboarding']),
  tabEntry('store', 'Store Info', 'Business profile, branding, browser appearance, referral sources, and integrations.', ['business', 'shop', 'company', 'appearance', 'theme']),
  tabEntry('billing', 'Billing & Plan', 'Subscription, plan, and billing settings.', ['subscription', 'plan', 'upgrade']),
  tabEntry('statuses', 'Ticket Statuses', 'Repair workflow status labels and order.', ['ticket statuses', 'workflow']),
  tabEntry('tax', 'Tax Classes', 'Tax rates and default tax behavior.', ['tax rate', 'sales tax']),
  tabEntry('payment', 'Payment Methods', 'Cash, card, store credit, and checkout payment methods.', ['payments', 'tender']),
  tabEntry('payment-terminal', 'Payment Processing', 'Payment terminal and processor configuration.', ['terminal', 'stripe', 'blockchyp', 'processor']),
  tabEntry('customer-groups', 'Customer Groups', 'Customer group labels and discounts.', ['groups', 'vip', 'discount']),
  tabEntry('users', 'Users', 'Employee accounts, roles, and PINs.', ['employees', 'staff', 'roles', 'pin']),
  tabEntry('repair-pricing', 'Repair Pricing', 'Repair pricing rules, margins, and tiers.', ['repair prices', 'margin', 'labor']),
  tabEntry('device-templates', 'Device Templates', 'Reusable device templates for repair intake.', ['devices', 'templates']),
  tabEntry('tickets-repairs', 'Tickets & Repairs', 'Ticket, repair, warranty, and intake settings.', ['repair settings', 'warranty', 'intake']),
  tabEntry('pos', 'POS', 'Point-of-sale checkout behavior and register settings.', ['point of sale', 'register', 'checkout']),
  tabEntry('invoices', 'Invoices', 'Invoice defaults, numbering, and customer-facing invoice behavior.', ['billing documents']),
  tabEntry('receipts', 'Receipts', 'Receipt printing, headers, footers, and templates.', ['thermal', 'printer', 'receipt printer']),
  tabEntry('conditions', 'Conditions', 'Pre-repair and post-repair condition checklists.', ['checklist', 'damage']),
  tabEntry('notifications', 'Notifications', 'SMS and email templates, reminders, and customer notifications.', ['templates', 'reminders', 'alerts']),
  tabEntry('sms-voice', 'SMS & Voice', 'SMS, MMS, voice provider, and calling settings.', ['texting', 'phone', 'twilio', 'voice']),
  tabEntry('automations', 'Automations', 'Workflow automation rules and triggers.', ['workflows', 'rules']),
  tabEntry('membership', 'Membership', 'Membership tiers and recurring customer benefits.', ['subscriptions', 'members']),
  tabEntry('data', 'Data', 'Imports, exports, migrations, retention, and data maintenance.', ['import', 'export', 'migration', 'privacy']),
  tabEntry('audit-logs', 'Audit Logs', 'Security and account activity history.', ['audit', 'security', 'history']),
  tabEntry('danger-zone', 'Danger Zone', 'Destructive account and tenant actions.', ['delete', 'terminate', 'cancel']),
]);

const SETTINGS_CATALOG: readonly SettingsCatalogEntry[] = Object.freeze([
  ...SETTINGS_TABS,
  {
    key: 'ui_theme',
    label: 'Appearance Theme',
    tab: 'store',
    tabLabel: 'Store Info',
    description: 'Switch this browser between Light, Dark, or System theme.',
    keywords: ['appearance', 'theme', 'mode', 'dark mode', 'light mode', 'dark/light', 'light/dark', 'night mode', 'day mode', 'system theme', 'display', 'ui', 'color scheme'],
  },
  {
    key: 'keyboard_shortcuts_enabled',
    label: 'Keyboard Shortcuts',
    tab: 'store',
    tabLabel: 'Store Info',
    description: 'Enable or disable single-key shortcuts for this browser.',
    keywords: ['hotkeys', 'shortcuts', 'keyboard', 'f2', 'f3', 'f4', 'f6', 'assistive technology', 'accessibility'],
  },
]);

function tabEntry(tab: string, label: string, description: string, keywords: string[] = []): SettingsCatalogEntry {
  return {
    key: `settings_tab_${tab}`,
    label,
    tab,
    tabLabel: label,
    description,
    keywords,
  };
}

function humanizeConfigKey(key: string): string {
  return key
    .replace(/^store_/, 'store ')
    .replace(/^sms_/, 'sms ')
    .replace(/^pos_/, 'pos ')
    .replace(/^ticket_/, 'ticket ')
    .replace(/^invoice_/, 'invoice ')
    .replace(/^receipt_/, 'receipt ')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (ch) => ch.toUpperCase());
}

function inferTabForConfigKey(key: string): { tab: string; tabLabel: string } {
  if (key.startsWith('pos_')) return { tab: 'pos', tabLabel: 'POS' };
  if (key.startsWith('sms_') || key.startsWith('voice_') || key.includes('twilio') || key.includes('telnyx')) return { tab: 'sms-voice', tabLabel: 'SMS & Voice' };
  if (key.startsWith('ticket_') || key.includes('warranty') || key.includes('repair')) return { tab: 'tickets-repairs', tabLabel: 'Tickets & Repairs' };
  if (key.startsWith('invoice_') || key.includes('estimate')) return { tab: 'invoices', tabLabel: 'Invoices' };
  if (key.startsWith('receipt_')) return { tab: 'receipts', tabLabel: 'Receipts' };
  if (key.includes('tax')) return { tab: 'tax', tabLabel: 'Tax Classes' };
  if (key.includes('payment') || key.includes('stripe') || key.includes('blockchyp')) return { tab: 'payment-terminal', tabLabel: 'Payment Processing' };
  if (key.includes('backup') || key.includes('import') || key.includes('retention')) return { tab: 'data', tabLabel: 'Data' };
  return { tab: 'store', tabLabel: 'Store Info' };
}

function matchesEntry(entry: SettingsCatalogEntry, tokens: readonly string[]): boolean {
  const haystack = [
    entry.key,
    entry.label,
    entry.tab,
    entry.tabLabel,
    entry.description,
    ...entry.keywords,
  ].join(' ').toLowerCase();
  return tokens.every((token) => haystack.includes(token));
}

function toResult(entry: SettingsCatalogEntry, id: number): SettingsSearchResult {
  return {
    id,
    display: entry.label,
    type: 'setting',
    subtitle: `Settings > ${entry.tabLabel} - ${entry.description}`,
    pagePath: `/settings/${entry.tab}#setting-${encodeURIComponent(entry.key)}`,
  };
}

export async function searchSettings(adb: AsyncDb, query: string, limit = 10): Promise<SettingsSearchResult[]> {
  const q = query.trim().toLowerCase();
  if (q.length < 3) return [];
  const tokens = q.split(/\s+/).filter(Boolean).slice(0, 8);
  if (tokens.length === 0) return [];

  const results: SettingsSearchResult[] = [];
  const seen = new Set<string>();

  for (const entry of SETTINGS_CATALOG) {
    if (!matchesEntry(entry, tokens)) continue;
    results.push(toResult(entry, results.length + 1));
    seen.add(entry.key);
    if (results.length >= limit) return results;
  }

  const like = `%${escapeLike(query)}%`;
  const rows = await adb.all<{ key: string }>(`
    SELECT key
    FROM store_config
    WHERE key LIKE ? ESCAPE '\\'
    ORDER BY key ASC
    LIMIT ?
  `, like, Math.max(0, limit - results.length));

  for (const row of rows) {
    if (seen.has(row.key)) continue;
    const tab = inferTabForConfigKey(row.key);
    results.push({
      id: results.length + 1,
      display: humanizeConfigKey(row.key),
      type: 'setting',
      subtitle: `Settings > ${tab.tabLabel} - Saved configuration key: ${row.key}`,
      pagePath: `/settings/${tab.tab}#setting-${encodeURIComponent(row.key)}`,
    });
    if (results.length >= limit) break;
  }

  return results;
}
