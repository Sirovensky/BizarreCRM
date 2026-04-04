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
  return phone || '';
}

export function getInitials(name: string): string {
  return name
    .split(' ')
    .filter(Boolean)
    .map(w => w[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);
}
