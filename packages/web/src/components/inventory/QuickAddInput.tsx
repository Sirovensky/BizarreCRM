/**
 * Rapid quick-add inventory input.
 *
 * Single text box that accepts "name @ price" syntax and creates an
 * inventory_items row via POST /inventory-enrich/quick-add.
 *
 * Usage: drop this inside any inventory page where the tech wants to spew
 * new parts into stock without opening a 11-field form.
 *
 * Cross-ref: criticalaudit.md §48 idea #13.
 */
import { useState, useRef, useEffect } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Zap, Loader2, Check } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface QuickAddInputProps {
  /** Called after a successful quick add with the inserted row id. */
  onAdded?: (itemId: number, name: string, price: number) => void;
  /** Auto-focus the input on mount. */
  autoFocus?: boolean;
  /** Placeholder override. */
  placeholder?: string;
}

export function QuickAddInput({ onAdded, autoFocus, placeholder }: QuickAddInputProps) {
  const queryClient = useQueryClient();
  const [value, setValue] = useState('');
  const [lastAdded, setLastAdded] = useState<string | null>(null);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    if (autoFocus) inputRef.current?.focus();
  }, [autoFocus]);

  const addMut = useMutation({
    mutationFn: async (input: string) => {
      const res = await api.post<{
        success: boolean;
        data: { id: number; name: string; retail_price: number };
      }>('/inventory-enrich/quick-add', { input });
      return res.data.data;
    },
    onSuccess: (item) => {
      toast.success(`Added "${item.name}"`);
      setLastAdded(item.name);
      setValue('');
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      onAdded?.(item.id, item.name, item.retail_price);
      inputRef.current?.focus();
      setTimeout(() => setLastAdded(null), 2000);
    },
    onError: (e: any) => {
      toast.error(e?.response?.data?.message || 'Failed to add');
    },
  });

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const v = value.trim();
    if (!v) return;
    addMut.mutate(v);
  };

  // Parse preview so the tech sees what they're about to create before pressing Enter.
  const preview = (() => {
    const raw = value.trim();
    if (!raw) return null;
    const atIdx = raw.lastIndexOf('@');
    if (atIdx <= 0) return { name: raw, price: 0 };
    const name = raw.slice(0, atIdx).trim();
    const priceStr = raw.slice(atIdx + 1).trim().replace(/[^0-9.]/g, '');
    const price = parseFloat(priceStr || '0') || 0;
    return { name, price };
  })();

  return (
    <form onSubmit={handleSubmit} className="space-y-2">
      <div className="flex items-center gap-2">
        <div className="flex-1 relative">
          <Zap className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-amber-500" />
          <input
            ref={inputRef}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={placeholder || 'iPhone 14 screen @ 89.99'}
            className="w-full rounded-md border border-surface-300 pl-10 pr-3 py-2 text-sm focus:border-primary-500 focus:ring-1 focus:ring-primary-500"
          />
        </div>
        <button
          type="submit"
          disabled={!value.trim() || addMut.isPending}
          className="inline-flex items-center gap-1 rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700 disabled:opacity-50"
        >
          {addMut.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : lastAdded ? (
            <Check className="h-4 w-4" />
          ) : (
            'Add'
          )}
        </button>
      </div>
      {preview && (
        <div className="text-xs text-surface-500 pl-10">
          Will create: <span className="font-semibold">{preview.name}</span>
          {preview.price > 0 && (
            <>
              {' @ '}
              <span className="font-mono">${preview.price.toFixed(2)}</span>
            </>
          )}
        </div>
      )}
      {lastAdded && (
        <div className="text-xs text-green-600 pl-10 flex items-center gap-1">
          <Check className="h-3 w-3" /> Added "{lastAdded}"
        </div>
      )}
    </form>
  );
}
