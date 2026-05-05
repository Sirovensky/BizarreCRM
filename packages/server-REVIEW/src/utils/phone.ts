export function normalizePhone(phone: string | null | undefined): string {
  if (!phone) return '';
  // Strip all non-digits
  const digits = phone.replace(/\D/g, '');
  // Remove leading 1 from 11-digit US numbers
  if (digits.length === 11 && digits.startsWith('1')) {
    return digits.slice(1);
  }
  return digits;
}

export function formatPhone(phone: string | null | undefined): string {
  const digits = normalizePhone(phone);
  if (digits.length === 10) {
    return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  }
  // @audit-fixed: Only return the raw value if it's actually a string, so a
  // `null`/`undefined`/object input can't crash downstream templates.
  return typeof phone === 'string' ? phone : '';
}

export function redactPhone(phone: unknown): string {
  if (typeof phone !== 'string') return 'XXX-XXX-XXXX';
  const digits = phone.replace(/\D/g, '');
  if (digits.length < 4) return 'XXX-XXX-XXXX';
  return `XXX-XXX-${digits.slice(-4)}`;
}

export function getInitials(name: string): string {
  // @audit-fixed: Defensively coerce null/undefined/non-string so this helper
  // can't throw `Cannot read properties of undefined (reading 'split')`.
  if (typeof name !== 'string') return '';
  return name
    .split(' ')
    .filter(Boolean)
    .map(w => w[0] || '')
    .join('')
    .toUpperCase()
    .slice(0, 2);
}
