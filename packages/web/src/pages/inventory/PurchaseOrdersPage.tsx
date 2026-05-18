import { useCallback, useEffect, useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Plus, Package, ChevronLeft, ChevronRight, Loader2, ChevronDown, ChevronUp, PackageCheck, Search, X, AlertTriangle, Send, ScanBarcode } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { inventoryApi, benchApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';
import { confirm } from '@/stores/confirmStore';

// WEB-UIUX-654: surface recent defect reports next to a PO line item so the
// operator sees "this exact SKU was reported defective N times in the last
// 30 days" before re-ordering more of it. Server endpoint is admin/manager
// only; non-privileged users see nothing (component returns null on 403).
function DefectWarningChip({ inventoryItemId }: { inventoryItemId: number | '' }) {
  const enabled = typeof inventoryItemId === 'number' && inventoryItemId > 0;
  const { data } = useQuery({
    queryKey: ['po-defect-warning', inventoryItemId],
    queryFn: () => benchApi.defects.byItem(inventoryItemId as number),
    enabled,
    retry: false,
    staleTime: 60_000,
  });
  if (!enabled) return null;
  const rows = (data?.data?.data as Array<{ reported_at: string }> | undefined) ?? [];
  const cutoff = Date.now() - 30 * 24 * 60 * 60 * 1000;
  const recent = rows.filter((r) => {
    const t = Date.parse(r.reported_at);
    return Number.isFinite(t) && t >= cutoff;
  });
  if (recent.length === 0) return null;
  return (
    <span
      role="alert"
      className="inline-flex items-center gap-1 rounded-md border border-amber-300 bg-amber-50 px-1.5 py-0.5 text-[10px] font-medium text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300"
      title={`${recent.length} defect report${recent.length === 1 ? '' : 's'} in the last 30 days. Confirm before re-ordering.`}
    >
      <AlertTriangle className="h-3 w-3" aria-hidden="true" />
      {recent.length} defect{recent.length === 1 ? '' : 's'} 30d
    </span>
  );
}

const STATUS_COLORS: Record<string, string> = {
  draft: 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
  pending: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  ordered: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  partial: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
  backordered: 'bg-orange-100 text-orange-700 dark:bg-orange-900/30 dark:text-orange-400',
  received: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
  cancelled: 'bg-red-100 text-red-500 dark:bg-red-900/30 dark:text-red-400',
};

const PO_STATUS_OPTIONS = ['draft', 'pending', 'ordered', 'partial', 'backordered', 'received', 'cancelled'];

interface PoLineItem {
  inventory_item_id: number | '';
  quantity_ordered: number;
  cost_price: number;
}

interface NewPoForm {
  supplier_id: number | '';
  // WEB-UIUX-1190: expected delivery date — server accepts it on POST and
  // uses it for late-shipment alerting + aging.
  expected_date: string;
  notes: string;
  items: PoLineItem[];
}

const EMPTY_ITEM: PoLineItem = { inventory_item_id: '', quantity_ordered: 1, cost_price: 0 };

// ---- WEB-W3-003: Receive modal ----
interface ReceiveItem {
  purchase_order_item_id: number;
  item_name: string;
  sku: string | null;
  quantity_ordered: number;
  quantity_received: number;
  receive_qty: number; // draft qty the user is entering
}

interface ReceiveModalProps {
  poId: number;
  poOrderId: string;
  items: any[];
  onClose: () => void;
  onSuccess: () => void;
}

function ReceiveModal({ poId, poOrderId, items, onClose, onSuccess }: ReceiveModalProps) {
  const navigate = useNavigate();
  const [receiving, setReceiving] = useState<ReceiveItem[]>(
    items
      .filter((it) => it.quantity_ordered - (it.quantity_received || 0) > 0)
      .map((it) => ({
        purchase_order_item_id: it.id,
        item_name: it.item_name,
        sku: it.sku,
        quantity_ordered: it.quantity_ordered,
        quantity_received: it.quantity_received || 0,
        // WEB-UIUX-1188: default the receive draft to 0, not the full
        // remaining. Pre-filling with the optimistic total lets a careless
        // "Confirm Receive" click silently post phantom units that
        // inventory cannot undo (no /reverse-receipt endpoint). Force the
        // cashier to type the physical count.
        receive_qty: 0,
      })),
  );

  const receiveMut = useMutation({
    mutationFn: () => {
      const payload = receiving
        .filter((r) => r.receive_qty > 0)
        .map((r) => ({ purchase_order_item_id: r.purchase_order_item_id, quantity_received: r.receive_qty }));
      if (payload.length === 0) throw new Error('No quantities entered');
      return inventoryApi.receivePurchaseOrder(poId, { items: payload });
    },
    onSuccess: (res: any) => {
      const firstItemId = res?.data?.data?.items?.[0]?.inventory_item_id;
      const inventoryPath = firstItemId ? `/inventory?highlight=${firstItemId}` : '/inventory';
      toast.success(
        (t) => (
          <span className="flex items-center gap-2">
            Stock received and updated
            <button
              onClick={() => { toast.dismiss(t.id); navigate(inventoryPath); }}
              className="text-xs font-semibold underline whitespace-nowrap"
            >
              View inventory
            </button>
          </span>
        ),
        { duration: 6000 },
      );
      onSuccess();
      onClose();
    },
    onError: (e: any) => {
      toast.error(e?.response?.data?.message || e?.message || 'Failed to receive');
    },
  });

  // WEB-UIUX-1193: in-modal barcode scan path. Operator hits the scan field
  // with a handheld scanner gun; on Enter the modal looks up the matching
  // PO line by SKU (case-insensitive) and increments its receive_qty by 1,
  // capped at the remaining count. Surfaces success/no-match/already-full
  // states inline so the cashier doesn't have to switch focus.
  const [scanValue, setScanValue] = useState('');
  const [scanFeedback, setScanFeedback] = useState<{ tone: 'ok' | 'warn' | 'err'; msg: string } | null>(null);
  const scanInputRef = useRef<HTMLInputElement>(null);

  const handleScan = useCallback((raw: string) => {
    const sku = raw.trim();
    if (!sku) return;
    const skuLower = sku.toLowerCase();
    const idx = receiving.findIndex((r) => (r.sku ?? '').toLowerCase() === skuLower);
    if (idx === -1) {
      setScanFeedback({ tone: 'err', msg: `No PO line matches SKU "${sku}".` });
      return;
    }
    const target = receiving[idx];
    const remaining = target.quantity_ordered - target.quantity_received;
    if (target.receive_qty >= remaining) {
      setScanFeedback({ tone: 'warn', msg: `"${target.item_name}" already at remaining cap (${remaining}).` });
      return;
    }
    setReceiving((prev) =>
      prev.map((item, i) =>
        i === idx ? { ...item, receive_qty: Math.min(remaining, item.receive_qty + 1) } : item,
      ),
    );
    setScanFeedback({ tone: 'ok', msg: `+1 ${target.item_name} (now ${target.receive_qty + 1} / ${remaining})` });
  }, [receiving]);

  const totalToReceive = receiving.reduce((s, r) => s + r.receive_qty, 0);
  // WEB-UIUX-1194: dirty-state guard on close. The modal captures physical
  // counts; an accidental dismiss = recount the entire shipment. Warn if
  // any line has a non-zero draft before discarding.
  const closeModal = useCallback(() => {
    if (receiveMut.isPending) return;
    if (totalToReceive > 0) {
      void confirm(
        `Discard counts for ${totalToReceive} item${totalToReceive === 1 ? '' : 's'}? You'll have to recount the shipment.`,
        { title: 'Discard receive counts?', confirmLabel: 'Discard', danger: true },
      ).then((ok) => { if (ok) onClose(); });
      return;
    }
    onClose();
  }, [onClose, receiveMut.isPending, totalToReceive]);

  useEffect(() => {
    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') closeModal();
    };
    document.addEventListener('keydown', handleKeyDown);
    return () => document.removeEventListener('keydown', handleKeyDown);
  }, [closeModal]);

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" onClick={closeModal}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="receive-po-title"
        aria-describedby="receive-po-summary"
        className="bg-white dark:bg-surface-900 rounded-xl shadow-xl w-full max-w-lg max-h-[90vh] flex flex-col"
        onClick={(event) => event.stopPropagation()}
      >
        <div className="flex items-center justify-between p-5 border-b border-surface-200 dark:border-surface-700">
          <div>
            <h2 id="receive-po-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">Receive Items</h2>
            <p className="text-sm text-surface-500">{poOrderId}</p>
          </div>
          <button
            type="button"
            onClick={closeModal}
            disabled={receiveMut.isPending}
            aria-label="Close receive items modal"
            className="text-surface-400 hover:text-surface-600 p-1 disabled:opacity-50"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* WEB-UIUX-1193: barcode-scan path surfaced inline so the cashier
            with a handheld scanner gun doesn't have to type qty per row. */}
        {receiving.length > 0 && (
          <div className="border-b border-surface-200 dark:border-surface-700 p-4">
            <label htmlFor="po-receive-scan-input" className="flex items-center gap-2 text-xs font-medium text-surface-500 dark:text-surface-400 mb-1.5">
              <ScanBarcode className="h-3.5 w-3.5" />
              Scan to receive (+1 per scan)
            </label>
            <input
              id="po-receive-scan-input"
              ref={scanInputRef}
              type="text"
              value={scanValue}
              onChange={(e) => setScanValue(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') {
                  e.preventDefault();
                  handleScan(scanValue);
                  setScanValue('');
                  scanInputRef.current?.focus();
                }
              }}
              placeholder="Scan or type SKU then Enter…"
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm font-mono text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 dark:placeholder:text-surface-500"
              autoComplete="off"
              spellCheck={false}
            />
            {scanFeedback && (
              <p
                className={cn(
                  'mt-1.5 text-xs',
                  scanFeedback.tone === 'ok' && 'text-emerald-600 dark:text-emerald-400',
                  scanFeedback.tone === 'warn' && 'text-amber-600 dark:text-amber-400',
                  scanFeedback.tone === 'err' && 'text-red-600 dark:text-red-400',
                )}
              >
                {scanFeedback.msg}
              </p>
            )}
          </div>
        )}

        <div className="flex-1 overflow-y-auto p-5 space-y-3">
          {receiving.length === 0 ? (
            <p className="text-sm text-surface-400 text-center py-4">All items already fully received.</p>
          ) : (
            receiving.map((r, idx) => {
              const remaining = r.quantity_ordered - r.quantity_received;
              return (
                <div key={r.purchase_order_item_id} className="flex items-center gap-3 text-sm">
                  <div className="flex-1 min-w-0">
                    <div className="font-medium text-surface-900 dark:text-surface-100 truncate">{r.item_name}</div>
                    {r.sku && <div className="text-xs text-surface-500 font-mono">{r.sku}</div>}
                    <div className="text-xs text-surface-400">
                      Ordered: {r.quantity_ordered} · Already received: {r.quantity_received} · Remaining: {remaining}
                    </div>
                  </div>
                  <div className="flex-shrink-0 w-24">
                    <label className="block text-xs text-surface-400 mb-1">Receive</label>
                    <input
                      type="number"
                      min={0}
                      max={remaining}
                      value={r.receive_qty}
                      onChange={(e) => {
                        const val = Math.min(remaining, Math.max(0, parseInt(e.target.value) || 0));
                        setReceiving((prev) => prev.map((item, i) => i === idx ? { ...item, receive_qty: val } : item));
                      }}
                      className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                    />
                  </div>
                </div>
              );
            })
          )}
        </div>

        <div className="p-5 border-t border-surface-200 dark:border-surface-700 flex justify-between items-center">
          <span id="receive-po-summary" className="text-sm text-surface-500">Total units to receive: <strong>{totalToReceive}</strong></span>
          <div className="flex gap-2">
            <button onClick={closeModal} disabled={receiveMut.isPending} className="px-3 py-2 text-sm text-surface-500 hover:text-surface-700 disabled:opacity-50">
              Cancel
            </button>
            <button
              type="button"
              onClick={async () => {
                const itemCount = receiving.filter((r) => r.receive_qty > 0).length;
                const ok = await confirm(
                  `Receive ${totalToReceive} units across ${itemCount} item(s)? This cannot be undone.`,
                  { title: 'Confirm receive', confirmLabel: 'Receive' },
                );
                if (ok) receiveMut.mutate();
              }}
              disabled={totalToReceive === 0 || receiveMut.isPending || receiving.length === 0}
              className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 text-on-primary rounded-lg text-sm font-medium hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
            >
              {receiveMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <PackageCheck className="h-4 w-4" />}
              Confirm Receive
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

// ---- WEB-W3-010: Expandable PO detail row ----
interface PoDetailRowProps {
  po: Record<string, unknown>;
  onReceive: (po: Record<string, unknown>, items: any[]) => void;
}

function PoDetailRow({ po, onReceive }: PoDetailRowProps) {
  const poId = po.id as number;
  const [expanded, setExpanded] = useState(false);
  const queryClient = useQueryClient();

  const markOrderedMut = useMutation({
    mutationFn: () => inventoryApi.updatePurchaseOrder(poId, { status: 'ordered' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('PO marked as Ordered');
    },
  });

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-order-detail', poId],
    queryFn: () => inventoryApi.getPurchaseOrder(poId),
    enabled: expanded,
    staleTime: 30_000,
  });

  const detail = data?.data?.data;
  const lineItems: any[] = detail?.items || [];
  const status = (po.status as string) || 'draft';
  const canReceive = ['ordered', 'partial', 'backordered'].includes(status);

  return (
    <>
      <tr
        className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors cursor-pointer"
        onClick={() => setExpanded(!expanded)}
      >
        <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">
          <div className="flex items-center gap-1.5">
            {expanded ? <ChevronUp className="h-3.5 w-3.5 text-surface-400" /> : <ChevronDown className="h-3.5 w-3.5 text-surface-400" />}
            {(po.order_id as string) || `PO-${po.id}`}
          </div>
        </td>
        <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
          {(po.supplier_name as string) || '(Supplier removed)'}
        </td>
        <td className="px-4 py-3">
          <span className={cn(
            'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium capitalize',
            STATUS_COLORS[status] || STATUS_COLORS.draft,
          )}>
            {status}
          </span>
        </td>
        <td className="px-4 py-3 text-surface-500">
          {(po.item_count as number) || 0} items
        </td>
        <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">
          {formatCurrency((po.total as number) || 0)}
        </td>
        <td className="px-4 py-3 text-surface-400 text-xs">
          {po.created_at ? formatDate(po.created_at as string) : '—'}
        </td>
      </tr>

      {expanded && (
        <tr>
          <td colSpan={6} className="bg-surface-50 dark:bg-surface-800/30 border-b border-surface-100 dark:border-surface-800">
            <div className="px-6 py-4">
              {isLoading ? (
                <div className="flex items-center gap-2 text-sm text-surface-400">
                  <Loader2 className="h-4 w-4 animate-spin" /> Loading line items…
                </div>
              ) : lineItems.length === 0 ? (
                <p className="text-sm text-surface-400">No line items found.</p>
              ) : (
                <div>
                  <table className="w-full text-sm mb-3">
                    <thead>
                      <tr className="text-left text-xs text-surface-500 border-b border-surface-200 dark:border-surface-700">
                        <th className="pb-1.5 pr-4">Item</th>
                        <th className="pb-1.5 pr-4">SKU</th>
                        <th className="pb-1.5 pr-4 text-right">Ordered</th>
                        <th className="pb-1.5 pr-4 text-right">Received</th>
                        <th className="pb-1.5 text-right">Unit Cost</th>
                      </tr>
                    </thead>
                    <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
                      {lineItems.map((li: any) => {
                        const received = li.quantity_received || 0;
                        const ordered = li.quantity_ordered;
                        const pct = ordered > 0 ? Math.round((received / ordered) * 100) : 0;
                        return (
                          <tr key={li.id} className="text-sm">
                            <td className="py-1.5 pr-4 font-medium text-surface-800 dark:text-surface-200">{li.item_name}</td>
                            <td className="py-1.5 pr-4 font-mono text-xs text-surface-500">{li.sku || '—'}</td>
                            <td className="py-1.5 pr-4 text-right text-surface-700 dark:text-surface-300">{ordered}</td>
                            <td className="py-1.5 pr-4 text-right">
                              <span className={cn(
                                received >= ordered ? 'text-green-600 dark:text-green-400 font-semibold' :
                                received > 0 ? 'text-amber-600 dark:text-amber-400' :
                                'text-surface-400',
                              )}>
                                {received}
                              </span>
                              <span className="ml-1 text-xs text-surface-400">({pct}%)</span>
                            </td>
                            <td className="py-1.5 text-right text-surface-700 dark:text-surface-300">
                              {formatCurrency(li.cost_price || 0)}
                            </td>
                          </tr>
                        );
                      })}
                    </tbody>
                  </table>

                  {canReceive && (
                    <button
                      onClick={(e) => { e.stopPropagation(); onReceive(po, lineItems); }}
                      className="inline-flex items-center gap-2 px-3 py-1.5 bg-primary-600 text-on-primary rounded-lg text-xs font-semibold hover:bg-primary-700 transition-colors"
                    >
                      <PackageCheck className="h-3.5 w-3.5" /> Receive Items
                    </button>
                  )}
                  {!canReceive && status === 'received' && (
                    <span className="text-xs text-green-600 dark:text-green-400 font-medium">Fully received</span>
                  )}
                  {!canReceive && status !== 'received' && status !== 'cancelled' && (
                    <div className="flex flex-wrap items-center gap-2">
                      <span className="text-xs text-surface-400">Change status to &ldquo;ordered&rdquo; before receiving.</span>
                      <button
                        onClick={(e) => { e.stopPropagation(); markOrderedMut.mutate(); }}
                        disabled={markOrderedMut.isPending}
                        className="inline-flex items-center gap-1.5 px-2.5 py-1 bg-blue-600 text-white rounded-md text-xs font-semibold hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                      >
                        {markOrderedMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : null}
                        Mark as Ordered
                      </button>
                      {/* WEB-UIUX-1191: "Email supplier" composes a mailto: link
                          pre-filled with the PO order_id + line-item summary so
                          the operator can send a purchase request without
                          retyping. Disabled when no supplier email on file —
                          tooltip explains. Uses mailto: rather than a server
                          email send so this works in any environment without
                          per-tenant SMTP setup. */}
                      <PoEmailSupplierButton po={po} lineItems={lineItems} onMarkOrdered={() => markOrderedMut.mutate()} />
                    </div>
                  )}
                </div>
              )}
            </div>
          </td>
        </tr>
      )}
    </>
  );
}

// WEB-UIUX-1191: Email-supplier button — builds a mailto: URL with the PO
// summary in the body so a draft / pending PO can be sent without leaving the
// app. Disabled with explanatory tooltip when no supplier email is on file.
function PoEmailSupplierButton({
  po,
  lineItems,
  onMarkOrdered,
}: {
  po: Record<string, unknown>;
  lineItems: any[];
  onMarkOrdered: () => void;
}) {
  const supplierEmail = (po.supplier_email as string | null | undefined) ?? null;
  const supplierName = (po.supplier_name as string | null | undefined) ?? 'supplier';
  const supplierContact = (po.supplier_contact as string | null | undefined) ?? null;
  const orderId = (po.order_id as string | null | undefined) ?? `PO-${po.id}`;
  const expectedDate = (po.expected_date as string | null | undefined) ?? null;
  const notes = (po.notes as string | null | undefined) ?? null;
  const total = Number(po.total) || 0;

  const disabled = !supplierEmail;
  const disabledReason = !supplierEmail
    ? 'No email on file for this supplier — add one under Inventory → Suppliers.'
    : '';

  function buildMailto(): string {
    const greeting = supplierContact ? `Hi ${supplierContact},` : `Hi ${supplierName} team,`;
    const lines: string[] = [
      greeting,
      '',
      `Please process purchase order ${orderId}:`,
      '',
    ];
    if (lineItems.length > 0) {
      for (const li of lineItems) {
        const sku = li.sku ? ` [${li.sku}]` : '';
        const qty = li.quantity_ordered ?? 0;
        const cost = Number(li.cost_price) || 0;
        const lineTotal = qty * cost;
        lines.push(`  • ${li.item_name}${sku} — qty ${qty} @ ${formatCurrency(cost)} = ${formatCurrency(lineTotal)}`);
      }
      lines.push('');
    }
    lines.push(`Order total: ${formatCurrency(total)}`);
    if (expectedDate) lines.push(`Requested delivery: ${expectedDate}`);
    if (notes) {
      lines.push('');
      lines.push('Notes:');
      lines.push(notes);
    }
    lines.push('');
    lines.push('Reply to this email to confirm. Thanks.');
    const subject = `Purchase Order ${orderId}`;
    const body = lines.join('\n');
    return `mailto:${encodeURIComponent(supplierEmail!)}?subject=${encodeURIComponent(subject)}&body=${encodeURIComponent(body)}`;
  }

  return (
    <button
      type="button"
      title={disabledReason || `Compose email to ${supplierEmail}`}
      disabled={disabled}
      onClick={(e) => {
        e.stopPropagation();
        if (disabled) return;
        window.location.href = buildMailto();
        // Auto-advance to "ordered" once the operator has triggered the
        // email; reduces the chance of a draft PO sitting forever after the
        // supplier was contacted. Operator can still revert via PUT.
        onMarkOrdered();
      }}
      className="inline-flex items-center gap-1.5 px-2.5 py-1 border border-surface-300 rounded-md text-xs font-semibold text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-200 dark:hover:bg-surface-800 disabled:opacity-40 disabled:cursor-not-allowed transition-colors"
    >
      <Send className="h-3 w-3" /> Email supplier
    </button>
  );
}

export function PurchaseOrdersPage() {
  const queryClient = useQueryClient();
  const [page, setPage] = useState(1);
  const [searchInput, setSearchInput] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [showCreate, setShowCreate] = useState(false);
  const [newPo, setNewPo] = useState<NewPoForm>({ supplier_id: '', expected_date: '', notes: '', items: [{ ...EMPTY_ITEM }] });

  // WEB-W3-003: receive modal state
  const [receiveModal, setReceiveModal] = useState<{ po: Record<string, unknown>; items: any[] } | null>(null);

  // WEB-UIUX-1192: status filter + keyword search, debounced.
  const [poSearch, setPoSearch] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setPoSearch(searchInput.trim()), 300);
    return () => clearTimeout(t);
  }, [searchInput]);
  const poListParams = {
    page,
    pagesize: 25,
    status: statusFilter || undefined,
    q: poSearch || undefined,
  };
  const hasListFilters = Boolean(poSearch || statusFilter);

  const { data, isLoading } = useQuery({
    queryKey: ['purchase-orders', page, statusFilter, poSearch],
    queryFn: () => inventoryApi.listPurchaseOrders(poListParams),
    staleTime: 30_000,
  });

  const { data: suppliersData, isLoading: suppliersLoading } = useQuery({
    queryKey: ['suppliers'],
    queryFn: () => inventoryApi.listSuppliers(),
    enabled: showCreate,
    staleTime: 30_000,
  });
  const suppliers: Array<{ id: number; name: string }> = suppliersData?.data?.data || [];

  const { data: inventoryData, isLoading: inventoryLoading } = useQuery({
    queryKey: ['inventory-items-select'],
    queryFn: () => inventoryApi.list({ pagesize: 250 }),
    enabled: showCreate,
    staleTime: 30_000,
  });
  const inventoryItems: Array<{ id: number; name: string; sku: string; cost_price: number }> =
    inventoryData?.data?.data?.items || [];

  const orders = data?.data?.data?.orders || data?.data?.data?.purchase_orders || [];
  const pagination = data?.data?.data?.pagination || { page: 1, total: 0, total_pages: 1 };

  const createMut = useMutation({
    mutationFn: () => {
      if (!newPo.supplier_id) throw new Error('Supplier is required');
      const validItems = newPo.items.filter(
        (i): i is { inventory_item_id: number; quantity_ordered: number; cost_price: number } =>
          typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0 && i.quantity_ordered > 0,
      );
      return inventoryApi.createPurchaseOrder({
        supplier_id: newPo.supplier_id as number,
        expected_date: newPo.expected_date || undefined,
        notes: newPo.notes || undefined,
        items: validItems,
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
      toast.success('Purchase order created');
      setShowCreate(false);
      setNewPo({ supplier_id: '', expected_date: '', notes: '', items: [{ ...EMPTY_ITEM }] });
    },
    onError: (e: unknown) => {
      const msg =
        e instanceof Error
          ? e.message
          : (e as { response?: { data?: { message?: string } } })?.response?.data?.message ||
            'Failed to create PO';
      toast.error(msg);
    },
  });

  const addItem = () => setNewPo({ ...newPo, items: [...newPo.items, { ...EMPTY_ITEM }] });
  const removeItem = (i: number) => setNewPo({ ...newPo, items: newPo.items.filter((_, idx) => idx !== i) });
  const updateItem = (i: number, patch: Partial<PoLineItem>) => {
    const items = newPo.items.map((item, idx) => (idx === i ? { ...item, ...patch } : item));
    setNewPo({ ...newPo, items });
  };

  const canSubmit =
    !!newPo.supplier_id &&
    newPo.items.some(
      (i) => typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0,
    );
  const createDisabledReason = !newPo.supplier_id
    ? 'Select a supplier before creating this purchase order.'
    : !newPo.items.some((i) => typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0)
      ? 'Add at least one inventory item before creating this purchase order.'
      : '';

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Purchase Orders</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400">Manage supplier orders</p>
        </div>
        <button
          onClick={() => setShowCreate(!showCreate)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-on-primary hover:bg-primary-700 transition-colors"
        >
          <Plus className="h-4 w-4" /> New Purchase Order
        </button>
      </div>

      {/* WEB-UIUX-1192: status filter + keyword search for the PO list. */}
      <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-center">
        <input
          type="search"
          value={searchInput}
          onChange={(e) => { setSearchInput(e.target.value); setPage(1); }}
          placeholder="Search PO number or supplier name…"
          className="flex-1 rounded-lg border border-surface-300 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          aria-label="Search purchase orders by PO number or supplier name"
        />
        <select
          value={statusFilter}
          onChange={(e) => { setStatusFilter(e.target.value); setPage(1); }}
          aria-label="Filter purchase orders by status"
          className="rounded-lg border border-surface-300 px-3 py-2 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
        >
          <option value="">All statuses</option>
          <option value="draft">Draft</option>
          <option value="ordered">Ordered</option>
          <option value="partial">Partial</option>
          <option value="backordered">Backordered</option>
          <option value="received">Received</option>
          <option value="cancelled">Cancelled</option>
        </select>
      </div>

      {/* Create form */}
      {showCreate && (
        <div className="card p-5 mb-6">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">New Purchase Order</h3>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-3 mb-3">
            <div>
              <label htmlFor="po-supplier" className="block text-xs font-medium text-surface-500 mb-1">Supplier <span className="text-red-500">*</span></label>
              <select
                id="po-supplier"
                value={newPo.supplier_id}
                disabled={suppliersLoading}
                onChange={(e) => setNewPo({ ...newPo, supplier_id: e.target.value ? Number(e.target.value) : '' })}
                className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 disabled:opacity-50"
              >
                {suppliersLoading
                  ? <option disabled>Loading…</option>
                  : <option value="">Select supplier…</option>
                }
                {suppliers.map((s) => (
                  <option key={s.id} value={s.id}>{s.name}</option>
                ))}
              </select>
            </div>
            {/* WEB-UIUX-1190: expected delivery date — server stores it for
                late-shipment alerting + aging reports. */}
            <div>
              <label htmlFor="po-expected-date" className="block text-xs font-medium text-surface-500 mb-1">Expected date</label>
              <input
                id="po-expected-date"
                type="date"
                value={newPo.expected_date}
                onChange={(e) => setNewPo({ ...newPo, expected_date: e.target.value })}
                className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
              />
            </div>
            <div>
              <label htmlFor="po-notes" className="block text-xs font-medium text-surface-500 mb-1">Notes</label>
              <input
                id="po-notes"
                value={newPo.notes}
                onChange={(e) => setNewPo({ ...newPo, notes: e.target.value })}
                placeholder="Notes (optional)"
                className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
              />
            </div>
          </div>

          <p className="text-xs font-medium text-surface-500 mb-2">Items</p>
          <div className="space-y-2 mb-3">
            {newPo.items.map((item, i) => (
              <div key={i} className="flex gap-2 items-center">
                <select
                  aria-label={`Inventory item for purchase order line ${i + 1}`}
                  value={item.inventory_item_id}
                  disabled={inventoryLoading}
                  onChange={(e) => {
                    const invId = e.target.value ? Number(e.target.value) : ('' as const);
                    const found = typeof invId === 'number'
                      ? inventoryItems.find((it) => it.id === invId)
                      : undefined;
                    updateItem(i, {
                      inventory_item_id: invId,
                      cost_price: found ? found.cost_price : item.cost_price,
                    });
                  }}
                  className="flex-1 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 disabled:opacity-50"
                >
                  {inventoryLoading
                    ? <option disabled>Loading…</option>
                    : <option value="">Select inventory item…</option>
                  }
                  {inventoryItems.map((it) => (
                    <option key={it.id} value={it.id}>
                      {it.name}{it.sku ? ` (${it.sku})` : ''}
                    </option>
                  ))}
                </select>
                <input
                  aria-label={`Quantity for purchase order line ${i + 1}`}
                  type="number"
                  min="1"
                  value={item.quantity_ordered}
                  onChange={(e) => updateItem(i, { quantity_ordered: parseInt(e.target.value) || 1 })}
                  className="w-20 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                  placeholder="Qty"
                />
                <input
                  aria-label={`Unit cost for purchase order line ${i + 1}`}
                  type="number"
                  step="0.01"
                  min="0"
                  value={item.cost_price || ''}
                  onChange={(e) => updateItem(i, { cost_price: parseFloat(e.target.value) || 0 })}
                  className="w-28 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                  placeholder="Unit cost"
                />
                <DefectWarningChip inventoryItemId={item.inventory_item_id} />
                {newPo.items.length > 1 && (
                  <button onClick={() => removeItem(i)} aria-label={`Remove purchase order line ${i + 1}`} className="text-red-400 hover:text-red-600 text-xs">
                    Remove
                  </button>
                )}
              </div>
            ))}
          </div>

          <div className="flex gap-2">
            <button onClick={addItem} className="text-xs text-primary-600 hover:underline">
              + Add Item
            </button>
            <div className="ml-auto flex gap-2">
              <button
                onClick={() => {
                  setShowCreate(false);
                  setNewPo({ supplier_id: '', expected_date: '', notes: '', items: [{ ...EMPTY_ITEM }] });
                }}
                className="px-3 py-1.5 text-sm text-surface-500"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={async () => {
                  const hasZeroCost = newPo.items.some(
                    (i) => typeof i.inventory_item_id === 'number' && i.inventory_item_id > 0 && i.cost_price === 0,
                  );
                  if (hasZeroCost) {
                    const ok = await confirm(
                      'Submit with $0 line items?',
                      { title: 'Submit purchase order?', confirmLabel: 'Submit' },
                    );
                    if (!ok) return;
                  }
                  createMut.mutate();
                }}
                disabled={!canSubmit || createMut.isPending}
                aria-describedby={createDisabledReason ? 'po-create-help' : undefined}
                className="px-4 py-1.5 text-sm bg-primary-600 text-on-primary rounded-lg hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                {createMut.isPending ? <Loader2 className="h-4 w-4 animate-spin inline" /> : 'Create PO'}
              </button>
            </div>
          </div>
          {createDisabledReason && (
            <p id="po-create-help" className="mt-2 text-xs text-amber-600 dark:text-amber-400">
              {createDisabledReason}
            </p>
          )}
        </div>
      )}

      <div className="mb-4 flex flex-col gap-2 sm:flex-row sm:items-center">
        <div className="relative flex-1 sm:max-w-md">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
          <input
            type="search"
            value={searchInput}
            onChange={(e) => {
              setSearchInput(e.target.value);
              setPage(1);
            }}
            placeholder="Search PO # or supplier..."
            autoCapitalize="off"
            autoCorrect="off"
            spellCheck={false}
            aria-label="Search purchase orders by PO number or supplier"
            className="w-full rounded-lg border border-surface-200 bg-white py-2 pl-10 pr-9 text-sm text-surface-900 placeholder:text-surface-400 transition-colors focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          />
          {searchInput && (
            <button
              type="button"
              onClick={() => {
                setSearchInput('');
                setPage(1);
              }}
              aria-label="Clear purchase order search"
              className="absolute right-2 top-1/2 -translate-y-1/2 rounded p-1 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
        <select
          aria-label="Filter purchase orders by status"
          value={statusFilter}
          onChange={(e) => {
            setStatusFilter(e.target.value);
            setPage(1);
          }}
          className="rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 transition-colors focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
        >
          <option value="">All statuses</option>
          {PO_STATUS_OPTIONS.map((status) => (
            <option key={status} value={status}>{status.charAt(0).toUpperCase() + status.slice(1)}</option>
          ))}
        </select>
      </div>

      {/* List — WEB-W3-010: rows are expandable for line-item view */}
      <div className="card overflow-x-auto">
        <table className="w-full text-sm text-left">
          <thead className="bg-surface-50 dark:bg-surface-800/50">
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 font-medium text-surface-500">PO #</th>
              <th className="px-4 py-3 font-medium text-surface-500">Supplier</th>
              <th className="px-4 py-3 font-medium text-surface-500">Status</th>
              <th className="px-4 py-3 font-medium text-surface-500">Items</th>
              <th className="px-4 py-3 font-medium text-surface-500 text-right">Total</th>
              <th className="px-4 py-3 font-medium text-surface-500">Created</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
            {isLoading ? (
              <tr>
                <td colSpan={6} className="text-center py-12">
                  <Loader2 className="h-6 w-6 animate-spin text-surface-400 mx-auto" />
                </td>
              </tr>
            ) : orders.length === 0 ? (
              <tr>
                <td colSpan={6} className="text-center py-12">
                  <Package className="h-12 w-12 text-surface-300 dark:text-surface-600 mx-auto mb-3" />
                  <p className="text-sm font-medium text-surface-500 dark:text-surface-400">
                    {hasListFilters ? 'No purchase orders match your filters' : 'No purchase orders yet'}
                  </p>
                  <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
                    {hasListFilters
                      ? 'Try another PO #, supplier, or status.'
                      : 'Create a purchase order to track parts and supplies from your suppliers.'}
                  </p>
                </td>
              </tr>
            ) : (
              orders.map((po: Record<string, unknown>) => (
                <PoDetailRow
                  key={po.id as number}
                  po={po}
                  onReceive={(po, items) => setReceiveModal({ po, items })}
                />
              ))
            )}
          </tbody>
        </table>

        {(pagination.total_pages as number) > 1 && (
          <div className="flex items-center justify-between border-t border-surface-200 dark:border-surface-700 px-4 py-3">
            <p className="text-sm text-surface-500">
              Page {page} of {pagination.total_pages}
            </p>
            <div className="flex gap-1">
              <button
                aria-label="Previous page"
                disabled={page <= 1}
                onClick={() => setPage(page - 1)}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              <button
                aria-label="Next page"
                disabled={page >= (pagination.total_pages as number)}
                onClick={() => setPage(page + 1)}
                className="inline-flex items-center justify-center rounded-lg text-surface-500 hover:bg-surface-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none min-h-[44px] min-w-[44px] md:min-h-[32px] md:min-w-[32px] md:p-1.5"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          </div>
        )}
      </div>

      {/* WEB-W3-003: Receive modal */}
      {receiveModal && (
        <ReceiveModal
          poId={receiveModal.po.id as number}
          poOrderId={(receiveModal.po.order_id as string) || `PO-${receiveModal.po.id}`}
          items={receiveModal.items}
          onClose={() => setReceiveModal(null)}
          onSuccess={() => {
            queryClient.invalidateQueries({ queryKey: ['purchase-orders'] });
            queryClient.invalidateQueries({ queryKey: ['purchase-order-detail', receiveModal.po.id] });
            queryClient.invalidateQueries({ queryKey: ['inventory'] });
            queryClient.invalidateQueries({ queryKey: ['pos-products'] });
          }}
        />
      )}
    </div>
  );
}
