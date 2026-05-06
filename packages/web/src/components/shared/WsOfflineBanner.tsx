import { WifiOff, RefreshCw } from 'lucide-react';
import { useWsStore } from '@/hooks/useWebSocket';

/**
 * WEB-UIUX-841: banner shown when the WebSocket has exhausted all reconnect
 * attempts (isWsOffline=true). A "Reconnect" button fires the same
 * `bizarre-crm:auth-ready` custom event that the visibility-change and
 * auth-refresh paths use to reset the attempt counter and retry the socket —
 * no new hook API needed.
 */
export function WsOfflineBanner() {
  const isWsOffline = useWsStore((s) => s.isWsOffline);

  if (!isWsOffline) return null;

  function handleReconnect() {
    window.dispatchEvent(new Event('bizarre-crm:auth-ready'));
  }

  return (
    <div
      role="alert"
      aria-live="polite"
      className="relative z-0 flex items-center justify-center gap-2 bg-amber-600 px-4 py-1.5 text-xs font-semibold text-white"
    >
      <WifiOff className="h-3.5 w-3.5 shrink-0" />
      <span>Live updates disconnected — real-time data may be stale.</span>
      <button
        type="button"
        onClick={handleReconnect}
        className="ml-2 inline-flex items-center gap-1 rounded bg-white/20 px-2 py-0.5 text-xs font-semibold text-white hover:bg-white/30 focus-visible:outline-none focus:ring-2 focus:ring-white/50 transition-colors"
        aria-label="Reconnect WebSocket"
      >
        <RefreshCw className="h-3 w-3" />
        Reconnect
      </button>
    </div>
  );
}
