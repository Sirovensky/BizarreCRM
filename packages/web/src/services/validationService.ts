/**
 * Centralised, reusable field validators for the setup wizard and settings forms.
 *
 * Every function takes a value and returns:
 *   null    — valid
 *   string  — error message to show below the field
 */

// ── Basic store fields ────────────────────────────────────────────────────────

export const validateStoreName = (v: string): string | null =>
  v.trim().length < 3 ? 'Store name must be at least 3 characters' : null;

export const validateStoreAddress = (v: string): string | null =>
  v.trim().length < 10 ? 'Enter a complete street address' : null;

export const validatePhoneInternational = (v: string): string | null => {
  const digits = v.replace(/\D/g, '');
  return digits.length < 10 || digits.length > 15 ? 'Phone must be 10–15 digits' : null;
};

export const validateEmail = (v: string): string | null =>
  /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(v) ? null : 'Invalid email address';

// ── Branding ──────────────────────────────────────────────────────────────────

export const validateHexColor = (v: string): string | null =>
  /^#[0-9a-fA-F]{6}$/.test(v) ? null : 'Use #RRGGBB hex format';

// ── Business hours ────────────────────────────────────────────────────────────

/**
 * Validates that a closing time is strictly after the opening time.
 * Times are compared lexicographically — works correctly for HH:MM 24-hour strings.
 */
export const validateBusinessHours = (open: string, close: string): string | null =>
  close <= open ? '"Closes" must be after "Opens"' : null;

// ── SMTP ──────────────────────────────────────────────────────────────────────

/** Standard SMTP ports. 25 = plain relay, 465 = implicit TLS, 587 = STARTTLS, 993/995 = IMAP/POP over TLS. */
export const validatePort = (v: number): string | null =>
  [25, 465, 587, 993, 995].includes(v) ? null : 'Use 25, 465, 587, 993, or 995';

// ── Timezone & Currency allow-lists ──────────────────────────────────────────

export const ALLOWED_TIMEZONES: string[] = [
  'America/Los_Angeles',
  'America/Denver',
  'America/Chicago',
  'America/New_York',
  'America/Phoenix',
  'America/Anchorage',
  'Pacific/Honolulu',
  'Europe/London',
  'Europe/Berlin',
  'Europe/Paris',
  'Asia/Tokyo',
  'Asia/Shanghai',
  'Asia/Kolkata',
  'Australia/Sydney',
  'UTC',
];

export const ALLOWED_CURRENCIES: string[] = ['USD', 'CAD', 'EUR', 'GBP', 'AUD', 'NZD'];

export const validateTimezone = (v: string): string | null =>
  ALLOWED_TIMEZONES.includes(v) ? null : 'Pick a supported timezone';

export const validateCurrency = (v: string): string | null =>
  ALLOWED_CURRENCIES.includes(v) ? null : 'Pick a supported currency';

// ── Composite mandatory-field check used by StepReview ───────────────────────

/**
 * Returns an array of human-readable missing/invalid field labels.
 * An empty array means the mandatory set is complete and valid.
 */
export interface MandatoryFieldResult {
  field: string;   // e.g. 'store_name'
  label: string;   // Human label, e.g. 'Store name'
  error: string;   // Validation error message
}

export function checkMandatoryFields(pending: {
  store_name?: string;
  store_address?: string;
  store_phone?: string;
  store_email?: string;
  store_timezone?: string;
  store_currency?: string;
}): MandatoryFieldResult[] {
  const issues: MandatoryFieldResult[] = [];

  const nameErr = validateStoreName(pending.store_name ?? '');
  if (nameErr) issues.push({ field: 'store_name', label: 'Store name', error: nameErr });

  const addrErr = validateStoreAddress(pending.store_address ?? '');
  if (addrErr) issues.push({ field: 'store_address', label: 'Address', error: addrErr });

  const phoneErr = validatePhoneInternational(pending.store_phone ?? '');
  if (phoneErr) issues.push({ field: 'store_phone', label: 'Phone', error: phoneErr });

  const emailErr = validateEmail(pending.store_email ?? '');
  if (emailErr) issues.push({ field: 'store_email', label: 'Email', error: emailErr });

  const tzErr = validateTimezone(pending.store_timezone ?? '');
  if (tzErr) issues.push({ field: 'store_timezone', label: 'Timezone', error: tzErr });

  const curErr = validateCurrency(pending.store_currency ?? '');
  if (curErr) issues.push({ field: 'store_currency', label: 'Currency', error: curErr });

  return issues;
}
