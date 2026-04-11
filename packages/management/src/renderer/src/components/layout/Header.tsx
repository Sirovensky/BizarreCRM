import { Minus, Square, Server } from 'lucide-react';
import { StatusBadge } from '@/components/shared/StatusBadge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';
import { getAPI } from '@/api/bridge';

export function Header() {
  const isOnline = useServerStore((s) => s.isOnline);
  const serviceStatus = useServerStore((s) => s.serviceStatus);
  const username = useAuthStore((s) => s.username);

  // @audit-fixed: previously typed `serverState` as `string` and then cast
  // to a literal union at the JSX site (`status={serverState as 'online' |
  // 'offline'}`). The cast lied to TypeScript — anything would have
  // compiled even if a future branch returned an unrelated state. Now the
  // local variable is itself the literal union, so the compiler enforces
  // exhaustiveness at the assignment site and the unsafe cast at the JSX
  // call goes away.
  // Priority: stats reachability > service state > offline
  let serverState: 'online' | 'offline';
  if (isOnline) {
    serverState = 'online';
  } else if (serviceStatus?.state === 'running') {
    serverState = 'online';
  } else if (serviceStatus?.state === 'stopped') {
    serverState = 'offline';
  } else {
    // not_installed / unknown / null — show offline, not the raw state
    serverState = 'offline';
  }

  return (
    <header className="h-[var(--header-height)] flex items-center px-4 border-b border-surface-800 bg-surface-950 select-none">
      {/* Left: Title + Status (not draggable) */}
      <div className="flex items-center gap-3">
        <Server className="w-4 h-4 text-accent-400" />
        <span className="text-sm font-semibold text-surface-200">BizarreCRM</span>
        <StatusBadge status={serverState} />
      </div>

      {/* Center: Drag handle — fills all available space */}
      <div className="flex-1 h-full" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties} />

      {/* Right: User + window controls (not draggable) */}
      <div className="flex items-center gap-2">
        {username && (
          <span className="text-xs text-surface-500 mr-2">{username}</span>
        )}
        <button
          onClick={() => getAPI().system.minimize()}
          className="p-1.5 rounded hover:bg-surface-800 text-surface-400 hover:text-surface-200 transition-colors"
          title="Minimize"
        >
          <Minus className="w-3.5 h-3.5" />
        </button>
        <button
          onClick={() => getAPI().system.maximize()}
          className="p-1.5 rounded hover:bg-surface-800 text-surface-400 hover:text-surface-200 transition-colors"
          title="Maximize"
        >
          <Square className="w-3 h-3" />
        </button>
      </div>
    </header>
  );
}
