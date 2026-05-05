import { useEffect, useState } from 'react';
import { WifiOff } from 'lucide-react';

/**
 * WEB-FO-004: persistent banner shown whenever `navigator.onLine === false`.
 *
 * The web app has no service worker (intentionally unregistered) and no other
 * surface flagged offline status — when wifi drops mid-checkout, the cashier
 * just sees spinners and 30s axios timeouts. This component listens to the
 * `online` / `offline` window events and renders a non-dismissible bar at the
 * top of the AppShell so the operator knows network mutations will fail until
 * connectivity returns.
 *
 * Kept intentionally tiny: no React Query coupling, no axios pause logic — the
 * goal here is communicating reality to the user, not preventing the failed
 * request. Server-side idempotency + react-query retry already handle the
 * recovery path.
 */
export function OfflineBanner() {
  // SSR-safe initial value: assume online until the browser tells us otherwise.
  const [online, setOnline] = useState<boolean>(() =>
    typeof navigator === 'undefined' ? true : navigator.onLine,
  );

  useEffect(() => {
    const handleOnline = () => setOnline(true);
    const handleOffline = () => setOnline(false);
    window.addEventListener('online', handleOnline);
    window.addEventListener('offline', handleOffline);
    // Re-sync once on mount in case the events fired before this listener
    // attached (e.g. fast page nav while already offline).
    setOnline(navigator.onLine);
    return () => {
      window.removeEventListener('online', handleOnline);
      window.removeEventListener('offline', handleOffline);
    };
  }, []);

  if (online) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className="relative z-0 flex items-center justify-center gap-2 bg-amber-500 px-4 py-1.5 text-xs font-semibold text-white"
    >
      <WifiOff className="h-3.5 w-3.5" />
      <span>You are offline — changes will not be saved until your connection returns.</span>
    </div>
  );
}
