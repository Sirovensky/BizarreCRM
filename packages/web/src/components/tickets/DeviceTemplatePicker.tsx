/**
 * DeviceTemplatePicker — audit 44.1 + 44.2 + 44.9.
 *
 * Lets a tech pick a saved repair template ("iPhone 13 screen replacement")
 * and one-click apply it to the current ticket. Shows live stock badges
 * (green / yellow / red) per part — audit 44.2 — and an "order from
 * supplier" hint when a part is red — audit 44.9.
 *
 * The apply action is server-side idempotent: clicking twice appends parts
 * twice. That's deliberate: a tech might need spares. If they make a mistake
 * they can delete the extra row on the ticket.
 */

import { useState, useMemo } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Wand2, Search, Loader2, Check, ShoppingCart } from 'lucide-react';
import toast from 'react-hot-toast';
import { deviceTemplateApi } from '@/api/endpoints';
import { formatCents } from '@/utils/format';

interface DeviceTemplatePickerProps {
  ticketId: number;
  ticketDeviceId?: number;
  suggestedCategory?: string;
  onApplied?: () => void;
}

interface EnrichedPart {
  inventory_item_id: number;
  qty: number;
  name: string;
  sku: string | null;
  in_stock: number;
  retail_price: number;
  stock_badge: 'green' | 'yellow' | 'red';
}

interface DeviceTemplate {
  id: number;
  name: string;
  device_category: string | null;
  device_model: string | null;
  fault: string | null;
  est_labor_minutes: number;
  est_labor_cost: number;
  suggested_price: number;
  warranty_days: number;
  parts: EnrichedPart[];
  diagnostic_checklist: string[];
}

function badgeClass(b: 'green' | 'yellow' | 'red') {
  if (b === 'green') return 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-300';
  if (b === 'yellow') return 'bg-yellow-100 text-yellow-700 dark:bg-yellow-900/40 dark:text-yellow-200';
  return 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-300';
}

export function DeviceTemplatePicker({
  ticketId,
  ticketDeviceId,
  suggestedCategory,
  onApplied,
}: DeviceTemplatePickerProps) {
  const qc = useQueryClient();
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);

  const { data, isLoading } = useQuery({
    queryKey: ['device-templates', suggestedCategory ?? 'all'],
    queryFn: () => deviceTemplateApi.list({ category: suggestedCategory, active: true }),
    enabled: open,
  });
  const templates: DeviceTemplate[] = data?.data?.data ?? [];

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return templates;
    return templates.filter((t) =>
      [t.name, t.device_model, t.fault]
        .filter((v): v is string => !!v)
        .some((v) => v.toLowerCase().includes(q)),
    );
  }, [templates, query]);

  const applyMut = useMutation({
    mutationFn: (templateId: number) =>
      deviceTemplateApi.applyToTicket(templateId, ticketId, ticketDeviceId),
    onSuccess: (res: any) => {
      const inserted = res?.data?.data?.inserted_parts ?? 0;
      toast.success(`Template applied — ${inserted} part(s) added`);
      qc.invalidateQueries({ queryKey: ['ticket', ticketId] });
      onApplied?.();
      setOpen(false);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to apply template';
      toast.error(msg);
    },
  });

  return (
    <div className="card p-4">
      <div className="mb-2 flex items-center justify-between">
        <div className="flex items-center gap-2 text-sm font-semibold text-surface-900 dark:text-surface-100">
          <Wand2 className="h-4 w-4 text-primary-500" />
          Repair Templates
        </div>
        {!open && (
          <button
            onClick={() => setOpen(true)}
            className="rounded-lg bg-primary-600 px-2.5 py-1 text-xs font-semibold text-white hover:bg-primary-700"
          >
            Browse
          </button>
        )}
      </div>

      {!open && (
        <p className="text-xs text-surface-500 dark:text-surface-400">
          Save time: pick a saved job to auto-fill parts, labor, and the diagnostic checklist.
        </p>
      )}

      {open && (
        <>
          <div className="relative mb-2">
            <Search className="absolute left-2.5 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              autoFocus
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="iPhone 13 screen..."
              className="w-full rounded-lg border border-surface-200 bg-surface-50 py-1.5 pl-8 pr-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
            />
          </div>

          <div className="max-h-72 space-y-2 overflow-y-auto">
            {isLoading && (
              <div className="flex justify-center py-4">
                <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
              </div>
            )}
            {!isLoading && filtered.length === 0 && (
              <p className="py-4 text-center text-xs text-surface-400">
                {templates.length === 0
                  ? 'No templates yet — ask an admin to create some in Settings → Device Templates.'
                  : 'No templates match your search.'}
              </p>
            )}
            {filtered.map((t) => {
              const hasRed = t.parts.some((p) => p.stock_badge === 'red');
              return (
                <div
                  key={t.id}
                  className="rounded-lg border border-surface-200 p-2.5 dark:border-surface-700"
                >
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0 flex-1">
                      <div className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
                        {t.name}
                      </div>
                      <div className="flex flex-wrap gap-2 text-[11px] text-surface-500 dark:text-surface-400">
                        {t.est_labor_minutes > 0 && <span>~{t.est_labor_minutes}m labor</span>}
                        {t.suggested_price > 0 && (
                          <span>{formatCents(t.suggested_price)}</span>
                        )}
                        {t.warranty_days > 0 && <span>{t.warranty_days}d warranty</span>}
                      </div>
                    </div>
                    <button
                      onClick={() => applyMut.mutate(t.id)}
                      disabled={applyMut.isPending}
                      className="flex shrink-0 items-center gap-1 rounded-lg bg-primary-600 px-2 py-1 text-[11px] font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
                    >
                      <Check className="h-3 w-3" /> Apply
                    </button>
                  </div>
                  {t.parts.length > 0 && (
                    <div className="mt-2 space-y-1">
                      {t.parts.slice(0, 4).map((p) => (
                        <div
                          key={p.inventory_item_id}
                          className="flex items-center justify-between text-[11px]"
                        >
                          <span className="truncate text-surface-600 dark:text-surface-300">
                            {p.qty}x {p.name}
                          </span>
                          <span className={`rounded-full px-1.5 py-0.5 ${badgeClass(p.stock_badge)}`}>
                            {p.in_stock} in stock
                          </span>
                        </div>
                      ))}
                      {t.parts.length > 4 && (
                        <div className="text-[10px] text-surface-400">
                          +{t.parts.length - 4} more part(s)
                        </div>
                      )}
                      {hasRed && (
                        <div className="mt-1 flex items-center gap-1 text-[11px] text-red-600 dark:text-red-400">
                          <ShoppingCart className="h-3 w-3" />
                          Some parts out of stock — ticket will park at "Awaiting parts"
                        </div>
                      )}
                    </div>
                  )}
                </div>
              );
            })}
          </div>

          <button
            onClick={() => setOpen(false)}
            className="mt-2 w-full rounded-lg border border-surface-200 py-1 text-xs text-surface-500 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-800"
          >
            Close
          </button>
        </>
      )}
    </div>
  );
}
