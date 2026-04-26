import { useEffect, useRef, useState, useCallback, useMemo } from 'react';
import { useSearchParams, useLocation, useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { useUnifiedPosStore } from './store';
import { LeftPanel } from './LeftPanel';
import { RightPanel } from './RightPanel';
import { BottomActions } from './BottomActions';
import { CheckoutModal } from './CheckoutModal';
import { SuccessScreen } from './SuccessScreen';
import { UpsellPrompt } from './UpsellPrompt';
import { InactivityTimer } from './InactivityTimer';
import { TopFiveTiles } from './TopFiveTiles';
import { usePosKeyboardShortcuts } from '@/hooks/usePosKeyboardShortcuts';
import toast from 'react-hot-toast';
import { ticketApi, customerApi, posApi, deviceTemplateApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { X, Keyboard } from 'lucide-react';

// ─── DeviceTemplateNudge ──────────────────────────────────────────────────────

const DEVICE_NUDGE_KEY = 'pos.device_template_nudge_dismissed';

function DeviceTemplateNudge() {
  const navigate = useNavigate();
  const [dismissed, setDismissed] = useState(
    () => localStorage.getItem(DEVICE_NUDGE_KEY) === '1',
  );
  const [searchParams] = useSearchParams();
  const tutorialActive = Boolean(searchParams.get('tutorial'));

  const { data } = useQuery({
    queryKey: ['device-templates-count'],
    queryFn: () => deviceTemplateApi.list({ active: true }),
    staleTime: 60_000,
    enabled: !dismissed && !tutorialActive,
  });

  const templates: unknown[] = (data?.data as { data?: unknown[] } | undefined)?.data ?? [];
  const hasTemplates = templates.length > 0;

  if (dismissed || tutorialActive || hasTemplates) return null;

  const handleDismiss = () => {
    localStorage.setItem(DEVICE_NUDGE_KEY, '1');
    setDismissed(true);
  };

  return (
    <div className="flex items-center gap-3 border-b border-amber-200 bg-amber-50 px-4 py-2.5 dark:border-amber-700/50 dark:bg-amber-900/20">
      <p className="flex-1 text-sm text-amber-800 dark:text-amber-200">
        No device templates yet — create templates in Settings to speed up future repair tickets
      </p>
      <button
        type="button"
        onClick={() => navigate('/settings/device-templates')}
        className="rounded-lg bg-amber-600 px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-amber-700"
      >
        Go to templates
      </button>
      <button
        type="button"
        onClick={handleDismiss}
        className="rounded-md p-1 text-amber-600 transition-colors hover:bg-amber-100 dark:text-amber-400 dark:hover:bg-amber-800/40"
        aria-label="Skip for now"
        title="Skip for now"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
import { genId } from './types';
import type { RepairCartItem, PartEntry, ProductCartItem } from './types';

// ─── FKeyLegend ───────────────────────────────────────────────────────────────
// WEB-W3-029 (FIXED-by-Fixer-A23 2026-04-25): the unified POS binds F1-F4,
// Shift+F5, F6 to tab/customer-search/checkout/returns shortcuts but
// nothing on screen ever told the cashier they exist. New hires had to
// be told verbally. Keep it light: a small "?" / keyboard chip in the
// page corner that toggles a popover listing each shortcut + its action.
// State lives only in this component so it doesn't pollute the POS store.

const F_KEY_BINDINGS: ReadonlyArray<{ keys: string; action: string }> = [
  { keys: 'F1', action: 'Repairs tab' },
  { keys: 'F2', action: 'Products tab' },
  { keys: 'F3', action: 'Misc tab' },
  { keys: 'F4', action: 'Customer search' },
  { keys: 'Shift+F5', action: 'Complete sale' },
  { keys: 'F6', action: 'Returns hotkey' },
];

function FKeyLegend() {
  const [open, setOpen] = useState(false);
  return (
    <div className="absolute bottom-3 right-3 z-40">
      {open && (
        <div
          role="dialog"
          aria-label="Keyboard shortcuts"
          className="mb-2 w-64 rounded-lg border border-surface-200 bg-white p-3 shadow-lg dark:border-surface-700 dark:bg-surface-900"
        >
          <div className="mb-2 flex items-center justify-between">
            <h2 className="text-xs font-semibold uppercase tracking-wide text-surface-500">
              Keyboard shortcuts
            </h2>
            <button
              type="button"
              onClick={() => setOpen(false)}
              className="rounded p-0.5 text-surface-400 hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200"
              aria-label="Close shortcuts"
            >
              <X className="h-3.5 w-3.5" aria-hidden="true" />
            </button>
          </div>
          <ul className="space-y-1.5">
            {F_KEY_BINDINGS.map((b) => (
              <li key={b.keys} className="flex items-center justify-between gap-3 text-xs">
                <kbd className="rounded border border-surface-300 bg-surface-50 px-1.5 py-0.5 font-mono text-[10px] font-semibold text-surface-700 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200">
                  {b.keys}
                </kbd>
                <span className="text-surface-700 dark:text-surface-300">{b.action}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className="flex items-center gap-1.5 rounded-full border border-surface-200 bg-white px-3 py-1.5 text-xs font-medium text-surface-700 shadow-sm hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200 dark:hover:bg-surface-800"
        aria-expanded={open}
        aria-label="Show keyboard shortcuts"
        title="Keyboard shortcuts (F1-F6)"
      >
        <Keyboard className="h-3.5 w-3.5" aria-hidden="true" />
        Shortcuts
      </button>
    </div>
  );
}

// ─── UnifiedPosPage ─────────────────────────────────────────────────

export function UnifiedPosPage() {
  const { showSuccess, setShowSuccess, showCheckout, setShowCheckout, setCustomer, addRepair, resetAll, setSourceTicketId, cartItems, sourceTicketId, setActiveTab } = useUnifiedPosStore();
  const [cartCollapsed, setCartCollapsed] = useState(false);
  const toggleCart = useCallback(() => setCartCollapsed((v) => !v), []);

  // F-key quick tabs (audit §43.10). Handlers are memoized so the hook's
  // keydown listener isn't re-bound on every render (which would conflict
  // with the barcode detection listener below).
  // WEB-FL-004 (Fixer-RRR 2026-04-25): wire F4 (customer search) so it
  // focuses the unified search box instead of falling through to the
  // global AppShell handler. F6 ("Returns hotkey") has no destination
  // route yet — surface a toast so the cashier knows the key is
  // recognized but the flow is pending, rather than letting it open the
  // command palette via AppShell.
  const posShortcuts = useMemo(() => ({
    onRepairsTab: () => setActiveTab('repairs'),
    onProductsTab: () => setActiveTab('products'),
    onMiscTab: () => setActiveTab('misc'),
    onCustomerSearch: () => {
      const el = document.querySelector<HTMLInputElement>('[data-pos-customer-search="true"]');
      if (el) {
        el.focus();
        el.select();
      }
    },
    onCompleteSale: () => setShowCheckout(true),
    onReturnsHotkey: () => toast('Returns flow coming soon — scan the original invoice from the ticket page for now'),
  }), [setActiveTab, setShowCheckout]);
  usePosKeyboardShortcuts(posShortcuts);

  // Barcode scanner detection: rapid chars ending with Enter
  const [scanFlash, setScanFlash] = useState(false);
  const scanBufferRef = useRef('');
  const scanTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const lastKeyTimeRef = useRef(0);
  const { addProduct } = useUnifiedPosStore();

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      // AUDIT-WEB-025: do not accumulate scan characters while a modal is
      // open — the modal may have its own input handling and the buffered
      // barcode would fire into a stale context when the modal closes.
      const { showCheckout: isCheckoutOpen, showSuccess: isSuccessOpen } =
        useUnifiedPosStore.getState();
      if (isCheckoutOpen || isSuccessOpen) return;

      // Ignore if user is typing in an input/textarea
      const tag = (e.target as HTMLElement)?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT') return;

      const now = Date.now();
      const timeSinceLast = now - lastKeyTimeRef.current;
      lastKeyTimeRef.current = now;

      if (e.key === 'Enter' && scanBufferRef.current.length >= 4) {
        // Check if input was fast enough to be a scanner (avg < 50ms per char)
        const code = scanBufferRef.current;
        scanBufferRef.current = '';
        clearTimeout(scanTimerRef.current);

        // Show flash
        setScanFlash(true);
        setTimeout(() => setScanFlash(false), 1200);

        // Search and add to cart
        posApi.products({ keyword: code }).then((res) => {
          const found = (res.data?.data?.items || [])[0];
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
            toast.success(`Scanned: ${found.name}`);
          } else {
            toast.error(`No item found for barcode: ${code}`);
          }
        }).catch(() => toast.error('Barcode search failed'));

        return;
      }

      // Only accumulate printable single chars
      if (e.key.length === 1) {
        if (timeSinceLast > 100) {
          // Too slow — reset buffer (human typing)
          scanBufferRef.current = e.key;
        } else {
          scanBufferRef.current += e.key;
        }
        clearTimeout(scanTimerRef.current);
        scanTimerRef.current = setTimeout(() => { scanBufferRef.current = ''; }, 200);
      }
    };
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [addProduct]);
  const [searchParams, setSearchParams] = useSearchParams();
  const location = useLocation();
  const navigate = useNavigate();
  const ticketParam = searchParams.get('ticket');
  const customerParam = searchParams.get('customer') || searchParams.get('customer_id');
  const hydratedRef = useRef<string | null>(null);

  // Inactivity timer: reset POS to default view after 10 min when an existing ticket is loaded or checkout completed
  const inactivityTimerRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  const POS_TIMEOUT_MS = 10 * 60 * 1000; // 10 minutes

  useEffect(() => {
    // Activate when an existing ticket is loaded into POS (via store, not URL) or success screen showing
    if (!sourceTicketId && !showSuccess) return;

    const resetTimer = () => {
      clearTimeout(inactivityTimerRef.current);
      inactivityTimerRef.current = setTimeout(() => {
        resetAll();
        navigate('/pos', { replace: true });
        toast('POS reset after inactivity', { icon: '⏱️' });
      }, POS_TIMEOUT_MS);
    };

    resetTimer();
    const events = ['mousedown', 'keydown', 'scroll', 'touchstart'];
    events.forEach(e => window.addEventListener(e, resetTimer, { passive: true }));

    return () => {
      clearTimeout(inactivityTimerRef.current);
      events.forEach(e => window.removeEventListener(e, resetTimer));
    };
  }, [sourceTicketId, showSuccess]); // intentional: inactivity timer resets on ticket/success state changes, navigate is stable

  // Clear success screen when navigating to POS via sidebar (no params)
  // Also reset hydration ref so the same ticket can be re-loaded
  useEffect(() => {
    if (!ticketParam && !customerParam) {
      if (showSuccess) setShowSuccess(null);
      hydratedRef.current = null;
    }
  }, [location.key]); // intentional: reset success screen on navigation, setters are stable

  // Reset hydration ref when cart is emptied (user deleted items / cancelled)
  useEffect(() => {
    if (cartItems.length === 0 && hydratedRef.current) {
      hydratedRef.current = null;
    }
  }, [cartItems.length]);

  // Fetch ticket data when ?ticket= is present
  const { data: ticketData } = useQuery({
    queryKey: ['ticket', Number(ticketParam)],
    queryFn: () => ticketApi.get(Number(ticketParam)),
    enabled: !!ticketParam && hydratedRef.current !== ticketParam,
  });

  // Hydrate POS store from ticket data (once)
  useEffect(() => {
    if (!ticketParam || hydratedRef.current === ticketParam) return;
    const ticket = ticketData?.data?.data;
    if (!ticket) return;

    hydratedRef.current = ticketParam;
    resetAll();
    setSourceTicketId(Number(ticketParam));

    // Set customer
    if (ticket.customer) {
      setCustomer({
        id: ticket.customer.id,
        first_name: ticket.customer.first_name,
        last_name: ticket.customer.last_name,
        phone: ticket.customer.phone || null,
        mobile: ticket.customer.mobile || null,
        email: ticket.customer.email || null,
        organization: ticket.customer.organization || null,
      });
    }

    // Add devices as repair cart items
    for (const device of (ticket.devices || [])) {
      const parts: PartEntry[] = (device.parts || []).map((p: any) => ({
        _key: genId(),
        inventory_item_id: p.inventory_item_id || 0,
        name: p.name || p.item_name || 'Part',
        sku: p.item_sku || p.sku || null,
        quantity: p.quantity || 1,
        price: p.price || 0,
        taxable: true,
        status: p.status || 'available',
      }));

      const repairItem: RepairCartItem = {
        type: 'repair',
        id: genId(),
        device: {
          device_type: device.device_type || 'Phone',
          device_name: device.device_name || 'Unknown Device',
          device_model_id: null,
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
        serviceName: device.service?.name || 'Repair',
        repairServiceId: device.service_id || null,
        selectedGradeId: null,
        laborPrice: device.price || 0,
        lineDiscount: device.line_discount || 0,
        parts,
        // WEB-FB-025 (Fixer-C15 2026-04-25): default labor non-taxable. Cashiers in
        // jurisdictions that DO tax labor must flip the per-line toggle in
        // LeftPanel.tsx (the `$X.XX / No tax` button next to the labor price input)
        // — that UI control is the per-line override and is the visible indicator.
        // Long-term fix is a tenant-wide "default labor taxable" preference.
        taxable: false,
        sourceTicketId: Number(ticketParam),
        sourceTicketOrderId: ticket.order_id || `T-${ticketParam}`,
      };
      addRepair(repairItem);
    }

    // Clear the URL param so refresh doesn't re-hydrate
    setSearchParams({}, { replace: true });
    // Advance the checkout tutorial only when the ticket had devices (non-empty cart).
    if ((ticket.devices?.length ?? 0) > 0) {
      window.dispatchEvent(new CustomEvent('pos:cart-loaded'));
    }
  }, [ticketParam, ticketData, resetAll, setCustomer, addRepair, setSearchParams, setSourceTicketId]);

  // Hydrate POS from ?customer= param (pre-select customer for new ticket)
  const { data: customerData } = useQuery({
    queryKey: ['customer', Number(customerParam)],
    queryFn: () => customerApi.get(Number(customerParam)),
    enabled: !!customerParam && !ticketParam && hydratedRef.current !== `c${customerParam}`,
  });

  useEffect(() => {
    if (!customerParam || ticketParam || hydratedRef.current === `c${customerParam}`) return;
    const cust = customerData?.data?.data;
    if (!cust) return;

    hydratedRef.current = `c${customerParam}`;
    resetAll();
    setCustomer({
      id: cust.id,
      first_name: cust.first_name,
      last_name: cust.last_name,
      phone: cust.phone || null,
      mobile: cust.mobile || null,
      email: cust.email || null,
      organization: cust.organization || null,
    });
    setSearchParams({}, { replace: true });
  }, [customerParam, ticketParam, customerData, resetAll, setCustomer, setSearchParams]);

  // After successful checkout / ticket creation
  if (showSuccess) {
    return (
      <div className="flex flex-col -m-6" style={{ height: 'calc(100vh - 4rem - var(--dev-banner-h, 0px))' }}>
        <SuccessScreen />
      </div>
    );
  }

  return (
    <div className="relative flex flex-col -m-6" style={{ height: 'calc(100vh - 4rem - var(--dev-banner-h, 0px))' }}>
      {/* Phase D2: device template nudge — dismissed per-session via localStorage */}
      <DeviceTemplateNudge />
      {/* WEB-W3-029: F-key shortcut legend (toggles a small popover) */}
      <FKeyLegend />
      {/* Barcode scan flash indicator */}
      {scanFlash && (
        <div className="absolute top-2 left-1/2 -translate-x-1/2 z-50 rounded-lg bg-green-600 px-4 py-2 text-sm font-bold text-white shadow-lg animate-pulse">
          Scan detected!
        </div>
      )}
      {/* Audit §43.9 upsell prompt — additive, non-blocking */}
      <UpsellPrompt />
      {/* Audit §43.13 inactivity chip — visible only when within 2 min of reset */}
      <InactivityTimer enabled={!!sourceTicketId || cartItems.length > 0} timeoutMs={POS_TIMEOUT_MS} />
      {/* Two-panel layout */}
      <div className="flex flex-1 overflow-hidden">
        {/* Left: customer + cart + totals */}
        <div
          className={cn(
            'flex-shrink-0 border-r border-surface-200 dark:border-surface-700 transition-all duration-200',
            cartCollapsed ? 'w-12' : 'w-[40%]',
          )}
        >
          <LeftPanel
            collapsed={cartCollapsed}
            onToggle={toggleCart}
            onNewCustomer={() => navigate('/customers/new')}
          />
        </div>

        {/* Right: tabs (repairs / products / misc) — audit §43.1 tiles above */}
        <div className="flex flex-1 flex-col overflow-hidden">
          <TopFiveTiles />
          <div className="flex-1 overflow-hidden"><RightPanel /></div>
        </div>
      </div>

      {/* Bottom actions bar */}
      <BottomActions />

      {/* Checkout modal overlay */}
      {showCheckout && (
        <CheckoutModal onClose={() => setShowCheckout(false)} />
      )}
    </div>
  );
}
