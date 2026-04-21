import { useState, useEffect, useRef } from 'react';
import { Search, X, User, Users } from 'lucide-react';
import { customerApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useUnifiedPosStore } from './store';
import type { CustomerResult } from './types';

export function CustomerSelector() {
  const { customer, setCustomer, setMemberDiscountApplied } = useUnifiedPosStore();
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<CustomerResult[]>([]);
  const [isOpen, setIsOpen] = useState(false);
  const [loading, setLoading] = useState(false);
  const wrapperRef = useRef<HTMLDivElement>(null);

  // Debounced search
  useEffect(() => {
    if (query.length < 2) {
      setResults([]);
      return;
    }
    setLoading(true);
    const timer = setTimeout(async () => {
      try {
        const res = await customerApi.search(query);
        const data = res.data?.data;
        setResults(Array.isArray(data) ? data.slice(0, 8) : []);
      } catch {
        // Search failed — handled by empty results
        setResults([]);
      } finally {
        setLoading(false);
      }
    }, 300);
    return () => clearTimeout(timer);
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

  // Auto-apply member discount when customer changes
  useEffect(() => {
    if (
      customer &&
      customer.group_auto_apply &&
      customer.group_discount_pct &&
      customer.group_discount_pct > 0
    ) {
      setMemberDiscountApplied(true);
    } else {
      setMemberDiscountApplied(false);
    }
  }, [customer, setMemberDiscountApplied]);

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
          className="shrink-0 rounded p-1 text-surface-400 hover:bg-surface-200 hover:text-surface-600 dark:hover:bg-surface-700 dark:hover:text-surface-300 transition-colors"
          title="Remove customer"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  // Search input + dropdown
  return (
    <div ref={wrapperRef} className="relative" data-tutorial-target="ticket:customer-picker">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
        <input
          type="text"
          value={query}
          onChange={(e) => { setQuery(e.target.value); setIsOpen(true); }}
          onFocus={() => { if (results.length) setIsOpen(true); }}
          placeholder="Walk-in Customer — search to assign"
          className={cn(
            'w-full rounded-lg border border-surface-200 dark:border-surface-700',
            'bg-white dark:bg-surface-800 pl-9 pr-3 py-2 text-sm',
            'text-surface-900 dark:text-surface-100 placeholder:text-surface-400',
            'focus:outline-none focus:ring-2 focus:ring-primary-500/30 focus:border-primary-500',
            'transition-colors',
          )}
        />
        {loading && (
          <div className="absolute right-3 top-1/2 -translate-y-1/2">
            <div className="h-4 w-4 animate-spin rounded-full border-2 border-surface-300 border-t-primary-500" />
          </div>
        )}
      </div>

      {isOpen && results.length > 0 && (
        <ul className="absolute z-30 mt-1 w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg max-h-60 overflow-auto">
          {results.map((c) => (
            <li key={c.id}>
              <button
                onClick={() => selectCustomer(c)}
                className="w-full flex items-center gap-3 px-3 py-2 text-left hover:bg-surface-50 dark:hover:bg-surface-700/50 transition-colors"
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
                  </span>
                )}
              </button>
            </li>
          ))}
        </ul>
      )}

      {isOpen && query.length >= 2 && results.length === 0 && !loading && (
        <div className="absolute z-30 mt-1 w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-lg p-3 text-center text-sm text-surface-500">
          No customers found
        </div>
      )}
    </div>
  );
}
