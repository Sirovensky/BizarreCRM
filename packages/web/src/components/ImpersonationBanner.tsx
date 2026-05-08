import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { ShieldAlert, X } from 'lucide-react';
import { superAdminTokenStore } from '@/api/client';
import { superAdminApi } from '@/api/endpoints';

export const IMPERSONATION_KEY = 'impersonation_session';

export interface ImpersonationSession {
  tenant_slug: string;
  tenant_name?: string;
  started_at?: string;
  jti?: string;
}

const IMPERSONATION_CHANGED_EVENT = 'bizarre-crm:impersonation-changed';
const TENANT_SLUG_RE = /^[a-z0-9-]{1,64}$/;
const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

interface ImpersonationTokenClaims {
  tenantSlug: string;
  jti: string;
}

function decodeJwtPayload(token: string): Record<string, unknown> | null {
  try {
    const parts = token.split('.');
    if (parts.length < 2) return null;
    const b64 = parts[1].replace(/-/g, '+').replace(/_/g, '/');
    const padded = b64 + '==='.slice((b64.length + 3) % 4);
    return JSON.parse(atob(padded)) as Record<string, unknown>;
  } catch {
    return null;
  }
}

export function readImpersonationTokenClaims(token: string): ImpersonationTokenClaims | null {
  const payload = decodeJwtPayload(token);
  if (!payload) return null;
  if (payload.type !== 'access' || payload.impersonated !== true) return null;
  if (typeof payload.tenantSlug !== 'string' || !TENANT_SLUG_RE.test(payload.tenantSlug)) return null;
  if (typeof payload.jti !== 'string' || !UUID_RE.test(payload.jti)) return null;
  return { tenantSlug: payload.tenantSlug, jti: payload.jti };
}

export function setImpersonationSession(session: ImpersonationSession): void {
  sessionStorage.setItem(IMPERSONATION_KEY, JSON.stringify(session));
  window.dispatchEvent(new CustomEvent(IMPERSONATION_CHANGED_EVENT));
}

export function clearImpersonationSession(): void {
  sessionStorage.removeItem(IMPERSONATION_KEY);
  window.dispatchEvent(new CustomEvent(IMPERSONATION_CHANGED_EVENT));
}

export function getImpersonationSession(): ImpersonationSession | null {
  try {
    const raw = sessionStorage.getItem(IMPERSONATION_KEY);
    if (!raw) return null;
    const parsed: unknown = JSON.parse(raw);
    if (typeof parsed !== 'object' || parsed === null) return null;
    const obj = parsed as Record<string, unknown>;
    if (typeof obj.tenant_slug !== 'string' || obj.tenant_slug.length === 0) return null;
    if (!TENANT_SLUG_RE.test(obj.tenant_slug)) return null;
    const jti = typeof obj.jti === 'string' && UUID_RE.test(obj.jti) ? obj.jti : undefined;
    return {
      tenant_slug: obj.tenant_slug,
      tenant_name: typeof obj.tenant_name === 'string' ? obj.tenant_name : undefined,
      started_at: typeof obj.started_at === 'string' ? obj.started_at : undefined,
      jti,
    };
  } catch {
    return null;
  }
}

export function ImpersonationBanner() {
  const [session, setSession] = useState<ImpersonationSession | null>(null);
  const [ending, setEnding] = useState(false);
  const navigate = useNavigate();

  useEffect(() => {
    setSession(getImpersonationSession());
  }, []);

  // Re-check on same-tab CustomEvents.
  // sessionStorage is tab-isolated so no cross-tab storage event is needed.
  useEffect(() => {
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
    window.addEventListener(IMPERSONATION_CHANGED_EVENT, onChanged);
    window.addEventListener('bizarre-crm:auth-cleared', onAuthCleared);
    return () => {
      window.removeEventListener(IMPERSONATION_CHANGED_EVENT, onChanged);
      window.removeEventListener('bizarre-crm:auth-cleared', onAuthCleared);
    };
  }, []);

  if (!session) return null;

  async function handleExit() {
    if (!session || ending) return;
    if (session.jti && superAdminTokenStore.get()) {
      setEnding(true);
      try {
        await superAdminApi.endImpersonation(session.tenant_slug, session.jti);
        toast.success('Impersonation ended');
      } catch (err) {
        const message =
          err && typeof err === 'object' && 'response' in err
            ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
            : undefined;
        toast.error(message ?? 'Could not end impersonation. Try again before leaving the session.');
        setEnding(false);
        return;
      }
      setEnding(false);
    }
    clearImpersonationSession();
    navigate('/super-admin/tenants');
  }

  return (
    <div
      role="status"
      className="flex w-full items-center justify-center gap-2 bg-amber-500 px-4 py-1.5 text-xs font-semibold text-white"
    >
      <ShieldAlert className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      <span>
        Impersonating{' '}
        {session.tenant_name ? (
          <>
            <strong>{session.tenant_name}</strong>{' '}
            <code className="font-normal opacity-80">({session.tenant_slug})</code>
          </>
        ) : (
          <strong>{session.tenant_slug}</strong>
        )}
      </span>
      <button
        type="button"
        onClick={handleExit}
        disabled={ending}
        aria-label="Exit impersonation"
        title="Exit impersonation and return to super-admin"
        className="ml-1 rounded focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white focus-visible:ring-offset-2 focus-visible:ring-offset-amber-500 hover:bg-amber-600 transition-colors p-0.5 disabled:cursor-wait disabled:opacity-60"
      >
        <X className="h-3.5 w-3.5 shrink-0" aria-hidden="true" />
      </button>
    </div>
  );
}
