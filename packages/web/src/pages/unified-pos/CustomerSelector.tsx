import { useState, useEffect, useRef } from 'react';
import { Search, X, User, Users, UserPlus, UserX } from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';
import { stripPhone } from '@/utils/phoneFormat';
import { useDefaultTaxRate } from '@/hooks/useDefaultTaxRate';
import { computePosTotals } from './totals';
import { useUnifiedPosStore } from './store';
import type { CustomerResult } from './types';

// Walk-in sentinel: loaded from backend (customers.code = 'WALK-IN').
// We cache it in module scope so we only fetch once per page load.
let walkinCustomerCache: CustomerResult | null = null;

async function fetchOrCreateWalkinCustomer(): Promise<CustomerResult | null> {
  if (walkinCustomerCache) return walkinCustomerCache;
  try {
    const res = await customerApi.search('WALK-IN');
    const data = res.data?.data;
    const list: CustomerResult[] = Array.isArray(data)
      ? data
      : Array.isArray((data as { customers?: CustomerResult[] })?.customers)
        ? (data as { customers: CustomerResult[] }).customers
        : [];
    // ONLY accept a customer that explicitly looks like the walk-in record.
    // Previous fallback (`list[0]`) could silently attach a real customer to
    // a "walk-in" sale when the search returned no walk-in row.
    const match = list.find(
      (c) =>
        (c.first_name + ' ' + c.last_name).toLowerCase().includes('walk') ||
        c.email?.toLowerCase().includes('walk-in') ||
        false,
    );
    if (match) {
      walkinCustomerCache = match;
      return match;
    }
    return null;
  } catch {
    return null;
  }
}

interface CustomerSelectorProps {
  /** Called when user clicks "New Customer". If omitted the button is hidden. */
  onNewCustomer?: () => void;
  /** When true, renders in compact inline mode for LeftPanel embedding */
  inline?: boolean;
}

export function CustomerSelector({ onNewCustomer, inline = false }: CustomerSelectorProps = {}) {
  const { customer, setCustomer, setMemberDiscountApplied, cartItems, discount, memberDiscountApplied } = useUnifiedPosStore();
  const taxRate = useDefaultTaxRate();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<CustomerResult[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const [walkInLoading, setWalkInLoading] = useState(false);
  const [searchError, setSearchError] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  const RESULT_CAP = 25;

  // Debounced search
  useEffect(() => {
    if (query.length < 2) {
      setResults([]);
      setSearchError(false);
      return;
    }
    setLoading(true);
    setSearchError(false);
    // Normalize mostly-digit queries (phone numbers) by stripping non-digit chars
    // so the server's fuzzy phone match works regardless of dashes/spaces/parens.
    const normalizedQuery = /^\d[\d\s\-().]{2,}$/.test(query) ? stripPhone(query) : query;
    // BUGHUNT-2026-05-17: stale-result race. The debounce timer is canceled on
    // re-keystroke, but once the fetch is in flight there was no abort/ignore
    // gate. If a slower in-flight request resolves AFTER a newer one, the
    // cashier sees results that don't match the current query — selecting one
    // would attach the wrong customer to the cart. Use a per-effect `cancelled`
    // flag so only the most recent fetch can call setResults/setLoading.
    let cancelled = false;
    const timer = setTimeout(async () => {
      try {
        const res = await customerApi.search(normalizedQuery);
        if (cancelled) return;
        const data = res.data?.data;
        setResults(Array.isArray(data) ? data.slice(0, RESULT_CAP) : []);
      } catch {
        if (cancelled) return;
        // Distinguish a network/server failure from a genuine zero-hit
        // search: previously both rendered "No customers found" so the
        // cashier had no signal that the lookup actually broke.
        setResults([]);
        setSearchError(true);
      } finally {
        if (!cancelled) setLoading(false);
      }
    }, 150);
    return () => {
      cancelled = true;
      clearTimeout(timer);
    };
  }, [query]);

  // Close dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setIsOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // WEB-UIUX-897: refresh the in-cart customer's group_discount_pct +
  // group_auto_apply from the server periodically so an admin tier change
  // mid-cart actually flows into the live cart (totals, member-discount
  // toggle). Without this poll the cart object is a snapshot from the moment
  // the customer was selected — totals stay stale until the operator
  // re-selects them. We skip the synthetic walk-in (id=0) since that row
  // isn't a real customer record.
  useEffect(() => {
    if (!customer || !customer.id) return;
    let cancelled = false;
    async function refresh() {
      if (!customer || !customer.id) return;
      try {
        const res = await customerApi.get(customer.id);
        if (cancelled) return;
        const fresh = (res?.data as { data?: Partial<CustomerResult> })?.data;
        if (!fresh) return;
        const groupChanged =
          fresh.group_discount_pct !== customer.group_discount_pct ||
          fresh.group_auto_apply !== customer.group_auto_apply ||
          fresh.group_name !== customer.group_name ||
          fresh.group_discount_type !== customer.group_discount_type;
        if (groupChanged) {
          // Merge fresh fields into the existing cart customer rather than
          // replacing wholesale — keeps any non-server-side fields (e.g. the
          // walk-in synthetic flag, locally-attached notes) intact.
          setCustomer({ ...customer, ...fresh } as CustomerResult);
        }
      } catch {
        // Network blip — leave the cached customer; next tick will retry.
      }
    }
    // Refresh once immediately on selection in case the snapshot from search
    // is older than the most recent admin edit, then again on a 30s cadence
    // and on tab refocus (operator returns from another tab/window).
    refresh();
    const interval = setInterval(refresh, 30_000);
    function onVisible() {
      if (document.visibilityState === 'visible') refresh();
    }
    document.addEventListener('visibilitychange', onVisible);
    return () => {
      cancelled = true;
      clearInterval(interval);
      document.removeEventListener('visibilitychange', onVisible);
    };
  }, [customer?.id]); // eslint-disable-line react-hooks/exhaustive-deps

  // Auto-apply member discount when customer changes; toast when discount flips on.
  useEffect(() => {
    if (
      customer &&
      customer.group_auto_apply &&
      customer.group_discount_pct &&
      customer.group_discount_pct > 0
    ) {
      if (!memberDiscountApplied) {
        const oldTotal = computePosTotals({
          cartItems,
          discount,
          customer,
          memberDiscountApplied: false,
          taxRate,
        }).total;
        const newTotal = computePosTotals({
          cartItems,
          discount,
          customer,
          memberDiscountApplied: true,
          taxRate,
        }).total;
        toast.success(`Group discount applied: ${formatCurrency(oldTotal)} → ${formatCurrency(newTotal)}`);
      }
      setMemberDiscountApplied(true);
    } else {
      setMemberDiscountApplied(false);
    }
  }, [customer, setMemberDiscountApplied, cartItems, discount, taxRate, memberDiscountApplied]);

  const selectCustomer = (c: CustomerResult) => {
    setCustomer(c);
    setQuery('');
    setResults([]);
    setIsOpen(false);
    // Advance the ticket tutorial when a customer is selected.
    window.dispatchEvent(new CustomEvent('pos:customer-selected'));
  };

  const clearCustomer = () => {
    setCustomer(null);
    setMemberDiscountApplied(false);
    setQuery('');
  };

  const handleWalkIn = async () => {
    setWalkInLoading(true);
    try {
      const walkin = await fetchOrCreateWalkinCustomer();
      if (walkin) {
        selectCustomer(walkin);
      } else {
        // Fallback synthetic walk-in if backend has no WALK-IN row yet
        const synthetic: CustomerResult = {
          id: 0,
          first_name: 'Walk-in',
          last_name: 'Customer',
          phone: null,
          mobile: null,
          email: null,
          organization: null,
        };
        selectCustomer(synthetic);
      }
    } finally {
      setWalkInLoading(false);
    }
  };

  const displayPhone = (c: CustomerResult): string =>
    c.mobile || c.phone || '';

  // Selected customer card
  if (customer) {
    return (
      <div className="flex items-center gap-3 rounded-lg border border-primary-200 dark:border-primary-800 bg-primary-50 dark:bg-primary-900/20 px-3 py-2">
        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary-100 dark:bg-primary-800">
          <User className="h-4 w-4 text-primary-600 dark:text-primary-400" />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <span className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
              {customer.first_name} {customer.last_name}
            </span>
            {customer.group_name && (
              <span className="inline-flex items-center gap-1 rounded-full bg-amber-100 dark:bg-amber-900/30 px-2 py-0.5 text-[10px] font-semibold uppercase text-amber-700 dark:text-amber-400">
                <Users className="h-3 w-3" />
                {customer.group_name}
              </span>
            )}
          </div>
          {displayPhone(customer) && (
            <p className="truncate text-xs text-surface-500 dark:text-surface-400">
              {displayPhone(customer)}
            </p>
          )}
        </div>
        <button
          onClick={clearCustomer}
          className="btn-icon btn-xs shrink-0 hover:bg-surface-200 hover:text-surface-600 dark:hover:bg-surface-700 dark:hover:text-surface-300"
          title="Remove customer"
          aria-label="Remove customer"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // Search input + dropdown + action buttons
  return (
    <div ref={wrapperRef} className={cn('flex flex-col gap-2', inline ? '' : 'relative')} data-tutorial-target="ticket:customer-picker">
      {/* Search input */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
        <input
          type="search"
          value={query}
          onChange={(e) => { setQuery(e.target.value); setIsOpen(true); }}
          onFocus={() => { if (results.length) setIsOpen(true); }}
          autoFocus={!inline}
          autoCapitalize="off"
          autoCorrect="off"
          spellCheck={false}
          placeholder="Search by name, phone, or email…"
          aria-label="Search customers by name, phone, or email"
          className={cn(
            'w-full rounded-lg border border-surface-200 dark:border-surface-700',
            'bg-white dark:bg-surface-800 pl-9 pr-3 py-2 text-sm',
            'text-surface-900 dark:text-surface-100 placeholder:text-surface-400',
            'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-primary-500',
            'transition-colors',
          )}
        />
        {loading && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-surface-300 border-t-primary-500" />
          </div>
        )}
      </div>

      {/* Search dropdown results */}
      {isOpen && results.length > 0 && (
        <ul className={cn(
          'z-30 w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg max-h-60 overflow-auto',
          inline ? 'relative' : 'absolute mt-1',
        )}>
          {results.map((c) => (
            <li key={c.id}>
              <button
                onClick={() => selectCustomer(c)}
                className="btn btn-md !h-auto w-full !justify-start !gap-3 !px-3 !py-2 text-left !whitespace-normal hover:bg-surface-50 dark:hover:bg-surface-700/50"
              >
                <div className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-surface-100 dark:bg-surface-700">
                  <User className="h-3.5 w-3.5 text-surface-500" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
                    {c.first_name} {c.last_name}
                    {c.organization && (
                      <span className="ml-1 text-xs text-surface-400">({c.organization})</span>
                    )}
                  </p>
                  <p className="truncate text-xs text-surface-500 dark:text-surface-400">
                    {displayPhone(c)}
                    {c.email && <span className="ml-2">{c.email}</span>}
                  </p>
                </div>
                {c.group_name && (
                  <span className="shrink-0 rounded bg-amber-100 dark:bg-amber-900/30 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700 dark:text-amber-400">
                    {c.group_name}
                    {typeof c.group_discount_pct === 'number' && c.group_discount_pct > 0 && (
                      <span className="ml-1 opacity-80">· {c.group_discount_pct}%</span>
                    )}
                  </span>
                )}
              </button>
            </li>
          ))}
          {results.length >= RESULT_CAP && (
            <li className="px-3 py-1.5 text-center text-[11px] text-surface-400 dark:text-surface-500 border-t border-surface-100 dark:border-surface-700">
              Showing first {RESULT_CAP} — refine search
            </li>
          )}
        </ul>
      )}

      {isOpen && query.length >= 2 && results.length === 0 && !loading && (
        <div className={cn(
          'z-30 w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg p-3',
          inline ? 'relative' : 'absolute mt-1',
        )}>
          {searchError ? (
            <p className="text-center text-sm text-rose-600 dark:text-rose-400">
              Search failed — check connection and try again
            </p>
          ) : (
            <p className="text-center text-sm text-surface-500">
              No customers match &ldquo;{query}&rdquo;
            </p>
          )}
          {!searchError && (
            <div className="mt-2 flex flex-col gap-1.5">
              {onNewCustomer && (
                <button
                  type="button"
                  onClick={onNewCustomer}
                  className="btn btn-sm w-full bg-primary-600 !font-semibold text-on-primary hover:bg-primary-700"
                >
                  <UserPlus className="h-3.5 w-3.5" />
                  Create &ldquo;{query.trim()}&rdquo;
                </button>
              )}
              <button
                type="button"
                onClick={handleWalkIn}
                disabled={walkInLoading}
                className="btn btn-sm w-full border border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800/60 disabled:opacity-50"
              >
                <UserX className="h-3.5 w-3.5" />
                {walkInLoading ? 'Loading…' : 'Walk-in · no profile'}
              </button>
            </div>
          )}
        </div>
      )}

      {/* Action buttons: New Customer (primary) + Walk-in (ghost) */}
      <div className="flex flex-col gap-1.5">
        {onNewCustomer && (
          <button
            type="button"
            onClick={onNewCustomer}
            className="btn btn-md w-full bg-primary-600 !font-semibold text-on-primary hover:bg-primary-700 active:bg-primary-800"
          >
            <UserPlus className="h-4 w-4" />
            New Customer
          </button>
        )}
        <button
          type="button"
          onClick={handleWalkIn}
          disabled={walkInLoading}
          className="btn btn-sm w-full border border-transparent text-surface-500 hover:border-surface-200 hover:bg-surface-50 hover:text-surface-700 dark:text-surface-400 dark:hover:border-surface-700 dark:hover:bg-surface-800/60 dark:hover:text-surface-300 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
        >
          <UserX className="h-4 w-4" />
          {walkInLoading ? 'Loading…' : 'Walk-in · no profile'}
        </button>
      </div>
    </div>
  );
}
