import { Minus, Square, Server } from 'lucide-react';
import { StatusBadge } from '@/components/shared/StatusBadge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';
import { getAPI } from '@/api/bridge';

export function Header() {
  const isOnline = useServerStore((s) => s.isOnline);
  const serviceStatus = useServerStore((s) => s.serviceStatus);
  const username = useAuthStore((s) => s.username);

  // Priority: stats reachability > service state > offline
  let serverState: string;
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
    <header className="h-[var(--header-height)] flex items-center justify-between px-4 border-b border-surface-800 bg-surface-950/80 backdrop-blur-sm select-none"
      style={{ WebkitAppRegion: 'drag' } as React.CSSProperties}
    >
      {/* Left: Title + Status */}
      <div className="flex items-center gap-3" style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
        <Server className="w-4 h-4 text-accent-400" />
        <span className="text-sm font-semibold text-surface-200">BizarreCRM</span>
        <StatusBadge status={serverState as 'online' | 'offline'} />
      </div>

      {/* Right: User + window controls */}
      <div className="flex items-center gap-2" style={{ WebkitAppRegion: 'no-drag' } as React.CSSProperties}>
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
