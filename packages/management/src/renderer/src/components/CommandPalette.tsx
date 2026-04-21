import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import {
  Command, Search, ArrowRight, LayoutDashboard, Users, Power, Database,
  AlertTriangle, Download, Activity, FileText, Stethoscope, Wrench, Settings,
  RefreshCw, PlayCircle, StopCircle, LogOut, X,
} from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { useServerStore } from '@/stores/serverStore';
import { useAuthStore } from '@/stores/authStore';
import toast from 'react-hot-toast';

interface CommandEntry {
  id: string;
  label: string;
  /** Extra searchable text (category, keywords) not shown directly. */
  keywords?: string;
  icon: React.ElementType;
  /** Either navigate to a route or fire an action. */
  onRun: () => void | Promise<void>;
  /** Group label for visual separation in results. */
  group: 'Pages' | 'Actions';
}

/**
 * Global command palette — Cmd/Ctrl+K opens it, `/` inside a non-input also
 * opens it. Arrow keys navigate, Enter executes, Escape closes. Results are
 * a substring match across label + keywords; no fuzzy scoring library
 * because the command list is small (~20 items) and operators type full
 * words like "backup" or "restart".
 */
export function CommandPalette() {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [activeIdx, setActiveIdx] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);
  const navigate = useNavigate();
  const isMultiTenant = useServerStore((s) => s.stats?.multiTenant) ?? false;
  const logout = useAuthStore((s) => s.logout);

  const commands = useMemo<CommandEntry[]>(() => {
    const list: CommandEntry[] = [
      // Pages — navigable routes
      { id: 'nav-overview', group: 'Pages', label: 'Overview', icon: LayoutDashboard, onRun: () => navigate('/') },
      { id: 'nav-server', group: 'Pages', label: 'Server Control', icon: Power, keywords: 'start stop restart pm2', onRun: () => navigate('/server') },
      { id: 'nav-backups', group: 'Pages', label: 'Backups', icon: Database, onRun: () => navigate('/backups') },
      { id: 'nav-crashes', group: 'Pages', label: 'Crash Monitor', icon: AlertTriangle, keywords: 'errors exceptions', onRun: () => navigate('/crashes') },
      { id: 'nav-updates', group: 'Pages', label: 'Updates', icon: Download, keywords: 'upgrade version git pull', onRun: () => navigate('/updates') },
      { id: 'nav-logs', group: 'Pages', label: 'Server Logs', icon: FileText, keywords: 'pm2 stderr stdout tail', onRun: () => navigate('/logs') },
      { id: 'nav-settings', group: 'Pages', label: 'Settings', icon: Settings, keywords: 'env stripe cloudflare captcha kill-switch', onRun: () => navigate('/settings') },
    ];
    if (isMultiTenant) {
      list.push(
        { id: 'nav-tenants', group: 'Pages', label: 'Tenants', icon: Users, onRun: () => navigate('/tenants') },
        { id: 'nav-activity', group: 'Pages', label: 'Activity (alerts, audit, sessions)', icon: Activity, keywords: 'security alerts audit sessions tenant auth', onRun: () => navigate('/activity') },
        { id: 'nav-activity-alerts', group: 'Pages', label: 'Activity → Security Alerts', icon: Activity, keywords: 'unacknowledged', onRun: () => navigate('/activity?tab=alerts') },
        { id: 'nav-activity-audit', group: 'Pages', label: 'Activity → Audit Log', icon: Activity, onRun: () => navigate('/activity?tab=audit') },
        { id: 'nav-diagnostics', group: 'Pages', label: 'Tenant Diagnostics', icon: Stethoscope, keywords: 'notifications webhooks automations', onRun: () => navigate('/diagnostics') },
        { id: 'nav-tools', group: 'Pages', label: 'Admin Tools', icon: Wrench, keywords: 'reset rate limit backfill dns', onRun: () => navigate('/tools') },
      );
    }
    // Actions — one-shot commands
    list.push(
      {
        id: 'act-backup-now', group: 'Actions', label: 'Run backup now',
        icon: Database, keywords: 'snapshot',
        onRun: async () => {
          const res = await getAPI().admin.runBackup();
          if (res.success) toast.success('Backup completed');
          else toast.error(res.message ?? 'Backup failed');
        },
      },
      {
        id: 'act-restart-server', group: 'Actions', label: 'Restart server',
        icon: RefreshCw, keywords: 'pm2 reload',
        onRun: async () => {
          const proceed = window.confirm('Restart the CRM server process? Active tenant sessions will briefly disconnect.');
          if (!proceed) return;
          const res = await getAPI().service.restart();
          if (res.success) toast.success('Server restart requested');
          else toast.error(res.message ?? 'Restart failed');
        },
      },
      {
        id: 'act-start-server', group: 'Actions', label: 'Start server',
        icon: PlayCircle, onRun: async () => {
          const res = await getAPI().service.start();
          if (res.success) toast.success('Start requested');
          else toast.error(res.message ?? 'Start failed');
        },
      },
      {
        id: 'act-stop-server', group: 'Actions', label: 'Stop server',
        icon: StopCircle, onRun: async () => {
          const proceed = window.confirm('Stop the CRM server process? All tenant requests will fail until it is restarted.');
          if (!proceed) return;
          const res = await getAPI().service.stop();
          if (res.success) toast.success('Stop requested');
          else toast.error(res.message ?? 'Stop failed');
        },
      },
      {
        id: 'act-logout', group: 'Actions', label: 'Log out',
        icon: LogOut, keywords: 'sign out',
        onRun: async () => {
          try { await getAPI().management.logout(); } catch { /* ignore — local logout still fires */ }
          logout();
          navigate('/login', { replace: true });
        },
      },
      {
        id: 'act-close-dashboard', group: 'Actions', label: 'Close dashboard',
        icon: X, keywords: 'quit exit',
        onRun: async () => {
          await getAPI().system.closeDashboard();
        },
      },
    );
    return list;
  }, [isMultiTenant, navigate, logout]);

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return commands;
    return commands.filter((c) => {
      const hay = `${c.label} ${c.keywords ?? ''} ${c.group}`.toLowerCase();
      return hay.includes(q);
    });
  }, [commands, query]);

  // Reset active index when filter changes
  useEffect(() => { setActiveIdx(0); }, [query, open]);

  const onKeyDownGlobal = useCallback((e: KeyboardEvent) => {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      setOpen((v) => !v);
      return;
    }
    // Plain `/` opens the palette unless the operator is already typing in an input.
    if (e.key === '/' && !open) {
      const tag = (e.target as HTMLElement | null)?.tagName;
      if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') {
        e.preventDefault();
        setOpen(true);
      }
    }
  }, [open]);

  useEffect(() => {
    window.addEventListener('keydown', onKeyDownGlobal);
    return () => window.removeEventListener('keydown', onKeyDownGlobal);
  }, [onKeyDownGlobal]);

  useEffect(() => {
    if (open) setTimeout(() => inputRef.current?.focus(), 0);
    else setQuery('');
  }, [open]);

  if (!open) return null;

  async function run(cmd: CommandEntry) {
    setOpen(false);
    try {
      await cmd.onRun();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Command failed');
    }
  }

  function onInputKeyDown(e: React.KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'Escape') { setOpen(false); return; }
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActiveIdx((i) => Math.min(filtered.length - 1, i + 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActiveIdx((i) => Math.max(0, i - 1));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      const target = filtered[activeIdx];
      if (target) run(target);
    }
  }

  // Build grouped display without losing global index.
  const pages = filtered.filter((c) => c.group === 'Pages');
  const actions = filtered.filter((c) => c.group === 'Actions');

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-24 bg-black/60 backdrop-blur-sm"
      onClick={() => setOpen(false)}
    >
      <div
        className="w-[min(520px,calc(100vw-2rem))] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-800">
          <Search className="w-4 h-4 text-surface-500" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={onInputKeyDown}
            placeholder="Jump to page or run a command…"
            className="flex-1 bg-transparent text-sm text-surface-100 placeholder:text-surface-600 focus:outline-none"
          />
          <span className="text-[10px] text-surface-500 font-mono border border-surface-700 rounded px-1.5 py-0.5">
            esc
          </span>
        </div>
        <div className="max-h-[50vh] overflow-y-auto py-1">
          {filtered.length === 0 ? (
            <p className="text-center text-xs text-surface-500 py-6">No commands match.</p>
          ) : (
            <>
              {pages.length > 0 && (
                <CommandGroup
                  label="Pages"
                  items={pages}
                  active={filtered[activeIdx]}
                  onRun={run}
                  onHover={(c) => setActiveIdx(filtered.indexOf(c))}
                />
              )}
              {actions.length > 0 && (
                <CommandGroup
                  label="Actions"
                  items={actions}
                  active={filtered[activeIdx]}
                  onRun={run}
                  onHover={(c) => setActiveIdx(filtered.indexOf(c))}
                />
              )}
            </>
          )}
        </div>
        <div className="px-3 py-2 border-t border-surface-800 flex items-center gap-3 text-[10px] text-surface-500">
          <span className="flex items-center gap-1"><Command className="w-3 h-3" />K to toggle</span>
          <span>↑↓ navigate</span>
          <span>↵ run</span>
        </div>
      </div>
    </div>
  );
}

function CommandGroup({
  label, items, active, onRun, onHover,
}: {
  label: string;
  items: CommandEntry[];
  active: CommandEntry | undefined;
  onRun: (c: CommandEntry) => void;
  onHover: (c: CommandEntry) => void;
}) {
  return (
    <div>
      <div className="px-3 pt-2 pb-1 text-[10px] font-semibold text-surface-500 uppercase tracking-wider">
        {label}
      </div>
      {items.map((c) => {
        const Icon = c.icon;
        const isActive = active?.id === c.id;
        return (
          <button
            key={c.id}
            onMouseEnter={() => onHover(c)}
            onClick={() => onRun(c)}
            className={`w-full flex items-center gap-2 px-3 py-1.5 text-left text-sm transition-colors ${
              isActive
                ? 'bg-accent-600/20 text-surface-100'
                : 'text-surface-300 hover:bg-surface-800/60'
            }`}
          >
            <Icon className="w-3.5 h-3.5 flex-shrink-0 text-surface-500" />
            <span className="flex-1 truncate">{c.label}</span>
            {isActive && <ArrowRight className="w-3 h-3 text-accent-400" />}
          </button>
        );
      })}
    </div>
  );
}
