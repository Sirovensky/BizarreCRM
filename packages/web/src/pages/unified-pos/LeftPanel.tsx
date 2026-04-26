import { useState, useRef, useMemo, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Barcode, Plus, Minus, Trash2, ShoppingCart, X, User, Ticket, Package, ChevronLeft, ChevronRight, UserSearch, type LucideIcon } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, ticketApi, customerApi, inventoryApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useUnifiedPosStore } from './store';
import { CustomerSelector } from './CustomerSelector';
import { genId } from './types';
import { useDefaultTaxRate } from '@/hooks/useDefaultTaxRate';
import { computePosTotals } from './totals';
import type { CartItem, RepairCartItem, ProductCartItem, MiscCartItem } from './types';

// ─── Local payload shapes ──────────────────────────────────────────
// WEB-FB-003 (FIXED-by-Fixer-A23 2026-04-25): replace the four `any`
// casts in this file (parts mapper x2, customer search row, product
// search row, barcode lookup) with narrow local types. These mirror the
// fields the file actually reads from the API response so a server
// rename (e.g. `is_default` -> `default`, `item_sku` -> `sku`) becomes
// a TypeScript error instead of a silent runtime undefined.
interface ApiTicketPart {
  inventory_item_id: number;
  item_name?: string | null;
  item_sku?: string | null;
  quantity: number;
  price: number;
  status?: string | null;
}

interface ApiCustomerRow {
  id: number;
  first_name: string;
  last_name: string;
  phone?: string | null;
  mobile?: string | null;
  email?: string | null;
  organization?: string | null;
  group_name?: string | null;
  group_discount_pct?: number | null;
  group_discount_type?: string | null;
  group_auto_apply?: boolean | null;
}

interface ApiProductRow {
  id: number;
  name: string;
  sku?: string | null;
  retail_price?: number | null;
  price?: number | null;
  in_stock?: number | null;
  item_type?: string | null;
  tax_inclusive?: boolean | null;
}

// ─── Unified Search Bar ────────────────────────────────────────────

function UnifiedSearchBar() {
  const [input, setInput] = useState('');
  const [focused, setFocused] = useState(false);
  const [results, setResults] = useState<{ type: string; label: string; sub?: string; action: () => void }[]>([]);
  const { setCustomer, customer, addProduct, addRepair, clearCart } = useUnifiedPosStore();
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  // WEB-FH-003: single-fire guard. Enter-keydown and onMouseDown can BOTH
  // resolve to `results[0].action()` in the same tick (Enter while a touch
  // is mid-down, or a barcode scanner emitting chars+Enter). Without this
  // ref the action runs twice — second cart row, double API call. The
  // 250 ms cooldown matches the input-debounce so legitimate fast scans
  // still register as separate actions when the input is also cleared.
  const actionInFlightRef = useRef(false);
  const fireOnce = (fn: () => void) => {
    if (actionInFlightRef.current) return;
    actionInFlightRef.current = true;
    try { fn(); } finally {
      setTimeout(() => { actionInFlightRef.current = false; }, 250);
    }
  };

  useEffect(() => {
    if (!input.trim()) { setResults([]); return; }
    let isCancelled = false;
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(async () => {
      const q = input.trim();
      const items: typeof results = [];

      // Check if it looks like a ticket ID
      const ticketMatch = q.match(/^T?-?(\d+)$/i);
      if (ticketMatch) {
        items.push({
          type: 'ticket',
          label: `Load Ticket T-${ticketMatch[1].padStart(4, '0')}`,
          action: async () => {
            try {
              const res = await ticketApi.get(parseInt(ticketMatch[1]));
              const ticket = res.data?.data;
              if (!ticket) { toast.error('Ticket not found'); return; }
              clearCart();
              if (ticket.customer) {
                setCustomer({
                  id: ticket.customer.id,
                  first_name: ticket.customer.first_name,
                  last_name: ticket.customer.last_name,
                  phone: ticket.customer.phone,
                  mobile: ticket.customer.mobile,
                  email: ticket.customer.email,
                  organization: ticket.customer.organization ?? null,
                  group_name: ticket.customer.group_name,
                  group_discount_pct: ticket.customer.group_discount_pct,
                  group_discount_type: ticket.customer.group_discount_type,
                  group_auto_apply: ticket.customer.group_auto_apply,
                });
              }
              for (const device of ticket.devices ?? []) {
                const parts = ((device.parts ?? []) as ApiTicketPart[]).map((p) => ({
                  _key: genId(),
                  inventory_item_id: p.inventory_item_id,
                  name: p.item_name || `Part #${p.inventory_item_id}`,
                  sku: p.item_sku || null,
                  quantity: p.quantity,
                  price: p.price,
                  taxable: true,
                  status: p.status || 'available',
                }));
                addRepair({
                  type: 'repair',
                  id: genId(),
                  device: {
                    device_type: device.device_type || '',
                    device_name: device.device_name || '',
                    device_model_id: device.device_model_id ?? null,
                    imei: device.imei || '',
                    serial: device.serial || '',
                    security_code: device.security_code || '',
                    color: device.color || '',
                    network: device.network || '',
                    pre_conditions: device.pre_conditions || [],
                    additional_notes: device.additional_notes || '',
                    device_location: device.device_location || '',
                    warranty: !!device.warranty,
                    warranty_days: device.warranty_days || 0,
                  },
                  serviceName: device.service?.name || 'Service/Labor',
                  repairServiceId: device.service_id ?? null,
                  selectedGradeId: null,
                  laborPrice: device.price || 0,
                  lineDiscount: device.line_discount || 0,
                  parts,
                  taxable: false,
                });
              }
              toast.success(`Loaded ticket T-${ticketMatch[1].padStart(4, '0')}`);
              if (!isCancelled) { setInput(''); setResults([]); }
            } catch { toast.error('Failed to load ticket'); }
          },
        });
      }

      // WEB-FH-017 (Fixer-B18 2026-04-25): bail out after each await if a
      // newer debounced tick has run. Without these checks tick N's slow
      // customer-search Promise resolves AFTER tick N+1's products call, and
      // both branches push into the SAME `items` array — the dropdown ends
      // up showing customers from "John" alongside products from "Johnsten".
      // Search customers
      try {
        const custRes = await customerApi.search(q);
        if (isCancelled) return;
        const customers = custRes.data?.data?.customers || custRes.data?.data || [];
        for (const c of (customers as ApiCustomerRow[]).slice(0, 3)) {
          items.push({
            type: 'customer',
            label: `${c.first_name} ${c.last_name}`,
            sub: c.mobile || c.phone || c.email,
            action: () => {
              setCustomer(c);
              if (!isCancelled) { setInput(''); setResults([]); }
            },
          });
        }
      } catch {
        // Search failed — handled by empty results
      }
      if (isCancelled) return;

      // Search products/inventory by name or SKU
      try {
        const prodRes = await posApi.products({ keyword: q });
        if (isCancelled) return;
        const prods = prodRes.data?.data?.items || [];
        for (const p of (prods as ApiProductRow[]).slice(0, 3)) {
          items.push({
            type: 'product',
            label: p.name,
            sub: p.sku ? `SKU: ${p.sku}` : undefined,
            action: () => {
              // WEB-FH-004: pass stock cap to the store. Service-type rows
              // have no `in_stock`, so skip the clamp.
              const isService = p.item_type === 'service';
              const stockCap = isService ? undefined : Number(p.in_stock ?? 0);
              if (stockCap === 0 && !isService) {
                toast.error(`${p.name} is out of stock`);
                return;
              }
              addProduct({
                type: 'product', id: genId(), inventoryItemId: p.id,
                name: p.name, sku: p.sku || null, quantity: 1,
                unitPrice: p.retail_price ?? p.price ?? 0,
                taxable: true, taxInclusive: !!p.tax_inclusive,
              }, { stockCap });
              if (!isCancelled) { setInput(''); setResults([]); }
              toast.success(`Added ${p.name}`);
            },
          });
        }
      } catch {
        // Search failed — handled by empty results
      }

      if (!isCancelled) setResults(items);
    }, 250);
    return () => { isCancelled = true; clearTimeout(debounceRef.current); };
  }, [input]); // intentional: debounced search triggers on input change, API fns and store actions are stable

  // WEB-FB-016: typed map so an unknown `r.type` is a build-time signal
  // rather than a silently-rendered nothing.
  const iconMap: Record<'ticket' | 'customer' | 'product', LucideIcon> = {
    ticket: Ticket,
    customer: User,
    product: Package,
  };

  return (
    <div className="relative">
      {customer ? (
        <div className="flex items-center justify-between rounded-lg border border-primary-300 dark:border-primary-700 bg-primary-50 dark:bg-primary-950/30 px-4 py-3">
          <div className="flex items-center gap-3">
            <div className="h-9 w-9 rounded-full bg-primary-100 dark:bg-primary-900/40 flex items-center justify-center">
              <User className="h-5 w-5 text-primary-600 dark:text-primary-400" />
            </div>
            <div className="min-w-0 flex-1">
              <span className="text-base font-bold text-surface-900 dark:text-surface-100 block truncate">{customer.first_name} {customer.last_name}</span>
              {(customer.mobile || customer.phone) && (
                <p className="text-xs text-surface-500 dark:text-surface-400 truncate">{customer.mobile || customer.phone}</p>
              )}
              {customer.email && (
                <p className="text-xs text-surface-400 dark:text-surface-500 truncate">{customer.email}</p>
              )}
              {customer.organization && (
                <p className="text-xs text-primary-600 dark:text-primary-400 truncate">{customer.organization}</p>
              )}
            </div>
          </div>
          <button onClick={() => setCustomer(null)} className="p-1.5 rounded-md text-surface-400 hover:text-red-500 hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors">
            <X className="h-4 w-4" />
          </button>
        </div>
      ) : (
        <>
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input
            ref={inputRef}
            // WEB-FL-004 (Fixer-RRR 2026-04-25): F4 hotkey targets this attr
            // to focus the customer/ticket search from the POS keyboard hook.
            data-pos-customer-search="true"
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onFocus={() => setFocused(true)}
            onBlur={() => setTimeout(() => setFocused(false), 200)}
            placeholder="Search ticket, customer, product, or scan barcode..."
            className={cn(
              'w-full rounded-lg border border-surface-200 dark:border-surface-700',
              'bg-white dark:bg-surface-800 pl-9 pr-3 py-2 text-sm',
              'text-surface-900 dark:text-surface-100 placeholder:text-surface-400',
              'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/30 focus-visible:border-primary-500',
            )}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && results.length > 0) {
                // WEB-FH-003: guard against Enter+Click race firing the
                // same action twice.
                fireOnce(() => results[0].action());
              }
            }}
          />
        </>
      )}
      {focused && results.length > 0 && !customer && (
        <div className="absolute left-0 right-0 top-full z-50 mt-1 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800 overflow-hidden">
          {results.map((r, i) => {
            const Icon = iconMap[r.type as keyof typeof iconMap] ?? Search;
            return (
              <button
                key={i}
                // WEB-FH-003: same fireOnce guard so a click during the
                // Enter-keydown window doesn't double-fire.
                onMouseDown={(e) => { e.preventDefault(); fireOnce(() => r.action()); }}
                className="flex w-full items-center gap-3 px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
              >
                <Icon className="h-4 w-4 shrink-0 text-surface-400" />
                <div className="min-w-0 flex-1">
                  <span className="font-medium text-surface-800 dark:text-surface-200">{r.label}</span>
                  {r.sub && <span className="ml-2 text-xs text-surface-400">{r.sub}</span>}
                </div>
                <span className="shrink-0 rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-medium uppercase text-surface-500 dark:bg-surface-700">
                  {r.type}
                </span>
              </button>
            );
          })}
        </div>
      )}
    </div>
  );
}

// ─── Ticket ID Search ───────────────────────────────────────────────

function TicketSearch() {
  const [ticketInput, setTicketInput] = useState('');
  const { setCustomer, addRepair, clearCart } = useUnifiedPosStore();

  const handleLoad = async () => {
    const raw = ticketInput.trim().replace(/^T-/i, '');
    const id = parseInt(raw, 10);
    if (!id || isNaN(id)) {
      toast.error('Enter a valid Ticket ID (e.g. T-1234 or 1234)');
      return;
    }
    try {
      const res = await ticketApi.get(id);
      const ticket = res.data?.data;
      if (!ticket) { toast.error('Ticket not found'); return; }

      clearCart();

      // Set customer
      if (ticket.customer) {
        setCustomer({
          id: ticket.customer.id,
          first_name: ticket.customer.first_name,
          last_name: ticket.customer.last_name,
          phone: ticket.customer.phone,
          mobile: ticket.customer.mobile,
          email: ticket.customer.email,
          organization: ticket.customer.organization ?? null,
          group_name: ticket.customer.group_name,
          group_discount_pct: ticket.customer.group_discount_pct,
          group_discount_type: ticket.customer.group_discount_type,
          group_auto_apply: ticket.customer.group_auto_apply,
        });
      }

      // Add each device as a repair cart item
      for (const device of ticket.devices ?? []) {
        const parts = ((device.parts ?? []) as ApiTicketPart[]).map((p) => ({
          _key: genId(),
          inventory_item_id: p.inventory_item_id,
          name: p.item_name || `Part #${p.inventory_item_id}`,
          sku: p.item_sku || null,
          quantity: p.quantity,
          price: p.price,
          taxable: true,
          status: p.status || 'available',
        }));

        addRepair({
          type: 'repair',
          id: genId(),
          device: {
            device_type: device.device_type || '',
            device_name: device.device_name || '',
            device_model_id: device.device_model_id ?? null,
            imei: device.imei || '',
            serial: device.serial || '',
            security_code: device.security_code || '',
            color: device.color || '',
            network: device.network || '',
            pre_conditions: device.pre_conditions || [],
            additional_notes: device.additional_notes || '',
            device_location: device.device_location || '',
            warranty: !!device.warranty,
            warranty_days: device.warranty_days || 0,
          },
          serviceName: device.service?.name || 'Service/Labor',
          repairServiceId: device.service_id ?? null,
          selectedGradeId: null,
          laborPrice: device.price || 0,
          lineDiscount: device.line_discount || 0,
          parts,
          taxable: false, // labor is non-taxable by default
        });
      }

      toast.success(`Loaded ticket T-${String(id).padStart(4, '0')}`);
      setTicketInput('');
    } catch {
      toast.error('Failed to load ticket');
    }
  };

  return (
    <div className="relative">
      <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
      <input
        type="text"
        value={ticketInput}
        onChange={(e) => setTicketInput(e.target.value)}
        onKeyDown={(e) => { if (e.key === 'Enter') handleLoad(); }}
        placeholder="Scan or enter Ticket ID"
        className={cn(
          'w-full rounded-lg border border-surface-200 dark:border-surface-700',
          'bg-white dark:bg-surface-800 pl-9 pr-3 py-1.5 text-sm',
          'text-surface-900 dark:text-surface-100 placeholder:text-surface-400',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/30 focus-visible:border-primary-500',
          'transition-colors',
        )}
      />
    </div>
  );
}

// ─── Barcode / SKU Search ───────────────────────────────────────────

function BarcodeSearch() {
  const { addProduct } = useUnifiedPosStore();
  const inputRef = useRef<HTMLInputElement>(null);
  // WEB-FH-003: rapid scanner emissions or Enter held down by an old
  // imaging gun can trigger overlapping handleKey calls — without a guard
  // the same barcode adds twice. Lock per scan; the lock releases on
  // completion (success, miss, or error).
  const scanInFlightRef = useRef(false);

  const handleKey = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    const code = (e.target as HTMLInputElement).value.trim();
    if (!code) return;
    if (scanInFlightRef.current) return;
    scanInFlightRef.current = true;

    try {
      const res = await posApi.products({ keyword: code });
      const found = res.data?.data?.items?.[0] as ApiProductRow | undefined;
      if (found) {
        // WEB-FH-004: clamp at available stock for non-service items.
        const isService = found.item_type === 'service';
        const stockCap = isService ? undefined : Number(found.in_stock ?? 0);
        if (stockCap === 0 && !isService) {
          toast.error(`${found.name} is out of stock`);
        } else {
          // Pre-check the cap against existing cart qty so the cashier
          // sees a clear toast instead of a silent clamp.
          const cartItems = useUnifiedPosStore.getState().cartItems;
          const existing = cartItems.find(
            (c) => c.type === 'product' && c.inventoryItemId === found.id,
          );
          const existingQty = existing && existing.type === 'product' ? existing.quantity : 0;
          if (stockCap != null && existingQty + 1 > stockCap) {
            toast.error(`Only ${stockCap} of "${found.name}" in stock`);
          } else {
            addProduct({
              type: 'product',
              id: genId(),
              inventoryItemId: found.id,
              name: found.name,
              sku: found.sku || null,
              quantity: 1,
              unitPrice: found.retail_price ?? found.price ?? 0,
              taxable: true,
              taxInclusive: !!found.tax_inclusive,
            }, { stockCap });
          }
        }
        if (inputRef.current) inputRef.current.value = '';
      } else {
        toast.error(`No item found for: ${code}`);
      }
    } catch {
      toast.error('Product search failed');
    } finally {
      scanInFlightRef.current = false;
    }
  };

  return (
    <div className="relative">
      <Barcode className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
      <input
        ref={inputRef}
        type="text"
        onKeyDown={handleKey}
        placeholder="Enter item name, SKU or scan barcode"
        className={cn(
          'w-full rounded-lg border border-surface-200 dark:border-surface-700',
          'bg-white dark:bg-surface-800 pl-9 pr-3 py-1.5 text-sm',
          'text-surface-900 dark:text-surface-100 placeholder:text-surface-400',
          'focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/30 focus-visible:border-primary-500',
          'transition-colors',
        )}
      />
    </div>
  );
}

// ─── Cart Item Rows ─────────────────────────────────────────────────

function RepairRow({ item, taxRate }: { item: RepairCartItem; taxRate: number }) {
  const { removeCartItem, updateCartItem } = useUnifiedPosStore();
  const partsTotal = item.parts.reduce((s, p) => s + p.quantity * p.price, 0);
  const lineTotal = item.laborPrice - item.lineDiscount + partsTotal;

  // Inline "Add part" state
  const [showPartSearch, setShowPartSearch] = useState(false);
  const [partQuery, setPartQuery] = useState('');

  const { data: partResults } = useQuery({
    queryKey: ['part-search-inline', partQuery],
    queryFn: async () => {
      const res = await inventoryApi.list({ keyword: partQuery, pagesize: 8, item_type: 'part' });
      return (res.data?.data?.items ?? []) as Array<{ id: number; name: string; sku?: string | null; retail_price?: number }>;
    },
    enabled: partQuery.length >= 2,
    staleTime: 10_000,
  });

  const addPartToItem = (part: { id: number; name: string; sku?: string | null; retail_price?: number }) => {
    const existing = item.parts.find((p) => p.inventory_item_id === part.id);
    const newParts = existing
      ? item.parts.map((p) =>
          p.inventory_item_id === part.id ? { ...p, quantity: p.quantity + 1 } : p,
        )
      : [
          ...item.parts,
          {
            _key: genId(),
            inventory_item_id: part.id,
            name: part.name,
            sku: part.sku ?? null,
            quantity: 1,
            price: part.retail_price ?? 0,
            taxable: true,
            status: 'available' as const,
          },
        ];
    updateCartItem(item.id, { parts: newParts } as Partial<RepairCartItem>);
    // Advance checkout tutorial when a part is added.
    window.dispatchEvent(new CustomEvent('pos:part-added'));
    setPartQuery('');
    setShowPartSearch(false);
    toast.success(`Added: ${part.name}`);
  };

  const toggleLaborTax = () => {
    updateCartItem(item.id, { taxable: !item.taxable } as Partial<RepairCartItem>);
  };

  const togglePartTax = (partKey: string) => {
    const newParts = item.parts.map(p =>
      p._key === partKey ? { ...p, taxable: !p.taxable } : p
    );
    updateCartItem(item.id, { parts: newParts } as Partial<RepairCartItem>);
  };

  return (
    <div className="border-b border-surface-100 dark:border-surface-700/50 pb-2 mb-2 last:border-0 last:pb-0 last:mb-0">
      <div className="flex items-start gap-2">
        <span className="shrink-0 mt-0.5 text-xs text-surface-400 w-8 text-center">1</span>
        <div className="min-w-0 flex-1">
          <p className="text-sm font-medium text-surface-900 dark:text-surface-100 leading-tight">
            {item.device.device_name}
          </p>
          <p className="text-xs text-surface-500 dark:text-surface-400 leading-tight">
            {item.serviceName}
          </p>
          {item.lineDiscount > 0 && (
            <p className="text-[11px] text-green-600 dark:text-green-400">
              Discount: -${item.lineDiscount.toFixed(2)}
            </p>
          )}
        </div>
        <input
          type="text" inputMode="decimal" pattern="[0-9.]*"
          data-tutorial-target="checkout:price-cell"
          value={item.laborPrice}
          onChange={(e) => {
            // WEB-FH-015 (Fixer-B2 2026-04-25): the input has min="0" but
            // that's HTML5 form-validation only — typing or pasting "-50"
            // sets state to a negative number, which silently subtracts
            // from the cart total (and the train-mode/free-pricing path
            // never re-validates). Clamp at parse time.
            const parsed = parseFloat(e.target.value);
            const safe = Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
            updateCartItem(item.id, { laborPrice: safe } as Partial<RepairCartItem>);
          }}
          className="shrink-0 w-16 rounded border border-surface-200 dark:border-surface-700 bg-transparent px-1 py-0.5 text-right text-xs text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
          step="0.01"
          min="0"
        />
        <button
          onClick={toggleLaborTax}
          aria-label={item.taxable ? 'Labor taxable — click to remove tax' : 'Labor non-taxable — click to add tax'}
          aria-pressed={item.taxable}
          className={cn(
            'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
            item.taxable
              ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
              : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
          )}
          title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
        >
          {item.taxable ? '$' + (item.laborPrice * taxRate).toFixed(2) : 'No tax'}
        </button>
        <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
          ${lineTotal.toFixed(2)}
        </span>
        <button
          onClick={() => removeCartItem(item.id)}
          aria-label={`Remove ${item.device.device_name || item.serviceName} from cart`}
          className="shrink-0 p-1 text-red-400 hover:text-red-600 dark:hover:text-red-300 transition-colors"
          title="Remove"
        >
          <Trash2 className="h-3.5 w-3.5" />
        </button>
      </div>
      {item.parts.length > 0 && (
        <div className="ml-10 mt-1 space-y-0.5">
          {item.parts.map((p) => (
            <div key={p._key} className="flex items-center text-[11px] text-surface-500 dark:text-surface-400">
              <span className="flex-1 truncate">
                {p.quantity > 1 ? `${p.quantity}x ` : ''}{p.name}
              </span>
              <span className="w-14 text-right">${(p.quantity * p.price).toFixed(2)}</span>
              <button
                onClick={() => togglePartTax(p._key)}
                aria-label={p.taxable ? `${p.name} taxable — click to remove tax` : `${p.name} non-taxable — click to add tax`}
                aria-pressed={p.taxable}
                className={cn(
                  'w-14 text-right rounded px-0.5 transition-colors cursor-pointer',
                  p.taxable
                    ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
                    : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
                )}
                title={p.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
              >
                {p.taxable ? '$' + (p.quantity * p.price * taxRate).toFixed(2) : 'No tax'}
              </button>
              <span className="w-16" />
              <span className="w-6" />
            </div>
          ))}
        </div>
      )}

      {/* Add part inline */}
      <div className="ml-10 mt-1">
        {!showPartSearch ? (
          <button
            type="button"
            data-tutorial-target="checkout:add-part-button"
            onClick={() => setShowPartSearch(true)}
            className="flex items-center gap-1 text-[11px] font-medium text-primary-600 dark:text-primary-400 hover:underline"
          >
            <Plus className="h-3 w-3" /> Add part
          </button>
        ) : (
          <div className="mt-1 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-sm">
            <div className="flex items-center gap-1 px-2 py-1 border-b border-surface-100 dark:border-surface-700">
              <Search className="h-3 w-3 text-surface-400 shrink-0" />
              <input
                type="text"
                value={partQuery}
                onChange={(e) => setPartQuery(e.target.value)}
                placeholder="Search inventory parts…"
                className="flex-1 text-xs bg-transparent text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400"
                autoFocus
              />
              <button
                type="button"
                onClick={() => { setShowPartSearch(false); setPartQuery(''); }}
                className="p-0.5 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
            {partQuery.length >= 2 && (
              <ul className="max-h-40 overflow-y-auto">
                {(partResults ?? []).length === 0 ? (
                  <li className="px-2 py-1.5 text-xs text-surface-400 text-center">No parts found</li>
                ) : (
                  (partResults ?? []).map((part) => (
                    <li key={part.id}>
                      <button
                        type="button"
                        onClick={() => addPartToItem(part)}
                        className="w-full flex items-center gap-2 px-2 py-1.5 text-left hover:bg-surface-50 dark:hover:bg-surface-700/50"
                      >
                        <span className="flex-1 text-xs text-surface-900 dark:text-surface-100 truncate">{part.name}</span>
                        {part.retail_price != null && (
                          <span className="text-xs text-surface-500 shrink-0">${part.retail_price.toFixed(2)}</span>
                        )}
                      </button>
                    </li>
                  ))
                )}
              </ul>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

function ProductRow({ item, taxRate }: { item: ProductCartItem; taxRate: number }) {
  const { updateProductQty, updateCartItem, removeCartItem } = useUnifiedPosStore();

  return (
    <div className="flex items-center gap-2 border-b border-surface-100 dark:border-surface-700/50 pb-2 mb-2 last:border-0 last:pb-0 last:mb-0">
      <div className="shrink-0 flex items-center gap-1 w-8">
        <button aria-label="Decrease quantity" onClick={() => updateProductQty(item.id, -1)} className="p-0.5 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 transition-colors">
          <Minus className="h-3 w-3" />
        </button>
        <span className="text-xs text-surface-700 dark:text-surface-300 min-w-[16px] text-center">{item.quantity}</span>
        <button aria-label="Increase quantity" onClick={() => updateProductQty(item.id, 1)} className="p-0.5 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 transition-colors">
          <Plus className="h-3 w-3" />
        </button>
      </div>
      <div className="min-w-0 flex-1">
        <p className="text-sm text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
        {item.sku && <p className="text-[10px] text-surface-400 truncate">{item.sku}</p>}
      </div>
      <input
        type="text" inputMode="decimal" pattern="[0-9.]*"
        value={item.unitPrice}
        onChange={(e) => {
          // WEB-FH-015 (Fixer-B2 2026-04-25): clamp negative input — see
          // matching laborPrice handler above.
          const parsed = parseFloat(e.target.value);
          const safe = Number.isFinite(parsed) && parsed > 0 ? parsed : 0;
          updateCartItem(item.id, { unitPrice: safe } as Partial<ProductCartItem>);
        }}
        className="w-14 rounded border border-surface-200 dark:border-surface-700 bg-transparent px-1 py-0.5 text-right text-xs text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 focus-visible:border-primary-400"
        step="0.01"
        min="0"
      />
      <button
        onClick={() => updateCartItem(item.id, { taxable: !item.taxable } as Partial<ProductCartItem>)}
        aria-label={item.taxable ? `${item.name} taxable — click to remove tax` : `${item.name} non-taxable — click to add tax`}
        aria-pressed={item.taxable}
        className={cn(
          'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
          item.taxable && !item.taxInclusive
            ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
            : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
        )}
        title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
      >
        {item.taxable && !item.taxInclusive
          ? '$' + (item.quantity * item.unitPrice * taxRate).toFixed(2)
          : 'No tax'}
      </button>
      <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
        ${(item.quantity * item.unitPrice).toFixed(2)}
      </span>
      <button
        onClick={() => removeCartItem(item.id)}
        aria-label={`Remove ${item.name} from cart`}
        className="shrink-0 p-1 text-red-400 hover:text-red-600 dark:hover:text-red-300 transition-colors"
        title="Remove"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

function MiscRow({ item, taxRate }: { item: MiscCartItem; taxRate: number }) {
  const { removeCartItem, updateCartItem } = useUnifiedPosStore();

  return (
    <div className="flex items-center gap-2 border-b border-surface-100 dark:border-surface-700/50 pb-2 mb-2 last:border-0 last:pb-0 last:mb-0">
      <span className="shrink-0 text-xs text-surface-400 w-8 text-center">{item.quantity}</span>
      <p className="min-w-0 flex-1 text-sm text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
      <span className="shrink-0 text-xs text-surface-500 dark:text-surface-400 w-14 text-right">
        ${item.unitPrice.toFixed(2)}
      </span>
      <button
        onClick={() => updateCartItem(item.id, { taxable: !item.taxable } as Partial<MiscCartItem>)}
        aria-label={item.taxable ? `${item.name} taxable — click to remove tax` : `${item.name} non-taxable — click to add tax`}
        aria-pressed={item.taxable}
        className={cn(
          'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
          item.taxable
            ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
            : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
        )}
        title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
      >
        {item.taxable ? '$' + (item.quantity * item.unitPrice * taxRate).toFixed(2) : 'No tax'}
      </button>
      <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
        ${(item.quantity * item.unitPrice).toFixed(2)}
      </span>
      <button
        onClick={() => removeCartItem(item.id)}
        aria-label={`Remove ${item.name} from cart`}
        className="shrink-0 p-1 text-red-400 hover:text-red-600 dark:hover:text-red-300 transition-colors"
        title="Remove"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

function CartItemRow({ item, taxRate }: { item: CartItem; taxRate: number }) {
  switch (item.type) {
    case 'repair':  return <RepairRow item={item} taxRate={taxRate} />;
    case 'product': return <ProductRow item={item} taxRate={taxRate} />;
    case 'misc':    return <MiscRow item={item} taxRate={taxRate} />;
  }
}

// ─── Totals ─────────────────────────────────────────────────────────

interface Totals {
  itemCount: number;
  subtotal: number;
  discountAmount: number;
  tax: number;
  total: number;
}

function useTotals(): Totals {
  const { cartItems, discount, customer, memberDiscountApplied } = useUnifiedPosStore();
  const taxRate = useDefaultTaxRate();

  // WEB-FH-005 (Fixer-O 2026-04-24): math moved to `./totals.ts` so this
  // panel and CheckoutModal share one cents-int implementation. Earlier
  // duplicate float pipelines could drift 1¢ between displays and disagree
  // with the server's cents-pure recompute (POS-SALES-001). Pro-rata
  // discount allocation (WEB-FH-006) is preserved inside the helper.
  return useMemo(
    () => computePosTotals({ cartItems, discount, customer, memberDiscountApplied, taxRate }),
    [cartItems, discount, customer, memberDiscountApplied, taxRate],
  );
}

// ─── LeftPanelCustomerPicker ────────────────────────────────────────
// Inline customer selection shown in the left panel when no customer is selected.

function LeftPanelCustomerPicker({ onNewCustomer }: { onNewCustomer?: () => void }) {
  return (
    <div className="flex flex-col h-full">
      <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50">
        <UserSearch className="h-4 w-4 text-surface-500" />
        <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Select Customer
        </span>
      </div>
      <div className="flex-1 overflow-y-auto px-4 py-4">
        <p className="mb-3 text-xs text-surface-400 dark:text-surface-500">
          Search for an existing customer or continue as walk-in.
        </p>
        <CustomerSelector onNewCustomer={onNewCustomer} inline />
      </div>
    </div>
  );
}

// ─── LeftPanel ──────────────────────────────────────────────────────

export function LeftPanel({ collapsed, onToggle, onNewCustomer }: { collapsed?: boolean; onToggle?: () => void; onNewCustomer?: () => void }) {
  const { cartItems, customer } = useUnifiedPosStore();
  const totals = useTotals();
  const taxRate = useDefaultTaxRate();

  // Collapsed bar
  if (collapsed) {
    return (
      <div className="flex flex-col h-full items-center py-3 px-1 gap-2">
        <button
          onClick={onToggle}
          className="flex flex-col items-center gap-1.5 rounded-lg p-2 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
          title="Expand cart"
        >
          <ShoppingCart className="h-5 w-5 text-surface-500" />
          <span className="text-[10px] font-bold text-surface-500">{cartItems.length}</span>
          <ChevronRight className="h-3.5 w-3.5 text-surface-400" />
        </button>
        {totals.total > 0 && (
          <span className="text-[10px] font-bold text-surface-700 dark:text-surface-300 writing-mode-vertical" style={{ writingMode: 'vertical-rl' }}>
            ${totals.total.toFixed(2)}
          </span>
        )}
      </div>
    );
  }

  // No customer selected and cart is empty → show inline customer picker
  if (!customer && cartItems.length === 0) {
    return <LeftPanelCustomerPicker onNewCustomer={onNewCustomer} />;
  }

  return (
    <div className="flex flex-col h-full">
      {/* Customer badge (shown when customer is set) */}
      {customer && (
        <div className="px-3 py-2 border-b border-surface-200 dark:border-surface-700 bg-primary-50/60 dark:bg-primary-900/10">
          <CustomerSelector />
        </div>
      )}

      {/* Cart header */}
      <div className="flex items-center gap-2 px-3 py-2 border-b border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50">
        {onToggle && (
          <button onClick={onToggle} className="p-0.5 rounded hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors" title="Collapse cart">
            <ChevronLeft className="h-3.5 w-3.5 text-surface-400" />
          </button>
        )}
        <ShoppingCart className="h-4 w-4 text-surface-500" />
        <span className="text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Cart
        </span>
        {cartItems.length > 0 && (
          <span className="ml-auto rounded-full bg-primary-100 dark:bg-primary-900/30 px-2 py-0.5 text-[10px] font-bold text-primary-700 dark:text-primary-400">
            {cartItems.length}
          </span>
        )}
      </div>

      {/* Column headers */}
      {cartItems.length > 0 && (
        <div className="flex items-center gap-2 px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-surface-400 border-b border-surface-100 dark:border-surface-700/50">
          <span className="w-8 text-center">QTY</span>
          <span className="flex-1">Item Name</span>
          <span className="w-14 text-right">Price</span>
          <span className="w-14 text-right">Tax</span>
          <span className="w-16 text-right">Total</span>
          <span className="w-6" />
        </div>
      )}

      {/* Cart items */}
      <div className="flex-1 overflow-y-auto px-3 py-2">
        {cartItems.length === 0 ? (
          <div className="flex flex-col items-center justify-center h-full text-center text-surface-400 dark:text-surface-500">
            <ShoppingCart className="h-10 w-10 mb-2 opacity-30" />
            <p className="text-sm">Cart is empty</p>
            <p className="text-xs mt-1">Scan a barcode, search a product, or add a repair</p>
          </div>
        ) : (
          (() => {
            // Group repair items by source ticket, keep others ungrouped
            const ticketGroups = new Map<string, RepairCartItem[]>();
            const ungrouped: CartItem[] = [];

            for (const item of cartItems) {
              if (item.type === 'repair' && item.sourceTicketId) {
                const key = item.sourceTicketOrderId || `T-${item.sourceTicketId}`;
                if (!ticketGroups.has(key)) ticketGroups.set(key, []);
                ticketGroups.get(key)!.push(item);
              } else {
                ungrouped.push(item);
              }
            }

            return (
              <>
                {Array.from(ticketGroups.entries()).map(([ticketLabel, items]) => (
                  <div key={ticketLabel} className="mb-1">
                    <div className="flex items-center gap-2 px-3 py-1.5 bg-surface-100 dark:bg-surface-800 border-b border-surface-200 dark:border-surface-700">
                      <span className="text-xs font-bold text-teal-600 dark:text-teal-400">{ticketLabel}</span>
                      <span className="text-[10px] text-surface-400">({items.length} device{items.length !== 1 ? 's' : ''})</span>
                    </div>
                    {items.map((item) => <CartItemRow key={item.id} item={item} taxRate={taxRate} />)}
                  </div>
                ))}
                {ungrouped.map((item) => <CartItemRow key={item.id} item={item} taxRate={taxRate} />)}
              </>
            );
          })()
        )}
      </div>

      {/* Totals — only show when cart has items */}
      {cartItems.length > 0 && <div className="border-t border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 px-3 py-2 space-y-0.5">
        <div className="flex justify-between text-xs text-surface-500 dark:text-surface-400">
          <span>Items</span>
          <span>{totals.itemCount}</span>
        </div>
        <div className="flex justify-between text-xs text-surface-500 dark:text-surface-400">
          <span>Subtotal</span>
          <span>${totals.subtotal.toFixed(2)}</span>
        </div>
        {totals.discountAmount > 0 && (
          <div className="flex justify-between text-xs text-green-600 dark:text-green-400">
            <span>Discount</span>
            <span>-${totals.discountAmount.toFixed(2)}</span>
          </div>
        )}
        <div className="flex justify-between text-xs text-surface-500 dark:text-surface-400">
          {/* WEB-FH-007: rate label MUST come from useDefaultTaxRate (live
              tenant config), not the legacy hardcoded "8.865%". Format with
              up to 3 fractional digits to keep precision for rates like
              7.625% or 8.875% without showing trailing zeros for "10%". */}
          <span>
            Tax ({(taxRate * 100).toLocaleString(undefined, { maximumFractionDigits: 3 })}%)
            {totals.tax === 0 && totals.subtotal > 0 ? ' \u2014 labor exempt' : ''}
          </span>
          <span>${totals.tax.toFixed(2)}</span>
        </div>
        <div className="flex justify-between text-sm font-bold text-surface-900 dark:text-surface-100 pt-1 border-t border-surface-200 dark:border-surface-700">
          <span>Total</span>
          <span>${totals.total.toFixed(2)}</span>
        </div>
      </div>}
    </div>
  );
}
