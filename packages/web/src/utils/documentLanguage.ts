const DEFAULT_DOCUMENT_LANGUAGE = 'en';

export function normalizeDocumentLanguage(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const candidate = value.trim().replace(/_/g, '-');
  if (!candidate) return null;

  try {
    return Intl.getCanonicalLocales(candidate)[0] ?? null;
  } catch {
    return /^[a-zA-Z]{2,3}(-[A-Za-z0-9]{2,8})*$/.test(candidate) ? candidate : null;
  }
}

export function getBrowserDocumentLanguage(): string {
  if (typeof navigator === 'undefined') return DEFAULT_DOCUMENT_LANGUAGE;
  const candidates = [
    ...(Array.isArray(navigator.languages) ? navigator.languages : []),
    navigator.language,
  ];
  for (const candidate of candidates) {
    const normalized = normalizeDocumentLanguage(candidate);
    if (normalized) return normalized;
  }
  return DEFAULT_DOCUMENT_LANGUAGE;
}

export function applyDocumentLanguage(value: unknown, fallback = DEFAULT_DOCUMENT_LANGUAGE): string {
  const language = normalizeDocumentLanguage(value)
    ?? normalizeDocumentLanguage(fallback)
    ?? DEFAULT_DOCUMENT_LANGUAGE;
  if (typeof document !== 'undefined') {
    document.documentElement.lang = language;
  }
  return language;
}
