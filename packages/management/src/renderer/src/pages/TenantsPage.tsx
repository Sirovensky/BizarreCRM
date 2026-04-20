import { useState, useEffect, useCallback } from 'react';
import { Users, Plus, RefreshCw, Search, Pause, Play, Trash2, ExternalLink, Wrench } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { Tenant, TenantCreateResult } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
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

export function TenantsPage() {
  const [tenants, setTenants] = useState<Tenant[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<Tenant | null>(null);
  const [lastCreated, setLastCreated] = useState<LastCreatedTenant | null>(null);

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

  const filteredTenants = tenants.filter(
    (t) =>
      t.slug.toLowerCase().includes(search.toLowerCase()) ||
      t.name.toLowerCase().includes(search.toLowerCase())
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
    <div className="space-y-6 animate-fade-in">
      <div className="flex items-center justify-between">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
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

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-surface-500" />
        <input
          type="text" value={search} onChange={(e) => setSearch(e.target.value)}
          placeholder="Search tenants..."
          className="w-full pl-10 pr-4 py-2 bg-surface-900 border border-surface-700 rounded-lg text-sm text-surface-200 placeholder:text-surface-600 focus:border-accent-500 focus:outline-none"
        />
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

      {/* Tenant list */}
      {filteredTenants.length === 0 ? (
        <div className="text-center py-12 text-sm text-surface-500">No tenants found</div>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-800">
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Slug</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Name</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Status</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Plan</th>
                <th className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Created</th>
                <th className="text-right py-2 px-3 text-xs text-surface-500 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredTenants.map((t) => (
                <tr key={t.id} className="border-b border-surface-800/50 hover:bg-surface-800/30">
                  <td className="py-2.5 px-3 font-mono text-accent-400 text-xs">{t.slug}</td>
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
                  <td className="py-2.5 px-3 text-surface-500 text-xs">{formatDateTime(t.created_at)}</td>
                  <td className="py-2.5 px-3">
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
              ))}
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
