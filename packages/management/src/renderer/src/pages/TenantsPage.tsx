import { Fragment, useState, useEffect, useCallback, useMemo, useRef } from 'react';
import { Users, Plus, RefreshCw, Search, Pause, Play, Trash2, ExternalLink, Wrench, ChevronDown, ChevronRight, Pencil, Check, X } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { Tenant } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { CopyText } from '@/components/CopyText';
import { formatDateTime } from '@/utils/format';
import { cn } from '@/utils/cn';
import toast from 'react-hot-toast';
import { PLAN_DEFINITIONS, type TenantPlan } from '@bizarre-crm/shared';
import { formatApiError } from '@/utils/apiError';

const PLAN_OPTIONS = Object.values(PLAN_DEFINITIONS);
const PLAN_NAME_SET = new Set<string>(PLAN_OPTIONS.map((plan) => plan.name));
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const STAT_CARD_CLASS = 'relative overflow-hidden rounded-lg border border-surface-800 bg-surface-900 p-3 lg:p-4 transition-colors hover:border-surface-700';
const TENANT_ACTION_REASON_MAX = 1000;
const TENANT_NAME_MAX = 200;
const DISALLOWED_TENANT_NAME_CHARS = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u202A-\u202E\u2066-\u2069]/;
type BulkAction = 'suspend' | 'activate' | 'delete';

function isTenantPlan(value: string): value is TenantPlan {
  return PLAN_NAME_SET.has(value);
}

function planLabel(value: string): string {
  return isTenantPlan(value) ? PLAN_DEFINITIONS[value].displayName : value;
}

function describePlanLimits(plan: TenantPlan): string {
  const limits = PLAN_DEFINITIONS[plan].limits;
  const tickets = limits.maxTicketsMonth === null ? 'unlimited tickets/month' : `${limits.maxTicketsMonth.toLocaleString()} tickets/month`;
  const users = limits.maxUsers === null ? 'unlimited users' : `${limits.maxUsers.toLocaleString()} user${limits.maxUsers === 1 ? '' : 's'}`;
  const storage = limits.storageLimitMb === null
    ? 'unlimited storage'
    : limits.storageLimitMb >= 1024
      ? `${(limits.storageLimitMb / 1024).toLocaleString(undefined, { maximumFractionDigits: 1 })} GB storage`
      : `${limits.storageLimitMb.toLocaleString()} MB storage`;
  return `${tickets}, ${users}, ${storage}`;
}

function formatTenantTimestamp(value?: string | null): string {
  return value ? formatDateTime(value) : '—';
}

function tenantActionReasonError(action: 'suspend' | 'activate', reason: string): string | null {
  const trimmed = reason.trim();
  if (action === 'suspend' && trimmed.length === 0) {
    return 'Enter a reason before suspending tenants.';
  }
  if (reason.length > TENANT_ACTION_REASON_MAX) {
    return `Reason must be ${TENANT_ACTION_REASON_MAX} characters or fewer.`;
  }
  return null;
}

function tenantNameError(value: string): string | null {
  const trimmed = value.trim();
  if (trimmed.length === 0) return 'Shop name is required.';
  if (trimmed.length > TENANT_NAME_MAX) return `Shop name must be ${TENANT_NAME_MAX} characters or fewer.`;
  if (DISALLOWED_TENANT_NAME_CHARS.test(trimmed)) return 'Shop name contains unsupported control characters.';
  return null;
}

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
  // DASH-ELEC-242: debounce keystrokes so we don't re-filter the (potentially
  // 200-row) tenant list on every keypress. 150 ms is below human-perception
  // latency for typing flow but coalesces fast typists.
  const [debouncedSearch, setDebouncedSearch] = useState('');
  useEffect(() => {
    const id = setTimeout(() => setDebouncedSearch(search), 150);
    return () => clearTimeout(id);
  }, [search]);
  const [showCreate, setShowCreate] = useState(false);
  const [deleteTarget, setDeleteTarget] = useState<Tenant | null>(null);
  const [suspendTarget, setSuspendTarget] = useState<Tenant | null>(null);
  const [activateTarget, setActivateTarget] = useState<Tenant | null>(null);
  const [tenantActionReason, setTenantActionReason] = useState('');
  const [tenantActionReasonErrorText, setTenantActionReasonErrorText] = useState<string | null>(null);
  // DASH-ELEC-133: gate Repair behind a ConfirmDialog so a stray click can't
  // recreate setup tokens / DB tables silently.
  const [repairTarget, setRepairTarget] = useState<Tenant | null>(null);
  const [selectedSlugs, setSelectedSlugs] = useState<Set<string>>(new Set());
  const [bulkAction, setBulkAction] = useState<BulkAction | null>(null);
  const [bulkProcessing, setBulkProcessing] = useState(false);
  const [lastCreated, setLastCreated] = useState<LastCreatedTenant | null>(null);
  const [expandedSlug, setExpandedSlug] = useState<string | null>(null);
  const [detailCache, setDetailCache] = useState<Record<string, TenantDetail | 'loading' | 'error'>>({});
  // DASH-ELEC-241: track in-flight requests separately so a fetch that errors
  // before setting detailCache doesn't leave the row permanently stuck as
  // 'loading'.  The Set is a ref (not state) because updates don't need a
  // re-render themselves — detailCache updates drive re-renders.
  const detailInFlight = useRef<Set<string>>(new Set());
  const [statusFilter, setStatusFilter] = useState<'all' | 'active' | 'suspended'>('all');
  const [planFilter, setPlanFilter] = useState<string>('');
  const [planChangeTarget, setPlanChangeTarget] = useState<{ tenant: Tenant; nextPlan: TenantPlan } | null>(null);
  const [updatingPlanSlug, setUpdatingPlanSlug] = useState<string | null>(null);
  const [renamingSlug, setRenamingSlug] = useState<string | null>(null);
  const [renameValue, setRenameValue] = useState('');
  const [renameError, setRenameError] = useState<string | null>(null);
  const [savingRenameSlug, setSavingRenameSlug] = useState<string | null>(null);

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

  // DASH-ELEC-278: extracted so the inline error <p> can offer a Retry button
  // — without this, once detailCache[slug]==='error' the toggleExpand short-
  // circuit (line below) means re-clicking the row never re-fetches.
  async function loadDetail(slug: string) {
    // DASH-ELEC-241: guard against duplicate in-flight requests.
    if (detailInFlight.current.has(slug)) return;
    detailInFlight.current.add(slug);
    setDetailCache((c) => ({ ...c, [slug]: 'loading' }));
    try {
      const res = await getAPI().superAdmin.getTenant(slug);
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        // DASH-ELEC-189: bridge.ts now types getTenant result with the
        // denormalised counts directly — no more `as unknown as` double cast.
        const d = res.data;
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
    } finally {
      detailInFlight.current.delete(slug);
    }
  }

  async function toggleExpand(slug: string) {
    if (expandedSlug === slug) {
      setExpandedSlug(null);
      return;
    }
    setExpandedSlug(slug);
    // Skip re-fetch if we have a good cache entry (not 'error').
    // DASH-ELEC-241: also skip if already in-flight (tracked by ref).
    if (
      detailCache[slug] &&
      detailCache[slug] !== 'error' &&
      !detailInFlight.current.has(slug)
    ) return;
    await loadDetail(slug);
  }

  const filteredTenants = tenants.filter(
    (t) => {
      if (statusFilter !== 'all' && t.status !== statusFilter) return false;
      if (planFilter && t.plan !== planFilter) return false;
      const q = debouncedSearch.toLowerCase();
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

  const visibleSlugs = useMemo(() => filteredTenants.map((t) => t.slug), [filteredTenants]);
  const selectedTenants = useMemo(
    () => tenants.filter((t) => selectedSlugs.has(t.slug)),
    [tenants, selectedSlugs]
  );
  const selectedVisibleCount = useMemo(
    () => visibleSlugs.reduce((count, slug) => count + (selectedSlugs.has(slug) ? 1 : 0), 0),
    [selectedSlugs, visibleSlugs]
  );
  const allVisibleSelected = visibleSlugs.length > 0 && selectedVisibleCount === visibleSlugs.length;
  const someVisibleSelected = selectedVisibleCount > 0 && !allVisibleSelected;
  const activeSelectedCount = selectedTenants.filter((t) => t.status === 'active').length;
  const suspendedSelectedCount = selectedTenants.filter((t) => t.status === 'suspended').length;

  const toggleSelectSlug = (slug: string) => {
    setSelectedSlugs((prev) => {
      const next = new Set(prev);
      if (next.has(slug)) next.delete(slug);
      else next.add(slug);
      return next;
    });
  };

  const toggleSelectVisible = () => {
    setSelectedSlugs((prev) => {
      const next = new Set(prev);
      if (allVisibleSelected) {
        visibleSlugs.forEach((slug) => next.delete(slug));
      } else {
        visibleSlugs.forEach((slug) => next.add(slug));
      }
      return next;
    });
  };

  const clearSelected = () => setSelectedSlugs(new Set());

  const resetTenantActionReason = () => {
    setTenantActionReason('');
    setTenantActionReasonErrorText(null);
  };

  const openSuspendConfirm = (tenant: Tenant) => {
    resetTenantActionReason();
    setSuspendTarget(tenant);
  };

  const openActivateConfirm = (tenant: Tenant) => {
    resetTenantActionReason();
    setActivateTarget(tenant);
  };

  const openBulkAction = (action: BulkAction) => {
    resetTenantActionReason();
    setBulkAction(action);
  };

  const closeSuspendConfirm = () => {
    setSuspendTarget(null);
    resetTenantActionReason();
  };

  const closeActivateConfirm = () => {
    setActivateTarget(null);
    resetTenantActionReason();
  };

  const closeBulkAction = () => {
    if (bulkProcessing) return;
    setBulkAction(null);
    resetTenantActionReason();
  };

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
        // DASH-ELEC-268 (Fixer-C24 2026-04-25): bridge.ts now parameterises
        // createTenant return shape, so the cast is no longer needed.
        const created = res.data;
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
        toast.error(formatApiError(res));
      }
    } catch {
      toast.error('Failed to create tenant');
    } finally {
      setCreating(false);
    }
  };

  const handleSuspend = async () => {
    if (!suspendTarget) return;
    const reason = tenantActionReason.trim();
    const error = tenantActionReasonError('suspend', tenantActionReason);
    if (error) {
      setTenantActionReasonErrorText(error);
      return;
    }
    const slug = suspendTarget.slug;
    const res = await getAPI().superAdmin.suspendTenant({ slug, reason });
    if (res.success) {
      toast.success('Tenant suspended');
      closeSuspendConfirm();
      // DASH-ELEC-235: evict cached detail so the next expand-row re-fetches
      // updated counts rather than showing stale pre-suspend data.
      setDetailCache((c) => { const n = { ...c }; delete n[slug]; return n; });
      refresh();
    } else toast.error(formatApiError(res));
  };

  const handleActivate = async () => {
    if (!activateTarget) return;
    const reason = tenantActionReason.trim();
    const error = tenantActionReasonError('activate', tenantActionReason);
    if (error) {
      setTenantActionReasonErrorText(error);
      return;
    }
    const slug = activateTarget.slug;
    const res = await getAPI().superAdmin.activateTenant({ slug, reason: reason || undefined });
    if (res.success) {
      toast.success('Tenant activated');
      closeActivateConfirm();
      // DASH-ELEC-235: same eviction for activate.
      setDetailCache((c) => { const n = { ...c }; delete n[slug]; return n; });
      refresh();
    } else toast.error(formatApiError(res));
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
      // DASH-ELEC-235: repair may recreate DB tables/rows — evict cached detail.
      setDetailCache((c) => { const n = { ...c }; delete n[slug]; return n; });
      refresh();
    } else {
      toast.error(formatApiError(res));
    }
  };

  const openPlanChange = (tenant: Tenant, nextPlan: TenantPlan) => {
    if (tenant.plan === nextPlan || updatingPlanSlug) return;
    setPlanChangeTarget({ tenant, nextPlan });
  };

  const handlePlanChange = async () => {
    if (!planChangeTarget || updatingPlanSlug) return;
    const { tenant, nextPlan } = planChangeTarget;
    setUpdatingPlanSlug(tenant.slug);
    try {
      const res = await getAPI().superAdmin.updateTenant({ slug: tenant.slug, plan: nextPlan });
      if (handleApiResponse(res)) return;
      if (res.success) {
        const updated = res.data;
        toast.success(`${tenant.slug} moved to ${PLAN_DEFINITIONS[nextPlan].displayName}`);
        setPlanChangeTarget(null);
        setTenants((list) => list.map((row) => (
          row.slug === tenant.slug ? { ...row, ...(updated ?? {}), plan: nextPlan } : row
        )));
        setDetailCache((c) => { const n = { ...c }; delete n[tenant.slug]; return n; });
        await refresh();
      } else {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to update tenant plan');
    } finally {
      setUpdatingPlanSlug(null);
    }
  };

  const startRename = (tenant: Tenant) => {
    if (savingRenameSlug !== null) return;
    setRenamingSlug(tenant.slug);
    setRenameValue(tenant.name);
    setRenameError(null);
  };

  const cancelRename = () => {
    if (savingRenameSlug !== null) return;
    setRenamingSlug(null);
    setRenameValue('');
    setRenameError(null);
  };

  const handleRename = async (tenant: Tenant) => {
    if (savingRenameSlug !== null) return;
    const error = tenantNameError(renameValue);
    if (error) {
      setRenameError(error);
      return;
    }
    const nextName = renameValue.trim();
    if (nextName === tenant.name) {
      cancelRename();
      return;
    }

    setSavingRenameSlug(tenant.slug);
    try {
      const res = await getAPI().superAdmin.updateTenant({ slug: tenant.slug, name: nextName });
      if (handleApiResponse(res)) return;
      if (res.success) {
        const updated = res.data;
        setTenants((list) => list.map((row) => (
          row.slug === tenant.slug ? { ...row, ...(updated ?? {}), name: updated?.name ?? nextName } : row
        )));
        setRenamingSlug(null);
        setRenameValue('');
        setRenameError(null);
        toast.success('Tenant shop name updated');
        await refresh();
      } else {
        const message = formatApiError(res);
        setRenameError(message);
        toast.error(message);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to update tenant shop name';
      setRenameError(message);
      toast.error(message);
    } finally {
      setSavingRenameSlug(null);
    }
  };

  const handleDelete = async () => {
    if (!deleteTarget) return;
    const slug = deleteTarget.slug;
    const res = await getAPI().superAdmin.deleteTenant(slug);
    if (res.success) {
      toast.success('Tenant deleted');
      setDeleteTarget(null);
      // DASH-ELEC-260: clear detail panel + cache so a stale entry isn't shown if
      // a new tenant with the same slug is created later in this session.
      setExpandedSlug((s) => (s === slug ? null : s));
      setDetailCache((c) => { const n = { ...c }; delete n[slug]; return n; });
      refresh();
    } else {
      toast.error(formatApiError(res));
    }
  };

  const getBulkTargets = (action: BulkAction) => {
    if (action === 'suspend') return selectedTenants.filter((t) => t.status === 'active');
    if (action === 'activate') return selectedTenants.filter((t) => t.status === 'suspended');
    return selectedTenants;
  };

  const getBulkLabel = (action: BulkAction) => {
    if (action === 'suspend') return 'Suspend Tenants';
    if (action === 'activate') return 'Activate Tenants';
    return 'Delete Tenants';
  };

  const getBulkMessage = (action: BulkAction) => {
    const targets = getBulkTargets(action);
    const skipped = selectedTenants.length - targets.length;
    const skippedText = skipped > 0 ? `\n\n${skipped} selected tenant${skipped === 1 ? '' : 's'} will be skipped because their current status does not apply.` : '';
    const countText = `${targets.length} tenant${targets.length === 1 ? '' : 's'}`;
    if (action === 'delete') {
      return `Permanently delete ${countText}? This will delete all selected tenant data and cannot be undone.`;
    }
    if (action === 'suspend') {
      return `Suspend ${countText}? Users for these tenants will be blocked from signing in until re-activated.${skippedText}`;
    }
    return `Activate ${countText}? Users for these tenants will be able to sign in immediately.${skippedText}`;
  };

  const handleBulkConfirm = async () => {
    if (!bulkAction || bulkProcessing) return;
    const action = bulkAction;
    const targets = getBulkTargets(action);
    if (targets.length === 0) {
      toast.error('No selected tenants match this action');
      setBulkAction(null);
      resetTenantActionReason();
      return;
    }
    if (action === 'suspend' || action === 'activate') {
      const error = tenantActionReasonError(action, tenantActionReason);
      if (error) {
        setTenantActionReasonErrorText(error);
        return;
      }
    }

    setBulkProcessing(true);
    const succeeded: string[] = [];
    const failed: string[] = [];
    const reason = tenantActionReason.trim();
    try {
      for (const tenant of targets) {
        const res = action === 'suspend'
          ? await getAPI().superAdmin.suspendTenant({ slug: tenant.slug, reason })
          : action === 'activate'
            ? await getAPI().superAdmin.activateTenant({ slug: tenant.slug, reason: reason || undefined })
            : await getAPI().superAdmin.deleteTenant(tenant.slug);
        if (res.success) {
          succeeded.push(tenant.slug);
        } else {
          failed.push(`${tenant.slug}: ${formatApiError(res)}`);
        }
      }

      if (succeeded.length > 0) {
        const verb = action === 'suspend' ? 'suspended' : action === 'activate' ? 'activated' : 'deleted';
        toast.success(`${succeeded.length} tenant${succeeded.length === 1 ? '' : 's'} ${verb}`);
        setDetailCache((c) => {
          const next = { ...c };
          succeeded.forEach((slug) => delete next[slug]);
          return next;
        });
        if (action === 'delete') {
          setExpandedSlug((slug) => (slug && succeeded.includes(slug) ? null : slug));
        }
        await refresh();
        clearSelected();
      }

      if (failed.length > 0) {
        toast.error(`Bulk ${action} failed for ${failed.length} tenant${failed.length === 1 ? '' : 's'}`);
        console.error(`Bulk ${action} failures`, failed);
      }
    } finally {
      setBulkProcessing(false);
      setBulkAction(null);
      resetTenantActionReason();
    }
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
          {/* DASH-ELEC-234: when the search/status filter is active show the
              filtered count vs total ("3 of 27") so the heading reflects what
              the table actually renders. Falls back to plain count otherwise. */}
          Tenants ({filteredTenants.length === tenants.length
            ? tenants.length
            : `${filteredTenants.length} of ${tenants.length}`})
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
            <div className={STAT_CARD_CLASS}>
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Tenants</div>
              <div className="text-lg lg:text-2xl font-bold text-surface-100">{tenants.length}</div>
            </div>
            <div className={STAT_CARD_CLASS}>
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Active</div>
              <div className="text-lg lg:text-2xl font-bold text-emerald-300">
                {active}<span className="text-xs text-surface-500"> / {tenants.length}</span>
              </div>
            </div>
            <div className={STAT_CARD_CLASS}>
              <div className="text-[10px] lg:text-[11px] text-surface-500 uppercase tracking-wider mb-1 lg:mb-2">Suspended</div>
              <div className={cn('text-lg lg:text-2xl font-bold', suspended > 0 ? 'text-amber-300' : 'text-surface-300')}>{suspended}</div>
            </div>
            <div className={STAT_CARD_CLASS}>
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
              <p className="mt-1 text-green-200">Send this setup link to the tenant admin so they can set their password.</p>
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

      {selectedSlugs.size > 0 && (
        <div className="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-accent-700/50 bg-accent-950/30 px-3 py-2">
          <div className="text-xs text-accent-100">
            <span className="font-semibold">{selectedSlugs.size}</span> selected
            {selectedVisibleCount !== selectedSlugs.size && (
              <span className="text-accent-300"> ({selectedVisibleCount} visible)</span>
            )}
          </div>
          <div className="flex flex-wrap items-center gap-2">
            <button
              type="button"
              onClick={() => openBulkAction('suspend')}
              disabled={activeSelectedCount === 0}
              className="inline-flex items-center gap-1.5 rounded-lg border border-amber-700/60 px-2.5 py-1.5 text-xs font-medium text-amber-200 hover:bg-amber-950/40 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <Pause className="h-3.5 w-3.5" />
              Suspend {activeSelectedCount > 0 ? activeSelectedCount : ''}
            </button>
            <button
              type="button"
              onClick={() => openBulkAction('activate')}
              disabled={suspendedSelectedCount === 0}
              className="inline-flex items-center gap-1.5 rounded-lg border border-green-700/60 px-2.5 py-1.5 text-xs font-medium text-green-200 hover:bg-green-950/40 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <Play className="h-3.5 w-3.5" />
              Activate {suspendedSelectedCount > 0 ? suspendedSelectedCount : ''}
            </button>
            <button
              type="button"
              onClick={() => openBulkAction('delete')}
              className="inline-flex items-center gap-1.5 rounded-lg border border-red-700/60 px-2.5 py-1.5 text-xs font-medium text-red-200 hover:bg-red-950/40"
            >
              <Trash2 className="h-3.5 w-3.5" />
              Delete {selectedSlugs.size}
            </button>
            <button
              type="button"
              onClick={clearSelected}
              className="rounded-lg border border-surface-700 px-2.5 py-1.5 text-xs font-medium text-surface-300 hover:bg-surface-800"
            >
              Clear
            </button>
          </div>
        </div>
      )}

      {/* Tenant list — empty-state CTA when the install has never created
          a tenant (fresh super-admin + multi-tenant mode). Falls back to a
          bare message when the search box filtered every tenant away. */}
      {filteredTenants.length === 0 ? (
        tenants.length === 0 ? (
          <div className="rounded-lg border border-dashed border-surface-700 bg-surface-900/50 p-8 text-center">
            <Users className="w-8 h-8 text-surface-600 mx-auto mb-2" />
            <p className="text-sm text-surface-200">No tenants yet</p>
            <p className="text-xs text-surface-500 mt-1 max-w-sm mx-auto leading-relaxed">
              Every tenant that uses this server gets its own DB. Create one
              now to get a slug, an admin setup link, and (if Cloudflare is
              configured) a DNS record.
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
              {/* DASH-ELEC-239: scope="col" so AT pairs each cell with its
                  header when the row is announced. */}
              <tr className="border-b border-surface-800">
                <th scope="col" className="w-10 py-2 px-3 text-left">
                  <input
                    type="checkbox"
                    checked={allVisibleSelected}
                    ref={(el) => {
                      if (el) el.indeterminate = someVisibleSelected;
                    }}
                    onChange={toggleSelectVisible}
                    aria-label={allVisibleSelected ? 'Deselect all visible tenants' : 'Select all visible tenants'}
                    className="h-4 w-4 rounded border-surface-700 bg-surface-950 text-accent-600 focus:ring-accent-500"
                  />
                </th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Slug</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Name</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Status</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Plan</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">DB size</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Activity</th>
                <th scope="col" className="text-left py-2 px-3 text-xs text-surface-500 font-medium">Created</th>
                <th scope="col" className="text-right py-2 px-3 text-xs text-surface-500 font-medium">Actions</th>
              </tr>
            </thead>
            <tbody>
              {filteredTenants.map((t) => {
                const isOpen = expandedSlug === t.slug;
                const detail = detailCache[t.slug];
                const isSelected = selectedSlugs.has(t.slug);
                return (
                <Fragment key={t.id}>
                <tr
                  className={cn(
                    'border-b border-surface-800/50 hover:bg-surface-800/30 cursor-pointer',
                    isSelected && 'bg-accent-950/20'
                  )}
                  onClick={() => toggleExpand(t.slug)}
                >
                  <td className="py-2.5 px-3" onClick={(e) => e.stopPropagation()}>
                    <input
                      type="checkbox"
                      checked={isSelected}
                      onChange={() => toggleSelectSlug(t.slug)}
                      aria-label={`Select ${t.name}`}
                      className="h-4 w-4 rounded border-surface-700 bg-surface-950 text-accent-600 focus:ring-accent-500"
                    />
                  </td>
                  <td className="py-2.5 px-3 font-mono text-accent-400 text-xs">
                    <span className="inline-flex items-center gap-1">
                      {isOpen ? <ChevronDown className="w-3 h-3" /> : <ChevronRight className="w-3 h-3" />}
                      <CopyText value={t.slug} toastLabel={`Copied ${t.slug}`}>{t.slug}</CopyText>
                    </span>
                  </td>
	                  <td className="py-2.5 px-3 text-surface-200" onClick={(e) => e.stopPropagation()}>
	                    {renamingSlug === t.slug ? (
	                      <form
	                        className="min-w-[220px] space-y-1"
	                        onSubmit={(e) => {
	                          e.preventDefault();
	                          void handleRename(t);
	                        }}
	                      >
	                        <div className="flex items-center gap-1.5">
	                          <input
	                            type="text"
	                            value={renameValue}
	                            maxLength={TENANT_NAME_MAX + 1}
	                            autoFocus
	                            onChange={(e) => {
	                              setRenameValue(e.target.value);
	                              setRenameError(null);
	                            }}
	                            onKeyDown={(e) => {
	                              if (e.key === 'Escape') {
	                                e.preventDefault();
	                                cancelRename();
	                              }
	                            }}
	                            aria-label={`New shop name for ${t.slug}`}
	                            aria-invalid={renameError ? 'true' : 'false'}
	                            aria-describedby={renameError ? `tenant-rename-error-${t.slug}` : undefined}
	                            className={cn(
	                              'h-8 w-56 rounded border bg-surface-950 px-2 text-xs text-surface-100 placeholder:text-surface-600 focus:outline-none',
	                              renameError ? 'border-red-600 focus:border-red-500' : 'border-surface-700 focus:border-accent-500'
	                            )}
	                          />
	                          <button
	                            type="submit"
	                            disabled={savingRenameSlug === t.slug || tenantNameError(renameValue) !== null || renameValue.trim() === t.name}
	                            className="p-1.5 rounded text-emerald-400 hover:text-emerald-200 hover:bg-surface-700 disabled:cursor-not-allowed disabled:opacity-40"
	                            title="Save shop name"
	                            aria-label={`Save shop name for ${t.slug}`}
	                          >
	                            <Check className="w-3.5 h-3.5" aria-hidden="true" />
	                          </button>
	                          <button
	                            type="button"
	                            disabled={savingRenameSlug === t.slug}
	                            onClick={cancelRename}
	                            className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-700 disabled:cursor-not-allowed disabled:opacity-40"
	                            title="Cancel rename"
	                            aria-label={`Cancel rename for ${t.slug}`}
	                          >
	                            <X className="w-3.5 h-3.5" aria-hidden="true" />
	                          </button>
	                        </div>
	                        {renameError ? (
	                          <p id={`tenant-rename-error-${t.slug}`} className="text-[11px] text-red-300">{renameError}</p>
	                        ) : null}
	                      </form>
	                    ) : (
	                      <div className="flex min-w-0 items-center gap-1.5">
	                        <span className="truncate" title={t.name}>{t.name}</span>
	                        <button
	                          type="button"
	                          onClick={() => startRename(t)}
	                          disabled={savingRenameSlug !== null || updatingPlanSlug === t.slug}
	                          className="shrink-0 p-1 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-700 disabled:cursor-not-allowed disabled:opacity-40"
	                          title="Rename shop"
	                          aria-label={`Rename shop for ${t.name}`}
	                        >
	                          <Pencil className="w-3 h-3" aria-hidden="true" />
	                        </button>
	                      </div>
	                    )}
	                  </td>
                  <td className="py-2.5 px-3">
                    {/* DASH-ELEC-239: aria-label spells the badge value out so
                        AT users hear "active" / "suspended" instead of just
                        the visual chip color cue. */}
                    <span
                      role="status"
                      aria-label={`Status: ${t.status}`}
                      className={cn(
                        'px-2 py-0.5 rounded-full text-xs font-medium',
                        t.status === 'active' ? 'bg-green-900/40 text-green-300' : 'bg-red-900/40 text-red-300'
                      )}
                    >
                      {t.status}
                    </span>
                  </td>
                  <td className="py-2.5 px-3 text-xs" onClick={(e) => e.stopPropagation()}>
                    <select
                      value={isTenantPlan(t.plan) ? t.plan : ''}
                      disabled={updatingPlanSlug === t.slug}
                      onChange={(e) => openPlanChange(t, e.target.value as TenantPlan)}
                      className="w-28 rounded border border-surface-700 bg-surface-950 px-2 py-1 text-xs text-surface-200 focus:border-accent-500 focus:outline-none disabled:cursor-wait disabled:opacity-60"
                      aria-label={`Change plan for ${t.name}`}
                      title={`Current plan: ${planLabel(t.plan)}`}
                    >
                      {!isTenantPlan(t.plan) && <option value="" disabled>Unknown: {t.plan}</option>}
                      {PLAN_OPTIONS.map((plan) => (
                        <option key={plan.name} value={plan.name}>{plan.displayName}</option>
                      ))}
                    </select>
                  </td>
                  <td className="py-2.5 px-3 text-surface-400 text-xs whitespace-nowrap">
                    {t.db_size_bytes
                      ? `${(t.db_size_bytes / 1024 / 1024).toFixed(1)} MB`
                      : '—'}
                  </td>
                  <td className="py-2.5 px-3 text-xs whitespace-nowrap">
                    <div className="space-y-0.5">
                      <div className="text-surface-400" title={t.last_active ? `Last active: ${formatDateTime(t.last_active)}` : 'Last active unknown'}>
                        <span className="text-surface-600">Last</span> {formatTenantTimestamp(t.last_active)}
                      </div>
                      {t.status === 'suspended' && (
                        <div className="text-amber-300" title={t.suspended_at ? `Suspended: ${formatDateTime(t.suspended_at)}` : 'Suspension timestamp unavailable'}>
                          <span className="text-surface-600">Susp.</span> {formatTenantTimestamp(t.suspended_at)}
                        </div>
                      )}
                    </div>
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
                              toast.error(formatApiError(res));
                            }
                          } catch (err) {
                            toast.error(err instanceof Error ? err.message : 'Failed to open tenant URL');
                          }
                        }}
                        className="p-1.5 rounded text-surface-500 hover:text-surface-200 hover:bg-surface-700"
                        title="Open"
                        aria-label={`Open ${t.slug}`}
                      >
                        <ExternalLink className="w-3.5 h-3.5" aria-hidden="true" />
                      </button>
                      {/* DASH-ELEC-128: aria-label per tenant so SR gets unique accessible names */}
                      {t.status === 'active' ? (
                        <button
                          onClick={() => openSuspendConfirm(t)}
                          className="p-1.5 rounded text-amber-500 hover:text-amber-300 hover:bg-surface-700"
                          title="Suspend"
                          aria-label={`Suspend ${t.name}`}
                        >
                          <Pause className="w-3.5 h-3.5" aria-hidden="true" />
                        </button>
                      ) : (
                        <button
                          onClick={() => openActivateConfirm(t)}
                          className="p-1.5 rounded text-green-500 hover:text-green-300 hover:bg-surface-700"
                          title="Activate"
                          aria-label={`Activate ${t.name}`}
                        >
                          <Play className="w-3.5 h-3.5" aria-hidden="true" />
                        </button>
                      )}
                      {/* DASH-ELEC-134: server `repairTenant` (management-api.ts)
                          carries no status restriction — an active tenant with a
                          missing DB table needs Repair too. Drop the
                          `status !== 'active'` gate so the button matches the
                          server's actual capability. */}
                      <button
                        onClick={() => setRepairTarget(t)}
                        className="p-1.5 rounded text-blue-500 hover:text-blue-300 hover:bg-surface-700"
                        title="Repair (additive — creates missing pieces, never deletes)"
                        aria-label={`Repair ${t.name}`}
                      >
                        <Wrench className="w-3.5 h-3.5" aria-hidden="true" />
                      </button>
                      <button
                        onClick={() => setDeleteTarget(t)}
                        className="p-1.5 rounded text-red-500 hover:text-red-300 hover:bg-surface-700"
                        title="Delete"
                        aria-label={`Delete ${t.name}`}
                      >
                        <Trash2 className="w-3.5 h-3.5" aria-hidden="true" />
                      </button>
                    </div>
                  </td>
                </tr>
                {isOpen && (
                  <tr className="border-b border-surface-800 bg-surface-900/30">
                    <td colSpan={9} className="px-3 py-3">
                      {detail === 'loading' || detail === undefined ? (
                        <p className="text-xs text-surface-500">Loading tenant metrics…</p>
                      ) : detail === 'error' ? (
                        // DASH-ELEC-278: surface a Retry so a transient
                        // failure isn't permanently sticky in detailCache.
                        <div className="flex items-center gap-2">
                          <p className="text-xs text-red-400">Failed to load tenant metrics.</p>
                          <button
                            type="button"
                            onClick={() => loadDetail(t.slug)}
                            className="px-2 py-0.5 text-[11px] font-semibold text-red-300 hover:text-red-100 border border-red-900/60 hover:border-red-700 rounded transition-colors"
                            aria-label={`Retry loading metrics for ${t.name}`}
                          >
                            Retry
                          </button>
                        </div>
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
                </Fragment>
                );
              })}
            </tbody>
          </table>
        </div>
      )}

      {/* Create Modal */}
      {/*
        DASH-ELEC-120 + DASH-ELEC-166 (Fixer-B27 2026-04-25):
         - Wrapped the body in a `<form onSubmit>` so Enter from any input
           submits via handleCreate (was: Enter did nothing, every field had
           to be tabbed to and the Create button clicked manually).
         - Added `role="dialog"`, `aria-modal="true"`, `aria-labelledby` so
           assistive tech announces this as a modal dialog (parity with
           ConfirmDialog / KeyboardShortcutsHelp).
         - Added Escape-to-close + a Tab focus trap mirroring ConfirmDialog
           — without these, Tab walked off the modal into the underlying
           tenants table and Escape did nothing.
        Cancel still uses `closeCreate` so the body-state reset happens in
        one place regardless of how the modal is dismissed (Esc / Cancel /
        successful submit all reset the same way).
      */}
      {showCreate && (
        <CreateTenantModal
          newSlug={newSlug}
          newName={newName}
          newEmail={newEmail}
          newPlan={newPlan}
          creating={creating}
          setNewSlug={setNewSlug}
          setNewName={setNewName}
          setNewEmail={setNewEmail}
          setNewPlan={setNewPlan}
          onSubmit={handleCreate}
          onCancel={() => { setShowCreate(false); setNewSlug(''); setNewName(''); setNewEmail(''); setNewPlan('free'); }}
        />
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

      {/* Suspend confirm */}
      <TenantStatusReasonDialog
        open={suspendTarget !== null}
        title="Suspend Tenant"
        message={`Suspending "${suspendTarget?.name}" will immediately block all users from signing in. You can re-activate at any time.`}
        danger
        reason={tenantActionReason}
        reasonError={tenantActionReasonErrorText}
        reasonRequired
        reasonLabel="Suspension reason"
        confirmLabel="Suspend Tenant"
        onConfirm={handleSuspend}
        onCancel={closeSuspendConfirm}
        onReasonChange={(value) => {
          setTenantActionReason(value);
          setTenantActionReasonErrorText(null);
        }}
      />

      {/* Activate confirm */}
      <TenantStatusReasonDialog
        open={activateTarget !== null}
        title="Activate Tenant"
        message={`Re-activate "${activateTarget?.name}"? Users will be able to sign in again immediately.`}
        reason={tenantActionReason}
        reasonError={tenantActionReasonErrorText}
        reasonLabel="Activation reason"
        confirmLabel="Activate Tenant"
        onConfirm={handleActivate}
        onCancel={closeActivateConfirm}
        onReasonChange={(value) => {
          setTenantActionReason(value);
          setTenantActionReasonErrorText(null);
        }}
      />

      {/* DASH-ELEC-133: Repair confirm — additive (creates missing DB tables
          and re-issues a setup token if the tenant has zero users). Spell out
          the side-effects so an operator doesn't trigger a token reissue
          accidentally. */}
      <ConfirmDialog
        open={repairTarget !== null}
        title="Repair Tenant"
        message={
          `Repair "${repairTarget?.name}" (${repairTarget?.slug})?\n\n` +
          `This is additive — nothing is deleted. It re-creates any missing ` +
          `database tables, and if the tenant has zero users it re-generates ` +
          `the one-time setup URL (the previous URL becomes invalid).`
        }
        confirmLabel="Repair Tenant"
        onConfirm={async () => {
          if (!repairTarget) return;
          const slug = repairTarget.slug;
          setRepairTarget(null);
          await handleRepair(slug);
        }}
        onCancel={() => setRepairTarget(null)}
      />

      <ConfirmDialog
        open={planChangeTarget !== null}
        title="Change Tenant Plan"
        message={
          planChangeTarget
            ? `Change "${planChangeTarget.tenant.name}" (${planChangeTarget.tenant.slug}) from ${planLabel(planChangeTarget.tenant.plan)} to ${PLAN_DEFINITIONS[planChangeTarget.nextPlan].displayName}? Limits will reset to ${describePlanLimits(planChangeTarget.nextPlan)}. This is audited and may update platform Stripe billing when the tenant has a Stripe customer.`
            : ''
        }
        confirmLabel="Change Plan"
        disabled={updatingPlanSlug !== null}
        onConfirm={handlePlanChange}
        onCancel={() => {
          if (updatingPlanSlug === null) setPlanChangeTarget(null);
        }}
      />

      <ConfirmDialog
        open={bulkAction === 'delete'}
        title={bulkAction ? getBulkLabel(bulkAction) : 'Bulk Action'}
        message={bulkAction ? getBulkMessage(bulkAction) : ''}
        danger
        requireTyping={`delete ${selectedTenants.length}`}
        confirmLabel={bulkAction ? getBulkLabel(bulkAction) : 'Confirm'}
        disabled={bulkProcessing || (bulkAction !== null && getBulkTargets(bulkAction).length === 0)}
        onConfirm={handleBulkConfirm}
        onCancel={closeBulkAction}
      />

      <TenantStatusReasonDialog
        open={bulkAction === 'suspend' || bulkAction === 'activate'}
        title={bulkAction ? getBulkLabel(bulkAction) : 'Bulk Action'}
        message={bulkAction ? getBulkMessage(bulkAction) : ''}
        danger={bulkAction === 'suspend'}
        reason={tenantActionReason}
        reasonError={tenantActionReasonErrorText}
        reasonRequired={bulkAction === 'suspend'}
        reasonLabel={bulkAction === 'activate' ? 'Activation reason' : 'Suspension reason'}
        confirmLabel={bulkAction ? getBulkLabel(bulkAction) : 'Confirm'}
        disabled={bulkProcessing || (bulkAction !== null && getBulkTargets(bulkAction).length === 0)}
        onConfirm={handleBulkConfirm}
        onCancel={closeBulkAction}
        onReasonChange={(value) => {
          setTenantActionReason(value);
          setTenantActionReasonErrorText(null);
        }}
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

interface TenantStatusReasonDialogProps {
  open: boolean;
  title: string;
  message: string;
  reason: string;
  reasonLabel: string;
  reasonError?: string | null;
  reasonRequired?: boolean;
  confirmLabel: string;
  danger?: boolean;
  disabled?: boolean;
  onReasonChange: (value: string) => void;
  onConfirm: () => void;
  onCancel: () => void;
}

function TenantStatusReasonDialog({
  open,
  title,
  message,
  reason,
  reasonLabel,
  reasonError,
  reasonRequired = false,
  confirmLabel,
  danger = false,
  disabled = false,
  onReasonChange,
  onConfirm,
  onCancel,
}: TenantStatusReasonDialogProps) {
  const textareaRef = useRef<HTMLTextAreaElement>(null);
  const confirmDisabled = disabled || (reasonRequired && reason.trim().length === 0) || reason.length > TENANT_ACTION_REASON_MAX;

  useEffect(() => {
    if (!open) return;
    textareaRef.current?.focus();
  }, [open]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm animate-fade-in">
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="tenant-status-dialog-title"
        aria-describedby="tenant-status-dialog-message tenant-status-reason-help"
        className="w-[460px] max-w-[calc(100vw-2rem)] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6 outline-none"
      >
        <div className="mb-4">
          <h3 id="tenant-status-dialog-title" className="text-sm font-semibold text-surface-100">{title}</h3>
          <p id="tenant-status-dialog-message" className="mt-3 whitespace-pre-line text-sm text-surface-400">{message}</p>
        </div>

        <div className="mb-5">
          <div className="mb-2 flex items-center justify-between gap-3">
            <label htmlFor="tenant-status-reason" className="text-xs font-medium text-surface-300">
              {reasonLabel}
              {reasonRequired ? <span className="text-red-300"> required</span> : <span className="text-surface-500"> optional</span>}
            </label>
            <span className={cn('text-[11px]', reason.length > TENANT_ACTION_REASON_MAX ? 'text-red-300' : 'text-surface-500')}>
              {reason.length}/{TENANT_ACTION_REASON_MAX}
            </span>
          </div>
          <textarea
            ref={textareaRef}
            id="tenant-status-reason"
            value={reason}
            maxLength={TENANT_ACTION_REASON_MAX + 1}
            rows={4}
            onChange={(event) => onReasonChange(event.target.value)}
            placeholder={reasonRequired ? 'Example: Non-payment after support escalation' : 'Example: Payment verified and account cleared'}
            aria-invalid={reasonError ? 'true' : 'false'}
            aria-describedby="tenant-status-reason-help"
            className={cn(
              'w-full resize-none rounded-lg border bg-surface-950 px-3 py-2 text-sm text-surface-100 placeholder:text-surface-600 focus:outline-none',
              reasonError ? 'border-red-600 focus:border-red-500' : 'border-surface-700 focus:border-accent-500'
            )}
          />
          <p id="tenant-status-reason-help" className={cn('mt-2 text-xs', reasonError ? 'text-red-300' : 'text-surface-500')}>
            {reasonError ?? 'Saved into the super-admin audit log for this tenant action.'}
          </p>
        </div>

        <div className="flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={disabled}
            className="px-4 py-2 text-sm text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors disabled:cursor-not-allowed disabled:opacity-50"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={confirmDisabled}
            className={cn(
              'px-4 py-2 text-sm font-semibold rounded-lg transition-colors disabled:cursor-not-allowed disabled:opacity-50',
              danger
                ? 'bg-red-600 text-white hover:bg-red-700 disabled:bg-red-800 disabled:text-red-200'
                : 'bg-accent-600 text-white hover:bg-accent-700'
            )}
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}

/**
 * DASH-ELEC-120 + DASH-ELEC-166 (Fixer-B27 2026-04-25): the Create-Tenant
 * modal extracted into its own component so Escape / focus-trap effects can
 * be attached unconditionally — the parent renders this only when
 * `showCreate` is true, so mount === open and a single useEffect owns the
 * keydown listener for the dialog's lifetime.
 */
interface CreateTenantModalProps {
  newSlug: string;
  newName: string;
  newEmail: string;
  newPlan: TenantPlan;
  creating: boolean;
  setNewSlug: (v: string) => void;
  setNewName: (v: string) => void;
  setNewEmail: (v: string) => void;
  setNewPlan: (v: TenantPlan) => void;
  onSubmit: () => void;
  onCancel: () => void;
}

function CreateTenantModal({
  newSlug, newName, newEmail, newPlan, creating,
  setNewSlug, setNewName, setNewEmail, setNewPlan,
  onSubmit, onCancel,
}: CreateTenantModalProps) {
  const containerRef = useRef<HTMLDivElement>(null);

  // Focus the first focusable element on open + Escape-to-cancel listener.
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const first = el.querySelector<HTMLElement>(
      'input, select, textarea, button, [href], [tabindex]:not([tabindex="-1"])'
    );
    first?.focus();
  }, []);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      onCancel();
      return;
    }
    if (e.key === 'Tab') {
      const el = containerRef.current;
      if (!el) return;
      const focusable = Array.from(
        el.querySelectorAll<HTMLElement>(
          'input, select, textarea, button, [href], [tabindex]:not([tabindex="-1"])'
        )
      ).filter((n) => !n.hasAttribute('disabled'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 backdrop-blur-sm">
      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="create-tenant-title"
        tabIndex={-1}
        onKeyDown={handleKeyDown}
        className="w-[min(420px,calc(100vw-2rem))] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl p-6 outline-none"
      >
        <h3 id="create-tenant-title" className="text-sm font-semibold text-surface-100 mb-4">Create New Tenant</h3>
        {/* DASH-ELEC-166: real <form> wrapper so Enter from any input submits. */}
        <form
          onSubmit={(e) => {
            e.preventDefault();
            if (creating || !newSlug.trim() || !newName.trim() || !newEmail.trim()) return;
            onSubmit();
          }}
        >
          <div className="space-y-3 mb-5">
            {/* DASH-ELEC-236: cap slug input at 30 chars to match handleCreate's
                client-side validation (the IPC schema accepts 64 but we reject
                anything over 30 with a toast — let the input prevent it). */}
            {/* DASH-ELEC-167: aria-label per input so SR users hear field names instead of placeholders only.
                DASH-ELEC-135: typing the shop name auto-populates slug while it's still untouched. */}
            <input type="text" value={newSlug} onChange={(e) => setNewSlug(e.target.value)} placeholder="Slug (e.g. my-shop)"
              maxLength={30}
              aria-label="Tenant slug (URL identifier, lowercase letters, digits, hyphens)"
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
            <input type="text" value={newName} onChange={(e) => {
              const next = e.target.value;
              setNewName(next);
              if (!newSlug.trim()) {
                setNewSlug(next.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 30));
              }
            }} placeholder="Shop name"
              aria-label="Shop name (display name shown to staff and customers)"
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
            <input type="email" value={newEmail} onChange={(e) => setNewEmail(e.target.value)} placeholder="Admin email (required)"
              aria-label="Admin email address (recipient of initial credentials)"
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none" />
            <select value={newPlan} onChange={(e) => setNewPlan(e.target.value as TenantPlan)}
              aria-label="Subscription plan"
              className="w-full px-3 py-2 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 focus:border-accent-500 focus:outline-none">
              {PLAN_OPTIONS.map((plan) => (
                <option key={plan.name} value={plan.name}>{plan.displayName}</option>
              ))}
            </select>
          </div>
          <div className="flex justify-end gap-2">
            <button type="button" onClick={onCancel} className="px-4 py-2 text-sm text-surface-300 bg-surface-800 border border-surface-700 rounded-lg hover:bg-surface-700">Cancel</button>
            <button type="submit" disabled={creating || !newSlug.trim() || !newName.trim() || !newEmail.trim()}
              className="px-4 py-2 text-sm font-semibold bg-accent-600 text-white rounded-lg hover:bg-accent-700 disabled:opacity-40">
              {creating ? 'Creating...' : 'Create'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}
