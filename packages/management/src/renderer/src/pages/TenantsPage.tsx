import { useState, useEffect, useCallback, useMemo } from 'react';
import { Users, Plus, RefreshCw, Search, Pause, Play, Trash2, ExternalLink, Wrench, ChevronDown, ChevronRight } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { Tenant, TenantCreateResult } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { CopyText } from '@/components/CopyText';
import { formatDateTime } from '@/utils/format';
import { cn } from '@/utils/cn';
import toast from 'react-hot-toast';
import { PLAN_DEFINITIONS, type TenantPlan } from '@bizarre-crm/shared';

const PLAN_OPTIONS = Object.values(PLAN_DEFINITIONS);
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

interface LastCreatedTenant {
  slug: string;
  setup_url?: string;
  url?: string;
}

interface TenantDetail {
  user_count: number;
  ticket_count: number;
  customer_count: number;
  db_size_mb: number;
}

export function TenantsPage() {
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<Tenant | null>(null);
  const [lastCreated, setLastCreated] = useState<LastCreatedTenant | null>(null);
  const [expandedSlug, setExpandedSlug] = useState<string | null>(null);
  const [detailCache, setDetailCache] = useState<Record<string, TenantDetail | 'loading' | 'error'>>({});
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'suspended'>('all');
  const [planFilter, setPlanFilter] = useState<string>('');

  // Create form state
  const [newSlug, setNewSlug] = useState('');
  const [newName, setNewName] = useState('');
  const [newEmail, setNewEmail] = useState('');
  const [newPlan, setNewPlan] = useState<TenantPlan>('free');
  const [creating, setCreating] = useState(false);

  const refresh = useCallback(async () => {
    try {
      const res = await getAPI().superAdmin.listTenants();
      // AUDIT-MGT-010: detect 401 and trigger global auto-logout.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const list = Array.isArray(res.data) ? res.data : (res.data as { tenants: Tenant[] }).tenants ?? [];
        setTenants(list);
      }
    } catch {
      toast.error('Failed to load tenants');
    } finally {
      setLoading(false);
    }
  }, []);

  useEffect(() => { refresh(); }, [refresh]);

  async function toggleExpand(slug: string) {
    if (expandedSlug === slug) {
      setExpandedSlug(null);
      return;
    }
    setExpandedSlug(slug);
    if (detailCache[slug] && detailCache[slug] !== 'error') return;
    setDetailCache((c) => ({ ...c, [slug]: 'loading' }));
    try {
      const res = await getAPI().superAdmin.getTenant(slug);
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        const d = res.data as unknown as TenantDetail;
        setDetailCache((c) => ({
          ...c,
          [slug]: {
            user_count: d.user_count ?? 0,
            ticket_count: d.ticket_count ?? 0,
            customer_count: d.customer_count ?? 0,
            db_size_mb: d.db_size_mb ?? 0,
          },
        }));
      } else {
        setDetailCache((c) => ({ ...c, [slug]: 'error' }));
      }
    } catch {
      setDetailCache((c) => ({ ...c, [slug]: 'error' }));
    }
  }

  const filteredTenants = tenants.filter(
    (t) => {
      if (statusFilter !== 'all' && t.status !== statusFilter) return false;
      if (planFilter && t.plan !== planFilter) return false;
      const q = search.toLowerCase();
      if (!q) return true;
      return (
        t.slug.toLowerCase().includes(q) ||
        t.name.toLowerCase().includes(q)
      );
    }
  );

  const planOptions = useMemo(
    () => Array.from(new Set(tenants.map((t) => t.plan))).sort(),
    [tenants]
  );

  const handleCreate = async () => {
    const slug = newSlug.trim().toLowerCase();
    const email = newEmail.trim();
    if (!slug || !newName.trim()) return;
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(slug) || slug.length < 3 || slug.length > 30) {
      toast.error('Slug must be 3-30 chars: lowercase letters, numbers, hyphens only');
      return;
    }
    if (!email) {
      toast.error('Admin email is required');
      return;
    }
    if (!EMAIL_RE.test(email)) {
      toast.error('Invalid email format');
      return;
    }
    setCreating(true);
    try {
      const res = await getAPI().superAdmin.createTenant({
        slug,
        shop_name: newName.trim(),
        admin_email: email,
        plan: newPlan,
      });
      if (res.success) {
        const created = res.data as TenantCreateResult | undefined;
        setLastCreated({
          slug: created?.slug ?? slug,
          setup_url: created?.setup_url,
          url: created?.url,
        });
        toast.success('Tenant created');
        setShowCreate(false);
        setNewSlug(''); setNewName(''); setNewEmail(''); setNewPlan('free');
        refresh();
      } else {
        toast.error(res.message ?? 'Failed to create tenant');
      }
    } catch {
      toast.error('Failed to create tenant');
    } finally {
      setCreating(false);
    }
  };

  const handleSuspend = async (slug: string) => {
    const res = await getAPI().superAdmin.suspendTenant(slug);
    if (res.success) { toast.success('Tenant suspended'); refresh(); }
    else toast.error(res.message ?? 'Failed');
  };

  const handleActivate = async (slug: string) => {
    const res = await getAPI().superAdmin.activateTenant(slug);
    if (res.success) { toast.success('Tenant activated'); refresh(); }
    else toast.error(res.message ?? 'Failed');
  };

  // TPH6: additive repair. Never deletes — only creates missing pieces.
  // If the repair had to generate a new setup token (zero users), the URL is
  // returned ONCE and surfaced via lastCreated so the operator can copy it.
  const handleRepair = async (slug: string) => {
    const res = await getAPI().superAdmin.repairTenant(slug);
    if (res.success) {
      toast.success('Tenant repaired');
      const payload = res.data;
      if (payload?.setup_url) {
        setLastCreated({ slug, setup_url: payload.setup_url });
      }
      refresh();
    } else {
      toast.error(res.message ?? 'Repair failed');
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    const res = await getAPI().superAdmin.deleteTenant(deleteTarget.slug);
    if (res.success) { toast.success('Tenant deleted'); setDeleteTarget(null); refresh(); }
    else toast.error(res.message ?? 'Failed');
  };

  const copySetupLink = async (url: string) => {
    try {
      await navigator.clipboard.writeText(url);
      toast.success('Setup link copied');
    } catch {
      toast.error('Copy failed');
    }
  };

  if (loading) {
    return <div className="flex items-center justify-center py-20"><RefreshCw className="w-5 h-5 text-surface-500 animate-spin" /></div>;
  }

  return (
    <div className="space-y-3 lg:space-y-5 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-base lg:text-lg font-bold text-surface-100 flex items-center gap-2">
          <Users className="w-5 h-5 text-accent-400" />
          Tenants ({tenants.length})
        </h1>
        <div className="flex items-center gap-2">
          <button onClick={refresh} className="p-2 rounded-lg text-surface-400 hover:text-surface-200 hover:bg-surface-800">
            <RefreshCw className="w-4 h-4" />
          </button>
          <button
            onClick={() => setShowCreate(true)}
            className="flex items-center gap-1.5 px-3 py-2 text-xs font-medium bg-accent-600 text-white rounded-lg hover:bg-accent-700"
          >
            <Plus className="w-3.5 h-3.5" />
            New Tenant
          </button>
        </div>
      </div>

      {/* Aggregate stats — total / active / suspended / DB size */}
      {tenants.length > 0 && (() => {
        const active = tenants.filter((t) => t.status === 'active').length;
        const suspended = tenants.length - active;
        const totalBytes = tenants.reduce((a, t) => a + (t.db_size_bytes ?? 0), 0);
        const planCounts = tenants.reduce<Record<string, number>>((acc, t) => {
          acc[t.plan] = (acc[t.plan] ?? 0) + 1;
          return acc;
        }, {});
        return (
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 md:gap-3">
            <div className="stat-card">
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Tenants</div>
              <div className="text-lg lg:text-2xl font-bold text-surface-100">{tenants.length}</div>
            </div>
            <div className="stat-card">
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Active</div>
              <div className="text-lg lg:text-2xl font-bold text-emerald-300">
                {active}<span className="text-xs text-surface-500"> / {tenants.length}</span>
              </div>
            </div>
            <div className="stat-card">
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Suspended</div>
              <div className={cn('text-lg lg:text-2xl font-bold', suspended > 0 ? 'text-amber-300' : 'text-surface-300')}>{suspended}</div>
            </div>
            <div className="stat-card">
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Total DB</div>
              <div className="text-lg lg:text-2xl font-bold text-surface-100">
                {totalBytes > 0
                  ? `${(totalBytes / 1024 / 1024).toFixed(1)} MB`
                  : '—'}
              </div>
              <div className="text-[9px] lg:text-[10px] text-surface-500 mt-0.5 lg:mt-1 truncate" title={Object.entries(planCounts).map(([p, n]) => `${n} ${p}`).join(' • ')}>
                {Object.entries(planCounts).map(([p, n]) => `${n} ${p}`).join(' • ')}
              </div>
            </div>
          </div>
        );
      })()}

      {/* Search + filter chips */}
      <div className="flex items-center gap-2 flex-wrap">
        <div className="relative flex-1 min-w-[200px]">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-500" />
          <input
            type="text" value={search} onChange={(e) => setSearch(e.target.value)}
            placeholder="Search tenants..."
            className="w-full pl-10 pr-4 py-2 bg-surface-900 border border-surface-700 rounded-lg text-sm text-surface-200 placeholder:text-surface-600 focus:border-accent-500 focus:outline-none"
          />
        </div>
        <div className="flex items-center gap-1 text-xs">
          {(['all', 'active', 'suspended'] as const).map((s) => (
            <button
              key={s}
              onClick={() => setStatusFilter(s)}
              className={`px-2.5 py-1 rounded border transition-colors ${
                statusFilter === s
                  ? 'bg-accent-600/20 border-accent-600 text-accent-300'
                  : 'border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600'
              }`}
            >
              {s[0].toUpperCase() + s.slice(1)}
            </button>
          ))}
        </div>
        {planOptions.length > 1 && (
          <select
            value={planFilter}
            onChange={(e) => setPlanFilter(e.target.value)}
            className="px-2 py-1 text-xs bg-surface-950 border border-surface-700 rounded text-surface-200"
          >
            <option value="">Any plan</option>
            {planOptions.map((p) => <option key={p} value={p}>{p}</option>)}
          </select>
        )}
      </div>

      {lastCreated?.setup_url ? (
        <div className="rounded-lg border border-green-700/50 bg-green-950/30 p-4 text-sm text-green-100">
          <div className="flex items-start justify-between gap-3">
            <div className="min-w-0">
              <p className="font-semibold">Tenant created: {lastCreated.slug}</p>
              <p className="mt-1 text-green-200">Send this setup link to the shop admin so they can set their password.</p>
              <p className="mt-2 break-all font-mono text-xs text-green-100">{lastCreated.setup_url}</p>
            </div>
            <button
              onClick={() => copySetupLink(lastCreated.setup_url!)}
              className="shrink-0 rounded-lg bg-green-700 px-3 py-2 text-xs font-semibold text-white hover:bg-green-600"
            >
              Copy
            </button>
          </div>
        </div>
      ) : null}

      {/* Tenant list — empty-state CTA when the install has never created
          a tenant (fresh super-admin + multi-tenant mode). Falls back to a
          bare message when the search box filtered every tenant away. */}
      {filteredTenants.length === 0 ? (
        tenants.length === 0 ? (
          <div className="rounded-lg border border-dashed border-surface-700 bg-surface-900/50 p-8 text-center">
            <Users className="w-8 h-8 text-surface-600 mx-auto mb-2" />
            <p className="text-sm text-surface-200">No tenants yet</p>
            <p className="text-xs text-surface-500 mt-1 max-w-sm mx-auto leading-relaxed">
              Every shop that uses this server is a tenant. Create one now to
              get a slug, an admin setup link, and (if Cloudflare is configured)
              a DNS record.
            </p>
            <button
              onClick={() => setShowCreate(true)}
              className="mt-4 inline-flex items-center gap-1.5 px-3 py-2 text-xs font-medium bg-accent-600 text-white rounded-lg hover:bg-accent-700"
            >
              <Plus className="w-3.5 h-3.5" />
              Create first tenant
            </button>
          </div>
        ) : (
          <div className="text-center py-12 text-sm text-surface-500">
            No tenants match <code className="font-mono text-surface-400">{search}</code>.
          </div>
        )
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Slug</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Name</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Status</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Plan</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">DB size</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Created</th>
                <th className="text-right py-2 px-3 text-xs text-surface-500 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredTenants.map((t) => {
                const isOpen = expandedSlug === t.slug;
                const detail = detailCache[t.slug];
                return (
                <>
                <tr
                  key={t.id}
                  className="border-b border-surface-800/50 hover:bg-surface-800/30 cursor-pointer"
                  onClick={() => toggleExpand(t.slug)}
                >
                  <td className="py-2.5 px-3 font-mono text-accent-400 text-xs">
                    <span className="inline-flex items-center gap-1">
                      {isOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                      <CopyText value={t.slug} toastLabel={`Copied ${t.slug}`}>{t.slug}</CopyText>
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-surface-200">{t.name}</td>
                  <td className="py-2.5 px-3">
                    <span className={cn(
                      'px-2 py-0.5 rounded-full text-xs font-medium',
                      t.status === 'active' ? 'bg-green-900/40 text-green-300' : 'bg-red-900/40 text-red-300'
                    )}>
                      {t.status}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-surface-400 text-xs">{t.plan}</td>
                  <td className="py-2.5 px-3 text-surface-400 text-xs whitespace-nowrap">
                    {t.db_size_bytes
                      ? `${(t.db_size_bytes / 1024 / 1024).toFixed(1)} MB`
                      : '—'}
                  </td>
                  <td className="py-2.5 px-3 text-surface-500 text-xs">{formatDateTime(t.created_at)}</td>
                  <td className="py-2.5 px-3" onClick={(e) => e.stopPropagation()}>
                    <div className="flex items-center justify-end gap-1">
                      <button
                        onClick={async () => {
                          // @audit-fixed: this previously called openExternal
                          // for `https://${slug}.localhost` and silently failed
                          // because the system:open-external IPC handler in
                          // src/main/ipc/system-info.ts only allows the bare
                          // loopback hostnames (localhost / 127.0.0.1 / ::1).
                          // Subdomains like `myshop.localhost` were rejected
                          // with no UI feedback. Until the IPC handler is
                          // expanded to allow `*.localhost` resolution, we
                          // open the bare loopback URL with the tenant slug
                          // as a query string so super admins can still reach
                          // the right tenant view, and we surface failures
                          // via toast instead of dropping them.
                          try {
                            const res = await getAPI().system.openExternal(
                              `https://localhost/?tenant=${encodeURIComponent(t.slug)}`
                            );
                            if (res && res.success === false) {
                              toast.error(res.message ?? 'Failed to open tenant URL');
                            }
                          } catch (err) {
                            toast.error(err instanceof Error ? err.message : 'Failed to open tenant URL');
                          }
                        }}
                        className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-700" title="Open"
                      >
                        <ExternalLink className="w-3.5 h-3.5" />
                      </button>
                      {t.status === 'active' ? (
                        <button onClick={() => handleSuspend(t.slug)} className="p-1.5 rounded text-amber-500 hover:text-amber-300 hover:bg-surface-700" title="Suspend">
                          <Pause className="w-3.5 h-3.5" />
                        </button>
                      ) : (
                        <button onClick={() => handleActivate(t.slug)} className="p-1.5 rounded text-green-500 hover:text-green-300 hover:bg-surface-700" title="Activate">
                          <Play className="w-3.5 h-3.5" />
                        </button>
                      )}
                      {t.status !== 'active' && (
                        <button
                          onClick={() => handleRepair(t.slug)}
                          className="p-1.5 rounded text-blue-500 hover:text-blue-300 hover:bg-surface-700"
                          title="Repair (additive — creates missing pieces, never deletes)"
                        >
                          <Wrench className="w-3.5 h-3.5" />
                        </button>
                      )}
                      <button onClick={() => setDeleteTarget(t)} className="p-1.5 rounded text-red-500 hover:text-red-300 hover:bg-surface-700" title="Delete">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                  </td>
                </tr>
                {isOpen && (
                  <tr key={t.slug + '-detail'} className="border-b border-surface-800 bg-surface-900/30">
                    <td colSpan={7} className="px-3 py-3">
                      {detail === 'loading' || detail === undefined ? (
                        <p className="text-xs text-surface-500">Loading tenant metrics…</p>
                      ) : detail === 'error' ? (
                        <p className="text-xs text-red-400">Failed to load tenant metrics.</p>
                      ) : (
                        <div className="grid grid-cols-2 sm:grid-cols-4 gap-2 text-xs">
                          <DetailMetric label="Active users" value={detail.user_count} />
                          <DetailMetric label="Tickets" value={detail.ticket_count} />
                          <DetailMetric label="Customers" value={detail.customer_count} />
                          <DetailMetric label="DB size" value={`${detail.db_size_mb.toFixed(1)} MB`} />
                        </div>
                      )}
                    </td>
                  </tr>
                )}
                </>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Create Modal */}
      {showCreate && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
          <div className="w-[420px] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6">
            <h3 className="text-sm font-semibold text-surface-100 mb-4">Create New Tenant</h3>
            <div className="space-y-3 mb-5">
              <input type="text" value={newSlug} onChange={(e) => setNewSlug(e.target.value)} placeholder="Slug (e.g. my-shop)"
                className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
              <input type="text" value={newName} onChange={(e) => setNewName(e.target.value)} placeholder="Shop name"
                className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
              <input type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} placeholder="Admin email (required)"
                className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
              <select value={newPlan} onChange={(e) => setNewPlan(e.target.value as TenantPlan)}
                className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none">
                {PLAN_OPTIONS.map((plan) => (
                  <option key={plan.name} value={plan.name}>{plan.displayName}</option>
                ))}
              </select>
            </div>
            <div className="flex justify-end gap-2">
              <button onClick={() => setShowCreate(false)} className="px-4 py-2 text-sm text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700">Cancel</button>
              <button onClick={handleCreate} disabled={creating || !newSlug.trim() || !newName.trim() || !newEmail.trim()}
                className="px-4 py-2 text-sm font-semibold bg-accent-600 text-white rounded-lg hover:bg-accent-700 disabled:opacity-40">
                {creating ? 'Creating...' : 'Create'}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Delete confirm */}
      <ConfirmDialog
        open={deleteTarget !== null}
        title="Delete Tenant"
        message={`This will permanently delete "${deleteTarget?.name}" and all its data. This cannot be undone.`}
        danger requireTyping={deleteTarget?.slug}
        confirmLabel="Delete Tenant"
        onConfirm={handleDelete}
        onCancel={() => setDeleteTarget(null)}
      />
    </div>
  );
}

function DetailMetric({ label, value }: { label: string; value: string | number }) {
  return (
    <div className="rounded border border-surface-800 bg-surface-950/60 px-2.5 py-1.5">
      <div className="text-[10px] text-surface-500 uppercase tracking-wider">{label}</div>
      <div className="text-sm font-bold text-surface-100 mt-0.5">{value}</div>
    </div>
  );
}
