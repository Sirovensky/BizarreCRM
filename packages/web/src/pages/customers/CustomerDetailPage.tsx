import React, { useState, useEffect, useRef, useCallback } from 'react';
import { useParams, useNavigate, Link, useLocation } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Pencil,
  Trash2,
  Save,
  Loader2,
  Ticket,
  FileText,
  MessageSquare,
  Monitor,
  User,
  Plus,
  X,
  AlertCircle,
  DollarSign,
  TrendingUp,
  Calendar,
  ShoppingCart,
  Shield,
  Download,
  GitMerge,
  Search,
  ArrowRight,
  ChevronRight,
  Crown,
  Pause,
  Play,
  Gift,
  Wallet,
  Copy,
  Eraser,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi, membershipApi, settingsApi, crmApi, privacyApi } from '@/api/endpoints';
import { api } from '@/api/client';
import { useAuthStore } from '@/stores/authStore';
// WEB-FAE-003: write recent_views under a per-user key so signing in as a
// different user on the same browser can't read another user's recent
// customer labels (PII). Reader is `Sidebar.RecentViews`.
import { recentViewsKey } from '@/components/layout/Sidebar';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatShortDateTime } from '@/utils/format';
import { formatPhoneAsYouType, stripPhone } from '@/utils/phoneFormat';
import { CopyButton } from '@/components/shared/CopyButton';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { BackButton } from '@/components/shared/BackButton';
// Audit §49 — CRM enrichment badges + mementos wallet
import { HealthScoreBadge } from './components/HealthScoreBadge';
import { LtvTierBadge } from './components/LtvTierBadge';
import { PhotoMementosWallet } from './components/PhotoMementosWallet';
import type {
  Customer,
  UpdateCustomerInput,
  CustomerAsset,
} from '@bizarre-crm/shared';

/** Safely parse tags which may be an array, a JSON string, or a plain string */
function parseTags(tags: unknown): string[] {
  if (Array.isArray(tags)) return tags;
  if (typeof tags === 'string') {
    try { const p = JSON.parse(tags); if (Array.isArray(p)) return p; } catch { /* not JSON */ }
    return tags ? [tags] : [];
  }
  return [];
}

type TabId = 'info' | 'tickets' | 'invoices' | 'communications' | 'assets';

const tabs: { id: TabId; label: string; icon: typeof User }[] = [
  { id: 'info', label: 'Info', icon: User },
  { id: 'tickets', label: 'Tickets', icon: Ticket },
  { id: 'invoices', label: 'Invoices', icon: FileText },
  { id: 'communications', label: 'Communications', icon: MessageSquare },
  { id: 'assets', label: 'Assets', icon: Monitor },
];

export function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const location = useLocation();
  const queryClient = useQueryClient();
  const customerId = Number(id);
  const isValidId = id != null && !isNaN(customerId) && customerId > 0;

  // FA-M26: the CRM enrichment endpoints (wallet-pass GET + referral-code
  // POST) are admin/manager-only on the server (crm.routes.ts:258, 327).
  // Hide the actions from other roles so non-privileged staff aren't shown
  // buttons that would just 403.
  const userRole = useAuthStore((s) => s.user?.role);
  const userId = useAuthStore((s) => s.user?.id);
  const canUseEnrichmentActions = userRole === 'admin' || userRole === 'manager';

  const [activeTab, setActiveTab] = useState<TabId>('info');

  // Handle direct tab deep-links from other pages
  useEffect(() => {
    if (location.hash === '#assets') setActiveTab('assets');
    else if (location.hash === '#invoices') setActiveTab('invoices');
    else if (location.hash === '#tickets') setActiveTab('tickets');
    else if (location.hash === '#communications') setActiveTab('communications');
  }, [location.hash]);

  // Fetch customer
  const {
    data: customerRes,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ['customer', customerId],
    queryFn: () => customerApi.get(customerId),
    enabled: isValidId,
  });

  const customer: Customer | undefined = customerRes?.data?.data;

  // Track recent views — keys on id/first_name/last_name so a rename in-place
  // re-writes the stored label. Bounded at 20 entries (W7 fix) with the oldest
  // entries sliced off, so the localStorage quota can't grow unbounded as users
  // browse hundreds of customers.
  const RECENT_VIEWS_MAX = 20;
  useEffect(() => {
    if (!customer) return;
    try {
      const key = recentViewsKey(userId);
      const raw = localStorage.getItem(key);
      const existing: { type: string; id: number; label: string; path: string }[] = raw
        ? JSON.parse(raw)
        : [];
      const label = `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim() || 'Customer';
      const entry = { type: 'customer', id: customer.id, label, path: `/customers/${customer.id}` };
      const filtered = existing.filter((e) => !(e.type === 'customer' && e.id === customer.id));
      filtered.unshift(entry);
      localStorage.setItem(key, JSON.stringify(filtered.slice(0, RECENT_VIEWS_MAX)));
    } catch (err) {
      console.warn('Failed to update recent views:', err);
    }
  }, [customer?.id, customer?.first_name, customer?.last_name, userId]);

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: (confirmName: string) => customerApi.delete(customerId, confirmName),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['customer', customerId] });
      toast.success('Customer deleted');
      navigate('/customers');
    },
    onError: () => toast.error('Failed to delete customer'),
  });

  // FA-M26: referral-code minting surfaces the returned code with a
  // copy-to-clipboard affordance. Reused codes are announced separately so
  // the user knows we're showing them the existing referral, not a new one.
  const mintReferralMutation = useMutation({
    mutationFn: () => crmApi.mintReferralCode(customerId),
    onSuccess: async (res) => {
      const code: string | undefined = res?.data?.data?.referral_code;
      const reused: boolean = Boolean(res?.data?.data?.reused);
      if (!code) {
        toast.error('Referral code not returned by server');
        return;
      }
      try {
        if (navigator.clipboard?.writeText) {
          await navigator.clipboard.writeText(code);
          toast.success(
            reused
              ? `Existing referral code copied: ${code}`
              : `Referral code created and copied: ${code}`,
          );
        } else {
          toast.success(reused ? `Existing referral code: ${code}` : `Referral code: ${code}`);
        }
      } catch {
        toast.success(reused ? `Existing referral code: ${code}` : `Referral code: ${code}`);
      }
    },
    onError: (err: unknown) => {
      const message =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(message || 'Failed to mint referral code');
    },
  });

  // FA-M26: the wallet-pass endpoint returns HTML (or a .pkpass binary when
  // pkpass signing is configured). The server enforces Authorization via the
  // standard bearer middleware, which a plain window.open cannot satisfy
  // from localStorage. Fetch the HTML with our authenticated axios client,
  // materialise it as a Blob, then open that blob URL in a new tab. Blob
  // URLs expire with the document, so we revoke after a delay to release
  // memory without pulling the rug out from under the new window.
  //
  // Longer-term: mint a signed short-lived pass URL server-side so the
  // customer can open it on their phone without a staff session token
  // (mirrors the FA-M12 photo-upload token design).
  const handleOpenWalletPass = async () => {
    if (walletPassLoading) return;
    setWalletPassLoading(true);
    try {
      const res = await api.get(`/crm/customers/${customerId}/wallet-pass`, {
        responseType: 'blob',
      });
      const contentType = (res.headers?.['content-type'] as string | undefined) || 'text/html';
      const blob = new Blob([res.data as BlobPart], { type: contentType });
      const url = URL.createObjectURL(blob);
      const win = window.open(url, '_blank', 'noopener,noreferrer');
      if (!win) toast.error('Pop-up blocked. Allow pop-ups for this site to view the wallet pass.');
      setTimeout(() => URL.revokeObjectURL(url), 60_000);
    } catch (err: unknown) {
      const message =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(message || 'Failed to load wallet pass');
    } finally {
      setWalletPassLoading(false);
    }
  };

  const erasePiiMutation = useMutation({
    mutationFn: (confirmName: string) =>
      privacyApi.eraseCustomerPii({ customer_id: customerId, confirm_name: confirmName }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer', id] });
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      toast.success('Customer PII erased successfully');
      navigate('/customers');
    },
    onError: (err: unknown) => {
      const message =
        err && typeof err === 'object' && 'response' in err
          ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
          : undefined;
      toast.error(message || 'Failed to erase customer PII');
    },
  });

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);
  const [showEraseConfirm, setShowEraseConfirm] = useState(false);
  const [showMergeModal, setShowMergeModal] = useState(false);
  const [exporting, setExporting] = useState(false);
  // FA-M26: loading flag for the wallet-pass fetch button.
  const [walletPassLoading, setWalletPassLoading] = useState(false);

  const handleDelete = () => {
    if (!customer) return;
    setShowDeleteConfirm(true);
  };

  const handleExportData = async () => {
    setExporting(true);
    try {
      const res = await customerApi.exportData(customerId);
      const exportPayload = res.data.data;
      const blob = new Blob([JSON.stringify(exportPayload, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `customer-${customerId}-data-export-${new Date().toISOString().slice(0, 10)}.json`;
      a.click();
      URL.revokeObjectURL(url);
      toast.success('Customer data exported successfully');
    } catch {
      toast.error('Failed to export customer data');
    } finally {
      setExporting(false);
    }
  };

  if (isLoading) {
    return <DetailSkeleton />;
  }

  if (!isValidId || isError || !customer) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-16 w-16 text-red-400 mb-4" />
        <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
          {!isValidId ? 'Invalid Customer ID' : 'Customer not found'}
        </h2>
        <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
          {!isValidId
            ? 'The URL contains an invalid customer ID.'
            : 'The customer you are looking for does not exist or has been deleted.'}
        </p>
        <Link
          to="/customers"
          className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium text-sm transition-colors"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Customers
        </Link>
      </div>
    );
  }

  const fullName = `${customer.first_name} ${customer.last_name}`.trim();

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Customers', href: '/customers' },
        { label: fullName || 'Customer' },
      ]} />
      {/* Header */}
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="flex items-center gap-4">
          <BackButton to="/customers" />
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                {fullName}
              </h1>
              {customer.code && (
                <span className="px-2.5 py-0.5 rounded-full text-xs font-mono font-medium bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400">
                  {customer.code}
                </span>
              )}
              {/* Audit §49 — health score + LTV tier badges */}
              <HealthScoreBadge customerId={customerId} />
              <LtvTierBadge customerId={customerId} showValue={false} />
              {/* FA-M26: referral + wallet-pass enrichment actions. Admin
                  /manager only — server returns 403 otherwise so we hide
                  the buttons from staff who can't use them. */}
              {canUseEnrichmentActions && (
                <>
                  <button
                    type="button"
                    onClick={() => mintReferralMutation.mutate()}
                    disabled={mintReferralMutation.isPending}
                    title="Mint or copy this customer's referral code"
                    className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border border-purple-200 text-purple-700 bg-purple-50 hover:bg-purple-100 disabled:opacity-60 dark:border-purple-500/30 dark:text-purple-300 dark:bg-purple-500/10 dark:hover:bg-purple-500/20 transition-colors"
                  >
                    {mintReferralMutation.isPending ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Gift className="h-3.5 w-3.5" />
                    )}
                    Referral code
                    <Copy className="h-3 w-3 opacity-70" />
                  </button>
                  <button
                    type="button"
                    onClick={handleOpenWalletPass}
                    disabled={walletPassLoading}
                    title="Open this customer's wallet pass in a new tab"
                    className="inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border border-sky-200 text-sky-700 bg-sky-50 hover:bg-sky-100 disabled:opacity-60 dark:border-sky-500/30 dark:text-sky-300 dark:bg-sky-500/10 dark:hover:bg-sky-500/20 transition-colors"
                  >
                    {walletPassLoading ? (
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                    ) : (
                      <Wallet className="h-3.5 w-3.5" />
                    )}
                    Wallet pass
                  </button>
                </>
              )}
            </div>
            <p className="text-surface-500 dark:text-surface-400 text-sm">
              {customer.type === 'business' ? 'Business' : 'Individual'}
              {customer.organization && ` \u00b7 ${customer.organization}`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => navigate(`/pos?customer=${customerId}`)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-green-600 rounded-lg hover:bg-green-700 transition-colors shadow-sm"
          >
            <ShoppingCart className="h-4 w-4" />
            New Ticket
          </button>
          <button
            onClick={() => setShowMergeModal(true)}
            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors"
          >
            <GitMerge className="h-4 w-4" />
            Merge
          </button>
          <button
            onClick={handleExportData}
            disabled={exporting}
            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors disabled:opacity-50"
          >
            {exporting ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
            Export Data
          </button>
          <button
            onClick={handleDelete}
            disabled={deleteMutation.isPending}
            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-600 dark:text-red-400 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
          >
            <Trash2 className="h-4 w-4" />
            Delete
          </button>
          {userRole === 'admin' && (
            <button
              onClick={() => setShowEraseConfirm(true)}
              disabled={erasePiiMutation.isPending}
              className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-700 dark:text-red-300 border border-red-300 dark:border-red-700 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors disabled:opacity-50"
            >
              <Eraser className="h-4 w-4" />
              Erase PII (GDPR)
            </button>
          )}
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-surface-200 dark:border-surface-700 mb-6">
        <div className="flex gap-1 -mb-px">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={cn(
                  'inline-flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors',
                  activeTab === tab.id
                    ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                    : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300 hover:border-surface-300 dark:hover:border-surface-600',
                )}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Customer analytics cards */}
      <CustomerAnalyticsBar customerId={customerId} />

      {/* Audit §49 — Photo mementos wallet (only on info tab) */}
      {activeTab === 'info' && <PhotoMementosWallet customerId={customerId} />}

      {/* Tab content */}
      {activeTab === 'info' && (
        <InfoTab customer={customer} customerId={customerId} />
      )}
      {activeTab === 'tickets' && <TicketsTab customerId={customerId} />}
      {activeTab === 'invoices' && <InvoicesTab customerId={customerId} />}
      {activeTab === 'communications' && <CommunicationsTab customerId={customerId} />}
      {activeTab === 'assets' && <AssetsTab customerId={customerId} />}

      <ConfirmDialog
        open={showDeleteConfirm}
        title="Delete Customer"
        message={`Are you sure you want to delete "${customer ? `${customer.first_name} ${customer.last_name}`.trim() : ''}"? This action cannot be undone.`}
        confirmLabel="Delete"
        danger
        requireTyping
        confirmText={customer ? `${customer.first_name} ${customer.last_name}`.trim() : ''}
        onConfirm={() => { setShowDeleteConfirm(false); deleteMutation.mutate(`${customer.first_name} ${customer.last_name}`.trim()); }}
        onCancel={() => setShowDeleteConfirm(false)}
      />

      <ConfirmDialog
        open={showEraseConfirm}
        title="Erase Customer PII (GDPR)"
        message={`This will permanently remove all personally identifiable information (name, email, phone, address) for this customer. Tickets, invoices, and other business records will be retained with anonymised references. This action cannot be undone.`}
        confirmLabel="Erase PII"
        danger
        requireTyping
        confirmText={customer ? `${customer.first_name} ${customer.last_name}`.trim() : ''}
        onConfirm={() => {
          setShowEraseConfirm(false);
          erasePiiMutation.mutate(`${customer.first_name} ${customer.last_name}`.trim());
        }}
        onCancel={() => setShowEraseConfirm(false)}
      />

      {showMergeModal && customer && (
        <CustomerMergeModal
          keepCustomer={customer}
          onClose={() => setShowMergeModal(false)}
          onMerged={() => {
            setShowMergeModal(false);
            queryClient.invalidateQueries({ queryKey: ['customer', customerId] });
            queryClient.invalidateQueries({ queryKey: ['customers'] });
          }}
        />
      )}
    </div>
  );
}

// ==================== Customer Merge Modal ====================

interface MergeSearchResult {
  id: number;
  first_name: string;
  last_name: string;
  phone?: string;
  mobile?: string;
  email?: string;
  organization?: string;
}

function CustomerMergeModal({
  keepCustomer,
  onClose,
  onMerged,
}: {
  keepCustomer: Customer;
  onClose: () => void;
  onMerged: () => void;
}) {
  const [searchQuery, setSearchQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [selectedMerge, setSelectedMerge] = useState<MergeSearchResult | null>(null);
  const [step, setStep] = useState<'search' | 'confirm'>('search');
  const searchRef = useRef<HTMLInputElement>(null);

  // Debounce search input
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedQuery(searchQuery), 300);
    return () => clearTimeout(debounceRef.current);
  }, [searchQuery]);

  // Search customers
  const { data: searchData, isLoading: searching } = useQuery({
    queryKey: ['customer-merge-search', debouncedQuery],
    queryFn: () => customerApi.search(debouncedQuery),
    enabled: debouncedQuery.length >= 2,
  });

  const searchResults: MergeSearchResult[] = (() => {
    const d = searchData?.data?.data;
    const list: MergeSearchResult[] = Array.isArray(d) ? d : d?.customers || [];
    // Exclude the current customer from results
    return list.filter((c) => c.id !== keepCustomer.id);
  })();

  // Merge mutation
  const mergeMutation = useMutation({
    mutationFn: () => customerApi.merge(keepCustomer.id, selectedMerge!.id),
    onSuccess: () => {
      toast.success(`Customer merged successfully`);
      onMerged();
    },
    onError: (err: any) => {
      const msg = err?.response?.data?.error || 'Failed to merge customers';
      toast.error(msg);
    },
  });

  const keepName = `${keepCustomer.first_name} ${keepCustomer.last_name}`.trim();
  const mergeName = selectedMerge ? `${selectedMerge.first_name} ${selectedMerge.last_name}`.trim() : '';

  // Focus search on mount
  useEffect(() => {
    searchRef.current?.focus();
  }, []);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div
        className="w-full max-w-lg rounded-xl bg-white shadow-xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <div className="flex items-center gap-2">
            <GitMerge className="h-5 w-5 text-primary-600" />
            <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
              Merge Customer
            </h2>
          </div>
          <button aria-label="Close" onClick={onClose} className="text-surface-400 hover:text-surface-600 dark:hover:text-surface-300">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="px-6 py-4">
          {step === 'search' && (
            <>
              <p className="mb-3 text-sm text-surface-600 dark:text-surface-400">
                Search for a duplicate customer to merge into <strong>{keepName}</strong>.
                All tickets, invoices, and communications from the duplicate will be moved to this customer.
              </p>

              {/* Search input */}
              <div className="relative mb-3">
                <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                <input
                  ref={searchRef}
                  type="text"
                  value={searchQuery}
                  onChange={(e) => setSearchQuery(e.target.value)}
                  placeholder="Search by name, phone, or email..."
                  className="w-full rounded-lg border border-surface-300 bg-white py-2.5 pl-10 pr-4 text-sm text-surface-900 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>

              {/* Search results */}
              <div className="max-h-60 overflow-y-auto rounded-lg border border-surface-200 dark:border-surface-700">
                {searching && (
                  <div className="flex items-center justify-center py-8">
                    <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
                  </div>
                )}
                {!searching && debouncedQuery.length >= 2 && searchResults.length === 0 && (
                  <div className="py-8 text-center text-sm text-surface-400">
                    No matching customers found
                  </div>
                )}
                {!searching && debouncedQuery.length < 2 && (
                  <div className="py-8 text-center text-sm text-surface-400">
                    Type at least 2 characters to search
                  </div>
                )}
                {searchResults.map((c) => (
                  <button
                    key={c.id}
                    onClick={() => {
                      setSelectedMerge(c);
                      setStep('confirm');
                    }}
                    className="flex w-full items-center gap-3 border-b border-surface-100 px-4 py-3 text-left transition-colors last:border-0 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-700"
                  >
                    <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-surface-100 text-xs font-semibold text-surface-600 dark:bg-surface-600 dark:text-surface-300">
                      {c.first_name?.[0] || ''}{c.last_name?.[0] || ''}
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="text-sm font-medium text-surface-900 dark:text-surface-100">
                        {c.first_name} {c.last_name}
                        <span className="ml-2 text-xs text-surface-400">#{c.id}</span>
                      </div>
                      <div className="text-xs text-surface-500 dark:text-surface-400 truncate">
                        {c.phone || c.mobile || ''}{c.email ? ` \u00b7 ${c.email}` : ''}
                      </div>
                    </div>
                    <ChevronRight className="h-4 w-4 shrink-0 text-surface-400" />
                  </button>
                ))}
              </div>
            </>
          )}

          {step === 'confirm' && selectedMerge && (
            <>
              <p className="mb-4 text-sm text-surface-600 dark:text-surface-400">
                This will merge all data from the duplicate customer into the primary customer.
                The duplicate will be soft-deleted. This cannot be undone.
              </p>

              <div className="mb-4 flex items-center gap-3">
                {/* Merge (source) customer */}
                <div className="flex-1 rounded-lg border border-red-200 bg-red-50 p-3 dark:border-red-800 dark:bg-red-900/20">
                  <div className="mb-1 text-[10px] font-semibold uppercase tracking-wider text-red-500">
                    Will be deleted
                  </div>
                  <div className="text-sm font-medium text-surface-900 dark:text-surface-100">
                    {mergeName}
                  </div>
                  <div className="text-xs text-surface-500 dark:text-surface-400">
                    #{selectedMerge.id}
                    {selectedMerge.phone ? ` \u00b7 ${selectedMerge.phone}` : ''}
                  </div>
                </div>

                <ArrowRight className="h-5 w-5 shrink-0 text-surface-400" />

                {/* Keep (target) customer */}
                <div className="flex-1 rounded-lg border border-green-200 bg-green-50 p-3 dark:border-green-800 dark:bg-green-900/20">
                  <div className="mb-1 text-[10px] font-semibold uppercase tracking-wider text-green-600 dark:text-green-400">
                    Will keep
                  </div>
                  <div className="text-sm font-medium text-surface-900 dark:text-surface-100">
                    {keepName}
                  </div>
                  <div className="text-xs text-surface-500 dark:text-surface-400">
                    #{keepCustomer.id}
                    {keepCustomer.phone ? ` \u00b7 ${keepCustomer.phone}` : ''}
                  </div>
                </div>
              </div>

              <div className="mb-4 rounded-lg bg-amber-50 px-3 py-2 text-xs text-amber-800 dark:bg-amber-900/20 dark:text-amber-300">
                <strong>What will be moved:</strong> Tickets, invoices, estimates, assets, SMS history,
                phone numbers, email addresses, and tags.
              </div>
            </>
          )}
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-2 border-t border-surface-200 px-6 py-4 dark:border-surface-700">
          {step === 'confirm' && (
            <button
              onClick={() => { setStep('search'); setSelectedMerge(null); }}
              className="px-4 py-2 text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-200"
            >
              Back
            </button>
          )}
          <button
            onClick={onClose}
            className="rounded-lg border border-surface-300 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
          {step === 'confirm' && (
            <button
              onClick={() => mergeMutation.mutate()}
              disabled={mergeMutation.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-red-600 px-4 py-2 text-sm font-semibold text-white transition-colors hover:bg-red-700 disabled:opacity-50"
            >
              {mergeMutation.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <GitMerge className="h-4 w-4" />
              )}
              Merge Customers
            </button>
          )}
        </div>
      </div>
    </div>
  );
}

// ==================== Customer Analytics Bar ====================

function CustomerAnalyticsBar({ customerId }: { customerId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-analytics', customerId],
    queryFn: () => customerApi.analytics(customerId),
    enabled: !!customerId,
    staleTime: 60_000,
  });

  const analytics = data?.data?.data;
  if (isLoading || !analytics) return null;

  const cards = [
    {
      label: 'Lifetime Value',
      value: formatCurrency(analytics.lifetime_value || 0),
      icon: DollarSign,
      color: 'text-green-600 bg-green-50 dark:text-green-400 dark:bg-green-900/20',
    },
    {
      label: 'Total Tickets',
      value: analytics.total_tickets || 0,
      icon: Ticket,
      color: 'text-blue-600 bg-blue-50 dark:text-blue-400 dark:bg-blue-900/20',
    },
    {
      label: 'Avg Ticket',
      value: formatCurrency(analytics.avg_ticket_value || 0),
      icon: TrendingUp,
      color: 'text-purple-600 bg-purple-50 dark:text-purple-400 dark:bg-purple-900/20',
    },
    {
      label: 'Last Visit',
      value: analytics.days_since_last_visit != null
        ? analytics.days_since_last_visit === 0
          ? 'Today'
          : `${analytics.days_since_last_visit}d ago`
        : 'Never',
      icon: Calendar,
      color: 'text-amber-600 bg-amber-50 dark:text-amber-400 dark:bg-amber-900/20',
    },
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
      {cards.map((card) => {
        const Icon = card.icon;
        return (
          <div key={card.label} className="rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 p-3">
            <div className="flex items-center gap-2.5">
              <div className={`flex h-8 w-8 items-center justify-center rounded-lg ${card.color}`}>
                <Icon className="h-4 w-4" />
              </div>
              <div>
                <p className="text-xs text-surface-500 dark:text-surface-400">{card.label}</p>
                <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{card.value}</p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ==================== Info Tab ====================

// ==================== Membership Card ====================

function MembershipCard({ customerId }: { customerId: number }) {
  const queryClient = useQueryClient();

  // Check if membership system is enabled
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
  });
  const enabled = configData?.['membership_enabled'] === 'true';

  // Fetch membership status
  const { data: memberData, isLoading } = useQuery({
    queryKey: ['membership', 'customer', customerId],
    queryFn: async () => {
      const res = await membershipApi.getCustomerMembership(customerId);
      return res.data.data as {
        id: number; tier_id: number; tier_name: string; monthly_price: number;
        discount_pct: number; discount_applies_to: string; benefits: string[];
        color: string; status: string; current_period_end: string;
        cancel_at_period_end: number; pause_reason: string | null;
      } | null;
    },
    enabled,
  });

  // Fetch tiers for enrollment
  const { data: tiersData } = useQuery({
    queryKey: ['membership', 'tiers'],
    queryFn: async () => {
      const res = await membershipApi.getTiers();
      return res.data.data as Array<{
        id: number; name: string; monthly_price: number; discount_pct: number;
        discount_applies_to: string; color: string; benefits: string[];
      }>;
    },
    enabled: enabled && !memberData,
  });
  const tiers = tiersData || [];

  const [enrollOpen, setEnrollOpen] = useState(false);
  const [selectedTier, setSelectedTier] = useState<number | null>(null);

  const subscribeMut = useMutation({
    mutationFn: (tierId: number) =>
      membershipApi.subscribe({ customer_id: customerId, tier_id: tierId }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'customer', customerId] });
      queryClient.invalidateQueries({ queryKey: ['membership', 'subscriptions'] });
      setEnrollOpen(false);
      setSelectedTier(null);
      toast.success('Membership activated!');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to subscribe'),
  });

  const cancelMut = useMutation({
    mutationFn: () => membershipApi.cancel(memberData!.id, { immediate: true }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'customer', customerId] });
      toast.success('Membership cancelled');
    },
    onError: () => toast.error('Failed to cancel'),
  });

  const pauseMut = useMutation({
    mutationFn: () => membershipApi.pause(memberData!.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'customer', customerId] });
      toast.success('Membership paused');
    },
    onError: () => toast.error('Failed to pause'),
  });

  const resumeMut = useMutation({
    mutationFn: () => membershipApi.resume(memberData!.id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'customer', customerId] });
      toast.success('Membership resumed');
    },
    onError: () => toast.error('Failed to resume'),
  });

  if (!enabled) return null;
  if (isLoading) return null;

  // Active membership
  if (memberData) {
    const statusColors: Record<string, string> = {
      active: 'bg-green-100 text-green-700 dark:bg-green-500/20 dark:text-green-400',
      paused: 'bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-400',
      past_due: 'bg-red-100 text-red-700 dark:bg-red-500/20 dark:text-red-400',
    };

    return (
      <div className="card overflow-hidden mb-6">
        <div
          className="px-5 py-3 flex items-center justify-between"
          style={{ backgroundColor: memberData.color + '18' }}
        >
          <div className="flex items-center gap-2">
            <Crown className="h-5 w-5" style={{ color: memberData.color }} />
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Membership</h3>
          </div>
          <span className={cn('inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold', statusColors[memberData.status] || statusColors.active)}>
            {memberData.status}
          </span>
        </div>
        <div className="px-5 py-4 flex items-center justify-between">
          <div>
            <div className="flex items-center gap-2 mb-1">
              <span
                className="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-bold text-white"
                style={{ backgroundColor: memberData.color }}
              >
                {memberData.tier_name}
              </span>
              <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">
                ${memberData.monthly_price.toFixed(2)}/mo
              </span>
            </div>
            <p className="text-xs text-surface-500">
              {memberData.discount_pct}% off {memberData.discount_applies_to}
            </p>
            {memberData.current_period_end && (
              <p className="text-xs text-surface-400 mt-0.5">
                Renews {new Date(memberData.current_period_end).toLocaleDateString()}
              </p>
            )}
            {memberData.cancel_at_period_end === 1 && (
              <p className="text-xs text-amber-600 dark:text-amber-400 mt-0.5">Cancels at period end</p>
            )}
          </div>
          <div className="flex items-center gap-1.5">
            {memberData.status === 'active' && (
              <>
                <button
                  onClick={() => pauseMut.mutate()}
                  disabled={pauseMut.isPending}
                  className="inline-flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-surface-600 dark:text-surface-300 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors"
                >
                  <Pause className="h-3.5 w-3.5" />
                  Pause
                </button>
                <button
                  onClick={() => cancelMut.mutate()}
                  disabled={cancelMut.isPending}
                  className="inline-flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-red-600 dark:text-red-400 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
                >
                  <X className="h-3.5 w-3.5" />
                  Cancel
                </button>
              </>
            )}
            {memberData.status === 'paused' && (
              <button
                onClick={() => resumeMut.mutate()}
                disabled={resumeMut.isPending}
                className="inline-flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium text-green-600 dark:text-green-400 border border-green-200 dark:border-green-800 rounded-lg hover:bg-green-50 dark:hover:bg-green-900/20 transition-colors"
              >
                <Play className="h-3.5 w-3.5" />
                Resume
              </button>
            )}
          </div>
        </div>
      </div>
    );
  }

  // No membership — show enroll option
  return (
    <div className="card overflow-hidden mb-6">
      <div className="px-5 py-3 flex items-center justify-between bg-surface-50 dark:bg-surface-800/50">
        <div className="flex items-center gap-2">
          <Crown className="h-5 w-5 text-surface-400" />
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Membership</h3>
        </div>
        <span className="text-xs text-surface-400">No active membership</span>
      </div>
      {!enrollOpen ? (
        <div className="px-5 py-4">
          <button
            onClick={() => setEnrollOpen(true)}
            disabled={tiers.length === 0}
            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition-colors disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
            Enroll in Membership
          </button>
          {tiers.length === 0 && (
            <p className="text-xs text-surface-400 mt-2">No membership tiers configured. Go to Settings to add tiers.</p>
          )}
        </div>
      ) : (
        <div className="px-5 py-4 space-y-3">
          <p className="text-sm font-medium text-surface-700 dark:text-surface-300">Select a tier:</p>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-2">
            {tiers.map((tier) => (
              <button
                key={tier.id}
                onClick={() => setSelectedTier(tier.id)}
                className={cn(
                  'rounded-lg border-2 p-3 text-left transition-all',
                  selectedTier === tier.id
                    ? 'shadow-md scale-[1.02]'
                    : 'border-surface-200 dark:border-surface-700 hover:border-surface-300 dark:hover:border-surface-600',
                )}
                style={selectedTier === tier.id ? { borderColor: tier.color, backgroundColor: tier.color + '10' } : undefined}
              >
                <div className="flex items-center gap-2 mb-1">
                  <div className="h-3 w-3 rounded-full" style={{ backgroundColor: tier.color }} />
                  <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">{tier.name}</span>
                </div>
                <p className="text-lg font-bold text-surface-900 dark:text-surface-100">${tier.monthly_price.toFixed(2)}<span className="text-xs font-normal text-surface-400">/mo</span></p>
                <p className="text-xs text-surface-500 mt-0.5">{tier.discount_pct}% off {tier.discount_applies_to}</p>
              </button>
            ))}
          </div>
          <div className="flex items-center gap-2 pt-1">
            <button
              onClick={() => selectedTier && subscribeMut.mutate(selectedTier)}
              disabled={!selectedTier || subscribeMut.isPending}
              className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition-colors disabled:opacity-50"
            >
              {subscribeMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Crown className="h-4 w-4" />}
              Activate Membership
            </button>
            <button
              onClick={() => { setEnrollOpen(false); setSelectedTier(null); }}
              className="px-3 py-2 text-sm text-surface-500 hover:text-surface-700 dark:hover:text-surface-300 transition-colors"
            >
              Cancel
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

function InfoTab({
  customer,
  customerId,
}: {
  customer: Customer;
  customerId: number;
}) {
  const queryClient = useQueryClient();

  const [form, setForm] = useState({
    first_name: customer.first_name || '',
    last_name: customer.last_name || '',
    type: customer.type || 'individual',
    organization: customer.organization || '',
    email: customer.email || '',
    phone: customer.phone || '',
    mobile: customer.mobile || '',
    address1: customer.address1 || '',
    address2: customer.address2 || '',
    city: customer.city || '',
    state: customer.state || '',
    postcode: customer.postcode || '',
    country: customer.country || 'US',
    referred_by: customer.referred_by || '',
    comments: customer.comments || '',
    tags: parseTags(customer.tags).join(', '),
    email_opt_in: customer.email_opt_in,
    sms_opt_in: customer.sms_opt_in,
    tax_number: customer.tax_number || '',
  });

  // Reset form when customer changes
  useEffect(() => {
    setForm({
      first_name: customer.first_name || '',
      last_name: customer.last_name || '',
      type: customer.type || 'individual',
      organization: customer.organization || '',
      email: customer.email || '',
      phone: customer.phone || '',
      mobile: customer.mobile || '',
      address1: customer.address1 || '',
      address2: customer.address2 || '',
      city: customer.city || '',
      state: customer.state || '',
      postcode: customer.postcode || '',
      country: customer.country || 'US',
      referred_by: customer.referred_by || '',
      comments: customer.comments || '',
      tags: parseTags(customer.tags).join(', '),
      email_opt_in: customer.email_opt_in,
      sms_opt_in: customer.sms_opt_in,
      tax_number: customer.tax_number || '',
    });
  }, [customer]);

  const updateMutation = useMutation({
    mutationFn: (data: UpdateCustomerInput) =>
      customerApi.update(customerId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer', customerId] });
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      toast.success('Customer updated');
    },
    onError: () => toast.error('Failed to update customer'),
  });

  const updateField = (key: string, value: any) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const handleSave = () => {
    if (!form.first_name.trim()) {
      toast.error('First name is required');
      return;
    }

    const payload: UpdateCustomerInput = {
      first_name: form.first_name.trim(),
      last_name: form.last_name.trim() || undefined,
      type: form.type as 'individual' | 'business',
      organization: form.organization.trim() || undefined,
      email: form.email.trim() || undefined,
      phone: stripPhone(form.phone) || undefined,
      mobile: stripPhone(form.mobile) || undefined,
      address1: form.address1.trim() || undefined,
      address2: form.address2.trim() || undefined,
      city: form.city.trim() || undefined,
      state: form.state.trim() || undefined,
      postcode: form.postcode.trim() || undefined,
      country: form.country.trim() || undefined,
      referred_by: form.referred_by.trim() || undefined,
      comments: form.comments.trim() || undefined,
      tax_number: form.tax_number.trim() || undefined,
      tags: form.tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean),
      email_opt_in: form.email_opt_in,
      sms_opt_in: form.sms_opt_in,
    };

    updateMutation.mutate(payload);
  };

  return (
    <div>
      <MembershipCard customerId={customerId} />

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Basic Info */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Basic Information
          </h3>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="First Name" required>
                <input
                  type="text"
                  value={form.first_name}
                  onChange={(e) => updateField('first_name', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="Last Name">
                <input
                  type="text"
                  value={form.last_name}
                  onChange={(e) => updateField('last_name', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
            <FieldBlock label="Type">
              <select
                value={form.type}
                onChange={(e) => updateField('type', e.target.value)}
                className="input"
              >
                <option value="individual">Individual</option>
                <option value="business">Business</option>
              </select>
            </FieldBlock>
            <FieldBlock label="Organization">
              <input
                type="text"
                value={form.organization}
                onChange={(e) => updateField('organization', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Tax Number">
              <input
                type="text"
                value={form.tax_number}
                onChange={(e) => updateField('tax_number', e.target.value)}
                className="input"
              />
            </FieldBlock>
          </div>
        </div>

        {/* Contact */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Contact Information
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Email">
              <input
                type="email"
                value={form.email}
                onChange={(e) => updateField('email', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Phone">
              <div className="flex items-center gap-1">
                <input
                  type="tel"
                  value={form.phone}
                  onChange={(e) => updateField('phone', formatPhoneAsYouType(e.target.value))}
                  className="input flex-1"
                />
                {form.phone && <CopyButton text={stripPhone(form.phone)} />}
              </div>
            </FieldBlock>
            <FieldBlock label="Mobile">
              <div className="flex items-center gap-1">
                <input
                  type="tel"
                  value={form.mobile}
                  onChange={(e) => updateField('mobile', formatPhoneAsYouType(e.target.value))}
                  className="input flex-1"
                />
                {form.mobile && <CopyButton text={stripPhone(form.mobile)} />}
              </div>
            </FieldBlock>

            {/* Phone list from API */}
            {customer.phones && customer.phones.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Additional Phones
                </label>
                <div className="space-y-1">
                  {customer.phones.map((p) => (
                    <div
                      key={p.id}
                      className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400"
                    >
                      <span className="px-1.5 py-0.5 rounded text-xs bg-surface-100 dark:bg-surface-700 text-surface-500 dark:text-surface-400">
                        {p.label}
                      </span>
                      <span>{p.phone}</span>
                      {p.is_primary && (
                        <span className="text-xs text-primary-600 dark:text-primary-400">
                          Primary
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Email list from API */}
            {customer.emails && customer.emails.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Additional Emails
                </label>
                <div className="space-y-1">
                  {customer.emails.map((em) => (
                    <div
                      key={em.id}
                      className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400"
                    >
                      <span className="px-1.5 py-0.5 rounded text-xs bg-surface-100 dark:bg-surface-700 text-surface-500 dark:text-surface-400">
                        {em.label}
                      </span>
                      <span>{em.email}</span>
                      {em.is_primary && (
                        <span className="text-xs text-primary-600 dark:text-primary-400">
                          Primary
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Address */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Address
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Address Line 1">
              <input
                type="text"
                value={form.address1}
                onChange={(e) => updateField('address1', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Address Line 2">
              <input
                type="text"
                value={form.address2}
                onChange={(e) => updateField('address2', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="City">
                <input
                  type="text"
                  value={form.city}
                  onChange={(e) => updateField('city', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="State">
                <input
                  type="text"
                  value={form.state}
                  onChange={(e) => updateField('state', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="Postcode">
                <input
                  type="text"
                  value={form.postcode}
                  onChange={(e) => updateField('postcode', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="Country">
                <input
                  type="text"
                  value={form.country}
                  onChange={(e) => updateField('country', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
          </div>
        </div>

        {/* Additional */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Additional Information
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Referred By">
              <input
                type="text"
                value={form.referred_by}
                onChange={(e) => updateField('referred_by', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Tags">
              <input
                type="text"
                value={form.tags}
                onChange={(e) => updateField('tags', e.target.value)}
                className="input"
                placeholder="Comma separated tags"
              />
            </FieldBlock>
            <FieldBlock label="Comments">
              <textarea
                value={form.comments}
                onChange={(e) => updateField('comments', e.target.value)}
                className="input min-h-[80px] resize-y"
                rows={3}
              />
            </FieldBlock>
            <div className="flex items-center gap-6 pt-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={form.email_opt_in}
                  onChange={(e) => updateField('email_opt_in', e.target.checked)}
                  className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-sm text-surface-700 dark:text-surface-300">
                  Email opt-in
                </span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={form.sms_opt_in}
                  onChange={(e) => updateField('sms_opt_in', e.target.checked)}
                  className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-sm text-surface-700 dark:text-surface-300">
                  SMS opt-in
                </span>
              </label>
            </div>
          </div>
        </div>
      </div>

      {/* Save */}
      <div className="mt-6 flex justify-end">
        <button
          onClick={handleSave}
          disabled={updateMutation.isPending}
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors shadow-sm disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {updateMutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  );
}

// ==================== Tickets Tab ====================

function TicketsTab({ customerId }: { customerId: number }) {
  const navigate = useNavigate();
  const { data, isLoading } = useQuery({
    queryKey: ['customer-tickets', customerId],
    queryFn: () => customerApi.getTickets(customerId),
  });

  const tickets = data?.data?.data?.tickets || [];

  if (isLoading) {
    return <TabSkeleton />;
  }

  if (tickets.length === 0) {
    return (
      <EmptyTabState
        icon={Ticket}
        title="No tickets"
        description="This customer has no repair tickets yet."
      />
    );
  }

  // Sort by created_at descending (newest first)
  const sorted = [...tickets].sort((a: any, b: any) =>
    new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  return (
    <div className="card p-6">
      <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-4 flex items-center gap-2">
        <Ticket className="h-4 w-4" />
        Repair History
      </h3>
      <div className="relative">
        {/* Vertical timeline line */}
        <div className="absolute left-[9px] top-2 bottom-2 w-0.5 bg-surface-200 dark:bg-surface-700" />

        <div className="space-y-0">
          {sorted.map((ticket: any, idx: number) => {
            const statusColor = ticket.status?.color || '#6b7280';
            const deviceName = ticket.devices?.[0]?.device_name || 'Unknown device';
            const serviceName = ticket.devices?.[0]?.service_name || ticket.devices?.[0]?.issue || '';
            const isLast = idx === sorted.length - 1;

            return (
              <div
                key={ticket.id}
                className="relative flex gap-4 group cursor-pointer"
                onClick={() => navigate(`/tickets/${ticket.id}`)}
              >
                {/* Timeline dot */}
                <div className="relative z-10 flex-shrink-0 mt-3">
                  <div
                    className="h-[18px] w-[18px] rounded-full border-[3px] border-white dark:border-surface-900 group-hover:scale-110 transition-transform"
                    style={{ backgroundColor: statusColor }}
                  />
                </div>

                {/* Content card */}
                <div className={cn(
                  'flex-1 rounded-lg p-3 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors',
                  !isLast && 'mb-1',
                )}>
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-mono font-medium text-surface-700 dark:text-surface-300">
                          T-{String(ticket.order_id || ticket.id).replace('T-', '')}
                        </span>
                        <StatusBadge
                          label={ticket.status?.name || 'Unknown'}
                          color={ticket.status?.color}
                        />
                      </div>
                      <p className="text-sm text-surface-800 dark:text-surface-200 mt-0.5">
                        {deviceName}
                      </p>
                      {serviceName && (
                        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5 truncate">
                          {serviceName}
                        </p>
                      )}
                    </div>
                    <div className="text-right flex-shrink-0">
                      <span className="text-sm font-medium text-surface-700 dark:text-surface-300">
                        ${Number(ticket.total || 0).toFixed(2)}
                      </span>
                      <p className="text-xs text-surface-400 dark:text-surface-500 mt-0.5">
                        {new Date(ticket.created_at).toLocaleDateString('en-US', {
                          month: 'short',
                          day: 'numeric',
                          year: 'numeric',
                        })}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ==================== Invoices Tab ====================

function InvoicesTab({ customerId }: { customerId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-invoices', customerId],
    queryFn: () => customerApi.getInvoices(customerId),
  });

  const invoices = data?.data?.data?.invoices || [];

  if (isLoading) {
    return <TabSkeleton />;
  }

  if (invoices.length === 0) {
    return (
      <EmptyTabState
        icon={FileText}
        title="No invoices"
        description="This customer has no invoices yet."
      />
    );
  }

  const statusColors: Record<string, string> = {
    paid: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    unpaid:
      'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
    partial:
      'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
    refunded:
      'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
    void: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
  };

  return (
    <div className="card overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">ID</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Status</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Total</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Paid</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
            {invoices.map((inv: any) => (
              <tr
                key={inv.id}
                className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
              >
                <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                  #{inv.order_id || inv.id}
                </td>
                <td className="px-4 py-3 text-sm">
                  <span
                    className={cn(
                      'badge',
                      statusColors[inv.status] || statusColors.unpaid,
                    )}
                  >
                    {inv.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-sm text-right font-medium text-surface-700 dark:text-surface-300">
                  ${Number(inv.total || 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-400">
                  ${Number(inv.amount_paid || 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">
                  {new Date(inv.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ==================== Communications Tab ====================

function CommunicationsTab({ customerId }: { customerId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-communications', customerId],
    queryFn: () => customerApi.getCommunications(customerId),
    enabled: !!customerId,
  });
  const communications: any[] = data?.data?.data?.communications || [];

  if (isLoading) {
    return <div className="flex items-center justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400" /></div>;
  }

  if (communications.length === 0) {
    return <EmptyTabState icon={MessageSquare} title="No Communications" description="No SMS, calls, or emails found for this customer." />;
  }

  const typeLabel: Record<string, string> = { sms: 'SMS', call: 'Call', email: 'Email' };

  return (
    <div className="space-y-2 max-h-96 overflow-y-auto">
      {communications.map((msg: any, i: number) => (
        <div key={msg.id || i} className={cn('flex', msg.direction === 'outbound' ? 'justify-end' : 'justify-start')}>
          <div className={cn(
            'max-w-[75%] rounded-lg px-3 py-2 text-sm',
            msg.direction === 'outbound'
              ? 'bg-primary-600 text-white rounded-br-none'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-900 dark:text-surface-100 rounded-bl-none'
          )}>
            {msg.comm_type && msg.comm_type !== 'sms' && (
              <p className={cn('text-[10px] font-semibold mb-0.5', msg.direction === 'outbound' ? 'text-primary-200' : 'text-surface-400')}>
                {typeLabel[msg.comm_type] ?? msg.comm_type}
                {msg.subject ? ` · ${msg.subject}` : ''}
              </p>
            )}
            <p>{msg.content ?? msg.message ?? ''}</p>
            <p className={cn('text-[10px] mt-1', msg.direction === 'outbound' ? 'text-primary-200' : 'text-surface-400')}>
              {msg.created_at ? formatShortDateTime(msg.created_at) : ''}
            </p>
          </div>
        </div>
      ))}
    </div>
  );
}

// ==================== Assets Tab ====================

function AssetsTab({ customerId }: { customerId: number }) {
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editingAsset, setEditingAsset] = useState<CustomerAsset | null>(null);
  const [assetForm, setAssetForm] = useState({
    name: '',
    device_type: '',
    serial: '',
    imei: '',
    color: '',
    notes: '',
  });

  const { data, isLoading } = useQuery({
    queryKey: ['customer-assets', customerId],
    queryFn: () => customerApi.getAssets(customerId),
  });

  const assets: CustomerAsset[] = (() => {
    const d = data?.data?.data;
    return Array.isArray(d) ? d : d?.assets || [];
  })();

  const addMutation = useMutation({
    mutationFn: (assetData: Partial<CustomerAsset>) =>
      customerApi.addAsset(customerId, assetData),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset added');
      resetForm();
    },
    onError: () => toast.error('Failed to add asset'),
  });

  const updateAssetMutation = useMutation({
    mutationFn: ({
      assetId,
      data,
    }: {
      assetId: number;
      data: Partial<CustomerAsset>;
    }) => customerApi.updateAsset(assetId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset updated');
      resetForm();
    },
    onError: () => toast.error('Failed to update asset'),
  });

  const deleteAssetMutation = useMutation({
    mutationFn: (assetId: number) => customerApi.deleteAsset(assetId),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset deleted');
    },
    onError: () => toast.error('Failed to delete asset'),
  });

  const resetForm = () => {
    setShowForm(false);
    setEditingAsset(null);
    setAssetForm({
      name: '',
      device_type: '',
      serial: '',
      imei: '',
      color: '',
      notes: '',
    });
  };

  const startEdit = (asset: CustomerAsset) => {
    setEditingAsset(asset);
    setAssetForm({
      name: asset.name || '',
      device_type: asset.device_type || '',
      serial: asset.serial || '',
      imei: asset.imei || '',
      color: asset.color || '',
      notes: asset.notes || '',
    });
    setShowForm(true);
  };

  const handleSubmitAsset = () => {
    if (!assetForm.name.trim()) {
      toast.error('Asset name is required');
      return;
    }

    const payload: Partial<CustomerAsset> = {
      name: assetForm.name.trim(),
      device_type: assetForm.device_type.trim() || null,
      serial: assetForm.serial.trim() || null,
      imei: assetForm.imei.trim() || null,
      color: assetForm.color.trim() || null,
      notes: assetForm.notes.trim() || null,
    };

    if (editingAsset) {
      updateAssetMutation.mutate({ assetId: editingAsset.id, data: payload });
    } else {
      addMutation.mutate(payload);
    }
  };

  const handleDeleteAsset = async (asset: CustomerAsset) => {
    if (
      await confirm(
        `Delete asset "${asset.name}"? This action cannot be undone.`,
        { danger: true },
      )
    ) {
      deleteAssetMutation.mutate(asset.id);
    }
  };

  if (isLoading) {
    return <TabSkeleton />;
  }

  return (
    <div>
      {/* Add button */}
      <div className="flex justify-end mb-4">
        <button
          onClick={() => {
            resetForm();
            setShowForm(true);
          }}
          className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors shadow-sm"
        >
          <Plus className="h-4 w-4" />
          Add Asset
        </button>
      </div>

      {/* Inline Form */}
      {showForm && (
        <div className="card p-4 mb-4">
          <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">
            {editingAsset ? 'Edit Asset' : 'New Asset'}
          </h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Name <span className="text-red-500">*</span>
              </label>
              <input
                type="text"
                value={assetForm.name}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, name: e.target.value }))
                }
                className="input"
                placeholder="iPhone 15 Pro"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Type
              </label>
              <input
                type="text"
                value={assetForm.device_type}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, device_type: e.target.value }))
                }
                className="input"
                placeholder="Phone, Laptop, etc."
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Serial
              </label>
              <input
                type="text"
                value={assetForm.serial}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, serial: e.target.value }))
                }
                className="input"
                placeholder="Serial number"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                IMEI
              </label>
              <input
                type="text"
                value={assetForm.imei}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, imei: e.target.value }))
                }
                className="input"
                placeholder="IMEI number"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Color
              </label>
              <input
                type="text"
                value={assetForm.color}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, color: e.target.value }))
                }
                className="input"
                placeholder="Black, Silver, etc."
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Notes
              </label>
              <input
                type="text"
                value={assetForm.notes}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, notes: e.target.value }))
                }
                className="input"
                placeholder="Additional notes"
              />
            </div>
          </div>
          <div className="flex items-center justify-end gap-2 mt-3">
            <button
              onClick={resetForm}
              className="px-3 py-1.5 text-sm text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800 rounded-md transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmitAsset}
              disabled={addMutation.isPending || updateAssetMutation.isPending}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-md transition-colors disabled:opacity-60"
            >
              {(addMutation.isPending || updateAssetMutation.isPending) && (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              )}
              {editingAsset ? 'Update' : 'Add'}
            </button>
          </div>
        </div>
      )}

      {/* Assets table */}
      {assets.length === 0 && !showForm ? (
        <EmptyTabState
          icon={Monitor}
          title="No assets"
          description="No devices or assets registered for this customer."
        />
      ) : assets.length > 0 ? (
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-surface-200 dark:border-surface-700">
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Type</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Serial</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">IMEI</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Color</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Notes</th>
                  <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {assets.map((asset) => (
                  <tr
                    key={asset.id}
                    className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
                  >
                    <td className="px-4 py-3 text-sm font-medium text-surface-900 dark:text-surface-100">
                      {asset.name}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-600 dark:text-surface-400">
                      {asset.device_type || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                      {asset.serial || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                      {asset.imei || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-600 dark:text-surface-400">
                      {asset.color || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400 max-w-[200px] truncate">
                      {asset.notes || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-right">
                      <div className="flex items-center justify-end gap-1">
                        <button
                          onClick={() => startEdit(asset)}
                          className="p-1.5 rounded-md text-surface-400 hover:text-amber-600 hover:bg-amber-50 dark:hover:text-amber-400 dark:hover:bg-amber-900/20 transition-colors"
                          title="Edit"
                        >
                          <Pencil className="h-4 w-4" />
                        </button>
                        <button
                          onClick={() => handleDeleteAsset(asset)}
                          className="p-1.5 rounded-md text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-900/20 transition-colors"
                          title="Delete"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </div>
  );
}

// ==================== Shared Components ====================

function FieldBlock({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  // Auto-generate a unique id, inject it into the first element child so the
  // label's htmlFor points at the real input. Without this, the label and
  // its input were siblings with no programmatic association — screen
  // readers couldn't pair them and clicking the label didn't focus the input.
  const generatedId = React.useId();
  let linkedChildren: React.ReactNode = children;
  if (React.isValidElement(children)) {
    const existingId = (children.props as { id?: string } | undefined)?.id;
    if (!existingId) {
      linkedChildren = React.cloneElement(children as React.ReactElement<{ id?: string }>, { id: generatedId });
    }
  }
  const htmlFor = React.isValidElement(children)
    ? ((children.props as { id?: string } | undefined)?.id ?? generatedId)
    : undefined;
  return (
    <div>
      <label
        htmlFor={htmlFor}
        className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1"
      >
        {label}
        {required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {linkedChildren}
    </div>
  );
}

function StatusBadge({ label, color }: { label: string; color?: string }) {
  return (
    <span
      className="badge"
      style={
        color
          ? {
              backgroundColor: `${color}20`,
              color: color,
            }
          : undefined
      }
    >
      {label}
    </span>
  );
}

function EmptyTabState({
  icon: Icon,
  title,
  description,
}: {
  icon: typeof User;
  title: string;
  description: string;
}) {
  return (
    <div className="card flex flex-col items-center justify-center py-16">
      <Icon className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-3" />
      <h3 className="text-base font-medium text-surface-600 dark:text-surface-400">
        {title}
      </h3>
      <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
        {description}
      </p>
    </div>
  );
}

function TabSkeleton() {
  return (
    <div className="card p-6 animate-pulse">
      <div className="space-y-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="flex gap-4">
            <div className="h-4 w-16 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-24 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" />
          </div>
        ))}
      </div>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div className="animate-pulse">
      <div className="mb-6 flex items-center gap-4">
        <div className="h-10 w-10 rounded-lg bg-surface-200 dark:bg-surface-700" />
        <div>
          <div className="h-7 w-48 rounded bg-surface-200 dark:bg-surface-700 mb-2" />
          <div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" />
        </div>
      </div>
      <div className="flex gap-4 mb-6 border-b border-surface-200 dark:border-surface-700 pb-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="h-5 w-20 rounded bg-surface-200 dark:bg-surface-700"
          />
        ))}
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="card p-6">
            <div className="h-5 w-32 rounded bg-surface-200 dark:bg-surface-700 mb-4" />
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, j) => (
                <div key={j} className="h-9 rounded bg-surface-100 dark:bg-surface-700/50" />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
