import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ShieldAlert, X } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';

export const IMPERSONATION_KEY = 'impersonation_session';

export interface ImpersonationSession {
  tenant_slug: string;
  tenant_name?: string;
  started_at?: string;
}

const IMPERSONATION_CHANGED_EVENT = 'bizarre-crm:impersonation-changed';

export function setImpersonationSession(session: ImpersonationSession): void {
  localStorage.setItem(IMPERSONATION_KEY, JSON.stringify(session));
  window.dispatchEvent(new CustomEvent(IMPERSONATION_CHANGED_EVENT));
}

export function clearImpersonationSession(): void {
  localStorage.removeItem(IMPERSONATION_KEY);
  window.dispatchEvent(new CustomEvent(IMPERSONATION_CHANGED_EVENT));
}

export function getImpersonationSession(): ImpersonationSession | null {
  try {
    const raw = localStorage.getItem(IMPERSONATION_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return null;
    const obj = parsed as Record<string, unknown>;
    if (typeof obj.tenant_slug !== 'string' || obj.tenant_slug.length === 0) return null;
    if (!/^[a-z0-9-]{1,64}$/.test(obj.tenant_slug)) return null;
    return {
      tenant_slug: obj.tenant_slug,
      tenant_name: typeof obj.tenant_name === 'string' ? obj.tenant_name : undefined,
      started_at: typeof obj.started_at === 'string' ? obj.started_at : undefined,
    };
  } catch {
    return null;
  }
}

export function ImpersonationBanner() {
  const [session, setSession] = useState<ImpersonationSession | null>(null);
  const navigate = useNavigate();
  const logout = useAuthStore((s) => s.logout);

  useEffect(() => {
    setSession(getImpersonationSession());
  }, []);

  // Re-check on cross-tab storage events AND same-tab CustomEvents
  // (storage event does not fire in the tab that wrote the value).
  useEffect(() => {
    function onStorage(e: StorageEvent) {
      if (e.key === IMPERSONATION_KEY) {
        setSession(getImpersonationSession());
      }
    }
    function onChanged() {
      setSession(getImpersonationSession());
    }
    // WEB-FJ-012 (Fixer-B15 2026-04-25): hard-clear the impersonation
    // marker whenever auth is cleared (logout, switchUser, refresh-fail).
    // Previously the marker survived everything except the explicit
    // "Exit" button click, so a stale `impersonation_session` blob in
    // localStorage could mislead the next staff member on the device into
    // thinking they were impersonating an arbitrary tenant_slug. The
    // banner trusted the localStorage value without verifying an active
    // SA session — the auth-cleared signal is the right tear-down hook.
    function onAuthCleared() {
      clearImpersonationSession();
      setSession(null);
    }
    window.addEventListener('storage', onStorage);
    window.addEventListener(IMPERSONATION_CHANGED_EVENT, onChanged);
    window.addEventListener('bizarre-crm:auth-cleared', onAuthCleared);
    return () => {
      window.removeEventListener('storage', onStorage);
      window.removeEventListener(IMPERSONATION_CHANGED_EVENT, onChanged);
      window.removeEventListener('bizarre-crm:auth-cleared', onAuthCleared);
    };
  }, []);

  if (!session) return null;

  async function handleExit() {
    clearImpersonationSession();
    await logout();
    navigate('/login');
  }

  return (
    <button
      type="button"
      className="flex w-full items-center justify-center gap-2 bg-amber-500 px-4 py-1.5 text-xs font-semibold text-white hover:bg-amber-600 transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-amber-500"
      onClick={handleExit}
      title="Click to exit impersonation and return to super-admin"
      aria-label={`Exit impersonation of tenant ${session.tenant_slug}`}
    >
      <ShieldAlert className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>
        Impersonating <strong>{session.tenant_slug}</strong>. Click to exit.
      </span>
      <X className="h-3.5 w-3.5 shrink-0 ml-1" aria-hidden="true" />
    </button>
  );
}
