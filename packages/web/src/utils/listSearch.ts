export function normalizeListSearchKeyword(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) return '';

  if (trimmed.includes('@')) {
    return trimmed.toLowerCase();
  }

  const digits = trimmed.replace(/\D/g, '');
  const hasLetters = /[A-Za-z]/.test(trimmed);
  if (digits.length >= 7 && !hasLetters) {
    return digits.length === 11 && digits.startsWith('1') ? digits.slice(1) : digits;
  }

  return trimmed;
}
