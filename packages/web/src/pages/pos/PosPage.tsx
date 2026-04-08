import { useState, useRef, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useSearchParams, Link } from 'react-router-dom';
import { Search, Plus, Minus, X, ShoppingCart, DollarSign, CreditCard, Wallet, CheckCircle2, Printer, RotateCcw, Barcode, Tag, Loader2, ExternalLink, AlertCircle, Smartphone } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi, customerApi, ticketApi, blockchypApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface CartItem {
  inventory_item_id: number;
  name: string;
  sku: string | null;
  item_type: string;
  quantity: number;
  unit_price: number;
  retail_price: number;
  tax_class_id: number | null;
  tax_inclusive: number;
  taxable: boolean;
  // For ticket items that don't have an inventory_item_id (service charges)
  is_service_charge?: boolean;
  device_name?: string;
}

export function PosPage() {
  const [searchParams, setSearchParams] = useSearchParams();
  const ticketParam = searchParams.get('ticket');
  const ticketId = ticketParam ? Number(ticketParam) : null;
  const queryClient = useQueryClient();

  const [keyword, setKeyword] = useState('');
  const [category, setCategory] = useState('');
  const [cart, setCart] = useState<CartItem[]>([]);
  const [discount, setDiscount] = useState('');
  const [payMethod, setPayMethod] = useState<'cash' | 'credit_card' | 'debit' | 'other' | 'blockchyp'>('cash');
  const [blockchypProcessing, setBlockchypProcessing] = useState(false);
  const [cashGiven, setCashGiven] = useState('');
  const [customerSearch, setCustomerSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<any>(null);
  const [customerResults, setCustomerResults] = useState<any[]>([]);
  const [showSuccess, setShowSuccess] = useState<any>(null);
  const [showCashIn, setShowCashIn] = useState(false);
  const [showCashOut, setShowCashOut] = useState(false);
  const [cashAmount, setCashAmount] = useState('');
  const [cashReason, setCashReason] = useState('');
  const [memberDiscountApplied, setMemberDiscountApplied] = useState(false);
  const [ticketLoaded, setTicketLoaded] = useState(false);
  const [tipAmount, setTipAmount] = useState('');
  // Dummy credit card processing state
  const [cardProcessing, setCardProcessing] = useState(false);
  const [cardApproved, setCardApproved] = useState(false);
  const [mobileCartOpen, setMobileCartOpen] = useState(false);
  const barcodeRef = useRef<HTMLInputElement>(null);

  // Fetch ticket data if checkout from ticket
  const { data: ticketData, isLoading: ticketLoading } = useQuery({
    queryKey: ['ticket', ticketId],
    queryFn: () => ticketApi.get(ticketId!),
    enabled: !!ticketId,
  });
  const ticket = ticketData?.data?.data;

  // Pre-fill cart from ticket when data arrives
  useEffect(() => {
    if (!ticket || ticketLoaded) return;

    const items: CartItem[] = [];

    // Add each device's service/labor charge
    for (const device of (ticket.devices || [])) {
      if (device.price > 0) {
        items.push({
          inventory_item_id: device.service_id || -(device.id), // Negative ID as placeholder for service charges
          name: `${device.device_name} - ${device.service?.name || 'Service/Labor'}`,
          sku: null,
          item_type: 'service',
          quantity: 1,
          unit_price: device.price,
          retail_price: device.price,
          tax_class_id: device.tax_class_id,
          tax_inclusive: device.tax_inclusive ? 1 : 0,
          taxable: true,
          is_service_charge: true,
          device_name: device.device_name,
        });
      }

      // Add each device's parts
      for (const part of (device.parts || [])) {
        items.push({
          inventory_item_id: part.inventory_item_id,
          name: part.item_name || `Part #${part.inventory_item_id}`,
          sku: part.item_sku || null,
          item_type: 'part',
          quantity: part.quantity,
          unit_price: part.price,
          retail_price: part.price,
          tax_class_id: null,
          tax_inclusive: 0,
          taxable: true,
        });
      }
    }

    setCart(items);

    // Pre-select customer
    if (ticket.customer) {
      setSelectedCustomer(ticket.customer);
    }

    // Pre-fill discount
    if (ticket.discount > 0) {
      setDiscount(String(ticket.discount));
    }

    setTicketLoaded(true);
  }, [ticket, ticketLoaded]);

  const { data: productsData } = useQuery({
    queryKey: ['pos-products', keyword, category],
    queryFn: () => posApi.products({ keyword: keyword || undefined, category: category || undefined }),
    staleTime: 30000,
  });

  const { data: registerData, refetch: refetchRegister } = useQuery({
    queryKey: ['pos-register'],
    queryFn: () => posApi.register(),
  });

  const { data: blockchypData } = useQuery({
    queryKey: ['blockchyp', 'status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 60000,
  });
  const blockchypEnabled = blockchypData?.data?.data?.enabled ?? false;

  const products: any[] = productsData?.data?.data?.items || [];
  const categories: string[] = productsData?.data?.data?.categories || [];
  const register: any = registerData?.data?.data;

  const transactionMutation = useMutation({
    mutationFn: (data: any) => posApi.transaction(data),
    onSuccess: async (res: any) => {
      const result = res.data.data;

      // If paying via BlockChyp terminal, process the card payment
      if (blockchypProcessing && result?.invoice?.id) {
        try {
          const tipAmount = tip > 0 ? tip : undefined;
          const bcRes = await blockchypApi.processPayment(result.invoice.id, tipAmount);
          const bcData = bcRes.data?.data;
          if (bcData?.success) {
            toast.success(`Payment approved${bcData.cardType ? ` — ${bcData.cardType} ending ${bcData.last4}` : ''}`);
            setShowSuccess({ ...result, blockchypPayment: bcData });
          } else {
            toast.error(bcData?.error || bcData?.responseDescription || 'Payment declined');
            setShowSuccess(result); // still show success screen — invoice created but unpaid
          }
        } catch (err: unknown) {
          const msg = err instanceof Error ? err.message : 'Terminal communication failed';
          toast.error(`Terminal error: ${msg}`);
          setShowSuccess(result);
        } finally {
          setBlockchypProcessing(false);
        }
      } else {
        setShowSuccess(result);
      }

      // If checking out from a ticket, update ticket status to Closed
      if (ticketId && ticket) {
        ticketApi.changeStatus(ticketId, getClosedStatusId()).catch(() => {});
        queryClient.invalidateQueries({ queryKey: ['ticket', ticketId] });
      }
    },
    onError: (e: any) => {
      setBlockchypProcessing(false);
      toast.error(e?.response?.data?.message || 'Transaction failed');
    },
  });

  // Helper to get the "Closed" status ID (default to 7 which is standard seed)
  const getClosedStatusId = () => {
    // We don't have statuses loaded here, so use a reasonable default.
    // The seed data creates "Closed" at sort_order 7 with is_closed = true.
    return 7;
  };

  const cashInMutation = useMutation({
    mutationFn: (data: any) => posApi.cashIn(data),
    onSuccess: () => { toast.success('Cash in recorded'); refetchRegister(); setShowCashIn(false); setCashAmount(''); setCashReason(''); },
  });

  const cashOutMutation = useMutation({
    mutationFn: (data: any) => posApi.cashOut(data),
    onSuccess: () => { toast.success('Cash out recorded'); refetchRegister(); setShowCashOut(false); setCashAmount(''); setCashReason(''); },
  });

  // Tax rate lookup (simplified - use Colorado default)
  const TAX_RATE = 0.08865;

  const subtotal = cart.reduce((sum, i) => sum + i.quantity * i.unit_price, 0);
  const manualDiscount = parseFloat(discount) || 0;

  // Member group discount
  let memberDiscountAmount = 0;
  if (memberDiscountApplied && selectedCustomer?.group_discount_pct > 0) {
    if (selectedCustomer.group_discount_type === 'fixed') {
      memberDiscountAmount = selectedCustomer.group_discount_pct;
    } else {
      memberDiscountAmount = subtotal * (selectedCustomer.group_discount_pct / 100);
    }
    memberDiscountAmount = Math.round(memberDiscountAmount * 100) / 100;
  }

  const discountAmount = manualDiscount + memberDiscountAmount;
  const tax = cart.reduce((sum, i) => {
    if (i.tax_inclusive || !i.taxable) return sum;
    return sum + i.quantity * i.unit_price * TAX_RATE;
  }, 0);
  const tip = parseFloat(tipAmount) || 0;
  const total = subtotal + tax - discountAmount + tip;
  const change = cashGiven ? Math.max(0, parseFloat(cashGiven) - total) : 0;

  // ── Suggestive sale alerts ──
  const SUGGESTIONS: Record<string, string[]> = {
    'screen': ['Screen Protector', 'Tempered Glass'],
    'lcd': ['Screen Protector', 'Tempered Glass'],
    'display': ['Screen Protector', 'Tempered Glass'],
    'battery': ['Charging Cable', 'Wireless Charger'],
    'charging port': ['Charging Cable'],
    'charge port': ['Charging Cable'],
    'back glass': ['Phone Case', 'Clear Case'],
    'housing': ['Phone Case', 'Clear Case'],
  };

  const suggestedItems = (() => {
    const suggestions = new Set<string>();
    const cartNames = cart.map((i) => i.name.toLowerCase());
    for (const item of cart) {
      const name = item.name.toLowerCase();
      for (const [keyword, items] of Object.entries(SUGGESTIONS)) {
        if (name.includes(keyword)) {
          for (const s of items) {
            if (!cartNames.some((cn) => cn.includes(s.toLowerCase()))) {
              suggestions.add(s);
            }
          }
        }
      }
      // Any phone repair → suggest phone case
      if (item.item_type === 'service' && (name.includes('phone') || name.includes('iphone') || name.includes('galaxy') || name.includes('pixel'))) {
        if (!cartNames.some((cn) => cn.includes('case'))) {
          suggestions.add('Phone Case');
        }
      }
    }
    return Array.from(suggestions).slice(0, 3);
  })();

  const addToCart = (product: any) => {
    setCart((prev) => {
      const existing = prev.find((i) => i.inventory_item_id === product.id);
      if (existing) {
        return prev.map((i) => i.inventory_item_id === product.id ? { ...i, quantity: i.quantity + 1 } : i);
      }
      return [...prev, {
        inventory_item_id: product.id,
        name: product.name,
        sku: product.sku || null,
        item_type: product.item_type,
        quantity: 1,
        unit_price: product.retail_price,
        retail_price: product.retail_price,
        tax_class_id: product.tax_class_id,
        tax_inclusive: product.tax_inclusive,
        taxable: true,
      }];
    });
  };

  const updateQty = (id: number, delta: number) => {
    setCart((prev) => prev.map((i) => {
      if (i.inventory_item_id !== id) return i;
      const q = i.quantity + delta;
      return q <= 0 ? null : { ...i, quantity: q };
    }).filter(Boolean) as CartItem[]);
  };

  const removeItem = (id: number) => setCart((prev) => prev.filter((i) => i.inventory_item_id !== id));

  const toggleTaxable = (id: number) => {
    setCart((prev) => prev.map((i) => i.inventory_item_id === id ? { ...i, taxable: !i.taxable } : i));
  };

  const updatePrice = (id: number, price: string) => {
    setCart((prev) => prev.map((i) => i.inventory_item_id === id ? { ...i, unit_price: parseFloat(price) || 0 } : i));
  };

  const handleCheckout = async () => {
    if (!cart.length) return toast.error('Cart is empty');

    // BlockChyp terminal payment
    if (payMethod === 'blockchyp') {
      setBlockchypProcessing(true);
      try {
        // First create the transaction to get an invoice
        processTransaction();
      } catch {
        setBlockchypProcessing(false);
        toast.error('Failed to create transaction');
      }
      return;
    }

    // For credit card / debit, show dummy processing modal
    if (payMethod === 'credit_card' || payMethod === 'debit') {
      setCardProcessing(true);
      setCardApproved(false);
      // Simulate 2-second processing delay
      setTimeout(() => {
        setCardApproved(true);
      }, 2000);
      return;
    }

    // For cash / other, process immediately
    processTransaction();
  };

  const processTransaction = () => {
    transactionMutation.mutate({
      customer_id: selectedCustomer?.id || null,
      items: cart
        .filter((i) => !i.is_service_charge || i.inventory_item_id > 0)
        .map((i) => ({ inventory_item_id: Math.abs(i.inventory_item_id), quantity: i.quantity, unit_price: i.unit_price })),
      payment_method: payMethod,
      payment_amount: payMethod === 'cash' ? parseFloat(cashGiven) || total : total,
      discount: discountAmount,
      discount_reason: memberDiscountApplied && selectedCustomer?.customer_group_name
        ? `Member: ${selectedCustomer.customer_group_name} (${selectedCustomer.group_discount_type === 'fixed' ? '$' + selectedCustomer.group_discount_pct : selectedCustomer.group_discount_pct + '%'})`
        : undefined,
      ticket_id: ticketId || undefined,
      tip: tip > 0 ? tip : undefined,
    });
  };

  const handleCardComplete = () => {
    setCardProcessing(false);
    setCardApproved(false);
    processTransaction();
  };

  const handleNewSale = () => {
    setCart([]);
    setDiscount('');
    setCashGiven('');
    setSelectedCustomer(null);
    setCustomerSearch('');
    setMemberDiscountApplied(false);
    setTipAmount('');
    setShowSuccess(null);
    setTicketLoaded(false);
    // Clear ticket param from URL
    if (ticketId) {
      setSearchParams({});
    }
  };

  // Customer search
  useEffect(() => {
    if (customerSearch.length < 2) { setCustomerResults([]); return; }
    const t = setTimeout(async () => {
      try {
        const res = await customerApi.search(customerSearch);
        const results = res.data?.data;
        setCustomerResults(Array.isArray(results) ? results.slice(0, 5) : []);
      } catch {}
    }, 300);
    return () => clearTimeout(t);
  }, [customerSearch]);

  // Auto-apply member discount when customer is selected
  useEffect(() => {
    if (
      selectedCustomer &&
      selectedCustomer.group_auto_apply &&
      selectedCustomer.group_discount_pct &&
      selectedCustomer.group_discount_pct > 0
    ) {
      setMemberDiscountApplied(true);
    } else {
      setMemberDiscountApplied(false);
    }
  }, [selectedCustomer]);

  // Barcode scan handler
  const handleBarcode = async (e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key !== 'Enter') return;
    const code = (e.target as HTMLInputElement).value.trim();
    if (!code) return;
    try {
      const res = await posApi.products({ keyword: code });
      const found = res.data?.data?.items?.[0];
      if (found) { addToCart(found); (e.target as HTMLInputElement).value = ''; }
      else toast.error(`No item found for: ${code}`);
    } catch {}
  };

  if (showSuccess) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[70vh] text-center">
        <div className="h-20 w-20 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center mb-6">
          <CheckCircle2 className="h-10 w-10 text-green-600 dark:text-green-400" />
        </div>
        <h2 className="text-2xl font-bold text-surface-900 dark:text-surface-100 mb-2">Sale Complete!</h2>
        {ticketId && (
          <p className="text-sm text-surface-500 dark:text-surface-400 mb-1">
            Ticket {ticket?.order_id || `T-${String(ticketId).padStart(4, '0')}`} has been checked out
          </p>
        )}
        <p className="text-surface-500 dark:text-surface-400 mb-1">Invoice: <span className="font-mono font-semibold">{showSuccess.invoice?.order_id}</span></p>
        <p className="text-3xl font-bold text-surface-900 dark:text-surface-100 mb-1">${Number(showSuccess.invoice?.total).toFixed(2)}</p>
        {showSuccess.change > 0 && (
          <p className="text-xl font-semibold text-green-600 dark:text-green-400 mb-4">Change: ${showSuccess.change.toFixed(2)}</p>
        )}
        <div className="flex gap-3 mt-4">
          <button onClick={() => window.print()} className="inline-flex items-center gap-2 px-5 py-2.5 border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 rounded-xl font-medium hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
            <Printer className="h-4 w-4" /> Print Receipt
          </button>
          {ticketId && (
            <Link to={`/tickets/${ticketId}`} className="inline-flex items-center gap-2 px-5 py-2.5 border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 rounded-xl font-medium hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
              <ExternalLink className="h-4 w-4" /> View Ticket
            </Link>
          )}
          <button onClick={handleNewSale} className="inline-flex items-center gap-2 px-5 py-2.5 bg-primary-600 hover:bg-primary-700 text-white rounded-xl font-medium transition-colors">
            <RotateCcw className="h-4 w-4" /> New Sale
          </button>
        </div>
      </div>
    );
  }

  // Show loading state when loading ticket
  if (ticketId && ticketLoading) {
    return (
      <div className="flex flex-col items-center justify-center min-h-[70vh]">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500 mb-4" />
        <p className="text-surface-500 dark:text-surface-400">Loading ticket data...</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col -m-3 md:-m-6" style={{ height: 'calc(100vh - 4rem - var(--dev-banner-h, 0px))' }}>
      {/* Ticket checkout banner */}
      {ticketId && ticket && (
        <div className="bg-teal-50 dark:bg-teal-900/20 border-b border-teal-200 dark:border-teal-800 px-4 py-2.5 flex items-center gap-3">
          <ShoppingCart className="h-5 w-5 text-teal-600 dark:text-teal-400" />
          <span className="text-sm font-semibold text-teal-800 dark:text-teal-200">
            Checking out Ticket {ticket.order_id || `T-${String(ticketId).padStart(4, '0')}`}
          </span>
          {ticket.customer && (
            <span className="text-sm text-teal-600 dark:text-teal-400">
              -- {ticket.customer.first_name} {ticket.customer.last_name}
            </span>
          )}
          <Link to={`/tickets/${ticketId}`} className="ml-auto inline-flex items-center gap-1 text-xs font-medium text-teal-600 dark:text-teal-400 hover:text-teal-700 dark:hover:text-teal-300 transition-colors">
            <ExternalLink className="h-3 w-3" /> View Ticket
          </Link>
          <button onClick={() => { setSearchParams({}); setCart([]); setTicketLoaded(false); setSelectedCustomer(null); setDiscount(''); }}
            className="text-teal-500 hover:text-teal-700 dark:hover:text-teal-300">
            <X className="h-4 w-4" />
          </button>
        </div>
      )}

      <div className="flex flex-col md:flex-row flex-1 overflow-hidden">
        {/* Left: Product Grid */}
        <div className="flex-1 flex flex-col md:border-r border-surface-200 dark:border-surface-700 overflow-hidden">
          {/* Top bar */}
          <div className="px-4 py-3 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 space-y-2">
            <div className="flex gap-2">
              {/* Search */}
              <div className="relative flex-1">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
                <input
                  type="text"
                  placeholder="Search products..."
                  value={keyword}
                  onChange={(e) => setKeyword(e.target.value)}
                  className="w-full pl-9 pr-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500"
                />
              </div>
              {/* Barcode */}
              <div className="relative">
                <Barcode className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
                <input
                  ref={barcodeRef}
                  type="text"
                  placeholder="Scan barcode..."
                  onKeyDown={handleBarcode}
                  className="w-40 pl-9 pr-3 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500"
                />
              </div>
            </div>
            {/* Category tabs */}
            {categories.length > 0 && (
              <div className="flex gap-1 overflow-x-auto pb-1 scrollbar-hide">
                <button
                  onClick={() => setCategory('')}
                  className={cn('flex-shrink-0 px-3 py-1 text-xs font-medium rounded-full transition-colors',
                    !category ? 'bg-primary-600 text-white' : 'bg-surface-100 dark:bg-surface-800 text-surface-600 dark:text-surface-300 hover:bg-surface-200 dark:hover:bg-surface-700'
                  )}
                >All</button>
                {categories.map((cat) => (
                  <button key={cat} onClick={() => setCategory(cat === category ? '' : cat)}
                    className={cn('flex-shrink-0 px-3 py-1 text-xs font-medium rounded-full transition-colors',
                      category === cat ? 'bg-primary-600 text-white' : 'bg-surface-100 dark:bg-surface-800 text-surface-600 dark:text-surface-300 hover:bg-surface-200 dark:hover:bg-surface-700'
                    )}>
                    {cat}
                  </button>
                ))}
              </div>
            )}
          </div>

          {/* Product grid */}
          <div className="flex-1 overflow-y-auto p-2 md:p-4">
            {products.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-surface-400">
                <ShoppingCart className="h-12 w-12 mb-3" />
                <p className="text-sm">No products found</p>
              </div>
            ) : (
              <div className="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 lg:grid-cols-5 gap-3">
                {products.map((p: any) => (
                  <button
                    key={p.id}
                    onClick={() => addToCart(p)}
                    disabled={p.item_type !== 'service' && p.in_stock === 0}
                    className={cn(
                      'relative flex flex-col items-start p-3 rounded-xl border text-left transition-all',
                      p.item_type !== 'service' && p.in_stock === 0
                        ? 'opacity-50 cursor-not-allowed border-surface-200 dark:border-surface-700'
                        : 'border-surface-200 dark:border-surface-700 hover:border-primary-400 hover:shadow-md hover:-translate-y-0.5 bg-white dark:bg-surface-800 active:translate-y-0'
                    )}
                  >
                    <div className="w-full mb-2 h-8 flex items-center justify-center rounded-lg bg-surface-100 dark:bg-surface-700">
                      <span className={cn('text-xs font-bold uppercase tracking-wide',
                        p.item_type === 'service' ? 'text-green-600 dark:text-green-400' : 'text-blue-600 dark:text-blue-400'
                      )}>{p.item_type === 'service' ? 'SVC' : 'PRD'}</span>
                    </div>
                    <p className="text-xs font-medium text-surface-800 dark:text-surface-200 leading-tight line-clamp-2 w-full">{p.name}</p>
                    {p.sku && <p className="text-[10px] font-mono text-surface-400 truncate w-full mt-0.5">{p.sku}</p>}
                    <p className="text-sm font-bold text-surface-900 dark:text-surface-100 mt-1">${Number(p.retail_price).toFixed(2)}</p>
                    {p.item_type !== 'service' && (
                      <p className={cn('text-xs mt-0.5', p.in_stock <= 2 ? 'text-amber-500' : 'text-surface-400')}>
                        {p.in_stock} left
                      </p>
                    )}
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Mobile cart toggle button */}
        <button
          onClick={() => setMobileCartOpen(!mobileCartOpen)}
          className="md:hidden fixed bottom-4 right-4 z-40 h-14 w-14 rounded-full bg-primary-600 text-white shadow-lg flex items-center justify-center active:bg-primary-700"
        >
          <ShoppingCart className="h-6 w-6" />
          {cart.length > 0 && (
            <span className="absolute -top-1 -right-1 h-5 min-w-[20px] px-1 rounded-full bg-red-500 text-white text-xs font-bold flex items-center justify-center">
              {cart.reduce((s, i) => s + i.quantity, 0)}
            </span>
          )}
        </button>

        {/* Mobile cart overlay */}
        {mobileCartOpen && (
          <div className="md:hidden fixed inset-0 z-50 bg-black/40" onClick={() => setMobileCartOpen(false)} />
        )}

        {/* Right: Cart */}
        <div className={cn(
          'flex flex-col bg-white dark:bg-surface-900 overflow-hidden',
          // Mobile: slide-up panel
          'fixed inset-x-0 bottom-0 z-50 max-h-[85vh] rounded-t-2xl shadow-2xl transition-transform duration-300 md:transition-none',
          mobileCartOpen ? 'translate-y-0' : 'translate-y-full',
          // Desktop: side panel
          'md:static md:translate-y-0 md:rounded-none md:shadow-none md:w-80 xl:md:w-96 md:max-h-none',
        )}>
          {/* Cart header */}
          <div className="px-4 py-3 border-b border-surface-200 dark:border-surface-700 flex items-center justify-between">
            <div className="flex items-center gap-2">
              <ShoppingCart className="h-5 w-5 text-surface-500" />
              <span className="font-semibold text-surface-900 dark:text-surface-100">Cart</span>
              {cart.length > 0 && <span className="inline-flex items-center justify-center h-5 min-w-[20px] px-1 rounded-full bg-primary-600 text-white text-xs font-bold">{cart.reduce((s, i) => s + i.quantity, 0)}</span>}
            </div>
            <div className="flex items-center gap-2">
              <span className="text-xs text-surface-400">Register: <span className="font-medium text-surface-700 dark:text-surface-300">${(register?.net || 0).toFixed(2)}</span></span>
              <button onClick={() => setMobileCartOpen(false)} className="md:hidden p-1 rounded-lg text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
                <X className="h-5 w-5" />
              </button>
            </div>
          </div>

          {/* Customer */}
          <div className="px-4 py-2 border-b border-surface-100 dark:border-surface-800 relative">
            {selectedCustomer ? (
              <div className="flex items-center justify-between">
                <div className="text-sm">
                  <div className="flex items-center gap-1.5 flex-wrap">
                    <span className="font-medium text-surface-900 dark:text-surface-100">{selectedCustomer.first_name} {selectedCustomer.last_name}</span>
                    {(selectedCustomer.mobile || selectedCustomer.phone) && <span className="text-surface-400">{selectedCustomer.mobile || selectedCustomer.phone}</span>}
                    {memberDiscountApplied && selectedCustomer.customer_group_name && (
                      <span className="inline-flex items-center gap-0.5 rounded-full bg-green-100 px-1.5 py-0.5 text-[10px] font-semibold text-green-700 dark:bg-green-900/30 dark:text-green-400">
                        <Tag className="h-2.5 w-2.5" />
                        {selectedCustomer.customer_group_name} ({selectedCustomer.group_discount_type === 'fixed' ? `$${selectedCustomer.group_discount_pct}` : `${selectedCustomer.group_discount_pct}%`} off)
                      </span>
                    )}
                  </div>
                </div>
                <button onClick={() => { setSelectedCustomer(null); setCustomerSearch(''); }} className="text-surface-400 hover:text-surface-600">
                  <X className="h-4 w-4" />
                </button>
              </div>
            ) : (
              <div className="relative">
                <input
                  type="text"
                  placeholder="Search customer (optional)..."
                  value={customerSearch}
                  onChange={(e) => setCustomerSearch(e.target.value)}
                  className="w-full text-xs py-1.5 px-3 rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-1 focus:ring-primary-500/30 focus:border-primary-500"
                />
                {customerResults.length > 0 && (
                  <div className="absolute top-full left-0 right-0 z-10 mt-1 bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 rounded-lg shadow-lg overflow-hidden">
                    {customerResults.map((c: any) => (
                      <button key={c.id} onClick={() => { setSelectedCustomer(c); setCustomerSearch(''); setCustomerResults([]); }}
                        className="w-full text-left px-3 py-2 text-xs hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors">
                        <span className="font-medium">{c.first_name} {c.last_name}</span>
                        {(c.mobile || c.phone) && <span className="text-surface-400 ml-1">{c.mobile || c.phone}</span>}
                      </button>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>

          {/* Cart items */}
          <div className="flex-1 overflow-y-auto">
            {cart.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-surface-400 p-4 text-center">
                <ShoppingCart className="h-10 w-10 mb-2 opacity-40" />
                <p className="text-sm">Click items to add them</p>
              </div>
            ) : (
              <div className="divide-y divide-surface-100 dark:divide-surface-800">
                {cart.map((item) => (
                  <div key={item.inventory_item_id} className="px-4 py-3">
                    <div className="flex items-start justify-between gap-2">
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
                        {item.sku && <p className="text-[10px] font-mono text-surface-400 truncate">{item.sku}</p>}
                        {item.is_service_charge && (
                          <span className="text-[10px] font-medium text-teal-600 dark:text-teal-400">Service charge</span>
                        )}
                        <div className="flex items-center gap-2 mt-1">
                          <span className="text-xs text-surface-400">$</span>
                          <input
                            type="number" step="0.01" min="0"
                            value={item.unit_price}
                            onChange={(e) => updatePrice(item.inventory_item_id, e.target.value)}
                            className="w-20 text-xs border border-surface-200 dark:border-surface-700 rounded px-1.5 py-0.5 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-500/30"
                          />
                        </div>
                      </div>
                      <div className="flex items-center gap-1">
                        <button onClick={() => updateQty(item.inventory_item_id, -1)} className="h-6 w-6 rounded-md border border-surface-200 dark:border-surface-700 flex items-center justify-center text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                          <Minus className="h-3 w-3" />
                        </button>
                        <span className="w-6 text-center text-sm font-medium text-surface-900 dark:text-surface-100">{item.quantity}</span>
                        <button onClick={() => updateQty(item.inventory_item_id, 1)} className="h-6 w-6 rounded-md border border-surface-200 dark:border-surface-700 flex items-center justify-center text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                          <Plus className="h-3 w-3" />
                        </button>
                        <button onClick={() => removeItem(item.inventory_item_id)} className="h-6 w-6 rounded-md flex items-center justify-center text-surface-300 hover:text-red-500 transition-colors ml-1">
                          <X className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    </div>
                    <div className="flex items-center justify-between mt-1">
                      <button
                        onClick={() => toggleTaxable(item.inventory_item_id)}
                        className={cn('text-[10px] font-medium px-1.5 py-0.5 rounded transition-colors',
                          item.taxable
                            ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300'
                            : 'bg-surface-100 text-surface-400 dark:bg-surface-800 dark:text-surface-500'
                        )}
                      >
                        {item.taxable ? 'TAX' : 'NO TAX'}
                      </button>
                      <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">${(item.quantity * item.unit_price).toFixed(2)}</span>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>

          {/* Suggestive sale alerts */}
          {suggestedItems.length > 0 && (
            <div className="px-4 py-2 border-t border-amber-200 dark:border-amber-800 bg-amber-50 dark:bg-amber-900/20">
              <p className="text-[10px] font-semibold text-amber-700 dark:text-amber-400 uppercase tracking-wide mb-1">Customers also buy:</p>
              <div className="flex flex-wrap gap-1">
                {suggestedItems.map((s) => (
                  <button
                    key={s}
                    onClick={() => setKeyword(s)}
                    className="text-[11px] px-2 py-0.5 rounded-full border border-amber-300 dark:border-amber-700 text-amber-700 dark:text-amber-300 hover:bg-amber-100 dark:hover:bg-amber-800/40 transition-colors"
                  >
                    + {s}
                  </button>
                ))}
              </div>
            </div>
          )}

          {/* Totals & Payment */}
          <div className="border-t border-surface-200 dark:border-surface-700 px-4 py-3 space-y-2 overflow-y-auto max-h-[45vh]">
            {/* Discount */}
            <div className="flex items-center gap-2">
              <span className="text-xs text-surface-500 w-16">Discount</span>
              <div className="relative flex-1">
                <span className="absolute left-2 top-1/2 -translate-y-1/2 text-surface-400 text-xs">$</span>
                <input type="number" step="0.01" min="0" value={discount} onChange={(e) => setDiscount(e.target.value)}
                  placeholder="0.00" className="w-full pl-5 pr-2 py-1.5 text-xs border border-surface-200 dark:border-surface-700 rounded-lg bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-500/30" />
              </div>
            </div>

            {/* Tip / Gratuity */}
            <div>
              <div className="flex items-center gap-2">
                <span className="text-xs text-surface-500 w-16">Tip</span>
                <div className="flex gap-1 flex-1">
                  {[10, 15, 20].map((pct) => {
                    const tipVal = Math.round(subtotal * pct) / 100;
                    const isActive = tipAmount === String(tipVal);
                    return (
                      <button key={pct} onClick={() => setTipAmount(isActive ? '' : String(tipVal))}
                        className={cn('flex-1 py-1 text-[10px] font-medium rounded border transition-colors',
                          isActive
                            ? 'bg-green-600 text-white border-green-600'
                            : 'border-surface-200 dark:border-surface-700 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800'
                        )}>
                        {pct}%
                      </button>
                    );
                  })}
                  <div className="relative flex-1">
                    <span className="absolute left-2 top-1/2 -translate-y-1/2 text-surface-400 text-[10px]">$</span>
                    <input type="number" step="0.01" min="0" value={tipAmount} onChange={(e) => setTipAmount(e.target.value)}
                      placeholder="Custom"
                      className="w-full pl-4 pr-1 py-1 text-[10px] border border-surface-200 dark:border-surface-700 rounded bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-500/30" />
                  </div>
                </div>
              </div>
            </div>

            {/* Summary */}
            <div className="space-y-1 text-sm">
              <div className="flex justify-between text-surface-500 dark:text-surface-400"><span>Subtotal</span><span>${subtotal.toFixed(2)}</span></div>
              {memberDiscountAmount > 0 && <div className="flex justify-between text-green-600 dark:text-green-400"><span>Member Discount</span><span>-${memberDiscountAmount.toFixed(2)}</span></div>}
              {manualDiscount > 0 && <div className="flex justify-between text-green-600 dark:text-green-400"><span>Discount</span><span>-${manualDiscount.toFixed(2)}</span></div>}
              <div className="flex justify-between text-surface-500 dark:text-surface-400"><span>Tax (8.865%)</span><span>${tax.toFixed(2)}</span></div>
              {tip > 0 && <div className="flex justify-between text-surface-500 dark:text-surface-400"><span>Tip</span><span>${tip.toFixed(2)}</span></div>}
              <div className="flex justify-between font-bold text-base text-surface-900 dark:text-surface-100 pt-1 border-t border-surface-200 dark:border-surface-700 mt-1">
                <span>Total</span><span>${total.toFixed(2)}</span>
              </div>
            </div>

            {/* Payment method */}
            <div className={cn('grid gap-1', blockchypEnabled ? 'grid-cols-5' : 'grid-cols-4')}>
              {[
                { key: 'cash', label: 'Cash', icon: DollarSign },
                ...(blockchypEnabled ? [{ key: 'blockchyp', label: 'Terminal', icon: Smartphone }] : []),
                { key: 'credit_card', label: 'Credit', icon: CreditCard },
                { key: 'debit', label: 'Debit', icon: CreditCard },
                { key: 'other', label: 'Other', icon: Wallet },
              ].map(({ key, label, icon: Icon }) => (
                <button key={key} onClick={() => setPayMethod(key as any)}
                  className={cn('flex flex-col items-center gap-0.5 px-1 py-2 rounded-lg text-xs font-medium border transition-colors',
                    payMethod === key
                      ? 'bg-primary-600 text-white border-primary-600'
                      : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800'
                  )}>
                  <Icon className="h-4 w-4" />{label}
                </button>
              ))}
            </div>

            {/* Cash given (only for cash) */}
            {payMethod === 'cash' && (
              <div>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400 text-sm">$</span>
                  <input type="number" step="0.01" min="0" value={cashGiven} onChange={(e) => setCashGiven(e.target.value)}
                    placeholder={`Cash given (min $${total.toFixed(2)})`}
                    className="w-full pl-7 pr-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-surface-50 dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500/20 focus:border-primary-500" />
                </div>
                {/* Quick amounts */}
                <div className="flex gap-1 mt-1.5">
                  {[Math.ceil(total), Math.ceil(total / 5) * 5, Math.ceil(total / 10) * 10, Math.ceil(total / 20) * 20].filter((v, i, a) => a.indexOf(v) === i).slice(0, 4).map((amt) => (
                    <button key={amt} onClick={() => setCashGiven(amt.toString())}
                      className="flex-1 py-1 text-xs font-medium rounded border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">
                      ${amt}
                    </button>
                  ))}
                </div>
                {cashGiven && parseFloat(cashGiven) >= total && (
                  <p className="text-sm font-semibold text-green-600 dark:text-green-400 mt-1 text-center">Change: ${change.toFixed(2)}</p>
                )}
              </div>
            )}

            {/* Checkout button */}
            <button
              onClick={handleCheckout}
              disabled={!cart.length || transactionMutation.isPending || blockchypProcessing || (payMethod === 'cash' && cashGiven !== '' && parseFloat(cashGiven) < total)}
              className="w-full py-3 bg-primary-600 hover:bg-primary-700 text-white rounded-xl font-bold text-base transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {(transactionMutation.isPending || blockchypProcessing) ? (
                payMethod === 'blockchyp' ? 'Waiting for terminal...' : 'Processing...'
              ) : payMethod === 'blockchyp' ? (
                <><Smartphone className="h-4 w-4 inline mr-1" />Send $${total.toFixed(2)} to Terminal</>
              ) : `Charge $${total.toFixed(2)}`}
            </button>

            {/* Cash in/out */}
            <div className="flex gap-2">
              <button onClick={() => setShowCashIn(true)} className="flex-1 py-1.5 text-xs font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">+ Cash In</button>
              <button onClick={() => setShowCashOut(true)} className="flex-1 py-1.5 text-xs font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">- Cash Out</button>
            </div>
          </div>
        </div>
      </div>

      {/* Cash In/Out Modal */}
      {(showCashIn || showCashOut) && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-sm p-6">
            <h2 className="text-lg font-bold text-surface-900 dark:text-surface-100 mb-4">{showCashIn ? 'Cash In' : 'Cash Out'}</h2>
            <div className="space-y-3">
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount</label>
                <div className="relative">
                  <span className="absolute left-3 top-1/2 -translate-y-1/2 text-surface-400">$</span>
                  <input type="number" step="0.01" min="0.01" value={cashAmount} onChange={(e) => setCashAmount(e.target.value)} className="input w-full pl-6" placeholder="0.00" autoFocus />
                </div>
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Reason</label>
                <input value={cashReason} onChange={(e) => setCashReason(e.target.value)} className="input w-full" placeholder="Opening float, tip, etc." />
              </div>
            </div>
            <div className="flex gap-3 mt-5">
              <button onClick={() => { setShowCashIn(false); setShowCashOut(false); setCashAmount(''); setCashReason(''); }} className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors">Cancel</button>
              <button
                onClick={() => {
                  if (!cashAmount || parseFloat(cashAmount) <= 0) return toast.error('Enter a valid amount');
                  if (showCashIn) cashInMutation.mutate({ amount: parseFloat(cashAmount), reason: cashReason });
                  else cashOutMutation.mutate({ amount: parseFloat(cashAmount), reason: cashReason });
                }}
                disabled={cashInMutation.isPending || cashOutMutation.isPending}
                className="flex-1 px-4 py-2.5 bg-primary-600 hover:bg-primary-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
              >
                Confirm
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Dummy Credit Card Processing Modal */}
      {cardProcessing && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4">
          <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-sm p-8 text-center">
            {!cardApproved ? (
              <>
                <div className="h-16 w-16 mx-auto mb-5 rounded-full bg-primary-50 dark:bg-primary-900/30 flex items-center justify-center">
                  <Loader2 className="h-8 w-8 animate-spin text-primary-600 dark:text-primary-400" />
                </div>
                <h2 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-2">
                  Processing {payMethod === 'credit_card' ? 'Credit Card' : 'Debit Card'} Payment...
                </h2>
                <p className="text-sm text-surface-500 dark:text-surface-400 mb-1">
                  Amount: <span className="font-semibold">${total.toFixed(2)}</span>
                </p>
                <p className="text-xs text-surface-400 dark:text-surface-500 mt-3">
                  Please wait while we process your card...
                </p>
              </>
            ) : (
              <>
                <div className="h-16 w-16 mx-auto mb-5 rounded-full bg-green-100 dark:bg-green-900/30 flex items-center justify-center">
                  <CheckCircle2 className="h-8 w-8 text-green-600 dark:text-green-400" />
                </div>
                <h2 className="text-xl font-bold text-green-700 dark:text-green-300 mb-2">
                  Payment Approved
                </h2>
                <p className="text-sm text-surface-500 dark:text-surface-400 mb-1">
                  <span className="font-semibold">${total.toFixed(2)}</span> charged successfully
                </p>
                <div className="mt-4 rounded-lg bg-amber-50 dark:bg-amber-900/20 border border-amber-200 dark:border-amber-800 px-4 py-3">
                  <div className="flex items-center gap-2 mb-1">
                    <AlertCircle className="h-4 w-4 text-amber-600 dark:text-amber-400" />
                    <span className="text-xs font-semibold text-amber-700 dark:text-amber-300">Demo Mode</span>
                  </div>
                  <p className="text-xs text-amber-600 dark:text-amber-400">
                    In production, this will connect to your payment terminal.
                  </p>
                </div>
                <button
                  onClick={handleCardComplete}
                  disabled={transactionMutation.isPending}
                  className="mt-5 w-full py-3 bg-green-600 hover:bg-green-700 text-white rounded-xl font-bold text-base transition-colors disabled:opacity-50"
                >
                  {transactionMutation.isPending ? 'Completing...' : 'Complete Sale'}
                </button>
                <button
                  onClick={() => { setCardProcessing(false); setCardApproved(false); }}
                  className="mt-2 w-full py-2 text-sm font-medium text-surface-500 hover:text-surface-700 dark:hover:text-surface-300 transition-colors"
                >
                  Cancel
                </button>
              </>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
