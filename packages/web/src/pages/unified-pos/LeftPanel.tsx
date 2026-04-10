import { useState, useRef, useMemo, useEffect } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Search, Barcode, Plus, Minus, Trash2, ShoppingCart, X, User, Ticket, Package, ChevronLeft, ChevronRight } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, ticketApi, customerApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { useUnifiedPosStore } from './store';
import { CustomerSelector } from './CustomerSelector';
import { TAX_RATE_FALLBACK, genId } from './types';
import type { CartItem, RepairCartItem, ProductCartItem, MiscCartItem } from './types';

// ─── Unified Search Bar ────────────────────────────────────────────

function UnifiedSearchBar() {
  const [input, setInput] = useState('');
  const [focused, setFocused] = useState(false);
  const [results, setResults] = useState<{ type: string; label: string; sub?: string; action: () => void }[]>([]);
  const { setCustomer, customer, addProduct, clearCart } = useUnifiedPosStore();
  const inputRef = useRef<HTMLInputElement>(null);
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);

  useEffect(() => {
    if (!input.trim()) { setResults([]); return; }
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
                const parts = (device.parts ?? []).map((p: any) => ({
                  _key: genId(), inventory_item_id: p.inventory_item_id,
                  name: p.item_name || `Part #${p.inventory_item_id}`,
                  sku: p.item_sku || null, quantity: p.quantity, price: p.price,
                  taxable: true, status: p.status || 'available',
                }));
                addProduct({ type: 'product', id: genId(), inventoryItemId: 0, name: `${device.device_name} - ${device.service?.name || 'Service'}`, sku: null, quantity: 1, unitPrice: device.price || 0, taxable: false, taxInclusive: false } as any);
              }
              toast.success(`Loaded ticket T-${ticketMatch[1].padStart(4, '0')}`);
              setInput('');
              setResults([]);
            } catch { toast.error('Failed to load ticket'); }
          },
        });
      }

      // Search customers
      try {
        const custRes = await customerApi.search(q);
        const customers = custRes.data?.data?.customers || custRes.data?.data || [];
        for (const c of (customers as any[]).slice(0, 3)) {
          items.push({
            type: 'customer',
            label: `${c.first_name} ${c.last_name}`,
            sub: c.mobile || c.phone || c.email,
            action: () => {
              setCustomer(c);
              setInput('');
              setResults([]);
            },
          });
        }
      } catch {
        // Search failed — handled by empty results
      }

      // Search products/inventory by name or SKU
      try {
        const prodRes = await posApi.products({ keyword: q });
        const prods = prodRes.data?.data?.items || [];
        for (const p of (prods as any[]).slice(0, 3)) {
          items.push({
            type: 'product',
            label: p.name,
            sub: p.sku ? `SKU: ${p.sku}` : undefined,
            action: () => {
              addProduct({
                type: 'product', id: genId(), inventoryItemId: p.id,
                name: p.name, sku: p.sku || null, quantity: 1,
                unitPrice: p.retail_price ?? p.price ?? 0,
                taxable: true, taxInclusive: !!p.tax_inclusive,
              });
              setInput('');
              setResults([]);
              toast.success(`Added ${p.name}`);
            },
          });
        }
      } catch {
        // Search failed — handled by empty results
      }

      setResults(items);
    }, 250);
    return () => clearTimeout(debounceRef.current);
  }, [input]); // intentional: debounced search triggers on input change, API fns and store actions are stable

  const iconMap: Record<string, any> = { ticket: Ticket, customer: User, product: Package };

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
              'focus:outline-none focus:ring-2 focus:ring-primary-500/30 focus:border-primary-500',
            )}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && results.length > 0) {
                results[0].action();
              }
            }}
          />
        </>
      )}
      {focused && results.length > 0 && !customer && (
        <div className="absolute left-0 right-0 top-full z-50 mt-1 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800 overflow-hidden">
          {results.map((r, i) => {
            const Icon = iconMap[r.type] || Search;
            return (
              <button
                key={i}
                onMouseDown={(e) => { e.preventDefault(); r.action(); }}
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
        const parts = (device.parts ?? []).map((p: any) => ({
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
          'focus:outline-none focus:ring-2 focus:ring-primary-500/30 focus:border-primary-500',
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

  const handleKey = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    const code = (e.target as HTMLInputElement).value.trim();
    if (!code) return;

    try {
      const res = await posApi.products({ keyword: code });
      const found = res.data?.data?.items?.[0];
      if (found) {
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
        });
        if (inputRef.current) inputRef.current.value = '';
      } else {
        toast.error(`No item found for: ${code}`);
      }
    } catch {
      toast.error('Product search failed');
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
          'focus:outline-none focus:ring-2 focus:ring-primary-500/30 focus:border-primary-500',
          'transition-colors',
        )}
      />
    </div>
  );
}

// ─── Cart Item Rows ─────────────────────────────────────────────────

function RepairRow({ item }: { item: RepairCartItem }) {
  const { removeCartItem, updateCartItem } = useUnifiedPosStore();
  const partsTotal = item.parts.reduce((s, p) => s + p.quantity * p.price, 0);
  const lineTotal = item.laborPrice - item.lineDiscount + partsTotal;

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
          type="number"
          value={item.laborPrice}
          onChange={(e) => updateCartItem(item.id, { laborPrice: parseFloat(e.target.value) || 0 } as Partial<RepairCartItem>)}
          className="shrink-0 w-16 rounded border border-surface-200 dark:border-surface-700 bg-transparent px-1 py-0.5 text-right text-xs text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-500"
          step="0.01"
          min="0"
        />
        <button
          onClick={toggleLaborTax}
          className={cn(
            'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
            item.taxable
              ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
              : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
          )}
          title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
        >
          {item.taxable ? '$' + (item.laborPrice * TAX_RATE_FALLBACK).toFixed(2) : 'No tax'}
        </button>
        <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
          ${lineTotal.toFixed(2)}
        </span>
        <button
          onClick={() => removeCartItem(item.id)}
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
                className={cn(
                  'w-14 text-right rounded px-0.5 transition-colors cursor-pointer',
                  p.taxable
                    ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
                    : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
                )}
                title={p.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
              >
                {p.taxable ? '$' + (p.quantity * p.price * TAX_RATE_FALLBACK).toFixed(2) : 'No tax'}
              </button>
              <span className="w-16" />
              <span className="w-6" />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

function ProductRow({ item }: { item: ProductCartItem }) {
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
        type="number"
        value={item.unitPrice}
        onChange={(e) => updateCartItem(item.id, { unitPrice: parseFloat(e.target.value) || 0 } as Partial<ProductCartItem>)}
        className="w-14 rounded border border-surface-200 dark:border-surface-700 bg-transparent px-1 py-0.5 text-right text-xs text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-500"
        step="0.01"
        min="0"
      />
      <button
        onClick={() => updateCartItem(item.id, { taxable: !item.taxable } as Partial<ProductCartItem>)}
        className={cn(
          'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
          item.taxable && !item.taxInclusive
            ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
            : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
        )}
        title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
      >
        {item.taxable && !item.taxInclusive
          ? '$' + (item.quantity * item.unitPrice * TAX_RATE_FALLBACK).toFixed(2)
          : 'No tax'}
      </button>
      <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
        ${(item.quantity * item.unitPrice).toFixed(2)}
      </span>
      <button
        onClick={() => removeCartItem(item.id)}
        className="shrink-0 p-1 text-red-400 hover:text-red-600 dark:hover:text-red-300 transition-colors"
        title="Remove"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

function MiscRow({ item }: { item: MiscCartItem }) {
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
        className={cn(
          'shrink-0 text-xs w-14 text-right rounded px-1 py-0.5 transition-colors cursor-pointer',
          item.taxable
            ? 'text-amber-600 dark:text-amber-400 hover:bg-amber-50 dark:hover:bg-amber-900/20'
            : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800'
        )}
        title={item.taxable ? 'Click to make non-taxable' : 'Click to make taxable'}
      >
        {item.taxable ? '$' + (item.quantity * item.unitPrice * TAX_RATE_FALLBACK).toFixed(2) : 'No tax'}
      </button>
      <span className="shrink-0 text-sm font-medium text-surface-900 dark:text-surface-100 w-16 text-right">
        ${(item.quantity * item.unitPrice).toFixed(2)}
      </span>
      <button
        onClick={() => removeCartItem(item.id)}
        className="shrink-0 p-1 text-red-400 hover:text-red-600 dark:hover:text-red-300 transition-colors"
        title="Remove"
      >
        <Trash2 className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

function CartItemRow({ item }: { item: CartItem }) {
  switch (item.type) {
    case 'repair':  return <RepairRow item={item} />;
    case 'product': return <ProductRow item={item} />;
    case 'misc':    return <MiscRow item={item} />;
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

  return useMemo(() => {
    let subtotal = 0;
    let taxableAmount = 0;

    for (const item of cartItems) {
      if (item.type === 'repair') {
        const labor = item.laborPrice - item.lineDiscount;
        subtotal += labor;
        if (item.taxable) taxableAmount += labor;
        for (const p of item.parts) {
          const partTotal = p.quantity * p.price;
          subtotal += partTotal;
          if (p.taxable) taxableAmount += partTotal;
        }
      } else if (item.type === 'product') {
        const lineTotal = item.quantity * item.unitPrice;
        subtotal += lineTotal;
        if (item.taxable && !item.taxInclusive) taxableAmount += lineTotal;
      } else {
        const lineTotal = item.quantity * item.unitPrice;
        subtotal += lineTotal;
        if (item.taxable) taxableAmount += lineTotal;
      }
    }

    // Member discount
    let memberDiscount = 0;
    if (memberDiscountApplied && customer?.group_discount_pct && customer.group_discount_pct > 0) {
      if (customer.group_discount_type === 'fixed') {
        memberDiscount = customer.group_discount_pct;
      } else {
        memberDiscount = subtotal * (customer.group_discount_pct / 100);
      }
      memberDiscount = Math.round(memberDiscount * 100) / 100;
    }

    const discountAmount = discount + memberDiscount;
    const tax = Math.round(taxableAmount * TAX_RATE_FALLBACK * 100) / 100;
    const total = Math.round((subtotal + tax - discountAmount) * 100) / 100;
    const itemCount = cartItems.length;

    return { itemCount, subtotal, discountAmount, tax, total: Math.max(0, total) };
  }, [cartItems, discount, customer, memberDiscountApplied]);
}

// ─── LeftPanel ──────────────────────────────────────────────────────

export function LeftPanel({ collapsed, onToggle }: { collapsed?: boolean; onToggle?: () => void }) {
  const { cartItems } = useUnifiedPosStore();
  const totals = useTotals();

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

  return (
    <div className="flex flex-col h-full">
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
                    {items.map((item) => <CartItemRow key={item.id} item={item} />)}
                  </div>
                ))}
                {ungrouped.map((item) => <CartItemRow key={item.id} item={item} />)}
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
          <span>Tax (8.865%){totals.tax === 0 && totals.subtotal > 0 ? ' \u2014 labor exempt' : ''}</span>
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
