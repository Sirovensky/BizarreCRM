import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  Banknote,
  CheckCircle2,
  ChevronLeft,
  ChevronRight,
  Clock,
  CreditCard,
  Edit3,
  FileText,
  Gift,
  History,
  Lock,
  Mail,
  MessageSquare,
  Minus,
  Monitor,
  Package,
  PackagePlus,
  Pause,
  Plus,
  Printer,
  Receipt,
  RotateCcw,
  ScanLine,
  Search,
  ShoppingCart,
  Smartphone,
  Star,
  Tag,
  Trash2,
  UserPlus,
  Wrench,
  X,
} from 'lucide-react';
import { api } from '@/api/client';
import {
  blockchypApi,
  customerApi,
  inventoryApi,
  leadApi,
  posApi,
  ticketApi,
} from '@/api/endpoints';
import { useDefaultTaxRateWithStatus } from '@/hooks/useDefaultTaxRate';
import { useUiStore } from '@/stores/uiStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDateTime, formatTime, generateIdempotencyKey, toLocalDateString } from '@/utils/format';
import { stripPhone } from '@/utils/phoneFormat';
import { computePosTotals } from './totals';
import { useUnifiedPosStore } from './store';
import { genId } from './types';
import type {
  CartItem,
  CustomerResult,
  MiscCartItem,
  PartEntry,
  ProductCartItem,
  RepairCartItem,
} from './types';

type PosMode =
  | 'gate'
  | 'sale'
  | 'repair-device'
  | 'repair-issue'
  | 'repair-quote'
  | 'repair-deposit'
  | 'tender-method'
  | 'tender-cash'
  | 'tender-card'
  | 'receipt'
  | 'held'
  | 'refund'
  | 'close-shift';

type TenderMethod = 'Cash' | 'Card' | 'Gift card' | 'Store credit';

interface PaymentLeg {
  method: TenderMethod;
  amount: number;
}

interface HeldCartRow {
  id: number;
  user_id?: number;
  label: string | null;
  cart_json: string;
  customer_id: number | null;
  total_cents: number | null;
  created_at: string;
  owner_first_name?: string | null;
  owner_last_name?: string | null;
}

interface HeldCartSnapshot {
  customer: CustomerResult | null;
  cartItems: CartItem[];
  discount: number;
  discountReason: string;
  memberDiscountApplied: boolean;
  meta: ReturnType<typeof useUnifiedPosStore.getState>['meta'];
  sourceTicketId: number | null;
}

interface ProductSearchItem {
  id: number;
  name: string;
  sku?: string | null;
  retail_price?: number | null;
  price?: number | null;
  in_stock?: number | null;
  item_type?: string | null;
  category?: string | null;
  tax_inclusive?: boolean | number | null;
  image_url?: string | null;
}

interface PosAppointment {
  id: number;
  lead_id: number | null;
  customer_id: number | null;
  title: string | null;
  start_time: string;
  end_time: string | null;
  assigned_to: number | null;
  status: string | null;
  notes: string | null;
  no_show?: number | boolean | null;
  customer_first_name?: string | null;
  customer_last_name?: string | null;
  assigned_first_name?: string | null;
  assigned_last_name?: string | null;
  lead_order_id?: string | null;
}

interface PosPickupTicket {
  id: number;
  order_id: string;
  customerName: string;
  itemSummary: string;
  progressLabel: string;
  total: number;
  statusName: string;
}

interface CreateCustomerDraft {
  customerType: 'individual' | 'business';
  firstName: string;
  lastName: string;
  phone: string;
  email: string;
  organization: string;
  comments: string;
  smsOptIn: boolean;
  emailOptIn: boolean;
}

interface CompletedSale {
  orderId: string;
  invoiceId: number | null;
  total: number;
  subtotal: number;
  tax: number;
  discount: number;
  payments: PaymentLeg[];
  change: number;
  customerName: string;
  customerPhone: string | null;
  items: CartItem[];
  completedAt: Date;
}

interface RepairDraft {
  deviceType: string;
  deviceName: string;
  imei: string;
  serial: string;
  condition: string;
  symptoms: string[];
  customerWords: string;
  diagnostic: string;
  serviceName: string;
  laborPrice: string;
  depositAmount: string;
  waiverHandled: boolean;
}

interface RefundLineSelection {
  line_item_id: number;
  quantity: number;
  reason: string;
}

const DEFAULT_REPAIR_DRAFT: RepairDraft = {
  deviceType: 'Phone',
  deviceName: 'iPhone',
  imei: '',
  serial: '',
  condition: 'Good',
  symptoms: [],
  customerWords: '',
  diagnostic: '',
  serviceName: 'Diagnostic repair',
  laborPrice: '79.00',
  depositAmount: '50.00',
  waiverHandled: false,
};

const DEVICE_TYPES = [
  { label: 'Phone', icon: Smartphone },
  { label: 'Tablet', icon: Monitor },
  { label: 'Laptop', icon: Monitor },
  { label: 'Console', icon: Package },
  { label: 'Watch', icon: Clock },
  { label: 'Other', icon: Wrench },
];

const EMPTY_CREATE_CUSTOMER_DRAFT: CreateCustomerDraft = {
  customerType: 'individual',
  firstName: '',
  lastName: '',
  phone: '',
  email: '',
  organization: '',
  comments: '',
  smsOptIn: true,
  emailOptIn: true,
};

function seedCustomerDraft(query: string, draft: CreateCustomerDraft): CreateCustomerDraft {
  const raw = query.trim();
  if (!raw) return draft;

  const next = { ...draft };
  const digits = stripPhone(raw);
  if (raw.includes('@') && !next.email) {
    next.email = raw.toLowerCase();
    return next;
  }
  if (digits.length >= 7 && !next.phone) {
    next.phone = raw;
    return next;
  }
  if (!next.firstName && !next.lastName) {
    const parts = raw.split(/\s+/).filter(Boolean);
    next.firstName = parts.shift() ?? '';
    next.lastName = parts.join(' ');
  }
  return next;
}

const SYMPTOMS = [
  'Cracked glass',
  'No power',
  'Battery drain',
  'Charging issue',
  'No sound',
  'Camera issue',
  'Water exposure',
  'Runs hot',
];

const CONDITIONS = ['Excellent', 'Good', 'Fair', 'Rough', 'Liquid damage'];

const CATALOG_FILTERS = ['All', 'Phones', 'Accessories', 'Repairs', 'Trade-in', 'Gift cards'];

const buttonBase =
  'inline-flex min-h-10 items-center justify-center gap-2 rounded-lg px-3 py-2 text-sm font-semibold transition focus-visible:outline-none disabled:cursor-not-allowed disabled:opacity-50';
const primaryButton =
  `${buttonBase} bg-primary-500 text-[#2b1400] shadow-sm hover:bg-primary-400 dark:bg-primary-500 dark:text-primary-950`;
const secondaryButton =
  `${buttonBase} border border-surface-200 bg-white text-surface-800 hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 dark:hover:bg-surface-700`;
const ghostButton =
  `${buttonBase} text-surface-600 hover:bg-surface-100 dark:text-surface-300 dark:hover:bg-surface-800`;
const dangerButton =
  `${buttonBase} border border-red-300 bg-red-50 text-red-700 hover:bg-red-100 dark:border-red-800/70 dark:bg-red-950/30 dark:text-red-300 dark:hover:bg-red-900/40`;
const inputClass =
  'w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 focus:border-primary-500 focus-visible:outline-none dark:border-surface-700 dark:bg-surface-900 dark:text-surface-50';

const toCents = (amount: number): number => Math.round(amount * 100);
const fromCents = (cents: number): number => cents / 100;
const parseMoney = (value: string): number => {
  const normalized = value.replace(/[^0-9.]/g, '');
  const parsed = Number.parseFloat(normalized);
  return Number.isFinite(parsed) ? parsed : 0;
};

function getCustomerName(customer: CustomerResult | null): string {
  if (!customer) return 'Walk-in customer';
  const full = `${customer.first_name ?? ''} ${customer.last_name ?? ''}`.trim();
  return full || customer.organization || `Customer #${customer.id}`;
}

function initials(name: string): string {
  const parts = name.trim().split(/\s+/).filter(Boolean);
  return (parts[0]?.[0] ?? 'W') + (parts[1]?.[0] ?? '');
}

function lineTitle(item: CartItem): string {
  if (item.type === 'repair') return `${item.serviceName} · ${item.device.device_name || item.device.device_type}`;
  return item.name;
}

function lineSubtitle(item: CartItem): string {
  if (item.type === 'repair') {
    const parts = item.parts.length;
    return `${item.device.imei || item.device.serial || 'No serial yet'} · ${parts} part${parts === 1 ? '' : 's'}`;
  }
  if (item.type === 'product') return `${item.sku || 'No SKU'} · qty ${item.quantity}`;
  return `Custom item · qty ${item.quantity}`;
}

function lineAmount(item: CartItem): number {
  if (item.type === 'repair') {
    const parts = item.parts.reduce((sum, part) => sum + part.quantity * part.price, 0);
    return Math.max(0, item.laborPrice - item.lineDiscount + parts);
  }
  if (item.type === 'product') return item.quantity * item.unitPrice;
  return item.quantity * item.unitPrice;
}

function apiPaymentMethod(method: TenderMethod): 'Cash' | 'Card' | 'Other' {
  if (method === 'Cash') return 'Cash';
  if (method === 'Card') return 'Card';
  return 'Other';
}

function stockLabel(product: ProductSearchItem): string {
  if (product.item_type === 'service') return 'service';
  const stock = Number(product.in_stock ?? 0);
  if (stock <= 0) return 'out';
  return `stock ${stock}`;
}

function appointmentCustomerName(appointment: PosAppointment): string {
  const full = `${appointment.customer_first_name ?? ''} ${appointment.customer_last_name ?? ''}`.trim();
  if (full) return full;
  if (appointment.customer_id) return `Customer #${appointment.customer_id}`;
  return appointment.title || 'Walk-in appointment';
}

function appointmentNote(appointment: PosAppointment): string {
  const title = appointment.title?.trim();
  const assigned = `${appointment.assigned_first_name ?? ''} ${appointment.assigned_last_name ?? ''}`.trim();
  if (title && title !== appointmentCustomerName(appointment)) return assigned ? `${title} - ${assigned}` : title;
  if (appointment.lead_order_id) return appointment.lead_order_id;
  return assigned ? `Assigned to ${assigned}` : 'Appointment';
}

function appointmentStatusLabel(appointment: PosAppointment, nowMs = Date.now()): string {
  if (appointment.no_show) return 'no-show';
  const status = appointment.status || 'scheduled';
  if (status !== 'scheduled' && status !== 'confirmed') return status;
  const startsAt = new Date(appointment.start_time).getTime();
  if (!Number.isFinite(startsAt)) return status;
  const minutes = Math.ceil((startsAt - nowMs) / 60000);
  if (minutes > 0 && minutes <= 120) return `in ${minutes}m`;
  if (minutes <= 0 && minutes > -60) return 'due now';
  return status;
}

function isReadyPickupStatus(statusName: string | null | undefined): boolean {
  const status = (statusName ?? '').toLowerCase();
  return [
    'ready for pickup',
    'ready to pick',
    'ready for collection',
    'waiting for payment',
    'qc passed',
    'repaired - qc',
    'repaired - waiting',
  ].some((keyword) => status.includes(keyword));
}

function customerNameFromTicket(ticket: any): string {
  const direct = `${ticket.customer?.first_name ?? ''} ${ticket.customer?.last_name ?? ''}`.trim();
  if (direct) return direct;
  const listName = `${ticket.c_first_name ?? ''} ${ticket.c_last_name ?? ''}`.trim();
  if (listName) return listName;
  return ticket.customer?.organization || ticket.c_organization || 'Walk-in';
}

function pickupItemSummary(ticket: any): string {
  const devices = Array.isArray(ticket.devices) ? ticket.devices : [];
  const deviceLabels = devices.map((device: any) => {
    const deviceName = device.device_name || device.device_type || 'Device';
    const serviceName = device.service?.name || device.service_name || device.issue || device.problem || '';
    return serviceName ? `${deviceName} - ${serviceName}` : deviceName;
  }).filter(Boolean);

  if (deviceLabels.length === 0) return ticket.latest_diagnostic_note || ticket.latest_internal_note || 'Repair ticket';
  if (deviceLabels.length === 1) return deviceLabels[0];
  return `${deviceLabels[0]} + ${deviceLabels.length - 1} more`;
}

function pickupProgressLabel(ticket: any): string {
  const status = String(ticket.status?.name || ticket.status_name || '').toLowerCase();
  const prefix = status.includes('qc') ? 'QC' : 'Ready';
  return `${prefix} ${formatTime(ticket.updated_at || ticket.created_at)}`;
}

function shapePickupTicket(ticket: any, fallback?: any): PosPickupTicket {
  const source = ticket ?? fallback ?? {};
  return {
    id: Number(source.id),
    order_id: source.order_id || `#${source.id}`,
    customerName: customerNameFromTicket(source),
    itemSummary: pickupItemSummary(source),
    progressLabel: pickupProgressLabel(source),
    total: Number(source.total ?? fallback?.total ?? 0),
    statusName: source.status?.name || source.status_name || fallback?.status_name || 'Ready',
  };
}

function buildCheckoutPayload(
  store: ReturnType<typeof useUnifiedPosStore.getState>,
  legs: PaymentLeg[],
) {
  const { cartItems, customer, discount, discountReason, meta, sourceTicketId } = store;
  const repairs = cartItems.filter((item): item is RepairCartItem => item.type === 'repair');
  const products = cartItems.filter((item): item is ProductCartItem => item.type === 'product');
  const miscItems = cartItems.filter((item): item is MiscCartItem => item.type === 'misc');
  const nonCardLegs = legs.filter((leg) => leg.method !== 'Card');

  return {
    mode: 'checkout' as const,
    customer_id: customer?.id ?? null,
    existing_ticket_id: sourceTicketId ?? null,
    ticket: {
      devices: repairs.map((repair) => ({
        device_type: repair.device.device_type,
        device_name: repair.device.device_name,
        device_model_id: repair.device.device_model_id,
        imei: repair.device.imei,
        serial: repair.device.serial,
        security_code: repair.device.security_code,
        color: repair.device.color,
        network: repair.device.network,
        pre_conditions: repair.device.pre_conditions,
        additional_notes: repair.device.additional_notes,
        device_location: repair.device.device_location,
        warranty: repair.device.warranty,
        warranty_days: repair.device.warranty_days,
        due_on: repair.device.due_date ?? null,
        service_name: repair.serviceName,
        repair_service_id: repair.repairServiceId,
        selected_grade_id: repair.selectedGradeId,
        labor_price: repair.laborPrice,
        line_discount: repair.lineDiscount,
        parts: repair.parts,
        taxable: repair.taxable,
      })),
      source: meta.source,
      referral_source: meta.referralSource || undefined,
      assigned_to: meta.assignedTo,
      discount,
      discount_reason: discountReason,
      internal_notes: meta.internalNotes,
      labels: meta.labels,
      due_date: meta.dueDate,
    },
    product_items: products.map((product) => ({
      inventory_item_id: product.inventoryItemId,
      name: product.name,
      sku: product.sku,
      quantity: product.quantity,
      unit_price: product.unitPrice,
      taxable: product.taxable,
      tax_inclusive: product.taxInclusive,
    })),
    misc_items: miscItems.map((item) => ({
      name: item.name,
      unit_price: item.unitPrice,
      quantity: item.quantity,
      taxable: item.taxable,
    })),
    payment_method: legs.length === 1 ? apiPaymentMethod(legs[0].method) : null,
    payment_amount: legs.length === 1 && legs[0].method !== 'Card'
      ? legs[0].amount
      : nonCardLegs.reduce((sum, leg) => sum + leg.amount, 0),
    payments: legs.length > 1 && nonCardLegs.length > 0
      ? nonCardLegs.map((leg) => ({ method: apiPaymentMethod(leg.method), amount: leg.amount }))
      : undefined,
  };
}

function Pill({
  children,
  tone = 'neutral',
  className,
}: {
  children: React.ReactNode;
  tone?: 'neutral' | 'success' | 'warning' | 'error' | 'info' | 'vip';
  className?: string;
}) {
  return (
    <span
      className={cn(
        'inline-flex items-center gap-1 rounded-full px-2.5 py-1 font-mono text-[11px] font-semibold uppercase leading-none',
        tone === 'neutral' && 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300',
        tone === 'success' && 'bg-emerald-500/12 text-emerald-700 dark:text-[#34C47E]',
        tone === 'warning' && 'bg-amber-500/14 text-amber-800 dark:text-[#E8A33D]',
        tone === 'error' && 'bg-red-500/12 text-red-700 dark:text-[#E2526C]',
        tone === 'info' && 'bg-cyan-500/12 text-cyan-700 dark:text-[#4DB8C9]',
        tone === 'vip' && 'bg-rose-500/12 text-rose-700 dark:text-[#C5566D]',
        className,
      )}
    >
      {children}
    </span>
  );
}

function Section({
  children,
  className,
}: {
  children: React.ReactNode;
  className?: string;
}) {
  return (
    <section
      className={cn(
        'rounded-lg border border-surface-200 bg-white text-surface-900 shadow-sm dark:border-surface-800 dark:bg-surface-900 dark:text-surface-50',
        className,
      )}
    >
      {children}
    </section>
  );
}

function Modal({
  title,
  children,
  footer,
  onClose,
}: {
  title: string;
  children: React.ReactNode;
  footer?: React.ReactNode;
  onClose: () => void;
}) {
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/45 p-4">
      <div
        role="dialog"
        aria-modal="true"
        aria-label={title}
        className="max-h-[90vh] w-full max-w-xl overflow-hidden rounded-lg border border-surface-200 bg-white shadow-2xl dark:border-surface-700 dark:bg-surface-900"
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-4 dark:border-surface-800">
          <h2 className="font-display text-2xl text-surface-900 dark:text-surface-50">{title}</h2>
          <button type="button" onClick={onClose} className={ghostButton} aria-label="Close">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="max-h-[65vh] overflow-auto px-5 py-4">{children}</div>
        {footer && <div className="border-t border-surface-200 px-5 py-4 dark:border-surface-800">{footer}</div>}
      </div>
    </div>
  );
}

function Stepper({ step }: { step: 'device' | 'issue' | 'quote' | 'deposit' }) {
  const steps: Array<{ key: typeof step; label: string }> = [
    { key: 'device', label: 'Device' },
    { key: 'issue', label: 'Issue' },
    { key: 'quote', label: 'Quote' },
    { key: 'deposit', label: 'Deposit' },
  ];
  const activeIndex = steps.findIndex((item) => item.key === step);
  return (
    <div className="flex items-center gap-3">
      {steps.map((item, index) => (
        <div key={item.key} className="flex items-center gap-3">
          <div className="flex items-center gap-2">
            <span
              className={cn(
                'grid h-6 w-6 place-items-center rounded-full border text-xs font-bold',
                index < activeIndex && 'border-emerald-500 bg-emerald-500 text-white',
                index === activeIndex && 'border-primary-500 bg-primary-500 text-[#2b1400]',
                index > activeIndex && 'border-surface-300 bg-surface-100 text-surface-900 dark:text-surface-500 dark:border-surface-700 dark:bg-surface-800',
              )}
            >
              {index < activeIndex ? <CheckCircle2 className="h-3.5 w-3.5" /> : index + 1}
            </span>
            <span className="text-sm font-semibold text-surface-700 dark:text-surface-300">{item.label}</span>
          </div>
          {index < steps.length - 1 && <div className="hidden h-px w-10 bg-surface-200 dark:bg-surface-700 sm:block" />}
        </div>
      ))}
    </div>
  );
}

export function UnifiedPosPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const setCommandPaletteOpen = useUiStore((state) => state.setCommandPaletteOpen);
  const taxState = useDefaultTaxRateWithStatus();

  const {
    customer,
    setCustomer,
    cartItems,
    addProduct,
    addMisc,
    addRepair,
    updateCartItem,
    updateProductQty,
    removeCartItem,
    clearDraft,
    resetAll,
    discount,
    discountReason,
    setDiscount,
    memberDiscountApplied,
    setMemberDiscountApplied,
    meta,
    setMeta,
    sourceTicketId,
    setSourceTicketId,
    ensureIdempotencyKey,
    rotateIdempotencyKey,
    showSuccess,
    setShowSuccess,
  } = useUnifiedPosStore();

  const [mode, setMode] = useState<PosMode>(() =>
    useUnifiedPosStore.getState().cartItems.length > 0 || useUnifiedPosStore.getState().customer ? 'sale' : 'gate',
  );
  const [walkInActive, setWalkInActive] = useState(() => {
    const state = useUnifiedPosStore.getState();
    return state.cartItems.length > 0 && !state.customer;
  });
  const [globalSearch, setGlobalSearch] = useState('');
  const [productSearch, setProductSearch] = useState('');
  const [activeFilter, setActiveFilter] = useState('All');
  const [scanFlash, setScanFlash] = useState(false);
  const [lineEditing, setLineEditing] = useState<CartItem | null>(null);
  const [discountOpen, setDiscountOpen] = useState(false);
  const [discountDraft, setDiscountDraft] = useState('');
  const [discountReasonDraft, setDiscountReasonDraft] = useState('cashier adjustment');
  const [customItemOpen, setCustomItemOpen] = useState(false);
  const [customName, setCustomName] = useState('');
  const [customPrice, setCustomPrice] = useState('');
  const [createCustomerOpen, setCreateCustomerOpen] = useState(false);
  const [createCustomerDraft, setCreateCustomerDraft] = useState<CreateCustomerDraft>(EMPTY_CREATE_CUSTOMER_DRAFT);
  const [repairDraft, setRepairDraft] = useState<RepairDraft>(DEFAULT_REPAIR_DRAFT);
  const [paidLegs, setPaidLegs] = useState<PaymentLeg[]>([]);
  const [selectedTenderMethod, setSelectedTenderMethod] = useState<TenderMethod>('Cash');
  const [amountEntry, setAmountEntry] = useState('');
  const [processing, setProcessing] = useState(false);
  const [terminalError, setTerminalError] = useState<string | null>(null);
  const [completedSale, setCompletedSale] = useState<CompletedSale | null>(null);
  const [refundInvoiceId, setRefundInvoiceId] = useState('');
  const [refundSelections, setRefundSelections] = useState<RefundLineSelection[]>([]);
  const [cashCount, setCashCount] = useState<Record<string, string>>({
    '100': '',
    '50': '',
    '20': '',
    '10': '',
    '5': '',
    '1': '',
    '0.25': '',
    '0.10': '',
    '0.05': '',
    '0.01': '',
  });

  const searchInputRef = useRef<HTMLInputElement | null>(null);
  const productInputRef = useRef<HTMLInputElement | null>(null);
  const scanBufferRef = useRef('');
  const scanTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const scanFlashTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const lastKeyTimeRef = useRef(0);
  const hydratedRef = useRef<string | null>(null);

  useEffect(() => {
    if (showSuccess) setShowSuccess(null);
  }, [showSuccess, setShowSuccess]);

  const totals = useMemo(
    () =>
      computePosTotals({
        cartItems,
        discount,
        customer,
        memberDiscountApplied,
        taxRate: taxState.rate,
      }),
    [cartItems, discount, customer, memberDiscountApplied, taxState.rate],
  );

  const paidCents = useMemo(
    () => paidLegs.reduce((sum, leg) => sum + toCents(leg.amount), 0),
    [paidLegs],
  );
  const remainingCents = Math.max(0, totals.totalCents - paidCents);
  const cartAwake = mode !== 'gate' || customer !== null || cartItems.length > 0 || walkInActive;

  const customerSearch = useQuery({
    queryKey: ['pos-customer-search', globalSearch],
    queryFn: ({ signal }) => customerApi.search(globalSearch, signal),
    enabled: globalSearch.trim().length >= 2 && mode === 'gate',
    staleTime: 15_000,
  });

  const customerResults: CustomerResult[] = useMemo(() => {
    const payload = customerSearch.data?.data?.data;
    const raw = Array.isArray(payload)
      ? payload
      : Array.isArray(payload?.customers)
        ? payload.customers
        : [];
    return raw.slice(0, 6).map((item: any) => ({
      id: Number(item.id),
      first_name: item.first_name ?? '',
      last_name: item.last_name ?? '',
      phone: item.phone ?? null,
      mobile: item.mobile ?? null,
      email: item.email ?? null,
      organization: item.organization ?? null,
      group_name: item.group_name,
      group_discount_pct: item.group_discount_pct,
      group_discount_type: item.group_discount_type,
      group_auto_apply: item.group_auto_apply,
    }));
  }, [customerSearch.data]);

  const todayRange = useMemo(() => {
    const today = new Date();
    const tomorrow = new Date(today);
    tomorrow.setDate(today.getDate() + 1);
    return {
      today: toLocalDateString(today),
      tomorrow: toLocalDateString(tomorrow),
    };
  }, []);

  const appointmentsQuery = useQuery({
    queryKey: ['pos-todays-appointments', todayRange.today],
    queryFn: () =>
      leadApi.appointments({
        from_date: todayRange.today,
        to_date: todayRange.tomorrow,
      }),
    enabled: mode === 'gate',
    staleTime: 30_000,
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });

  const todaysAppointments: PosAppointment[] = useMemo(() => {
    const payload = appointmentsQuery.data?.data?.data;
    const raw = Array.isArray(payload?.appointments)
      ? payload.appointments
      : Array.isArray(payload)
        ? payload
        : [];

    return raw.slice(0, 7).map((item: any) => ({
      id: Number(item.id),
      lead_id: item.lead_id == null ? null : Number(item.lead_id),
      customer_id: item.customer_id == null ? null : Number(item.customer_id),
      title: item.title ?? null,
      start_time: item.start_time,
      end_time: item.end_time ?? null,
      assigned_to: item.assigned_to == null ? null : Number(item.assigned_to),
      status: item.status ?? null,
      notes: item.notes ?? null,
      no_show: item.no_show,
      customer_first_name: item.customer_first_name ?? null,
      customer_last_name: item.customer_last_name ?? null,
      assigned_first_name: item.assigned_first_name ?? null,
      assigned_last_name: item.assigned_last_name ?? null,
      lead_order_id: item.lead_order_id ?? null,
    }));
  }, [appointmentsQuery.data]);

  const readyPickupQuery = useQuery({
    queryKey: ['pos-ready-pickup-tickets'],
    queryFn: async () => {
      const listRes = await ticketApi.list({
        status_group: 'active',
        pagesize: 100,
        sort_by: 'updated_at',
        sort_order: 'DESC',
      });
      const payload = listRes.data?.data;
      const rows = Array.isArray(payload?.tickets)
        ? payload.tickets
        : Array.isArray(listRes.data?.tickets)
          ? listRes.data.tickets
          : [];
      const readyRows = rows.filter((ticket: any) => isReadyPickupStatus(ticket.status_name));
      const visibleRows = readyRows.slice(0, 4);
      const tickets = await Promise.all(
        visibleRows.map(async (row: any) => {
          try {
            const detailRes = await ticketApi.get(Number(row.id));
            return shapePickupTicket(detailRes.data?.data, row);
          } catch {
            return shapePickupTicket(row);
          }
        }),
      );

      return {
        total: readyRows.length,
        tickets,
      };
    },
    enabled: mode === 'gate',
    staleTime: 30_000,
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });

  const readyPickup = readyPickupQuery.data ?? { total: 0, tickets: [] as PosPickupTicket[] };

  const productsQuery = useQuery({
    queryKey: ['pos-products-rewrite', productSearch, activeFilter],
    queryFn: ({ signal }) =>
      posApi.products({
        keyword: productSearch || undefined,
        category: activeFilter !== 'All' ? activeFilter : undefined,
        show_out_of_stock: '1',
        limit: 32,
      }, signal),
    staleTime: 30_000,
    enabled: mode === 'sale',
  });

  const products: ProductSearchItem[] = productsQuery.data?.data?.data?.items ?? [];
  const categories: string[] = productsQuery.data?.data?.data?.categories ?? CATALOG_FILTERS.slice(1);

  const heldCarts = useQuery({
    queryKey: ['pos-held-carts'],
    queryFn: () => api.get<{ success: boolean; data: HeldCartRow[] }>('/pos/held-carts'),
    enabled: mode === 'held',
    staleTime: 10_000,
  });

  const blockchypStatus = useQuery({
    queryKey: ['blockchyp-status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 30_000,
    enabled: mode === 'tender-method' || mode === 'tender-card',
  });
  const blockchypConfigured = blockchypStatus.data?.data?.data?.enabled ?? false;
  const terminalName = blockchypStatus.data?.data?.data?.terminalName ?? 'terminal';

  const ticketParam = searchParams.get('ticket');
  const customerParam = searchParams.get('customer') || searchParams.get('customer_id');

  const ticketQuery = useQuery({
    queryKey: ['ticket', Number(ticketParam)],
    queryFn: () => ticketApi.get(Number(ticketParam)),
    enabled: !!ticketParam && hydratedRef.current !== ticketParam,
  });

  const customerHydration = useQuery({
    queryKey: ['customer', Number(customerParam)],
    queryFn: () => customerApi.get(Number(customerParam)),
    enabled: !!customerParam && !ticketParam && hydratedRef.current !== `c${customerParam}`,
  });

  useEffect(() => {
    if (!ticketParam || hydratedRef.current === ticketParam) return;
    const ticket = ticketQuery.data?.data?.data;
    if (!ticket) return;

    hydratedRef.current = ticketParam;
    resetAll();
    setWalkInActive(!ticket.customer);
    setSourceTicketId(Number(ticketParam));
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

    for (const device of ticket.devices || []) {
      const parts: PartEntry[] = (device.parts || []).map((part: any) => ({
        _key: genId(),
        inventory_item_id: part.inventory_item_id || 0,
        name: part.name || part.item_name || 'Part',
        sku: part.item_sku || part.sku || null,
        quantity: part.quantity || 1,
        price: part.price || 0,
        taxable: true,
        status: part.status || 'available',
      }));
      addRepair({
        type: 'repair',
        id: genId(),
        device: {
          device_type: device.device_type || 'Device',
          device_name: device.device_name || 'Unknown device',
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
        taxable: false,
        sourceTicketId: Number(ticketParam),
        sourceTicketOrderId: ticket.order_id || `T-${ticketParam}`,
      });
    }
    setMode('sale');
    setSearchParams({}, { replace: true });
  }, [ticketParam, ticketQuery.data, resetAll, setCustomer, addRepair, setSearchParams, setSourceTicketId]);

  useEffect(() => {
    if (!customerParam || ticketParam || hydratedRef.current === `c${customerParam}`) return;
    const cust = customerHydration.data?.data?.data;
    if (!cust) return;
    hydratedRef.current = `c${customerParam}`;
    resetAll();
    setWalkInActive(false);
    setCustomer({
      id: cust.id,
      first_name: cust.first_name,
      last_name: cust.last_name,
      phone: cust.phone || null,
      mobile: cust.mobile || null,
      email: cust.email || null,
      organization: cust.organization || null,
      group_name: cust.group_name,
      group_discount_pct: cust.group_discount_pct,
      group_discount_type: cust.group_discount_type,
      group_auto_apply: cust.group_auto_apply,
    });
    setMode('sale');
    setSearchParams({}, { replace: true });
  }, [customerParam, ticketParam, customerHydration.data, resetAll, setCustomer, setSearchParams]);

  useEffect(() => {
    if (mode === 'gate' && (customer || cartItems.length > 0 || walkInActive)) setMode('sale');
  }, [mode, customer, cartItems.length, walkInActive]);

  useEffect(() => {
    if (cartItems.length === 0 && !customer && !walkInActive && mode === 'sale') setMode('gate');
  }, [cartItems.length, customer, walkInActive, mode]);

  const addProductToCart = useCallback((product: ProductSearchItem) => {
    const isService = product.item_type === 'service';
    const stockCap = isService ? undefined : Number(product.in_stock ?? 0);
    if (stockCap === 0 && !isService) {
      toast.error(`${product.name} is out of stock`);
      return;
    }
    const existing = useUnifiedPosStore.getState().cartItems.find(
      (item) => item.type === 'product' && item.inventoryItemId === product.id,
    );
    if (existing?.type === 'product' && stockCap != null && existing.quantity + 1 > stockCap) {
      toast.error(`Only ${stockCap} in stock`);
      return;
    }
    addProduct({
      type: 'product',
      id: genId(),
      inventoryItemId: product.id,
      name: product.name,
      sku: product.sku || null,
      quantity: 1,
      unitPrice: Number(product.retail_price ?? product.price ?? 0),
      taxable: true,
      taxInclusive: !!product.tax_inclusive,
    }, { stockCap });
    setMode('sale');
  }, [addProduct]);

  useEffect(() => {
    const handleScanner = (event: KeyboardEvent) => {
      if (processing || lineEditing || discountOpen || customItemOpen) return;
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) return;

      const now = Date.now();
      const sinceLast = now - lastKeyTimeRef.current;
      lastKeyTimeRef.current = now;

      if (event.key === 'Enter' && scanBufferRef.current.length >= 4) {
        const code = scanBufferRef.current;
        scanBufferRef.current = '';
        if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
        setScanFlash(true);
        if (scanFlashTimerRef.current) clearTimeout(scanFlashTimerRef.current);
        scanFlashTimerRef.current = setTimeout(() => setScanFlash(false), 1000);

        const lookup = /^\d{8,}$/.test(code)
          ? inventoryApi.lookupBarcode(code).then((res) => res.data?.data)
          : posApi.products({ keyword: code, limit: 20 }).then((res) => res.data?.data?.items?.[0]);
        lookup
          .then((found: ProductSearchItem | null | undefined) => {
            if (found) {
              addProductToCart(found);
              toast.success(`Scanned ${found.name}`);
            } else {
              setCustomName(code);
              setCustomItemOpen(true);
              toast.error('No item matched that scan');
            }
          })
          .catch(() => toast.error('Scan lookup failed'));
        return;
      }

      if (event.key.length === 1) {
        scanBufferRef.current = sinceLast > 100 ? event.key : scanBufferRef.current + event.key;
        if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
        scanTimerRef.current = setTimeout(() => {
          scanBufferRef.current = '';
        }, 200);
      }
    };
    window.addEventListener('keydown', handleScanner);
    return () => {
      window.removeEventListener('keydown', handleScanner);
      if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
      if (scanFlashTimerRef.current) clearTimeout(scanFlashTimerRef.current);
    };
  }, [addProductToCart, customItemOpen, discountOpen, lineEditing, processing]);

  const startNewSale = useCallback(() => {
    setCompletedSale(null);
    setPaidLegs([]);
    setTerminalError(null);
    rotateIdempotencyKey();
    clearDraft();
    setWalkInActive(false);
    setCreateCustomerOpen(false);
    setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
    setMode('gate');
    setGlobalSearch('');
    setProductSearch('');
    searchInputRef.current?.focus();
  }, [clearDraft, rotateIdempotencyKey]);

  const holdMutation = useMutation({
    mutationFn: async () => {
      const snapshot: HeldCartSnapshot = {
        customer,
        cartItems,
        discount,
        discountReason,
        memberDiscountApplied,
        meta,
        sourceTicketId,
      };
      const label = customer ? getCustomerName(customer) : cartItems[0] ? lineTitle(cartItems[0]) : 'Walk-in sale';
      return api.post('/pos/held-carts', {
        cart_json: JSON.stringify(snapshot),
        label,
        customer_id: customer?.id ?? null,
        total_cents: totals.totalCents,
      });
    },
    onSuccess: () => {
      toast.success('Sale held');
      queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
      clearDraft();
      setWalkInActive(false);
      setPaidLegs([]);
      setMode('gate');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not hold sale'),
  });

  const restoreSnapshot = useCallback((snapshot: HeldCartSnapshot) => {
    resetAll();
    setCustomer(snapshot.customer ?? null);
    setWalkInActive(!snapshot.customer);
    setDiscount(snapshot.discount ?? 0, snapshot.discountReason ?? '');
    setMemberDiscountApplied(!!snapshot.memberDiscountApplied);
    setMeta(snapshot.meta ?? {});
    setSourceTicketId(snapshot.sourceTicketId ?? null);
    for (const item of snapshot.cartItems ?? []) {
      if (item.type === 'product') addProduct(item);
      if (item.type === 'misc') addMisc(item);
      if (item.type === 'repair') addRepair(item);
    }
    setMode('sale');
  }, [addMisc, addProduct, addRepair, resetAll, setCustomer, setDiscount, setMemberDiscountApplied, setMeta, setSourceTicketId]);

  const recallMutation = useMutation({
    mutationFn: (id: number) => api.post<{ success: boolean; data: HeldCartRow }>(`/pos/held-carts/${id}/recall`),
    onSuccess: (res) => {
      const row = res.data.data;
      restoreSnapshot(JSON.parse(row.cart_json) as HeldCartSnapshot);
      queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
      toast.success('Held sale restored');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not recall sale'),
  });

  const discardHeldMutation = useMutation({
    mutationFn: (id: number) => api.delete(`/pos/held-carts/${id}`),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
      toast.success('Held sale discarded');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not discard sale'),
  });

  const refundQuery = useQuery({
    queryKey: ['pos-returnable-invoice', refundInvoiceId],
    queryFn: () => posApi.returnableInvoice(Number(refundInvoiceId)),
    enabled: mode === 'refund' && /^\d+$/.test(refundInvoiceId),
    staleTime: 10_000,
  });

  const refundInvoice = refundQuery.data?.data?.data;
  const refundMutation = useMutation({
    mutationFn: () => posApi.return({
      invoice_id: Number(refundInvoiceId),
      items: refundSelections.filter((line) => line.quantity > 0),
    }),
    onSuccess: () => {
      toast.success('Refund processed');
      setRefundSelections([]);
      queryClient.invalidateQueries({ queryKey: ['pos-returnable-invoice', refundInvoiceId] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not process refund'),
  });

  const closeShiftMutation = useMutation({
    mutationFn: () => api.post('/pos/open-drawer', { reason: 'close-shift-count' }),
    onSuccess: () => toast.success('Drawer command sent'),
    onError: () => toast.error('Could not contact cash drawer'),
  });

  useEffect(() => {
    const handleKeys = (event: KeyboardEvent) => {
      const mod = event.metaKey || event.ctrlKey;
      if (!mod) return;
      const key = event.key.toLowerCase();
      if (key === 'k') {
        event.preventDefault();
        setCommandPaletteOpen(true);
      }
      if (key === 'n') {
        event.preventDefault();
        startNewSale();
      }
      if (key === 'h') {
        event.preventDefault();
        if (cartItems.length > 0 || customer) holdMutation.mutate();
      }
      if (key === 'r') {
        event.preventDefault();
        setMode('held');
      }
      if (key === 'd') {
        event.preventDefault();
        setDiscountOpen(true);
      }
      if (key === 'b') {
        event.preventDefault();
        productInputRef.current?.focus();
      }
      if (event.key === 'Enter') {
        event.preventDefault();
        if (mode === 'sale' && cartItems.length > 0) setMode('tender-method');
      }
    };
    window.addEventListener('keydown', handleKeys);
    return () => window.removeEventListener('keydown', handleKeys);
  }, [cartItems.length, customer, holdMutation, mode, setCommandPaletteOpen, startNewSale]);

  const saveRepairToCart = useCallback(() => {
    const labor = parseMoney(repairDraft.laborPrice);
    if (!repairDraft.deviceName.trim()) {
      toast.error('Add a device name first');
      setMode('repair-device');
      return;
    }
    if (labor <= 0) {
      toast.error('Quote must include a labor amount');
      setMode('repair-quote');
      return;
    }
    addRepair({
      type: 'repair',
      id: genId(),
      device: {
        device_type: repairDraft.deviceType,
        device_name: repairDraft.deviceName,
        device_model_id: null,
        imei: repairDraft.imei,
        serial: repairDraft.serial,
        security_code: '',
        color: '',
        network: '',
        pre_conditions: repairDraft.symptoms,
        additional_notes: [repairDraft.customerWords, repairDraft.diagnostic].filter(Boolean).join('\n'),
        device_location: 'front counter',
        warranty: false,
        warranty_days: 90,
      },
      serviceName: repairDraft.serviceName || 'Repair',
      repairServiceId: null,
      selectedGradeId: null,
      laborPrice: labor,
      lineDiscount: 0,
      parts: [],
      taxable: false,
    });
    toast.success('Repair added to cart');
    setRepairDraft(DEFAULT_REPAIR_DRAFT);
    setMode('sale');
  }, [addRepair, repairDraft]);

  const submitCheckout = useCallback(async (finalLeg: PaymentLeg) => {
    const legs = [...paidLegs, finalLeg].filter((leg) => leg.amount > 0);
    const finalPaidCents = legs.reduce((sum, leg) => sum + toCents(leg.amount), 0);
    if (finalPaidCents < totals.totalCents) {
      setPaidLegs(legs);
      setAmountEntry(fromCents(totals.totalCents - finalPaidCents).toFixed(2));
      setMode('tender-method');
      toast.success(`${formatCurrency(fromCents(finalPaidCents))} paid. ${formatCurrency(fromCents(totals.totalCents - finalPaidCents))} remaining.`);
      return;
    }
    if (legs.some((leg) => leg.method === 'Card') && !blockchypConfigured) {
      toast.error('Pair a BlockChyp terminal before accepting card');
      return;
    }

    setProcessing(true);
    setTerminalError(null);
    try {
      const snapshotItems = [...cartItems];
      const snapshotCustomer = customer;
      const payload = buildCheckoutPayload(useUnifiedPosStore.getState(), legs);
      const idempotencyKey = ensureIdempotencyKey();
      const res = await posApi.checkoutWithTicket(payload, idempotencyKey);
      const invoiceId: number | null = res.data?.data?.invoice?.id ?? res.data?.data?.invoice_id ?? null;

      const cardLegs = legs.filter((leg) => leg.method === 'Card');
      if (invoiceId && cardLegs.length > 0) {
        for (const leg of cardLegs) {
          const terminalRes = await blockchypApi.processPayment(
            invoiceId,
            generateIdempotencyKey('bc'),
            undefined,
            cardLegs.length > 1 || legs.length > 1 ? leg.amount : undefined,
          );
          const terminalResult = terminalRes.data?.data;
          if (!terminalResult?.success) {
            const message = terminalResult?.error || terminalResult?.responseDescription || 'Payment declined';
            setTerminalError(`Invoice created but card was not approved: ${message}`);
            return;
          }
        }
      }

      const cashPaid = legs.filter((leg) => leg.method === 'Cash').reduce((sum, leg) => sum + leg.amount, 0);
      const overpay = Math.max(0, toCents(cashPaid) + legs.filter((leg) => leg.method !== 'Cash').reduce((sum, leg) => sum + toCents(leg.amount), 0) - totals.totalCents);
      setCompletedSale({
        orderId: res.data?.data?.invoice?.order_id || res.data?.data?.ticket?.order_id || res.data?.data?.order_id || 'POS',
        invoiceId,
        total: totals.total,
        subtotal: totals.subtotal,
        tax: totals.tax,
        discount: totals.discountAmount,
        payments: legs,
        change: fromCents(overpay),
        customerName: getCustomerName(snapshotCustomer),
        customerPhone: snapshotCustomer?.phone || snapshotCustomer?.mobile || null,
        items: snapshotItems,
        completedAt: new Date(),
      });
      clearDraft();
      setPaidLegs([]);
      setMode('receipt');
      window.dispatchEvent(new CustomEvent('pos:payment-completed'));
      toast.success('Sale complete');
    } catch (err: any) {
      toast.error(err?.response?.data?.message || err?.message || 'Checkout failed');
    } finally {
      setProcessing(false);
    }
  }, [paidLegs, totals, blockchypConfigured, cartItems, customer, ensureIdempotencyKey, clearDraft]);

  const acceptTender = useCallback((method: TenderMethod) => {
    const amount = parseMoney(amountEntry || fromCents(remainingCents).toFixed(2));
    if (amount <= 0) {
      toast.error('Enter an amount first');
      return;
    }
    if (method === 'Card' && toCents(amount) > remainingCents) {
      toast.error('Card amount cannot exceed the remaining balance');
      return;
    }
    void submitCheckout({ method, amount });
  }, [amountEntry, remainingCents, submitCheckout]);

  const applyDiscount = () => {
    const amount = parseMoney(discountDraft);
    setDiscount(amount, discountReasonDraft || 'cashier adjustment');
    setDiscountOpen(false);
  };

  const addCustomItem = () => {
    const price = parseMoney(customPrice);
    if (!customName.trim() || price <= 0) {
      toast.error('Add a name and price');
      return;
    }
    addMisc({
      type: 'misc',
      id: genId(),
      name: customName.trim(),
      unitPrice: price,
      quantity: 1,
      taxable: true,
    });
    setCustomName('');
    setCustomPrice('');
    setCustomItemOpen(false);
    setMode('sale');
  };

  const selectCustomer = (nextCustomer: CustomerResult) => {
    setCustomer(nextCustomer);
    setWalkInActive(false);
    setCreateCustomerOpen(false);
    setGlobalSearch('');
    setMode('sale');
    setTimeout(() => productInputRef.current?.focus(), 0);
  };

  const startWalkIn = () => {
    setCustomer(null);
    setWalkInActive(true);
    setCreateCustomerOpen(false);
    setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
    setGlobalSearch('');
    setMode('sale');
    setTimeout(() => productInputRef.current?.focus(), 0);
  };

  const createCustomerMutation = useMutation({
    mutationFn: () => customerApi.create({
      first_name: createCustomerDraft.firstName.trim(),
      last_name: createCustomerDraft.lastName.trim() || undefined,
      phone: stripPhone(createCustomerDraft.phone) || undefined,
      email: createCustomerDraft.email.trim() || undefined,
      organization: createCustomerDraft.organization.trim() || undefined,
      type: createCustomerDraft.customerType,
      comments: createCustomerDraft.comments.trim() || undefined,
      sms_opt_in: createCustomerDraft.smsOptIn,
      email_opt_in: createCustomerDraft.emailOptIn,
      source: 'POS',
    }),
    onSuccess: (res) => {
      const created = res.data?.data;
      if (!created?.id) {
        toast.error('Customer created, but the record did not load');
        return;
      }

      setCustomer({
        id: Number(created.id),
        first_name: created.first_name ?? '',
        last_name: created.last_name ?? '',
        phone: created.phone || null,
        mobile: created.mobile || null,
        email: created.email || null,
        organization: created.organization || null,
        group_name: created.group_name,
        group_discount_pct: created.group_discount_pct,
        group_discount_type: created.group_discount_type,
        group_auto_apply: created.group_auto_apply,
      });
      setWalkInActive(false);
      setCreateCustomerOpen(false);
      setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
      setGlobalSearch('');
      setMode('sale');
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['pos-customer-search'] });
      toast.success('Customer created');
      setTimeout(() => productInputRef.current?.focus(), 0);
    },
    onError: (err: any) => {
      const message = err?.response?.data?.message || err?.response?.data?.error || 'Failed to create customer';
      toast.error(message, { duration: 6000 });
    },
  });

  const submitCreateCustomer = () => {
    if (!createCustomerDraft.firstName.trim()) {
      toast.error('First name is required');
      return;
    }
    createCustomerMutation.mutate();
  };

  const openInlineCustomerCreate = () => {
    const seeded = seedCustomerDraft(globalSearch, createCustomerDraft);
    setCreateCustomerDraft(seeded);
    setCreateCustomerOpen(true);
  };

  const cancelInlineCustomerCreate = () => {
    if (createCustomerMutation.isPending) return;
    setCreateCustomerOpen(false);
    setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
  };

  const selectAppointment = async (appointment: PosAppointment) => {
    if (appointment.customer_id) {
      const fallbackCustomer: CustomerResult = {
        id: appointment.customer_id,
        first_name: appointment.customer_first_name ?? '',
        last_name: appointment.customer_last_name ?? '',
        phone: null,
        mobile: null,
        email: null,
        organization: null,
      };

      selectCustomer(fallbackCustomer);

      try {
        const res = await customerApi.get(appointment.customer_id);
        const loaded = res.data?.data;
        if (loaded) {
          setCustomer({
            id: loaded.id,
            first_name: loaded.first_name ?? '',
            last_name: loaded.last_name ?? '',
            phone: loaded.phone || null,
            mobile: loaded.mobile || null,
            email: loaded.email || null,
            organization: loaded.organization || null,
            group_name: loaded.group_name,
            group_discount_pct: loaded.group_discount_pct,
            group_discount_type: loaded.group_discount_type,
            group_auto_apply: loaded.group_auto_apply,
          });
        }
      } catch {
        toast.error('Customer details did not load, but the appointment customer is selected');
      }
      return;
    }

    if (appointment.lead_id) {
      navigate(`/leads/${appointment.lead_id}`);
      return;
    }

    navigate('/calendar');
  };

  const openReadyPickupTicket = (ticket: PosPickupTicket) => {
    hydratedRef.current = null;
    setSearchParams({ ticket: String(ticket.id) });
  };

  const cartLineCount = cartItems.reduce((sum, item) => sum + (item.type === 'product' || item.type === 'misc' ? item.quantity : 1), 0);
  const title = mode === 'gate'
    ? 'New sale'
    : mode === 'held'
      ? 'Held sales - recall'
      : mode === 'refund'
        ? 'Refund'
        : mode === 'close-shift'
          ? 'Close shift'
          : mode.startsWith('repair')
            ? 'Repair intake'
            : mode.startsWith('tender')
              ? 'Tender'
              : mode === 'receipt'
                ? 'Sale complete'
                : `New sale - ${getCustomerName(customer)}`;
  const subtitle =
    mode === 'gate'
      ? 'Pick a customer to begin · or take a walk-in'
      : mode === 'held'
        ? 'Resume a parked sale or discard one to free the slot'
        : mode === 'refund'
          ? 'Pick lines + a refund-to method · manager PIN above threshold'
          : mode === 'close-shift'
            ? 'Count the drawer · variance ≤ $5 passes · larger needs a manager note'
            : mode === 'repair-device'
              ? 'Step 1 of 4 · pick a device or scan its IMEI'
              : mode === 'repair-issue'
                ? 'Step 2 of 4 · capture symptoms + condition'
                : mode === 'repair-quote'
                  ? 'Step 3 of 4 · diagnostic + quote'
                  : mode === 'repair-deposit'
                    ? 'Step 4 of 4 · take deposit · drop-off waiver'
                    : mode === 'tender-method'
                      ? 'Pick a method · cart locks during tender'
                      : mode === 'tender-cash'
                        ? 'Type the amount · ↵ confirms · drawer auto-opens'
                        : mode === 'tender-card'
                          ? 'Customer terminal handles tap / chip / swipe + tip'
                          : cartLineCount > 0
                            ? `${cartLineCount} line${cartLineCount === 1 ? '' : 's'} in cart · ${formatCurrency(totals.total)} due`
                            : 'Browse the catalog or scan to start adding items';

  return (
    <div className="-m-6 flex h-[calc(100vh-4rem-var(--dev-banner-h,0px))] min-h-[720px] flex-col overflow-hidden bg-surface-50 dark:bg-[#050403] text-surface-900 dark:text-surface-50">
      <div className="flex h-[38px] shrink-0 items-center gap-2 border-b border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#080706] px-4">
        <button
          type="button"
          onClick={() => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate')}
          className={cn(
            'inline-flex h-7 min-w-[190px] items-center gap-2 rounded-t-lg px-3 text-xs font-semibold',
            !['held', 'refund', 'close-shift', 'receipt'].includes(mode)
              ? 'bg-surface-100 dark:bg-[#0f0e0c] text-primary-700 dark:text-[#fdeed0]'
              : 'text-surface-900 dark:text-surface-500 hover:text-surface-600 dark:text-surface-300',
          )}
        >
          <span className="grid h-3 w-3 place-items-center rounded-[3px] bg-primary-500 dark:bg-[#fdeed0] text-[8px] font-black text-[#2b1400]">B</span>
          POS
        </button>
        {(customer || cartItems.length > 0) && (
          <button
            type="button"
            onClick={() => holdMutation.mutate()}
            disabled={cartItems.length === 0 && !customer}
            className="inline-flex h-7 min-w-[170px] items-center gap-2 rounded-t-lg px-3 text-xs font-semibold text-surface-900 dark:text-surface-500 hover:text-surface-600 dark:text-surface-300 disabled:opacity-50"
          >
            <Pause className="h-3.5 w-3.5" />
            Hold current sale
          </button>
        )}
      </div>

      <header className={cn(
        'flex shrink-0 items-center gap-5 border-b border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#080706] px-5',
        // Customer gate gets a taller bar (mockup Frame 03 makes the search the
        // primary entry point at this step). Other modes keep the compact
        // 56px bar to leave more room for main canvas content.
        mode === 'gate' ? 'h-[68px]' : 'h-14',
      )}>
        <div className="min-w-[220px]">
          <div className="text-[15px] font-bold text-surface-900 dark:text-surface-100">{title}</div>
          {subtitle && <div className="mt-0.5 text-[11.5px] text-surface-900 dark:text-surface-500">{subtitle}</div>}
        </div>
        <div className="relative min-w-[260px] flex-1">
          <Search className={cn(
            'absolute left-4 top-1/2 -translate-y-1/2 text-surface-900 dark:text-surface-500',
            mode === 'gate' ? 'h-[18px] w-[18px]' : 'h-4 w-4',
          )} />
          <input
            ref={mode === 'gate' ? searchInputRef : undefined}
            value={mode === 'gate' ? globalSearch : productSearch}
            onChange={(event) => (mode === 'gate' ? setGlobalSearch(event.target.value) : setProductSearch(event.target.value))}
            data-pos-customer-search={mode === 'gate' ? 'true' : undefined}
            className={cn(
              'w-full rounded-[10px] border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] pr-24 font-semibold text-surface-900 dark:text-surface-100 placeholder:text-surface-400 dark:placeholder:text-surface-500 focus:border-primary-500 dark:focus:border-[#fdeed0] focus-visible:outline-none',
              mode === 'gate' ? 'h-12 pl-12 text-[15px]' : 'h-11 pl-11 text-sm',
            )}
            placeholder={mode === 'gate' ? 'Search customer · phone · email · ticket # · SKU' : 'Search items or scan'}
          />
          <span className="absolute right-3 top-1/2 -translate-y-1/2 rounded border border-surface-200 dark:border-[#1e1c1a] bg-surface-100 dark:bg-[#0f0e0c] px-2 py-0.5 font-mono text-[10px] text-surface-400">⌘K</span>
        </div>
        {/* Status + action chips. Mockup uses chip-pills here so they read as
            secondary status, not as primary CTAs. Refund + Shift live in a
            ⋯ overflow menu so the topbar stays calm; Recall is always
            visible because it's part of the parallel-sale workflow. */}
        <div className="flex items-center gap-2">
          {!taxState.isLoaded && <Pill tone="warning">tax loading</Pill>}
          {scanFlash && <Pill tone="success">scan detected</Pill>}
          {mode === 'gate' && (
            <button
              type="button"
              onClick={() => setMode('held')}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-[#fdeed0]/40"
            >
              <History className="h-3 w-3" /> Recall
              <span className="ml-1 rounded border border-surface-200 dark:border-[#1e1c1a] bg-surface-50 dark:bg-[#0f0e0c] px-1.5 font-mono text-[9px] text-surface-400">⌘R</span>
            </button>
          )}
          {mode !== 'gate' && (
            <button
              type="button"
              onClick={startNewSale}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-[#fdeed0]/40"
            >
              <Plus className="h-3 w-3" /> New sale
              <span className="ml-1 rounded border border-surface-200 dark:border-[#1e1c1a] bg-surface-50 dark:bg-[#0f0e0c] px-1.5 font-mono text-[9px] text-surface-400">⌘N</span>
            </button>
          )}
          <div className="relative">
            <details className="group">
              <summary className="inline-flex h-7 w-7 cursor-pointer list-none items-center justify-center rounded-full border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-[#fdeed0]/40 [&::-webkit-details-marker]:hidden">
                <span className="text-[14px] leading-none">⋯</span>
              </summary>
              <div className="absolute right-0 top-full z-20 mt-1 min-w-[180px] rounded-lg border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] p-1 shadow-xl">
                <button type="button" onClick={() => setMode('refund')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]">
                  <RotateCcw className="h-3.5 w-3.5" /> Refund
                </button>
                <button type="button" onClick={() => setMode('close-shift')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]">
                  <Lock className="h-3.5 w-3.5" /> Close shift
                </button>
                {mode === 'gate' && (
                  <button type="button" onClick={startNewSale} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]">
                    <Plus className="h-3.5 w-3.5" /> New sale (⌘N)
                  </button>
                )}
                {mode !== 'gate' && (
                  <button type="button" onClick={() => setMode('held')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]">
                    <History className="h-3.5 w-3.5" /> Recall held (⌘R)
                  </button>
                )}
              </div>
            </details>
          </div>
        </div>
      </header>

      <div className="flex-1 overflow-hidden">
        {mode === 'receipt' && completedSale ? (
          <ReceiptView sale={completedSale} onNext={startNewSale} />
        ) : (
          <div className="grid h-full grid-cols-1 overflow-hidden xl:grid-cols-[minmax(0,1fr)_400px]">
            <main className="overflow-auto bg-surface-100 dark:bg-[#0f0e0c] p-0">
              {mode === 'gate' && (
                <CustomerGate
                  query={globalSearch}
                  setQuery={setGlobalSearch}
                  inputRef={searchInputRef}
                  results={customerResults}
                  loading={customerSearch.isFetching}
                  appointments={todaysAppointments}
                  appointmentsLoading={appointmentsQuery.isLoading}
                  onSelectAppointment={selectAppointment}
                  readyPickupTickets={readyPickup.tickets}
                  readyPickupTotal={readyPickup.total}
                  readyPickupLoading={readyPickupQuery.isLoading}
                  onOpenReadyPickup={openReadyPickupTicket}
                  onViewReadyPickup={() => navigate('/tickets?status_group=active')}
                  onSelectCustomer={selectCustomer}
                  onWalkIn={startWalkIn}
                  onNewCustomer={openInlineCustomerCreate}
                  createCustomerOpen={createCustomerOpen}
                  createCustomerDraft={createCustomerDraft}
                  setCreateCustomerDraft={setCreateCustomerDraft}
                  creatingCustomer={createCustomerMutation.isPending}
                  onSubmitCreateCustomer={submitCreateCustomer}
                  onCancelCreateCustomer={cancelInlineCustomerCreate}
                  onViewCalendar={() => navigate('/calendar')}
                />
              )}

              {mode === 'sale' && (
                <SaleWorkspace
                  products={products}
                  categories={categories}
                  loading={productsQuery.isFetching}
                  productSearch={productSearch}
                  setProductSearch={setProductSearch}
                  productInputRef={productInputRef}
                  activeFilter={activeFilter}
                  setActiveFilter={setActiveFilter}
                  cartItems={cartItems}
                  onAddProduct={addProductToCart}
                  onCustomItem={() => setCustomItemOpen(true)}
                  onStartRepair={() => setMode('repair-device')}
                  onTender={() => setMode('tender-method')}
                />
              )}

              {mode === 'repair-device' && (
                <RepairDeviceStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onCancel={() => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate')}
                  onContinue={() => setMode('repair-issue')}
                />
              )}
              {mode === 'repair-issue' && (
                <RepairIssueStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-device')}
                  onContinue={() => setMode('repair-quote')}
                />
              )}
              {mode === 'repair-quote' && (
                <RepairQuoteStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-issue')}
                  onContinue={() => setMode('repair-deposit')}
                />
              )}
              {mode === 'repair-deposit' && (
                <RepairDepositStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-quote')}
                  onSave={saveRepairToCart}
                />
              )}

              {mode === 'tender-method' && (
                <TenderMethodView
                  totalCents={totals.totalCents}
                  paidLegs={paidLegs}
                  remainingCents={remainingCents}
                  blockchypConfigured={blockchypConfigured}
                  terminalName={terminalName}
                  onBack={() => setMode('sale')}
                  onSelect={(method) => {
                    setSelectedTenderMethod(method);
                    setAmountEntry(fromCents(remainingCents).toFixed(2));
                    setMode(method === 'Cash' ? 'tender-cash' : 'tender-card');
                  }}
                />
              )}
              {mode === 'tender-cash' && (
                <CashTenderView
                  amount={amountEntry}
                  setAmount={setAmountEntry}
                  remainingCents={remainingCents}
                  processing={processing}
                  onBack={() => setMode('tender-method')}
                  onAccept={() => acceptTender('Cash')}
                />
              )}
              {mode === 'tender-card' && (
                <CardTenderView
                  method={selectedTenderMethod}
                  amount={amountEntry}
                  setAmount={setAmountEntry}
                  remainingCents={remainingCents}
                  processing={processing}
                  terminalError={terminalError}
                  blockchypConfigured={blockchypConfigured}
                  terminalName={terminalName}
                  onBack={() => setMode('tender-method')}
                  onAccept={() => acceptTender(selectedTenderMethod)}
                />
              )}

              {mode === 'held' && (
                <HeldSalesView
                  rows={heldCarts.data?.data?.data ?? []}
                  loading={heldCarts.isFetching}
                  onRecall={(id) => recallMutation.mutate(id)}
                  onDiscard={(id) => discardHeldMutation.mutate(id)}
                />
              )}
              {mode === 'refund' && (
                <RefundView
                  invoiceId={refundInvoiceId}
                  setInvoiceId={setRefundInvoiceId}
                  invoice={refundInvoice}
                  loading={refundQuery.isFetching}
                  selections={refundSelections}
                  setSelections={setRefundSelections}
                  processing={refundMutation.isPending}
                  onProcess={() => refundMutation.mutate()}
                />
              )}
              {mode === 'close-shift' && (
                <CloseShiftView
                  cashCount={cashCount}
                  setCashCount={setCashCount}
                  onPopDrawer={() => closeShiftMutation.mutate()}
                />
              )}
            </main>

            <CartColumn
              awake={cartAwake}
              locked={mode.startsWith('tender')}
              customer={customer}
              cartItems={cartItems}
              totals={totals}
              paidLegs={paidLegs}
              onSwapCustomer={() => {
                setWalkInActive(false);
                setMode('gate');
              }}
              onEditLine={setLineEditing}
              onRemoveLine={removeCartItem}
              onQty={updateProductQty}
              onDiscount={() => {
                setDiscountDraft(discount ? String(discount) : '');
                setDiscountReasonDraft(discountReason || 'cashier adjustment');
                setDiscountOpen(true);
              }}
              onTender={() => setMode('tender-method')}
            />
          </div>
        )}
      </div>

      {lineEditing && (
        <LineEditModal
          item={lineEditing}
          onClose={() => setLineEditing(null)}
          onSave={(updates) => {
            updateCartItem(lineEditing.id, updates);
            setLineEditing(null);
          }}
        />
      )}
      {discountOpen && (
        <Modal
          title="Apply Discount"
          onClose={() => setDiscountOpen(false)}
          footer={
            <div className="flex justify-end gap-2">
              <button type="button" className={secondaryButton} onClick={() => setDiscountOpen(false)}>Cancel</button>
              <button type="button" className={primaryButton} onClick={applyDiscount}>Apply discount</button>
            </div>
          }
        >
          <div className="space-y-4">
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Discount amount</span>
              <input value={discountDraft} onChange={(event) => setDiscountDraft(event.target.value)} className={inputClass} inputMode="decimal" placeholder="0.00" />
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Reason</span>
              <select value={discountReasonDraft} onChange={(event) => setDiscountReasonDraft(event.target.value)} className={inputClass}>
                <option value="cashier adjustment">Cashier adjustment</option>
                <option value="loyalty">Loyalty</option>
                <option value="manager approved">Manager approved</option>
                <option value="damaged package">Damaged package</option>
              </select>
            </label>
            {parseMoney(discountDraft) > totals.subtotal * 0.25 && (
              <div className="rounded-lg border border-amber-300 bg-amber-50 p-3 text-sm text-amber-800 dark:border-amber-800 dark:bg-amber-950/30 dark:text-amber-200">
                Discounts over 25% should use manager approval before tender.
              </div>
            )}
          </div>
        </Modal>
      )}
      {customItemOpen && (
        <Modal
          title="Quick Custom Item"
          onClose={() => setCustomItemOpen(false)}
          footer={
            <div className="flex justify-end gap-2">
              <button type="button" className={secondaryButton} onClick={() => setCustomItemOpen(false)}>Cancel</button>
              <button type="button" className={primaryButton} onClick={addCustomItem}>Add item</button>
            </div>
          }
        >
          <div className="space-y-4">
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Item name</span>
              <input value={customName} onChange={(event) => setCustomName(event.target.value)} className={inputClass} placeholder="Accessory, service, or scanned code" />
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Price</span>
              <input value={customPrice} onChange={(event) => setCustomPrice(event.target.value)} className={inputClass} inputMode="decimal" placeholder="0.00" />
            </label>
          </div>
        </Modal>
      )}
    </div>
  );
}

function CustomerGate({
  query,
  results,
  loading,
  appointments,
  appointmentsLoading,
  onSelectAppointment,
  readyPickupTickets,
  readyPickupTotal,
  readyPickupLoading,
  onOpenReadyPickup,
  onViewReadyPickup,
  onSelectCustomer,
  onWalkIn,
  onNewCustomer,
  createCustomerOpen,
  createCustomerDraft,
  setCreateCustomerDraft,
  creatingCustomer,
  onSubmitCreateCustomer,
  onCancelCreateCustomer,
  onViewCalendar,
}: {
  query: string;
  setQuery: (value: string) => void;
  inputRef: React.RefObject<HTMLInputElement | null>;
  results: CustomerResult[];
  loading: boolean;
  appointments: PosAppointment[];
  appointmentsLoading: boolean;
  onSelectAppointment: (appointment: PosAppointment) => void;
  readyPickupTickets: PosPickupTicket[];
  readyPickupTotal: number;
  readyPickupLoading: boolean;
  onOpenReadyPickup: (ticket: PosPickupTicket) => void;
  onViewReadyPickup: () => void;
  onSelectCustomer: (customer: CustomerResult) => void;
  onWalkIn: () => void;
  onNewCustomer: () => void;
  createCustomerOpen: boolean;
  createCustomerDraft: CreateCustomerDraft;
  setCreateCustomerDraft: React.Dispatch<React.SetStateAction<CreateCustomerDraft>>;
  creatingCustomer: boolean;
  onSubmitCreateCustomer: () => void;
  onCancelCreateCustomer: () => void;
  onViewCalendar: () => void;
}) {
  const nowMs = Date.now();
  const nextAppointment = appointments.find((appointment) => {
    const startsAt = new Date(appointment.start_time).getTime();
    return Number.isFinite(startsAt) && startsAt >= nowMs;
  });
  const bookingSummary = appointmentsLoading
    ? 'Booked today - loading'
    : `Booked today - ${appointments.length}${nextAppointment ? ` - next ${appointmentStatusLabel(nextAppointment, nowMs)}` : ''}`;

  return (
    <div className="flex min-h-full flex-col">
      <section className="px-6 pt-5">
        <div className="mb-3 flex items-center gap-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">{bookingSummary}</div>
          <div className="h-px flex-1 bg-surface-100 dark:bg-[#1e1c1a]" />
          <button type="button" onClick={onViewCalendar} className="text-xs font-semibold text-primary-700 dark:text-[#fdeed0] underline-offset-4 hover:underline">View calendar</button>
        </div>
        <div className="flex gap-3 overflow-x-auto pb-2">
          {!appointmentsLoading && appointments.length === 0 && (
            <div className="flex min-w-[280px] items-center gap-3 rounded-xl border border-surface-200 bg-white px-4 py-3 text-left dark:border-[#1e1c1a] dark:bg-[#161513]">
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-bold text-surface-900 dark:text-surface-50">No bookings left</div>
                <div className="truncate text-[11.5px] text-surface-400">Walk-ins and pickups are ready.</div>
              </div>
            </div>
          )}
          {appointments.map((appointment, index) => (
            <button
              key={appointment.id}
              type="button"
              onClick={() => onSelectAppointment(appointment)}
              className={cn(
                'flex min-w-[280px] items-center gap-3 rounded-xl border bg-white dark:bg-[#161513] px-4 py-3 text-left',
                index === 0 ? 'border-l-2 border-l-primary-500 dark:border-l-[#fdeed0] border-surface-300 dark:border-[#2a2621]' : 'border-surface-200 dark:border-[#1e1c1a]',
              )}
            >
              <div className={cn('min-w-[58px] font-display text-2xl leading-none tabular-nums', index === 0 ? 'text-primary-700 dark:text-[#fdeed0]' : 'text-surface-900 dark:text-surface-100')}>{formatTime(appointment.start_time)}</div>
              <div className="min-w-0 flex-1">
                <div className="truncate text-sm font-bold text-surface-900 dark:text-surface-50">
                  {appointmentCustomerName(appointment)}
                </div>
                <div className="truncate text-[11.5px] text-surface-400">{appointmentNote(appointment)}</div>
              </div>
              <span className={cn('rounded-full px-2 py-1 font-mono text-[10px] font-semibold', index === 0 ? 'bg-[#e8a33d]/15 text-[#e8a33d]' : 'bg-surface-100 dark:bg-[#1e1c1a] text-surface-400')}>{appointmentStatusLabel(appointment, nowMs)}</span>
            </button>
          ))}
        </div>
      </section>

      {createCustomerOpen ? (
        <InlineCreateCustomerPanel
          draft={createCustomerDraft}
          setDraft={setCreateCustomerDraft}
          creating={creatingCustomer}
          onSubmit={onSubmitCreateCustomer}
          onCancel={onCancelCreateCustomer}
          onWalkIn={onWalkIn}
        />
      ) : query.trim().length >= 2 ? (
        <section className="mx-auto mt-8 w-full max-w-3xl px-6">
          <div className="overflow-hidden rounded-xl border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] shadow-2xl">
            <div className="border-b border-surface-200 dark:border-[#1e1c1a] px-4 py-3 font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">Customer matches</div>
            {loading && <div className="p-5 text-sm text-surface-900 dark:text-surface-500">Searching...</div>}
            {!loading && results.length === 0 && (
              <div className="p-5 text-sm text-surface-900 dark:text-surface-500">
                No matching customers. Create a profile or continue as a walk-in.
              </div>
            )}
            {results.map((customer) => (
              <button
                key={customer.id}
                type="button"
                onClick={() => onSelectCustomer(customer)}
                className="flex w-full items-center gap-3 border-b border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513] p-4 text-left last:border-b-0 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]"
              >
                <div className="grid h-10 w-10 place-items-center rounded-full bg-[#4db8c9] font-bold text-[#002d35]">
                  {initials(getCustomerName(customer))}
                </div>
                <div className="min-w-0 flex-1">
                  <div className="truncate font-semibold text-surface-900 dark:text-surface-50">{getCustomerName(customer)}</div>
                  <div className="truncate font-mono text-xs text-surface-900 dark:text-surface-500">{customer.phone || customer.mobile || customer.email || 'No contact saved'}</div>
                </div>
                {customer.group_name && <Pill tone="vip">{customer.group_name}</Pill>}
                <ChevronRight className="h-4 w-4 text-surface-900 dark:text-surface-500" />
              </button>
            ))}
            <div className="flex gap-2 border-t border-surface-200 dark:border-[#1e1c1a] p-3">
              <button type="button" onClick={onNewCustomer} className="flex-1 rounded-lg bg-primary-500 dark:bg-[#fdeed0] px-4 py-2 text-sm font-bold text-[#2b1400]">Create customer</button>
              <button type="button" onClick={onWalkIn} className="flex-1 rounded-lg border border-surface-300 dark:border-[#2a2621] px-4 py-2 text-sm font-bold text-surface-700 dark:text-surface-200">Walk-in</button>
            </div>
          </div>
        </section>
      ) : (
        <section className="flex flex-1 flex-col items-center justify-center gap-3 px-6 py-10 text-center">
          <button type="button" onClick={onNewCustomer} className="inline-flex min-w-[280px] items-center justify-center gap-3 rounded-lg bg-primary-500 dark:bg-[#fdeed0] px-6 py-4 text-[15px] font-bold text-[#2b1400] shadow-lg shadow-black/20 hover:bg-primary-400 dark:hover:bg-[#f5dca7]">
            <UserPlus className="h-5 w-5" />
            Create new customer
          </button>
          <button type="button" onClick={onWalkIn} className="inline-flex min-w-[280px] items-center justify-center gap-3 rounded-lg border border-surface-300 dark:border-[#2a2621] bg-white dark:bg-[#161513] px-6 py-4 text-[15px] font-bold text-surface-900 dark:text-surface-100 hover:border-primary-500 dark:hover:border-[#fdeed0]/40">
            <ShoppingCart className="h-5 w-5" />
            Walk-in - no profile
          </button>
          <div className="mt-2 font-mono text-[11.5px] text-surface-500 dark:text-surface-500">
            or start typing in the search bar above · scan gun ready
          </div>
        </section>
      )}

      <section className="px-6 pb-6">
        <div className="mb-3 flex items-center gap-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">
            {readyPickupLoading ? 'Ready for pickup - loading' : `Ready for pickup - ${readyPickupTotal}`}
          </div>
          <div className="h-px flex-1 bg-surface-100 dark:bg-[#1e1c1a]" />
          <button type="button" onClick={onViewReadyPickup} className="text-xs font-semibold text-primary-700 dark:text-[#fdeed0] underline-offset-4 hover:underline">
            View active tickets
          </button>
        </div>
        <div className="overflow-hidden rounded-xl border border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513]">
          {readyPickupLoading && (
            <div className="px-4 py-5 text-sm text-surface-900 dark:text-surface-500">Loading pickup tickets...</div>
          )}
          {!readyPickupLoading && readyPickupTickets.length === 0 && (
            <div className="px-4 py-5 text-sm text-surface-900 dark:text-surface-500">No ready pickup tickets right now.</div>
          )}
          {readyPickupTickets.map((ticket) => (
            <button
              key={ticket.id}
              type="button"
              onClick={() => onOpenReadyPickup(ticket)}
              className="grid w-full grid-cols-[76px_70px_180px_minmax(0,1fr)_110px_90px_70px] items-center gap-3 border-b border-surface-200 dark:border-[#1e1c1a] px-4 py-2.5 text-left text-sm last:border-b-0 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]"
            >
              <span className="rounded-full bg-[#34c47e]/15 px-2 py-1 text-center font-mono text-[10px] font-bold uppercase text-[#34c47e]">ready</span>
              <span className="font-mono text-xs text-surface-400">{ticket.order_id}</span>
              <span className="truncate font-semibold text-surface-900 dark:text-surface-100">{ticket.customerName}</span>
              <span className="truncate text-xs text-surface-600 dark:text-surface-300">{ticket.itemSummary}</span>
              <span className="font-mono text-xs text-surface-900 dark:text-surface-500">{ticket.progressLabel}</span>
              <span className="text-right font-mono text-xs text-primary-700 dark:text-[#fdeed0]">{formatCurrency(ticket.total)}</span>
              <span className="text-right text-xs font-semibold text-[#4db8c9]">Open</span>
            </button>
          ))}
        </div>
      </section>
    </div>
  );
}

function InlineCreateCustomerPanel({
  draft,
  setDraft,
  creating,
  onSubmit,
  onCancel,
  onWalkIn,
}: {
  draft: CreateCustomerDraft;
  setDraft: React.Dispatch<React.SetStateAction<CreateCustomerDraft>>;
  creating: boolean;
  onSubmit: () => void;
  onCancel: () => void;
  onWalkIn: () => void;
}) {
  const updateDraft = (patch: Partial<CreateCustomerDraft>) => {
    setDraft((current) => ({ ...current, ...patch }));
  };
  const tileInput =
    'h-10 w-full border-0 bg-transparent p-0 text-[15px] font-semibold text-surface-900 placeholder:text-surface-400 focus-visible:outline-none dark:text-surface-50 dark:placeholder:text-surface-600';
  const fieldTile =
    'bg-white px-4 py-3 dark:bg-[#161513]';

  return (
    <section className="flex w-full flex-1 items-center px-6 py-6">
      <form
        className="mx-auto w-full max-w-4xl overflow-hidden rounded-xl border border-surface-200 bg-surface-200 shadow-lg shadow-black/10 dark:border-[#1e1c1a] dark:bg-[#1e1c1a] dark:shadow-black/30"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit();
        }}
      >
        <div className="flex flex-wrap items-center justify-between gap-3 bg-white px-4 py-3 dark:bg-[#161513]">
          <div className="flex items-center gap-3">
            <div className="grid h-9 w-9 place-items-center rounded-lg bg-primary-500 text-[#2b1400] dark:bg-[#fdeed0]">
              <UserPlus className="h-5 w-5" />
            </div>
            <div className="font-display text-3xl leading-none text-surface-900 dark:text-surface-50">Create customer</div>
          </div>
          <div className="inline-flex rounded-lg border border-surface-200 bg-surface-100 p-1 dark:border-[#2a2621] dark:bg-[#0f0e0c]">
            {(['individual', 'business'] as const).map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => updateDraft({ customerType: type })}
                className={cn(
                  'rounded-md px-3 py-1.5 text-xs font-bold capitalize',
                  draft.customerType === type
                    ? 'bg-white text-surface-900 shadow-sm dark:bg-[#fdeed0] dark:text-[#2b1400]'
                    : 'text-surface-500 hover:text-surface-900 dark:hover:text-surface-100',
                )}
              >
                {type}
              </button>
            ))}
          </div>
        </div>

        <div className="grid gap-px sm:grid-cols-2">
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">First name</span>
            <input
              autoFocus
              required
              value={draft.firstName}
              onChange={(event) => updateDraft({ firstName: event.target.value })}
              className={tileInput}
            />
          </label>
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Last name</span>
            <input
              value={draft.lastName}
              onChange={(event) => updateDraft({ lastName: event.target.value })}
              className={tileInput}
            />
          </label>
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Mobile</span>
            <input
              value={draft.phone}
              onChange={(event) => updateDraft({ phone: event.target.value })}
              className={tileInput}
              inputMode="tel"
            />
          </label>
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Email</span>
            <input
              value={draft.email}
              onChange={(event) => updateDraft({ email: event.target.value })}
              className={tileInput}
              inputMode="email"
            />
          </label>
        </div>

        <div className="grid gap-px md:grid-cols-[minmax(0,0.8fr)_minmax(0,1.2fr)]">
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Company</span>
            <input
              value={draft.organization}
              onChange={(event) => updateDraft({ organization: event.target.value })}
              className={tileInput}
            />
          </label>
          <label className={fieldTile}>
            <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Counter note</span>
            <input
              value={draft.comments}
              onChange={(event) => updateDraft({ comments: event.target.value })}
              className={tileInput}
            />
          </label>
        </div>

        <div className="flex flex-wrap items-center justify-between gap-3 bg-white px-4 py-3 dark:bg-[#161513]">
          <div className="flex flex-wrap gap-2">
            <label className="inline-flex h-10 items-center gap-2 rounded-lg border border-surface-200 px-3 text-sm font-semibold text-surface-800 dark:border-[#2a2621] dark:text-surface-100">
              <input
                type="checkbox"
                checked={draft.smsOptIn}
                onChange={(event) => updateDraft({ smsOptIn: event.target.checked })}
                className="h-4 w-4 accent-primary-500"
              />
              SMS updates
            </label>
            <label className="inline-flex h-10 items-center gap-2 rounded-lg border border-surface-200 px-3 text-sm font-semibold text-surface-800 dark:border-[#2a2621] dark:text-surface-100">
              <input
                type="checkbox"
                checked={draft.emailOptIn}
                onChange={(event) => updateDraft({ emailOptIn: event.target.checked })}
                className="h-4 w-4 accent-primary-500"
              />
              Email receipts
            </label>
          </div>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={onCancel} disabled={creating} className={secondaryButton}>
              Cancel
            </button>
            <button type="button" onClick={onWalkIn} disabled={creating} className={secondaryButton}>
              Walk-in
            </button>
            <button type="submit" disabled={creating} className={primaryButton}>
              {creating ? 'Creating...' : 'Create customer'}
            </button>
          </div>
        </div>
      </form>
    </section>
  );
}

function SaleWorkspace({
  products,
  categories,
  loading,
  productSearch,
  setProductSearch,
  productInputRef,
  activeFilter,
  setActiveFilter,
  cartItems,
  onAddProduct,
  onCustomItem,
  onStartRepair,
  onTender,
}: {
  products: ProductSearchItem[];
  categories: string[];
  loading: boolean;
  productSearch: string;
  setProductSearch: (value: string) => void;
  productInputRef: React.RefObject<HTMLInputElement | null>;
  activeFilter: string;
  setActiveFilter: (value: string) => void;
  cartItems: CartItem[];
  onAddProduct: (product: ProductSearchItem) => void;
  onCustomItem: () => void;
  onStartRepair: () => void;
  onTender: () => void;
}) {
  const cartProductIds = new Set(cartItems.filter((item): item is ProductCartItem => item.type === 'product').map((item) => item.inventoryItemId));
  const filterOptions = ['All', ...categories.filter(Boolean).slice(0, 8)];
  return (
    <div className="flex flex-col">
      {/* Single filter strip at the top — matches mockup Frame 09. The
          dedicated catalog search input is gone (redundant with the topbar
          ⌘K search), and Charge moved to the cart footer where Charge
          belongs. Repair + Custom item live as right-aligned pills next
          to the category filters so they read as starting points, not
          floating CTAs. */}
      <div className="flex items-center gap-2 overflow-x-auto border-b border-surface-200 bg-white px-5 py-3 dark:border-surface-800 dark:bg-[#080706]">
        {filterOptions.map((filter) => (
          <button
            key={filter}
            type="button"
            onClick={() => setActiveFilter(filter)}
            className={cn(
              'shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold',
              activeFilter === filter
                ? 'bg-primary-500 text-[#2b1400] dark:bg-[#fdeed0]'
                : 'bg-surface-100 text-surface-600 hover:bg-surface-200 dark:bg-surface-800 dark:text-surface-300',
            )}
          >
            {filter}
          </button>
        ))}
        <div className="ml-auto flex items-center gap-2">
          <button
            type="button"
            onClick={onCustomItem}
            className="inline-flex items-center gap-1.5 rounded-full border border-dashed border-surface-300 bg-transparent px-3 py-1.5 text-xs font-semibold text-surface-700 hover:border-primary-500 hover:text-primary-700 dark:border-surface-700 dark:text-surface-200 dark:hover:border-[#fdeed0]/40 dark:hover:text-[#fdeed0]"
          >
            <PackagePlus className="h-3.5 w-3.5" />
            Custom item
          </button>
          <button
            type="button"
            onClick={onStartRepair}
            className="inline-flex items-center gap-1.5 rounded-full bg-surface-100 px-3 py-1.5 text-xs font-semibold text-surface-700 hover:bg-surface-200 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <Wrench className="h-3.5 w-3.5" />
            Repair
          </button>
          {cartItems.length > 0 && (
            <button
              type="button"
              onClick={onTender}
              className="inline-flex items-center gap-1.5 rounded-full bg-primary-500 px-3 py-1.5 text-xs font-bold text-[#2b1400] dark:bg-[#fdeed0]"
            >
              <CreditCard className="h-3.5 w-3.5" />
              Charge
            </button>
          )}
        </div>
      </div>

      <div className="grid gap-3 p-5 sm:grid-cols-2 xl:grid-cols-4">
        <button type="button" className="rounded-lg border border-cyan-400/40 bg-cyan-500/10 p-4 text-left" onClick={onCustomItem}>
          <Star className="h-5 w-5 text-cyan-700 dark:text-[#4DB8C9]" />
          <div className="mt-3 font-semibold">Loyalty smart add</div>
          <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Add a qualifying accessory before tender.</div>
        </button>
        {loading && Array.from({ length: 7 }).map((_, index) => (
          <div key={index} className="h-36 animate-pulse rounded-lg bg-surface-100 dark:bg-surface-900" />
        ))}
        {!loading && products.length === 0 && (
          <Section className="col-span-full p-8 text-center">
            <Package className="mx-auto h-8 w-8 text-surface-400" />
            <div className="mt-3 font-semibold">No catalog items found</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Scan again or add a custom item.</div>
          </Section>
        )}
        {!loading && products.map((product) => {
          const out = product.item_type !== 'service' && Number(product.in_stock ?? 0) <= 0;
          const inCart = cartProductIds.has(product.id);
          return (
            <button
              key={product.id}
              type="button"
              onClick={() => onAddProduct(product)}
              disabled={out}
              className={cn(
                'relative flex min-h-36 flex-col rounded-lg border p-4 text-left shadow-sm transition',
                out
                  ? 'border-surface-200 bg-surface-100 opacity-60 dark:border-surface-800 dark:bg-surface-900'
                  : 'border-surface-200 bg-white hover:-translate-y-0.5 hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900',
              )}
            >
              {inCart && <Pill tone="info" className="absolute right-3 top-3">in cart</Pill>}
              <Package className="h-6 w-6 text-surface-400" />
              <div className="mt-3 line-clamp-2 min-h-10 font-semibold">{product.name}</div>
              <div className="mt-1 truncate font-mono text-xs text-surface-900 dark:text-surface-500">{product.sku || 'No SKU'}</div>
              <div className="mt-auto flex items-end justify-between pt-3">
                <span className="font-display text-2xl">{formatCurrency(Number(product.retail_price ?? product.price ?? 0))}</span>
                <Pill tone={out ? 'error' : Number(product.in_stock ?? 0) <= 2 && product.item_type !== 'service' ? 'warning' : 'success'}>
                  {stockLabel(product)}
                </Pill>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function CartColumn({
  awake,
  locked,
  customer,
  cartItems,
  totals,
  paidLegs,
  onSwapCustomer,
  onEditLine,
  onRemoveLine,
  onQty,
  onDiscount,
  onTender,
}: {
  awake: boolean;
  locked: boolean;
  customer: CustomerResult | null;
  cartItems: CartItem[];
  totals: ReturnType<typeof computePosTotals>;
  paidLegs: PaymentLeg[];
  onSwapCustomer: () => void;
  onEditLine: (item: CartItem) => void;
  onRemoveLine: (id: string) => void;
  onQty: (id: string, delta: number) => void;
  onDiscount: () => void;
  onTender: () => void;
}) {
  const paid = paidLegs.reduce((sum, leg) => sum + leg.amount, 0);
  return (
    <aside className={cn('flex min-h-0 flex-col border-l border-surface-200 dark:border-[#1e1c1a] bg-white dark:bg-[#161513]', locked && 'opacity-90')}>
      <div className="flex h-[52px] items-center justify-between border-b border-surface-200 dark:border-[#1e1c1a] px-4">
        <div className="flex items-center gap-2 font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-surface-600 dark:text-surface-300">
          <ChevronLeft className="h-4 w-4 text-surface-900 dark:text-surface-500" />
          <ShoppingCart className="h-4 w-4" />
          Cart
        </div>
        {locked ? <Pill tone="warning"><Lock className="h-3 w-3" /> locked</Pill> : <Pill tone={awake ? 'success' : 'neutral'}>{awake ? 'awake' : 'asleep'}</Pill>}
      </div>
      {!awake && (
        <div className="flex flex-1 flex-col items-center justify-center p-8 text-center opacity-60">
          <div className="grid h-14 w-14 place-items-center rounded-2xl bg-surface-100 dark:bg-[#0f0e0c]">
            <ShoppingCart className="h-7 w-7 text-surface-900 dark:text-surface-500" />
          </div>
          <div className="mt-4 font-display text-2xl text-surface-900 dark:text-surface-100">Cart is asleep</div>
          <div className="mt-1 max-w-[240px] text-[12.5px] text-surface-500 dark:text-surface-400">
            Pick a customer or take a walk-in to wake it up.
          </div>
        </div>
      )}
      {awake && (
        <>
          <button type="button" onClick={onSwapCustomer} className="flex items-center gap-3 border-b border-surface-200 dark:border-[#1e1c1a] p-4 text-left hover:bg-surface-100 dark:hover:bg-[#0f0e0c]">
            <div className="grid h-11 w-11 place-items-center rounded-full bg-[#4db8c9] font-bold text-[#002d35]">
              {initials(getCustomerName(customer))}
            </div>
            <div className="min-w-0 flex-1">
              <div className="truncate font-semibold text-surface-900 dark:text-surface-50">{getCustomerName(customer)}</div>
              <div className="truncate text-sm text-surface-900 dark:text-surface-500">{customer?.phone || customer?.mobile || customer?.email || 'No customer attached'}</div>
            </div>
            {customer?.group_name && <Pill tone="vip">{customer.group_name}</Pill>}
          </button>
          <div className="min-h-0 flex-1 overflow-auto p-3">
            {cartItems.length === 0 ? (
              <div className="rounded-lg border border-dashed border-surface-300 dark:border-[#2a2621] p-6 text-center text-sm text-surface-900 dark:text-surface-500">
                Scan or add an item to start the cart.
              </div>
            ) : (
              <div className="space-y-2">
                {cartItems.map((item) => (
                  <div key={item.id} className={cn('rounded-lg border border-surface-200 dark:border-[#1e1c1a] bg-surface-100 dark:bg-[#0f0e0c] p-3', item.type === 'repair' && 'border-l-4 border-l-primary-500 dark:border-l-[#fdeed0]')}>
                    <div className="flex gap-3">
                      <div className="mt-1 grid h-8 w-8 place-items-center rounded-lg bg-surface-100 dark:bg-[#1e1c1a]">
                        {item.type === 'repair' ? <Wrench className="h-4 w-4" /> : <Package className="h-4 w-4" />}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="line-clamp-2 font-semibold text-surface-900 dark:text-surface-100">{lineTitle(item)}</div>
                        <div className="mt-1 text-xs text-surface-900 dark:text-surface-500">{lineSubtitle(item)}</div>
                        {(item.type === 'product' || item.type === 'misc') && (
                          <div className="mt-2 flex items-center gap-2">
                            <button type="button" onClick={() => onQty(item.id, -1)} disabled={locked} className="rounded border border-surface-300 dark:border-[#2a2621] p-1" aria-label="Decrease quantity"><Minus className="h-3 w-3" /></button>
                            <span className="w-8 text-center font-mono text-xs">{item.quantity}</span>
                            <button type="button" onClick={() => onQty(item.id, 1)} disabled={locked} className="rounded border border-surface-300 dark:border-[#2a2621] p-1" aria-label="Increase quantity"><Plus className="h-3 w-3" /></button>
                          </div>
                        )}
                      </div>
                      <div className="text-right">
                        <div className="font-display text-xl text-surface-900 dark:text-surface-100">{formatCurrency(lineAmount(item))}</div>
                        <div className="mt-2 flex justify-end gap-1">
                          <button type="button" onClick={() => onEditLine(item)} disabled={locked} className="rounded p-1 text-surface-900 dark:text-surface-500 hover:bg-surface-100 dark:hover:bg-[#1e1c1a]" aria-label="Edit line"><Edit3 className="h-3.5 w-3.5" /></button>
                          <button type="button" onClick={() => onRemoveLine(item.id)} disabled={locked} className="rounded p-1 text-red-500 hover:bg-red-50 dark:hover:bg-red-950/40" aria-label="Remove line"><Trash2 className="h-3.5 w-3.5" /></button>
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
          <div className="border-t border-surface-200 dark:border-[#1e1c1a] p-4">
            <button type="button" onClick={onDiscount} disabled={locked} className="mb-3 flex w-full items-center gap-2 rounded-lg border border-dashed border-surface-300 dark:border-[#2a2621] px-3 py-2 text-sm font-semibold text-surface-600 dark:text-surface-300 hover:border-primary-500 dark:hover:border-[#fdeed0]/40">
              <Tag className="h-4 w-4" />
              Coupon or discount
            </button>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Subtotal</span><span className="font-mono">{formatCurrency(totals.subtotal)}</span></div>
              {totals.discountAmount > 0 && <div className="flex justify-between text-emerald-700 dark:text-[#34C47E]"><span>Discount</span><span className="font-mono">-{formatCurrency(totals.discountAmount)}</span></div>}
              <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Tax</span><span className="font-mono">{formatCurrency(totals.tax)}</span></div>
              {paid > 0 && <div className="flex justify-between text-cyan-700 dark:text-[#4DB8C9]"><span>Paid</span><span className="font-mono">-{formatCurrency(paid)}</span></div>}
              <div className="flex items-end justify-between border-t border-surface-200 dark:border-[#1e1c1a] pt-3">
                <span className="font-semibold">Due now</span>
                <span className="font-display text-4xl text-primary-700 dark:text-[#fdeed0]">{formatCurrency(Math.max(0, totals.total - paid))}</span>
              </div>
            </div>
            <button type="button" onClick={onTender} disabled={locked || cartItems.length === 0} className={cn(primaryButton, 'mt-4 w-full py-3 text-base')}>
              <CreditCard className="h-4 w-4" />
              Charge {formatCurrency(Math.max(0, totals.total - paid))}
            </button>
          </div>
        </>
      )}
    </aside>
  );
}

function RepairDeviceStep({ draft, setDraft, onCancel, onContinue }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onCancel: () => void;
  onContinue: () => void;
}) {
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4">
      <Stepper step="device" />
      <Section className="p-5">
        <div className="grid gap-3 sm:grid-cols-3">
          {DEVICE_TYPES.map(({ label, icon: Icon }) => (
            <button
              key={label}
              type="button"
              onClick={() => setDraft((prev) => ({ ...prev, deviceType: label }))}
              className={cn('rounded-lg border p-4 text-left', draft.deviceType === label ? 'border-primary-500 bg-primary-500/10' : 'border-surface-200 hover:border-primary-500 dark:border-surface-800')}
            >
              <Icon className="h-5 w-5" />
              <div className="mt-3 font-semibold">{label}</div>
            </button>
          ))}
        </div>
        <div className="mt-5 grid gap-4 md:grid-cols-2">
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">Device name</span>
            <input className={inputClass} value={draft.deviceName} onChange={(event) => setDraft((prev) => ({ ...prev, deviceName: event.target.value }))} placeholder="iPhone 14 Pro, MacBook Air..." />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">IMEI or serial</span>
            <input className={inputClass} value={draft.imei} onChange={(event) => setDraft((prev) => ({ ...prev, imei: event.target.value }))} placeholder="Scan or type" />
          </label>
        </div>
      </Section>
      <WizardFooter onBack={onCancel} backLabel="Cancel" onContinue={onContinue} />
    </div>
  );
}

function RepairIssueStep({ draft, setDraft, onBack, onContinue }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onContinue: () => void;
}) {
  const toggleSymptom = (symptom: string) => {
    setDraft((prev) => ({
      ...prev,
      symptoms: prev.symptoms.includes(symptom)
        ? prev.symptoms.filter((item) => item !== symptom)
        : [...prev.symptoms, symptom],
    }));
  };
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4">
      <Stepper step="issue" />
      <Section className="p-5">
        <div className="mb-4 flex flex-wrap gap-2">
          {CONDITIONS.map((condition) => (
            <button
              key={condition}
              type="button"
              onClick={() => setDraft((prev) => ({ ...prev, condition }))}
              className={cn('rounded-full px-3 py-1.5 text-sm font-semibold', draft.condition === condition ? 'bg-primary-500 text-[#2b1400]' : 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300')}
            >
              {condition}
            </button>
          ))}
        </div>
        <div className="grid gap-3 sm:grid-cols-4">
          {SYMPTOMS.map((symptom) => (
            <button
              key={symptom}
              type="button"
              onClick={() => toggleSymptom(symptom)}
              className={cn('rounded-lg border p-4 text-left text-sm font-semibold', draft.symptoms.includes(symptom) ? 'border-primary-500 bg-primary-500/10' : 'border-surface-200 hover:border-primary-500 dark:border-surface-800')}
            >
              {symptom}
            </button>
          ))}
        </div>
        <label className="mt-5 block">
          <span className="mb-1 block text-sm font-semibold">Customer's words</span>
          <textarea className={inputClass} rows={4} value={draft.customerWords} onChange={(event) => setDraft((prev) => ({ ...prev, customerWords: event.target.value }))} placeholder="What did the customer say is happening?" />
        </label>
      </Section>
      <WizardFooter onBack={onBack} onContinue={onContinue} />
    </div>
  );
}

function RepairQuoteStep({ draft, setDraft, onBack, onContinue }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onContinue: () => void;
}) {
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4">
      <Stepper step="quote" />
      <Section className="p-5">
        <div className="grid gap-4 md:grid-cols-2">
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">Service name</span>
            <input className={inputClass} value={draft.serviceName} onChange={(event) => setDraft((prev) => ({ ...prev, serviceName: event.target.value }))} />
          </label>
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">Labor price</span>
            <input className={inputClass} inputMode="decimal" value={draft.laborPrice} onChange={(event) => setDraft((prev) => ({ ...prev, laborPrice: event.target.value }))} />
          </label>
        </div>
        <label className="mt-4 block">
          <span className="mb-1 block text-sm font-semibold">Diagnostic notes</span>
          <textarea className={inputClass} rows={5} value={draft.diagnostic} onChange={(event) => setDraft((prev) => ({ ...prev, diagnostic: event.target.value }))} placeholder="Short counter-safe quote summary." />
        </label>
        <div className="mt-4 rounded-lg border border-surface-200 p-4 dark:border-surface-800">
          <div className="text-sm font-semibold">Quote preview</div>
          <div className="mt-2 flex justify-between font-mono text-sm"><span>{draft.serviceName}</span><span>{formatCurrency(parseMoney(draft.laborPrice))}</span></div>
        </div>
      </Section>
      <WizardFooter onBack={onBack} onContinue={onContinue} />
    </div>
  );
}

function RepairDepositStep({ draft, setDraft, onBack, onSave }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onSave: () => void;
}) {
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4">
      <Stepper step="deposit" />
      <Section className="p-6 text-center">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Suggested deposit</div>
        <div className="mt-2 font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(parseMoney(draft.depositAmount))}</div>
        <div className="mt-2 text-sm text-surface-900 dark:text-surface-500">Balance is collected at pickup. Deposit can be changed before tender.</div>
        <div className="mx-auto mt-6 max-w-sm">
          <input className={cn(inputClass, 'text-center font-display text-4xl')} inputMode="decimal" value={draft.depositAmount} onChange={(event) => setDraft((prev) => ({ ...prev, depositAmount: event.target.value }))} />
        </div>
        <label className="mt-5 inline-flex items-center gap-2 text-sm font-semibold">
          <input type="checkbox" checked={draft.waiverHandled} onChange={(event) => setDraft((prev) => ({ ...prev, waiverHandled: event.target.checked }))} />
          Waiver handled on terminal or paper
        </label>
      </Section>
      <WizardFooter onBack={onBack} continueLabel="Add repair to cart" onContinue={onSave} />
    </div>
  );
}

function WizardFooter({ onBack, onContinue, backLabel = 'Back', continueLabel = 'Continue' }: {
  onBack: () => void;
  onContinue: () => void;
  backLabel?: string;
  continueLabel?: string;
}) {
  return (
    <div className="flex items-center justify-between rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-800 dark:bg-surface-900">
      <button type="button" onClick={onBack} className={secondaryButton}>
        <ChevronLeft className="h-4 w-4" />
        {backLabel}
      </button>
      <button type="button" onClick={onContinue} className={primaryButton}>
        {continueLabel}
        <ChevronRight className="h-4 w-4" />
      </button>
    </div>
  );
}

function TenderMethodView({
  totalCents,
  paidLegs,
  remainingCents,
  blockchypConfigured,
  terminalName,
  onBack,
  onSelect,
}: {
  totalCents: number;
  paidLegs: PaymentLeg[];
  remainingCents: number;
  blockchypConfigured: boolean;
  terminalName: string;
  onBack: () => void;
  onSelect: (method: TenderMethod) => void;
}) {
  const methods: Array<{ method: TenderMethod; title: string; subtitle: string; icon: React.ElementType; disabled?: boolean }> = [
    { method: 'Cash', title: 'Cash', subtitle: 'Typed amount, drawer opens on confirm', icon: Banknote },
    { method: 'Card', title: 'Card', subtitle: blockchypConfigured ? `${terminalName} ready` : 'Pair terminal in settings', icon: CreditCard, disabled: !blockchypConfigured },
    { method: 'Gift card', title: 'Gift card', subtitle: 'Scan or type code', icon: Gift },
    { method: 'Store credit', title: 'Store credit', subtitle: 'Apply customer balance', icon: Star },
  ];
  return (
    <div className="mx-auto max-w-4xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Back to cart</button>
      <div className="mt-4 text-center">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Amount due</div>
        <div className="font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(fromCents(remainingCents))}</div>
        <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Total {formatCurrency(fromCents(totalCents))}</div>
      </div>
      {paidLegs.length > 0 && (
        <div className="mt-5 rounded-lg border border-cyan-400/40 bg-cyan-500/10 p-4">
          <div className="text-sm font-semibold">Paid so far</div>
          <div className="mt-2 flex flex-wrap gap-2">
            {paidLegs.map((leg, index) => <Pill key={`${leg.method}-${index}`} tone="info">{leg.method} {formatCurrency(leg.amount)}</Pill>)}
          </div>
        </div>
      )}
      <div className="mt-6 grid gap-3 sm:grid-cols-2">
        {methods.map(({ method, title, subtitle, icon: Icon, disabled }) => (
          <button key={method} type="button" onClick={() => onSelect(method)} disabled={disabled} className="rounded-lg border border-surface-200 bg-white p-5 text-left shadow-sm hover:border-primary-500 disabled:hover:border-surface-200 dark:border-surface-800 dark:bg-surface-900">
            <Icon className="h-7 w-7 text-primary-700 dark:text-primary-500" />
            <div className="mt-4 font-display text-3xl">{title}</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">{subtitle}</div>
          </button>
        ))}
      </div>
      <div className="mt-4 text-center text-sm text-surface-900 dark:text-surface-500">Take a partial payment by entering less than the remaining amount.</div>
    </div>
  );
}

function CashTenderView({ amount, setAmount, remainingCents, processing, onBack, onAccept }: {
  amount: string;
  setAmount: (value: string) => void;
  remainingCents: number;
  processing: boolean;
  onBack: () => void;
  onAccept: () => void;
}) {
  const remaining = fromCents(remainingCents);
  const quick = [remaining, Math.ceil(remaining / 5) * 5, Math.ceil(remaining / 10) * 10, Math.ceil(remaining / 20) * 20]
    .filter((value, index, arr) => value > 0 && arr.indexOf(value) === index);
  const change = Math.max(0, parseMoney(amount) - remaining);
  return (
    <div className="mx-auto max-w-xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Cash received</div>
        <input className="mt-2 w-full rounded-lg border border-surface-200 bg-surface-50 px-4 py-3 text-right font-display text-6xl text-cyan-700 focus:border-primary-500 focus-visible:outline-none dark:border-surface-700 dark:bg-surface-950 dark:text-[#4DB8C9]" value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" autoFocus />
        <div className="mt-4 flex flex-wrap gap-2">
          {quick.map((value) => (
            <button key={value} type="button" onClick={() => setAmount(value.toFixed(2))} className={secondaryButton}>{formatCurrency(value)}</button>
          ))}
        </div>
        <div className="mt-5 rounded-lg border border-surface-200 p-4 dark:border-surface-800">
          <div className="text-sm text-surface-900 dark:text-surface-500">Change due</div>
          <div className="font-display text-5xl text-emerald-700 dark:text-[#34C47E]">{formatCurrency(change)}</div>
        </div>
        <button type="button" onClick={onAccept} disabled={processing} className={cn(primaryButton, 'mt-5 w-full py-3 text-base')}>
          {processing ? 'Processing...' : 'Take cash'}
        </button>
      </Section>
    </div>
  );
}

function CardTenderView({ method, amount, setAmount, remainingCents, processing, terminalError, blockchypConfigured, terminalName, onBack, onAccept }: {
  method: TenderMethod;
  amount: string;
  setAmount: (value: string) => void;
  remainingCents: number;
  processing: boolean;
  terminalError: string | null;
  blockchypConfigured: boolean;
  terminalName: string;
  onBack: () => void;
  onAccept: () => void;
}) {
  const requiresTerminal = method === 'Card';
  const disabled = processing || (requiresTerminal && !blockchypConfigured);
  return (
    <div className="mx-auto max-w-2xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6 text-center">
        {method === 'Card' ? <CreditCard className="mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" /> : <Gift className="mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" />}
        <div className="mt-4 font-display text-4xl">{method === 'Card' ? 'Waiting on terminal' : method}</div>
        <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">
          {method === 'Card'
            ? (blockchypConfigured ? `${terminalName} will prompt for card and tip.` : 'Terminal is not configured.')
            : 'Enter the amount to apply. Scan or validate the code before tendering.'}
        </div>
        <label className="mx-auto mt-5 block max-w-sm text-left">
          <span className="mb-1 block text-sm font-semibold">{method} amount</span>
          <input className={inputClass} value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" />
        </label>
        <div className="mt-4 text-sm text-surface-900 dark:text-surface-500">Remaining balance is {formatCurrency(fromCents(remainingCents))}.</div>
        {terminalError && (
          <div className="mt-5 rounded-lg border border-red-300 bg-red-50 p-3 text-left text-sm text-red-700 dark:border-red-800 dark:bg-red-950/30 dark:text-red-300">
            {terminalError}
          </div>
        )}
        <button type="button" onClick={onAccept} disabled={disabled} className={cn(primaryButton, 'mt-5 w-full py-3 text-base')}>
          {processing ? 'Processing...' : method === 'Card' ? 'Send to terminal' : `Apply ${method}`}
        </button>
      </Section>
    </div>
  );
}

function HeldSalesView({ rows, loading, onRecall, onDiscard }: {
  rows: HeldCartRow[];
  loading: boolean;
  onRecall: (id: number) => void;
  onDiscard: (id: number) => void;
}) {
  return (
    <Section className="overflow-hidden">
      <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-800">
        <div>
          <div className="font-display text-2xl">Held Sales</div>
          <div className="text-sm text-surface-900 dark:text-surface-500">{rows.length} parked sale{rows.length === 1 ? '' : 's'}</div>
        </div>
        <Pill tone="info">recall</Pill>
      </div>
      {loading ? (
        <div className="p-6 text-sm text-surface-900 dark:text-surface-500">Loading held sales...</div>
      ) : rows.length === 0 ? (
        <div className="p-8 text-center text-sm text-surface-900 dark:text-surface-500">No held sales right now.</div>
      ) : (
        <div className="divide-y divide-surface-200 dark:divide-surface-800">
          {rows.map((row) => (
            <div key={row.id} className="grid items-center gap-3 px-4 py-3 text-sm md:grid-cols-[1fr_140px_160px_180px]">
              <div>
                <div className="font-semibold">{row.label || 'Held sale'}</div>
                <div className="text-surface-900 dark:text-surface-500">Held {formatDateTime(row.created_at)}</div>
              </div>
              <div className="font-mono">{row.total_cents != null ? formatCurrency(fromCents(row.total_cents)) : '-'}</div>
              <div className="text-surface-900 dark:text-surface-500">{[row.owner_first_name, row.owner_last_name].filter(Boolean).join(' ') || 'Current cashier'}</div>
              <div className="flex justify-end gap-2">
                <button type="button" onClick={() => onRecall(row.id)} className={primaryButton}>Resume</button>
                <button type="button" onClick={() => onDiscard(row.id)} className={dangerButton}>Discard</button>
              </div>
            </div>
          ))}
        </div>
      )}
    </Section>
  );
}

function RefundView({ invoiceId, setInvoiceId, invoice, loading, selections, setSelections, processing, onProcess }: {
  invoiceId: string;
  setInvoiceId: (value: string) => void;
  invoice: any;
  loading: boolean;
  selections: RefundLineSelection[];
  setSelections: React.Dispatch<React.SetStateAction<RefundLineSelection[]>>;
  processing: boolean;
  onProcess: () => void;
}) {
  const selectedTotal = selections.reduce((sum, selection) => {
    const line = invoice?.line_items?.find((item: any) => item.id === selection.line_item_id);
    return sum + (line ? Number(line.unit_price ?? line.price ?? 0) * selection.quantity : 0);
  }, 0);
  const toggleLine = (line: any) => {
    setSelections((prev) => {
      if (prev.some((item) => item.line_item_id === line.id)) return prev.filter((item) => item.line_item_id !== line.id);
      return [...prev, { line_item_id: line.id, quantity: 1, reason: 'customer return' }];
    });
  };
  return (
    <div className="mx-auto max-w-5xl">
      <Section className="p-5">
        <div className="grid gap-3 md:grid-cols-[1fr_auto]">
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">Invoice or receipt number</span>
            <input className={inputClass} value={invoiceId} onChange={(event) => setInvoiceId(event.target.value)} placeholder="28014" />
          </label>
          <div className="flex items-end">
            <Pill tone={loading ? 'warning' : invoice ? 'success' : 'neutral'}>{loading ? 'loading' : invoice ? 'found' : 'idle'}</Pill>
          </div>
        </div>
      </Section>
      {invoice && (
        <Section className="mt-4 overflow-hidden">
          <div className="border-b border-surface-200 px-4 py-3 text-sm font-semibold dark:border-surface-800">Returnable lines</div>
          <div className="divide-y divide-surface-200 dark:divide-surface-800">
            {invoice.line_items?.map((line: any) => {
              const selected = selections.some((item) => item.line_item_id === line.id);
              return (
                <button key={line.id} type="button" onClick={() => toggleLine(line)} className="grid w-full grid-cols-[32px_1fr_120px] gap-3 px-4 py-3 text-left hover:bg-surface-50 dark:hover:bg-surface-900">
                  <span className={cn('mt-1 h-5 w-5 rounded border', selected ? 'border-primary-500 bg-primary-500' : 'border-surface-300 dark:border-surface-700')} />
                  <span>
                    <span className="block font-semibold">{line.description || line.name}</span>
                    <span className="text-sm text-surface-900 dark:text-surface-500">Returnable qty {line.returnable_quantity ?? line.quantity ?? 1}</span>
                  </span>
                  <span className="text-right font-mono">{formatCurrency(Number(line.total ?? line.amount ?? line.unit_price ?? 0))}</span>
                </button>
              );
            })}
          </div>
          <div className="flex items-center justify-between border-t border-surface-200 p-4 dark:border-surface-800">
            <div>
              <div className="text-sm text-surface-900 dark:text-surface-500">Refund total</div>
              <div className="font-display text-4xl">{formatCurrency(selectedTotal)}</div>
            </div>
            <button type="button" onClick={onProcess} disabled={processing || selections.length === 0} className={dangerButton}>
              Process refund
            </button>
          </div>
        </Section>
      )}
    </div>
  );
}

function CloseShiftView({ cashCount, setCashCount, onPopDrawer }: {
  cashCount: Record<string, string>;
  setCashCount: React.Dispatch<React.SetStateAction<Record<string, string>>>;
  onPopDrawer: () => void;
}) {
  const counted = Object.entries(cashCount).reduce((sum, [denom, count]) => sum + Number(denom) * (Number.parseInt(count || '0', 10) || 0), 0);
  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
      <Section className="p-5">
        <div className="flex items-center justify-between">
          <div>
            <div className="font-display text-3xl">Close shift</div>
            <div className="text-sm text-surface-900 dark:text-surface-500">Count denominations, review Z-report, then lock the register.</div>
          </div>
          <button type="button" onClick={onPopDrawer} className={secondaryButton}><Banknote className="h-4 w-4" /> Pop drawer</button>
        </div>
        <div className="mt-5 grid gap-3 sm:grid-cols-3">
          {Object.keys(cashCount).map((denom) => (
            <label key={denom} className="block">
              <span className="mb-1 block text-sm font-semibold">{formatCurrency(Number(denom))}</span>
              <input className={inputClass} value={cashCount[denom]} onChange={(event) => setCashCount((prev) => ({ ...prev, [denom]: event.target.value }))} inputMode="numeric" />
            </label>
          ))}
        </div>
      </Section>
      <Section className="p-5">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Counted cash</div>
        <div className="mt-1 font-display text-5xl">{formatCurrency(counted)}</div>
        <div className="mt-5 space-y-3 text-sm">
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Gross sales</span><span className="font-mono">{formatCurrency(1832.44)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Refunds</span><span className="font-mono text-red-600">-{formatCurrency(34.88)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Card tender</span><span className="font-mono">{formatCurrency(1260.12)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Expected cash</span><span className="font-mono">{formatCurrency(537.44)}</span></div>
          <div className="border-t border-surface-200 pt-3 dark:border-surface-800">
            <div className="flex justify-between font-semibold"><span>Variance</span><span className="font-mono">{formatCurrency(counted - 537.44)}</span></div>
          </div>
        </div>
        <button type="button" className={cn(primaryButton, 'mt-6 w-full')}>Lock register</button>
      </Section>
    </div>
  );
}

function LineEditModal({ item, onClose, onSave }: {
  item: CartItem;
  onClose: () => void;
  onSave: (updates: Partial<CartItem>) => void;
}) {
  const [name, setName] = useState(lineTitle(item));
  const [price, setPrice] = useState(
    item.type === 'repair' ? String(item.laborPrice) : item.type === 'product' ? String(item.unitPrice) : String(item.unitPrice),
  );
  const [discount, setLineDiscount] = useState(item.type === 'repair' ? String(item.lineDiscount) : '0');
  return (
    <Modal
      title="Edit Cart Line"
      onClose={onClose}
      footer={
        <div className="flex justify-end gap-2">
          <button type="button" className={secondaryButton} onClick={onClose}>Cancel</button>
          <button
            type="button"
            className={primaryButton}
            onClick={() => {
              if (item.type === 'repair') onSave({ serviceName: name, laborPrice: parseMoney(price), lineDiscount: parseMoney(discount) } as Partial<CartItem>);
              if (item.type === 'product') onSave({ name, unitPrice: parseMoney(price) } as Partial<CartItem>);
              if (item.type === 'misc') onSave({ name, unitPrice: parseMoney(price) } as Partial<CartItem>);
            }}
          >
            Save line
          </button>
        </div>
      }
    >
      <div className="space-y-4">
        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Line name</span>
          <input className={inputClass} value={name} onChange={(event) => setName(event.target.value)} />
        </label>
        <label className="block">
          <span className="mb-1 block text-sm font-semibold">Unit or labor price</span>
          <input className={inputClass} inputMode="decimal" value={price} onChange={(event) => setPrice(event.target.value)} />
        </label>
        {item.type === 'repair' && (
          <label className="block">
            <span className="mb-1 block text-sm font-semibold">Line discount</span>
            <input className={inputClass} inputMode="decimal" value={discount} onChange={(event) => setLineDiscount(event.target.value)} />
          </label>
        )}
        <div className="rounded-lg border border-surface-200 p-3 text-sm text-surface-900 dark:text-surface-500 dark:border-surface-800">
          Edits are kept in the POS cart and sent with checkout.
        </div>
      </div>
    </Modal>
  );
}

function ReceiptView({ sale, onNext }: { sale: CompletedSale; onNext: () => void }) {
  return (
    <div className="h-full overflow-auto p-4">
      <div className="mx-auto grid max-w-6xl gap-4 lg:grid-cols-[minmax(0,1fr)_420px]">
        <div className="flex flex-col gap-4">
          <Section className="p-6 text-center">
            <CheckCircle2 className="mx-auto h-14 w-14 text-emerald-600 dark:text-[#34C47E]" />
            <div className="mt-4 font-display text-5xl">Payment complete</div>
            <div className="mt-2 font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(sale.total)}</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">{sale.orderId} · {sale.customerName}</div>
            {sale.change > 0 && <Pill tone="success" className="mt-4">Change due {formatCurrency(sale.change)}</Pill>}
          </Section>
          <div className="grid gap-3 sm:grid-cols-4">
            {[
              ['SMS', MessageSquare],
              ['Email', Mail],
              ['Print', Printer],
              ['PDF', FileText],
            ].map(([label, Icon]) => (
              <button key={label as string} type="button" className="rounded-lg border border-surface-200 bg-white p-4 text-center font-semibold hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900">
                <Icon className="mx-auto h-5 w-5 text-primary-700 dark:text-primary-500" />
                <span className="mt-2 block">{label as string}</span>
              </button>
            ))}
          </div>
          <Section className="p-5">
            <div className="flex items-center gap-3">
              <Star className="h-8 w-8 text-cyan-700 dark:text-[#4DB8C9]" />
              <div className="flex-1">
                <div className="font-semibold">Loyalty updated</div>
                <div className="text-sm text-surface-900 dark:text-surface-500">Points and warranty history are attached when a customer is selected.</div>
              </div>
            </div>
          </Section>
          <div className="flex flex-wrap gap-2">
            <button type="button" onClick={onNext} className={primaryButton}>Next sale</button>
            {sale.invoiceId && <button type="button" onClick={() => window.location.assign(`/invoices/${sale.invoiceId}`)} className={secondaryButton}>Open invoice</button>}
          </div>
        </div>
        <Section className="p-5 font-mono text-sm">
          <div className="text-center font-display text-3xl">BIZARRE REPAIR</div>
          <div className="mt-1 text-center text-xs text-surface-900 dark:text-surface-500">Receipt {sale.orderId}</div>
          <div className="my-4 border-t border-dashed border-surface-300 dark:border-surface-700" />
          <div className="flex justify-between"><span>Customer</span><span>{sale.customerName}</span></div>
          <div className="flex justify-between"><span>Date</span><span>{sale.completedAt.toLocaleString()}</span></div>
          <div className="my-4 border-t border-dashed border-surface-300 dark:border-surface-700" />
          {sale.items.map((item) => (
            <div key={item.id} className="mb-2">
              <div className="flex justify-between gap-3"><span>{lineTitle(item)}</span><span>{formatCurrency(lineAmount(item))}</span></div>
              <div className="text-xs text-surface-900 dark:text-surface-500">{lineSubtitle(item)}</div>
            </div>
          ))}
          <div className="my-4 border-t border-dashed border-surface-300 dark:border-surface-700" />
          <div className="flex justify-between"><span>Subtotal</span><span>{formatCurrency(sale.subtotal)}</span></div>
          {sale.discount > 0 && <div className="flex justify-between text-emerald-700 dark:text-[#34C47E]"><span>Discount</span><span>-{formatCurrency(sale.discount)}</span></div>}
          <div className="flex justify-between"><span>Tax</span><span>{formatCurrency(sale.tax)}</span></div>
          <div className="mt-2 flex justify-between font-bold"><span>Total</span><span>{formatCurrency(sale.total)}</span></div>
          <div className="my-4 border-t border-dashed border-surface-300 dark:border-surface-700" />
          {sale.payments.map((leg, index) => (
            <div key={`${leg.method}-${index}`} className="flex justify-between"><span>{leg.method}</span><span>{formatCurrency(leg.amount)}</span></div>
          ))}
          {sale.change > 0 && <div className="flex justify-between"><span>Change</span><span>{formatCurrency(sale.change)}</span></div>}
          <div className="mt-6 text-center text-xs text-surface-900 dark:text-surface-500">Thank you.</div>
        </Section>
      </div>
    </div>
  );
}
