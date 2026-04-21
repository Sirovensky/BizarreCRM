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
import { X } from 'lucide-react';

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
        onClick={() => navigate('/settings?tab=device-templates')}
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

// ─── UnifiedPosPage ─────────────────────────────────────────────────

export function UnifiedPosPage() {
  const { showSuccess, setShowSuccess, showCheckout, setShowCheckout, setCustomer, addRepair, resetAll, setSourceTicketId, cartItems, sourceTicketId, setActiveTab } = useUnifiedPosStore();
  const [cartCollapsed, setCartCollapsed] = useState(false);
  const toggleCart = useCallback(() => setCartCollapsed((v) => !v), []);

  // F-key quick tabs (audit §43.10). Handlers are memoized so the hook's
  // keydown listener isn't re-bound on every render (which would conflict
  // with the barcode detection listener below).
  const posShortcuts = useMemo(() => ({
    onRepairsTab: () => setActiveTab('repairs'),
    onProductsTab: () => setActiveTab('products'),
    onMiscTab: () => setActiveTab('misc'),
    onCompleteSale: () => setShowCheckout(true),
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
        taxable: false, // labor is non-taxable by default
        sourceTicketId: Number(ticketParam),
        sourceTicketOrderId: ticket.order_id || `T-${ticketParam}`,
      };
      addRepair(repairItem);
    }

    // Clear the URL param so refresh doesn't re-hydrate
    setSearchParams({}, { replace: true });
    // Advance the checkout tutorial when a ticket is loaded into POS.
    window.dispatchEvent(new CustomEvent('pos:cart-loaded'));
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
    <div className="flex flex-col -m-6" style={{ height: 'calc(100vh - 4rem - var(--dev-banner-h, 0px))' }}>
      {/* Phase D2: device template nudge — dismissed per-session via localStorage */}
      <DeviceTemplateNudge />
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
          <LeftPanel collapsed={cartCollapsed} onToggle={toggleCart} />
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
