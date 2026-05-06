import { useMemo, useRef, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { Loader2, RotateCcw, Search, X } from 'lucide-react';
import { invoiceApi, posApi } from '@/api/endpoints';
import type { PosReturnInput, PosReturnableInvoice, PosReturnableLineItem } from '@/api/types';
import { formatCurrency, formatDate } from '@/utils/format';
import { cn } from '@/utils/cn';

type InvoiceLookupRow = {
  id: number;
  order_id?: string | null;
  status?: string | null;
  total?: number | null;
  created_at?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  organization?: string | null;
};

function makeIdempotencyKey(): string {
  return globalThis.crypto?.randomUUID?.() ??
    `pos-return-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function errorMessage(err: unknown, fallback: string): string {
  if (err && typeof err === 'object') {
    const axiosErr = err as { response?: { data?: { message?: string } }; message?: string };
    return axiosErr.response?.data?.message || axiosErr.message || fallback;
  }
  return fallback;
}

function extractInvoiceRows(response: unknown): InvoiceLookupRow[] {
  const body = (response as { data?: { data?: unknown } } | undefined)?.data?.data;
  if (Array.isArray(body)) return body as InvoiceLookupRow[];
  if (body && typeof body === 'object') {
    const obj = body as { invoices?: unknown; items?: unknown };
    if (Array.isArray(obj.invoices)) return obj.invoices as InvoiceLookupRow[];
    if (Array.isArray(obj.items)) return obj.items as InvoiceLookupRow[];
  }
  return [];
}

function customerName(invoice: InvoiceLookupRow | PosReturnableInvoice): string {
  const org = invoice.organization?.trim();
  const name = [invoice.first_name, invoice.last_name].filter(Boolean).join(' ').trim();
  return org || name || 'Walk-in customer';
}

function lineReturnValue(line: PosReturnableLineItem, quantity: number): number {
  const soldQty = Number(line.quantity) || 1;
  const unitTax = soldQty > 0 ? Number(line.tax_amount || 0) / soldQty : 0;
  return quantity * (Number(line.unit_price || 0) + unitTax);
}

export function ReturnModal({
  open,
  onClose,
  onCompleted,
}: {
  open: boolean;
  onClose: () => void;
  onCompleted?: () => void;
}) {
  const queryClient = useQueryClient();
  const [lookup, setLookup] = useState('');
  const [lookupRows, setLookupRows] = useState<InvoiceLookupRow[]>([]);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [lookupLoading, setLookupLoading] = useState(false);
  const [invoice, setInvoice] = useState<PosReturnableInvoice | null>(null);
  const [selectedQty, setSelectedQty] = useState<Record<number, number>>({});
  const [reason, setReason] = useState('Customer return');
  const idempotencyKeyRef = useRef(makeIdempotencyKey());

  const loadInvoice = async (invoiceId: number) => {
    setLookupLoading(true);
    setLookupError(null);
    try {
      const res = await posApi.returnableInvoice(invoiceId);
      const detail = res.data.data;
      setInvoice(detail);
      setLookupRows([]);
      setSelectedQty({});
      idempotencyKeyRef.current = makeIdempotencyKey();
    } catch (err) {
      setInvoice(null);
      setLookupError(errorMessage(err, 'Invoice lookup failed'));
    } finally {
      setLookupLoading(false);
    }
  };

  const handleLookup = async () => {
    const trimmed = lookup.trim();
    if (!trimmed) return;
    setLookupLoading(true);
    setLookupError(null);
    setLookupRows([]);

    const numeric = Number(trimmed.replace(/^#/, ''));
    if (Number.isInteger(numeric) && numeric > 0) {
      await loadInvoice(numeric);
      return;
    }

    try {
      const res = await invoiceApi.list({ keyword: trimmed, pagesize: 8 });
      const rows = extractInvoiceRows(res);
      const exact = rows.find((row) => row.order_id?.toLowerCase() === trimmed.toLowerCase());
      if (exact?.id) {
        await loadInvoice(exact.id);
        return;
      }
      if (rows.length === 1 && rows[0]?.id) {
        await loadInvoice(rows[0].id);
        return;
      }
      setInvoice(null);
      setLookupRows(rows);
      if (rows.length === 0) setLookupError('No matching invoice found');
    } catch (err) {
      setLookupError(errorMessage(err, 'Invoice search failed'));
    } finally {
      setLookupLoading(false);
    }
  };

  const selectableLines = invoice?.line_items.filter(
    (line) => Number(line.quantity) > 0 && Number(line.returnable_quantity) > 0,
  ) ?? [];

  const selectedItems = useMemo(() => {
    if (!invoice) return [];
    return invoice.line_items
      .map((line) => ({
        line,
        quantity: selectedQty[line.id] ?? 0,
      }))
      .filter((entry) => entry.quantity > 0);
  }, [invoice, selectedQty]);

  const returnTotal = selectedItems.reduce(
    (sum, entry) => sum + lineReturnValue(entry.line, entry.quantity),
    0,
  );

  const returnMutation = useMutation({
    mutationFn: (payload: PosReturnInput) => posApi.return(payload, idempotencyKeyRef.current),
    onSuccess: async (res) => {
      toast.success(`Return completed: ${formatCurrency(res.data.data.total_credited)}`);
      if (invoice?.id) {
        await queryClient.invalidateQueries({ queryKey: ['invoice', invoice.id] });
      }
      onCompleted?.();
      onClose();
    },
    onError: (err) => {
      toast.error(errorMessage(err, 'Return failed'));
      idempotencyKeyRef.current = makeIdempotencyKey();
    },
  });

  const setLineQuantity = (line: PosReturnableLineItem, raw: number) => {
    const max = Math.max(0, Number(line.returnable_quantity) || 0);
    const next = Math.max(0, Math.min(max, Math.floor(raw || 0)));
    setSelectedQty((prev) => {
      const copy = { ...prev };
      if (next <= 0) delete copy[line.id];
      else copy[line.id] = next;
      return copy;
    });
  };

  const submitReturn = () => {
    if (!invoice) return;
    const cleanReason = reason.trim();
    if (!cleanReason) {
      toast.error('Return reason is required');
      return;
    }
    if (selectedItems.length === 0) {
      toast.error('Select at least one item to return');
      return;
    }
    returnMutation.mutate({
      invoice_id: invoice.id,
      items: selectedItems.map(({ line, quantity }) => ({
        line_item_id: line.id,
        quantity,
        reason: cleanReason,
      })),
    });
  };

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="pos-return-title"
      className="fixed inset-0 z-[90] flex items-center justify-center bg-black/50 p-4"
    >
      <div className="flex max-h-[92vh] w-full max-w-4xl flex-col overflow-hidden rounded-lg bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-4 dark:border-surface-700">
          <div className="flex items-center gap-3">
            <div className="flex h-9 w-9 items-center justify-center rounded-lg bg-primary-100 text-primary-700 dark:bg-primary-900/40 dark:text-primary-300">
              <RotateCcw className="h-5 w-5" />
            </div>
            <div>
              <h2 id="pos-return-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
                Process Return
              </h2>
              <p className="text-sm text-surface-500 dark:text-surface-400">
                Find the original invoice and select the returned items.
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="btn-icon btn-md text-surface-500 hover:text-surface-900 dark:hover:text-surface-100"
            aria-label="Close return modal"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="overflow-y-auto p-5">
          <div className="flex flex-col gap-3 sm:flex-row">
            <label className="flex-1">
              <span className="mb-1 block text-xs font-medium uppercase tracking-wider text-surface-500 dark:text-surface-400">
                Invoice ID or order number
              </span>
              <input
                value={lookup}
                onChange={(e) => setLookup(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') {
                    e.preventDefault();
                    void handleLookup();
                  }
                }}
                placeholder="INV-000123 or 123"
                className="input"
                autoFocus
              />
            </label>
            <button
              type="button"
              onClick={() => void handleLookup()}
              disabled={lookupLoading || !lookup.trim()}
              className="btn btn-primary mt-0 sm:mt-6"
            >
              {lookupLoading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />}
              Search
            </button>
          </div>

          {lookupError && (
            <div className="mt-3 rounded-lg border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800/50 dark:bg-red-900/20 dark:text-red-300">
              {lookupError}
            </div>
          )}

          {lookupRows.length > 0 && (
            <div className="mt-4 overflow-hidden rounded-lg border border-surface-200 dark:border-surface-700">
              {lookupRows.map((row) => (
                <button
                  key={row.id}
                  type="button"
                  onClick={() => void loadInvoice(row.id)}
                  className="btn btn-md !h-auto w-full !justify-between !gap-4 !rounded-none border-b border-surface-100 !px-4 !py-3 text-left !whitespace-normal last:border-b-0 hover:bg-surface-50 dark:border-surface-800 dark:hover:bg-surface-800/60"
                >
                  <span>
                    <span className="block font-mono text-sm font-semibold text-surface-900 dark:text-surface-100">
                      {row.order_id || `#${row.id}`}
                    </span>
                    <span className="text-xs text-surface-500">
                      {customerName(row)} · {row.created_at ? formatDate(row.created_at) : 'No date'}
                    </span>
                  </span>
                  <span className="text-right">
                    <span className="block text-sm font-semibold text-surface-900 dark:text-surface-100">
                      {formatCurrency(row.total ?? 0)}
                    </span>
                    <span className="text-xs uppercase text-surface-500">{row.status || 'unknown'}</span>
                  </span>
                </button>
              ))}
            </div>
          )}

          {invoice && (
            <div className="mt-5 space-y-4">
              <div className="flex flex-wrap items-start justify-between gap-4 rounded-lg border border-surface-200 bg-surface-50 px-4 py-3 dark:border-surface-700 dark:bg-surface-800/50">
                <div>
                  <div className="font-mono text-sm font-semibold text-surface-900 dark:text-surface-100">
                    {invoice.order_id}
                  </div>
                  <div className="text-sm text-surface-600 dark:text-surface-300">
                    {customerName(invoice)} · {formatDate(invoice.created_at)}
                  </div>
                </div>
                <div className="text-right">
                  <div className="text-sm text-surface-500">Invoice total</div>
                  <div className="text-lg font-bold text-surface-900 dark:text-surface-100">
                    {formatCurrency(invoice.total)}
                  </div>
                </div>
              </div>

              <div className="overflow-hidden rounded-lg border border-surface-200 dark:border-surface-700">
                <table className="w-full">
                  <thead className="bg-surface-50 dark:bg-surface-800/70">
                    <tr>
                      <th className="w-12 px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-surface-500" />
                      <th className="px-3 py-2 text-left text-xs font-semibold uppercase tracking-wider text-surface-500">Item</th>
                      <th className="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wider text-surface-500">Sold</th>
                      <th className="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wider text-surface-500">Available</th>
                      <th className="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wider text-surface-500">Return</th>
                      <th className="px-3 py-2 text-right text-xs font-semibold uppercase tracking-wider text-surface-500">Credit</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                    {invoice.line_items.map((line) => {
                      const max = Math.max(0, Number(line.returnable_quantity) || 0);
                      const qty = selectedQty[line.id] ?? 0;
                      const disabled = max <= 0 || Number(line.quantity) <= 0;
                      return (
                        <tr key={line.id} className={cn(disabled && 'opacity-55')}>
                          <td className="px-3 py-3">
                            <input
                              type="checkbox"
                              checked={qty > 0}
                              disabled={disabled}
                              onChange={(e) => setLineQuantity(line, e.target.checked ? 1 : 0)}
                              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                            />
                          </td>
                          <td className="px-3 py-3 text-sm text-surface-900 dark:text-surface-100">
                            {line.description}
                            {Number(line.returned_quantity) > 0 && (
                              <div className="text-xs text-surface-500">
                                {line.returned_quantity} already returned
                              </div>
                            )}
                          </td>
                          <td className="px-3 py-3 text-right text-sm text-surface-600 dark:text-surface-300">
                            {line.quantity}
                          </td>
                          <td className="px-3 py-3 text-right text-sm text-surface-600 dark:text-surface-300">
                            {max}
                          </td>
                          <td className="px-3 py-3 text-right">
                            <input
                              type="number"
                              min={0}
                              max={max}
                              value={qty}
                              disabled={disabled}
                              onChange={(e) => setLineQuantity(line, Number(e.target.value))}
                              className="input ml-auto h-9 w-20 text-right"
                            />
                          </td>
                          <td className="px-3 py-3 text-right text-sm font-medium text-surface-900 dark:text-surface-100">
                            {formatCurrency(lineReturnValue(line, qty))}
                          </td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>

              {selectableLines.length === 0 && (
                <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-800 dark:border-amber-800/50 dark:bg-amber-900/20 dark:text-amber-200">
                  This invoice has no remaining returnable items.
                </div>
              )}

              <label>
                <span className="mb-1 block text-xs font-medium uppercase tracking-wider text-surface-500 dark:text-surface-400">
                  Return reason
                </span>
                <textarea
                  value={reason}
                  onChange={(e) => setReason(e.target.value)}
                  rows={3}
                  className="input min-h-[84px]"
                />
              </label>
            </div>
          )}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 border-t border-surface-200 px-5 py-4 dark:border-surface-700">
          <div>
            <div className="text-xs uppercase tracking-wider text-surface-500">Credit total</div>
            <div className="text-xl font-bold text-surface-900 dark:text-surface-100">
              {formatCurrency(returnTotal)}
            </div>
          </div>
          <div className="flex items-center gap-2">
            <button type="button" onClick={onClose} className="btn btn-secondary">
              Cancel
            </button>
            <button
              type="button"
              onClick={submitReturn}
              disabled={!invoice || selectedItems.length === 0 || returnMutation.isPending || selectableLines.length === 0}
              className="btn btn-primary"
            >
              {returnMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <RotateCcw className="h-4 w-4" />}
              Complete Return
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
