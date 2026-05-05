import { useEffect, useState } from 'react';
import { Minus, Square, Server } from 'lucide-react';
import { StatusBadge } from '@/components/shared/StatusBadge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';
import { getAPI } from '@/api/bridge';

export function Header() {
  const isOnline = useServerStore((s) => s.isOnline);
  const serviceStatus = useServerStore((s) => s.serviceStatus);
  const lastUpdated = useServerStore((s) => s.lastUpdated);
  const username = useAuthStore((s) => s.username);

  // Second-resolution "freshness" tick — forces a 1 Hz re-render so the
  // "last tick 3s ago" chip updates in real time even when no new stats
  // have arrived. Keeps the render cost negligible by only touching the
  // header subtree.
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(id);
  }, []);
  const ageSec = lastUpdated ? Math.max(0, Math.floor((now - lastUpdated) / 1000)) : null;
  const ageColor = ageSec == null
    ? 'text-surface-500 border-surface-800'
    : ageSec < 15
      ? 'text-emerald-400/80 border-emerald-900/50'
      : ageSec < 60
        ? 'text-amber-400/90 border-amber-900/50'
        : 'text-red-400/90 border-red-900/50';

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
        {ageSec != null && (
          <span
            // DASH-ELEC-178: window minWidth is 900px so `sm:` (640) is always
            // satisfied — the guard read as if it hid the chip on narrow widths
            // when in fact it never could. Drop the dead breakpoint.
            className={`inline-flex items-center gap-1 text-[10px] border rounded px-1.5 py-0.5 font-mono ${ageColor}`}
            title="Time since last successful server-stats poll"
          >
            tick {ageSec}s
          </span>
        )}
      </div>

      {/* Center: Drag handle — fills all available space */}
      <div className="flex-1 h-full" style={{ WebkitAppRegion: 'drag' } as React.CSSProperties} />

      {/* Right: User + window controls (not draggable) */}
      <div className="flex items-center gap-2">
        {/* Static palette hint — the actual Cmd+K handler lives on window in
            CommandPalette. DASH-ELEC-126: use <kbd> so SR announces "keyboard
            shortcut" and add aria-keyshortcuts on the hint element itself. */}
        <kbd
          // DASH-ELEC-178: same dead breakpoint as the tick chip above —
          // minWidth 900 means `sm:` (640) always matches. Drop the guard.
          className="inline-flex items-center gap-1 text-[10px] text-surface-500 border border-surface-700 rounded px-1.5 py-0.5 font-mono not-italic"
          aria-label="Command palette shortcut: Control K or Command K"
          aria-keyshortcuts="Control+k Meta+k"
        >
          ⌘K
        </kbd>
        {username && (
          <span className="text-xs text-surface-500 mr-2">{username}</span>
        )}
        <button
          onClick={() => getAPI().system.minimize()}
          className="p-1.5 rounded hover:bg-surface-800 text-surface-400 hover:text-surface-200 transition-colors"
          title="Minimize"
          aria-label="Minimize window"
        >
          <Minus className="w-3.5 h-3.5" />
        </button>
        <button
          onClick={() => getAPI().system.maximize()}
          className="p-1.5 rounded hover:bg-surface-800 text-surface-400 hover:text-surface-200 transition-colors"
          title="Maximize"
          aria-label="Maximize window"
        >
          <Square className="w-3 h-3" />
        </button>
      </div>
    </header>
  );
}
