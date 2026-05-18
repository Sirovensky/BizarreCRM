import React, { useState, useEffect, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation } from '@tanstack/react-query';
import {
  Building2,
  LogIn,
  Loader2,
  AlertCircle,
  ShieldCheck,
  Search,
  LogOut,
  ChevronLeft,
  ChevronRight,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { superAdminApi, type SuperAdminTenant } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { SUPER_ADMIN_LOGOUT_EVENT, superAdminTokenStore } from '@/api/client';
import {
  readImpersonationTokenClaims,
  setImpersonationSession,
} from '@/components/ImpersonationBanner';
import { cn } from '@/utils/cn';
import { useFocusTrap } from '@/hooks/useFocusTrap';

// BUGHUNT-2026-05-17: tenant.created_at is a SQLite datetime string
// ("YYYY-MM-DD HH:MM:SS", UTC). V8 parses bare-space datetimes as LOCAL,
// so a tenant provisioned at 00:30 UTC shows as the prior day in any
// negative-offset zone (PST/CST/EST super-admins). Append 'Z' so the
// Date converts UTC -> local correctly.
function formatTenantCreatedAt(iso: string | null | undefined): string {
  if (!iso) return '—';
  const normalized = iso.includes('T') || iso.endsWith('Z') || /[+-]\d{2}:?\d{2}$/.test(iso)
    ? iso
    : `${iso.replace(' ', 'T')}Z`;
  const d = new Date(normalized);
  if (Number.isNaN(d.getTime())) return '—';
  return d.toLocaleDateString();
}

interface LoginFormProps {
  onSuccess: () => void;
}

function SuperAdminLoginForm({ onSuccess }: LoginFormProps) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [code, setCode] = useState('');
  const [challengeToken, setChallengeToken] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  async function handlePasswordSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setSubmitting(true);
    try {
      const res = await superAdminApi.loginPassword(username, password);
      const data = res.data?.data;
      if (data?.challengeToken) {
        setChallengeToken(data.challengeToken);
      } else {
        setError('Unexpected login response');
      }
    } catch (err: unknown) {
      const msg =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      setError(msg ?? 'Login failed');
    } finally {
      setSubmitting(false);
    }
  }

  async function handleTotpSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!challengeToken) return;
    setError(null);
    setSubmitting(true);
    try {
      const res = await superAdminApi.loginTotp(challengeToken, code);
      const token = res.data?.data?.token;
      if (!token) {
        setError('No token in response');
        return;
      }
      // WEB-FJ-001: token in sessionStorage so it dies with the tab.
      superAdminTokenStore.set(token);
      onSuccess();
    } catch (err: unknown) {
      const msg =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      setError(msg ?? '2FA verification failed');
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <div className="flex flex-col items-center justify-center py-20">
      <div className="w-full max-w-sm p-6 rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg">
        <div className="flex items-center gap-2 mb-5">
          <ShieldCheck className="h-5 w-5 text-primary-600" />
          <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100">
            Super-Admin Login
          </h2>
        </div>

        {!challengeToken ? (
          <form onSubmit={handlePasswordSubmit} className="flex flex-col gap-3">
            <input
              type="text"
              value={username}
              onChange={(e) => setUsername(e.target.value)}
              placeholder="Username"
              required
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
            />
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Password"
              required
              autoComplete="current-password"
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
            />
            {error && <p role="alert" aria-live="polite" className="text-xs text-red-600 dark:text-red-400">{error}</p>}
            <button
              type="submit"
              disabled={submitting}
              className="w-full rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
            >
              {submitting ? <Loader2 className="h-4 w-4 animate-spin mx-auto" /> : 'Continue →'}
            </button>
          </form>
        ) : (
          <form onSubmit={handleTotpSubmit} className="flex flex-col gap-3">
            <p className="text-sm text-surface-500 dark:text-surface-400">
              Enter the 6-digit code from your authenticator app.
            </p>
            <input
              type="text"
              inputMode="numeric"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="000000"
              maxLength={6}
              required
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm text-center tracking-widest font-mono focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
            />
            {error && <p role="alert" aria-live="polite" className="text-xs text-red-600 dark:text-red-400">{error}</p>}
            <button
              type="submit"
              disabled={submitting || code.length !== 6}
              className="w-full rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
            >
              {submitting ? <Loader2 className="h-4 w-4 animate-spin mx-auto" /> : 'Verify & sign in'}
            </button>
            <button
              type="button"
              onClick={() => { setChallengeToken(null); setCode(''); setError(null); }}
              className="text-xs text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
            >
              Back
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

interface TenantRowProps {
  tenant: SuperAdminTenant;
}

// Shared impersonation logic extracted so both TenantRow (table) and
// TenantCard (mobile) can use it without duplicating the mutation setup.
function useTenantImpersonation(tenant: SuperAdminTenant) {
  const navigate = useNavigate();
  const completeLogin = useAuthStore((s) => s.completeLogin);
  const [confirmOpen, setConfirmOpen] = useState(false);
  const [typedSlug, setTypedSlug] = useState('');
  const [reason, setReason] = useState('');

  const closeConfirm = () => {
    setConfirmOpen(false);
    setTypedSlug('');
    setReason('');
  };

  const impersonateMutation = useMutation({
    mutationFn: (overrideReason: string) =>
      superAdminApi.impersonate(tenant.slug, overrideReason),
    onSuccess: (res) => {
      const data = res.data?.data;
      if (!data?.token) {
        toast.error('No token returned from impersonation');
        return;
      }
      // WEB-UIUX-819: persist the server-returned jti so the Exit button
      // can call POST /tenants/:slug/impersonate/:jti/end and revoke the
      // active token immediately instead of waiting for TTL expiry. The
      // banner reads this back via getImpersonationSession.
      // Also validate the token's claims match the requested tenant before
      // persisting so a tampered/mismatched response cannot install a
      // session for another tenant.
      const claims = readImpersonationTokenClaims(data.token);
      if (!claims || claims.tenantSlug !== data.tenant_slug || claims.jti !== data.jti) {
        toast.error('Impersonation token did not include the expected tenant claims');
        return;
      }
      setImpersonationSession({
        tenant_slug: data.tenant_slug,
        tenant_name: tenant.name,
        started_at: new Date().toISOString(),
        jti: claims.jti,
      });
      const targetUser = data.target_user;
      const validRole = (['admin', 'manager', 'technician', 'cashier'] as const).includes(
        targetUser.role as 'admin' | 'manager' | 'technician' | 'cashier',
      )
        ? (targetUser.role as 'admin' | 'manager' | 'technician' | 'cashier')
        : ('admin' as const);
      completeLogin(data.token, '', {
        id: targetUser.id,
        username: targetUser.username,
        role: validRole,
        first_name: '',
        last_name: '',
        email: '',
        avatar_url: null,
        is_active: true,
        permissions: null,
        created_at: '',
        updated_at: '',
      });
      toast.success(`Impersonating ${data.tenant_slug}`);
      closeConfirm();
      navigate('/');
    },
    onError: (err: unknown) => {
      const msg =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(msg ?? 'Impersonation failed');
    },
  });

  return { confirmOpen, setConfirmOpen, typedSlug, setTypedSlug, reason, setReason, closeConfirm, impersonateMutation };
}

function TenantRow({ tenant }: TenantRowProps) {
  // WEB-FG-003 / FIXED-by-Fixer-U 2026-04-25 — gate impersonation behind a
  // typed-slug confirmation + required reason field so accidental clicks
  // can't silently log an operator in as a tenant admin and the server
  // audit log gets attribution ("ticket #1234, customer support").
  const { confirmOpen, setConfirmOpen, typedSlug, setTypedSlug, reason, setReason, closeConfirm, impersonateMutation } =
    useTenantImpersonation(tenant);

  const statusColors: Record<string, string> = {
    active: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    suspended: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
    deleted: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
    trial: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  };

  return (
    <tr className="border-t border-surface-100 dark:border-surface-800 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
      <td className="px-4 py-3">
        <div className="font-medium text-surface-900 dark:text-surface-100 text-sm">{tenant.name}</div>
        <div className="text-xs text-surface-400 font-mono">{tenant.slug}</div>
      </td>
      <td className="px-4 py-3 text-xs text-surface-500">{tenant.admin_email}</td>
      <td className="px-4 py-3">
        <span className={cn('px-2 py-0.5 rounded-full text-xs font-medium', statusColors[tenant.status] ?? 'bg-surface-100 text-surface-600')}>
          {tenant.status}
        </span>
      </td>
      <td className="px-4 py-3 text-xs text-surface-500">{tenant.plan}</td>
      <td className="px-4 py-3 text-xs text-surface-500">{tenant.db_size_mb} MB</td>
      <td className="px-4 py-3 text-xs text-surface-500">
        {formatTenantCreatedAt(tenant.created_at)}
      </td>
      <td className="px-4 py-3">
        <button
          onClick={() => setConfirmOpen(true)}
          disabled={impersonateMutation.isPending || tenant.status !== 'active'}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-amber-600 text-white border border-amber-700 rounded-lg hover:bg-amber-700 dark:bg-amber-700 dark:border-amber-600 dark:hover:bg-amber-600 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
          title={tenant.status !== 'active' ? `Cannot impersonate: tenant is ${tenant.status}` : 'Log in as tenant admin'}
        >
          {impersonateMutation.isPending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <LogIn className="h-3.5 w-3.5" />
          )}
          Log in as
        </button>
        {confirmOpen && (
          <ImpersonateConfirmModal
            tenantSlug={tenant.slug}
            tenantName={tenant.name}
            typedSlug={typedSlug}
            reason={reason}
            onTypedSlugChange={setTypedSlug}
            onReasonChange={setReason}
            onCancel={closeConfirm}
            onConfirm={() => impersonateMutation.mutate(reason.trim())}
            submitting={impersonateMutation.isPending}
          />
        )}
      </td>
    </tr>
  );
}

interface ImpersonateConfirmModalProps {
  tenantSlug: string;
  tenantName: string;
  typedSlug: string;
  reason: string;
  onTypedSlugChange: (v: string) => void;
  onReasonChange: (v: string) => void;
  onCancel: () => void;
  onConfirm: () => void;
  submitting: boolean;
}

// WEB-FG-003: cross-tenant access requires typed-slug + reason. Mirrors
// DangerZoneTab's three-step pattern but inline so we don't need to thread
// a global confirm dialog through super-admin auth state.
function ImpersonateConfirmModal({
  tenantSlug, tenantName, typedSlug, reason,
  onTypedSlugChange, onReasonChange, onCancel, onConfirm, submitting,
}: ImpersonateConfirmModalProps) {
  const slugMatches = typedSlug.trim() === tenantSlug;
  const reasonValid = reason.trim().length >= 8;
  const canConfirm = slugMatches && reasonValid && !submitting;

  // WEB-UIUX-412: focus trap for WCAG 2.1 SC 2.1.2 compliance.
  const dialogRef = useFocusTrap(true);

  // WEB-FX-003: Esc dismisses unless we're mid-submit (avoid losing the
  // typed slug/reason during the network round trip).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && !submitting) onCancel();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onCancel, submitting]);

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm"
      role="presentation"
      onClick={() => {
        if (!submitting) onCancel();
      }}
    >
      <div
        ref={dialogRef as React.RefObject<HTMLDivElement>}
        role="dialog"
        aria-modal="true"
        aria-labelledby="impersonate-confirm-title"
        className="w-full max-w-md rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-red-100 dark:bg-red-950/30">
            <ShieldCheck className="h-5 w-5 text-red-600 dark:text-red-400" />
          </div>
          <div>
            <h3
              id="impersonate-confirm-title"
              className="text-base font-semibold text-surface-900 dark:text-surface-100"
            >
              Impersonate {tenantName}?
            </h3>
            <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
              You will be logged in as the tenant admin. This is recorded to
              the audit log with the reason below.
            </p>
          </div>
        </div>

        <div className="mt-4 space-y-3">
          <div>
            <label
              htmlFor="impersonate-confirm-slug"
              className="block text-xs font-medium text-surface-700 dark:text-surface-300 mb-1"
            >
              Type the tenant slug{' '}
              <code className="font-mono text-surface-900 dark:text-surface-100">
                {tenantSlug}
              </code>{' '}
              to confirm
            </label>
            <input
              id="impersonate-confirm-slug"
              type="text"
              value={typedSlug}
              onChange={(e) => onTypedSlugChange(e.target.value)}
              placeholder={tenantSlug}
              autoComplete="off"
              spellCheck={false}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm font-mono focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
            />
          </div>
          <div>
            <label
              htmlFor="impersonate-confirm-reason"
              className="block text-xs font-medium text-surface-700 dark:text-surface-300 mb-1"
            >
              Reason (min 8 chars — e.g. ticket #1234, customer support)
            </label>
            <input
              id="impersonate-confirm-reason"
              type="text"
              value={reason}
              onChange={(e) => onReasonChange(e.target.value)}
              placeholder="ticket #1234 — investigating refund issue"
              maxLength={200}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500"
            />
            {!reasonValid && reason.length > 0 && (
              <p role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">
                Reason must be at least 8 characters.
              </p>
            )}
          </div>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button
            type="button"
            onClick={onCancel}
            disabled={submitting}
            className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          <button
            type="button"
            onClick={onConfirm}
            disabled={!canConfirm}
            className={`rounded-lg px-4 py-2 text-sm font-medium text-white transition-colors ${
              canConfirm
                ? 'bg-red-600 hover:bg-red-700'
                : 'bg-surface-300 dark:bg-surface-600 cursor-not-allowed'
            }`}
          >
            {submitting ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              'Impersonate'
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

// WEB-UIUX-181: mobile card for the tenants list — rendered on small screens
// instead of the 7-column table which creates a horizontal-scroll trap.
function TenantCard({ tenant }: TenantRowProps) {
  const { confirmOpen, setConfirmOpen, typedSlug, setTypedSlug, reason, setReason, closeConfirm, impersonateMutation } =
    useTenantImpersonation(tenant);

  const statusColors: Record<string, string> = {
    active: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    suspended: 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/30 dark:text-yellow-400',
    deleted: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400',
    trial: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  };

  return (
    <div className="rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800 p-4 flex flex-col gap-3">
      {/* Header row: name + status badge */}
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="font-semibold text-surface-900 dark:text-surface-100 text-sm truncate">{tenant.name}</div>
          <div className="text-xs text-surface-400 font-mono mt-0.5 truncate">{tenant.slug}</div>
        </div>
        <span className={cn('shrink-0 px-2 py-0.5 rounded-full text-xs font-medium', statusColors[tenant.status] ?? 'bg-surface-100 text-surface-600')}>
          {tenant.status}
        </span>
      </div>

      {/* Key fields */}
      <div className="grid grid-cols-2 gap-x-4 gap-y-1.5 text-xs text-surface-500 dark:text-surface-400">
        <div>
          <span className="block text-surface-400 dark:text-surface-500 uppercase tracking-wide text-[10px] font-semibold mb-0.5">Email</span>
          <span className="truncate block">{tenant.admin_email}</span>
        </div>
        <div>
          <span className="block text-surface-400 dark:text-surface-500 uppercase tracking-wide text-[10px] font-semibold mb-0.5">Plan</span>
          <span>{tenant.plan}</span>
        </div>
        <div>
          <span className="block text-surface-400 dark:text-surface-500 uppercase tracking-wide text-[10px] font-semibold mb-0.5">DB Size</span>
          <span>{tenant.db_size_mb} MB</span>
        </div>
        <div>
          <span className="block text-surface-400 dark:text-surface-500 uppercase tracking-wide text-[10px] font-semibold mb-0.5">Created</span>
          <span>{formatTenantCreatedAt(tenant.created_at)}</span>
        </div>
      </div>

      {/* Action */}
      <div className="pt-1 border-t border-surface-100 dark:border-surface-700">
        <button
          onClick={() => setConfirmOpen(true)}
          disabled={impersonateMutation.isPending || tenant.status !== 'active'}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium bg-amber-600 text-white border border-amber-700 rounded-lg hover:bg-amber-700 dark:bg-amber-700 dark:border-amber-600 dark:hover:bg-amber-600 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
          title={tenant.status !== 'active' ? `Cannot impersonate: tenant is ${tenant.status}` : 'Log in as tenant admin'}
        >
          {impersonateMutation.isPending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <LogIn className="h-3.5 w-3.5" />
          )}
          Log in as
        </button>
      </div>

      {confirmOpen && (
        <ImpersonateConfirmModal
          tenantSlug={tenant.slug}
          tenantName={tenant.name}
          typedSlug={typedSlug}
          reason={reason}
          onTypedSlugChange={setTypedSlug}
          onReasonChange={setReason}
          onCancel={closeConfirm}
          onConfirm={() => impersonateMutation.mutate(reason.trim())}
          submitting={impersonateMutation.isPending}
        />
      )}
    </div>
  );
}

export function TenantsListPage() {
  const [isAuthenticated, setIsAuthenticated] = useState<boolean>(
    () => Boolean(superAdminTokenStore.get()),
  );
  const [statusFilter, setStatusFilter] = useState('');
  const [search, setSearch] = useState('');
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const [page, setPage] = useState(1);
  const [pageSize, setPageSize] = useState(25);

  useEffect(() => {
    const id = window.setTimeout(() => {
      setDebouncedSearch(search.trim());
      setPage(1);
    }, 200);
    return () => window.clearTimeout(id);
  }, [search]);

  // When the superAdminClient response interceptor detects a 401/403 it
  // clears the token and dispatches SUPER_ADMIN_LOGOUT_EVENT. Drop back to
  // the login form so the page doesn't sit in an authed state calling into
  // a dead session.
  useEffect(() => {
    const handleLogout = () => setIsAuthenticated(false);
    window.addEventListener(SUPER_ADMIN_LOGOUT_EVENT, handleLogout);
    return () => window.removeEventListener(SUPER_ADMIN_LOGOUT_EVENT, handleLogout);
  }, []);

  const {
    data,
    isLoading,
    isFetching,
    isError,
    refetch,
  } = useQuery({
    queryKey: ['super-admin-tenants', { statusFilter, debouncedSearch, page, pageSize }],
    queryFn: () => superAdminApi.listTenants({
      page,
      per_page: pageSize,
      status: statusFilter || undefined,
      search: debouncedSearch || undefined,
    }),
    enabled: isAuthenticated,
    retry: false,
  });

  const tenants = data?.data?.data?.tenants ?? [];
  const pagination = data?.data?.data?.pagination;
  const currentPage = pagination?.page ?? page;
  const totalPages = pagination?.total_pages ?? 1;
  const perPage = pagination?.per_page ?? pageSize;
  const totalTenants = pagination?.total ?? tenants.length;
  const showingStart = totalTenants === 0 ? 0 : (currentPage - 1) * perPage + 1;
  const showingEnd = totalTenants === 0 ? 0 : Math.min(currentPage * perPage, totalTenants);

  const handleSignOut = () => {
    // WEB-S4-042: call server logout so the audit log records the
    // sign-out; best-effort — token is removed locally regardless.
    superAdminApi.logout().finally(() => {
      superAdminTokenStore.remove();
      setIsAuthenticated(false);
    });
  };

  useEffect(() => {
    if (pagination && pagination.page !== page) {
      setPage(pagination.page);
    }
  }, [pagination, page]);

  const visiblePages = useMemo(() => {
    const maxButtons = 7;
    if (totalPages <= maxButtons) {
      return Array.from({ length: totalPages }, (_, i) => i + 1);
    }
    const half = Math.floor(maxButtons / 2);
    const start = Math.max(1, Math.min(currentPage - half, totalPages - maxButtons + 1));
    return Array.from({ length: maxButtons }, (_, i) => start + i);
  }, [currentPage, totalPages]);

  if (!isAuthenticated) {
    return (
      <SuperAdminLoginForm
        onSuccess={() => setIsAuthenticated(true)}
      />
    );
  }

  return (
    <div>
      <div className="mb-6 flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex items-center gap-3">
          <Building2 className="h-6 w-6 text-primary-600" />
          <div>
            <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100">Tenants</h1>
            <p className="text-sm text-surface-500 dark:text-surface-400">
              {totalTenants} tenant{totalTenants !== 1 ? 's' : ''}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2 self-start rounded-lg border border-surface-200 bg-surface-50 px-2.5 py-1.5 text-xs text-surface-500 dark:border-surface-700 dark:bg-surface-800/70 dark:text-surface-400">
          <ShieldCheck className="h-4 w-4 text-primary-600 dark:text-primary-400" aria-hidden="true" />
          <span className="font-medium text-surface-700 dark:text-surface-200">Super-admin session</span>
          <button
            type="button"
            onClick={handleSignOut}
            className="inline-flex items-center gap-1 rounded-md px-1.5 py-1 font-medium text-surface-500 transition-colors hover:bg-white hover:text-surface-800 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:text-surface-400 dark:hover:bg-surface-700 dark:hover:text-surface-100"
          >
            <LogOut className="h-3.5 w-3.5" aria-hidden="true" />
            Sign out
          </button>
        </div>
      </div>

      <div className="mb-4 flex flex-col gap-3 md:flex-row md:items-center md:justify-between">
        <div className="flex w-full flex-col gap-3 sm:flex-row sm:items-center md:max-w-2xl">
          <div className="relative w-full sm:max-w-sm">
            <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="search"
              aria-label="Search tenants"
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search tenants"
              className="w-full rounded-lg border border-surface-200 bg-white py-2 pl-9 pr-3 text-sm text-surface-900 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
            />
          </div>
          <div className="flex items-center gap-2">
            {isFetching && !isLoading && (
              <Loader2 className="h-4 w-4 animate-spin text-surface-400" aria-label="Loading tenants" />
            )}
            <select
              aria-label="Filter tenants by status"
              value={statusFilter}
              onChange={(e) => {
                setStatusFilter(e.target.value);
                setPage(1);
              }}
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 sm:w-auto"
            >
              <option value="">All statuses</option>
              <option value="active">Active</option>
              <option value="trial">Trial</option>
              <option value="suspended">Suspended</option>
              <option value="deleted">Deleted</option>
            </select>
          </div>
        </div>
        <label className="flex items-center gap-2 text-sm text-surface-500 dark:text-surface-400">
          Rows
          <select
            value={pageSize}
            onChange={(e) => {
              setPageSize(Number(e.target.value));
              setPage(1);
            }}
            className="rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200"
          >
            {[10, 25, 50, 100].map((size) => (
              <option key={size} value={size}>{size}</option>
            ))}
          </select>
        </label>
      </div>

      {isError && (
        <div className="flex flex-col items-center justify-center py-16 gap-3">
          <AlertCircle className="h-10 w-10 text-red-400" />
          <p className="text-sm text-surface-500">Failed to load tenants.</p>
          <button
            onClick={() => refetch()}
            className="px-4 py-2 text-sm text-primary-600 border border-primary-200 rounded-lg hover:bg-primary-50"
          >
            Retry
          </button>
        </div>
      )}

      {isLoading && (
        <div className="flex justify-center py-16">
          <Loader2 className="h-8 w-8 animate-spin text-primary-400" />
        </div>
      )}

      {!isLoading && !isError && (
        <div>
          {/* Mobile card list — hidden at md+ */}
          <div className="md:hidden grid grid-cols-1 gap-3 mb-4">
            {tenants.length === 0 ? (
              <p className="text-center text-sm text-surface-400 py-12">No tenants found.</p>
            ) : (
              tenants.map((t) => <TenantCard key={t.id} tenant={t} />)
            )}
          </div>

          {/* Desktop table — hidden below md */}
          <div className="hidden md:block rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="bg-surface-50 dark:bg-surface-800/80">
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Tenant</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Admin Email</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Status</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Plan</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">DB Size</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Created</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold text-surface-500 uppercase tracking-wide">Actions</th>
                </tr>
              </thead>
              <tbody>
                {tenants.length === 0 ? (
                  <tr>
                    <td colSpan={7} className="px-4 py-12 text-center text-sm text-surface-400">
                      No tenants found.
                    </td>
                  </tr>
                ) : (
                  tenants.map((t) => <TenantRow key={t.id} tenant={t} />)
                )}
              </tbody>
            </table>
          </div>
          <div className="flex flex-col gap-3 border-t border-surface-100 px-4 py-3 text-sm text-surface-500 dark:border-surface-700 dark:text-surface-400 md:flex-row md:items-center md:justify-between">
            <div>
              Showing {showingStart}-{showingEnd} of {totalTenants}
            </div>
            <div className="flex items-center gap-1">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={currentPage <= 1}
                className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-surface-200 text-surface-600 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                aria-label="Previous page"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              {visiblePages.map((pageNumber) => (
                <button
                  key={pageNumber}
                  type="button"
                  onClick={() => setPage(pageNumber)}
                  className={cn(
                    'inline-flex h-9 min-w-9 items-center justify-center rounded-lg border px-3 text-sm font-medium transition-colors',
                    pageNumber === currentPage
                      ? 'border-primary-200 bg-primary-50 text-primary-700 dark:border-primary-700 dark:bg-primary-950/40 dark:text-primary-300'
                      : 'border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700',
                  )}
                  aria-current={pageNumber === currentPage ? 'page' : undefined}
                >
                  {pageNumber}
                </button>
              ))}
              <button
                type="button"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage >= totalPages}
                className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-surface-200 text-surface-600 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                aria-label="Next page"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
          </div>

          {/* Mobile pagination — visible below md */}
          <div className="md:hidden flex flex-col gap-3 border-t border-surface-100 dark:border-surface-700 px-1 py-3 text-sm text-surface-500 dark:text-surface-400">
            <div>Showing {showingStart}-{showingEnd} of {totalTenants}</div>
            <div className="flex items-center gap-1 flex-wrap">
              <button
                type="button"
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={currentPage <= 1}
                className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-surface-200 text-surface-600 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                aria-label="Previous page"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              {visiblePages.map((pageNumber) => (
                <button
                  key={pageNumber}
                  type="button"
                  onClick={() => setPage(pageNumber)}
                  className={cn(
                    'inline-flex h-9 min-w-9 items-center justify-center rounded-lg border px-3 text-sm font-medium transition-colors',
                    pageNumber === currentPage
                      ? 'border-primary-200 bg-primary-50 text-primary-700 dark:border-primary-700 dark:bg-primary-950/40 dark:text-primary-300'
                      : 'border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700',
                  )}
                  aria-current={pageNumber === currentPage ? 'page' : undefined}
                >
                  {pageNumber}
                </button>
              ))}
              <button
                type="button"
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={currentPage >= totalPages}
                className="inline-flex h-9 w-9 items-center justify-center rounded-lg border border-surface-200 text-surface-600 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                aria-label="Next page"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
