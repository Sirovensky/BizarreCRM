import { useState, useEffect, useRef, useCallback } from 'react';
import { useSearchParams, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Search, Plus, ClipboardList, ChevronLeft, ChevronRight, Trash2,
  ArrowRightLeft, Send, Eye, X, Loader2, ChevronDown, AlertTriangle, Clock,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { estimateApi, customerApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';

// ─── Status config ───────────────────────────────────────────────
const ESTIMATE_STATUSES = [
  { value: '', label: 'All' },
  { value: 'draft', label: 'Draft', color: '#6b7280' },
  { value: 'sent', label: 'Sent', color: '#3b82f6' },
  { value: 'approved', label: 'Approved', color: '#22c55e' },
  { value: 'rejected', label: 'Rejected', color: '#ef4444' },
  { value: 'converted', label: 'Converted', color: '#8b5cf6' },
] as const;

function getStatusConfig(status: string) {
  return ESTIMATE_STATUSES.find((s) => s.value === status) ?? { value: status, label: status, color: '#6b7280' };
}

function StatusBadge({ status }: { status: string }) {
  const cfg = getStatusConfig(status);
  const color = 'color' in cfg ? cfg.color : '#6b7280';
  return (
    <span
      className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
      style={{ backgroundColor: `${color}18`, color }}
    >
      <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
      {cfg.label}
    </span>
  );
}

// ─── Skeleton ────────────────────────────────────────────────────
function SkeletonRow() {
  return (
    <tr className="animate-pulse">
      {Array.from({ length: 7 }).map((_, i) => (
        <td key={i} className="px-4 py-3">
          <div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" />
        </td>
      ))}
    </tr>
  );
}

// ─── Create Estimate Modal ──────────────────────────────────────
function CreateEstimateModal({
  open,
  onClose,
}: {
  open: boolean;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const navigate = useNavigate();
  const [customerSearch, setCustomerSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<any>(null);
  const [showCustomerDropdown, setShowCustomerDropdown] = useState(false);
  const dropdownRef = useRef<HTMLDivElement>(null);

  const [lineItems, setLineItems] = useState([
    { description: '', quantity: 1, unit_price: 0, tax_amount: 0 },
  ]);
  const [notes, setNotes] = useState('');
  const [validUntil, setValidUntil] = useState('');

  // Customer search
  const { data: customerData } = useQuery({
    queryKey: ['customer-search', customerSearch],
    queryFn: () => customerApi.search(customerSearch),
    enabled: customerSearch.length >= 2,
  });
  const customerResults: any[] = customerData?.data?.data || [];

  // Close dropdown on outside click
  useEffect(() => {
    if (!showCustomerDropdown) return;
    function handleClick(e: MouseEvent) {
      if (dropdownRef.current && !dropdownRef.current.contains(e.target as Node)) setShowCustomerDropdown(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [showCustomerDropdown]);

  const createMut = useMutation({
    mutationFn: (data: any) => estimateApi.create(data),
    onSuccess: () => {
      toast.success('Estimate created');
      queryClient.invalidateQueries({ queryKey: ['estimates'] });
      onClose();
      resetForm();
    },
    onError: () => toast.error('Failed to create estimate'),
  });

  function resetForm() {
    setSelectedCustomer(null);
    setCustomerSearch('');
    setLineItems([{ description: '', quantity: 1, unit_price: 0, tax_amount: 0 }]);
    setNotes('');
    setValidUntil('');
  }

  function addLineItem() {
    setLineItems((prev) => [...prev, { description: '', quantity: 1, unit_price: 0, tax_amount: 0 }]);
  }

  function removeLineItem(idx: number) {
    setLineItems((prev) => prev.filter((_, i) => i !== idx));
  }

  function updateLineItem(idx: number, field: string, value: string | number) {
    setLineItems((prev) =>
      prev.map((item, i) => (i === idx ? { ...item, [field]: value } : item)),
    );
  }

  const subtotal = lineItems.reduce((sum, li) => sum + li.quantity * li.unit_price, 0);
  const totalTax = lineItems.reduce((sum, li) => sum + li.tax_amount, 0);
  const total = subtotal + totalTax;

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 overflow-y-auto py-8">
      <div className="w-full max-w-2xl rounded-xl bg-white shadow-2xl dark:bg-surface-800">
        <div className="flex items-center justify-between border-b border-surface-200 px-6 py-4 dark:border-surface-700">
          <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">New Estimate</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5" />
          </button>
        </div>
        <form
          className="space-y-4 px-6 py-4"
          onSubmit={(e) => {
            e.preventDefault();
            if (!selectedCustomer) {
              toast.error('Please select a customer');
              return;
            }
            createMut.mutate({
              customer_id: selectedCustomer.id,
              notes: notes || null,
              valid_until: validUntil || null,
              line_items: lineItems.filter((li) => li.description),
            });
          }}
        >
          {/* Customer picker */}
          <div className="relative" ref={dropdownRef}>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Customer *</label>
            {selectedCustomer ? (
              <div className="flex items-center gap-2 rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 dark:border-surface-700 dark:bg-surface-900">
                <span className="text-sm text-surface-900 dark:text-surface-100">
                  {selectedCustomer.first_name} {selectedCustomer.last_name}
                </span>
                <button
                  type="button"
                  onClick={() => { setSelectedCustomer(null); setCustomerSearch(''); }}
                  className="ml-auto rounded p-0.5 text-surface-400 hover:text-surface-600"
                >
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>
            ) : (
              <input
                value={customerSearch}
                onChange={(e) => {
                  setCustomerSearch(e.target.value);
                  setShowCustomerDropdown(true);
                }}
                onFocus={() => customerSearch.length >= 2 && setShowCustomerDropdown(true)}
                placeholder="Search customers..."
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            )}
            {showCustomerDropdown && customerResults.length > 0 && !selectedCustomer && (
              <div className="absolute left-0 top-full z-10 mt-1 w-full rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                <div className="max-h-48 overflow-y-auto py-1">
                  {customerResults.map((c: any) => (
                    <button
                      key={c.id}
                      type="button"
                      onClick={() => {
                        setSelectedCustomer(c);
                        setShowCustomerDropdown(false);
                      }}
                      className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700"
                    >
                      <span className="font-medium text-surface-900 dark:text-surface-100">{c.first_name} {c.last_name}</span>
                      {c.phone && <span className="text-surface-400 text-xs">{c.phone}</span>}
                    </button>
                  ))}
                </div>
              </div>
            )}
          </div>

          {/* Line items */}
          <div>
            <label className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">Line Items</label>
            <div className="space-y-2">
              {lineItems.map((item, idx) => (
                <div key={idx} className="flex items-start gap-2">
                  <input
                    value={item.description}
                    onChange={(e) => updateLineItem(idx, 'description', e.target.value)}
                    placeholder="Description"
                    className="flex-1 rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                  <input
                    type="number"
                    min="1"
                    value={item.quantity}
                    onChange={(e) => updateLineItem(idx, 'quantity', Number(e.target.value))}
                    className="w-16 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm text-center dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                    placeholder="Qty"
                  />
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={item.unit_price || ''}
                    onChange={(e) => updateLineItem(idx, 'unit_price', Number(e.target.value))}
                    className="w-24 rounded-lg border border-surface-200 bg-surface-50 px-2 py-2 text-sm text-right dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                    placeholder="Price"
                  />
                  {lineItems.length > 1 && (
                    <button
                      type="button"
                      onClick={() => removeLineItem(idx)}
                      className="rounded-lg p-2 text-surface-400 hover:text-red-500"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  )}
                </div>
              ))}
            </div>
            <button
              type="button"
              onClick={addLineItem}
              className="mt-2 inline-flex items-center gap-1 text-sm text-primary-600 hover:text-primary-700 dark:text-primary-400"
            >
              <Plus className="h-3.5 w-3.5" /> Add line item
            </button>
          </div>

          {/* Totals */}
          <div className="rounded-lg bg-surface-50 px-4 py-3 dark:bg-surface-900">
            <div className="flex justify-between text-sm">
              <span className="text-surface-500">Subtotal</span>
              <span className="font-medium text-surface-900 dark:text-surface-100">{formatCurrency(subtotal)}</span>
            </div>
            <div className="mt-1 flex justify-between text-sm">
              <span className="text-surface-500">Tax</span>
              <span className="font-medium text-surface-900 dark:text-surface-100">{formatCurrency(totalTax)}</span>
            </div>
            <div className="mt-2 flex justify-between border-t border-surface-200 pt-2 text-sm dark:border-surface-700">
              <span className="font-medium text-surface-700 dark:text-surface-300">Total</span>
              <span className="text-base font-bold text-surface-900 dark:text-surface-100">{formatCurrency(total)}</span>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Valid Until</label>
              <input
                type="date"
                value={validUntil}
                onChange={(e) => setValidUntil(e.target.value)}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
            <div>
              <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Notes</label>
              <input
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              />
            </div>
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={createMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white shadow-sm hover:bg-primary-700 disabled:opacity-50"
            >
              {createMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Create Estimate
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────
export function EstimateListPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();

  const page = Number(searchParams.get('page') || '1');
  const pageSize = Number(searchParams.get('pagesize') || localStorage.getItem('estimates_pagesize') || '25');
  const keyword = searchParams.get('keyword') || '';
  const statusFilter = searchParams.get('status') || '';

  const [searchInput, setSearchInput] = useState(keyword);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const [showCreate, setShowCreate] = useState(false);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => {
      setSearchParams((prev) => {
        const next = new URLSearchParams(prev);
        if (searchInput) next.set('keyword', searchInput); else next.delete('keyword');
        next.set('page', '1');
        return next;
      });
    }, 400);
    return () => clearTimeout(debounceRef.current);
  }, [searchInput, setSearchParams]);

  // Fetch estimates
  const estimateParams = {
    page,
    pagesize: pageSize,
    ...(keyword ? { keyword } : {}),
    ...(statusFilter ? { status: statusFilter } : {}),
  };

  const { data: estData, isLoading, isFetching } = useQuery({
    queryKey: ['estimates', estimateParams],
    queryFn: () => estimateApi.list(estimateParams),
    placeholderData: (prev: any) => prev,
  });

  const estimates: any[] = estData?.data?.data?.estimates || [];
  const pagination = estData?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1, per_page: 20 };

  // Send mutation
  const sendMut = useMutation({
    mutationFn: (id: number) => estimateApi.send(id),
    onSuccess: () => {
      toast.success('Estimate sent to customer');
      queryClient.invalidateQueries({ queryKey: ['estimates'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to send estimate'),
  });

  // Convert mutation
  const convertMut = useMutation({
    mutationFn: (id: number) => estimateApi.convert(id),
    onSuccess: (res) => {
      const ticketId = res?.data?.data?.ticket?.id;
      toast.success('Estimate converted to ticket');
      queryClient.invalidateQueries({ queryKey: ['estimates'] });
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to convert estimate'),
  });

  // Delete mutation
  const deleteMut = useMutation({
    mutationFn: (id: number) => estimateApi.delete(id),
    onSuccess: () => {
      toast.success('Estimate deleted');
      queryClient.invalidateQueries({ queryKey: ['estimates'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to delete estimate'),
  });

  function setParam(key: string, value: string) {
    setSearchParams((prev) => {
      const next = new URLSearchParams(prev);
      if (value) next.set(key, value); else next.delete(key);
      next.set('page', '1');
      return next;
    });
  }

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Estimates</h1>
          <p className="text-surface-500 dark:text-surface-400">Create and manage repair estimates</p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" />
          New Estimate
        </button>
      </div>

      {/* Status filter pills */}
      <div className="mb-4 flex flex-wrap gap-2">
        {ESTIMATE_STATUSES.map((s) => {
          const color = 'color' in s ? s.color : '#6b7280';
          const isActive = statusFilter === s.value;
          return (
            <button
              key={s.value}
              onClick={() => setParam('status', s.value)}
              className={cn(
                'inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition-all',
                isActive
                  ? 'ring-2 ring-offset-1 ring-offset-white dark:ring-offset-surface-900'
                  : 'hover:opacity-80',
              )}
              style={
                s.value
                  ? { backgroundColor: `${color}18`, color, ...(isActive ? { ringColor: color } : {}) }
                  : isActive
                    ? { backgroundColor: '#6b728018', color: '#6b7280' }
                    : { backgroundColor: '#6b728010', color: '#9ca3af' }
              }
            >
              {s.value && <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />}
              {s.label}
            </button>
          );
        })}
      </div>

      <div className="card relative">
        {/* Search */}
        <div className="flex items-center gap-3 border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <div className="relative flex-1 max-w-sm">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="text"
              value={searchInput}
              onChange={(e) => setSearchInput(e.target.value)}
              placeholder="Search estimates..."
              className="w-full rounded-lg border border-surface-200 bg-surface-50 py-1.5 pl-9 pr-4 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
            />
          </div>
        </div>

        {/* Table */}
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-surface-200 dark:border-surface-700">
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Estimate ID</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Customer</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Status</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400 text-right">Total</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Valid Until</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Created</th>
                <th className="px-4 py-3 font-medium text-surface-500 dark:text-surface-400 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {isLoading ? (
                Array.from({ length: 6 }).map((_, i) => <SkeletonRow key={i} />)
              ) : estimates.length === 0 ? (
                <tr>
                  <td colSpan={7}>
                    <div className="flex flex-col items-center justify-center py-20">
                      <ClipboardList className="mb-4 h-16 w-16 text-surface-300 dark:text-surface-600" />
                      <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">No Estimates</h2>
                      <p className="mt-1 max-w-sm text-center text-sm text-surface-400 dark:text-surface-500">
                        {keyword || statusFilter
                          ? 'No estimates match your filters. Try adjusting your search or status filter.'
                          : 'Create an estimate to give customers a repair quote. Click "New Estimate" above to get started.'}
                      </p>
                    </div>
                  </td>
                </tr>
              ) : (
                estimates.map((est) => {
                  const isExpired = est.valid_until && new Date(est.valid_until) < new Date();
                  return (
                    <tr
                      key={est.id}
                      onClick={() => navigate(`/estimates/${est.id}`)}
                      className="cursor-pointer transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50"
                    >
                      <td className="px-4 py-3 font-medium text-primary-600 dark:text-primary-400">
                        {est.order_id || `EST-${String(est.id).padStart(4, '0')}`}
                      </td>
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">
                        {est.customer_first_name
                          ? `${est.customer_first_name} ${est.customer_last_name}`
                          : '--'}
                      </td>
                      <td className="px-4 py-3">
                        <StatusBadge status={est.status} />
                      </td>
                      <td className="px-4 py-3 text-right font-medium text-surface-800 dark:text-surface-200">
                        {formatCurrency(est.total ?? 0)}
                      </td>
                      <td className="px-4 py-3">
                        {est.valid_until ? (
                          <div className="flex items-center gap-1.5">
                            <span className={cn(
                              'text-sm',
                              isExpired
                                ? 'text-red-500 dark:text-red-400'
                                : est.is_expiring
                                  ? 'text-amber-600 dark:text-amber-400'
                                  : 'text-surface-600 dark:text-surface-400',
                            )}>
                              {formatDate(est.valid_until)}
                            </span>
                            {isExpired && (
                              <span className="inline-flex items-center gap-0.5 rounded-full bg-red-100 px-1.5 py-0.5 text-[10px] font-medium text-red-700 dark:bg-red-950/30 dark:text-red-400">
                                <AlertTriangle className="h-2.5 w-2.5" />
                                Expired
                              </span>
                            )}
                            {!isExpired && est.is_expiring && (
                              <span className="inline-flex items-center gap-0.5 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-medium text-amber-700 dark:bg-amber-950/30 dark:text-amber-400">
                                <Clock className="h-2.5 w-2.5" />
                                {est.days_until_expiry === 0 ? 'Today' : `${est.days_until_expiry}d left`}
                              </span>
                            )}
                          </div>
                        ) : (
                          <span className="text-surface-300 dark:text-surface-600">--</span>
                        )}
                      </td>
                      <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                        {est.created_at ? formatDate(est.created_at) : '--'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex items-center justify-end gap-1">
                          <button
                            onClick={(e) => { e.stopPropagation(); navigate(`/estimates/${est.id}`); }}
                            className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-700 dark:hover:text-surface-200"
                            title="View Estimate"
                          >
                            <Eye className="h-4 w-4" />
                          </button>
                          {(est.status === 'draft' || est.status === 'sent') && (
                            <button
                              onClick={async (e) => {
                                e.stopPropagation();
                                if (await confirm(`Send this estimate to the customer${est.status === 'sent' ? ' again' : ''}?`)) {
                                  sendMut.mutate(est.id);
                                }
                              }}
                              disabled={sendMut.isPending}
                              className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-blue-50 hover:text-blue-600 dark:hover:bg-blue-950/30 dark:hover:text-blue-400"
                              title={est.status === 'sent' ? 'Resend to Customer' : 'Send to Customer'}
                            >
                              <Send className="h-4 w-4" />
                            </button>
                          )}
                          {est.status !== 'converted' && est.status !== 'rejected' && (
                            <button
                              onClick={async (e) => {
                                e.stopPropagation();
                                if (await confirm('Convert this estimate to a ticket?')) {
                                  convertMut.mutate(est.id);
                                }
                              }}
                              disabled={convertMut.isPending}
                              className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-green-50 hover:text-green-600 dark:hover:bg-green-950/30 dark:hover:text-green-400"
                              title="Convert to Ticket"
                            >
                              <ArrowRightLeft className="h-4 w-4" />
                            </button>
                          )}
                          <button
                            onClick={async (e) => {
                              e.stopPropagation();
                              if (await confirm('Delete this estimate?', { danger: true })) {
                                deleteMut.mutate(est.id);
                              }
                            }}
                            disabled={deleteMut.isPending}
                            className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-950/30 dark:hover:text-red-400"
                            title="Delete Estimate"
                          >
                            <Trash2 className="h-4 w-4" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  );
                })
              )}
            </tbody>
          </table>
        </div>

        {/* Pagination */}
          <div className="flex items-center justify-between border-t border-surface-200 px-4 py-3 dark:border-surface-700">
            <div className="flex items-center gap-4">
              <div className="flex items-center gap-1.5">
                <span className="text-xs text-surface-500 dark:text-surface-400">Show</span>
                <select
                  value={pageSize}
                  onChange={(e) => {
                    const v = e.target.value;
                    localStorage.setItem('estimates_pagesize', v);
                    const p = new URLSearchParams(searchParams);
                    p.set('pagesize', v);
                    p.set('page', '1');
                    setSearchParams(p, { replace: true });
                  }}
                  className="text-xs rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-2 py-1 focus:outline-none focus:ring-1 focus:ring-primary-500"
                >
                  {[10, 25, 50, 100, 250].map((n) => (
                    <option key={n} value={n}>{n}</option>
                  ))}
                </select>
                <span className="text-xs text-surface-500 dark:text-surface-400">per page</span>
              </div>
              <p className="text-sm text-surface-500 dark:text-surface-400">
                Showing {(page - 1) * pagination.per_page + 1}
                &ndash;
                {Math.min(page * pagination.per_page, pagination.total)} of {pagination.total}
              </p>
            </div>
            {pagination.total_pages > 1 && (
            <div className="flex items-center gap-1">
              <button
                disabled={page <= 1}
                onClick={() => setParam('page', String(page - 1))}
                className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              {Array.from({ length: Math.min(pagination.total_pages, 7) }, (_, i) => {
                let pageNum: number;
                if (pagination.total_pages <= 7) {
                  pageNum = i + 1;
                } else if (page <= 4) {
                  pageNum = i + 1;
                } else if (page >= pagination.total_pages - 3) {
                  pageNum = pagination.total_pages - 6 + i;
                } else {
                  pageNum = page - 3 + i;
                }
                return (
                  <button
                    key={pageNum}
                    onClick={() => setParam('page', String(pageNum))}
                    className={cn(
                      'h-8 w-8 rounded-lg text-sm font-medium transition-colors',
                      pageNum === page
                        ? 'bg-primary-600 text-white'
                        : 'text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700',
                    )}
                  >
                    {pageNum}
                  </button>
                );
              })}
              <button
                disabled={page >= pagination.total_pages}
                onClick={() => setParam('page', String(page + 1))}
                className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
            )}
          </div>

        {/* Loading overlay */}
        {isFetching && !isLoading && (
          <div className="absolute inset-0 flex items-center justify-center bg-white/40 dark:bg-surface-900/40">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary-200 border-t-primary-600" />
          </div>
        )}
      </div>

      {/* Create modal */}
      <CreateEstimateModal open={showCreate} onClose={() => setShowCreate(false)} />
    </div>
  );
}
