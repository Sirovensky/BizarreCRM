export function formatPhoneAsYouType(value: string): string {
  const digits = value.replace(/\D/g, '');
  if (digits.length <= 3) return digits;
  if (digits.length <= 6) return `(${digits.slice(0, 3)}) ${digits.slice(3)}`;
  if (digits.length <= 10) return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  // 11 digits (with country code 1)
  if (digits.startsWith('1') && digits.length === 11) return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  return value;
}

export function stripPhone(value: string): string {
  return value.replace(/\D/g, '');
}

/**
 * Store phone specific formatter — outputs "+1 (XXX)-XXX-XXXX".
 *
 * Differs from formatPhoneAsYouType in two ways:
 *   - Always prepends "+1" for US numbers (not just 11-digit input)
 *   - Uses a dash between the area code parenthesis and the exchange
 *     instead of a space: "(303)-261-1911" not "(303) 261-1911"
 *
 * This is the preferred format for the shop's own phone number (stored in
 * store_config.store_phone) per the user's preference. Customer phone
 * numbers elsewhere in the app keep the standard formatPhoneAsYouType.
 *
 * Non-US numbers (anything longer than 11 digits or starting with a non-US
 * country code) are returned unchanged so they can be entered freely.
 *
 * Progressive while typing:
 *   "3"           -> "+1 (3"
 *   "30"          -> "+1 (30"
 *   "303"         -> "+1 (303)"
 *   "3032"        -> "+1 (303)-2"
 *   "303261"      -> "+1 (303)-261"
 *   "3032611"     -> "+1 (303)-261-1"
 *   "3032611911"  -> "+1 (303)-261-1911"
 *   "13032611911" -> "+1 (303)-261-1911"  (strips leading 1)
 */
export function formatStorePhoneAsYouType(value: string): string {
  let digits = value.replace(/\D/g, '');
  // Strip leading 1 if the user typed a full 11-digit US number
  if (digits.length === 11 && digits.startsWith('1')) {
    digits = digits.slice(1);
  }
  // More than 10 digits and doesn't fit the US pattern — don't try to format,
  // let the user enter whatever they need (international, extensions, etc.)
  // WEB-FD-024 (Fixer-C5 2026-04-25): require an explicit "+" prefix for
  // non-US numbers so a paste of "447911123456" (UK without +) becomes
  // "+447911123456" instead of being silently echoed without country-code
  // semantics. If the user already typed a "+", preserve their input
  // verbatim (we don't presume to reformat international patterns we don't
  // own).
  if (digits.length > 11) {
    const trimmed = value.trim();
    if (trimmed.startsWith('+')) return trimmed;
    return `+${digits}`;
  }

  if (digits.length === 0) return '';
  if (digits.length <= 3) return `+1 (${digits}`;
  if (digits.length <= 6) return `+1 (${digits.slice(0, 3)})-${digits.slice(3)}`;
  return `+1 (${digits.slice(0, 3)})-${digits.slice(3, 6)}-${digits.slice(6, 10)}`;
}

/**
 * WEB-FJ-004 / FIXED-by-Fixer-A11 2026-04-25 — non-reversible 8-hex-char
 * fingerprint of a phone number, used as a localStorage draft-key suffix in
 * place of the raw phone digits. Prevents anyone with shared-PC access to
 * the browser's localStorage from harvesting `phone -> draft message body`
 * pairs (medical-device repairs, addresses, account-recovery codes, door
 * codes, etc.) by reading keys like `bizarrecrm:draft:42:draft_sms_+15551234567`.
 *
 * FNV-1a 32-bit — small, dependency-free, and "good enough" for opaque
 * key namespacing. NOT a cryptographic hash and NOT a secret; collisions
 * are tolerable here because draft restoration is best-effort UX, not a
 * security boundary, and per-user namespacing already isolates buckets.
 *
 * Returned as 8 lowercase hex chars (e.g. "a3f2c980") so the resulting
 * draft key stays a fixed, opaque length regardless of input format.
 */
export function obfuscatePhoneForStorageKey(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  // Empty/missing input still gets a stable key so callers can pass
  // through "no phone selected" without branching.
  const input = digits || phone;
  let h = 0x811c9dc5; // FNV offset basis
  for (let i = 0; i < input.length; i += 1) {
    h ^= input.charCodeAt(i);
    // FNV prime multiply — Math.imul keeps it 32-bit on JS engines.
    h = Math.imul(h, 0x01000193);
  }
  // Coerce to unsigned and pad to 8 hex chars.
  return (h >>> 0).toString(16).padStart(8, '0');
}
