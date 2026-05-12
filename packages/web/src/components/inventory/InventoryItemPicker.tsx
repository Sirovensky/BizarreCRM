import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Loader2, Search, X } from 'lucide-react';
import { inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

export interface InventoryItemPickerItem {
  id: number;
  name: string;
  sku?: string | null;
  in_stock?: number | null;
  item_type?: string | null;
}

interface InventoryItemPickerProps {
  value: number | null;
  onChange: (item: InventoryItemPickerItem | null) => void;
  id?: string;
  label?: string;
  ariaLabel?: string;
  placeholder?: string;
  helperText?: string;
  itemType?: string;
  disabled?: boolean;
  required?: boolean;
  className?: string;
}

const describeItem = (item: InventoryItemPickerItem) => {
  const sku = item.sku ? ` (${item.sku})` : '';
  return `${item.name}${sku}`;
};

export function InventoryItemPicker({
  value,
  onChange,
  id,
  label,
  ariaLabel,
  placeholder = 'Search inventory by name or SKU...',
  helperText,
  itemType,
  disabled,
  required,
  className,
}: InventoryItemPickerProps) {
  const generatedId = useId();
  const inputId = id || generatedId;
  const helpId = `${inputId}-help`;
  const listboxId = `${inputId}-results`;
  const wrapperRef = useRef<HTMLDivElement>(null);
  const selectedId = typeof value === 'number' && value > 0 ? value : null;
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [open, setOpen] = useState(false);

  useEffect(() => {
    const handle = window.setTimeout(() => setDebouncedQuery(query.trim()), 250);
    return () => window.clearTimeout(handle);
  }, [query]);

  const { data: selectedItem } = useQuery({
    queryKey: ['inventory-item-picker', 'selected', selectedId],
    queryFn: async () => {
      const res = await inventoryApi.get(selectedId as number);
      return res.data?.data?.item as InventoryItemPickerItem;
    },
    enabled: !!selectedId,
    staleTime: 60_000,
  });

  const { data: results = [], isFetching } = useQuery({
    queryKey: ['inventory-item-picker', 'search', itemType || 'all', debouncedQuery],
    queryFn: async () => {
      const res = await inventoryApi.list({
        keyword: debouncedQuery,
        pagesize: 10,
        ...(itemType ? { item_type: itemType } : {}),
      });
      const data = res.data?.data;
      return (data?.items || data || []) as InventoryItemPickerItem[];
    },
    enabled: open && debouncedQuery.length >= 2,
    staleTime: 15_000,
  });

  useEffect(() => {
    if (!selectedId) {
      if (!open) setQuery('');
      return;
    }
    if (selectedItem && !open) setQuery(describeItem(selectedItem));
  }, [open, selectedId, selectedItem]);

  useEffect(() => {
    const handlePointerDown = (event: PointerEvent) => {
      if (wrapperRef.current && !wrapperRef.current.contains(event.target as Node)) setOpen(false);
    };
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') setOpen(false);
    };
    document.addEventListener('pointerdown', handlePointerDown);
    document.addEventListener('keydown', handleKeyDown);
    return () => {
      document.removeEventListener('pointerdown', handlePointerDown);
      document.removeEventListener('keydown', handleKeyDown);
    };
  }, []);

  const statusText = useMemo(() => {
    if (!open) return '';
    if (debouncedQuery.length < 2) return 'Type at least 2 characters to search.';
    if (isFetching) return 'Searching inventory...';
    if (results.length === 0) return 'No matching inventory items.';
    return `${results.length} inventory item${results.length === 1 ? '' : 's'} found.`;
  }, [debouncedQuery.length, isFetching, open, results.length]);

  const selectItem = (item: InventoryItemPickerItem) => {
    onChange(item);
    setQuery(describeItem(item));
    setOpen(false);
  };

  const clearSelection = () => {
    onChange(null);
    setQuery('');
    setOpen(false);
  };

  return (
    <div ref={wrapperRef} className={cn('relative', className)}>
      {label && (
        <label htmlFor={inputId} className="mb-1 block text-xs font-medium text-surface-500 dark:text-surface-400">
          {label} {required && <span className="text-red-500">*</span>}
        </label>
      )}
      <div className="relative">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
        <input
          id={inputId}
          value={query}
          onChange={(event) => {
            setQuery(event.target.value);
            setOpen(true);
            if (selectedId) onChange(null);
          }}
          onFocus={() => setOpen(true)}
          placeholder={placeholder}
          disabled={disabled}
          required={required}
          aria-label={label ? undefined : ariaLabel || placeholder}
          aria-expanded={open}
          aria-controls={listboxId}
          aria-autocomplete="list"
          aria-describedby={helperText ? helpId : undefined}
          className="w-full rounded-md border border-surface-300 bg-white py-2 pl-9 pr-9 text-sm text-surface-900 placeholder:text-surface-400 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
        />
        {isFetching && (
          <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />
        )}
        {!isFetching && selectedId && (
          <button
            type="button"
            onClick={clearSelection}
            aria-label="Clear selected inventory item"
            className="absolute right-2 top-1/2 rounded p-1 text-surface-400 hover:text-red-500 -translate-y-1/2"
          >
            <X className="h-4 w-4" />
          </button>
        )}
      </div>
      {helperText && (
        <p id={helpId} className="mt-1 text-xs text-surface-500 dark:text-surface-400">
          {helperText}
        </p>
      )}
      <p className="sr-only" aria-live="polite">{statusText}</p>
      {open && (
        <div
          id={listboxId}
          role="listbox"
          className="absolute z-30 mt-1 max-h-60 w-full overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800"
        >
          {debouncedQuery.length < 2 && (
            <div className="px-3 py-2 text-sm text-surface-500 dark:text-surface-400">
              Type at least 2 characters to search inventory.
            </div>
          )}
          {debouncedQuery.length >= 2 && !isFetching && results.length === 0 && (
            <div className="px-3 py-2 text-sm text-surface-500 dark:text-surface-400">
              No matching inventory items.
            </div>
          )}
          {results.map((item) => (
            <button
              key={item.id}
              type="button"
              role="option"
              aria-selected={item.id === selectedId}
              onClick={() => selectItem(item)}
              className={cn(
                'flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700/60',
                item.id === selectedId && 'bg-primary-50 dark:bg-primary-900/30',
              )}
            >
              <span className="min-w-0">
                <span className="block truncate font-medium text-surface-900 dark:text-surface-100">{item.name}</span>
                <span className="block truncate text-xs text-surface-500 dark:text-surface-400">
                  {item.sku || `Item #${item.id}`}
                </span>
              </span>
              {typeof item.in_stock === 'number' && (
                <span className="shrink-0 text-xs text-surface-500 dark:text-surface-400">
                  Stock: {item.in_stock}
                </span>
              )}
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
