import { AppError } from '../middleware/errorHandler.js';

export function validatePrice(value: unknown, fieldName = 'price'): number {
  const num = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(num) || !isFinite(num) || num < 0) throw new AppError(`${fieldName} must be non-negative`, 400);
  if (num > 999999.99) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return Math.round(num * 100) / 100;
}

/**
 * Validate a signed money amount — allows negatives (e.g. discounts, adjustments)
 * but still rejects Infinity / NaN and clamps the range. Unlike validatePrice
 * which is for non-negative prices, use this for adjustments, deltas, and
 * credit notes where negative values are legitimate.
 */
export function validateSignedAmount(value: unknown, fieldName = 'amount'): number {
  const num = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(num) || !isFinite(num)) throw new AppError(`${fieldName} must be a number`, 400);
  if (num < -999999.99 || num > 999999.99) throw new AppError(`${fieldName} out of range`, 400);
  return Math.round(num * 100) / 100;
}

/**
 * Validate a positive money amount (strictly > 0). Use for payments, refunds,
 * where a zero or negative value would be nonsense but a small amount is fine.
 */
export function validatePositiveAmount(value: unknown, fieldName = 'amount'): number {
  const num = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(num) || !isFinite(num) || num <= 0) throw new AppError(`${fieldName} must be > 0`, 400);
  if (num > 999999.99) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return Math.round(num * 100) / 100;
}

export function validateQuantity(value: unknown, fieldName = 'quantity'): number {
  // @audit-fixed: parseInt("10abc", 10) returns 10 silently. Require the full
  // string to match the integer shape before coercion so we can't accept a
  // quantity of "10 items" etc. Also reject Infinity/-Infinity explicitly.
  let num: number;
  if (typeof value === 'number') {
    num = value;
  } else if (typeof value === 'string' && /^-?\d+$/.test(value.trim())) {
    num = Number(value.trim());
  } else {
    throw new AppError(`${fieldName} must be a positive integer`, 400);
  }
  if (!Number.isFinite(num) || isNaN(num) || num < 1) throw new AppError(`${fieldName} must be at least 1`, 400);
  if (num > 100000) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return num;
}

/**
 * Integer quantity that allows 0 and strictly rejects fractions + NaN + Infinity.
 * Use for stock counts and line-item quantities where 2.7 should NOT silently
 * truncate to 2 (POS5 bug).
 */
export function validateIntegerQuantity(value: unknown, fieldName = 'quantity'): number {
  const raw = typeof value === 'number' ? value : parseFloat(value as string);
  if (isNaN(raw) || !isFinite(raw)) throw new AppError(`${fieldName} must be an integer`, 400);
  if (!Number.isInteger(raw)) throw new AppError(`${fieldName} must be a whole number`, 400);
  if (raw < 0) throw new AppError(`${fieldName} cannot be negative`, 400);
  if (raw > 100000) throw new AppError(`${fieldName} exceeds maximum`, 400);
  return raw;
}

export function validateTextLength(value: string | undefined, maxLength: number, fieldName = 'text'): string {
  if (!value) return '';
  if (value.length > maxLength) throw new AppError(`${fieldName} exceeds ${maxLength} characters`, 400);
  return value;
}

/**
 * Email validation. Accepts the same format as the original inline regex but
 * also rejects edge cases like `a..b@c` and `t@t.t` (too-short TLD).
 * Returns the trimmed lowercased form, or null for empty input.
 */
export function validateEmail(value: unknown, fieldName = 'email', required = false): string | null {
  if (value === undefined || value === null || value === '') {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const email = value.trim().toLowerCase();
  if (!email) {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (email.length > 254) throw new AppError(`${fieldName} too long`, 400);
  // @audit-fixed: Split into local and domain halves BEFORE running the regex
  // so a malicious input like "a".repeat(250) + "@" + ... cannot trigger
  // quadratic backtracking on the nested `(?:\.[^\s@.]+)*` groups. RFC 5321
  // caps local at 64 and domain at 253; enforcing that trims the regex input
  // to sizes where a linear scan is provably fast.
  const atIdx = email.indexOf('@');
  if (atIdx < 1 || atIdx !== email.lastIndexOf('@')) throw new AppError(`${fieldName} is not a valid email`, 400);
  const local = email.slice(0, atIdx);
  const domain = email.slice(atIdx + 1);
  if (local.length > 64 || domain.length < 1 || domain.length > 253) {
    throw new AppError(`${fieldName} is not a valid email`, 400);
  }
  // Reject consecutive dots in local part, require 2+ char TLD, disallow spaces.
  const re = /^[^\s@.]+(?:\.[^\s@.]+)*@[^\s@.]+(?:\.[^\s@.]+)*\.[^\s@.]{2,}$/;
  if (!re.test(email)) throw new AppError(`${fieldName} is not a valid email`, 400);
  return email;
}

/**
 * Phone validation. Digits-only length check after normalization. Returns the
 * normalized 10-digit form or null. Accepts the normalized result of the
 * existing `normalizePhone()` helper.
 */
export function validatePhoneDigits(digits: string, fieldName = 'phone', required = false): string | null {
  if (!digits) {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (!/^\d+$/.test(digits)) throw new AppError(`${fieldName} must contain only digits`, 400);
  // US/Canada 10-digit. Reject obviously-bogus short numbers.
  if (digits.length < 10 || digits.length > 15) {
    throw new AppError(`${fieldName} must be 10-15 digits`, 400);
  }
  return digits;
}

/**
 * SEC-M57: reject control + bidirectional-override codepoints in user-
 * facing text. Control chars < U+0020 (except tab U+0009, LF U+000A,
 * CR U+000D) and RTL/LTR override chars in U+202A..U+202E / U+2066..U+2069
 * are either log-injection primitives (CR/LF in identifiers) or
 * presentation-spoofing primitives (RTL override flips "TechStore" to
 * "erotSkceT" in rendered lists). Applied to every user-facing name /
 * title / label via validateRequiredString so a hostile customer
 * import can't poison audit trails or UI rendering.
 */
const DISALLOWED_TEXT_CODEPOINTS =
  // eslint-disable-next-line no-control-regex
  /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u202A-\u202E\u2066-\u2069]/;

export function rejectControlAndRTL(value: string, fieldName: string): void {
  if (DISALLOWED_TEXT_CODEPOINTS.test(value)) {
    throw new AppError(`${fieldName} contains disallowed control or bidi codepoints`, 400);
  }
}

/**
 * Validate a non-empty trimmed name / title / label field.
 */
export function validateRequiredString(value: unknown, fieldName: string, maxLength = 255): string {
  if (value === undefined || value === null) throw new AppError(`${fieldName} is required`, 400);
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (!trimmed) throw new AppError(`${fieldName} is required`, 400);
  if (trimmed.length > maxLength) throw new AppError(`${fieldName} exceeds ${maxLength} characters`, 400);
  rejectControlAndRTL(trimmed, fieldName);
  return trimmed;
}

/**
 * Validate an ISO 8601 date string. Accepts YYYY-MM-DD or full ISO timestamps.
 * Returns the ISO string, or null if empty + !required.
 */
export function validateIsoDate(value: unknown, fieldName = 'date', required = false): string | null {
  if (value === undefined || value === null || value === '') {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a date string`, 400);
  const trimmed = value.trim();
  if (!trimmed) {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  // Strict ISO date or date-time check.
  if (!/^\d{4}-\d{2}-\d{2}(T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?)?$/.test(trimmed)) {
    throw new AppError(`${fieldName} must be an ISO date (YYYY-MM-DD)`, 400);
  }
  // Reject things like 2025-02-30 that Date accepts but roll over silently.
  const d = new Date(trimmed);
  if (isNaN(d.getTime())) throw new AppError(`${fieldName} is not a valid date`, 400);
  // For date-only form, re-check the round-trip.
  if (/^\d{4}-\d{2}-\d{2}$/.test(trimmed)) {
    const [y, m, day] = trimmed.split('-').map(Number);
    if (d.getUTCFullYear() !== y || d.getUTCMonth() + 1 !== m || d.getUTCDate() !== day) {
      throw new AppError(`${fieldName} is not a valid date`, 400);
    }
  }
  return trimmed;
}

/**
 * Validate an enum field against a whitelist. Trims and lowercases before check.
 */
export function validateEnum<T extends string>(
  value: unknown,
  allowed: readonly T[],
  fieldName: string,
  required = true,
): T | null {
  if (value === undefined || value === null || value === '') {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (!allowed.includes(trimmed as T)) {
    throw new AppError(`${fieldName} must be one of: ${allowed.join(', ')}`, 400);
  }
  return trimmed as T;
}

/**
 * Validate a JSON payload for shape + circular references + size before storing.
 * Prevents V13 "circular ref crash" and unbounded blob storage.
 */
export function validateJsonPayload(value: unknown, fieldName = 'payload', maxBytes = 65_536): string {
  let serialized: string;
  try {
    serialized = JSON.stringify(value);
  } catch {
    throw new AppError(`${fieldName} is not serializable`, 400);
  }
  if (!serialized) throw new AppError(`${fieldName} is empty`, 400);
  if (serialized.length > maxBytes) throw new AppError(`${fieldName} exceeds ${maxBytes} bytes`, 400);
  return serialized;
}

/**
 * Validate an array length is within bounds. Use to reject 100k-item line-item lists
 * and similar DoS vectors (V12).
 */
export function validateArrayBounds<T>(value: unknown, fieldName: string, maxItems: number): T[] {
  if (!Array.isArray(value)) throw new AppError(`${fieldName} must be an array`, 400);
  if (value.length > maxItems) throw new AppError(`${fieldName} exceeds ${maxItems} items`, 400);
  return value as T[];
}

/**
 * Validate a hex color string (#RRGGBB or #RGB). Prevents V22 XSS where a color
 * field stored `javascript:alert(1)` and was reflected to the frontend.
 */
export function validateHexColor(value: unknown, fieldName = 'color', required = false): string | null {
  if (value === undefined || value === null || value === '') {
    if (required) throw new AppError(`${fieldName} is required`, 400);
    return null;
  }
  if (typeof value !== 'string') throw new AppError(`${fieldName} must be a string`, 400);
  const trimmed = value.trim();
  if (!/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/.test(trimmed)) {
    throw new AppError(`${fieldName} must be a #RRGGBB or #RGB hex color`, 400);
  }
  return trimmed;
}

/**
 * Round a float to 2 decimal places (cents precision) deterministically.
 * Use everywhere money arithmetic happens to kill 0.1+0.2 drift (M7, M8).
 */
export function roundCents(value: number): number {
  if (!isFinite(value)) return 0;
  return Math.round(value * 100) / 100;
}

/**
 * Convert a float dollar amount to integer cents for safe arithmetic.
 */
export function toCents(value: number): number {
  return Math.round(value * 100);
}

/**
 * Convert integer cents back to float dollars.
 */
export function fromCents(cents: number): number {
  return cents / 100;
}

/**
 * SEC-M10: Validate multiple string field lengths in one call.
 * Pass an object of field values and a rules map of fieldName → maxLength.
 * Skips undefined/null fields. Throws on first violation.
 */
export function validateInputLengths(
  data: Record<string, unknown>,
  rules: Record<string, number>,
): void {
  for (const [field, maxLen] of Object.entries(rules)) {
    const val = data[field];
    if (typeof val === 'string' && val.length > maxLen) {
      throw new AppError(`${field} exceeds ${maxLen} characters`, 400);
    }
  }
}

/**
 * BUG-3: Parse + validate a route param (or query string) as a positive integer ID.
 * Replaces bare `parseInt(req.params.id)` which silently returns NaN for non-numeric
 * strings, propagating NULL into SQL queries and producing unexpected results.
 */
export function validateId(value: unknown, fieldName = 'id'): number {
  const raw = typeof value === 'number' ? value : parseInt(String(value), 10);
  if (isNaN(raw) || !isFinite(raw) || raw < 1) {
    throw new AppError(`Invalid ${fieldName}`, 400);
  }
  return raw;
}
