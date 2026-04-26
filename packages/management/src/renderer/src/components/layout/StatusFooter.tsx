import { useEffect, useState } from 'react';
import { useServerStore } from '@/stores/serverStore';
import { formatUptime } from '@/utils/format';
import { cn } from '@/utils/cn';

/**
 * One-line footer strip showing core server state that operators want
 * visible regardless of which page they're on. Data comes entirely from
 * the existing useServerHealth poll (serverStore) — no extra fetch — so
 * this is pure presentation sitting below the main content.
 *
 * Hidden when server is offline or stats are stale because there is
 * nothing to display; in that case the Header's status lamp carries the
 * "offline" signal alone.
 */
export function StatusFooter() {
  const stats = useServerStore((s) => s.stats);
  const serviceStatus = useServerStore((s) => s.serviceStatus);
  const lastUpdated = useServerStore((s) => s.lastUpdated);

  const [, forceTick] = useState(0);
  useEffect(() => {
    // Re-render every 30s so uptime display does not fall out of sync with
    // the stats poll cadence. Low-frequency on purpose — anything faster
    // is noise; anything slower and a one-minute uptime increment is
    // invisible. Keep the footer subtree isolated so this does not cause
    // a page re-render storm.
    const id = setInterval(() => forceTick((t) => t + 1), 30_000);
    return () => clearInterval(id);
  }, []);

  if (!stats) return null;

  const pieces: Array<{ label: string; value: string; className?: string }> = [];

  if (stats.uptime !== undefined) {
    // DASH-ELEC-049: compute live uptime rather than showing the frozen poll
    // value. Add the seconds elapsed since the last successful poll so the
    // number increments on screen even between fetch cycles (up to 60 s gap
    // at max back-off). Falls back to raw stats.uptime when lastUpdated is null.
    const elapsed = lastUpdated != null ? Math.floor((Date.now() - lastUpdated) / 1000) : 0;
    pieces.push({ label: 'uptime', value: formatUptime(stats.uptime + elapsed) });
  }
  if (stats.multiTenant !== undefined) {
    pieces.push({
      label: 'mode',
      value: stats.multiTenant ? 'multi-tenant' : 'single-tenant',
      className: stats.multiTenant ? 'text-accent-400' : 'text-surface-400',
    });
  }
  if (stats.nodeEnv) {
    pieces.push({
      label: 'env',
      value: stats.nodeEnv,
      className: stats.nodeEnv === 'production' ? 'text-emerald-400' : 'text-amber-400',
    });
  }
  if (stats.pm2Managed !== undefined) {
    pieces.push({ label: 'pm2', value: stats.pm2Managed ? 'yes' : 'no' });
  }
  if (serviceStatus?.mode && serviceStatus.mode !== 'none') {
    pieces.push({ label: 'service', value: serviceStatus.mode });
  }
  if (stats.nodeVersion) {
    pieces.push({ label: 'node', value: stats.nodeVersion });
  }
  if (stats.hostname) {
    pieces.push({ label: 'host', value: stats.hostname });
  }

  // DASH-ELEC-177: window minWidth is 900px so the `sm:` (640) breakpoint is
  // always satisfied; the `hidden sm:flex` guard was dead. Just always flex.
  return (
    <footer className="flex items-center gap-x-3 gap-y-1 px-3 py-1 text-[10px] text-surface-500 border-t border-surface-800 bg-surface-950 flex-wrap">
      {pieces.map((p, i) => (
        <span key={i} className="inline-flex items-center gap-1">
          <span className="text-surface-600">{p.label}</span>
          {/* DASH-ELEC-151 (Fixer-C26 2026-04-25): cn() instead of template
              literal so the JIT scanner sees `font-mono` as a literal token
              and the override class arrives intact (no whitespace surprise
              if a future contributor forgets the leading space). */}
          <span className={cn('font-mono', p.className ?? 'text-surface-400')}>{p.value}</span>
          {i < pieces.length - 1 && <span className="text-surface-700">·</span>}
        </span>
      ))}
    </footer>
  );
}
