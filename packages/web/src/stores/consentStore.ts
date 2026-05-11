/**
 * Cookie consent store — LEGAL-COOKIE-CONSENT-1.
 *
 * Persists per-category consent under localStorage `bizarre-crm:cookie-consent`.
 * Categories follow ePrivacy / GDPR / CCPA convention:
 *   - necessary    : auth (refreshToken, csrf_token, deviceTrust), routing,
 *                    server-set session cookies. Always on.
 *   - preferences  : theme, sidebar collapsed state, language. User opt-in.
 *                    Currently the only "preferences" cookie is `theme`, which
 *                    falls under the ePrivacy "explicitly requested" exemption
 *                    so it is allowed even when preferences=false; future ones
 *                    must check `isAllowed('preferences')` before writing.
 *   - analytics    : Sentry session replay, GA, internal usage telemetry.
 *                    Default off until user opts in.
 *   - marketing    : ad pixels, retargeting, social embeds. Default off.
 *
 * "ccpa_do_not_sell" is tracked separately because CCPA opt-out is its own
 * persistent flag independent of category toggles.
 */
import { create } from 'zustand';

export type ConsentCategory = 'necessary' | 'preferences' | 'analytics' | 'marketing';

export interface ConsentState {
  hasDecided: boolean;
  preferences: boolean;
  analytics: boolean;
  marketing: boolean;
  ccpaDoNotSell: boolean;
  decidedAt: string | null;
  acceptAll: () => void;
  rejectNonEssential: () => void;
  saveCustom: (next: { preferences: boolean; analytics: boolean; marketing: boolean }) => void;
  setDoNotSell: (next: boolean) => void;
  isAllowed: (category: ConsentCategory) => boolean;
  reopen: () => void;
}

const STORAGE_KEY = 'bizarre-crm:cookie-consent';
const STORAGE_VERSION = 1;

interface PersistedShape {
  v: number;
  hasDecided: boolean;
  preferences: boolean;
  analytics: boolean;
  marketing: boolean;
  ccpaDoNotSell: boolean;
  decidedAt: string | null;
}

function loadPersisted(): PersistedShape | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = window.localStorage.getItem(STORAGE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as PersistedShape;
    if (parsed && parsed.v === STORAGE_VERSION) return parsed;
    return null;
  } catch {
    return null;
  }
}

function persist(state: PersistedShape): void {
  if (typeof window === 'undefined') return;
  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
    window.dispatchEvent(new CustomEvent('bizarre-crm:cookie-consent-changed', { detail: state }));
  } catch {
    /* quota or disabled storage — fall through */
  }
}

const initial = loadPersisted();

export const useConsentStore = create<ConsentState>((set, get) => ({
  hasDecided: initial?.hasDecided ?? false,
  preferences: initial?.preferences ?? false,
  analytics: initial?.analytics ?? false,
  marketing: initial?.marketing ?? false,
  ccpaDoNotSell: initial?.ccpaDoNotSell ?? false,
  decidedAt: initial?.decidedAt ?? null,

  acceptAll: () => {
    const next: PersistedShape = {
      v: STORAGE_VERSION,
      hasDecided: true,
      preferences: true,
      analytics: true,
      marketing: true,
      ccpaDoNotSell: get().ccpaDoNotSell,
      decidedAt: new Date().toISOString(),
    };
    persist(next);
    set({
      hasDecided: true,
      preferences: true,
      analytics: true,
      marketing: true,
      decidedAt: next.decidedAt,
    });
  },

  rejectNonEssential: () => {
    const next: PersistedShape = {
      v: STORAGE_VERSION,
      hasDecided: true,
      preferences: false,
      analytics: false,
      marketing: false,
      ccpaDoNotSell: get().ccpaDoNotSell,
      decidedAt: new Date().toISOString(),
    };
    persist(next);
    set({
      hasDecided: true,
      preferences: false,
      analytics: false,
      marketing: false,
      decidedAt: next.decidedAt,
    });
  },

  saveCustom: (sel) => {
    const next: PersistedShape = {
      v: STORAGE_VERSION,
      hasDecided: true,
      preferences: sel.preferences,
      analytics: sel.analytics,
      marketing: sel.marketing,
      ccpaDoNotSell: get().ccpaDoNotSell,
      decidedAt: new Date().toISOString(),
    };
    persist(next);
    set({
      hasDecided: true,
      preferences: sel.preferences,
      analytics: sel.analytics,
      marketing: sel.marketing,
      decidedAt: next.decidedAt,
    });
  },

  setDoNotSell: (flag) => {
    const cur = get();
    const next: PersistedShape = {
      v: STORAGE_VERSION,
      hasDecided: cur.hasDecided,
      preferences: cur.preferences,
      analytics: cur.analytics,
      marketing: cur.marketing,
      ccpaDoNotSell: flag,
      decidedAt: cur.decidedAt,
    };
    persist(next);
    set({ ccpaDoNotSell: flag });
  },

  isAllowed: (category) => {
    if (category === 'necessary') return true;
    const s = get();
    return s[category];
  },

  reopen: () => {
    set({ hasDecided: false });
  },
}));
