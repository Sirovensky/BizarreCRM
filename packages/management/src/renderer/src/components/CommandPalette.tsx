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
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
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
  const [pendingConfirm, setPendingConfirm] = useState<null | {
    title: string; message: string; onConfirm: () => Promise<void>;
  }>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const listboxId = 'command-palette-listbox';
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
        // DASH-ELEC-051: Sessions deep-link parity with the alerts/audit deep-links above.
        { id: 'nav-activity-sessions', group: 'Pages', label: 'Activity → Sessions', icon: Activity, keywords: 'session token revoke', onRun: () => navigate('/activity?tab=sessions') },
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
          await new Promise<void>((resolve) => {
            setPendingConfirm({
              title: 'Restart server?',
              message: 'Active tenant sessions will briefly disconnect while the CRM server restarts.',
              onConfirm: async () => {
                const res = await getAPI().service.restart();
                if (res.success) toast.success('Server restart requested. May take up to a minute to come back online.');
                else toast.error(res.message ?? 'Restart failed');
                resolve();
              },
            });
          });
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
          await new Promise<void>((resolve) => {
            setPendingConfirm({
              title: 'Stop server?',
              message: 'All tenant requests will fail until the server is restarted.',
              onConfirm: async () => {
                const res = await getAPI().service.stop();
                if (res.success) toast.success('Stop requested');
                else toast.error(res.message ?? 'Stop failed');
                resolve();
              },
            });
          });
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

  if (!open && !pendingConfirm) return null;

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

  const activeId = filtered[activeIdx] ? `cmd-opt-${filtered[activeIdx].id}` : undefined;

  return (
    <>
      {open && (
        <div
          className="fixed inset-0 z-50 flex items-start justify-center pt-[max(1rem,min(6rem,10vh))] bg-black/60 backdrop-blur-sm"
          onClick={() => setOpen(false)}
        >
          <div
            className="w-[min(520px,calc(100vw-2rem))] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-800">
              <Search className="w-4 h-4 text-surface-500" aria-hidden="true" />
              <input
                ref={inputRef}
                type="text"
                role="combobox"
                aria-expanded={filtered.length > 0}
                aria-autocomplete="list"
                aria-controls={listboxId}
                aria-activedescendant={activeId}
                value={query}
                onChange={(e) => setQuery(e.target.value)}
                onKeyDown={onInputKeyDown}
                placeholder="Jump to page or run a command…"
                aria-label="Command palette search"
                className="flex-1 bg-transparent text-sm text-surface-100 placeholder:text-surface-600 focus:outline-none focus:ring-2 focus:ring-accent-500 focus:ring-offset-0 rounded"
              />
              <span className="text-[10px] text-surface-500 font-mono border border-surface-700 rounded px-1.5 py-0.5">
                esc
              </span>
            </div>
            <div id={listboxId} role="listbox" aria-label="Commands" className="max-h-[50vh] overflow-y-auto py-1">
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
              <span className="flex items-center gap-1"><Command className="w-3 h-3" aria-hidden="true" />K to toggle</span>
              <span>↑↓ navigate</span>
              <span>↵ run</span>
            </div>
          </div>
        </div>
      )}
      {pendingConfirm && (
        <ConfirmDialog
          open={true}
          title={pendingConfirm.title}
          message={pendingConfirm.message}
          confirmLabel="Confirm"
          danger
          onConfirm={async () => {
            const cfg = pendingConfirm;
            setPendingConfirm(null);
            try { await cfg.onConfirm(); } catch (err) {
              toast.error(err instanceof Error ? err.message : 'Command failed');
            }
          }}
          onCancel={() => setPendingConfirm(null)}
        />
      )}
    </>
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
      {/* DASH-ELEC-031: promote to <h3> so SR users can skim group headings */}
      <h3 className="px-3 pt-2 pb-1 text-[10px] font-semibold text-surface-500 uppercase tracking-wider">
        {label}
      </h3>
      {items.map((c) => {
        const Icon = c.icon;
        const isActive = active?.id === c.id;
        return (
          <button
            key={c.id}
            id={`cmd-opt-${c.id}`}
            role="option"
            aria-selected={isActive}
            onMouseEnter={() => onHover(c)}
            onClick={() => onRun(c)}
            className={`w-full flex items-center gap-2 px-3 py-1.5 text-left text-sm transition-colors ${
              isActive
                ? 'bg-accent-600/20 text-surface-100'
                : 'text-surface-300 hover:bg-surface-800/60'
            }`}
          >
            <Icon className="w-3.5 h-3.5 flex-shrink-0 text-surface-500" aria-hidden="true" />
            <span className="flex-1 truncate">{c.label}</span>
            {isActive && <ArrowRight className="w-3 h-3 text-accent-400" aria-hidden="true" />}
          </button>
        );
      })}
    </div>
  );
}
