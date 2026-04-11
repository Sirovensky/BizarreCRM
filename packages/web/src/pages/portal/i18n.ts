/**
 * Portal i18n — lightweight in-file dictionary (English + Spanish).
 *
 * Deliberately avoids `react-i18next` / `i18next` so we don't add heavy
 * deps for what is currently two languages on the customer portal. If a
 * third language is added, swap this module for i18next without touching
 * consumers — the `t(key)` signature is designed to match.
 *
 * Auto-detection: on first load, reads `navigator.language` and falls back
 * to English. User's explicit choice (via <LanguageSwitcher/>) overrides
 * detection and persists in localStorage.
 */
import { useCallback, useEffect, useState } from 'react';

export type Locale = 'en' | 'es';

const STORAGE_KEY = 'portal_locale';

type Dictionary = Record<string, string>;

const EN: Dictionary = {
  'portal.title': 'Repair Tracking',
  'portal.loading': 'Loading...',
  'timeline.title': 'Status Timeline',
  'timeline.empty': 'No updates yet.',
  'timeline.checked_in': 'Checked in',
  'timeline.diagnosed': 'Diagnosed',
  'timeline.parts_ordered': 'Parts ordered',
  'timeline.parts_arrived': 'Parts arrived',
  'timeline.completed': 'Repair completed',
  'timeline.ready': 'Ready for pickup',
  'queue.title': 'Queue position',
  'queue.loading': 'Checking position...',
  'queue.position': "You're {n} in line",
  'queue.eta': 'Estimated wait: {min}-{max}h',
  'queue.closed': 'Repair completed',
  'queue.disabled': '',
  'tech.title': 'Your technician',
  'tech.handling': '{name} is handling your repair',
  'tech.privacy': 'Tech details are opt-in for privacy.',
  'photos.title': 'Repair photos',
  'photos.before': 'Before',
  'photos.after': 'After',
  'photos.empty': 'No photos yet.',
  'photos.delete': 'Remove',
  'photos.delete_confirm': 'Remove this photo from your view?',
  'photos.delete_window': 'Removable for {hours}h after upload.',
  'pay.title': 'Pay Now',
  'pay.amount_due': 'Amount due: ${amount}',
  'pay.button': 'Pay securely',
  'pay.paid': 'Paid in full — thank you!',
  'review.title': 'How did we do?',
  'review.prompt': "We'd love your feedback on this repair.",
  'review.rating_label': 'Your rating',
  'review.comment_label': 'Comments (optional)',
  'review.submit': 'Submit review',
  'review.thanks': 'Thank you for your feedback!',
  'review.google_prompt': 'Mind sharing that on Google?',
  'review.google_button': 'Leave a Google review',
  'trust.ssl': 'Encrypted connection',
  'trust.pci': 'Secure payments',
  'trust.address': 'Address',
  'trust.phone': 'Phone',
  'trust.hours': 'Hours',
  'faq.what_is.awaiting_parts': 'Awaiting Parts means we\'ve ordered the parts we need and are waiting for them to arrive.',
  'faq.what_is.diagnosed': 'Diagnosed means a tech inspected your device and identified the issue.',
  'faq.what_is.on_hold': 'On Hold means we need info or approval from you before continuing.',
  'faq.what_is.in_progress': 'In Progress means your device is being actively worked on.',
  'sla.default': 'Standard repairs ready within 2 business days.',
  'receipt.download': 'Download receipt',
  'warranty.download': 'Download warranty certificate',
  'loyalty.title': 'Loyalty points',
  'loyalty.balance': '{points} points',
  'loyalty.rate': 'Earn {rate} points per $1.',
  'loyalty.refer': 'Refer a friend',
  'loyalty.refer_description': 'Both get ${amount} off.',
  'loyalty.refer_copy': 'Copy your code',
  'loyalty.refer_copied': 'Code copied!',
  'language.label': 'Language',
  'language.en': 'English',
  'language.es': 'Spanish',
  'a11y.font_increase': 'Increase font size',
  'a11y.font_decrease': 'Decrease font size',
  'a11y.contrast_toggle': 'Toggle high contrast',
  'a11y.dark_toggle': 'Toggle dark mode',
};

const ES: Dictionary = {
  'portal.title': 'Seguimiento de reparación',
  'portal.loading': 'Cargando...',
  'timeline.title': 'Cronología',
  'timeline.empty': 'Aún no hay actualizaciones.',
  'timeline.checked_in': 'Recibido',
  'timeline.diagnosed': 'Diagnosticado',
  'timeline.parts_ordered': 'Piezas pedidas',
  'timeline.parts_arrived': 'Piezas recibidas',
  'timeline.completed': 'Reparación completada',
  'timeline.ready': 'Listo para recoger',
  'queue.title': 'Posición en la cola',
  'queue.loading': 'Revisando posición...',
  'queue.position': 'Estás en la posición {n}',
  'queue.eta': 'Espera estimada: {min}-{max}h',
  'queue.closed': 'Reparación completada',
  'queue.disabled': '',
  'tech.title': 'Tu técnico',
  'tech.handling': '{name} está atendiendo tu reparación',
  'tech.privacy': 'La info del técnico es opcional por privacidad.',
  'photos.title': 'Fotos de la reparación',
  'photos.before': 'Antes',
  'photos.after': 'Después',
  'photos.empty': 'Aún no hay fotos.',
  'photos.delete': 'Eliminar',
  'photos.delete_confirm': '¿Eliminar esta foto de tu vista?',
  'photos.delete_window': 'Se puede eliminar durante {hours}h tras subirla.',
  'pay.title': 'Pagar ahora',
  'pay.amount_due': 'Saldo: ${amount}',
  'pay.button': 'Pagar de forma segura',
  'pay.paid': 'Pagado — ¡gracias!',
  'review.title': '¿Cómo lo hicimos?',
  'review.prompt': 'Nos encantaría tu opinión sobre esta reparación.',
  'review.rating_label': 'Tu calificación',
  'review.comment_label': 'Comentarios (opcional)',
  'review.submit': 'Enviar reseña',
  'review.thanks': '¡Gracias por tus comentarios!',
  'review.google_prompt': '¿La compartirías en Google?',
  'review.google_button': 'Deja una reseña en Google',
  'trust.ssl': 'Conexión cifrada',
  'trust.pci': 'Pagos seguros',
  'trust.address': 'Dirección',
  'trust.phone': 'Teléfono',
  'trust.hours': 'Horario',
  'faq.what_is.awaiting_parts': 'Esperando piezas significa que pedimos las piezas y estamos esperando que lleguen.',
  'faq.what_is.diagnosed': 'Diagnosticado significa que un técnico revisó tu dispositivo e identificó el problema.',
  'faq.what_is.on_hold': 'En espera significa que necesitamos información o aprobación tuya antes de continuar.',
  'faq.what_is.in_progress': 'En progreso significa que tu dispositivo está siendo reparado activamente.',
  'sla.default': 'Las reparaciones estándar están listas en 2 días hábiles.',
  'receipt.download': 'Descargar recibo',
  'warranty.download': 'Descargar certificado de garantía',
  'loyalty.title': 'Puntos de lealtad',
  'loyalty.balance': '{points} puntos',
  'loyalty.rate': 'Gana {rate} puntos por cada $1.',
  'loyalty.refer': 'Refiere a un amigo',
  'loyalty.refer_description': 'Ambos reciben ${amount} de descuento.',
  'loyalty.refer_copy': 'Copiar tu código',
  'loyalty.refer_copied': '¡Código copiado!',
  'language.label': 'Idioma',
  'language.en': 'Inglés',
  'language.es': 'Español',
  'a11y.font_increase': 'Aumentar tamaño de letra',
  'a11y.font_decrease': 'Reducir tamaño de letra',
  'a11y.contrast_toggle': 'Alto contraste',
  'a11y.dark_toggle': 'Modo oscuro',
};

const DICTIONARIES: Readonly<Record<Locale, Dictionary>> = Object.freeze({
  en: EN,
  es: ES,
});

/** Detects the browser's preferred portal locale, falling back to English. */
export function detectLocale(): Locale {
  if (typeof navigator === 'undefined') return 'en';
  const stored = (typeof localStorage !== 'undefined'
    ? localStorage.getItem(STORAGE_KEY)
    : null) as Locale | null;
  if (stored === 'en' || stored === 'es') return stored;
  const browser = (navigator.language || 'en').slice(0, 2).toLowerCase();
  return browser === 'es' ? 'es' : 'en';
}

/** Interpolates {name} tokens in the translation value. */
function interpolate(text: string, vars?: Record<string, string | number>): string {
  if (!vars) return text;
  return text.replace(/\{(\w+)\}/g, (_, key: string) => {
    const value = vars[key];
    return value === undefined ? `{${key}}` : String(value);
  });
}

/** Translate a key for an explicit locale (useful outside React). */
export function translate(
  locale: Locale,
  key: string,
  vars?: Record<string, string | number>,
): string {
  const dict = DICTIONARIES[locale] || EN;
  return interpolate(dict[key] || EN[key] || key, vars);
}

export interface UsePortalI18n {
  locale: Locale;
  setLocale: (next: Locale) => void;
  t: (key: string, vars?: Record<string, string | number>) => string;
}

/** React hook — reads stored locale, exposes a translator, and notifies
 *  other hook instances via a custom event so multiple consumers stay in
 *  sync without a Context provider. */
export function usePortalI18n(): UsePortalI18n {
  const [locale, setLocaleState] = useState<Locale>(() => detectLocale());

  useEffect(() => {
    const handler = (event: Event): void => {
      const next = (event as CustomEvent<Locale>).detail;
      if (next === 'en' || next === 'es') setLocaleState(next);
    };
    window.addEventListener('portal-locale-change', handler);
    return () => window.removeEventListener('portal-locale-change', handler);
  }, []);

  const setLocale = useCallback((next: Locale): void => {
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      /* localStorage may be unavailable in some embeds */
    }
    window.dispatchEvent(new CustomEvent('portal-locale-change', { detail: next }));
    setLocaleState(next);
  }, []);

  const t = useCallback(
    (key: string, vars?: Record<string, string | number>): string =>
      translate(locale, key, vars),
    [locale],
  );

  return { locale, setLocale, t };
}
