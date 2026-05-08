import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
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
import { repairPricingApi } from '@/api/endpoints';
import type { RepairPricingMatrixResponse, RepairPricingMatrixPrice } from '@/api/types';
import {
  blockchypApi,
  customerApi,
  inventoryApi,
  leadApi,
  posApi,
  settingsApi,
  ticketApi,
} from '@/api/endpoints';
import { useDefaultTaxRateWithStatus } from '@/hooks/useDefaultTaxRate';
import { useUiStore } from '@/stores/uiStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDateTime, formatTime, generateIdempotencyKey, toLocalDateString } from '@/utils/format';
import { stripPhone } from '@/utils/phoneFormat';
import { PinModal } from '@/components/shared/PinModal';
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
  | 'repair-category'
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
  customerGroup?: string | null;
  itemSummary: string;
  progressLabel: string;
  total: number;
  statusName: string;
}

interface CreateCustomerDraft {
  customerType: 'individual' | 'business';
  firstName: string;
  lastName: string;
  title: string;
  phone: string;
  email: string;
  organization: string;
  customerGroupId: number | null;
  taxClassId: number | null;
  referredBy: string;
  // Address
  address1: string;
  address2: string;
  city: string;
  state: string;
  postcode: string;
  country: string;
  contactPerson: string;
  // Additional
  comments: string;
  taxNumber: string;
  idType: string;
  idNumber: string;
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

/**
 * One problem selected on the Issue step. Pulls from the device's
 * repair-pricing matrix when device_model_id is known; falls back to the
 * service catalog when the device was free-typed (no model id, manual price).
 *
 * `priceCents` carries the labor in CENTS so we don't accumulate float drift
 * when the total tally re-renders. Custom problems get a synthetic id prefix
 * `custom:<uuid>` so toggling state still keys cleanly.
 */
interface SelectedProblem {
  id: string;                       // `${repair_service_id}` or `custom:<rand>`
  repairServiceId: number | null;   // null for custom problems
  name: string;
  category: string | null;          // server `repair_services.category`
  priceCents: number;
  isCustom: boolean;
}

interface RepairDraft {
  deviceType: string;
  /** Optional `device_models.id` when picked from catalog. Drives the Issue
   * step's price lookup. Null when device name was free-typed. */
  deviceModelId: number | null;
  deviceName: string;
  imei: string;
  serial: string;
  condition: string;
  symptoms: string[];
  /** New flow: priced repair operations from `repair_services`. Replaces the
   * old free-form symptom-checklist on the Issue step. Multi-select, each
   * line becomes a quote line. */
  selectedProblems: SelectedProblem[];
  customerWords: string;
  /** Mockup Frame 05: staff-only note that never prints on the receipt.
   * Hidden by default; opens via the "+ Add internal note" link. */
  internalNote: string;
  internalNoteOpen: boolean;
  diagnostic: string;
  serviceName: string;
  laborPrice: string;
  depositAmount: string;
  waiverHandled: boolean;
  /** Mockup Frame 06 (quote): assigned technician + promised turnaround.
   * Captured at quote time so the deposit confirmation + customer-facing
   * receipt can show "Tech mike · same-day" without re-prompting. */
  technician: string;
  turnaround: string;
}

interface RefundLineSelection {
  line_item_id: number;
  quantity: number;
  reason: string;
}

const DEFAULT_REPAIR_DRAFT: RepairDraft = {
  // Empty by default. The Category step asks the cashier to pick first; no
  // implicit "Phone / iPhone" pre-fill. Server accepts whatever device_type
  // string lands so the lowercase category slug ("phone") is fine.
  deviceType: '',
  deviceModelId: null,
  deviceName: '',
  imei: '',
  serial: '',
  condition: 'Good',
  symptoms: [],
  selectedProblems: [],
  customerWords: '',
  internalNote: '',
  internalNoteOpen: false,
  diagnostic: '',
  serviceName: 'Diagnostic repair',
  laborPrice: '79.00',
  depositAmount: '50.00',
  waiverHandled: false,
  technician: '',
  turnaround: 'Same-day',
};

// Mockup Frame 06 picker options. Technician list is a stub — real impl will
// query GET /users?role=technician and surface availability. Turnaround is
// fixed text; storing as freeform string lets shops add custom SLAs without
// a migration.
const TURNAROUND_OPTIONS = ['Same-day', '24 hours', '2-3 days', '5-7 days', 'Mail-in (10+ days)'];
const TECHNICIAN_OPTIONS_STUB = ['Mike', 'Tasha', 'Devon', 'Priya', '— unassigned —'];

// Backup-pos parity: 9 device categories. Each tile is one screen in the
// repair flow ("Category" step). Picking one routes to the Device step which
// queries `/catalog/devices?category=<value>` for popular models.
// `quick` is the escape hatch — skip the device picker entirely and intake
// the ticket without a specific device.
const CATEGORY_TILES: Array<{ value: string; label: string; emoji: string }> = [
  { value: 'phone',         label: 'Mobile / Phone',  emoji: '📱' },
  { value: 'tablet',        label: 'Tablet',          emoji: '📲' },
  { value: 'laptop',        label: 'Laptop / Mac',    emoji: '💻' },
  { value: 'tv',            label: 'TV',              emoji: '📺' },
  { value: 'desktop',       label: 'Desktop',         emoji: '🖥️' },
  { value: 'console',       label: 'Game console',    emoji: '🎮' },
  { value: 'data_recovery', label: 'Data recovery',   emoji: '💾' },
  { value: 'other',         label: 'Other',           emoji: '❓' },
  { value: 'quick',         label: 'Quick check-in',  emoji: '⚡' },
];

// Per-category manufacturer chips. Mirrors backup pos so the Device step
// surfaces a one-tap filter to narrow the popular-devices grid.
const MANUFACTURER_SHORTCUTS: Record<string, string[]> = {
  phone: ['Apple', 'Samsung', 'Google', 'Motorola', 'OnePlus', 'LG'],
  tablet: ['Apple', 'Samsung', 'Lenovo', 'Microsoft'],
  laptop: ['Apple', 'Dell', 'HP', 'Lenovo', 'Asus', 'Acer'],
  console: ['Nintendo', 'PlayStation', 'Xbox', 'Steam'],
  tv: ['Samsung', 'LG', 'Sony', 'TCL', 'Vizio'],
  desktop: ['Apple', 'Dell', 'HP', 'Lenovo'],
};

const DEVICE_PLACEHOLDER: Record<string, string> = {
  phone: 'e.g. Samsung Galaxy A15',
  tablet: 'e.g. iPad Air 5th Gen',
  laptop: 'e.g. Dell Latitude 5540',
  tv: 'e.g. Samsung UN55TU7000',
  console: 'e.g. PlayStation 5 Slim',
  desktop: 'e.g. Dell OptiPlex 7080',
  other: 'e.g. DJI Mavic 3',
  data_recovery: 'e.g. WD My Passport 2TB',
  quick: 'e.g. Samsung Galaxy A15',
};

const EMPTY_CREATE_CUSTOMER_DRAFT: CreateCustomerDraft = {
  customerType: 'individual',
  firstName: '',
  lastName: '',
  title: '',
  phone: '',
  email: '',
  organization: '',
  customerGroupId: null,
  taxClassId: null,
  referredBy: '',
  address1: '',
  address2: '',
  city: '',
  state: '',
  postcode: '',
  country: '',
  contactPerson: '',
  comments: '',
  taxNumber: '',
  idType: '',
  idNumber: '',
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
  `${buttonBase} bg-primary-500 text-on-primary shadow-sm hover:bg-primary-400 dark:bg-primary-500 dark:text-primary-950`;
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
    const sn = item.device.imei || item.device.serial || 'No serial yet';
    const tech = item.technician ? `tech ${item.technician}` : null;
    const turnaround = item.turnaround ? item.turnaround.toLowerCase() : null;
    // Tail = "tech mike · same-day" when both present, just one when only one set,
    // empty otherwise. Joined with the existing serial + parts segments by " · ".
    const tail = [tech, turnaround].filter(Boolean).join(' · ');
    return [`${sn} · ${parts} part${parts === 1 ? '' : 's'}`, tail].filter(Boolean).join(' · ');
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

/** Human label for the resolved refund method returned by /pos/return.
 *  Server resolves 'original' to one of cash/card/store_credit before
 *  responding, so this just maps the four canonical values. */
function formatRefundMethodLabel(method: string): string {
  switch (method) {
    case 'cash': return 'cash from drawer';
    case 'card': return 'card · reverse charge';
    case 'store_credit': return 'store credit';
    default: return method;
  }
}

function appointmentStatusLabel(appointment: PosAppointment, nowMs = Date.now()): string {
  if (appointment.no_show) return 'no-show';
  const status = appointment.status || 'scheduled';
  if (status !== 'scheduled' && status !== 'confirmed') return status;
  const startsAt = new Date(appointment.start_time).getTime();
  if (!Number.isFinite(startsAt)) return status;
  const minutes = Math.round((startsAt - nowMs) / 60000);
  if (minutes > 60) return `in ${Math.round(minutes / 60)}h`;
  if (minutes > 0) return `in ${minutes}m`;
  if (minutes === 0) return 'due now';
  if (minutes >= -15) return 'due now';
  if (minutes >= -120) return `${-minutes}m late`;
  if (minutes >= -1440) return `${Math.round(-minutes / 60)}h late`;
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
  // List-shape returns `first_device` (single object) + `device_count`; detail
  // shape returns `devices` (array). Accept either.
  const devices: any[] = Array.isArray(ticket.devices)
    ? ticket.devices
    : ticket.first_device
      ? [ticket.first_device]
      : [];
  const deviceLabels = devices.map((device: any) => {
    const deviceName = device.device_name || device.device_type || 'Device';
    const serviceName = device.service?.name || device.service_name || device.issue || device.problem || '';
    return serviceName ? `${deviceName} - ${serviceName}` : deviceName;
  }).filter(Boolean);

  const moreCount = Math.max(0, Number(ticket.device_count ?? deviceLabels.length) - 1);
  if (deviceLabels.length === 0) return ticket.latest_diagnostic_note || ticket.latest_internal_note || 'Repair ticket';
  if (moreCount <= 0) return deviceLabels[0];
  return `${deviceLabels[0]} + ${moreCount} more`;
}

function pickupProgressLabel(ticket: any): string {
  const status = String(ticket.status?.name || ticket.status_name || '').toLowerCase();
  const prefix = status.includes('qc') ? 'QC' : 'Ready';
  return `${prefix} ${formatTime(ticket.updated_at || ticket.created_at)}`;
}

function shapePickupTicket(ticket: any, fallback?: any): PosPickupTicket {
  const source = ticket ?? fallback ?? {};
  const groupName = source.customer?.customer_group?.name
    || source.customer?.group_name
    || source.customer_group_name
    || fallback?.customer?.group_name
    || null;
  return {
    id: Number(source.id),
    order_id: source.order_id || `#${source.id}`,
    customerName: customerNameFromTicket(source),
    customerGroup: groupName,
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

// Five-step repair-intake stepper. "Category" was previously baked into the
// "Device" step (same screen rendered the type chips + the model picker)
// which made it easy to lose your place — picking a category jumped you down
// the page rather than to a fresh screen. Now Category and Device are two
// separate stops, matching the iOS / Android flow + the backup web POS.
type RepairStepKey = 'category' | 'device' | 'issue' | 'quote' | 'deposit';

function Stepper({ step, onGoToStep }: { step: RepairStepKey; onGoToStep?: (target: RepairStepKey) => void }) {
  const steps: Array<{ key: RepairStepKey; label: string }> = [
    { key: 'category', label: 'Category' },
    { key: 'device', label: 'Device' },
    { key: 'issue', label: 'Issue' },
    { key: 'quote', label: 'Quote' },
    { key: 'deposit', label: 'Deposit' },
  ];
  const activeIndex = steps.findIndex((item) => item.key === step);
  return (
    <div className="flex items-center gap-3">
      {steps.map((item, index) => {
        // Past steps clickable — jump back without losing draft. Future steps
        // disabled (data not collected yet). Active step is its own page,
        // re-clicking is harmless but no-op.
        const isPast = index < activeIndex;
        const interactive = isPast && Boolean(onGoToStep);
        const Tag: any = interactive ? 'button' : 'div';
        const handler = interactive ? () => onGoToStep!(item.key) : undefined;
        return (
          <div key={item.key} className="flex items-center gap-3">
            <Tag
              type={interactive ? 'button' : undefined}
              onClick={handler}
              disabled={interactive ? false : undefined}
              className={cn(
                'flex items-center gap-2 rounded-full transition',
                interactive && 'cursor-pointer hover:opacity-80 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/60 focus-visible:ring-offset-2 focus-visible:ring-offset-surface-950',
              )}
              title={interactive ? `Back to ${item.label}` : undefined}
            >
              <span
                className={cn(
                  'grid h-6 w-6 place-items-center rounded-full border text-xs font-bold',
                  index < activeIndex && 'border-emerald-500 bg-emerald-500 text-white',
                  index === activeIndex && 'border-primary-500 bg-primary-500 text-on-primary',
                  index > activeIndex && 'border-surface-300 bg-surface-100 text-surface-900 dark:text-surface-500 dark:border-surface-700 dark:bg-surface-800',
                )}
              >
                {index < activeIndex ? <CheckCircle2 className="h-3.5 w-3.5" /> : index + 1}
              </span>
              <span className={cn('text-sm font-semibold', isPast ? 'text-surface-900 dark:text-surface-200 underline decoration-dotted underline-offset-4' : 'text-surface-700 dark:text-surface-300')}>{item.label}</span>
            </Tag>
            {index < steps.length - 1 && <div className="hidden h-px w-10 bg-surface-200 dark:bg-surface-700 sm:block" />}
          </div>
        );
      })}
    </div>
  );
}

// Tab strip portals UP into AppShell header's `#pos-header-slot` when present
// so the shell-header empty space is reclaimed by sale tabs (parallel-sale UX).
// Falls back to inline rendering if slot not yet mounted.
function PosTabStripShell({ headerSlot, children }: { headerSlot: HTMLElement | null; children: React.ReactNode }) {
  if (headerSlot) {
    return createPortal(
      <div className="flex h-full flex-1 items-end gap-1 min-w-0 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {children}
      </div>,
      headerSlot,
    );
  }
  return (
    <div className="flex h-[38px] shrink-0 items-center gap-2 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-950 px-4 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
      {children}
    </div>
  );
}

export function UnifiedPosPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [searchParams, setSearchParams] = useSearchParams();
  const setCommandPaletteOpen = useUiStore((state) => state.setCommandPaletteOpen);
  const commandPaletteOpen = useUiStore((state) => state.commandPaletteOpen);
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
  const [headerSlot, setHeaderSlot] = useState<HTMLElement | null>(null);
  useEffect(() => {
    let cancelled = false;
    const find = () => {
      if (cancelled) return;
      const el = document.getElementById('pos-header-slot');
      if (el) setHeaderSlot(el); else requestAnimationFrame(find);
    };
    find();
    return () => { cancelled = true; setHeaderSlot(null); };
  }, []);
  const [lineEditing, setLineEditing] = useState<CartItem | null>(null);
  const [discountOpen, setDiscountOpen] = useState(false);
  const [discountDraft, setDiscountDraft] = useState('');
  const [discountReasonDraft, setDiscountReasonDraft] = useState('cashier adjustment');
  // Holds a discount that exceeds the 25%-of-subtotal manager-approval bar.
  // applyDiscount() parks here instead of committing; PinModal commits on success.
  const [pendingDiscount, setPendingDiscount] = useState<{ amount: number; reason: string } | null>(null);
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
  // Refund-to method (back-to-original is the canonical default per Frame 18 spec).
  // Stored in state; server-side wiring follows in a separate change — `/pos/return`
  // currently always issues a credit note. Keeping the UI control honest with users
  // is more important than waiting for the wire — they need to *see* the choice.
  const [refundMethod, setRefundMethod] = useState<'original' | 'cash' | 'card' | 'store_credit'>('original');
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

  // Clear any stale `showSuccess` flag from a previous session on mount.
  // Was deps `[showSuccess, setShowSuccess]` which re-fired on every change
  // and caused an extra render after every successful sale. Runs once.
  useEffect(() => {
    setShowSuccess(null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

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
      group_name: item.group_name ?? item.customer_group_name ?? null,
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

  // Gate's open-tickets feed. Was "ready for pickup only"; user wants the
  // full active queue with ready-for-pickup rows pinned to the top so the
  // cashier can see *all* current open work in one place. Sort: ready first
  // (sub-sorted by updated_at DESC), then everything else by updated_at DESC.
  // Cap at 8 visible rows; "View active tickets" link still jumps to the
  // full list.
  const readyPickupQuery = useQuery({
    queryKey: ['pos-open-tickets'],
    queryFn: async () => {
      const listRes = await ticketApi.list({
        status_group: 'active',
        pagesize: 100,
        sort_by: 'updated_at',
        sort_order: 'DESC',
      });
      const payload = listRes.data?.data;
      const rows: any[] = Array.isArray(payload?.tickets)
        ? payload.tickets
        : Array.isArray(listRes.data?.tickets)
          ? listRes.data.tickets
          : [];
      // Two physically separate buckets: ready-for-pickup (capped section,
      // pinned top of the gate) and everything else still active. Each
      // bucket renders in its own scroll surface so a long ready list never
      // pushes the in-progress queue off the screen and vice versa.
      const readyRows = rows.filter((t) => isReadyPickupStatus(t.status_name ?? t.status?.name));
      const otherRows = rows.filter((t) => !isReadyPickupStatus(t.status_name ?? t.status?.name));
      const visibleReady = readyRows.slice(0, 20);
      const visibleOthers = otherRows.slice(0, 30);

      const shape = async (row: any) => {
        try {
          const detailRes = await ticketApi.get(Number(row.id));
          return shapePickupTicket(detailRes.data?.data, row);
        } catch {
          return shapePickupTicket(row);
        }
      };
      const [ready, others] = await Promise.all([
        Promise.all(visibleReady.map(shape)),
        Promise.all(visibleOthers.map(shape)),
      ]);

      return {
        total: rows.length,
        readyTotal: readyRows.length,
        otherTotal: otherRows.length,
        ready,
        others,
      };
    },
    enabled: mode === 'gate',
    staleTime: 30_000,
    refetchInterval: 60_000,
    refetchIntervalInBackground: false,
  });

  const readyPickup = readyPickupQuery.data ?? {
    total: 0,
    readyTotal: 0,
    otherTotal: 0,
    ready: [] as PosPickupTicket[],
    others: [] as PosPickupTicket[],
  };

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
    // Background-poll silently — transient SQLite busy / network errors should
    // not surface a global toast to the cashier mid-sale. The tab strip + Recall
    // pill simply skip the update on this tick and try again on the next.
    queryFn: () => api.get<{ success: boolean; data: HeldCartRow[] }>('/pos/held-carts', { skipGlobal500Toast: true } as object),
    staleTime: 10_000,
  });
  const heldCartCount = heldCarts.data?.data?.data?.length ?? 0;

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
      // Hold during tender (paidLegs already filled) is a footgun — a Cash
      // leg is in the drawer, a Card leg already settled at the terminal,
      // and the held snapshot wouldn't replay either. Bounce the hold
      // attempt back to the picker; cashier must finish or cancel tender.
      if (paidLegs.length > 0) {
        throw new Error('Finish or cancel current payment before holding');
      }
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
      }, { skipGlobal500Toast: true } as object);
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

  /**
   * POST a blank held-cart row server-side. Used as a placeholder so an
   * empty active tab still has a server-backed entry when the cashier
   * spawns or switches tabs. Returns the same promise the caller can
   * await before continuing the switch / reset flow.
   */
  const persistBlankTab = useCallback(async () => {
    const blankSnapshot: HeldCartSnapshot = {
      customer: null,
      cartItems: [],
      discount: 0,
      discountReason: '',
      memberDiscountApplied: false,
      meta: {
        assignedTo: null,
        dueDate: '',
        source: 'Walk-in',
        internalNotes: '',
        labels: '',
        discountReason: '',
        referralSource: '',
      },
      sourceTicketId: null,
    };
    try {
      await api.post('/pos/held-carts', {
        cart_json: JSON.stringify(blankSnapshot),
        label: 'New sale',
        customer_id: null,
        total_cents: 0,
      }, { skipGlobal500Toast: true } as object);
      await queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
    } catch (err: any) {
      toast.error(err?.response?.data?.message || 'Could not park empty tab');
      throw err;
    }
  }, [queryClient]);

  /**
   * Mint a blank tab + reset the active slot to a fresh gate. Used by
   * the `+` button when the active draft is empty so the cashier can
   * fan out as many parallel intake slots as they want.
   */
  const spawnBlankTab = useCallback(() => {
    persistBlankTab().then(startNewSale).catch(() => undefined);
  }, [persistBlankTab, startNewSale]);

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
    // Clear any in-flight tender state from the previous cart so the recalled
    // sale starts fresh: prior paidLegs would be re-summed into change math
    // (double-credit), a stale terminalError banner would haunt the new cart,
    // amountEntry would prefill with the previous remainder, and a hung
    // `processing` flag would keep the Charge button disabled forever.
    setPaidLegs([]);
    setProcessing(false);
    setTerminalError(null);
    setAmountEntry('');
    setMode('sale');
  }, [addMisc, addProduct, addRepair, resetAll, setCustomer, setDiscount, setMemberDiscountApplied, setMeta, setSourceTicketId]);

  // recallMutation now serves two patterns:
  //   • Server-first (default): server response drives state restore. Used
  //     when the client doesn't have the snapshot cached (recall from
  //     elsewhere, list-not-loaded edge cases).
  //   • Client-first (`{ skipRestore: true }`): we already restored locally
  //     from the cached `cart_json`; mutation just marks the row as
  //     recalled server-side. Avoids clobbering any keystrokes the cashier
  //     made between the click and the server reply.
  const recallMutation = useMutation({
    mutationFn: ({ id }: { id: number; skipRestore?: boolean }) =>
      api.post<{ success: boolean; data: HeldCartRow }>(`/pos/held-carts/${id}/recall`, {}, { skipGlobal500Toast: true } as object),
    onSuccess: (res, vars) => {
      if (!vars.skipRestore) {
        const row = res.data.data;
        restoreSnapshot(JSON.parse(row.cart_json) as HeldCartSnapshot);
        toast.success('Held sale restored');
      }
      queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
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
    mutationFn: () => {
      // Frontend now sends `method` so server picks the right execution path.
      // 'original' lets the server detect from the invoice's payments; the
      // cashier's UI still lets them override (cash/card/store_credit).
      const methodMap = { original: 'original', cash: 'cash', card: 'card', store_credit: 'store_credit' } as const;
      return posApi.return({
        invoice_id: Number(refundInvoiceId),
        items: refundSelections.filter((line) => line.quantity > 0),
        method: methodMap[refundMethod],
      });
    },
    onSuccess: async (res) => {
      const data = res.data.data as any;
      const resolved = data.refund_method as string | undefined;
      const popDrawer = Boolean(data.pop_drawer);
      const summary = resolved
        ? `Refund processed · ${formatRefundMethodLabel(resolved)}`
        : 'Refund processed';
      toast.success(summary);
      if (popDrawer) {
        try { await api.post('/pos/open-drawer', { reason: 'cash-refund' }); } catch { /* drawer pop is best-effort */ }
      }
      setRefundSelections([]);
      queryClient.invalidateQueries({ queryKey: ['pos-returnable-invoice', refundInvoiceId] });
      queryClient.invalidateQueries({ queryKey: ['pos-register'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not process refund'),
  });

  const popDrawerMutation = useMutation({
    mutationFn: () => api.post('/pos/open-drawer', { reason: 'close-shift-count' }),
    onSuccess: () => toast.success('Drawer command sent'),
    onError: () => toast.error('Could not contact cash drawer'),
  });

  useEffect(() => {
    const handleKeys = (event: KeyboardEvent) => {
      // Esc cancels the foremost modal / wizard step. Lives outside the
      // mod-key gate because Esc never carries Cmd/Ctrl.
      if (event.key === 'Escape') {
        if (commandPaletteOpen) {
          setCommandPaletteOpen(false);
          event.preventDefault();
          return;
        }
        if (discountOpen) {
          setDiscountOpen(false);
          event.preventDefault();
          return;
        }
        if (lineEditing) {
          setLineEditing(null);
          event.preventDefault();
          return;
        }
        if (customItemOpen) {
          setCustomItemOpen(false);
          event.preventDefault();
          return;
        }
        if (mode.startsWith('tender')) {
          setMode('sale');
          event.preventDefault();
          return;
        }
      }
      const mod = event.metaKey || event.ctrlKey;
      if (!mod) return;
      const key = event.key.toLowerCase();
      if (key === 'k') {
        event.preventDefault();
        setCommandPaletteOpen(true);
      }
      if (key === 'n' && event.shiftKey) {
        // ⌘⇧N opens "Create new customer" inline panel on customer gate.
        event.preventDefault();
        if (mode === 'gate') openInlineCustomerCreate();
        return;
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
        // Don't stack on top of an open modal — the user mashing ⌘D while a
        // line-edit or custom-item modal is up would render two overlapping
        // dialogs with confusing focus.
        if (lineEditing || customItemOpen || pendingDiscount) return;
        setDiscountOpen(true);
      }
      if (key === 'b') {
        event.preventDefault();
        productInputRef.current?.focus();
      }
      if (key === 'w') {
        // ⌘W on customer gate triggers walk-in. Outside gate, leave the
        // browser default (close tab) alone — overriding it would surprise
        // users who actually want to close the tab.
        if (mode === 'gate') {
          event.preventDefault();
          startWalkIn();
        }
      }
      if (event.key === 'Enter') {
        event.preventDefault();
        if (mode === 'sale' && cartItems.length > 0) setMode('tender-method');
      }
    };
    window.addEventListener('keydown', handleKeys);
    return () => window.removeEventListener('keydown', handleKeys);
    // `startWalkIn`, `openInlineCustomerCreate`, and `startNewSale` are
    // declared further down the file; including them in deps trips a TDZ.
    // They're effectively-stable component-scope helpers, so the latest
    // closure will read the latest value off the next mount.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [cartItems.length, customer, holdMutation, mode, setCommandPaletteOpen, commandPaletteOpen, discountOpen, lineEditing, customItemOpen, pendingDiscount]);

  const saveRepairToCart = useCallback(() => {
    if (!repairDraft.deviceName.trim()) {
      toast.error('Add a device name first');
      setMode('repair-device');
      return;
    }
    // New flow: one cart line per selected problem. The Issue step captures
    // the catalog of problems, the Quote step lets the cashier edit per-line
    // pricing, the Deposit step lands them all in the cart with consistent
    // device + condition metadata.
    const problems = repairDraft.selectedProblems;
    if (problems.length === 0) {
      // Quick check-in path skips Issue/Quote — fall back to single labor line
      // so quick walk-ins still produce a cart line.
      const labor = parseMoney(repairDraft.laborPrice);
      if (labor <= 0) {
        toast.error('Quote must include at least one problem or a labor amount');
        setMode('repair-quote');
        return;
      }
      addRepair({
        type: 'repair',
        id: genId(),
        device: {
          device_type: repairDraft.deviceType,
          device_name: repairDraft.deviceName,
          device_model_id: repairDraft.deviceModelId,
          imei: repairDraft.imei,
          serial: repairDraft.serial,
          security_code: '',
          color: '',
          network: '',
          pre_conditions: [],
          additional_notes: [
            repairDraft.condition ? `Condition: ${repairDraft.condition}` : '',
            repairDraft.customerWords ? `Customer: ${repairDraft.customerWords}` : '',
            repairDraft.diagnostic,
          ].filter(Boolean).join('\n'),
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
        technician: repairDraft.technician || undefined,
        turnaround: repairDraft.turnaround || undefined,
      });
    } else {
      problems.forEach((problem) => {
        addRepair({
          type: 'repair',
          id: genId(),
          device: {
            device_type: repairDraft.deviceType,
            device_name: repairDraft.deviceName,
            device_model_id: repairDraft.deviceModelId,
            imei: repairDraft.imei,
            serial: repairDraft.serial,
            security_code: '',
            color: '',
            network: '',
            pre_conditions: [repairDraft.condition].filter(Boolean),
            additional_notes: [repairDraft.customerWords, repairDraft.diagnostic].filter(Boolean).join('\n'),
            device_location: 'front counter',
            warranty: false,
            warranty_days: 90,
          },
          serviceName: problem.name,
          repairServiceId: problem.repairServiceId,
          selectedGradeId: null,
          laborPrice: problem.priceCents / 100,
          lineDiscount: 0,
          parts: [],
          taxable: false,
          technician: repairDraft.technician || undefined,
          turnaround: repairDraft.turnaround || undefined,
        });
      });
    }
    toast.success(problems.length > 1 ? `${problems.length} repair lines added` : 'Repair added to cart');
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
      // PIN gate (WEB-W1-P0): forward the verified-with-TTL flag so the
      // server's `requirePosPinByMode` middleware accepts checkout when
      // store_config.pos_require_pin_* is on. Without this, a cashier who
      // already PIN'd into the session would get a 403 on charge.
      const pinVerified = useUnifiedPosStore.getState().isPosPinVerified();
      const res = await posApi.checkoutWithTicket(payload, idempotencyKey, pinVerified);
      const invoiceId: number | null = res.data?.data?.invoice?.id ?? res.data?.data?.invoice_id ?? null;

      const cardLegs = legs.filter((leg) => leg.method === 'Card');
      if (invoiceId && cardLegs.length > 0) {
        // Idempotency: mint ONE base key for this checkout submission and
        // suffix per leg index. Previously the key was minted inside the loop,
        // so on retry of a partially-failed split (leg 1 captured, leg 2
        // declined) the cashier's "try again" would mint NEW keys for both
        // legs — leg 1 would re-process and double-charge.
        // Per-leg suffix keeps each card capture deduped server-side while
        // still being deterministic across retries within the same submit.
        const baseCardKey = ensureIdempotencyKey();
        for (let i = 0; i < cardLegs.length; i++) {
          const leg = cardLegs[i];
          const terminalRes = await blockchypApi.processPayment(
            invoiceId,
            `${baseCardKey}-bc-${i}`,
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

      // Change-making: ONLY cash overpay yields change. Card / gift / store
      // credit can't return cash, so non-cash legs are capped to "what's left
      // after subtotaling them against the total" and any cash surplus beyond
      // that is the change. Previously the code summed everything and treated
      // any overpay as change — meaning a $100 card on a $99.99 total would
      // pretend to dispense $0.01 cash from the drawer.
      // Sum in cents throughout to dodge the float-binary trap.
      const cashCents = legs.filter((leg) => leg.method === 'Cash').reduce((sum, leg) => sum + toCents(leg.amount), 0);
      const nonCashCents = legs.filter((leg) => leg.method !== 'Cash').reduce((sum, leg) => sum + toCents(leg.amount), 0);
      const cashNeededCents = Math.max(0, totals.totalCents - nonCashCents);
      const overpay = Math.max(0, cashCents - cashNeededCents);
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

  /**
   * Apply discount with manager-PIN gate at >25% of subtotal.
   *
   * The modal previously displayed an amber "should use manager approval"
   * advisory but didn't block — that's a footgun on a busy counter where the
   * cashier ignores the warning. Now we hard-gate by parking the action in
   * pendingDiscount state, opening PinModal, and committing only on success.
   */
  /**
   * Cart-row trash deletes immediately, but most accidental clicks are
   * recoverable in <8 s. Surface the removed item in a sticky toast with an
   * Undo action that re-adds the line via the type-specific add fn (qty,
   * discount, parts all preserved). Toast self-dismisses after 6 s — past
   * that the cashier can re-scan / re-add by hand.
   */
  const removeLineWithUndo = useCallback((id: string) => {
    const removed = useUnifiedPosStore.getState().cartItems.find((item) => item.id === id);
    removeCartItem(id);
    if (!removed) return;
    const label = lineTitle(removed);
    toast(
      (t) => (
        <span className="flex items-center gap-3">
          <span className="text-sm">Removed: <strong>{label}</strong></span>
          <button
            type="button"
            className="rounded-md bg-primary-500 px-2 py-1 text-xs font-bold text-on-primary"
            onClick={() => {
              if (removed.type === 'product') addProduct(removed);
              else if (removed.type === 'misc') addMisc(removed);
              else if (removed.type === 'repair') addRepair(removed);
              toast.dismiss(t.id);
            }}
          >
            Undo
          </button>
        </span>
      ),
      { duration: 6000 },
    );
  }, [addMisc, addProduct, addRepair, removeCartItem]);

  const applyDiscount = () => {
    const amount = parseMoney(discountDraft);
    if (totals.subtotal > 0 && amount > totals.subtotal * 0.25) {
      setPendingDiscount({ amount, reason: discountReasonDraft || 'cashier adjustment' });
      return;
    }
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

  // Default landing after attaching a customer (or going walk-in) is the
  // repair-device step — repairs are the primary thing most shops sell, and
  // parts get added inside the repair flow. Cashier who's actually doing a
  // pure retail sale hits "Cancel" on the wizard and lands on the catalog
  // (`mode === 'sale'`). Skip the wizard entirely if the cart already has
  // items (e.g. a recalled held cart) — they're past the intake stage.
  const defaultPostGateMode = (): PosMode =>
    cartItems.length > 0 ? 'sale' : 'repair-category';

  const selectCustomer = (nextCustomer: CustomerResult) => {
    setCustomer(nextCustomer);
    setWalkInActive(false);
    setCreateCustomerOpen(false);
    setGlobalSearch('');
    setMode(defaultPostGateMode());
  };

  const startWalkIn = () => {
    setCustomer(null);
    setWalkInActive(true);
    setCreateCustomerOpen(false);
    setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
    setGlobalSearch('');
    setMode(defaultPostGateMode());
  };

  const createCustomerMutation = useMutation({
    mutationFn: () => customerApi.create({
      first_name: createCustomerDraft.firstName.trim(),
      last_name: createCustomerDraft.lastName.trim() || undefined,
      title: createCustomerDraft.title.trim() || undefined,
      phone: stripPhone(createCustomerDraft.phone) || undefined,
      email: createCustomerDraft.email.trim() || undefined,
      organization: createCustomerDraft.organization.trim() || undefined,
      type: createCustomerDraft.customerType,
      customer_group_id: createCustomerDraft.customerGroupId ?? undefined,
      tax_class_id: createCustomerDraft.taxClassId ?? undefined,
      referred_by: createCustomerDraft.referredBy.trim() || undefined,
      address1: createCustomerDraft.address1.trim() || undefined,
      address2: createCustomerDraft.address2.trim() || undefined,
      city: createCustomerDraft.city.trim() || undefined,
      state: createCustomerDraft.state.trim() || undefined,
      postcode: createCustomerDraft.postcode.trim() || undefined,
      country: createCustomerDraft.country.trim() || undefined,
      contact_person: createCustomerDraft.contactPerson.trim() || undefined,
      tax_number: createCustomerDraft.taxNumber.trim() || undefined,
      id_type: createCustomerDraft.idType.trim() || undefined,
      id_number: createCustomerDraft.idNumber.trim() || undefined,
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

      // Server response shape varies between /customers (POST) and search
      // endpoints — POST may surface `customer_group_name`, search returns
      // `group_name`, and the joined customer detail uses both. Fall through
      // both keys so the new GOLD/VIP pill renders even when the wire shape
      // shifts.
      setCustomer({
        id: Number(created.id),
        first_name: created.first_name ?? '',
        last_name: created.last_name ?? '',
        phone: created.phone || null,
        mobile: created.mobile || null,
        email: created.email || null,
        organization: created.organization || null,
        group_name: created.group_name ?? created.customer_group_name ?? null,
        group_discount_pct: created.group_discount_pct,
        group_discount_type: created.group_discount_type,
        group_auto_apply: created.group_auto_apply,
      });
      setWalkInActive(false);
      setCreateCustomerOpen(false);
      setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
      setGlobalSearch('');
      // Match selectCustomer/startWalkIn: drop the freshly-created customer
      // straight into the repair-device step rather than the catalog.
      setMode(cartItems.length > 0 ? 'sale' : 'repair-category');
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['pos-customer-search'] });
      toast.success('Customer created');
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
    // Spec §3.6 (Frame 23): require phone OR email so the customer is
    // contactable. Saves a server round-trip + matches the visual hint
    // ("first name + one of phone / email") shown on the create panel.
    const hasPhone = !!stripPhone(createCustomerDraft.phone);
    const hasEmail = !!createCustomerDraft.email.trim();
    if (!hasPhone && !hasEmail) {
      toast.error('Add a phone or email — at least one is required');
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
      ? 'Held sales · recall'
      : mode === 'refund'
        ? 'Refund'
        : mode === 'close-shift'
          ? 'Close shift'
          : mode.startsWith('repair')
            ? 'Repair intake'
            : mode === 'tender-cash'
              ? `Cash · ${getCustomerName(customer)}`
              : mode === 'tender-card'
                ? `Card · ${getCustomerName(customer)}`
                : mode.startsWith('tender')
                  ? `Tender · ${getCustomerName(customer)}`
              : mode === 'receipt'
                ? 'Sale complete'
                : `New sale · ${getCustomerName(customer)}`;
  const subtitle =
    mode === 'gate'
      ? null
      : mode === 'held'
        ? `${heldCartCount} parked · resume or discard to free slots`
        : mode === 'refund'
          ? 'Pick lines + a refund-to method · manager PIN above threshold'
          : mode === 'close-shift'
            ? 'Count the drawer · variance ≤ $5 passes · larger needs a manager note'
            : mode === 'repair-category'
              ? 'Step 1 of 5 · pick a device category'
              : mode === 'repair-device'
                ? 'Step 2 of 5 · pick the model · or scan IMEI'
                : mode === 'repair-issue'
                  ? 'Step 3 of 5 · capture symptoms + condition'
                  : mode === 'repair-quote'
                    ? 'Step 4 of 5 · diagnostic + quote'
                    : mode === 'repair-deposit'
                      ? 'Step 5 of 5 · take deposit · drop-off waiver'
                    : mode === 'tender-method'
                      ? `${cartLineCount} line${cartLineCount === 1 ? '' : 's'} · choose payment method`
                      : mode === 'tender-cash'
                        ? `Charging ${formatCurrency(totals.total)} · type amount or use a preset · ↵ to confirm`
                        : mode === 'tender-card'
                          ? `Charging ${formatCurrency(totals.total)} · customer terminal handles tap / chip / swipe + tip`
                          : cartLineCount > 0
                            ? `${cartLineCount} line${cartLineCount === 1 ? '' : 's'} in cart · ${formatCurrency(totals.total)} due`
                            : 'Browse the catalog or scan to start adding items';

  return (
    <div className="-m-6 mx-auto flex h-[calc(100vh-4rem-var(--dev-banner-h,0px))] min-h-[720px] w-full max-w-[1440px] flex-col overflow-hidden bg-surface-50 dark:bg-surface-950 text-surface-900 dark:text-surface-50">
      <PosTabStripShell headerSlot={headerSlot}>
        {/* Tab order matches Chrome semantics: older tabs sit left, the
            active tab + the `+` button hug the right edge so a new tab
            visually opens to the RIGHT of the previously-active one.
            Server returns held carts DESC (newest first); reverse here so
            the just-held cart slots in immediately to the LEFT of the
            now-active tab — same intuition as Chrome's "duplicate to right". */}
        {[...(heldCarts.data?.data?.data ?? [])].reverse().map((row) => (
          // Tab is now an outer DIV (not a button) so we can nest the close
          // X as its own button without violating the no-nested-button rule.
          // The whole tab body still acts as a clickable area via the inner
          // `<button>` that fills the row.
          <div
            key={row.id}
            className="group relative inline-flex h-9 max-w-[220px] shrink-0 items-center rounded-t-lg bg-transparent text-xs font-semibold text-surface-700 dark:text-surface-400 hover:bg-surface-100/60 dark:hover:bg-surface-800/60 whitespace-nowrap transition-colors"
          >
            <button
              type="button"
              onClick={() => {
                // Instant tab switch. The held-carts LIST endpoint already
                // returns `cart_json` so we can hydrate the picked tab from
                // the cache synchronously — no recall round-trip, no
                // mid-switch loading flash.
                //
                // Server reconciliation runs IN PARALLEL after the swap:
                //   1. Hold the current tab (or blank-stub if empty) so it
                //      reappears in the strip when the user comes back.
                //   2. Fire `recall` against the picked row so it leaves
                //      `held_carts` and stays unique.
                //
                // If either background mutation fails the toast surfaces
                // the error; the visible tab swap still succeeded so the
                // cashier isn't held up by network jitter.
                const snapshot = (() => {
                  try { return JSON.parse(row.cart_json) as HeldCartSnapshot; } catch { return null; }
                })();
                if (snapshot) {
                  if (cartItems.length > 0 || customer) holdMutation.mutate();
                  else void persistBlankTab();
                  restoreSnapshot(snapshot);
                  recallMutation.mutate({ id: row.id, skipRestore: true });
                } else {
                  // Snapshot couldn't parse — fall back to server recall so
                  // we still get the data even if the local cache row was
                  // tampered with.
                  if (cartItems.length > 0 || customer) holdMutation.mutate();
                  else void persistBlankTab();
                  recallMutation.mutate({ id: row.id });
                }
              }}
              className="flex h-full min-w-0 flex-1 items-center gap-2 px-3 pr-1"
              title={`Resume ${row.label || `cart #${row.id}`}`}
            >
              <span className="grid h-3 w-3 shrink-0 place-items-center rounded-[3px] bg-primary-500 dark:bg-primary-500 text-[8px] font-black text-on-primary">B</span>
              <span className="truncate">#{row.id} · {row.label || (row.owner_first_name ? `${row.owner_first_name}${row.owner_last_name ? ' ' + row.owner_last_name[0] + '.' : ''}` : 'held')} (held)</span>
            </button>
            {/* Close X — discards held cart server-side. Stop propagation so
                clicking the X doesn't ALSO recall the tab. Hover-revealed on
                non-active tabs to keep the strip calm; visible on focus for
                keyboard users. */}
            <button
              type="button"
              onClick={(e) => {
                e.stopPropagation();
                if (window.confirm(`Close held cart #${row.id}? This drops the cart contents.`)) {
                  discardHeldMutation.mutate(row.id);
                }
              }}
              className="mr-1 grid h-5 w-5 shrink-0 place-items-center rounded text-surface-500 opacity-0 transition group-hover:opacity-100 focus:opacity-100 hover:bg-surface-200 dark:hover:bg-surface-700"
              title="Close tab"
              aria-label={`Close held cart #${row.id}`}
            >
              <X className="h-3 w-3" />
            </button>
          </div>
        ))}
        <button
          type="button"
          onClick={() => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate')}
          className={cn(
            // Chrome-style tab: rounded-top, distinct fill, an inset top
            // accent bar on active to read clearly as "this is the active
            // tab, others are switchable". Border between tabs comes from
            // the gap, not a visible line.
            'group relative inline-flex h-9 max-w-[260px] shrink-0 items-center gap-2 rounded-t-lg px-3 text-xs font-semibold whitespace-nowrap transition-colors',
            !['held', 'refund', 'close-shift', 'receipt'].includes(mode)
              ? 'bg-surface-50 dark:bg-surface-900 text-surface-900 dark:text-surface-50 shadow-[inset_0_2px_0_rgb(var(--primary-500))]'
              : 'bg-transparent text-surface-700 dark:text-surface-400 hover:bg-surface-100/60 dark:hover:bg-surface-800/60',
          )}
          title={`POS · ${title}`}
        >
          <span className="grid h-3.5 w-3.5 shrink-0 place-items-center rounded-[4px] bg-primary-500 dark:bg-primary-500 text-[8px] font-black text-on-primary">B</span>
          <span className="truncate">POS · {title}</span>
        </button>
        {/* + New tab — always spawns a new tab, even when the current cart
            is empty. If the current sale has any in-flight work (items or a
            customer attached) we auto-hold to park it; otherwise we mint a
            placeholder held tab from the current empty draft so the cashier
            can fan out as many parallel intake slots as they want. Mockup
            §5.1: parallel sales are tabs; ⌘N opens a new one without
            losing the current. */}
        <button
          type="button"
          onClick={() => {
            if (cartItems.length > 0 || customer) {
              holdMutation.mutate();
            } else {
              // Empty current tab → fire a "blank tab" hold so the now-
              // active slot becomes a held placeholder, then snap home for
              // the new slot. The hold mutation accepts an empty cart_json
              // (server only requires it to be valid JSON) so this is just
              // a stub row in held_carts; the cashier can discard it later
              // if they don't need it.
              spawnBlankTab();
            }
          }}
          className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-t-lg text-surface-500 hover:bg-surface-100/60 dark:hover:bg-surface-800/60 dark:text-surface-400 transition-colors"
          title="New sale (⌘N)"
          aria-label="New sale"
        >
          <Plus className="h-3.5 w-3.5" />
        </button>
      </PosTabStripShell>

      {/* Outer grid: topbar + main on the left column, cart spans the full
          height on the right so the cart panel reads as a continuous side
          column from the very top of the POS area instead of starting below
          the topbar's bottom edge. */}
      <div className="flex-1 grid h-full grid-cols-1 overflow-hidden xl:grid-cols-[minmax(0,1fr)_400px]">
        <div className="flex min-h-0 flex-col overflow-hidden">
      <header className={cn(
        'flex shrink-0 items-center gap-5 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-950 px-5',
        mode === 'gate' ? 'h-16' : 'h-14',
      )}>
        {/* Back chevron — visible on side-quest modes (held / refund /
            close-shift / repair-*) so the cashier always has a one-click
            escape back to the customer gate without having to remember
            the POS-tab affordance. Hidden in gate (already home) and
            tender (Cart/Method esc lives in the action area). */}
        {/* Step-aware back: in repair flow we walk the wizard stack one step
            backwards rather than nuking the draft and snapping to sale. The
            wizard footer's Back button does the same; the topbar chevron
            mirrors it so cashiers never lose work to the wrong button.
            From `repair-category` (first step) Back exits to home. */}
        {(mode === 'held' || mode === 'refund' || mode === 'close-shift' || mode.startsWith('repair')) && (() => {
          const REPAIR_BACK: Record<string, PosMode> = {
            'repair-category': cartItems.length > 0 ? 'sale' : 'gate',
            'repair-device': 'repair-category',
            'repair-issue': 'repair-device',
            'repair-quote': 'repair-issue',
            'repair-deposit': 'repair-quote',
          };
          const back = mode.startsWith('repair')
            ? () => setMode((REPAIR_BACK[mode] ?? (cartItems.length > 0 ? 'sale' : 'gate')) as PosMode)
            : () => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate');
          return (
            <button
              type="button"
              onClick={back}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
              aria-label="Back"
              title="Back (esc)"
            >
              <ChevronLeft className="h-4 w-4" />
            </button>
          );
        })()}
        {/* Visible "Cancel intake" affordance during the repair wizard.
            Resets the repair draft + jumps home. The chevron alone wasn't
            obvious as an "abandon" button — this is. Hidden outside repair
            mode so the topbar stays calm. */}
        {mode.startsWith('repair') && (
          <button
            type="button"
            onClick={() => {
              setRepairDraft(DEFAULT_REPAIR_DRAFT);
              setMode(cartItems.length > 0 || customer ? 'sale' : 'gate');
            }}
            className="hidden sm:inline-flex h-9 shrink-0 items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 text-xs font-semibold text-surface-700 dark:text-surface-200 hover:border-rose-500 hover:text-rose-600 dark:hover:border-rose-500/60"
            title="Cancel repair intake"
          >
            <X className="h-3.5 w-3.5" />
            Cancel intake
          </button>
        )}
        <div className="min-w-[180px]">
          <div className="text-[15px] font-bold text-surface-900 dark:text-surface-100">{title}</div>
          {subtitle && <div className="mt-0.5 text-[11.5px] text-surface-900 dark:text-surface-500">{subtitle}</div>}
        </div>
        <div className={cn(
          'relative min-w-[260px] flex-1',
          // Cap search width on gate so the bar doesn't sprawl across the
          // whole topbar at 1440px+. Shorter feels more focused; the catalog
          // search keeps full flex since it's used for live filtering.
          mode === 'gate' && 'max-w-md',
        )}>
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
              'w-full rounded-[10px] border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 pr-24 font-semibold text-surface-900 dark:text-surface-100 placeholder:text-surface-400 dark:placeholder:text-surface-500 focus:border-primary-500 dark:focus:border-primary-500 focus-visible:outline-none',
              mode === 'gate' ? 'h-12 pl-12 text-[15px]' : 'h-11 pl-11 text-sm',
            )}
            placeholder={mode === 'gate' ? 'Search or scan' : 'Search SKU · scan barcode · or type to filter catalog'}
          />
          <span className="absolute right-3 top-1/2 -translate-y-1/2 rounded border border-surface-200 dark:border-surface-700 bg-surface-100 dark:bg-surface-900 px-2 py-0.5 font-mono text-[10px] text-surface-400">⌘K</span>
        </div>
        {/* Status + action chips. Mockup uses chip-pills here so they read as
            secondary status, not as primary CTAs. Refund + Shift live in a
            ⋯ overflow menu so the topbar stays calm; Recall is always
            visible because it's part of the parallel-sale workflow. */}
        <div className="flex items-center gap-2">
          {!taxState.isLoaded && <Pill tone="warning">tax loading</Pill>}
          {scanFlash && <Pill tone="success">scan detected</Pill>}
          {mode === 'gate' && heldCartCount > 0 && (
            <button
              type="button"
              onClick={() => setMode('held')}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
            >
              <History className="h-3 w-3" /> Recall {heldCartCount}
              <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘R</span>
            </button>
          )}
          {mode === 'sale' && (
            <button
              type="button"
              onClick={() => holdMutation.mutate()}
              disabled={cartItems.length === 0 && !customer}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50"
            >
              <Pause className="h-3 w-3" /> Hold
              <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘H</span>
            </button>
          )}
          {mode.startsWith('tender') && (
            <>
              <span className="inline-flex items-center gap-1 rounded-full bg-[#e8a33d]/15 px-3 py-1 text-[11.5px] font-bold text-[#e8a33d]">
                {mode === 'tender-cash' ? <Banknote className="h-3 w-3" /> : mode === 'tender-card' ? <CreditCard className="h-3 w-3" /> : <Lock className="h-3 w-3" />}
                {mode === 'tender-cash' ? 'Cash · active' : mode === 'tender-card' ? 'Card · active' : 'Tendering'}
              </span>
              <button
                type="button"
                onClick={() => setMode(mode === 'tender-method' ? 'sale' : 'tender-method')}
                className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
              >
                <ChevronLeft className="h-3 w-3" /> {mode === 'tender-method' ? 'Cart' : 'Method'}
                <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">esc</span>
              </button>
            </>
          )}
          {mode === 'close-shift' && (
            <span className="inline-flex items-center gap-1 rounded-full bg-[#e8a33d]/15 px-3 py-1 text-[11.5px] font-bold text-[#e8a33d]">
              <span className="h-2 w-2 rounded-full bg-[#e8a33d] animate-pulse" /> Closing in progress
            </span>
          )}
          {mode !== 'gate' && mode !== 'sale' && !mode.startsWith('tender') && mode !== 'close-shift' && (
            <button
              type="button"
              onClick={startNewSale}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
            >
              <Plus className="h-3 w-3" /> New sale
              <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘N</span>
            </button>
          )}
          {mode !== 'gate' && (
            <div className="relative">
              <details className="group">
                <summary className="inline-flex h-7 w-7 cursor-pointer list-none items-center justify-center rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 [&::-webkit-details-marker]:hidden">
                  <span className="text-[14px] leading-none">⋯</span>
                </summary>
                <div className="absolute right-0 top-full z-20 mt-1 min-w-[180px] rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 p-1 shadow-xl">
                  <button type="button" onClick={() => setMode('refund')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-700">
                    <RotateCcw className="h-3.5 w-3.5" /> Refund
                  </button>
                  <button type="button" onClick={() => setMode('close-shift')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-700">
                    <Lock className="h-3.5 w-3.5" /> Close shift
                  </button>
                  <button type="button" onClick={() => setMode('held')} className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-left text-xs font-semibold text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-700">
                    <History className="h-3.5 w-3.5" /> Recall held (⌘R)
                  </button>
                </div>
              </details>
            </div>
          )}
        </div>
      </header>

      <div className="flex-1 min-h-0 overflow-hidden">
        {mode === 'receipt' && completedSale ? (
          <ReceiptView sale={completedSale} onNext={startNewSale} />
        ) : (
          <main className="h-full overflow-auto bg-surface-100 dark:bg-surface-900 p-0">
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
                  readyTickets={readyPickup.ready}
                  otherTickets={readyPickup.others}
                  readyPickupTotal={readyPickup.total}
                  readyTotal={readyPickup.readyTotal}
                  otherTotal={readyPickup.otherTotal}
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
                  customer={customer}
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
                  onStartRepair={() => setMode('repair-category')}
                  onTender={() => setMode('tender-method')}
                />
              )}

              {mode === 'repair-category' && (
                <RepairCategoryStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  // Cancel = full reset of THIS tab back to the customer
                  // gate. Drops draft customer, cart, repair-draft. Held
                  // tabs stay put; only the active tab snaps home.
                  onCancel={startNewSale}
                  onContinue={() => setMode('repair-device')}
                  onQuick={() => setMode('repair-issue')}
                />
              )}
              {mode === 'repair-device' && (
                <RepairDeviceStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-category')}
                  onContinue={() => setMode('repair-issue')}
                  onGoToStep={(target) => setMode(`repair-${target}` as any)}
                />
              )}
              {mode === 'repair-issue' && (
                <RepairIssueStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-device')}
                  onContinue={() => setMode('repair-quote')}
                  onGoToStep={(target) => setMode(`repair-${target}` as any)}
                />
              )}
              {mode === 'repair-quote' && (
                <RepairQuoteStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-issue')}
                  // Primary path = save the ticket without collecting a
                  // deposit. The deposit step is now opt-in via the ghost
                  // sub-button: cashier explicitly chooses to charge.
                  onContinue={saveRepairToCart}
                  onChargeDeposit={() => setMode('repair-deposit')}
                  onGoToStep={(target) => setMode(`repair-${target}` as any)}
                />
              )}
              {mode === 'repair-deposit' && (
                <RepairDepositStep
                  draft={repairDraft}
                  setDraft={setRepairDraft}
                  onBack={() => setMode('repair-quote')}
                  onSave={saveRepairToCart}
                  onGoToStep={(target) => setMode(`repair-${target}` as any)}
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
                  onRecall={(id) => recallMutation.mutate({ id })}
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
                  refundMethod={refundMethod}
                  setRefundMethod={setRefundMethod}
                  processing={refundMutation.isPending}
                  onProcess={() => refundMutation.mutate()}
                />
              )}
              {mode === 'close-shift' && (
                <CloseShiftView
                  cashCount={cashCount}
                  setCashCount={setCashCount}
                  onPopDrawer={() => popDrawerMutation.mutate()}
                />
              )}
            </main>
        )}
        </div>
        </div>
        <CartColumn
          awake={cartAwake}
          locked={mode.startsWith('tender')}
          customer={customer}
          cartItems={cartItems}
          totals={totals}
          taxRate={taxState.rate}
          paidLegs={paidLegs}
          onSwapCustomer={() => {
            // If we're on a walk-in, the user expects to ATTACH a real
            // customer (not nuke the cart and bounce home). Open the inline
            // create form so they can capture name + phone right where they
            // are. For a real customer attached, fall back to gate-swap so
            // they can pick a different one (the old behavior).
            if (walkInActive || !customer) {
              openInlineCustomerCreate();
              setMode('gate');
            } else {
              setMode('gate');
            }
          }}
          onEditLine={setLineEditing}
          onRemoveLine={removeLineWithUndo}
          onQty={updateProductQty}
          onUpdateLine={updateCartItem}
          onDiscount={() => {
            setDiscountDraft(discount ? String(discount) : '');
            setDiscountReasonDraft(discountReason || 'cashier adjustment');
            setDiscountOpen(true);
          }}
          onTender={() => setMode('tender-method')}
        />
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
                Over 25% — manager PIN required to apply.
              </div>
            )}
          </div>
        </Modal>
      )}
      {pendingDiscount && (
        <PinModal
          title={`Manager PIN — discount ${formatCurrency(pendingDiscount.amount)} (>25% of subtotal)`}
          onSuccess={() => {
            setDiscount(pendingDiscount.amount, pendingDiscount.reason);
            setPendingDiscount(null);
            setDiscountOpen(false);
          }}
          onCancel={() => setPendingDiscount(null)}
        />
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
  readyTickets,
  otherTickets,
  readyPickupTotal,
  readyTotal,
  otherTotal,
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
  readyTickets: PosPickupTicket[];
  otherTickets: PosPickupTicket[];
  readyPickupTotal: number;
  readyTotal: number;
  otherTotal: number;
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
  // "Remaining today" = appointments that still need cashier action today —
  // not just future-time slots. A 10:30 AM booking that the cashier hasn't
  // checked in yet is still "remaining" at 11:30 AM; pretending it's gone
  // hides work. Filter rules:
  //   • drop no-shows (already accounted for)
  //   • drop completed/cancelled/checked-in (already actioned)
  //   • everything else stays, regardless of whether start_time is past
  // Sort by start_time so the soonest-overdue / next-up bubbles to the top.
  const remainingAppointments = appointments
    .filter((appointment) => {
      if (appointment.no_show) return false;
      const status = (appointment.status ?? '').toString().toLowerCase();
      if (status === 'completed' || status === 'cancelled' || status === 'canceled' || status === 'checked_in' || status === 'no_show') return false;
      return true;
    })
    .sort((a, b) => {
      const aMs = new Date(a.start_time).getTime();
      const bMs = new Date(b.start_time).getTime();
      return aMs - bMs;
    });
  // nextAppointment intentionally unused after the timeline rewrite — kept
  // here behind a void cast in case future hero variants need a "next-up"
  // callout. The new timeline shows the top three remaining slots inline.
  void remainingAppointments[0];

  return (
    <div className="flex min-h-full flex-col">
      {/* Combined gate hero block (per user mock):
            Left  — Next appointment summary + total-today line
            Right — primary "Create new customer" CTA + ghost "Walk-in"
          Replaces the old horizontal-scroll appointment strip + centered
          button stack. The next appointment is the highest-signal
          schedule item; remaining bookings live under "View calendar"
          rather than crowding the gate. */}
      {!createCustomerOpen && (
        <section className="px-6 pt-5 pb-5">
          {/* Gate hero — three regions in one band:
                LEFT (2fr)  — actionable appointment timeline. Today's first
                              three remaining appointments laid out as a
                              vertical schedule strip; tappable rows route to
                              each. Past-due rows get a rose accent so the
                              cashier sees what's overdue at a glance.
                CENTER (1fr) — quick stats column (remaining-today, total-today,
                              ready-pickup count). KPI tiles, dark fills.
                RIGHT (auto) — primary "+ New customer" + ghost Walk-in.
              Replaces the previous "ALL CLEAR" mega-headline that consumed
              the whole hero with no signal when the day was busy. */}
          <div className="grid gap-4 lg:grid-cols-[minmax(0,2fr)_minmax(0,1fr)_280px]">
            {/* Appointment timeline */}
            <div className="rounded-2xl border-2 border-[#fdeed0] bg-surface-950 p-5 text-surface-50">
              <div className="mb-3 flex items-center justify-between">
                <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-[#fdeed0]/80">
                  {appointmentsLoading ? 'Loading…' : `Today · ${remainingAppointments.length} remaining`}
                </div>
                <button
                  type="button"
                  onClick={onViewCalendar}
                  className="font-mono text-[10.5px] uppercase tracking-[0.14em] text-[#fdeed0]/70 hover:text-[#fdeed0]"
                >
                  Calendar →
                </button>
              </div>

              {appointmentsLoading ? (
                <div className="space-y-2">
                  <div className="h-12 animate-pulse rounded-lg bg-surface-900" />
                  <div className="h-12 animate-pulse rounded-lg bg-surface-900" />
                </div>
              ) : remainingAppointments.length === 0 ? (
                <div className="flex h-[152px] flex-col items-center justify-center gap-1 text-center">
                  <div className="font-display text-2xl text-[#fdeed0]">All clear</div>
                  <div className="text-sm text-surface-400">No upcoming bookings · walk-ins + pickups ready.</div>
                </div>
              ) : (
                <div className="space-y-1.5">
                  {remainingAppointments.slice(0, 3).map((appointment) => {
                    const startMs = new Date(appointment.start_time).getTime();
                    const isPast = Number.isFinite(startMs) && startMs < nowMs;
                    return (
                      <button
                        key={appointment.id}
                        type="button"
                        onClick={() => onSelectAppointment(appointment)}
                        className={cn(
                          'flex w-full items-center gap-3 rounded-lg border-l-4 px-3 py-2.5 text-left transition hover:bg-surface-900',
                          isPast ? 'border-l-rose-500 bg-rose-500/5' : 'border-l-[#fdeed0] bg-surface-900/50',
                        )}
                      >
                        <div className={cn('w-16 shrink-0 font-mono text-sm', isPast ? 'text-rose-400' : 'text-[#fdeed0]')}>
                          {formatTime(appointment.start_time)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-sm font-semibold">{appointmentCustomerName(appointment)}</div>
                          <div className="truncate text-[11.5px] text-surface-400">
                            {appointmentNote(appointment) || appointmentStatusLabel(appointment, nowMs)}
                          </div>
                        </div>
                        <span className={cn('shrink-0 rounded-full px-2 py-0.5 font-mono text-[10px] uppercase', isPast ? 'bg-rose-500/15 text-rose-300' : 'bg-[#fdeed0]/15 text-[#fdeed0]')}>
                          {appointmentStatusLabel(appointment, nowMs)}
                        </span>
                      </button>
                    );
                  })}
                  {remainingAppointments.length > 3 && (
                    <button
                      type="button"
                      onClick={onViewCalendar}
                      className="flex w-full items-center justify-center gap-1 rounded-lg px-3 py-2 text-xs text-surface-400 hover:bg-surface-900 hover:text-surface-200"
                    >
                      + {remainingAppointments.length - 3} more · view all
                    </button>
                  )}
                </div>
              )}
            </div>

            {/* KPI strip */}
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-1">
              <div className="rounded-xl bg-surface-100 dark:bg-surface-900 p-3 ring-1 ring-inset ring-surface-200 dark:ring-surface-800">
                <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500">Remaining today</div>
                <div className="mt-1 font-display text-3xl text-surface-900 dark:text-surface-50">{remainingAppointments.length}</div>
                <div className="text-[11px] text-surface-500">of {appointments.length} booked</div>
              </div>
              <div className="rounded-xl bg-surface-100 dark:bg-surface-900 p-3 ring-1 ring-inset ring-surface-200 dark:ring-surface-800">
                <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500">Ready for pickup</div>
                <div className="mt-1 font-display text-3xl text-surface-900 dark:text-surface-50">{readyPickupTotal}</div>
                <div className="text-[11px] text-surface-500">awaiting customer</div>
              </div>
              <div className="rounded-xl bg-surface-100 dark:bg-surface-900 p-3 ring-1 ring-inset ring-surface-200 dark:ring-surface-800">
                <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500">Open tickets</div>
                <div className="mt-1 font-display text-3xl text-surface-900 dark:text-surface-50">{readyTotal + otherTotal}</div>
                <div className="text-[11px] text-surface-500">in shop</div>
              </div>
            </div>

            {/* Primary actions */}
            <div className="flex flex-col gap-2">
              <button
                type="button"
                onClick={onNewCustomer}
                className="inline-flex flex-1 items-center justify-center gap-2 rounded-2xl bg-primary-500 dark:bg-primary-500 px-6 py-5 text-[15px] font-bold text-on-primary shadow-lg shadow-black/20 hover:bg-primary-400 dark:hover:bg-primary-600"
              >
                + New customer
              </button>
              <button
                type="button"
                onClick={onWalkIn}
                className="inline-flex items-center justify-center gap-2 rounded-2xl border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 px-6 py-3 text-sm font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
              >
                Walk-in · no profile
              </button>
            </div>
          </div>
        </section>
      )}

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
          <div className="overflow-hidden rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-2xl">
            <div className="border-b border-surface-200 dark:border-surface-700 px-4 py-3 font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">Customer matches</div>
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
                className="flex w-full items-center gap-3 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 p-4 text-left last:border-b-0 hover:bg-surface-100 dark:hover:bg-surface-700"
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
            <div className="flex gap-2 border-t border-surface-200 dark:border-surface-700 p-3">
              <button type="button" onClick={onNewCustomer} className="flex-1 rounded-lg bg-primary-500 dark:bg-primary-500 px-4 py-2 text-sm font-bold text-on-primary">Create customer</button>
              <button type="button" onClick={onWalkIn} className="flex-1 rounded-lg border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-bold text-surface-700 dark:text-surface-200">Walk-in</button>
            </div>
          </div>
        </section>
      ) : null}

      {/* Two-section gate feed:
            1. Ready for pickup — capped at ~22vh (≈ 1/5 of screen) with
               internal scroll, so a busy day doesn't bury everything else.
            2. In progress — the rest of the active queue. Larger surface
               since it's where the day's work actually lives.
          Both share the same row layout so the eye scans cleanly across
          the boundary. */}
      <section className="px-6 pb-6 space-y-3">
        <div className="flex items-center gap-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">
            {readyPickupLoading
              ? 'Current open tickets · loading'
              : `Current open tickets · ${readyPickupTotal}${readyTotal > 0 ? ` · ${readyTotal} ready for pickup` : ''}`}
          </div>
          <div className="h-px flex-1 bg-surface-100 dark:bg-surface-700" />
          <button type="button" onClick={onViewReadyPickup} className="text-xs font-semibold text-primary-700 dark:text-primary-500 underline-offset-4 hover:underline">
            View active tickets
          </button>
        </div>

        {/* Single combined list. Ready-for-pickup rows pinned at the top
            under their own subheader, then In-progress rows under theirs.
            One bordered container so the boundary feels like one list with
            grouped sections rather than two separate cards. */}
        <div className="overflow-hidden rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800">
          {readyPickupLoading && (
            <div className="px-4 py-5 text-sm text-surface-900 dark:text-surface-500">Loading…</div>
          )}
          {!readyPickupLoading && readyTickets.length === 0 && otherTickets.length === 0 && (
            <div className="px-4 py-5 text-sm text-surface-900 dark:text-surface-500">No open tickets right now.</div>
          )}
          {readyTickets.length > 0 && (
            <>
              <div className="bg-surface-50 dark:bg-surface-900 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.14em] text-[#34c47e] border-b border-surface-200 dark:border-surface-700">
                Ready for pickup · {readyTotal}
              </div>
              {readyTickets.map((ticket) => (
                <button
                  key={ticket.id}
                  type="button"
                  onClick={() => onOpenReadyPickup(ticket)}
                  className="grid w-full grid-cols-[120px_70px_180px_minmax(0,1fr)_110px_90px_70px] items-center gap-3 border-b border-surface-200 dark:border-surface-700 px-4 py-2.5 text-left text-sm hover:bg-surface-100 dark:hover:bg-surface-700"
                >
                  <span className="rounded-full bg-[#34c47e]/15 px-2 py-1 text-center font-mono text-[10px] font-bold uppercase text-[#34c47e]">✓ ready</span>
                  <span className="font-mono text-xs text-surface-400">#{ticket.order_id}</span>
                  <span className="truncate font-semibold text-surface-900 dark:text-surface-100">{ticket.customerName}{ticket.customerGroup ? <span className="ml-2 rounded-full bg-burgundy-light/15 px-2 py-0.5 text-[9.5px] font-bold text-[#c5566d]">{ticket.customerGroup}</span> : null}</span>
                  <span className="truncate text-xs text-surface-600 dark:text-surface-300">{ticket.itemSummary}</span>
                  <span className="font-mono text-xs text-surface-900 dark:text-surface-500">{ticket.progressLabel}</span>
                  <span className="text-right font-mono text-xs text-primary-700 dark:text-primary-500">{formatCurrency(ticket.total)}</span>
                  <span className="text-right text-xs font-semibold text-[#4db8c9]">Open →</span>
                </button>
              ))}
            </>
          )}
          {otherTickets.length > 0 && (
            <>
              <div className="bg-surface-50 dark:bg-surface-900 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500 border-b border-surface-200 dark:border-surface-700">
                In progress · {otherTotal}
              </div>
              {otherTickets.map((ticket, idx) => {
                const isLast = idx === otherTickets.length - 1;
                return (
                  <button
                    key={ticket.id}
                    type="button"
                    onClick={() => onOpenReadyPickup(ticket)}
                    className={cn(
                      'grid w-full grid-cols-[120px_70px_180px_minmax(0,1fr)_110px_90px_70px] items-center gap-3 px-4 py-2.5 text-left text-sm hover:bg-surface-100 dark:hover:bg-surface-700',
                      !isLast && 'border-b border-surface-200 dark:border-surface-700',
                    )}
                  >
                    <span className="truncate rounded-full bg-surface-100 dark:bg-surface-700 px-2 py-1 text-center font-mono text-[10px] font-bold uppercase text-surface-600 dark:text-surface-300" title={ticket.statusName}>
                      {ticket.statusName}
                    </span>
                    <span className="font-mono text-xs text-surface-400">#{ticket.order_id}</span>
                    <span className="truncate font-semibold text-surface-900 dark:text-surface-100">{ticket.customerName}{ticket.customerGroup ? <span className="ml-2 rounded-full bg-burgundy-light/15 px-2 py-0.5 text-[9.5px] font-bold text-[#c5566d]">{ticket.customerGroup}</span> : null}</span>
                    <span className="truncate text-xs text-surface-600 dark:text-surface-300">{ticket.itemSummary}</span>
                    <span className="font-mono text-xs text-surface-900 dark:text-surface-500">{ticket.progressLabel}</span>
                    <span className="text-right font-mono text-xs text-primary-700 dark:text-primary-500">{formatCurrency(ticket.total)}</span>
                    <span className="text-right text-xs font-semibold text-[#4db8c9]">Open →</span>
                  </button>
                );
              })}
            </>
          )}
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
  const [activeTab, setActiveTab] = useState<'contact' | 'address' | 'additional'>('contact');
  const updateDraft = (patch: Partial<CreateCustomerDraft>) => {
    setDraft((current) => ({ ...current, ...patch }));
  };
  // Pull customer groups + tax classes for the dropdowns. Both are shop-
  // configured and rarely change; long staleTime is fine. Coerce to array
  // so a server shape drift doesn't crash `.map`.
  const groupsQuery = useQuery({
    queryKey: ['settings', 'customer-groups-pos'],
    queryFn: async () => {
      const res = await settingsApi.getCustomerGroups();
      const payload: any = (res as any)?.data?.data ?? (res as any)?.data;
      return Array.isArray(payload) ? payload : [];
    },
    staleTime: 5 * 60 * 1000,
  });
  const taxClassesQuery = useQuery({
    queryKey: ['settings', 'tax-classes-pos'],
    queryFn: async () => {
      const res = await settingsApi.getTaxClasses();
      const payload: any = (res as any)?.data?.data ?? (res as any)?.data;
      return Array.isArray(payload) ? payload : [];
    },
    staleTime: 5 * 60 * 1000,
  });
  const customerGroups: Array<{ id: number; name: string }> = groupsQuery.data ?? [];
  const taxClasses: Array<{ id: number; name: string; rate: number }> = taxClassesQuery.data ?? [];
  // Suppress the global `:focus-visible` 4px primary halo on these tile
  // inputs — the ring lit up the whole field with a too-loud cream border
  // on focus. Focus state lives on the surrounding tile (label) as a subtle
  // bg shift + 1px primary inset edge instead. Resting state gets a 1px
  // surface ring so each field reads as a clear cell, not a flat block.
  const tileInput =
    'h-10 w-full border-0 bg-transparent p-0 text-[15px] font-semibold text-surface-900 placeholder:text-surface-400 outline-none [&:focus-visible]:!shadow-none [&:focus-visible]:!ring-0 dark:text-surface-50 dark:placeholder:text-surface-600';
  const fieldTile =
    'block bg-white px-4 py-3 ring-1 ring-inset ring-surface-200 transition-shadow focus-within:ring-primary-500 dark:bg-surface-800 dark:ring-surface-600 dark:focus-within:ring-primary-500';

  return (
    <section className="flex w-full flex-1 items-center px-6 py-6">
      <form
        className="mx-auto w-full max-w-4xl overflow-hidden rounded-xl border border-surface-200 bg-surface-200 shadow-lg shadow-black/10 dark:border-surface-700 dark:bg-surface-700 dark:shadow-black/30"
        onSubmit={(event) => {
          event.preventDefault();
          onSubmit();
        }}
      >
        <div className="flex flex-wrap items-center justify-between gap-3 bg-white px-4 py-3 dark:bg-surface-800">
          <div className="flex items-center gap-3">
            <div className="grid h-9 w-9 place-items-center rounded-lg bg-primary-500 text-on-primary dark:bg-primary-500">
              <UserPlus className="h-5 w-5" />
            </div>
            <div className="font-display text-3xl leading-none text-surface-900 dark:text-surface-50">Create customer</div>
          </div>
          <div className="inline-flex rounded-lg border border-surface-200 bg-surface-100 p-1 dark:border-surface-700 dark:bg-surface-900">
            {(['individual', 'business'] as const).map((type) => (
              <button
                key={type}
                type="button"
                onClick={() => updateDraft({ customerType: type })}
                className={cn(
                  'rounded-md px-3 py-1.5 text-xs font-bold capitalize',
                  draft.customerType === type
                    ? 'bg-white text-surface-900 shadow-sm dark:bg-primary-500 dark:text-on-primary'
                    : 'text-surface-500 hover:text-surface-900 dark:hover:text-surface-100',
                )}
              >
                {type}
              </button>
            ))}
          </div>
        </div>

        {/* Tab strip — Contact / Address / Additional Details. Mirrors the
            RepairDesk customer-create UX so a counter clerk can capture the
            full identity profile (loyalty group, tax class, ID, address) in
            one go without context-switching to a separate page. */}
        <div className="flex gap-px bg-surface-200 dark:bg-surface-700">
          {([
            { id: 'contact', label: 'Contact' },
            { id: 'address', label: 'Address' },
            { id: 'additional', label: 'Additional details' },
          ] as const).map((tab) => (
            <button
              key={tab.id}
              type="button"
              onClick={() => setActiveTab(tab.id)}
              className={cn(
                'flex-1 py-2.5 text-xs font-bold uppercase tracking-wider transition-colors',
                activeTab === tab.id
                  ? 'bg-white text-primary-700 dark:bg-surface-800 dark:text-primary-500'
                  : 'bg-surface-50 text-surface-600 hover:bg-white dark:bg-surface-700 dark:text-surface-400 dark:hover:bg-surface-800',
              )}
            >
              {tab.label}
            </button>
          ))}
        </div>

        {activeTab === 'contact' && (
          <>
            <div className="grid gap-px sm:grid-cols-2">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">
                  First name <span className="text-red-500">*</span>
                </span>
                <input
                  autoFocus
                  required
                  value={draft.firstName}
                  onChange={(event) => updateDraft({ firstName: event.target.value })}
                  className={tileInput}
                  placeholder="Jane"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Last name</span>
                <input
                  value={draft.lastName}
                  onChange={(event) => updateDraft({ lastName: event.target.value })}
                  className={tileInput}
                  placeholder="Doe"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Mobile</span>
                <input
                  value={draft.phone}
                  onChange={(event) => updateDraft({ phone: event.target.value })}
                  className={tileInput}
                  inputMode="tel"
                  placeholder="(415) 555-0100"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Email</span>
                <input
                  value={draft.email}
                  onChange={(event) => updateDraft({ email: event.target.value })}
                  className={tileInput}
                  inputMode="email"
                  placeholder="jane@example.com"
                />
              </label>
            </div>

            <div className="grid gap-px sm:grid-cols-2">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Customer group</span>
                <select
                  value={draft.customerGroupId ?? ''}
                  onChange={(event) => updateDraft({ customerGroupId: event.target.value ? Number(event.target.value) : null })}
                  className={tileInput}
                >
                  <option value="">— Select —</option>
                  {customerGroups.map((g) => (
                    <option key={g.id} value={g.id}>{g.name}</option>
                  ))}
                </select>
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Tax class</span>
                <select
                  value={draft.taxClassId ?? ''}
                  onChange={(event) => updateDraft({ taxClassId: event.target.value ? Number(event.target.value) : null })}
                  className={tileInput}
                >
                  <option value="">— Default —</option>
                  {taxClasses.map((tc) => (
                    <option key={tc.id} value={tc.id}>{tc.name} ({tc.rate}%)</option>
                  ))}
                </select>
              </label>
            </div>

            <div className="grid gap-px sm:grid-cols-2">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">How did you hear about us?</span>
                <input
                  value={draft.referredBy}
                  onChange={(event) => updateDraft({ referredBy: event.target.value })}
                  className={tileInput}
                  placeholder="Google, friend, walk-by…"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">
                  {draft.customerType === 'business' ? 'Organization *' : 'Organization'}
                </span>
                <input
                  value={draft.organization}
                  onChange={(event) => updateDraft({ organization: event.target.value })}
                  className={tileInput}
                  required={draft.customerType === 'business'}
                  placeholder={draft.customerType === 'business' ? 'Acme Inc.' : 'optional'}
                />
              </label>
            </div>
          </>
        )}

        {activeTab === 'address' && (
          <>
            <div className="grid gap-px sm:grid-cols-2">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Street address</span>
                <input
                  value={draft.address1}
                  onChange={(event) => updateDraft({ address1: event.target.value })}
                  className={tileInput}
                  placeholder="123 Main St"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">House / apt / floor</span>
                <input
                  value={draft.address2}
                  onChange={(event) => updateDraft({ address2: event.target.value })}
                  className={tileInput}
                  placeholder="Apt 4B"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Postcode</span>
                <input
                  value={draft.postcode}
                  onChange={(event) => updateDraft({ postcode: event.target.value })}
                  className={tileInput}
                  placeholder="94110"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">City</span>
                <input
                  value={draft.city}
                  onChange={(event) => updateDraft({ city: event.target.value })}
                  className={tileInput}
                  placeholder="San Francisco"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">State / region</span>
                <input
                  value={draft.state}
                  onChange={(event) => updateDraft({ state: event.target.value })}
                  className={tileInput}
                  placeholder="CA"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Country</span>
                <input
                  value={draft.country}
                  onChange={(event) => updateDraft({ country: event.target.value })}
                  className={tileInput}
                  placeholder="USA"
                />
              </label>
            </div>
            <div className="grid gap-px">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Contact person</span>
                <input
                  value={draft.contactPerson}
                  onChange={(event) => updateDraft({ contactPerson: event.target.value })}
                  className={tileInput}
                  placeholder="optional · spouse / assistant / colleague"
                />
              </label>
            </div>
          </>
        )}

        {activeTab === 'additional' && (
          <>
            <div className="grid gap-px sm:grid-cols-2">
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Tax / VAT number</span>
                <input
                  value={draft.taxNumber}
                  onChange={(event) => updateDraft({ taxNumber: event.target.value })}
                  className={tileInput}
                  placeholder="optional"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">ID type</span>
                <select
                  value={draft.idType}
                  onChange={(event) => updateDraft({ idType: event.target.value })}
                  className={tileInput}
                >
                  <option value="">— None —</option>
                  <option value="drivers_license">Driver's license</option>
                  <option value="passport">Passport</option>
                  <option value="state_id">State ID</option>
                  <option value="other">Other</option>
                </select>
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">ID number</span>
                <input
                  value={draft.idNumber}
                  onChange={(event) => updateDraft({ idNumber: event.target.value })}
                  className={tileInput}
                  placeholder="optional"
                />
              </label>
              <label className={fieldTile}>
                <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Title</span>
                <input
                  value={draft.title}
                  onChange={(event) => updateDraft({ title: event.target.value })}
                  className={tileInput}
                  placeholder="Mr. / Ms. / Dr."
                />
              </label>
            </div>
            <label className={cn(fieldTile, 'block')}>
              <span className="block font-mono text-[10px] uppercase tracking-[0.12em] text-surface-500">Private note</span>
              <textarea
                value={draft.comments}
                onChange={(event) => updateDraft({ comments: event.target.value })}
                rows={3}
                className={cn(tileInput, 'h-auto resize-y py-1')}
                placeholder="staff-only · prints nowhere customer-facing"
              />
            </label>
          </>
        )}

        <div className="flex flex-wrap items-center justify-between gap-3 bg-white px-4 py-3 dark:bg-surface-800">
          <div className="flex flex-wrap gap-2">
            <label className="inline-flex h-10 items-center gap-2 rounded-lg border border-surface-200 px-3 text-sm font-semibold text-surface-800 dark:border-surface-700 dark:text-surface-100">
              <input
                type="checkbox"
                checked={draft.smsOptIn}
                onChange={(event) => updateDraft({ smsOptIn: event.target.checked })}
                className="h-4 w-4 accent-primary-500"
              />
              SMS updates
            </label>
            <label className="inline-flex h-10 items-center gap-2 rounded-lg border border-surface-200 px-3 text-sm font-semibold text-surface-800 dark:border-surface-700 dark:text-surface-100">
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
  customer,
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
  customer: CustomerResult | null;
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
      <div className="flex items-center gap-2 overflow-x-auto border-b border-surface-200 bg-white px-5 py-3 dark:border-surface-800 dark:bg-surface-950">
        {filterOptions.map((filter) => (
          <button
            key={filter}
            type="button"
            onClick={() => setActiveFilter(filter)}
            className={cn(
              'shrink-0 rounded-full px-3 py-1.5 text-xs font-semibold',
              activeFilter === filter
                ? 'bg-primary-500 text-on-primary dark:bg-primary-500'
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
            className="inline-flex items-center gap-1.5 rounded-full border border-dashed border-surface-300 bg-transparent px-3 py-1.5 text-xs font-semibold text-surface-700 hover:border-primary-500 hover:text-primary-700 dark:border-surface-700 dark:text-surface-200 dark:hover:border-primary-500/40 dark:hover:text-[#fdeed0]"
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
          {/* Charge button lives only in the cart footer per mockup pattern.
              Filter row stays focused on category navigation; cart footer
              owns the primary tender CTA. */}
        </div>
      </div>

      <div className="grid gap-3 p-5 sm:grid-cols-2 xl:grid-cols-4">
        {/* Smart-tile (Frame 09): customer-aware loyalty/upsell hint. Only
            renders when an attached customer is in a discount group — the
            "Sarah is 45 pts from PLATINUM" hint pattern. Walk-in / no-group
            sales skip it so the catalog grid reclaims the col-span. Clicking
            jumps to the custom-item modal so the cashier can attach the
            qualifying SKU on the fly. */}
        {customer?.group_name && (
          <button type="button" className="rounded-lg border border-cyan-400/40 bg-cyan-500/10 p-4 text-left xl:col-span-2" onClick={onCustomItem}>
            <Star className="h-5 w-5 text-cyan-700 dark:text-[#4DB8C9]" />
            <div className="mt-3 font-semibold">{getCustomerName(customer).split(' ')[0]} is {customer.group_name} · keep the streak</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Add a qualifying accessory before tender to lock in the next-tier bonus.</div>
          </button>
        )}
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
              {inCart && (
                <span className="absolute right-2 top-2 inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 font-mono text-[10px] font-bold uppercase text-emerald-700 dark:bg-[#34c47e]/15 dark:text-[#34c47e]">
                  ✓ IN CART
                </span>
              )}
              <Package className="h-6 w-6 text-surface-400" />
              <div className="mt-2 line-clamp-2 min-h-10 text-[13px] font-semibold leading-snug" title={product.sku ? `${product.name} · ${product.sku}` : product.name}>{product.name}</div>
              <div className="mt-auto flex items-baseline justify-between pt-2">
                <span className="font-display text-[22px] text-primary-700 dark:text-primary-500">{formatCurrency(Number(product.retail_price ?? product.price ?? 0))}</span>
                <span className={cn(
                  'font-mono text-[10.5px] uppercase tracking-wider',
                  out ? 'text-red-500' : Number(product.in_stock ?? 0) <= 2 && product.item_type !== 'service' ? 'text-[#e8a33d]' : 'text-emerald-600 dark:text-[#34c47e]',
                )}>
                  {stockLabel(product)}
                </span>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}

/**
 * Inline-editable price chip for a cart row. Click the formatted price →
 * input swap → Enter / blur to save, Esc to cancel. Updates the right
 * field per item type:
 *   • repair  → laborPrice (cents-int parsed from dollars float)
 *   • product → unitPrice
 *   • misc    → unitPrice
 * lineAmount() pulls from these so the formatted display stays in sync.
 */
function CartLinePrice({ item, locked, onUpdate }: {
  item: CartItem;
  locked: boolean;
  onUpdate: (id: string, updates: Partial<CartItem>) => void;
}) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');
  const inputRef = useRef<HTMLInputElement | null>(null);

  // Source-of-truth value for THIS line. Repairs render `lineAmount` which
  // = labor − discount + parts; clicking the price puts the laborPrice
  // alone into the input so editing it doesn't fight the parts math.
  const editableValue = item.type === 'repair' ? item.laborPrice : item.unitPrice;

  useEffect(() => {
    if (editing) {
      setDraft(String(editableValue ?? 0));
      // Defer focus to next tick so the input is mounted before select().
      setTimeout(() => {
        inputRef.current?.focus();
        inputRef.current?.select();
      }, 0);
    }
  }, [editing, editableValue]);

  const commit = () => {
    const next = parseMoney(draft);
    if (Number.isFinite(next) && next >= 0) {
      if (item.type === 'repair') onUpdate(item.id, { laborPrice: next } as Partial<CartItem>);
      else onUpdate(item.id, { unitPrice: next } as Partial<CartItem>);
    }
    setEditing(false);
  };

  if (editing) {
    return (
      <input
        ref={inputRef}
        type="text"
        inputMode="decimal"
        value={draft}
        onChange={(e) => setDraft(e.target.value)}
        onBlur={commit}
        onKeyDown={(e) => {
          if (e.key === 'Enter') { e.preventDefault(); commit(); }
          else if (e.key === 'Escape') { e.preventDefault(); setEditing(false); }
        }}
        className="w-24 rounded border border-primary-500 bg-white dark:bg-surface-900 px-2 py-0.5 text-right font-mono text-[14px] font-semibold text-surface-900 dark:text-surface-100 outline-none"
        aria-label="Edit price"
      />
    );
  }

  return (
    <button
      type="button"
      disabled={locked}
      onClick={() => setEditing(true)}
      title="Click to edit price"
      className="rounded px-1 -mx-1 font-mono text-[15px] font-semibold text-surface-900 dark:text-surface-100 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:cursor-not-allowed disabled:hover:bg-transparent"
    >
      {formatCurrency(lineAmount(item))}
    </button>
  );
}

function CartColumn({
  awake,
  locked,
  customer,
  cartItems,
  totals,
  taxRate,
  paidLegs,
  onSwapCustomer,
  onEditLine,
  onRemoveLine,
  onQty,
  onUpdateLine,
  onDiscount,
  onTender,
}: {
  awake: boolean;
  locked: boolean;
  customer: CustomerResult | null;
  cartItems: CartItem[];
  totals: ReturnType<typeof computePosTotals>;
  taxRate: number;
  paidLegs: PaymentLeg[];
  onSwapCustomer: () => void;
  onEditLine: (item: CartItem) => void;
  onRemoveLine: (id: string) => void;
  onQty: (id: string, delta: number) => void;
  onUpdateLine: (id: string, updates: Partial<CartItem>) => void;
  onDiscount: () => void;
  onTender: () => void;
}) {
  const paid = paidLegs.reduce((sum, leg) => sum + leg.amount, 0);
  // Mockup format: "Subtotal · 3 lines" (count) + "Tax (8.875%)" (rate %).
  // taxRate comes in as a fraction (e.g. 0.08875); render with up to 3
  // decimals so "8.875%" not "8.9%".
  const lineCount = cartItems.reduce((sum, item) => sum + (item.type === 'product' || item.type === 'misc' ? item.quantity : 1), 0);
  const taxPct = (taxRate * 100).toFixed(3).replace(/\.?0+$/, '');
  return (
    <aside className={cn('flex min-h-0 flex-col border-l border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800', locked && 'opacity-90')}>
      {/* Mockup cart toolbar: just `‹ 🛒 CART`. Status pills (locked /
          asleep) clutter the header on every refresh; the locked + asleep
          states already read from the dimmed body, sleeping illustration,
          and disabled Charge button. The locked pill is kept because
          it's a critical "hands off — tender in flight" cue. */}
      <div className="flex h-[44px] items-center gap-2 border-b border-surface-200 dark:border-surface-700 px-4 font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-surface-600 dark:text-surface-300">
        <ChevronLeft className="h-4 w-4 text-surface-900 dark:text-surface-500" />
        <ShoppingCart className="h-4 w-4" />
        Cart
        {locked && <span className="ml-auto inline-flex items-center gap-1 rounded-full bg-[#e8a33d]/15 px-2 py-0.5 text-[10px] font-semibold text-[#e8a33d]"><Lock className="h-3 w-3" /> locked</span>}
      </div>
      {!awake && (
        <div className="flex flex-1 flex-col items-center justify-center p-8 text-center opacity-60">
          <div className="grid h-14 w-14 place-items-center rounded-2xl bg-surface-100 dark:bg-surface-900">
            <ShoppingCart className="h-7 w-7 text-surface-900 dark:text-surface-500" />
          </div>
          <div className="mt-4 font-display text-2xl text-surface-900 dark:text-surface-100">Cart is asleep</div>
        </div>
      )}
      {awake && (
        <>
          <button type="button" onClick={onSwapCustomer} className="flex items-start gap-3 border-b border-surface-200 dark:border-surface-700 p-4 text-left hover:bg-surface-100 dark:hover:bg-surface-900">
            <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-[#4db8c9] font-bold text-[#002d35]">
              {initials(getCustomerName(customer))}
            </div>
            <div className="min-w-0 flex-1">
              <div className="flex items-center gap-2">
                <span className="truncate font-semibold text-surface-900 dark:text-surface-50">{getCustomerName(customer)}</span>
                {customer?.group_name && <Pill tone="vip">{customer.group_name}</Pill>}
              </div>
              <div className="truncate text-[12.5px] text-surface-900 dark:text-surface-500">{customer?.phone || customer?.mobile || customer?.email || 'No contact saved'}</div>
              {(customer?.past_tickets_count != null || customer?.warranty_summary) && (
                <div className="truncate text-[11.5px] text-surface-500 dark:text-surface-400">
                  {[
                    customer?.past_tickets_count != null ? `${customer.past_tickets_count} past tickets` : null,
                    customer?.warranty_summary || null,
                  ].filter(Boolean).join(' · ')}
                </div>
              )}
            </div>
            <span className="text-surface-400 dark:text-surface-500" aria-label="Swap customer">⋯</span>
          </button>
          <div className="min-h-0 flex-1 overflow-auto p-3">
            {cartItems.length === 0 ? (
              <div className="rounded-lg border border-dashed border-surface-300 dark:border-surface-700 p-6 text-center text-sm text-surface-900 dark:text-surface-500">
                Scan or add an item to start the cart.
              </div>
            ) : (
              <div className="space-y-2">
                {cartItems.map((item) => (
                  <div key={item.id} className={cn('group relative rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 p-3', item.type === 'repair' && 'border-l-4 border-l-primary-500 dark:border-l-[#fdeed0]')}>
                    <div className="flex gap-3">
                      <div className="mt-0.5 grid h-7 w-7 shrink-0 place-items-center rounded-lg bg-surface-100 dark:bg-surface-800 text-surface-700 dark:text-surface-300">
                        {item.type === 'repair' ? <Wrench className="h-3.5 w-3.5" /> : <Package className="h-3.5 w-3.5" />}
                      </div>
                      <div className="min-w-0 flex-1">
                        <div className="line-clamp-2 text-[13px] font-semibold text-surface-900 dark:text-surface-100">{lineTitle(item)}</div>
                        <div className="mt-0.5 truncate text-[11.5px] text-surface-500 dark:text-surface-500">{lineSubtitle(item)}</div>
                        {(item.type === 'product' || item.type === 'misc') && (
                          <div className="mt-1.5 flex items-center gap-1.5">
                            <button type="button" onClick={() => onQty(item.id, -1)} disabled={locked} className="rounded border border-surface-200 dark:border-surface-700 p-0.5 text-surface-700 dark:text-surface-300" aria-label="Decrease quantity"><Minus className="h-3 w-3" /></button>
                            <span className="w-6 text-center font-mono text-[11.5px]">{item.quantity}</span>
                            <button type="button" onClick={() => onQty(item.id, 1)} disabled={locked} className="rounded border border-surface-200 dark:border-surface-700 p-0.5 text-surface-700 dark:text-surface-300" aria-label="Increase quantity"><Plus className="h-3 w-3" /></button>
                          </div>
                        )}
                      </div>
                      <div className="flex flex-col items-end gap-1.5">
                        <CartLinePrice item={item} locked={locked} onUpdate={onUpdateLine} />
                        <div className="flex gap-0.5 opacity-0 transition-opacity group-hover:opacity-100 focus-within:opacity-100">
                          <button type="button" onClick={() => onEditLine(item)} disabled={locked} className="rounded p-1 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-700" aria-label="Edit line"><Edit3 className="h-3 w-3" /></button>
                          <button type="button" onClick={() => onRemoveLine(item.id)} disabled={locked} className="rounded p-1 text-red-500 hover:bg-red-50 dark:hover:bg-red-950/40" aria-label="Remove line"><Trash2 className="h-3 w-3" /></button>
                        </div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
          {/* Coupon row pinned above totals (mockup pattern). When a discount
              is applied, render as state ("REASON · APPLIED") not a prompt. */}
          <button type="button" onClick={onDiscount} disabled={locked} className={cn(
            'flex w-full items-center gap-2 border-y px-4 py-2.5 text-left text-sm font-semibold',
            totals.discountAmount > 0
              ? 'border-emerald-500/30 bg-emerald-500/10 text-emerald-700 dark:bg-[#34c47e]/10 dark:text-[#34c47e]'
              : 'border-surface-200 dark:border-surface-700 bg-surface-50/60 dark:bg-surface-900 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-700',
          )}>
            <Tag className="h-4 w-4" />
            {totals.discountAmount > 0 ? (
              <>
                <span className="truncate font-mono uppercase tracking-wider">{(customer?.group_name || 'discount').toString().toUpperCase()}</span>
                <span className="ml-auto rounded-full bg-emerald-500/20 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider">applied</span>
              </>
            ) : (
              'Coupon or discount'
            )}
          </button>
          <div className="border-t border-surface-200 dark:border-surface-700 p-4">
            <div className="space-y-1.5 font-mono text-[12.5px]">
              <div className="flex justify-between">
                <span className="text-surface-900 dark:text-surface-500">Subtotal{lineCount > 0 ? ` · ${lineCount} line${lineCount === 1 ? '' : 's'}` : ''}</span>
                <span>{formatCurrency(totals.subtotal)}</span>
              </div>
              {totals.discountAmount > 0 && (
                <div className="flex justify-between text-emerald-700 dark:text-[#34C47E]">
                  <span>Discount</span>
                  <span>-{formatCurrency(totals.discountAmount)}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-surface-900 dark:text-surface-500">Tax{taxPct ? ` (${taxPct}%)` : ''}</span>
                <span>{formatCurrency(totals.tax)}</span>
              </div>
              {paid > 0 && (
                <div className="flex justify-between text-cyan-700 dark:text-[#4DB8C9]">
                  <span>Paid</span>
                  <span>-{formatCurrency(paid)}</span>
                </div>
              )}
              <div className="mt-2 flex items-end justify-between border-t border-surface-200 dark:border-surface-700 pt-3">
                <span className="font-sans text-[10.5px] uppercase tracking-[0.12em] text-surface-500">Due now</span>
                <span className="font-display text-4xl text-primary-700 dark:text-primary-500 tabular-nums">{formatCurrency(Math.max(0, totals.total - paid))}</span>
              </div>
            </div>
            {/* Footer action grid: Discount + Note share a row, Charge spans
                full width. Mirrors mockup `cart-foot` exactly. */}
            <div className="mt-4 grid grid-cols-2 gap-2">
              <button type="button" onClick={onDiscount} disabled={locked} className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-xs font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50">
                <Tag className="h-3.5 w-3.5" /> Discount
                <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘D</span>
              </button>
              <button type="button" disabled={locked} className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-xs font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50">
                <FileText className="h-3.5 w-3.5" /> Note
              </button>
              <button type="button" onClick={onTender} disabled={locked || cartItems.length === 0} className={cn(primaryButton, 'col-span-2 w-full py-3 text-base')}>
                <CreditCard className="h-4 w-4" />
                Charge {formatCurrency(Math.max(0, totals.total - paid))}
                <span className="ml-2 rounded border border-black/15 bg-black/5 px-1.5 font-mono text-[10px]">⌘↵</span>
              </button>
            </div>
          </div>
        </>
      )}
    </aside>
  );
}

/**
 * Step 1 — Category. Big-tile grid; pick a category and route to the
 * Device step. Quick check-in skips device entirely.
 *
 * Wrapper has `pt-4` so the dot-stepper doesn't kiss the topbar at the top
 * of the page (the topbar is sticky, the step content scrolls inside it).
 */
function RepairCategoryStep({ draft, setDraft, onCancel, onContinue, onQuick }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onCancel: () => void;
  onContinue: () => void;
  onQuick: () => void;
}) {
  return (
    <div className="mx-auto flex h-full max-w-5xl flex-col gap-3 px-4 pt-3 pb-3">
      {/* Category is the first step — no past steps to jump to. Stepper still
          renders so the user sees where they are in the 5-step flow. */}
      <Stepper step="category" />
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-surface-500">Pick a category</div>
          <div className="mt-0.5 text-xs text-surface-600 dark:text-surface-400">
            Or hit <span className="font-mono">Quick check-in</span> to log without a specific device.
          </div>
        </div>
        {/* Category grid — design-system tile pattern: thicker `ring-1
            ring-inset` border, surface-800 fill against the surface-900
            page background so each tile reads as a distinct card.
            Active: primary ring + tinted fill. Hover: brighter ring +
            lift. Quick check-in keeps a dashed primary outline so it
            reads as "the alternate path." Larger px/py + 4xl emoji +
            base font label so the targets are obvious touch surfaces. */}
        <div className="grid min-h-0 flex-1 grid-cols-2 gap-3 sm:grid-cols-3">
          {CATEGORY_TILES.map((tile) => {
            const active = draft.deviceType === tile.value;
            const isQuick = tile.value === 'quick';
            return (
              <button
                key={tile.value}
                type="button"
                onClick={() => {
                  setDraft((prev) => ({ ...prev, deviceType: tile.value, deviceName: '' }));
                  if (isQuick) onQuick();
                  else onContinue();
                }}
                className={cn(
                  'group flex min-h-[120px] flex-col items-center justify-center gap-2 rounded-xl bg-white px-4 py-6 text-center shadow-sm transition hover:-translate-y-0.5 hover:shadow-md dark:bg-surface-800',
                  // Inset ring instead of border — keeps tile dimensions
                  // stable on hover/active swaps. Two units thick on
                  // active / hover so the accent reads at any zoom.
                  active
                    ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 dark:bg-primary-500/15'
                    : isQuick
                      ? 'border-2 border-dashed border-primary-500/60 hover:border-primary-500'
                      : 'ring-1 ring-inset ring-surface-300 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:hover:ring-primary-500/80',
                )}
              >
                <div className="text-4xl leading-none">{tile.emoji}</div>
                <div className="text-base font-semibold text-surface-900 dark:text-surface-50">{tile.label}</div>
                {isQuick && (
                  <div className="text-[10.5px] font-mono uppercase tracking-[0.14em] text-primary-700 dark:text-primary-400">skip device</div>
                )}
              </button>
            );
          })}
        </div>
      </div>
      <WizardFooter onBack={onCancel} backLabel="Cancel" onContinue={onContinue} continueLabel="Continue" />
    </div>
  );
}

/**
 * Step 2 — Device. Per-category device picker:
 *   • Manufacturer chips (one-tap filter)
 *   • Search field (debounced, hits /catalog/devices)
 *   • Popular grid (server-flagged)
 *   • Free-text fallback for devices not in the catalog
 *
 * IMEI / serial input + scan hint live at the bottom — that's where the
 * scan gun's keyboard input naturally lands when focus isn't elsewhere.
 */
function RepairDeviceStep({ draft, setDraft, onBack, onContinue, onGoToStep }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onContinue: () => void;
  onGoToStep?: (target: RepairStepKey) => void;
}) {
  const category = draft.deviceType || 'phone';
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const [mfgFilter, setMfgFilter] = useState<string>('');
  const debounceRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedQuery(query), 300);
    return () => clearTimeout(debounceRef.current);
  }, [query]);

  const popularQuery = useQuery({
    queryKey: ['pos-popular-devices', category],
    queryFn: () => api.get<{ data: any[] }>(`/catalog/devices`, { params: { popular: '1', category, limit: 12 } }),
    staleTime: 60_000,
  });
  const popularDevices: any[] = (popularQuery.data?.data as any)?.data ?? popularQuery.data?.data ?? [];

  const effectiveQuery = mfgFilter || debouncedQuery;
  const searchEnabled = effectiveQuery.length >= 2;
  const isMfgFilter = !!mfgFilter;
  const searchQuery = useQuery({
    queryKey: ['pos-device-search', effectiveQuery, category, isMfgFilter],
    queryFn: () => api.get<{ data: any[] }>(`/catalog/devices`, { params: { q: effectiveQuery, category, limit: isMfgFilter ? 100 : 20 } }),
    enabled: searchEnabled,
    staleTime: 30_000,
  });
  const searchResults: any[] = (searchQuery.data?.data as any)?.data ?? searchQuery.data?.data ?? [];

  const shortcuts = MANUFACTURER_SHORTCUTS[category] ?? [];
  const showSearch = searchEnabled;
  const categoryLabel = CATEGORY_TILES.find((t) => t.value === category)?.label ?? 'Device';

  // pick() captures BOTH the human-readable device name AND the catalog
  // device_model_id when available. The Issue step needs device_model_id to
  // pull device-scoped repair prices from `/repair-pricing/matrix`.
  const pick = (deviceName: string, deviceModelId: number | null = null) => {
    setDraft((prev) => ({ ...prev, deviceName, deviceModelId }));
  };

  return (
    <div className="mx-auto flex h-full max-w-5xl flex-col gap-3 px-4 pt-3 pb-3">
      <Stepper step="device" onGoToStep={onGoToStep} />
      <Section className="flex min-h-0 flex-1 flex-col p-4">
        <div className="mb-3">
          <div className="font-display text-xl">{categoryLabel}</div>
          <div className="mt-0.5 text-xs text-surface-900 dark:text-surface-500">Pick a brand to filter, type to search, or scan IMEI.</div>
        </div>

        {shortcuts.length > 0 && (
          // Bigger manufacturer tiles. Old chips were `text-xs px-3 py-1` — too
          // small to read or tap. Now design-system inset-ring pattern: even
          // grid, bold label, ring-2 active state, ring-1 resting. Matches
          // Category step look so the brand-pick reads as the same caliber of
          // decision (it is).
          <div className="mb-3 grid grid-cols-3 gap-2 sm:grid-cols-6">
            {shortcuts.map((mfg) => {
              const active = mfgFilter === mfg;
              return (
                <button
                  key={mfg}
                  type="button"
                  onClick={() => {
                    if (active) setMfgFilter('');
                    else { setMfgFilter(mfg); setQuery(''); }
                  }}
                  className={cn(
                    'flex min-h-[48px] items-center justify-center rounded-xl bg-white px-4 py-2.5 text-sm font-semibold transition hover:-translate-y-0.5 hover:shadow dark:bg-surface-800',
                    active
                      ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 text-primary-700 dark:text-primary-200'
                      : 'ring-1 ring-inset ring-surface-300 text-surface-900 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:text-surface-100 dark:hover:ring-primary-500/80',
                  )}
                >
                  {mfg}
                </button>
              );
            })}
          </div>
        )}

        <div className="relative mb-3">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
          <input
            type="text"
            value={query}
            onChange={(e) => { setQuery(e.target.value); if (e.target.value) setMfgFilter(''); }}
            placeholder={DEVICE_PLACEHOLDER[category] ?? 'Search models'}
            className={cn(inputClass, 'pl-9')}
            autoFocus
          />
        </div>

        {/* Models scroll inside this flex-1 / min-h-0 wrapper so the entire
            step fits the viewport — header, manufacturer chips, search, and
            footer all stay visible while the candidate list takes whatever
            vertical space is left. */}
        <div className="min-h-0 flex-1 overflow-y-auto">
          {showSearch && (
            <div className="rounded-lg border border-surface-200 dark:border-surface-700">
              {searchResults.length === 0 && !searchQuery.isFetching ? (
                /* No catalog match → "Add as new device" CTA that just
                   picks the typed query directly. Keeps intake one-step:
                   what the cashier typed becomes the model name on the
                   ticket, no separate Free-text input + Use button to
                   re-type the same string. */
                <div className="flex flex-col gap-3 p-4">
                  <div className="text-sm text-surface-500">No catalog match for "{effectiveQuery}".</div>
                  <button
                    type="button"
                    onClick={() => { pick(effectiveQuery, null); setQuery(''); setMfgFilter(''); }}
                    className={cn(primaryButton, 'self-start')}
                  >
                    + Add "{effectiveQuery}" as new device
                  </button>
                </div>
              ) : (
                searchResults.map((d) => {
                  const fullName = `${d.manufacturer_name ?? ''} ${d.name ?? ''}`.trim();
                  const active = draft.deviceName === fullName && draft.deviceModelId === d.id;
                  return (
                    <button
                      key={d.id}
                      type="button"
                      onClick={() => pick(fullName, d.id)}
                      className={cn(
                        // Stronger row affordance: bigger touch (py-3),
                        // accent border on the LEFT when selected, brighter
                        // hover background, animated chevron. The old row
                        // looked like a separator — now it reads as a button.
                        'group relative flex w-full cursor-pointer items-center gap-3 border-b-2 border-transparent px-4 py-3 text-left text-sm transition-all last:border-0',
                        active
                          ? 'border-l-4 border-l-primary-500 bg-primary-500/10 dark:bg-primary-500/15'
                          : 'border-b-surface-100 hover:bg-primary-500/5 hover:border-l-4 hover:border-l-primary-400 dark:border-b-surface-800 dark:hover:bg-primary-500/10',
                      )}
                    >
                      <span className="font-medium text-surface-900 dark:text-surface-100">{fullName}</span>
                      {d.release_year && <span className="text-xs text-surface-500">· {d.release_year}</span>}
                      <ChevronRight className="ml-auto h-4 w-4 text-surface-400 transition-transform group-hover:translate-x-0.5 group-hover:text-primary-500" />
                    </button>
                  );
                })
              )}
            </div>
          )}

          {!showSearch && popularDevices.length > 0 && (
            <div>
              <div className="mb-2 font-mono text-[10.5px] uppercase tracking-[0.12em] text-surface-500">Popular</div>
              <div className="flex flex-wrap gap-2">
                {popularDevices.map((d) => {
                  const fullName = `${d.manufacturer_name ?? ''} ${d.name ?? ''}`.trim();
                  const active = draft.deviceName === fullName && draft.deviceModelId === d.id;
                  return (
                    <button
                      key={d.id}
                      type="button"
                      onClick={() => pick(fullName, d.id)}
                      className={cn(
                        'rounded-full px-4 py-2 text-sm font-semibold transition',
                        active
                          ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 text-primary-700 dark:text-primary-200'
                          : 'ring-1 ring-inset ring-surface-300 text-surface-900 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:text-surface-100',
                      )}
                    >
                      {fullName}
                    </button>
                  );
                })}
              </div>
            </div>
          )}

          {!showSearch && popularDevices.length === 0 && !popularQuery.isLoading && (
            <p className="text-sm text-surface-500">Type to search or use the manufacturer chips above.</p>
          )}
        </div>

        {/* Pinned footer: IMEI input only. Model is captured via the
            search → pick / Add-as-new flow above; no separate free-text
            input here means no double-entry path. */}
        <div className="mt-3">
          <input
            className={inputClass}
            value={draft.imei}
            onChange={(event) => setDraft((prev) => ({ ...prev, imei: event.target.value }))}
            placeholder="Scan IMEI / serial"
            aria-label="IMEI or serial"
          />
        </div>
      </Section>
      <WizardFooter onBack={onBack} backLabel="Back" onContinue={onContinue} />
    </div>
  );
}

// Server `repair_services.category` slug → human label + emoji used to group
// problem tiles. Unknown categories fall through to "Other" so the screen
// never collapses on a missing key.
const PROBLEM_GROUP_META: Record<string, { label: string; emoji: string }> = {
  screen:       { label: 'Screen',         emoji: '📱' },
  battery:      { label: 'Battery',        emoji: '🔋' },
  charging:     { label: 'Charging',       emoji: '🔌' },
  camera:       { label: 'Camera',         emoji: '📸' },
  audio:        { label: 'Audio',          emoji: '🔊' },
  buttons:      { label: 'Buttons',        emoji: '🎛️' },
  water:        { label: 'Water damage',   emoji: '💧' },
  software:     { label: 'Software',       emoji: '💻' },
  diagnostic:   { label: 'Diagnostic',     emoji: '🔍' },
  data:         { label: 'Data recovery',  emoji: '💾' },
  motherboard:  { label: 'Board',          emoji: '🧠' },
  back_glass:   { label: 'Back glass',     emoji: '🪞' },
  other:        { label: 'Other',          emoji: '🛠️' },
};
const PROBLEM_GROUP_FALLBACK = { label: 'Other', emoji: '🛠️' };

function pickGroupMeta(category: string | null | undefined) {
  if (!category) return PROBLEM_GROUP_FALLBACK;
  return PROBLEM_GROUP_META[category] ?? { label: category.replace(/_/g, ' '), emoji: '🛠️' };
}

function priceCentsFrom(price: RepairPricingMatrixPrice): number {
  // labor_price is dollars (number) on the wire. Round to cents to avoid
  // float drift in the running tally.
  if (price.labor_price == null || !Number.isFinite(price.labor_price)) return 0;
  return Math.round(price.labor_price * 100);
}

function RepairIssueStep({ draft, setDraft, onBack, onContinue, onGoToStep }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onContinue: () => void;
  onGoToStep?: (target: RepairStepKey) => void;
}) {
  const [problemQuery, setProblemQuery] = useState('');
  const [customOpen, setCustomOpen] = useState(false);
  const [customName, setCustomName] = useState('');
  const [customPrice, setCustomPrice] = useState('');

  const category = draft.deviceType || 'phone';
  const deviceName = draft.deviceName.trim();
  const hasDeviceModel = draft.deviceModelId != null;

  // Pull device-scoped pricing matrix. With device_model_id known we'd ideally
  // hit a /repair-pricing/devices/:id/services endpoint — until that ships we
  // use the matrix endpoint with `q=<deviceName>` and pick the matching device
  // out of the response. `category` narrows the service list to the relevant
  // operations (screen/battery for phones, etc.).
  const matrixQuery = useQuery({
    queryKey: ['pos-problem-matrix', category, deviceName, draft.deviceModelId],
    queryFn: async () => {
      const res = await repairPricingApi.getMatrix({
        category,
        ...(deviceName ? { q: deviceName } : {}),
        limit: 50,
      });
      return res.data.data as RepairPricingMatrixResponse;
    },
    staleTime: 60_000,
  });

  const matrix = matrixQuery.data;
  const services = matrix?.services ?? [];
  // Match the picked device. If multiple come back, prefer one whose
  // device_model_id matches; else first row (substring match should be tight).
  const matchedDevice = (() => {
    const devices = matrix?.devices ?? [];
    if (devices.length === 0) return null;
    if (draft.deviceModelId != null) {
      const exact = devices.find((d) => d.device_model_id === draft.deviceModelId);
      if (exact) return exact;
    }
    return devices[0];
  })();

  // Build display rows. One per service. Price = device-specific labor when
  // available, else null (rendered as "Set price"). Group by service category.
  const filteredQ = problemQuery.trim().toLowerCase();
  const rows = services
    .filter((s) => (filteredQ ? s.name.toLowerCase().includes(filteredQ) : true))
    .map((s) => {
      const priceRow = matchedDevice?.prices.find((p) => p.repair_service_id === s.id);
      const priceCents = priceRow ? priceCentsFrom(priceRow) : 0;
      return {
        serviceId: s.id,
        name: s.name,
        category: s.category,
        priceCents,
        hasDevicePrice: priceRow ? priceRow.labor_price != null : false,
      };
    });

  const groups = rows.reduce<Record<string, typeof rows>>((acc, row) => {
    const key = row.category ?? 'other';
    if (!acc[key]) acc[key] = [] as typeof rows;
    acc[key].push(row);
    return acc;
  }, {});
  const groupKeys = Object.keys(groups).sort((a, b) => {
    // Render Screen / Battery / Charging first — most-common counter ops.
    const order = ['screen', 'battery', 'charging', 'camera', 'audio', 'buttons', 'software', 'water', 'data', 'motherboard', 'back_glass', 'diagnostic', 'other'];
    return order.indexOf(a) - order.indexOf(b);
  });

  const isSelected = (serviceId: number) => draft.selectedProblems.some((p) => p.repairServiceId === serviceId);

  const toggleProblem = (row: typeof rows[number]) => {
    setDraft((prev) => {
      const exists = prev.selectedProblems.find((p) => p.repairServiceId === row.serviceId);
      if (exists) {
        return { ...prev, selectedProblems: prev.selectedProblems.filter((p) => p.repairServiceId !== row.serviceId) };
      }
      const next: SelectedProblem = {
        id: String(row.serviceId),
        repairServiceId: row.serviceId,
        name: row.name,
        category: row.category,
        priceCents: row.priceCents,
        isCustom: false,
      };
      return { ...prev, selectedProblems: [...prev.selectedProblems, next] };
    });
  };

  const addCustomProblem = () => {
    const name = customName.trim();
    const priceNum = Number(customPrice);
    if (!name) return;
    if (!Number.isFinite(priceNum) || priceNum < 0) return;
    const id = `custom:${crypto.randomUUID?.() ?? Math.random().toString(36).slice(2)}`;
    setDraft((prev) => ({
      ...prev,
      selectedProblems: [
        ...prev.selectedProblems,
        {
          id,
          repairServiceId: null,
          name,
          category: 'other',
          priceCents: Math.round(priceNum * 100),
          isCustom: true,
        },
      ],
    }));
    setCustomName('');
    setCustomPrice('');
    setCustomOpen(false);
  };

  const totalSelectedCents = draft.selectedProblems.reduce((sum, p) => sum + p.priceCents, 0);
  const selectedCount = draft.selectedProblems.length;
  const canContinue = selectedCount > 0;

  return (
    <div className="mx-auto flex h-full max-w-5xl flex-col gap-3 px-4 pt-3 pb-3">
      <Stepper step="issue" onGoToStep={onGoToStep} />
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <div className="flex items-end justify-between gap-3">
          <div>
            <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-surface-500">What needs fixing?</div>
            <div className="mt-0.5 text-xs text-surface-600 dark:text-surface-400">
              Pick one or more problems. Pricing shown is for {deviceName || 'this device'}.
              {!hasDeviceModel && ' (Custom device — prices come from default tier; tap any tile to add.)'}
            </div>
          </div>
        </div>

        <div className="relative">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
          <input
            type="text"
            value={problemQuery}
            onChange={(e) => setProblemQuery(e.target.value)}
            placeholder="Search problems · cracked screen, battery, charging port..."
            className={cn(inputClass, 'pl-9')}
          />
        </div>

        {/* Scrollable problem grid. Pinned tally + footer remain visible. */}
        <div className="min-h-0 flex-1 overflow-y-auto pr-1">
          {matrixQuery.isLoading && (
            <div className="rounded-xl border border-dashed border-surface-300 p-6 text-center text-sm text-surface-500 dark:border-surface-700">
              Loading problem catalog…
            </div>
          )}
          {!matrixQuery.isLoading && rows.length === 0 && (
            <div className="rounded-xl border border-dashed border-surface-300 p-6 text-center text-sm text-surface-500 dark:border-surface-700">
              No catalog problems for this device. Use <span className="font-semibold">Add custom problem</span> below.
            </div>
          )}
          {groupKeys.map((groupKey) => {
            const meta = pickGroupMeta(groupKey);
            const groupRows = groups[groupKey];
            return (
              <div key={groupKey} className="mb-4">
                <div className="mb-2 flex items-center gap-2 font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">
                  <span className="text-base leading-none">{meta.emoji}</span>
                  {meta.label}
                  <span className="text-surface-400">· {groupRows.length}</span>
                </div>
                <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 lg:grid-cols-4">
                  {groupRows.map((row) => {
                    const active = isSelected(row.serviceId);
                    return (
                      <button
                        key={row.serviceId}
                        type="button"
                        onClick={() => toggleProblem(row)}
                        className={cn(
                          'group flex min-h-[80px] flex-col items-start justify-between gap-2 rounded-xl bg-white px-4 py-3 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md dark:bg-surface-800',
                          active
                            ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 dark:bg-primary-500/15'
                            : 'ring-1 ring-inset ring-surface-300 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:hover:ring-primary-500/80',
                        )}
                      >
                        <div className="text-sm font-semibold leading-tight text-surface-900 dark:text-surface-50">
                          {row.name}
                        </div>
                        <div className="flex w-full items-center justify-between text-xs">
                          <span className={cn('font-mono', row.hasDevicePrice ? 'text-surface-700 dark:text-surface-300' : 'text-surface-500')}>
                            {row.hasDevicePrice ? formatCurrency(row.priceCents / 100) : 'Set price'}
                          </span>
                          {active && <CheckCircle2 className="h-4 w-4 text-primary-500" />}
                        </div>
                      </button>
                    );
                  })}
                </div>
              </div>
            );
          })}

          {/* Custom problem affordance — last in the list so the eye lands on
              catalog problems first. Inline form expands so cashier doesn't
              leave the screen to add a one-off. */}
          <div className="mt-2 rounded-xl border-2 border-dashed border-primary-500/40 p-3">
            {!customOpen ? (
              <button
                type="button"
                onClick={() => setCustomOpen(true)}
                className="flex w-full items-center justify-center gap-2 py-2 text-sm font-semibold text-primary-700 hover:text-primary-600 dark:text-primary-400"
              >
                + Add custom problem
              </button>
            ) : (
              <div className="grid gap-2 sm:grid-cols-[1fr_auto_auto] sm:items-end">
                <label className="block">
                  <span className="mb-1 block text-xs text-surface-600 dark:text-surface-400">Problem</span>
                  <input
                    className={inputClass}
                    value={customName}
                    onChange={(e) => setCustomName(e.target.value)}
                    placeholder="e.g. Sim tray replacement"
                    autoFocus
                  />
                </label>
                <label className="block">
                  <span className="mb-1 block text-xs text-surface-600 dark:text-surface-400">Price</span>
                  <input
                    className={cn(inputClass, 'w-32')}
                    inputMode="decimal"
                    value={customPrice}
                    onChange={(e) => setCustomPrice(e.target.value)}
                    placeholder="0.00"
                  />
                </label>
                <div className="flex gap-2">
                  <button type="button" onClick={addCustomProblem} className={primaryButton}>Add</button>
                  <button type="button" onClick={() => { setCustomOpen(false); setCustomName(''); setCustomPrice(''); }} className={ghostButton}>Cancel</button>
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Pinned running tally — what's selected so far + total + count.
            Sits above the wizard footer so the cashier sees their progress
            without scrolling back up. */}
        <div className={cn(
          'rounded-xl border p-3 transition',
          selectedCount > 0 ? 'border-primary-500 bg-primary-500/10 dark:bg-primary-500/15' : 'border-dashed border-surface-300 dark:border-surface-700',
        )}>
          {selectedCount === 0 ? (
            <div className="text-center text-sm text-surface-500">No problems selected yet.</div>
          ) : (
            <div className="flex flex-wrap items-center justify-between gap-3">
              <div className="flex flex-wrap gap-1.5">
                {draft.selectedProblems.map((p) => (
                  <span key={p.id} className="inline-flex items-center gap-1 rounded-full bg-white px-2.5 py-1 text-xs font-semibold text-surface-900 shadow-sm dark:bg-surface-800 dark:text-surface-100">
                    {p.name}
                    <span className="font-mono text-surface-500">{formatCurrency(p.priceCents / 100)}</span>
                    <button
                      type="button"
                      onClick={() => setDraft((prev) => ({ ...prev, selectedProblems: prev.selectedProblems.filter((x) => x.id !== p.id) }))}
                      className="text-surface-400 hover:text-rose-500"
                      aria-label={`Remove ${p.name}`}
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </span>
                ))}
              </div>
              <div className="flex items-baseline gap-2">
                <span className="font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">
                  {selectedCount} selected
                </span>
                <span className="font-display text-2xl text-primary-700 dark:text-primary-300">
                  {formatCurrency(totalSelectedCents / 100)}
                </span>
              </div>
            </div>
          )}
        </div>
      </div>
      <WizardFooter
        onBack={onBack}
        onContinue={onContinue}
        continueDisabled={!canContinue}
      />
    </div>
  );
}

function RepairQuoteStep({ draft, setDraft, onBack, onContinue, onChargeDeposit, onGoToStep }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onContinue: () => void;
  /** Optional opt-in path. When provided, the wizard footer renders a ghost
   *  "Charge deposit" sub-button next to the primary save action. The
   *  primary save creates the ticket WITHOUT taking a deposit; the ghost
   *  button routes to the Deposit step where a deposit can be tendered.
   *  Lets shops pick deposit-on / deposit-off per ticket without baking the
   *  step into the wizard. */
  onChargeDeposit?: () => void;
  onGoToStep?: (target: RepairStepKey) => void;
}) {
  // Inline price-edit state per problem line.
  const [editingId, setEditingId] = useState<string | null>(null);
  const [editingDraft, setEditingDraft] = useState('');

  const updatePrice = (id: string, priceCents: number) => {
    setDraft((prev) => ({
      ...prev,
      selectedProblems: prev.selectedProblems.map((p) => (p.id === id ? { ...p, priceCents } : p)),
    }));
  };

  const removeProblem = (id: string) => {
    setDraft((prev) => ({
      ...prev,
      selectedProblems: prev.selectedProblems.filter((p) => p.id !== id),
    }));
  };

  const subtotalCents = draft.selectedProblems.reduce((sum, p) => sum + p.priceCents, 0);

  const startEdit = (id: string, currentCents: number) => {
    setEditingId(id);
    setEditingDraft((currentCents / 100).toFixed(2));
  };

  const commitEdit = (id: string) => {
    const next = Number(editingDraft);
    if (Number.isFinite(next) && next >= 0) updatePrice(id, Math.round(next * 100));
    setEditingId(null);
  };

  return (
    <div className="mx-auto flex h-full max-w-5xl flex-col gap-3 px-4 pt-3 pb-3">
      <Stepper step="quote" onGoToStep={onGoToStep} />

      <div className="flex min-h-0 flex-1 flex-col gap-3 overflow-y-auto pr-1">
        {/* Quote summary — selected problems become editable line items.
            This is the primary content of the screen. Replaces the old
            single-service form (which couldn't represent multi-problem
            tickets at all). */}
        <Section className="p-4">
          <div className="mb-3 flex items-center justify-between">
            <div>
              <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-surface-500">Quote</div>
              <div className="text-sm text-surface-700 dark:text-surface-300">
                {draft.deviceName || 'Device TBD'} · {draft.selectedProblems.length} problem{draft.selectedProblems.length === 1 ? '' : 's'}
              </div>
            </div>
            <button type="button" onClick={onBack} className="text-xs font-semibold text-primary-700 underline-offset-4 hover:underline dark:text-primary-400">
              Edit problems
            </button>
          </div>

          {draft.selectedProblems.length === 0 ? (
            <div className="rounded-lg border border-dashed border-surface-300 p-6 text-center text-sm text-surface-500 dark:border-surface-700">
              No problems on this quote. Go back to add some.
            </div>
          ) : (
            <div className="divide-y divide-surface-200 dark:divide-surface-800">
              {draft.selectedProblems.map((p) => (
                <div key={p.id} className="flex items-center gap-3 py-2.5">
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-semibold text-surface-900 dark:text-surface-50">{p.name}</div>
                    {p.category && <div className="font-mono text-[10.5px] uppercase tracking-[0.12em] text-surface-500">{pickGroupMeta(p.category).label}{p.isCustom && ' · custom'}</div>}
                  </div>
                  {editingId === p.id ? (
                    <input
                      autoFocus
                      type="text"
                      inputMode="decimal"
                      value={editingDraft}
                      onChange={(e) => setEditingDraft(e.target.value)}
                      onBlur={() => commitEdit(p.id)}
                      onKeyDown={(e) => {
                        if (e.key === 'Enter') { commitEdit(p.id); }
                        if (e.key === 'Escape') { setEditingId(null); }
                      }}
                      className="w-28 rounded-md border border-primary-500 bg-white px-2 py-1 text-right font-mono text-sm dark:bg-surface-900"
                    />
                  ) : (
                    <button
                      type="button"
                      onClick={() => startEdit(p.id, p.priceCents)}
                      className="rounded-md px-2 py-1 text-right font-mono text-sm text-surface-900 hover:bg-surface-100 dark:text-surface-100 dark:hover:bg-surface-800"
                      title="Click to edit price"
                    >
                      {formatCurrency(p.priceCents / 100)}
                    </button>
                  )}
                  <button
                    type="button"
                    onClick={() => removeProblem(p.id)}
                    className="text-surface-400 hover:text-rose-500"
                    aria-label={`Remove ${p.name}`}
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              ))}
            </div>
          )}

          <div className="mt-3 flex items-baseline justify-end gap-3 border-t border-surface-200 pt-3 dark:border-surface-800">
            <span className="font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">Subtotal</span>
            <span className="font-display text-3xl text-primary-700 dark:text-primary-300">{formatCurrency(subtotalCents / 100)}</span>
          </div>
        </Section>

        {/* Diagnostic intake — condition, customer's words, internal note,
            tech assignment, turnaround, diag summary. Moved here from the
            old Issue step so the Issue step is purely about WHAT is being
            repaired. */}
        <Section className="p-4">
          <div className="mb-2 font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">Device condition</div>
          <div className="mb-4 flex flex-wrap gap-2">
            {CONDITIONS.map((condition) => (
              <button
                key={condition}
                type="button"
                onClick={() => setDraft((prev) => ({ ...prev, condition }))}
                className={cn(
                  'rounded-full px-4 py-1.5 text-sm font-semibold transition',
                  draft.condition === condition
                    ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 text-primary-700 dark:text-primary-200'
                    : 'ring-1 ring-inset ring-surface-300 text-surface-700 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:text-surface-200',
                )}
              >
                {condition}
              </button>
            ))}
          </div>

          <div className="grid gap-3 md:grid-cols-2">
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Technician</span>
              <select className={inputClass} value={draft.technician} onChange={(event) => setDraft((prev) => ({ ...prev, technician: event.target.value }))}>
                <option value="">— assign later —</option>
                {TECHNICIAN_OPTIONS_STUB.map((tech) => <option key={tech} value={tech}>{tech}</option>)}
              </select>
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Promised turnaround</span>
              <select className={inputClass} value={draft.turnaround} onChange={(event) => setDraft((prev) => ({ ...prev, turnaround: event.target.value }))}>
                {TURNAROUND_OPTIONS.map((opt) => <option key={opt} value={opt}>{opt}</option>)}
              </select>
            </label>
          </div>

          <label className="mt-3 block">
            <span className="mb-1 block text-sm font-semibold">Customer's words</span>
            <textarea
              className={inputClass}
              rows={3}
              value={draft.customerWords}
              onChange={(event) => setDraft((prev) => ({ ...prev, customerWords: event.target.value }))}
              placeholder="What did the customer say is happening?"
            />
          </label>

          <label className="mt-3 block">
            <span className="mb-1 block text-sm font-semibold">Diagnostic notes</span>
            <textarea
              className={inputClass}
              rows={3}
              value={draft.diagnostic}
              onChange={(event) => setDraft((prev) => ({ ...prev, diagnostic: event.target.value }))}
              placeholder="Short counter-safe quote summary."
            />
          </label>

          <button
            type="button"
            onClick={() => setDraft((prev) => ({ ...prev, internalNoteOpen: !prev.internalNoteOpen }))}
            className="mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary-700 underline-offset-4 hover:underline dark:text-primary-500"
          >
            + Add internal note
            <span className="text-surface-500 dark:text-surface-400 font-normal">· staff-only · won't print on receipt</span>
          </button>
          {draft.internalNoteOpen && (
            <textarea
              className={cn(inputClass, 'mt-2 border-dashed')}
              rows={3}
              value={draft.internalNote || ''}
              onChange={(event) => setDraft((prev) => ({ ...prev, internalNote: event.target.value }))}
              placeholder="@mention staff · #tag tickets"
            />
          )}
        </Section>
      </div>

      {/* Quote-step footer — TWO actions:
            • Primary "Save ticket" creates the ticket without collecting a
              deposit. This is the most-common counter path: estimate,
              capture device, pickup later.
            • Ghost "Charge deposit" routes through the Deposit step so the
              cashier can tender a deposit before parking the ticket.
          Mockup §6 wanted deposit collection to be opt-in. The wizard
          footer accepts an optional second-action via `subActionLabel`. */}
      <WizardFooter
        onBack={onBack}
        onContinue={onContinue}
        continueLabel="Save ticket"
        continueDisabled={draft.selectedProblems.length === 0}
        subActionLabel={onChargeDeposit ? 'Charge deposit' : undefined}
        onSubAction={onChargeDeposit}
        subActionDisabled={draft.selectedProblems.length === 0}
      />
    </div>
  );
}

function RepairDepositStep({ draft, setDraft, onBack, onSave, onGoToStep }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onBack: () => void;
  onSave: () => void;
  onGoToStep?: (target: RepairStepKey) => void;
}) {
  const [waiverModal, setWaiverModal] = useState(false);
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4 px-4 pt-4 pb-6">
      <Stepper step="deposit" onGoToStep={onGoToStep} />
      <Section className="p-6 text-center">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Suggested deposit</div>
        <div className="mt-2 font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(parseMoney(draft.depositAmount))}</div>
        <div className="mt-2 text-sm text-surface-900 dark:text-surface-500">Balance is collected at pickup. Deposit can be changed before tender.</div>
        {(draft.technician || draft.turnaround) && (
          <div className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full border border-surface-200 bg-surface-50 px-3 py-1 text-xs text-surface-700 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300">
            {draft.technician ? `Tech ${draft.technician}` : 'Tech: TBD'} · {draft.turnaround || 'Turnaround: TBD'}
          </div>
        )}
        <div className="mx-auto mt-6 max-w-sm">
          <input className={cn(inputClass, 'text-center font-display text-4xl')} inputMode="decimal" value={draft.depositAmount} onChange={(event) => setDraft((prev) => ({ ...prev, depositAmount: event.target.value }))} />
        </div>
        <div className="mt-5 flex items-center justify-center gap-3">
          <label className="inline-flex items-center gap-2 text-sm font-semibold">
            <input type="checkbox" checked={draft.waiverHandled} onChange={(event) => setDraft((prev) => ({ ...prev, waiverHandled: event.target.checked }))} />
            Waiver handled
          </label>
          <button type="button" className={ghostButton} onClick={() => setWaiverModal(true)}>
            <FileText className="h-4 w-4" /> Sign on screen
          </button>
        </div>
      </Section>
      <WizardFooter onBack={onBack} continueLabel="Add repair to cart" onContinue={onSave} />
      {waiverModal && (
        <WaiverCanvasModal
          onCancel={() => setWaiverModal(false)}
          onConfirm={() => {
            setDraft((prev) => ({ ...prev, waiverHandled: true }));
            setWaiverModal(false);
            toast.success('Waiver signed');
          }}
        />
      )}
    </div>
  );
}

/**
 * WaiverCanvasModal — Mockup Frame 07: customer signs the diagnostic waiver
 * on screen before the deposit posts. Persisting the signature image is a
 * follow-up — the server already has `repair_waivers` table from the audit
 * doc, but the upload endpoint isn't wired yet. For now we capture the
 * stroke locally and treat any non-empty signature as "handled" so the
 * cashier can proceed; the image bytes will be hooked up when /repair-waivers
 * lands.
 */
function WaiverCanvasModal({ onCancel, onConfirm }: { onCancel: () => void; onConfirm: () => void }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const drawingRef = useRef(false);
  const [hasInk, setHasInk] = useState(false);

  const start = (event: React.PointerEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    drawingRef.current = true;
    canvas.setPointerCapture(event.pointerId);
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const rect = canvas.getBoundingClientRect();
    ctx.beginPath();
    ctx.moveTo(event.clientX - rect.left, event.clientY - rect.top);
  };
  const move = (event: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawingRef.current) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const rect = canvas.getBoundingClientRect();
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.strokeStyle = '#111';
    ctx.lineTo(event.clientX - rect.left, event.clientY - rect.top);
    ctx.stroke();
    setHasInk(true);
  };
  const end = () => { drawingRef.current = false; };
  const clear = () => {
    const canvas = canvasRef.current;
    const ctx = canvas?.getContext('2d');
    if (canvas && ctx) ctx.clearRect(0, 0, canvas.width, canvas.height);
    setHasInk(false);
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4">
      <div className="w-full max-w-2xl overflow-hidden rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-800">
          <div>
            <div className="font-display text-xl">Diagnostic waiver</div>
            <div className="text-xs text-surface-500">Hand the screen to the customer to sign.</div>
          </div>
          <button type="button" onClick={onCancel} aria-label="Close" className="rounded p-1 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800"><X className="h-4 w-4" /></button>
        </div>
        <div className="border-b border-surface-200 bg-surface-50 px-5 py-4 text-xs leading-relaxed text-surface-700 dark:border-surface-800 dark:bg-surface-950 dark:text-surface-300">
          By signing, you authorize diagnostic work and agree the deposit is non-refundable if the device cannot be repaired due to undisclosed prior damage. Liquid-damage repairs are best-effort. We are not responsible for data loss; back up before service.
        </div>
        <div className="bg-white p-3 dark:bg-surface-900">
          <canvas
            ref={canvasRef}
            width={600}
            height={180}
            className="block w-full rounded-md border border-dashed border-surface-300 bg-surface-50 dark:border-surface-700 dark:bg-surface-100"
            onPointerDown={start}
            onPointerMove={move}
            onPointerUp={end}
            onPointerLeave={end}
            onPointerCancel={end}
          />
        </div>
        <div className="flex items-center justify-between border-t border-surface-200 px-5 py-3 dark:border-surface-800">
          <button type="button" onClick={clear} className={ghostButton}>Clear</button>
          <div className="flex gap-2">
            <button type="button" onClick={onCancel} className={secondaryButton}>Cancel</button>
            <button type="button" disabled={!hasInk} onClick={onConfirm} className={primaryButton}>Confirm signature</button>
          </div>
        </div>
      </div>
    </div>
  );
}

function WizardFooter({ onBack, onContinue, backLabel = 'Back', continueLabel = 'Continue', continueDisabled = false, subActionLabel, onSubAction, subActionDisabled = false }: {
  onBack: () => void;
  onContinue: () => void;
  backLabel?: string;
  continueLabel?: string;
  continueDisabled?: boolean;
  /** Optional secondary action next to the primary continue button.
   *  Renders as a ghost-style button, sits LEFT of the primary so the
   *  primary stays the rightmost (eye-line) target. Used for opt-in
   *  branches like "Charge deposit" on the Quote step. */
  subActionLabel?: string;
  onSubAction?: () => void;
  subActionDisabled?: boolean;
}) {
  return (
    <div className="flex items-center justify-between gap-2 rounded-lg border border-surface-200 bg-white p-3 dark:border-surface-800 dark:bg-surface-900">
      <button type="button" onClick={onBack} className={secondaryButton}>
        <ChevronLeft className="h-4 w-4" />
        {backLabel}
      </button>
      <div className="flex items-center gap-2">
        {subActionLabel && onSubAction && (
          <button
            type="button"
            onClick={onSubAction}
            disabled={subActionDisabled}
            className={cn(ghostButton, subActionDisabled && 'cursor-not-allowed opacity-50')}
            title="Take a deposit before saving the ticket"
          >
            {subActionLabel}
          </button>
        )}
        <button
          type="button"
          onClick={onContinue}
          disabled={continueDisabled}
          className={cn(primaryButton, continueDisabled && 'cursor-not-allowed opacity-50')}
        >
          {continueLabel}
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
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
    { method: 'Cash', title: 'Cash', subtitle: 'Type amount · drawer opens on confirm', icon: Banknote },
    { method: 'Card', title: 'Card · tap · chip · swipe', subtitle: blockchypConfigured ? `Terminal ${terminalName} · ready · tip handled there` : 'Pair terminal in settings', icon: CreditCard, disabled: !blockchypConfigured },
    { method: 'Gift card', title: 'Gift card', subtitle: 'Scan or type code', icon: Gift },
    { method: 'Store credit', title: 'Store credit', subtitle: 'Apply customer balance', icon: Star },
  ];

  // Number-key shortcuts: 1-4 picks the matching method tile so the cashier
  // can stay on the keyboard. Skip when a meta/ctrl chord is in flight (those
  // are owned by the global handler), or when focus is in an input/textarea
  // (rare on this view but cheap defense).
  useEffect(() => {
    const handle = (event: KeyboardEvent) => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) return;
      const idx = ['1', '2', '3', '4'].indexOf(event.key);
      if (idx === -1) return;
      const candidate = methods[idx];
      if (!candidate || candidate.disabled) return;
      event.preventDefault();
      onSelect(candidate.method);
    };
    window.addEventListener('keydown', handle);
    return () => window.removeEventListener('keydown', handle);
  }, [methods, onSelect]);

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
        {methods.map(({ method, title, subtitle, icon: Icon, disabled }, index) => (
          <button key={method} type="button" onClick={() => onSelect(method)} disabled={disabled} className="relative rounded-lg border border-surface-200 bg-white p-5 text-left shadow-sm hover:border-primary-500 disabled:hover:border-surface-200 dark:border-surface-800 dark:bg-surface-900">
            <span className="absolute right-3 top-3 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[10px] text-surface-400">{index + 1}</span>
            <Icon className="h-7 w-7 text-primary-700 dark:text-primary-500" />
            <div className="mt-4 font-display text-3xl">{title}</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">{subtitle}</div>
          </button>
        ))}
      </div>
      <div className="mt-4 text-center text-sm text-surface-900 dark:text-surface-500">Take less than the full amount on any method — remainder bounces back here for a second tender.</div>
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
  // Mockup Frame 13 quick-amount strip: Exact + 5 staggered presets that
  // round up the remaining amount to common bill counts. Dedupe so $80 and
  // $80 don't show twice when remaining = $80.00.
  const quick: { label: string; value: number }[] = (() => {
    const exact = remaining;
    const presets = [
      { label: 'Exact', value: exact },
      { label: `$${Math.ceil(exact / 5) * 5}`, value: Math.ceil(exact / 5) * 5 },
      { label: `$${Math.ceil(exact / 10) * 10}`, value: Math.ceil(exact / 10) * 10 },
      { label: `$${Math.ceil(exact / 20) * 20}`, value: Math.ceil(exact / 20) * 20 },
      { label: `$${Math.ceil(exact / 50) * 50}`, value: Math.ceil(exact / 50) * 50 },
      { label: `$${Math.ceil(exact / 100) * 100}`, value: Math.ceil(exact / 100) * 100 },
    ];
    const seen = new Set<number>();
    return presets.filter((p) => {
      if (p.value <= 0 || seen.has(p.value)) return false;
      seen.add(p.value);
      return true;
    });
  })();
  const change = Math.max(0, parseMoney(amount) - remaining);
  return (
    <div className="mx-auto max-w-xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Cash received</div>
        <input className="mt-2 w-full rounded-lg border border-surface-200 bg-surface-50 px-4 py-3 text-right font-display text-6xl text-cyan-700 focus:border-primary-500 focus-visible:outline-none dark:border-surface-700 dark:bg-surface-950 dark:text-[#4DB8C9]" value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" autoFocus />
        <div className="mt-4 flex flex-wrap gap-2">
          {quick.map((preset) => (
            <button
              key={preset.label}
              type="button"
              onClick={() => setAmount(preset.value.toFixed(2))}
              className={cn(
                'rounded-full px-3 py-1.5 text-sm font-mono font-semibold border transition-colors',
                parseMoney(amount).toFixed(2) === preset.value.toFixed(2)
                  ? 'bg-primary-500 text-on-primary border-primary-500'
                  : 'border-surface-200 bg-white text-surface-700 hover:border-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200',
              )}
            >
              {preset.label === 'Exact' ? `Exact · ${formatCurrency(preset.value)}` : preset.label}
            </button>
          ))}
        </div>
        <div className="mt-5 rounded-lg border border-surface-200 p-4 dark:border-surface-800">
          <div className="flex items-baseline justify-between">
            <div className="text-sm text-surface-900 dark:text-surface-500">Change due</div>
            <div className="font-mono text-[11px] text-surface-500 dark:text-surface-400">drawer auto-opens on confirm</div>
          </div>
          <div className="font-display text-5xl text-emerald-700 dark:text-[#34C47E]">{formatCurrency(change)}</div>
        </div>
        <button type="button" onClick={onAccept} disabled={processing} className={cn(primaryButton, 'mt-5 w-full py-3 text-base')}>
          {processing ? 'Processing...' : `Take ${formatCurrency(parseMoney(amount) || remaining)} · open drawer · print receipt`}
        </button>
        <div className="mt-3 text-center font-mono text-[11px] text-surface-500 dark:text-surface-400">
          Type a smaller amount to take a partial payment — remainder bounces back to method picker.
        </div>
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
  const networkOnline = typeof navigator !== 'undefined' ? navigator.onLine : true;
  return (
    <div className="mx-auto max-w-2xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6 text-center">
        {method === 'Card' ? (
          /* Mockup Frame 14: terminal-pulse panel. Two animated rings around a
             card icon signal "waiting for tap". CSS keyframes defined in
             globals.css (or inline). */
          <div className="relative mx-auto h-24 w-24">
            <span className="absolute inset-0 rounded-full bg-cyan-500/12 animate-pulse"></span>
            <span className="absolute inset-3 rounded-full bg-cyan-500/22"></span>
            <CreditCard className="relative mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" style={{ marginTop: '28px' }} />
          </div>
        ) : (
          <Gift className="mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" />
        )}
        <div className="mt-4 font-display text-4xl">{method === 'Card' ? 'Tap, insert, or swipe' : method}</div>
        <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">
          {method === 'Card'
            ? (blockchypConfigured ? `Customer terminal mirrors the prompt + handles tip.` : 'Terminal is not configured.')
            : 'Enter the amount to apply. Scan or validate the code before tendering.'}
        </div>
        {method === 'Card' && blockchypConfigured && (
          <div className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full bg-surface-100 px-3 py-1 font-mono text-[11px] text-cyan-700 dark:bg-surface-800 dark:text-[#4DB8C9]">
            <span className="text-[10px]">●</span> Terminal {terminalName} · paired
          </div>
        )}
        <label className="mx-auto mt-5 block max-w-sm text-left">
          <span className="mb-1 block text-sm font-semibold">{method} amount</span>
          <input className={inputClass} value={amount} onChange={(event) => setAmount(event.target.value)} inputMode="decimal" />
          <div className="mt-1.5 font-mono text-[11px] text-surface-500 dark:text-surface-400">Edit to take partial · remainder bounces back to method picker</div>
        </label>
        <div className="mt-4 text-sm text-surface-900 dark:text-surface-500">Remaining balance is {formatCurrency(fromCents(remainingCents))}.</div>
        {!networkOnline && (
          /* Mockup Frame 14: network-fallback warning surfaces when Wi-Fi
             reconnect is in progress; cellular backup is configured at the
             store level. */
          <div className="mt-4 flex items-center gap-2 rounded-lg border border-amber-400/40 bg-amber-500/10 p-3 text-left text-xs text-amber-700 dark:text-[#e8a33d]">
            <span className="text-base">⚠️</span>
            <span>Network in fallback (Wi-Fi reconnecting) · cellular backup ready.</span>
          </div>
        )}
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
  const [filter, setFilter] = useState<'all' | 'repair' | 'expiring'>('all');
  // Compute counts off the rows so the pills match what the cashier will
  // actually see after filtering. Repair drafts are detected by label tag
  // (the holdMutation labels include "repair" / "draft" when applicable —
  // weak signal, but the only one without a snapshot deserialize per row).
  // Expiring uses the held-cart server's 24-hour TTL, anything older than
  // 23 h is "Expiring < 1h".
  const now = Date.now();
  const expiringMs = 23 * 60 * 60 * 1000;
  const isRepair = (row: HeldCartRow) => /repair|draft/i.test(row.label || '');
  const isExpiring = (row: HeldCartRow) => {
    const t = row.created_at ? new Date(row.created_at).getTime() : NaN;
    return Number.isFinite(t) && now - t > expiringMs;
  };
  const counts = {
    all: rows.length,
    repair: rows.filter(isRepair).length,
    expiring: rows.filter(isExpiring).length,
  };
  const filtered = rows.filter((row) => {
    if (filter === 'repair') return isRepair(row);
    if (filter === 'expiring') return isExpiring(row);
    return true;
  });
  const filterPills: Array<{ id: 'all' | 'repair' | 'expiring'; label: string; count: number }> = [
    { id: 'all', label: 'All', count: counts.all },
    { id: 'repair', label: 'Repair drafts', count: counts.repair },
    { id: 'expiring', label: 'Expiring < 1h', count: counts.expiring },
  ];
  return (
    <div className="px-5 py-4">
      <div className="mb-3 flex flex-wrap gap-2">
        {filterPills.map((pill) => (
          <button
            key={pill.id}
            type="button"
            onClick={() => setFilter(pill.id)}
            className={cn(
              'rounded-full px-3 py-1.5 text-xs font-semibold',
              filter === pill.id
                ? 'bg-primary-500 text-on-primary dark:bg-primary-500'
                : 'bg-surface-100 text-surface-600 hover:bg-surface-200 dark:bg-surface-800 dark:text-surface-300',
            )}
          >
            {pill.label} · {pill.count}
          </button>
        ))}
      </div>
      <div className="overflow-hidden rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-[minmax(200px,1fr)_minmax(200px,1.4fr)_120px_140px_120px_120px] gap-3 border-b border-surface-200 px-4 py-3 font-mono text-[11px] uppercase tracking-[0.14em] text-surface-500 dark:border-surface-700 dark:text-surface-500">
          <span>Customer</span>
          <span>Items</span>
          <span>Total</span>
          <span>Held by</span>
          <span>Held since</span>
          <span></span>
        </div>
        {loading ? (
          <div className="p-6 text-sm text-surface-900 dark:text-surface-500">Loading held sales...</div>
        ) : filtered.length === 0 ? (
          <div className="p-8 text-center text-sm text-surface-900 dark:text-surface-500">
            {rows.length === 0 ? 'No held sales right now.' : `No held sales match "${filterPills.find((p) => p.id === filter)?.label}".`}
          </div>
        ) : (
          filtered.map((row) => (
            <div key={row.id} className="grid grid-cols-[minmax(200px,1fr)_minmax(200px,1.4fr)_120px_140px_120px_120px] items-center gap-3 border-b border-surface-200 px-4 py-3 text-sm last:border-b-0 dark:border-surface-700">
              <div className="font-semibold">{row.label?.split(' · ')?.[0] || 'Held sale'}</div>
              <div className="truncate text-xs text-surface-600 dark:text-surface-300">{row.label?.split(' · ').slice(1).join(' · ') || '—'}</div>
              <div className="font-mono">{row.total_cents != null ? formatCurrency(fromCents(row.total_cents)) : '—'}</div>
              <div className="text-xs text-surface-600 dark:text-surface-400">{[row.owner_first_name, row.owner_last_name].filter(Boolean).join(' ') || 'Current cashier'}</div>
              <div className="font-mono text-xs text-surface-500">{formatDateTime(row.created_at)}</div>
              <div className="flex justify-end gap-2">
                <button type="button" onClick={() => onRecall(row.id)} className={primaryButton}>Resume</button>
                <button type="button" onClick={() => onDiscard(row.id)} aria-label="Discard held sale" title="Discard" className={cn(dangerButton, 'text-xs')}>×</button>
              </div>
            </div>
          ))
        )}
      </div>
    </div>
  );
}

type RefundMethod = 'original' | 'cash' | 'card' | 'store_credit';

function RefundView({ invoiceId, setInvoiceId, invoice, loading, selections, setSelections, refundMethod, setRefundMethod, processing, onProcess }: {
  invoiceId: string;
  setInvoiceId: (value: string) => void;
  invoice: any;
  loading: boolean;
  selections: RefundLineSelection[];
  setSelections: React.Dispatch<React.SetStateAction<RefundLineSelection[]>>;
  refundMethod: RefundMethod;
  setRefundMethod: (m: RefundMethod) => void;
  processing: boolean;
  onProcess: () => void;
}) {
  // Pull the open shift so we can read its live expected-cash balance via
  // the z-report endpoint. Used for the drawer-can-cover indicator on the
  // Cash refund-method tile. Fail-quiet — refunds without an open shift
  // (rare but possible if a manager kicks off a refund pre-shift) skip
  // the indicator instead of blocking the flow.
  const drawerShiftQuery = useQuery({
    queryKey: ['pos-enrich', 'drawer-current'],
    queryFn: async () => {
      const res = await api.get<{ data: { id: number } | null }>('/pos-enrich/drawer/current');
      return res.data.data;
    },
    staleTime: 30_000,
  });
  const drawerShiftId = drawerShiftQuery.data?.id ?? null;
  const drawerZReportQuery = useQuery({
    queryKey: ['pos-enrich', 'z-report', drawerShiftId, 'refund-cap'],
    enabled: drawerShiftId != null,
    queryFn: async () => {
      const res = await api.get<{ data: { expected_cents: number } }>(`/pos-enrich/drawer/${drawerShiftId}/z-report`);
      return res.data.data;
    },
    staleTime: 10_000,
  });
  const drawerCashOnHand = drawerZReportQuery.data ? fromCents(drawerZReportQuery.data.expected_cents) : null;

  const selectedTotal = selections.reduce((sum, selection) => {
    const line = invoice?.line_items?.find((item: any) => item.id === selection.line_item_id);
    return sum + (line ? Number(line.unit_price ?? line.price ?? 0) * selection.quantity : 0);
  }, 0);
  const cashShort = refundMethod === 'cash' && drawerCashOnHand !== null && selectedTotal > drawerCashOnHand;
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
          <div className="border-t border-surface-200 p-4 dark:border-surface-800">
            <div className="mb-3 font-mono text-[10px] uppercase tracking-wider text-surface-500">Refund to</div>
            <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
              {([
                { id: 'original', label: 'Back to original', sub: 'recommended' },
                { id: 'cash', label: 'Cash', sub: 'from drawer' },
                { id: 'card', label: 'Card', sub: 'reverse charge' },
                { id: 'store_credit', label: 'Store credit', sub: 'on customer file' },
              ] as Array<{ id: RefundMethod; label: string; sub: string }>).map((opt) => {
                const active = refundMethod === opt.id;
                return (
                  <button
                    key={opt.id}
                    type="button"
                    onClick={() => setRefundMethod(opt.id)}
                    className={cn(
                      'flex flex-col items-start gap-1 rounded-lg border px-3 py-2 text-left transition',
                      active
                        ? 'border-primary-500 bg-primary-500/10 text-primary-700 dark:text-primary-300'
                        : 'border-surface-200 bg-surface-50 text-surface-700 hover:border-surface-300 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200',
                    )}
                  >
                    <span className="text-sm font-semibold">{opt.label}</span>
                    <span className={cn('text-[10px] uppercase tracking-wider', active ? 'text-primary-600 dark:text-primary-400' : 'text-surface-500')}>{opt.sub}</span>
                  </button>
                );
              })}
            </div>
            {refundMethod === 'cash' && drawerCashOnHand === null && (
              <p className="mt-2 text-xs text-surface-500">Confirm the drawer has at least {formatCurrency(selectedTotal)} on hand before processing.</p>
            )}
            {refundMethod === 'cash' && drawerCashOnHand !== null && !cashShort && (
              <p className="mt-2 text-xs text-emerald-600 dark:text-[#34c47e]">
                ✓ Drawer covers — {formatCurrency(drawerCashOnHand)} on hand · refund {formatCurrency(selectedTotal)} leaves {formatCurrency(drawerCashOnHand - selectedTotal)}.
              </p>
            )}
            {refundMethod === 'cash' && drawerCashOnHand !== null && cashShort && (
              <p className="mt-2 text-xs text-red-600 dark:text-red-400">
                ✗ Drawer short — {formatCurrency(drawerCashOnHand)} on hand · refund needs {formatCurrency(selectedTotal)}. Cash-in or pick a different method.
              </p>
            )}
            {refundMethod === 'store_credit' && (
              <p className="mt-2 text-xs text-surface-500">Credit posts to the customer's file for use on a future ticket.</p>
            )}
          </div>
          <div className="flex items-center justify-between border-t border-surface-200 p-4 dark:border-surface-800">
            <div>
              <div className="text-sm text-surface-900 dark:text-surface-500">Refund total</div>
              <div className="font-display text-4xl">{formatCurrency(selectedTotal)}</div>
            </div>
            <button type="button" onClick={onProcess} disabled={processing || selections.length === 0 || cashShort} className={dangerButton} title={cashShort ? 'Drawer cannot cover this cash refund' : undefined}>
              Process refund
            </button>
          </div>
        </Section>
      )}
    </div>
  );
}

/**
 * CloseShiftView — formerly hardcoded dummy values for the Z-report side panel.
 *
 * Now reads:
 *   GET /pos-enrich/drawer/current    → active shift (or null if none open)
 *   GET /pos-enrich/drawer/{id}/z-report → live totals (gross, refund, payment breakdown,
 *                                          expected cash, variance)
 *
 * Lock-register fires `POST /pos-enrich/drawer/{id}/close` with the operator's
 * counted-cash total. Variance > $5 surfaces a warning banner (manager-PIN gate
 * lives in a follow-up — server already requires manager-or-admin).
 */
function CloseShiftView({ cashCount, setCashCount, onPopDrawer }: {
  cashCount: Record<string, string>;
  setCashCount: React.Dispatch<React.SetStateAction<Record<string, string>>>;
  onPopDrawer: () => void;
}) {
  const qc = useQueryClient();
  // Variance > $5 → require manager PIN before close lands. PinModal hits the
  // generic /auth/verify-pin and is shared with cash-in/out + high-value sale
  // gates, so the lockout state (5 fails → 60 s lock) is consistent.
  const [showPinGate, setShowPinGate] = useState(false);
  const { data: shift, isLoading: shiftLoading } = useQuery({
    queryKey: ['pos-enrich', 'drawer-current'],
    queryFn: async () => {
      const res = await api.get<{ data: { id: number; opened_at: string; opening_float_cents: number; closed_at: string | null } | null }>('/pos-enrich/drawer/current');
      return res.data.data;
    },
    staleTime: 30_000,
  });

  const shiftId = shift?.id ?? null;
  const { data: zReport, isLoading: zLoading } = useQuery({
    queryKey: ['pos-enrich', 'z-report', shiftId, 'preview'],
    enabled: shiftId != null,
    queryFn: async () => {
      const res = await api.get<{ data: {
        opening_float_cents: number;
        expected_cents: number;
        counted_cents: number;
        variance_cents: number;
        payment_breakdown: Array<{ method: string; cents: number; count: number }>;
        totals: { gross_cents: number; refund_cents: number; net_cents: number; transaction_count: number };
      } }>(`/pos-enrich/drawer/${shiftId}/z-report`);
      return res.data.data;
    },
    // Z-report is computed live for an open shift, so refetch on focus.
    refetchOnWindowFocus: true,
    staleTime: 10_000,
  });

  const closeMutation = useMutation({
    mutationFn: async (countedCents: number) => {
      if (shiftId == null) throw new Error('No open shift');
      const res = await api.post(`/pos-enrich/drawer/${shiftId}/close`, { closing_counted_cents: countedCents });
      return res.data?.data;
    },
    onSuccess: () => {
      toast.success('Shift closed');
      qc.invalidateQueries({ queryKey: ['pos-enrich', 'drawer-current'] });
      qc.invalidateQueries({ queryKey: ['pos-enrich', 'z-report'] });
    },
    onError: (err: any) => {
      toast.error(err?.message || 'Could not close shift');
    },
  });

  const counted = Object.entries(cashCount).reduce(
    (sum, [denom, count]) => sum + Number(denom) * (Number.parseInt(count || '0', 10) || 0),
    0,
  );
  const expectedCash = zReport ? fromCents(zReport.expected_cents) : 0;
  const variance = counted - expectedCash;
  const grossSales = zReport ? fromCents(zReport.totals.gross_cents) : 0;
  const refundsTotal = zReport ? fromCents(zReport.totals.refund_cents) : 0;
  const cardTender = zReport
    ? fromCents(zReport.payment_breakdown.filter((p) => p.method === 'card').reduce((s, p) => s + p.cents, 0))
    : 0;
  const txCount = zReport?.totals.transaction_count ?? 0;
  const varianceFlagged = Math.abs(variance) > 5;

  return (
    <div className="grid gap-4 lg:grid-cols-[minmax(0,1fr)_360px]">
      <Section className="p-5">
        <div className="flex items-center justify-between">
          <div>
            <div className="font-display text-3xl">Close shift</div>
            <div className="text-sm text-surface-900 dark:text-surface-500">
              {shiftLoading
                ? 'Loading shift…'
                : shift
                  ? `Shift #${shift.id} · opened ${formatTime(shift.opened_at)} · float ${formatCurrency(fromCents(shift.opening_float_cents))}`
                  : 'No open shift — start one from the cash-drawer widget in the topbar.'}
            </div>
          </div>
          <button type="button" onClick={onPopDrawer} className={secondaryButton} disabled={!shift}><Banknote className="h-4 w-4" /> Pop drawer</button>
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
        {zLoading && <div className="mt-3 text-xs text-surface-500">Loading Z-report…</div>}
        <div className="mt-5 space-y-3 text-sm">
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Transactions</span><span className="font-mono">{txCount}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Gross sales</span><span className="font-mono">{formatCurrency(grossSales)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Refunds</span><span className="font-mono text-red-600">-{formatCurrency(refundsTotal)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Card tender</span><span className="font-mono">{formatCurrency(cardTender)}</span></div>
          <div className="flex justify-between"><span className="text-surface-900 dark:text-surface-500">Expected cash</span><span className="font-mono">{formatCurrency(expectedCash)}</span></div>
          <div className="border-t border-surface-200 pt-3 dark:border-surface-800">
            <div className="flex justify-between font-semibold">
              <span>Variance</span>
              <span className={cn('font-mono', varianceFlagged ? (variance < 0 ? 'text-red-600' : 'text-amber-600') : 'text-surface-700 dark:text-surface-300')}>
                {variance >= 0 ? '+' : ''}{formatCurrency(variance)}
              </span>
            </div>
          </div>
        </div>
        {varianceFlagged && (
          <div className="mt-3 rounded-md border border-amber-300 bg-amber-50 px-3 py-2 text-xs text-amber-700 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300">
            Variance over $5 — manager PIN required to close.
          </div>
        )}
        <button
          type="button"
          className={cn(primaryButton, 'mt-6 w-full')}
          disabled={!shift || closeMutation.isPending}
          onClick={() => {
            if (varianceFlagged) {
              setShowPinGate(true);
            } else {
              closeMutation.mutate(toCents(counted));
            }
          }}
        >
          <Lock className="h-4 w-4" />
          {closeMutation.isPending ? 'Locking…' : 'Lock register'}
        </button>
      </Section>
      {showPinGate && (
        <PinModal
          title="Manager PIN required — variance over $5"
          onSuccess={() => {
            setShowPinGate(false);
            closeMutation.mutate(toCents(counted));
          }}
          onCancel={() => setShowPinGate(false)}
        />
      )}
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
  // Inject print-only CSS that hides everything outside the receipt panel.
  // Lifted from the Z-report modal pattern — same guarantees: removed on
  // unmount so it never leaks into other print contexts.
  useEffect(() => {
    const style = document.createElement('style');
    style.setAttribute('data-receipt-print', 'true');
    style.textContent = `
@media print {
  body > * { display: none !important; }
  [data-receipt-panel] { display: block !important; position: static !important; }
  [data-receipt-panel] > * { display: block !important; }
  [data-receipt-panel] .no-print { display: none !important; }
}
`.trim();
    document.head.appendChild(style);
    return () => { style.remove(); };
  }, []);

  // Print works today via window.print() + the print-only style above.
  // SMS / Email / PDF require server endpoints that aren't wired yet —
  // toast advises the cashier instead of a silent no-op.
  const handleShare = (kind: 'SMS' | 'Email' | 'Print' | 'PDF') => {
    if (kind === 'Print') {
      window.print();
      return;
    }
    toast(`${kind} delivery is coming soon`);
  };

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
          <div className="grid gap-3 sm:grid-cols-4 no-print">
            {([
              ['SMS', MessageSquare],
              ['Email', Mail],
              ['Print', Printer],
              ['PDF', FileText],
            ] as Array<[string, React.ElementType]>).map(([label, Icon]) => (
              <button
                key={label}
                type="button"
                onClick={() => handleShare(label as 'SMS' | 'Email' | 'Print' | 'PDF')}
                className="rounded-lg border border-surface-200 bg-white p-4 text-center font-semibold hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900"
              >
                <Icon className="mx-auto h-5 w-5 text-primary-700 dark:text-primary-500" />
                <span className="mt-2 block">{label}</span>
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
          <div className="flex flex-wrap gap-2 no-print">
            <button type="button" onClick={onNext} className={primaryButton}>Next sale</button>
            {sale.invoiceId && <button type="button" onClick={() => window.location.assign(`/invoices/${sale.invoiceId}`)} className={secondaryButton}>Open invoice</button>}
          </div>
        </div>
        <Section className="p-5 font-mono text-sm" data-receipt-panel>
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
