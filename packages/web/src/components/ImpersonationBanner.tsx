import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { ShieldAlert, X } from 'lucide-react';
import { useAuthStore } from '@/stores/authStore';

export const IMPERSONATION_KEY = 'impersonation_session';

export interface ImpersonationSession {
  tenant_slug: string;
}

export function setImpersonationSession(session: ImpersonationSession): void {
  localStorage.setItem(IMPERSONATION_KEY, JSON.stringify(session));
}

export function clearImpersonationSession(): void {
  localStorage.removeItem(IMPERSONATION_KEY);
}

export function getImpersonationSession(): ImpersonationSession | null {
  try {
    const raw = localStorage.getItem(IMPERSONATION_KEY);
    return raw ? (JSON.parse(raw) as ImpersonationSession) : null;
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

  // Re-check whenever localStorage changes (e.g. impersonate sets the key)
  useEffect(() => {
    function onStorage(e: StorageEvent) {
      if (e.key === IMPERSONATION_KEY) {
        setSession(getImpersonationSession());
      }
    }
    window.addEventListener('storage', onStorage);
    return () => window.removeEventListener('storage', onStorage);
  }, []);

  if (!session) return null;

  async function handleExit() {
    clearImpersonationSession();
    await logout();
    navigate('/login');
  }

  return (
    <div
      className="flex items-center justify-center gap-2 bg-amber-500 px-4 py-1.5 text-xs font-semibold text-white cursor-pointer hover:bg-amber-600 transition-colors"
      onClick={handleExit}
      role="button"
      title="Click to exit impersonation and return to super-admin"
    >
      <ShieldAlert className="h-3.5 w-3.5 shrink-0" />
      <span>
        Impersonating <strong>{session.tenant_slug}</strong>. Click to exit.
      </span>
      <X className="h-3.5 w-3.5 shrink-0 ml-1" />
    </div>
  );
}
