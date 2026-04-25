/**
 * DeviceTemplatesPage — admin editor for repair templates.
 *
 * Shops create reusable "job cards" once:
 *   - iPhone 13 screen replacement
 *   - MacBook battery replacement
 *   - Samsung S22 back glass
 * ...then the tech one-click applies them on any ticket.
 *
 * This page is the CRUD source of truth for migration 087
 * (device_model_templates). It's intentionally a small, form-heavy page —
 * no fancy drag-and-drop — because templates are edited rarely but need
 * to be 100% correct when they are.
 */

import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus,
  Wand2,
  Pencil,
  Trash2,
  Loader2,
  Save,
  X,
  DollarSign,
  Clock,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { deviceTemplateApi, inventoryApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';

interface TemplatePart {
  inventory_item_id: number;
  qty: number;
  name?: string;
  sku?: string | null;
  in_stock?: number;
  stock_badge?: 'green' | 'yellow' | 'red';
}

interface TemplateForm {
  id?: number;
  name: string;
  device_category: string;
  device_model: string;
  fault: string;
  est_labor_minutes: number;
  est_labor_cost_dollars: number;
  suggested_price_dollars: number;
  warranty_days: number;
  parts: TemplatePart[];
  diagnostic_checklist: string[];
  is_active: boolean;
}

const EMPTY_FORM: TemplateForm = {
  name: '',
  device_category: 'phone',
  device_model: '',
  fault: '',
  est_labor_minutes: 30,
  est_labor_cost_dollars: 0,
  suggested_price_dollars: 0,
  warranty_days: 30,
  parts: [],
  diagnostic_checklist: [],
  is_active: true,
};

const CATEGORIES = ['phone', 'tablet', 'laptop', 'tv', 'watch', 'other'];

// WEB-FF-001 / FIXED-by-Fixer-ZZ 2026-04-25 — float * 100 + round drops a cent
// when the dollar input came from a binary-fp computation (e.g. 0.1+0.2). Parse
// the input as a string and split on the decimal so 19.995 -> 1999, 19.99 ->
// 1999, 0.1 -> 10 deterministically. Falls back to 0 on bad input.
function dollarsToCents(value: number | string): number {
  const raw = String(value ?? '').trim();
  if (!raw) return 0;
  const m = raw.match(/^(-?)(\d*)(?:\.(\d{0,2}))?\d*$/);
  if (!m) {
    const fallback = Number(raw);
    return Number.isFinite(fallback) ? Math.round(fallback * 100) : 0;
  }
  const [, sign, whole, frac = ''] = m;
  const cents = Number(whole || '0') * 100 + Number((frac + '00').slice(0, 2) || '0');
  return sign === '-' ? -cents : cents;
}

export function DeviceTemplatesPage() {
  const qc = useQueryClient();
  const [editing, setEditing] = useState<TemplateForm | null>(null);
  const [partSearch, setPartSearch] = useState('');

  // WEB-FX-003: Esc closes the editor modal so keyboard users aren't trapped.
  useEffect(() => {
    if (!editing) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') setEditing(null); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [editing]);

  const { data, isLoading } = useQuery({
    queryKey: ['device-templates-admin'],
    queryFn: () => deviceTemplateApi.list({ active: false }),
  });
  const templates = data?.data?.data ?? [];

  const { data: partData } = useQuery({
    queryKey: ['inventory-part-search', partSearch],
    queryFn: () =>
      inventoryApi.list({
        keyword: partSearch,
        pagesize: 10,
      } as any),
    enabled: !!editing && partSearch.length >= 2,
  });
  const partResults =
    partData?.data?.data?.items ||
    partData?.data?.items ||
    partData?.data?.data ||
    [];

  const saveMut = useMutation({
    mutationFn: (form: TemplateForm) => {
      const payload = {
        name: form.name,
        device_category: form.device_category || null,
        device_model: form.device_model || null,
        fault: form.fault || null,
        est_labor_minutes: form.est_labor_minutes,
        est_labor_cost: dollarsToCents(form.est_labor_cost_dollars),
        suggested_price: dollarsToCents(form.suggested_price_dollars),
        warranty_days: form.warranty_days,
        parts: form.parts.map((p) => ({ inventory_item_id: p.inventory_item_id, qty: p.qty })),
        diagnostic_checklist: form.diagnostic_checklist,
        is_active: form.is_active,
      };
      return form.id
        ? deviceTemplateApi.update(form.id, payload)
        : deviceTemplateApi.create(payload);
    },
    onSuccess: () => {
      toast.success('Template saved');
      qc.invalidateQueries({ queryKey: ['device-templates-admin'] });
      qc.invalidateQueries({ queryKey: ['device-templates'] });
      setEditing(null);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to save template';
      toast.error(msg);
    },
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => deviceTemplateApi.delete(id),
    onSuccess: () => {
      toast.success('Template deleted');
      qc.invalidateQueries({ queryKey: ['device-templates-admin'] });
      qc.invalidateQueries({ queryKey: ['device-templates'] });
    },
    onError: () => toast.error('Failed to delete template'),
  });

  const startEdit = (row: any) => {
    setEditing({
      id: row.id,
      name: row.name ?? '',
      device_category: row.device_category ?? '',
      device_model: row.device_model ?? '',
      fault: row.fault ?? '',
      est_labor_minutes: row.est_labor_minutes ?? 0,
      est_labor_cost_dollars: (row.est_labor_cost ?? 0) / 100,
      suggested_price_dollars: (row.suggested_price ?? 0) / 100,
      warranty_days: row.warranty_days ?? 30,
      parts: (row.parts ?? []).map((p: any) => ({
        inventory_item_id: p.inventory_item_id,
        qty: p.qty,
        name: p.name,
        in_stock: p.in_stock,
      })),
      diagnostic_checklist: row.diagnostic_checklist ?? [],
      is_active: !!row.is_active,
    });
  };

  const addPart = (item: any) => {
    if (!editing) return;
    if (editing.parts.find((p) => p.inventory_item_id === item.id)) {
      toast.error('Part already in template');
      return;
    }
    setEditing({
      ...editing,
      parts: [
        ...editing.parts,
        { inventory_item_id: item.id, qty: 1, name: item.name, in_stock: item.in_stock },
      ],
    });
    setPartSearch('');
  };

  const updatePartQty = (idx: number, qty: number) => {
    if (!editing) return;
    const parts = editing.parts.map((p, i) => (i === idx ? { ...p, qty: Math.max(1, qty) } : p));
    setEditing({ ...editing, parts });
  };

  const removePart = (idx: number) => {
    if (!editing) return;
    setEditing({ ...editing, parts: editing.parts.filter((_, i) => i !== idx) });
  };

  const addChecklistItem = () => {
    if (!editing) return;
    setEditing({ ...editing, diagnostic_checklist: [...editing.diagnostic_checklist, ''] });
  };
  const updateChecklistItem = (idx: number, text: string) => {
    if (!editing) return;
    const list = editing.diagnostic_checklist.map((c, i) => (i === idx ? text : c));
    setEditing({ ...editing, diagnostic_checklist: list });
  };
  const removeChecklistItem = (idx: number) => {
    if (!editing) return;
    setEditing({
      ...editing,
      diagnostic_checklist: editing.diagnostic_checklist.filter((_, i) => i !== idx),
    });
  };

  return (
    <div className="mx-auto max-w-5xl p-6">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-semibold text-surface-900 dark:text-surface-100">
            <Wand2 className="h-6 w-6 text-primary-500" />
            Device Repair Templates
          </h1>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
            Save repeatable repair jobs. Techs apply one with a single click on any ticket.
          </p>
        </div>
        <button
          onClick={() => setEditing({ ...EMPTY_FORM })}
          className="flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" /> New template
        </button>
      </div>

      {isLoading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
        </div>
      ) : templates.length === 0 ? (
        <div className="card flex flex-col items-center p-12 text-center">
          <Wand2 className="mb-3 h-10 w-10 text-surface-300" />
          <p className="text-sm text-surface-500">No templates yet.</p>
          <p className="mt-1 text-xs text-surface-400">
            Click "New template" to save your first common repair job.
          </p>
        </div>
      ) : (
        <div className="card divide-y divide-surface-200 dark:divide-surface-700">
          {templates.map((t: any) => (
            <div key={t.id} className="flex items-start justify-between gap-4 p-4">
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <span className="font-semibold text-surface-900 dark:text-surface-100">{t.name}</span>
                  {!t.is_active && (
                    <span className="rounded-full bg-surface-200 px-2 py-0.5 text-[10px] font-medium text-surface-600 dark:bg-surface-700 dark:text-surface-300">
                      inactive
                    </span>
                  )}
                </div>
                <div className="mt-1 flex flex-wrap gap-3 text-xs text-surface-500 dark:text-surface-400">
                  {t.device_category && <span>{t.device_category}</span>}
                  {t.device_model && <span>{t.device_model}</span>}
                  {t.fault && <span>{t.fault}</span>}
                  {t.est_labor_minutes > 0 && (
                    <span className="flex items-center gap-1">
                      <Clock className="h-3 w-3" /> {t.est_labor_minutes}m
                    </span>
                  )}
                  {t.suggested_price > 0 && (
                    <span className="flex items-center gap-1">
                      <DollarSign className="h-3 w-3" /> {(t.suggested_price / 100).toFixed(2)}
                    </span>
                  )}
                  <span>{(t.parts ?? []).length} part(s)</span>
                </div>
              </div>
              <div className="flex gap-1">
                <button
                  onClick={() => startEdit(t)}
                  className="rounded-lg p-1.5 text-surface-500 hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-700"
                >
                  <Pencil className="h-4 w-4" />
                </button>
                <button
                  onClick={async () => {
                    // WEB-FB-007 (Fixer-QQQ 2026-04-25): swap native confirm for
                    // themed async confirm so the dialog respects dark mode +
                    // brand fonts and queues correctly with other modals.
                    if (await confirm(`Delete template "${t.name}"?`, { danger: true, confirmLabel: 'Delete' })) deleteMut.mutate(t.id);
                  }}
                  className="rounded-lg p-1.5 text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20"
                >
                  <Trash2 className="h-4 w-4" />
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      {editing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="presentation" onClick={() => setEditing(null)}>
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="device-tpl-edit-title"
            className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-white p-6 shadow-2xl dark:bg-surface-800"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-4 flex items-center justify-between">
              <h2 id="device-tpl-edit-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
                {editing.id ? 'Edit template' : 'New template'}
              </h2>
              <button onClick={() => setEditing(null)} className="p-1 text-surface-400 hover:text-surface-600">
                <X className="h-5 w-5" />
              </button>
            </div>

            <div className="space-y-3">
              <div>
                <label htmlFor="dt-name" className="mb-1 block text-xs font-semibold uppercase text-surface-500">Name *</label>
                <input
                  id="dt-name"
                  value={editing.name}
                  onChange={(e) => setEditing({ ...editing, name: e.target.value })}
                  placeholder="iPhone 13 Screen Replacement"
                  required
                  aria-required="true"
                  aria-invalid={!editing.name.trim() ? true : undefined}
                  aria-describedby={!editing.name.trim() ? 'dt-name-error' : undefined}
                  className={`w-full rounded-lg border bg-surface-50 p-2 text-sm dark:bg-surface-900 dark:text-surface-100 ${!editing.name.trim() ? 'border-red-400 dark:border-red-500' : 'border-surface-200 dark:border-surface-700'}`}
                />
                {!editing.name.trim() && (
                  <p id="dt-name-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">
                    Name is required.
                  </p>
                )}
              </div>

              <div className="grid grid-cols-3 gap-2">
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Category</label>
                  <select
                    value={editing.device_category}
                    onChange={(e) => setEditing({ ...editing, device_category: e.target.value })}
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  >
                    <option value="">-</option>
                    {CATEGORIES.map((c) => (
                      <option key={c} value={c}>
                        {c}
                      </option>
                    ))}
                  </select>
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Model</label>
                  <input
                    value={editing.device_model}
                    onChange={(e) => setEditing({ ...editing, device_model: e.target.value })}
                    placeholder="iPhone 13"
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Fault</label>
                  <input
                    value={editing.fault}
                    onChange={(e) => setEditing({ ...editing, fault: e.target.value })}
                    placeholder="screen"
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
              </div>

              <div className="grid grid-cols-4 gap-2">
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Labor (min)</label>
                  <input
                    type="number"
                    min={0}
                    value={editing.est_labor_minutes}
                    onChange={(e) =>
                      setEditing({ ...editing, est_labor_minutes: Number(e.target.value) || 0 })
                    }
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Labor ($)</label>
                  <input
                    type="number"
                    min={0}
                    step="0.01"
                    value={editing.est_labor_cost_dollars}
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        est_labor_cost_dollars: Number(e.target.value) || 0,
                      })
                    }
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Price ($)</label>
                  <input
                    type="number"
                    min={0}
                    step="0.01"
                    value={editing.suggested_price_dollars}
                    onChange={(e) =>
                      setEditing({
                        ...editing,
                        suggested_price_dollars: Number(e.target.value) || 0,
                      })
                    }
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Warranty (d)</label>
                  <input
                    type="number"
                    min={0}
                    value={editing.warranty_days}
                    onChange={(e) =>
                      setEditing({ ...editing, warranty_days: Number(e.target.value) || 0 })
                    }
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                  />
                </div>
              </div>

              <div>
                <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">Parts</label>
                <div className="mb-2 space-y-1">
                  {editing.parts.length === 0 && (
                    <p className="text-xs text-surface-400">No parts yet — search below.</p>
                  )}
                  {editing.parts.map((p, i) => (
                    <div
                      key={p.inventory_item_id}
                      className="flex items-center gap-2 rounded-lg border border-surface-200 p-2 text-xs dark:border-surface-700"
                    >
                      <span className="flex-1 truncate">{p.name ?? `#${p.inventory_item_id}`}</span>
                      <input
                        type="number"
                        min={1}
                        value={p.qty}
                        onChange={(e) => updatePartQty(i, Number(e.target.value) || 1)}
                        className="w-14 rounded border border-surface-200 bg-white p-1 text-center dark:border-surface-600 dark:bg-surface-900"
                      />
                      <button
                        onClick={() => removePart(i)}
                        className="p-1 text-red-500 hover:text-red-700"
                      >
                        <X className="h-3 w-3" />
                      </button>
                    </div>
                  ))}
                </div>
                <input
                  value={partSearch}
                  onChange={(e) => setPartSearch(e.target.value)}
                  placeholder="Search inventory to add parts..."
                  className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                />
                {partSearch.length >= 2 && Array.isArray(partResults) && partResults.length > 0 && (
                  <div className="mt-1 max-h-40 overflow-y-auto rounded-lg border border-surface-200 dark:border-surface-700">
                    {partResults.map((item: any) => (
                      <button
                        key={item.id}
                        onClick={() => addPart(item)}
                        className="flex w-full items-center justify-between px-2 py-1 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700"
                      >
                        <span className="truncate">{item.name}</span>
                        <span className="text-surface-400">{item.in_stock} in stock</span>
                      </button>
                    ))}
                  </div>
                )}
              </div>

              <div>
                <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">
                  Diagnostic checklist
                </label>
                <div className="space-y-1">
                  {editing.diagnostic_checklist.map((c, i) => (
                    <div key={i} className="flex items-center gap-2">
                      <input
                        value={c}
                        onChange={(e) => updateChecklistItem(i, e.target.value)}
                        placeholder="Inspect back glass..."
                        className="flex-1 rounded-lg border border-surface-200 bg-surface-50 p-1.5 text-xs dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                      />
                      <button
                        onClick={() => removeChecklistItem(i)}
                        className="p-1 text-red-500 hover:text-red-700"
                      >
                        <X className="h-3 w-3" />
                      </button>
                    </div>
                  ))}
                </div>
                <button
                  onClick={addChecklistItem}
                  className="mt-1 text-xs text-primary-600 hover:underline dark:text-primary-400"
                >
                  + Add step
                </button>
              </div>

              <label className="flex items-center gap-2 text-sm text-surface-700 dark:text-surface-300">
                <input
                  type="checkbox"
                  checked={editing.is_active}
                  onChange={(e) => setEditing({ ...editing, is_active: e.target.checked })}
                  className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                />
                Template is active
              </label>
            </div>

            <div className="mt-6 flex justify-end gap-2">
              <button
                onClick={() => setEditing(null)}
                className="rounded-lg border border-surface-300 px-4 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                onClick={() => saveMut.mutate(editing)}
                disabled={!editing.name || saveMut.isPending}
                className="flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
              >
                {saveMut.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Save className="h-4 w-4" />
                )}
                Save template
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
