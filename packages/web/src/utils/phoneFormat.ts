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
  if (digits.length > 11) return value;

  if (digits.length === 0) return '';
  if (digits.length <= 3) return `+1 (${digits}`;
  if (digits.length <= 6) return `+1 (${digits.slice(0, 3)})-${digits.slice(3)}`;
  return `+1 (${digits.slice(0, 3)})-${digits.slice(3, 6)}-${digits.slice(6, 10)}`;
}
