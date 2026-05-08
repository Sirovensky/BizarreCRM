import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { createPortal } from 'react-dom';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  AlertTriangle,
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
import { stripPhone, formatPhoneAsYouType } from '@/utils/phoneFormat';
import { PinModal } from '@/components/shared/PinModal';
import { useSettings } from '@/hooks/useSettings';
import { useAuthStore } from '@/stores/authStore';
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
  // Mid-intake repair draft (device, problems, notes, deposit). Optional so
  // older held-cart rows without it still restore cleanly.
  repairDraft?: RepairDraft;
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
  /** Quick check-in path: cashier skipped the Device picker via the gate's
   * "Quick check-in" CTA. Drives Back routing on the Issue step so it lands
   * on Category instead of an unvisited Device step. */
  skippedDevice: boolean;
  /** New flow: priced repair operations from `repair_services`. Replaces the
   * old free-form symptom-checklist on the Issue step. Multi-select, each
   * line becomes a quote line. */
  selectedProblems: SelectedProblem[];
  /** Staff-only note. Persists into ticket `meta.internalNotes`; never prints
   * on the receipt. Hidden by default; opens via the "+ Add internal note"
   * link. The old "Customer's words" field was removed — admins now route
   * customer-said notes into either Diagnostic (public) or Internal at
   * their discretion. */
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

// Survives a page refresh during repair intake so device + problems + notes
// aren't lost. Tab-scoped (sessionStorage) so concurrent registers in
// different windows don't clobber each other.
const REPAIR_DRAFT_STORAGE_KEY = 'pos-repair-draft';

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
  skippedDevice: false,
  selectedProblems: [],
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
  { value: 'watch',         label: 'Watch',           emoji: '⌚' },
  { value: 'tv',            label: 'TV',              emoji: '📺' },
  { value: 'desktop',       label: 'Desktop',         emoji: '🖥️' },
  { value: 'console',       label: 'Game console',    emoji: '🎮' },
  { value: 'xr',            label: 'VR / XR',         emoji: '🥽' },
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
  watch: ['Apple', 'Samsung', 'Google', 'OnePlus', 'Garmin', 'Fitbit'],
  console: ['Nintendo', 'PlayStation', 'Xbox', 'Steam'],
  xr: ['Apple', 'Meta', 'PlayStation', 'Valve', 'Pico'],
  tv: ['Samsung', 'LG', 'Sony', 'TCL', 'Vizio'],
  desktop: ['Apple', 'Dell', 'HP', 'Lenovo'],
};

const DEVICE_PLACEHOLDER: Record<string, string> = {
  phone: 'e.g. Samsung Galaxy A15',
  tablet: 'e.g. iPad Air 5th Gen',
  laptop: 'e.g. Dell Latitude 5540',
  watch: 'e.g. Apple Watch Series 11',
  tv: 'e.g. Samsung UN55TU7000',
  console: 'e.g. PlayStation 5 Slim',
  xr: 'e.g. Meta Quest 3 / Vision Pro',
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
const SCANNER_MAX_CHAR_INTERVAL_MS = 50;
const SCANNER_BUFFER_IDLE_MS = 200;

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
  mode: 'checkout' | 'create_ticket' = 'checkout',
) {
  const { cartItems, customer, discount, discountReason, meta, sourceTicketId, stackMembership } = store;
  const repairs = cartItems.filter((item): item is RepairCartItem => item.type === 'repair');
  const products = cartItems.filter((item): item is ProductCartItem => item.type === 'product');
  const miscItems = cartItems.filter((item): item is MiscCartItem => item.type === 'misc');
  const nonCardLegs = legs.filter((leg) => leg.method !== 'Card');

  return {
    mode,
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
    // WEB-UIUX-1245: opt-in stacking. Server defaults to max(manual,
    // membership); only sum both when the operator explicitly asked
    // via the discount-modal checkbox.
    stack_membership: stackMembership || undefined,
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
        tone === 'success' && 'bg-emerald-500/12 text-emerald-700 dark:text-emerald-400',
        tone === 'warning' && 'bg-amber-500/14 text-amber-800 dark:text-[#E8A33D]',
        tone === 'error' && 'bg-red-500/12 text-red-700 dark:text-[#E2526C]',
        tone === 'info' && 'bg-cyan-500/12 text-cyan-700 dark:text-cyan-400',
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
  // Capture the element that opened the modal so focus can return there on
  // close. Without this, dismissing a modal lands focus on <body>, which
  // makes Tab order start over and breaks keyboard flow.
  const triggerRef = useRef<HTMLElement | null>(null);
  const dialogRef = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    triggerRef.current = (document.activeElement as HTMLElement) ?? null;
    // Land focus on the dialog itself; the dialog's tabIndex makes it the
    // first stop when Tab is pressed.
    dialogRef.current?.focus({ preventScroll: true });
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        onClose();
      }
    };
    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      // Restore focus to the opener if it's still in the DOM.
      const el = triggerRef.current;
      if (el && document.contains(el)) {
        try { el.focus({ preventScroll: true }); } catch { /* noop */ }
      }
    };
  }, [onClose]);
  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/45 p-4">
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
        className="max-h-[90vh] w-full max-w-xl overflow-hidden rounded-lg border border-surface-200 bg-white shadow-2xl outline-none dark:border-surface-700 dark:bg-surface-900"
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
      <div role="tablist" aria-label="Open sales" className="flex h-full flex-1 items-end gap-1 min-w-0 overflow-x-auto overflow-y-hidden [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
        {children}
      </div>,
      headerSlot,
    );
  }
  return (
    <div role="tablist" aria-label="Open sales" className="flex h-[38px] shrink-0 items-center gap-2 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-950 px-4 overflow-x-auto [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
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
    stackMembership,
    setStackMembership,
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
  // WEB-UIUX-1227: pre-flight manager-PIN gate driven by store_config.
  // `pos_require_manager_for_discount === '1'` plus non-(admin|manager)
  // role triggers the PinModal BEFORE checkout. Without this the server
  // rejects safely at checkout time but the cashier discovers the gate
  // only after entering a discount + queueing tender.
  const { getSetting } = useSettings();
  const requireManagerForDiscount = getSetting('pos_require_manager_for_discount', '0') === '1';
  const currentUserRole = useAuthStore((s) => s.user?.role) ?? '';
  const cashierCanApplyDiscount = currentUserRole === 'admin' || currentUserRole === 'manager';
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
  // Repair-intake draft persists to sessionStorage so a mid-intake page
  // refresh (browser crash, accidental cmd-R) doesn't nuke the device +
  // problems + notes the cashier just entered. Also captured into the
  // held-cart snapshot so parking a mid-intake sale and recalling it
  // restores the draft as well.
  const [repairDraft, setRepairDraft] = useState<RepairDraft>(() => {
    try {
      const raw = sessionStorage.getItem(REPAIR_DRAFT_STORAGE_KEY);
      if (raw) return { ...DEFAULT_REPAIR_DRAFT, ...JSON.parse(raw) };
    } catch {
      /* corrupted blob — fall back to defaults */
    }
    return DEFAULT_REPAIR_DRAFT;
  });
  useEffect(() => {
    try {
      sessionStorage.setItem(REPAIR_DRAFT_STORAGE_KEY, JSON.stringify(repairDraft));
    } catch {
      /* quota exceeded — best-effort; in-memory draft is still authoritative */
    }
  }, [repairDraft]);
  const [paidLegs, setPaidLegs] = useState<PaymentLeg[]>([]);
  const [selectedTenderMethod, setSelectedTenderMethod] = useState<TenderMethod>('Cash');
  const [amountEntry, setAmountEntry] = useState('');
  const [processing, setProcessing] = useState(false);
  // BUGHUNT-2026-05-10-17: synchronous in-flight guard. React batches the
  // setProcessing(true) write; a rapid double-click on Charge can race
  // both calls past the `if (processing) return` check before the
  // re-render disables the button. inFlightRef toggles inside the
  // handler synchronously so the second click short-circuits.
  const checkoutInFlightRef = useRef(false);
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
  // WEB-UIUX-796: serialize concurrent scan lookups so a rapid double-scan
  // doesn't lose the first hit. Each new scan chains onto the prior promise.
  const scanQueueRef = useRef<Promise<void> | null>(null);
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

  // Debounce the search term so each keystroke doesn't fire a fresh request
  // (and flip `isFetching` → spinner → header reflow). 180 ms feels snappy
  // without flooding the API on long names.
  const [debouncedSearch, setDebouncedSearch] = useState('');
  useEffect(() => {
    const t = setTimeout(() => setDebouncedSearch(globalSearch.trim()), 180);
    return () => clearTimeout(t);
  }, [globalSearch]);

  const customerSearch = useQuery({
    queryKey: ['pos-customer-search', debouncedSearch],
    queryFn: ({ signal }) => customerApi.search(debouncedSearch, signal),
    enabled: debouncedSearch.length >= 2 && mode === 'gate',
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

  // Stable tab order — Chrome semantics. The server returns held carts by
  // created_at DESC, so naive sort would shove every fresh hold to the
  // leftmost slot and visually drag the surrounding tabs around. We keep a
  // client-side `tabOrder` array that:
  //   1. Drops ids no longer in the held list.
  //   2. Slots a NEW id into the position previously occupied by the tab
  //      the cashier just clicked (so clicking tab X parks the old cart
  //      INTO X's slot instead of the rightmost edge).
  //   3. Otherwise appends new ids to the right end (where new holds belong).
  // `lastClickedHeldRef` carries the just-clicked id from the click handler
  // into the reconcile effect; the effect clears it on first use.
  const [tabOrder, setTabOrder] = useState<number[]>([]);
  const lastClickedHeldRef = useRef<number | null>(null);
  useEffect(() => {
    const ids = (heldCarts.data?.data?.data ?? []).map((r) => r.id);
    setTabOrder((prev) => {
      const present = new Set(ids);
      const kept = prev.filter((id) => present.has(id));
      const fresh = ids.filter((id) => !prev.includes(id));
      const removedClicked = lastClickedHeldRef.current;
      if (removedClicked != null && fresh.length === 1 && !present.has(removedClicked)) {
        // Clicked tab `X` got recalled (removed) and a new hold `Y` arrived.
        // Reuse the index where X was sitting in the previous order so Y
        // takes X's visual slot instead of jumping to the end.
        const idx = prev.indexOf(removedClicked);
        if (idx >= 0) {
          const next = [...kept];
          next.splice(idx, 0, fresh[0]);
          lastClickedHeldRef.current = null;
          return next;
        }
      }
      lastClickedHeldRef.current = null;
      return [...kept, ...fresh];
    });
  }, [heldCarts.data]);

  const blockchypStatus = useQuery({
    queryKey: ['blockchyp-status'],
    queryFn: () => blockchypApi.status(),
    staleTime: 30_000,
    enabled: mode === 'tender-method' || mode === 'tender-card',
  });
  const blockchypConfigured = blockchypStatus.data?.data?.data?.enabled ?? false;
  const terminalName = blockchypStatus.data?.data?.data?.terminalName ?? 'terminal';
  // WEB-UIUX-937: heartbeat-aware reachability. `null` = no ping yet this
  // process (unknown — UI shouldn't block); `online === false` = last ping
  // failed or is older than the freshness window.
  const blockchypHeartbeat = blockchypStatus.data?.data?.data?.heartbeat ?? null;
  const blockchypOffline = !!blockchypHeartbeat && !blockchypHeartbeat.online;
  const blockchypOfflineReason = blockchypHeartbeat?.lastError
    ? `Last error: ${blockchypHeartbeat.lastError}`
    : blockchypHeartbeat?.stale
      ? 'No recent ping — terminal may be unplugged'
      : null;

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

    // Layer-4 guard: if the ticket already has a fully-paid invoice the
    // cashier should NOT be able to re-tender it from the POS. Bounce them
    // to the invoice page with a toast instead of pre-loading the cart.
    // Server enforces the same rule (ERR_RESOURCE_CONFLICT) but we shortcut
    // the round-trip + show a clear message.
    const inv = (ticket as any).invoice;
    const invoiceStatus = inv?.status ?? null;
    const invoiceId = ticket.invoice_id ?? inv?.id ?? null;
    if (invoiceId && invoiceStatus === 'paid') {
      hydratedRef.current = ticketParam;
      setSearchParams({}, { replace: true });
      toast.success(`Invoice ${inv?.order_id ?? `#${invoiceId}`} is already paid · opening invoice`);
      navigate(`/invoices/${invoiceId}`);
      return;
    }

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
    // Skip while the inline customer-create panel is open: the cart's
    // "swap walk-in" click intentionally lands on `gate` to surface that
    // panel, and bouncing back to `sale` here would unmount it mid-flash.
    if (createCustomerOpen) return;
    if (mode === 'gate' && (customer || cartItems.length > 0 || walkInActive)) setMode('sale');
  }, [mode, customer, cartItems.length, walkInActive, createCustomerOpen]);

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
      // WEB-UIUX-792: bail when any modal/overlay-style state is open so
      // phantom barcodes don't add a line item to the underlying cart while
      // the cashier is interacting with PinModal / DeviceTemplateNudge /
      // UpsellPrompt / CheckoutModal-style overlays. The element-level
      // checks below (INPUT/TEXTAREA/SELECT/contenteditable) cover focused
      // inputs inside those modals; this guard adds the modal-state set.
      const modalOpen = Boolean(document.querySelector('[aria-modal="true"], [role="dialog"]'));
      if (
        processing ||
        lineEditing ||
        discountOpen ||
        customItemOpen ||
        createCustomerOpen ||
        terminalError ||
        completedSale ||
        (mode !== 'gate' && mode !== 'sale') ||
        modalOpen
      ) return;
      const target = event.target as HTMLElement | null;
      const tag = target?.tagName;
      if (tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || target?.isContentEditable) return;

      const now = Date.now();
      const sinceLast = now - lastKeyTimeRef.current;
      lastKeyTimeRef.current = now;

      if (event.key === 'Enter' && scanBufferRef.current.length >= 4) {
        event.preventDefault();
        const code = scanBufferRef.current;
        scanBufferRef.current = '';
        if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
        if (scanFlashTimerRef.current) clearTimeout(scanFlashTimerRef.current);
        setScanFlash(false);

        // WEB-UIUX-796: queue overlapping scans so the second doesn't abort
        // the first. Previously the lookup promise was fire-and-forget; a
        // scanner that double-fires 200ms apart kicked off a second
        // request whose state could clobber the first's `addProductToCart`
        // if React batched setState updates in different orders. We now
        // chain lookups via the ref so each scan is processed in arrival
        // order against an explicit in-flight pointer; nothing aborts and
        // every confirmed-hit reaches the cart.
        const runLookup = async () => {
          try {
            const found: ProductSearchItem | null | undefined = /^\d{8,}$/.test(code)
              ? await inventoryApi.lookupBarcode(code).then((res) => res.data?.data)
              : await posApi.products({ keyword: code, limit: 20 }).then((res) => res.data?.data?.items?.[0]);
            if (found) {
              setScanFlash(true);
              if (scanFlashTimerRef.current) clearTimeout(scanFlashTimerRef.current);
              scanFlashTimerRef.current = setTimeout(() => setScanFlash(false), 1000);
              addProductToCart(found);
              setScanFlash(true);
              scanFlashTimerRef.current = setTimeout(() => setScanFlash(false), 1000);
              toast.success(`Scanned ${found.name}`);
            } else {
              setCustomName(code);
              setCustomItemOpen(true);
              toast.error('No item matched that scan');
            }
          } catch {
            toast.error('Scan lookup failed');
          }
        };
        // Chain to any pending lookup so order is preserved even when two
        // scans arrive in <250ms. Drop scanQueueRef when settled.
        scanQueueRef.current = (scanQueueRef.current ?? Promise.resolve())
          .then(runLookup)
          .catch(() => { /* prior chain failure already toasted */ });
        return;
      }

      if (event.key.length === 1) {
        // WEB-UIUX-794: tighten scanner inter-keystroke threshold. A 40-wpm
        // typist averages ~75ms/char, so the previous 100ms gap accepted
        // human typing as a scan. Real USB HID scanners deliver characters
        // at sub-20ms intervals; SCANNER_MAX_CHAR_INTERVAL_MS is a safe
        // upper bound (50ms).
        scanBufferRef.current = sinceLast > SCANNER_MAX_CHAR_INTERVAL_MS ? event.key : scanBufferRef.current + event.key;
        if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
        scanTimerRef.current = setTimeout(() => {
          scanBufferRef.current = '';
        }, SCANNER_BUFFER_IDLE_MS);
      }
    };
    window.addEventListener('keydown', handleScanner);
    return () => {
      window.removeEventListener('keydown', handleScanner);
      if (scanTimerRef.current) clearTimeout(scanTimerRef.current);
      if (scanFlashTimerRef.current) clearTimeout(scanFlashTimerRef.current);
    };
  }, [addProductToCart, completedSale, createCustomerOpen, customItemOpen, discountOpen, lineEditing, mode, processing, terminalError]);

  const startNewSale = useCallback(() => {
    setCompletedSale(null);
    setPaidLegs([]);
    setTerminalError(null);
    rotateIdempotencyKey();
    clearDraft();
    setWalkInActive(false);
    setCreateCustomerOpen(false);
    setCreateCustomerDraft(EMPTY_CREATE_CUSTOMER_DRAFT);
    // Repair draft lives in component state (plus sessionStorage), so
    // clearDraft() — which only resets zustand — leaves it stale. Wipe it
    // explicitly so the new sale starts with no leaked device/problem picks.
    setRepairDraft(DEFAULT_REPAIR_DRAFT);
    setMode('gate');
    setGlobalSearch('');
    setProductSearch('');
    searchInputRef.current?.focus();
  }, [clearDraft, rotateIdempotencyKey]);

  // `skipReset` keeps the active draft + mode untouched after the server
  // ack — used by the tab-switch handler, which already restored the picked
  // tab's snapshot synchronously. Without it the post-hold cleanup runs
  // AFTER restoreSnapshot and wipes the freshly-recalled cart, snapping the
  // cashier back to the gate.
  const holdMutation = useMutation({
    mutationFn: async (vars?: { skipReset?: boolean }) => {
      void vars;
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
        repairDraft,
      };
      // Build a richer tab label so `#42 · held` becomes
      // `Marco D'Souza · 3 items · $214.50` — actually identifiable when the
      // strip has 5+ tabs. Fallbacks: customer-name → first-line-title → walk-in.
      const itemsLabel = cartItems.length > 0
        ? `${cartItems.length} item${cartItems.length === 1 ? '' : 's'}`
        : '';
      const totalLabel = totals.totalCents > 0 ? formatCurrency(fromCents(totals.totalCents)) : '';
      const headLabel = customer
        ? getCustomerName(customer)
        : cartItems[0] ? lineTitle(cartItems[0]) : 'Walk-in sale';
      const label = [headLabel, itemsLabel, totalLabel].filter(Boolean).join(' · ');
      return api.post('/pos/held-carts', {
        cart_json: JSON.stringify(snapshot),
        label,
        customer_id: customer?.id ?? null,
        total_cents: totals.totalCents,
      }, { skipGlobal500Toast: true } as object);
    },
    onSuccess: (_res, vars) => {
      queryClient.invalidateQueries({ queryKey: ['pos-held-carts'] });
      if (vars?.skipReset) return;
      toast.success('Sale held');
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
      repairDraft: DEFAULT_REPAIR_DRAFT,
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
    // Restore the mid-intake repair draft when the held row carried one.
    // Falling back to DEFAULT_REPAIR_DRAFT prevents the previously-active
    // tab's draft from leaking into a recalled cart.
    setRepairDraft(snapshot.repairDraft ?? DEFAULT_REPAIR_DRAFT);
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
        const row = res.data?.data;
        // Corrupt or truncated cart_json blob shouldn't crash the page;
        // surface a toast and leave the existing draft intact so the
        // cashier can decide whether to discard or retry.
        let snapshot: HeldCartSnapshot | null = null;
        try {
          if (row?.cart_json) snapshot = JSON.parse(row.cart_json) as HeldCartSnapshot;
        } catch {
          snapshot = null;
        }
        if (snapshot) {
          restoreSnapshot(snapshot);
          toast.success('Held sale restored');
        } else {
          toast.error('Held sale data was unreadable. Try again or discard the tab.');
        }
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

  // Warn before tab close when an in-flight charge or partial tender is
  // pending so the cashier doesn't accidentally strand a payment that the
  // server may already have captured. Browsers ignore custom strings, so
  // returnValue is set but the message text is a hint to humans reading
  // the code, not the dialog.
  useEffect(() => {
    const hasPendingPayment = processing || paidLegs.length > 0;
    if (!hasPendingPayment) return;
    const handler = (event: BeforeUnloadEvent) => {
      event.preventDefault();
      event.returnValue = 'A payment is still in progress. Leaving may strand the charge.';
      return event.returnValue;
    };
    window.addEventListener('beforeunload', handler);
    return () => window.removeEventListener('beforeunload', handler);
  }, [processing, paidLegs.length]);

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
        if (cartItems.length > 0 || customer) holdMutation.mutate(undefined);
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
      // ⌘1..9 — jump to the Nth held tab. Mirrors Chrome's tab-switch
      // shortcuts so cashiers running 3-9 parallel sales can swap without
      // reaching for the mouse. Reversed list to match visible left→right
      // tab order in the strip.
      if (/^[1-9]$/.test(event.key)) {
        // Match the visible strip order (driven by `tabOrder`) so ⌘1 lines
        // up with the leftmost tab the cashier can see.
        const heldRows = heldCarts.data?.data?.data ?? [];
        const byId = new Map(heldRows.map((r) => [r.id, r]));
        const ordered = tabOrder.map((id) => byId.get(id)).filter((r): r is HeldCartRow => Boolean(r));
        const orderedIds = new Set(ordered.map((r) => r.id));
        const tail = heldRows.filter((r) => !orderedIds.has(r.id));
        const list = [...ordered, ...tail];
        const idx = Number(event.key) - 1;
        const row = list[idx];
        if (row) {
          event.preventDefault();
          if (mode.startsWith('tender')) {
            toast.error('Finish or cancel payment before switching tabs');
            return;
          }
          lastClickedHeldRef.current = row.id;
          if (cartItems.length > 0 || customer) holdMutation.mutate({ skipReset: true });
          recallMutation.mutate({ id: row.id });
        }
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
  }, [cartItems.length, customer, holdMutation, mode, setCommandPaletteOpen, commandPaletteOpen, discountOpen, lineEditing, customItemOpen, pendingDiscount, heldCarts.data, recallMutation]);

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
            additional_notes: [repairDraft.diagnostic].filter(Boolean).join('\n'),
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
    // Persist the staff-only note onto the ticket's cart-wide internalNotes
    // so it survives checkout (server stores it on the ticket, not the line).
    // Append rather than overwrite — operator may have entered notes on a
    // different surface earlier in the same cart.
    if (repairDraft.internalNote.trim()) {
      const existing = useUnifiedPosStore.getState().meta.internalNotes;
      setMeta({
        internalNotes: existing
          ? `${existing}\n${repairDraft.internalNote.trim()}`
          : repairDraft.internalNote.trim(),
      });
    }
    toast.success(problems.length > 1 ? `${problems.length} repair lines added` : 'Repair added to cart');
    setRepairDraft(DEFAULT_REPAIR_DRAFT);
    setMode('sale');
  }, [addRepair, repairDraft, setMeta]);

  // Same as saveRepairToCart, but additionally stamps the deposit + balance
  // onto the ticket's internal notes so the pickup desk can reconcile what
  // was collected today against what is owed at pickup. Capture deposit +
  // quote BEFORE delegating because saveRepairToCart resets the draft.
  const saveRepairWithDeposit = useCallback(() => {
    const deposit = parseMoney(repairDraft.depositAmount);
    const quoteSubtotal = repairDraft.selectedProblems.length > 0
      ? repairDraft.selectedProblems.reduce((s, p) => s + p.priceCents, 0) / 100
      : parseMoney(repairDraft.laborPrice);
    const balance = Math.max(0, quoteSubtotal - deposit);
    saveRepairToCart();
    if (deposit > 0 && balance > 0) {
      const existing = useUnifiedPosStore.getState().meta.internalNotes;
      const note = `Deposit ${formatCurrency(deposit)} collected; balance ${formatCurrency(balance)} owed at pickup.`;
      setMeta({ internalNotes: existing ? `${existing}\n${note}` : note });
      toast.success(`Deposit ${formatCurrency(deposit)} noted — adjust line prices before tender if charging only the deposit.`);
    }
  }, [repairDraft, saveRepairToCart, setMeta]);

  const submitCheckout = useCallback(async (finalLeg: PaymentLeg) => {
    // BUGHUNT-2026-05-10-17: synchronous re-entrancy guard. Stops rapid
    // double-clicks from firing two POST /sales calls with the same
    // idempotency key before React commits the processing flag.
    if (checkoutInFlightRef.current) return;
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

    checkoutInFlightRef.current = true;
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
          // WEB-UIUX-825: distinguish HTTP 202 / `pending_reconciliation`
          // from a flat decline. A pending state means the server has NOT
          // confirmed the capture either way — retrying the same
          // idempotency key replays the prior charge if it actually went
          // through, which can double-bill. Surface a different message
          // and bail without offering a retry button.
          if (terminalResult?.status === 'pending_reconciliation') {
            setTerminalError(
              'Card status pending — the terminal did not confirm capture. Do NOT retry: check the terminal and the customer\'s card. If charged, complete the sale manually.',
            );
            return;
          }
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
      // WEB-UIUX-887: invalidate inventory + reports caches so other tabs see
      // post-sale stock and revenue. Previously only membership cache was
      // touched, leaving every other surface stale.
      void queryClient.invalidateQueries({ queryKey: ['inventory'] });
      void queryClient.invalidateQueries({ queryKey: ['inventory-low-stock'] });
      void queryClient.invalidateQueries({ queryKey: ['pos-products'] });
      void queryClient.invalidateQueries({ queryKey: ['pos-products-rewrite'] });
      void queryClient.invalidateQueries({ queryKey: ['invoices'] });
      void queryClient.invalidateQueries({ queryKey: ['invoice-stats'] });
      void queryClient.invalidateQueries({ queryKey: ['dashboard'] });
      void queryClient.invalidateQueries({ queryKey: ['reports'] });
      window.dispatchEvent(new CustomEvent('pos:payment-completed'));
      toast.success('Sale complete');
      // WEB-UIUX-1228: server may swap a smaller manual discount for a
      // larger membership discount when the cashier didn't explicitly opt
      // into stacking. Surface that swap so the cashier sees why the
      // applied discount differs from what they typed.
      const dbk = res.data?.data?.discount_breakdown;
      if (dbk?.manual_dropped) {
        toast(
          `Membership discount ${formatCurrency(fromCents(dbk.membership))} replaced your manual ${formatCurrency(fromCents(dbk.manual))} (larger wins). Toggle "Stack with membership" to combine.`,
          { duration: 6000, icon: 'ℹ️' },
        );
      }
    } catch (err: any) {
      toast.error(err?.response?.data?.message || err?.message || 'Checkout failed');
    } finally {
      setProcessing(false);
      checkoutInFlightRef.current = false;
    }
  }, [paidLegs, totals, blockchypConfigured, cartItems, customer, ensureIdempotencyKey, clearDraft, queryClient]);

  /**
   * Create the ticket on the server WITHOUT taking payment. Counterpart to
   * `submitCheckout` for the common counter path: cashier wants to log the
   * device + estimate now, collect later when the customer picks up. Hits
   * the same `/pos/checkout-with-ticket` endpoint in `mode: 'create_ticket'`
   * — server skips invoice creation and payment legs entirely.
   */
  const submitCreateTicket = useCallback(async () => {
    const repairs = cartItems.filter((item): item is RepairCartItem => item.type === 'repair');
    if (repairs.length === 0) {
      toast.error('Add a repair line before saving as ticket');
      return;
    }
    if (paidLegs.length > 0) {
      toast.error('Cannot save as ticket once a payment has been started');
      return;
    }
    setProcessing(true);
    try {
      const payload = buildCheckoutPayload(useUnifiedPosStore.getState(), [], 'create_ticket');
      const idempotencyKey = ensureIdempotencyKey();
      const pinVerified = useUnifiedPosStore.getState().isPosPinVerified();
      const res = await posApi.checkoutWithTicket(payload, idempotencyKey, pinVerified);
      const ticketOrderId = res.data?.data?.ticket?.order_id ?? res.data?.data?.order_id;
      clearDraft();
      setPaidLegs([]);
      setMode('gate');
      toast.success(ticketOrderId ? `Ticket ${ticketOrderId} created` : 'Ticket created');
    } catch (err: any) {
      toast.error(err?.response?.data?.message || err?.message || 'Could not save ticket');
    } finally {
      setProcessing(false);
    }
  }, [cartItems, paidLegs, ensureIdempotencyKey, clearDraft]);

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
    // WEB-UIUX-1227: pre-flight gates that park the apply in `pendingDiscount`
    // and let the PinModal commit on success.
    //   1. >25% subtotal — historical advisory turned hard gate.
    //   2. pos_require_manager_for_discount + non-(admin|manager) cashier —
    //      server enforces with a 403 at checkout; gating here saves the
    //      cashier from typing tender and discovering the block too late.
    const needsManagerForRule = requireManagerForDiscount && !cashierCanApplyDiscount && amount > 0;
    const needsManagerForSize = totals.subtotal > 0 && amount > totals.subtotal * 0.25;
    if (needsManagerForRule || needsManagerForSize) {
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

  const cancelAppointmentMutation = useMutation({
    mutationFn: (id: number) => leadApi.updateAppointment(id, { status: 'cancelled' }),
    onSuccess: () => {
      toast.success('Appointment cancelled');
      queryClient.invalidateQueries({ queryKey: ['pos-todays-appointments'] });
      queryClient.invalidateQueries({ queryKey: ['appointments'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not cancel appointment'),
  });
  const cancelAppointment = (appointment: PosAppointment) => {
    if (!window.confirm(`Cancel ${appointmentCustomerName(appointment)}'s ${formatTime(appointment.start_time)} appointment?`)) return;
    cancelAppointmentMutation.mutate(appointment.id);
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
            // Repair-* modes used to repeat "Step N of 5 · …" here, but the
            // Stepper component on each step already shows the same info more
            // legibly. Drop the topbar duplicate; let the title stay as
            // "Repair intake".
            : mode.startsWith('repair')
              ? null
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
        {/* Chrome-style tab order: each held cart keeps its slot for as long
            as it lives. Driven by client-side `tabOrder` (set up above) so
            clicking a tab doesn't shove the parked cart to the rightmost
            edge — the new hold inherits the clicked tab's index. */}
        {(() => {
          const heldRows = heldCarts.data?.data?.data ?? [];
          const byId = new Map(heldRows.map((r) => [r.id, r]));
          // Render any ids in tabOrder first (in order); fall back to raw
          // list for ids not yet reconciled (first paint after refresh).
          const ordered = tabOrder
            .map((id) => byId.get(id))
            .filter((row): row is HeldCartRow => Boolean(row));
          const orderedIds = new Set(ordered.map((r) => r.id));
          const tail = heldRows.filter((r) => !orderedIds.has(r.id));
          return [...ordered, ...tail];
        })().map((row) => (
          // Tab is now an outer DIV (not a button) so we can nest the close
          // X as its own button without violating the no-nested-button rule.
          // The whole tab body still acts as a clickable area via the inner
          // `<button>` that fills the row.
          <div
            key={row.id}
            role="tab"
            aria-selected={false}
            className="group relative inline-flex h-9 max-w-[220px] shrink-0 items-center rounded-t-lg bg-transparent text-xs font-semibold text-surface-500 dark:text-surface-500 hover:bg-surface-100/60 dark:hover:bg-surface-800/60 whitespace-nowrap transition-colors"
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
                // Capture the clicked tab's id BEFORE mutations so the
                // tab-order reconciliation effect can slot the new hold
                // (the parked old active cart) into this tab's index —
                // keeping its position stable instead of jumping to the
                // rightmost edge.
                lastClickedHeldRef.current = row.id;
                if (snapshot) {
                  if (cartItems.length > 0 || customer) holdMutation.mutate({ skipReset: true });
                  else void persistBlankTab();
                  restoreSnapshot(snapshot);
                  recallMutation.mutate({ id: row.id, skipRestore: true });
                } else {
                  // Snapshot couldn't parse — fall back to server recall so
                  // we still get the data even if the local cache row was
                  // tampered with.
                  if (cartItems.length > 0 || customer) holdMutation.mutate({ skipReset: true });
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
        {/* Active POS tab — outer DIV so the close-X is its own button next
            to the body button (no nested-button violation). Active tab also
            gets a close X (Chrome semantics: every tab is closable). On
            close: dump the active draft and snap to the gate; if held tabs
            exist the cashier can recall one to fill the slot. */}
        <div
          role="tab"
          aria-selected={!['held', 'refund', 'close-shift', 'receipt'].includes(mode)}
          className={cn(
            'group relative inline-flex h-9 max-w-[280px] shrink-0 items-center rounded-t-lg whitespace-nowrap transition-colors',
            !['held', 'refund', 'close-shift', 'receipt'].includes(mode)
              ? 'bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-50 shadow-[inset_0_2px_0_rgb(var(--primary-500)),_0_-1px_0_rgb(var(--primary-500))] ring-1 ring-surface-200/60 dark:ring-surface-700/60 font-bold'
              : 'bg-transparent text-surface-500 dark:text-surface-500 hover:bg-surface-100/60 dark:hover:bg-surface-800/60',
          )}
        >
          <button
            type="button"
            onClick={() => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate')}
            className="flex h-full min-w-0 flex-1 items-center gap-2 px-3 pr-1 text-xs font-semibold"
            title={`POS · ${title}`}
          >
            <span className="grid h-3.5 w-3.5 shrink-0 place-items-center rounded-[4px] bg-primary-500 dark:bg-primary-500 text-[8px] font-black text-on-primary">B</span>
            <span className="truncate">POS · {title}</span>
          </button>
          <button
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              const hasWork = cartItems.length > 0 || customer || walkInActive;
              if (hasWork && !window.confirm('Close this tab? In-flight cart + customer will be dropped.')) return;
              startNewSale();
            }}
            className="mr-1 grid h-5 w-5 shrink-0 place-items-center rounded text-surface-500 opacity-0 transition group-hover:opacity-100 focus:opacity-100 hover:bg-surface-200 dark:hover:bg-surface-700"
            title="Close tab"
            aria-label="Close tab"
          >
            <X className="h-3 w-3" />
          </button>
        </div>
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
            // Repair-intake state lives in `repairDraft`, not in the cart, so
            // the existing hold-or-blank branch silently nuked any in-flight
            // intake. Confirm before discarding so the tech can't lose the
            // device + issue picks they just made.
            const repairDirty = mode.startsWith('repair') && (
              !!repairDraft.deviceType
                || !!repairDraft.deviceName
                || !!repairDraft.deviceModelId
                || repairDraft.selectedProblems.length > 0
                || !!repairDraft.imei
                || !!repairDraft.serial
            );
            if (repairDirty) {
              const ok = window.confirm('Discard this in-progress repair intake to start a new sale? The cart side will still be parked, but the intake step picks will be lost.');
              if (!ok) return;
              setRepairDraft(DEFAULT_REPAIR_DRAFT);
            }
            if (cartItems.length > 0 || customer) {
              holdMutation.mutate(undefined);
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
        // Match AppShell `<Header>` padding (`px-4 sm:px-6`) so the in-body
        // topbar's back-arrow lines up with the tab strip's first tab —
        // previous `px-5` made the tabs sit a few pixels left of the body.
        'flex shrink-0 items-center gap-5 border-b border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-950 px-4 sm:px-6',
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
        {/* On `repair-category` (first wizard step) the topbar already shows
            the visible "Cancel intake" button, so a separate back chevron is
            redundant — both go to the same place. Hide the chevron there to
            kill the "three escape buttons" stack the user flagged. */}
        {(mode === 'sale' || mode === 'held' || mode === 'refund' || mode === 'close-shift' || (mode.startsWith('repair') && mode !== 'repair-category')) && (() => {
          const REPAIR_BACK: Record<string, PosMode> = {
            'repair-category': cartItems.length > 0 ? 'sale' : 'gate',
            'repair-device': 'repair-category',
            'repair-issue': 'repair-device',
            'repair-quote': 'repair-issue',
            'repair-deposit': 'repair-quote',
          };
          // Sale → home: park the in-flight sale as a held tab so the gate
          // shows up cleanly. Without parking, an auto-flip useEffect (which
          // exists to keep `mode` in sync with cart/customer state) bounces
          // straight back to `sale` — the user reported the flicker.
          // Empty sales just navigate to gate without spawning a tab.
          const back = mode === 'sale'
            ? () => {
                if (cartItems.length > 0 || customer || walkInActive) {
                  holdMutation.mutate(undefined);
                } else {
                  setMode('gate');
                }
              }
            : mode.startsWith('repair')
              ? () => setMode((REPAIR_BACK[mode] ?? (cartItems.length > 0 ? 'sale' : 'gate')) as PosMode)
              : () => setMode(cartItems.length > 0 || customer ? 'sale' : 'gate');
          return (
            <button
              type="button"
              onClick={back}
              className="inline-flex h-9 w-9 shrink-0 items-center justify-center rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40"
              aria-label={mode === 'sale' ? 'Home' : 'Back'}
              title={mode === 'sale' ? 'Back to home (esc)' : 'Back (esc)'}
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
              onClick={() => holdMutation.mutate(undefined)}
              disabled={cartItems.length === 0 && !customer}
              className="inline-flex items-center gap-1 rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-1 text-[11.5px] font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50"
            >
              <Pause className="h-3 w-3" /> Hold
              <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘H</span>
            </button>
          )}
          {mode.startsWith('tender') && (
            <>
              <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/15 px-3 py-1 text-[11.5px] font-bold text-amber-500 dark:text-amber-400">
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
            <span className="inline-flex items-center gap-1 rounded-full bg-amber-500/15 px-3 py-1 text-[11.5px] font-bold text-amber-500 dark:text-amber-400">
              <span className="h-2 w-2 rounded-full bg-amber-500 motion-safe:animate-pulse" /> Closing in progress
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
                <summary
                  aria-label="More POS actions"
                  title="More POS actions"
                  className="inline-flex h-7 w-7 cursor-pointer list-none items-center justify-center rounded-full border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 [&::-webkit-details-marker]:hidden"
                >
                  <span aria-hidden="true" className="text-[14px] leading-none">⋯</span>
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
          <ReceiptView
            sale={completedSale}
            onNext={startNewSale}
            // WEB-UIUX-433: Process Refund inline on the success screen so
            // the cashier doesn't have to nav Invoices → find → open → click
            // Credit Note (5 clicks for a 2-tap operation in-store).
            onProcessRefund={completedSale.invoiceId ? () => {
              setRefundInvoiceId(String(completedSale.invoiceId));
              setRefundSelections([]);
              setRefundMethod('original');
              setMode('refund');
            } : undefined}
          />
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
                  onCancelAppointment={cancelAppointment}
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
                  // Day view = vertical timeline of just today's slots —
                  // user feedback wanted "+1 view all" to drop into a
                  // chronological strip, not the busy month grid.
                  onViewCalendar={() => navigate('/calendar?view=day')}
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
                  onCustomItem={(prefillName?: string) => {
                    // Defensive coerce: the parent button onClick handlers
                    // upstream sometimes hand off a MouseEvent when wired
                    // directly. Force-string keeps `[object Object]` from
                    // ever leaking into the input. Always reset price too
                    // so a stale value from a prior open doesn't carry over.
                    setCustomName(typeof prefillName === 'string' ? prefillName : '');
                    setCustomPrice('');
                    setCustomItemOpen(true);
                  }}
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
                  onContinue={() => {
                    // Full path: Category → Device → Issue. Clear the skip flag
                    // so Back from Issue lands on Device, not Category.
                    setRepairDraft((prev) => ({ ...prev, skippedDevice: false }));
                    setMode('repair-device');
                  }}
                  onQuick={() => {
                    // Quick check-in: skip Device. Mark the draft so Back from
                    // Issue routes to Category, not the unvisited Device step.
                    setRepairDraft((prev) => ({ ...prev, skippedDevice: true }));
                    setMode('repair-issue');
                  }}
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
                  onBack={() => setMode(repairDraft.skippedDevice ? 'repair-category' : 'repair-device')}
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
                  // Save adds repair lines at FULL quote AND records the
                  // requested deposit + balance-owed note onto the ticket
                  // so the cashier (and the pickup desk) can see what was
                  // collected today vs. what's outstanding. Cart math still
                  // reflects the full quote — cashier can adjust the lines
                  // before tender if they only want to charge the deposit.
                  onSave={saveRepairWithDeposit}
                  onGoToStep={(target) => setMode(`repair-${target}` as any)}
                />
              )}

              {mode === 'tender-method' && (
                <TenderMethodView
                  totalCents={totals.totalCents}
                  paidLegs={paidLegs}
                  remainingCents={remainingCents}
                  blockchypConfigured={blockchypConfigured}
                  blockchypOffline={blockchypOffline}
                  blockchypOfflineReason={blockchypOfflineReason}
                  terminalName={terminalName}
                  customerId={customer?.id ?? null}
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
                  blockchypOffline={blockchypOffline}
                  blockchypOfflineReason={blockchypOfflineReason}
                  terminalName={terminalName}
                  customerId={customer?.id ?? null}
                  customerName={customer ? getCustomerName(customer) : null}
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
          onSaveTicket={submitCreateTicket}
          saveTicketBusy={processing}
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
            {/* WEB-UIUX-1245: only useful when the customer has a membership
                tier — otherwise there's nothing to stack against. Server
                still ignores the flag when no membership discount applies,
                so it's safe to leave the checkbox absent on non-member
                checkouts. */}
            {memberDiscountApplied && (
              <label className="flex items-start gap-2 rounded-lg border border-surface-200 bg-surface-50 p-3 text-sm dark:border-surface-700 dark:bg-surface-800/50">
                <input
                  type="checkbox"
                  checked={stackMembership}
                  onChange={(e) => setStackMembership(e.target.checked)}
                  className="mt-0.5"
                />
                <span>
                  <span className="font-medium">Stack with membership</span>
                  <span className="block text-xs text-surface-500 dark:text-surface-400 mt-0.5">
                    Default keeps the larger of manual vs membership discount. Tick to apply BOTH (server caps the sum at subtotal).
                  </span>
                </span>
              </label>
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
  setQuery,
  results,
  loading,
  appointments,
  appointmentsLoading,
  onSelectAppointment,
  onCancelAppointment,
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
  onCancelAppointment: (appointment: PosAppointment) => void;
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

  // When the cashier is typing a search, render the customer-matches dropdown
  // anchored to the topbar input with a backdrop-blur scrim over the gate
  // body. Page content stays in the DOM (so layout doesn't reflow) but is
  // visually de-emphasized while the dropdown is the focal point — standard
  // web search-suggestion pattern.
  const searching = !createCustomerOpen && query.trim().length >= 2;
  // Esc anywhere on the page clears the query so the cashier can dismiss the
  // dropdown without reaching for the mouse. Click-on-scrim does the same
  // (handler attached to the scrim div below).
  useEffect(() => {
    if (!searching) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        setQuery('');
      }
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [searching, setQuery]);
  return (
    <div className="relative flex min-h-full flex-col">
      {searching && (
        <>
          {/* Scrim sits over the page content (timeline, KPIs, ticket list)
              so the dropdown stands alone. backdrop-blur-sm lets the page
              content show through while pushing it visually behind. Clicking
              the scrim clears the query and dismisses the dropdown. */}
          <button
            type="button"
            aria-label="Dismiss customer search"
            onClick={() => setQuery('')}
            className="absolute inset-x-0 top-0 bottom-0 z-10 cursor-default bg-black/40 backdrop-blur-sm dark:bg-black/60"
          />
          <section className="relative z-20 mx-auto mt-3 w-full max-w-3xl px-6">
            <div className="overflow-hidden rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 shadow-2xl">
              <div className="flex items-center justify-between gap-3 border-b border-surface-200 dark:border-surface-700 px-4 py-3 font-mono text-[11px] uppercase tracking-[0.14em] text-surface-500">
                <span>Customer matches</span>
                {/* Fixed-width status slot so the heading row never reflows
                    between "searching" and the result count. Spinner stays
                    in the same position; count slides in once it lands. */}
                <span className="inline-flex h-4 min-w-[3ch] items-center justify-end tabular-nums text-surface-400">
                  {loading
                    ? <span aria-label="Searching" className="inline-block h-3 w-3 motion-safe:animate-spin rounded-full border-2 border-surface-300 border-t-primary-500" />
                    : results.length > 0 ? results.length : ''}
                </span>
              </div>
              {/* Reserve a min-height so the dropdown body doesn't pop on
                  the first keystroke when results haven't landed yet. */}
              <div className="min-h-[280px]">
                {loading && results.length === 0 && (
                  <div className="space-y-2 p-3">
                    {[0, 1, 2].map((i) => (
                      <div key={i} aria-hidden="true" className="h-14 motion-safe:animate-pulse rounded-lg bg-surface-100 dark:bg-surface-900" />
                    ))}
                  </div>
                )}
                {!loading && results.length === 0 && (
                  <div className="p-5 text-sm text-surface-700 dark:text-surface-400">
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
                  <div className="grid h-10 w-10 place-items-center rounded-full bg-cyan-500 font-bold text-cyan-950 dark:bg-cyan-400 dark:text-cyan-950">
                    {initials(getCustomerName(customer))}
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate font-semibold text-surface-900 dark:text-surface-50">{getCustomerName(customer)}</div>
                    <div className="truncate font-mono text-xs text-surface-500">{customer.phone || customer.mobile || customer.email || 'No contact saved'}</div>
                  </div>
                  {customer.group_name && (
                    <Pill tone="vip">
                      {customer.group_name}
                      {typeof customer.group_discount_pct === 'number' && customer.group_discount_pct > 0 && (
                        <span className="ml-1 opacity-80">· {customer.group_discount_pct}%</span>
                      )}
                    </Pill>
                  )}
                  <ChevronRight className="h-4 w-4 text-surface-400" />
                </button>
                ))}
              </div>
              <div className="flex gap-2 border-t border-surface-200 dark:border-surface-700 p-3">
                <button type="button" onClick={onNewCustomer} className="flex-1 rounded-lg bg-primary-500 dark:bg-primary-500 px-4 py-2 text-sm font-bold text-on-primary">
                  Create &ldquo;{query.trim()}&rdquo;
                </button>
                <button type="button" onClick={onWalkIn} className="flex-1 rounded-lg border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-bold text-surface-700 dark:text-surface-200">
                  Walk-in
                </button>
              </div>
            </div>
          </section>
        </>
      )}
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
                  <div className="h-12 motion-safe:animate-pulse rounded-lg bg-surface-900" />
                  <div className="h-12 motion-safe:animate-pulse rounded-lg bg-surface-900" />
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
                    const note = appointmentNote(appointment);
                    // Outer is now a div + role=button so the cancel-X can
                    // sit alongside the row body without nested-button
                    // violation. Body falls back to the device snippet
                    // (`note`) only — the status label that used to live
                    // here was already shown in the right-side pill, so
                    // dropping it kills the duplicate the user flagged.
                    return (
                      <div
                        key={appointment.id}
                        role="button"
                        tabIndex={0}
                        onClick={() => onSelectAppointment(appointment)}
                        onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onSelectAppointment(appointment); } }}
                        className={cn(
                          'group flex w-full cursor-pointer items-center gap-3 rounded-lg border-l-4 px-3 py-2.5 text-left transition hover:bg-surface-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-[#fdeed0]/40',
                          isPast ? 'border-l-rose-500 bg-rose-500/5' : 'border-l-[#fdeed0] bg-surface-900/50',
                        )}
                      >
                        <div className={cn('w-16 shrink-0 font-mono text-sm', isPast ? 'text-rose-400' : 'text-[#fdeed0]')}>
                          {formatTime(appointment.start_time)}
                        </div>
                        <div className="min-w-0 flex-1">
                          <div className="truncate text-sm font-semibold">{appointmentCustomerName(appointment)}</div>
                          {note && (
                            <div className="truncate text-[11.5px] text-surface-400">{note}</div>
                          )}
                        </div>
                        <span className={cn('shrink-0 rounded-full px-2 py-0.5 font-mono text-[10px] uppercase', isPast ? 'bg-rose-500/15 text-rose-300' : 'bg-[#fdeed0]/15 text-[#fdeed0]')}>
                          {appointmentStatusLabel(appointment, nowMs)}
                        </span>
                        {/* Cancel X — hover-revealed so the row stays calm
                            on idle. One click + confirm marks the
                            appointment cancelled server-side; tech doesn't
                            have to open the appointment detail to mark a
                            known no-show. */}
                        <button
                          type="button"
                          onClick={(e) => { e.stopPropagation(); onCancelAppointment(appointment); }}
                          className="shrink-0 rounded-md p-1 text-surface-500 opacity-0 transition group-hover:opacity-100 hover:bg-rose-500/15 hover:text-rose-400 focus:opacity-100"
                          aria-label="Cancel appointment"
                          title="Cancel appointment"
                        >
                          <X className="h-3.5 w-3.5" />
                        </button>
                      </div>
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

            {/* KPI strip — "Remaining today" was here too but the timeline
                header already broadcasts that count, so it'd be the same
                number twice. Pickup + open-tickets carry their own signal. */}
            <div className="grid grid-cols-2 gap-2 lg:grid-cols-1">
              <button
                type="button"
                onClick={onViewReadyPickup}
                aria-label={`Ready for pickup · ${readyTotal} tickets · view active tickets`}
                className="rounded-xl bg-surface-100 dark:bg-surface-900 p-3 text-left ring-1 ring-inset ring-surface-200 hover:ring-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 dark:ring-surface-800 dark:hover:ring-primary-500/40"
              >
                <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500">Ready for pickup</div>
                <div className="mt-1 font-display text-3xl text-surface-900 dark:text-surface-50">{readyTotal}</div>
                <div className="text-[11px] text-surface-500">awaiting customer</div>
              </button>
              <button
                type="button"
                onClick={onViewReadyPickup}
                aria-label={`In progress · ${otherTotal} tickets · view active tickets`}
                className="rounded-xl bg-surface-100 dark:bg-surface-900 p-3 text-left ring-1 ring-inset ring-surface-200 hover:ring-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 dark:ring-surface-800 dark:hover:ring-primary-500/40"
              >
                <div className="font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500">In progress</div>
                <div className="mt-1 font-display text-3xl text-surface-900 dark:text-surface-50">{otherTotal}</div>
                <div className="text-[11px] text-surface-500">on the bench</div>
              </button>
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

      {createCustomerOpen && (
        <InlineCreateCustomerPanel
          draft={createCustomerDraft}
          setDraft={setCreateCustomerDraft}
          creating={creatingCustomer}
          onSubmit={onSubmitCreateCustomer}
          onCancel={onCancelCreateCustomer}
          onWalkIn={onWalkIn}
        />
      )}

      {/* Two-section gate feed:
            1. Ready for pickup — capped at ~22vh (≈ 1/5 of screen) with
               internal scroll, so a busy day doesn't bury everything else.
            2. In progress — the rest of the active queue. Larger surface
               since it's where the day's work actually lives.
          Both share the same row layout so the eye scans cleanly across
          the boundary. */}
      <section className="px-6 pb-6 space-y-3">
        {/* Bare header — counts live in the section subheaders ("Ready for
            pickup · N", "In progress · N") + the KPI strip above, so the
            old "Current open tickets · 34 · 10 ready for pickup" was the
            same number twice over. Just label the band + offer the link. */}
        <div className="flex items-center gap-3">
          <div className="font-mono text-[11px] uppercase tracking-[0.14em] text-surface-900 dark:text-surface-500">
            {readyPickupLoading ? 'Open tickets · loading' : 'Open tickets'}
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
          {(() => {
            // Cap each section so the gate doesn't become a 30-row scroll.
            // Cashier wants a quick glance at the freshest items, then a
            // single jump to the full active-tickets view if they need more.
            const READY_PREVIEW_LIMIT = 3;
            const OTHER_PREVIEW_LIMIT = 5;
            const readyPreview = readyTickets.slice(0, READY_PREVIEW_LIMIT);
            const otherPreview = otherTickets.slice(0, OTHER_PREVIEW_LIMIT);
            const readyHidden = Math.max(0, readyTotal - readyPreview.length);
            const otherHidden = Math.max(0, otherTotal - otherPreview.length);
            return (
              <>
                {readyPreview.length > 0 && (
                  <>
                    <div className="bg-surface-50 dark:bg-surface-900 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.14em] text-emerald-400 border-b border-surface-200 dark:border-surface-700">
                      Ready for pickup · {readyTotal}
                    </div>
                    {readyPreview.map((ticket) => (
                      <button
                        key={ticket.id}
                        type="button"
                        onClick={() => onOpenReadyPickup(ticket)}
                        className="grid w-full grid-cols-[120px_70px_180px_minmax(0,1fr)_110px_90px_70px] items-center gap-3 border-b border-surface-200 dark:border-surface-700 px-4 py-2.5 text-left text-sm hover:bg-surface-100 dark:hover:bg-surface-700"
                      >
                        <span className="rounded-full bg-emerald-500/15 px-2 py-1 text-center font-mono text-[10px] font-bold uppercase text-emerald-400">✓ ready</span>
                        <span className="font-mono text-xs text-surface-400">#{ticket.order_id}</span>
                        <span className="truncate font-semibold text-surface-900 dark:text-surface-100">{ticket.customerName}{ticket.customerGroup ? <span className="ml-2 rounded-full bg-burgundy-light/15 px-2 py-0.5 text-[9.5px] font-bold text-rose-500">{ticket.customerGroup}</span> : null}</span>
                        <span className="truncate text-xs text-surface-600 dark:text-surface-300">{ticket.itemSummary}</span>
                        <span className="font-mono text-xs text-surface-900 dark:text-surface-500">{ticket.progressLabel}</span>
                        <span className="text-right font-mono text-xs text-primary-700 dark:text-primary-500">{formatCurrency(ticket.total)}</span>
                        <span className="text-right text-xs font-semibold text-cyan-500 dark:text-cyan-400">Open →</span>
                      </button>
                    ))}
                    {readyHidden > 0 && (
                      <button
                        type="button"
                        onClick={onViewReadyPickup}
                        className="flex w-full items-center justify-center gap-2 border-b border-surface-200 px-4 py-2 text-xs font-semibold text-primary-700 hover:bg-surface-100 dark:border-surface-700 dark:text-primary-500 dark:hover:bg-surface-700"
                      >
                        + {readyHidden} more ready · view all
                      </button>
                    )}
                  </>
                )}
                {otherPreview.length > 0 && (
                  <>
                    <div className="bg-surface-50 dark:bg-surface-900 px-4 py-2 font-mono text-[10px] uppercase tracking-[0.14em] text-surface-500 border-b border-surface-200 dark:border-surface-700">
                      In progress · {otherTotal}
                    </div>
                    {otherPreview.map((ticket, idx) => {
                      const isLast = idx === otherPreview.length - 1 && otherHidden === 0;
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
                          <span className="truncate font-semibold text-surface-900 dark:text-surface-100">{ticket.customerName}{ticket.customerGroup ? <span className="ml-2 rounded-full bg-burgundy-light/15 px-2 py-0.5 text-[9.5px] font-bold text-rose-500">{ticket.customerGroup}</span> : null}</span>
                          <span className="truncate text-xs text-surface-600 dark:text-surface-300">{ticket.itemSummary}</span>
                          <span className="font-mono text-xs text-surface-900 dark:text-surface-500">{ticket.progressLabel}</span>
                          <span className="text-right font-mono text-xs text-primary-700 dark:text-primary-500">{formatCurrency(ticket.total)}</span>
                          <span className="text-right text-xs font-semibold text-cyan-500 dark:text-cyan-400">Open →</span>
                        </button>
                      );
                    })}
                    {otherHidden > 0 && (
                      <button
                        type="button"
                        onClick={onViewReadyPickup}
                        className="flex w-full items-center justify-center gap-2 px-4 py-2 text-xs font-semibold text-primary-700 hover:bg-surface-100 dark:text-primary-500 dark:hover:bg-surface-700"
                      >
                        + {otherHidden} more in progress · view all
                      </button>
                    )}
                  </>
                )}
              </>
            );
          })()}
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
                  onChange={(event) => updateDraft({ phone: formatPhoneAsYouType(event.target.value) })}
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
  onCustomItem: (prefillName?: string) => void;
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
            onClick={() => onCustomItem()}
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
          <button type="button" className="rounded-lg border border-cyan-400/40 bg-cyan-500/10 p-4 text-left xl:col-span-2" onClick={() => onCustomItem()}>
            <Star className="h-5 w-5 text-cyan-700 dark:text-cyan-400" />
            <div className="mt-3 font-semibold">{getCustomerName(customer).split(' ')[0]} is {customer.group_name} · keep the streak</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Add a qualifying accessory before tender to lock in the next-tier bonus.</div>
          </button>
        )}
        {loading && Array.from({ length: 7 }).map((_, index) => (
          <div key={index} className="h-36 motion-safe:animate-pulse rounded-lg bg-surface-100 dark:bg-surface-900" />
        ))}
        {!loading && products.length === 0 && (
          <Section className="col-span-full p-8 text-center">
            <Package className="mx-auto h-8 w-8 text-surface-400" />
            <div className="mt-3 font-semibold">No catalog items found</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">Scan again, or quick-add what the cashier typed.</div>
            {/* Quick-add: drop the typed query into the Custom Item modal
                pre-filled as the name so the cashier doesn't retype it. The
                cart picks the price up from the modal — keeps the empty-
                state clickable instead of just text. */}
            <div className="mt-4 flex flex-wrap items-center justify-center gap-2">
              <button
                type="button"
                onClick={() => onCustomItem(productSearch.trim() || undefined)}
                className={cn(primaryButton, 'inline-flex items-center gap-1.5')}
              >
                <PackagePlus className="h-4 w-4" />
                {productSearch.trim() ? `+ Quick-add "${productSearch.trim()}"` : '+ Quick-add custom item'}
              </button>
            </div>
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
                <span className="absolute right-2 top-2 inline-flex items-center gap-1 rounded-full bg-emerald-500/15 px-2 py-0.5 font-mono text-[10px] font-bold uppercase text-emerald-700 dark:bg-emerald-500/15 dark:text-emerald-400">
                  ✓ IN CART
                </span>
              )}
              <Package className="h-6 w-6 text-surface-400" />
              <div className="mt-2 line-clamp-2 min-h-10 text-[13px] font-semibold leading-snug" title={product.sku ? `${product.name} · ${product.sku}` : product.name}>{product.name}</div>
              <div className="mt-auto flex items-baseline justify-between pt-2">
                <span className="font-display text-[22px] text-primary-700 dark:text-primary-500">{formatCurrency(Number(product.retail_price ?? product.price ?? 0))}</span>
                <span className={cn(
                  'font-mono text-[10.5px] uppercase tracking-wider',
                  out ? 'text-red-500' : Number(product.in_stock ?? 0) <= 2 && product.item_type !== 'service' ? 'text-amber-500 dark:text-amber-400' : 'text-emerald-600 dark:text-emerald-400',
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

  // For repairs, the chip shows total (labor − discount + parts) but the
  // INPUT pre-fills laborPrice only — clarify in the title so the cashier
  // doesn't think they're overriding the whole total.
  const titleHint = item.type === 'repair'
    ? 'Click to edit base labor price · parts and line discount stay'
    : 'Click to edit unit price';
  return (
    <button
      type="button"
      disabled={locked}
      onClick={() => setEditing(true)}
      title={titleHint}
      aria-label={`Edit price · current ${formatCurrency(lineAmount(item))}`}
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
  onSaveTicket,
  saveTicketBusy,
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
  /** Save the cart as a ticket WITHOUT processing payment. Shown only when
   * the cart has at least one repair line. */
  onSaveTicket: () => void;
  saveTicketBusy: boolean;
}) {
  const paid = paidLegs.reduce((sum, leg) => sum + leg.amount, 0);
  // Mockup format: "Subtotal · 3 lines" (count) + "Tax (8.875%)" (rate %).
  // taxRate comes in as a fraction (e.g. 0.08875); render with up to 3
  // decimals so "8.875%" not "8.9%".
  const lineCount = cartItems.reduce((sum, item) => sum + (item.type === 'product' || item.type === 'misc' ? item.quantity : 1), 0);
  const taxPct = (taxRate * 100).toFixed(3).replace(/\.?0+$/, '');
  const hasRepair = cartItems.some((item) => item.type === 'repair');
  // "Add part to repair" sub-row state. Scoped to CartPanel since the entry
  // point lives here and the commit only needs `onUpdateLine`. The empty
  // sub-row itself is render-only — it doesn't sit in cartItems and never
  // ships to the receipt unless the tech actually adds a part.
  const [partModal, setPartModal] = useState<{ repairId: string; name: string; price: string } | null>(null);
  const partModalRepair = partModal ? cartItems.find((c) => c.id === partModal.repairId && c.type === 'repair') as RepairCartItem | undefined : undefined;
  const commitPart = () => {
    if (!partModal || !partModalRepair) return;
    const trimmed = partModal.name.trim();
    const priceNum = Number(partModal.price);
    if (!trimmed) { toast.error('Part name required'); return; }
    if (!Number.isFinite(priceNum) || priceNum < 0) { toast.error('Enter a valid price'); return; }
    // Default ad-hoc parts to taxable=true so they enter the tax base in
    // totals.ts; previous default (false) silently under-collected sales tax
    // on every cart-added part regardless of shop settings.
    const newPart: PartEntry = {
      _key: `part-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      inventory_item_id: 0,
      name: trimmed,
      sku: null,
      quantity: 1,
      price: priceNum,
      taxable: true,
      status: 'available',
    };
    onUpdateLine(partModalRepair.id, { parts: [...partModalRepair.parts, newPart] } as Partial<CartItem>);
    setPartModal(null);
  };
  return (
    <aside className={cn('flex min-h-0 flex-col border-l border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800', locked && 'opacity-90')}>
      {/* Mockup cart toolbar: just `‹ 🛒 CART`. Status pills (locked /
          asleep) clutter the header on every refresh; the locked + asleep
          states already read from the dimmed body, sleeping illustration,
          and disabled Charge button. The locked pill is kept because
          it's a critical "hands off — tender in flight" cue. */}
      <div className="flex h-[44px] items-center gap-2 border-b border-surface-200 dark:border-surface-700 px-4 font-mono text-[11px] font-semibold uppercase tracking-[0.14em] text-surface-600 dark:text-surface-300">
        <ShoppingCart className="h-4 w-4" />
        Cart
        {locked && (
          <span
            title="Cart locked during payment — press Esc or Back to cancel"
            className="ml-auto inline-flex items-center gap-1 rounded-full bg-amber-500/15 px-2 py-0.5 text-[10px] font-semibold text-amber-600 dark:text-amber-400"
          >
            <Lock className="h-3 w-3" /> locked
          </span>
        )}
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
          <button
            type="button"
            onClick={onSwapCustomer}
            aria-label={`Swap customer (currently ${getCustomerName(customer) || 'walk-in'})`}
            className="flex items-start gap-3 border-b border-surface-200 dark:border-surface-700 p-4 text-left hover:bg-surface-100 dark:hover:bg-surface-900"
          >
            <div className="grid h-11 w-11 shrink-0 place-items-center rounded-full bg-cyan-500 dark:bg-cyan-400 font-bold text-cyan-950">
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
            <span aria-hidden="true" className="text-surface-400 dark:text-surface-500">⋯</span>
          </button>
          <div className="min-h-0 flex-1 overflow-auto p-3">
            {cartItems.length === 0 ? (
              <div className="flex flex-col items-center gap-3 rounded-lg border border-dashed border-surface-300 dark:border-surface-700 p-6 text-center text-sm text-surface-700 dark:text-surface-400">
                <ShoppingCart className="h-6 w-6 text-surface-400" aria-hidden="true" />
                <span>Scan or add an item to start the cart.</span>
                <button
                  type="button"
                  onClick={() => {
                    // Focus the catalog search input in the left panel so the
                    // cashier can start typing without reaching for the mouse.
                    const el = document.querySelector<HTMLInputElement>('input[placeholder*="SKU" i], input[placeholder*="catalog" i]');
                    el?.focus();
                  }}
                  className="inline-flex items-center gap-1.5 rounded-md border border-surface-200 bg-white px-3 py-1.5 text-xs font-semibold text-surface-700 hover:border-primary-500 hover:text-primary-700 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:border-primary-500/40"
                >
                  <Search className="h-3.5 w-3.5" aria-hidden="true" />
                  Browse catalog
                  <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1 font-mono text-[9px] text-surface-400">⌘B</span>
                </button>
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
                    {/* Repair sub-rows: each attached part as a small line, plus
                        an empty "+ Add part to repair" CTA at the bottom. The
                        CTA is render-only — never enters cartItems or the
                        receipt unless the tech actually adds a part. Existing
                        parts go on the receipt as part of the repair line. */}
                    {item.type === 'repair' && (
                      <div className="mt-2 ml-10 space-y-1 border-l border-dashed border-surface-300 pl-3 dark:border-surface-700">
                        {item.parts.map((p) => (
                          <div key={p._key} className="flex items-center justify-between gap-2 text-[12px]">
                            <span className="min-w-0 flex-1 truncate text-surface-700 dark:text-surface-300">
                              ↳ {p.name}
                              {p.quantity > 1 && <span className="ml-1 font-mono text-surface-500">×{p.quantity}</span>}
                            </span>
                            <span className="font-mono text-surface-700 dark:text-surface-300">{formatCurrency(p.price * p.quantity)}</span>
                            <button
                              type="button"
                              onClick={() => onUpdateLine(item.id, { parts: item.parts.filter((x) => x._key !== p._key) } as Partial<CartItem>)}
                              disabled={locked}
                              className="rounded p-0.5 text-red-500 opacity-0 transition-opacity group-hover:opacity-100 hover:bg-red-50 dark:hover:bg-red-950/40"
                              aria-label={`Remove ${p.name}`}
                            >
                              <X className="h-3 w-3" />
                            </button>
                          </div>
                        ))}
                        <button
                          type="button"
                          onClick={() => setPartModal({ repairId: item.id, name: '', price: '' })}
                          disabled={locked}
                          className="flex w-full items-center justify-center gap-1.5 rounded border border-dashed border-surface-300 px-2 py-1 text-[11.5px] text-surface-500 hover:border-primary-500 hover:text-primary-700 dark:border-surface-700 dark:hover:border-primary-500/50 dark:hover:text-[#fdeed0]"
                        >
                          <Plus className="h-3 w-3" />
                          Add part to repair?
                        </button>
                      </div>
                    )}
                  </div>
                ))}
              </div>
            )}
          </div>
          {/* Applied-discount status row. The "open discount modal" trigger
              lives once in the footer grid below — no duplicate prompt. */}
          {totals.discountAmount > 0 && (
            <button
              type="button"
              onClick={onDiscount}
              disabled={locked}
              className="flex w-full items-center gap-2 border-y border-emerald-500/30 bg-emerald-500/10 px-4 py-2.5 text-left text-sm font-semibold text-emerald-700 dark:text-emerald-400"
            >
              <Tag className="h-4 w-4" />
              <span className="truncate font-mono uppercase tracking-wider">
                {(customer?.group_name || 'discount').toString().toUpperCase()}
              </span>
              <span className="ml-auto rounded-full bg-emerald-500/20 px-2 py-0.5 font-mono text-[10px] uppercase tracking-wider">
                applied
              </span>
            </button>
          )}
          <div className="border-t border-surface-200 dark:border-surface-700 p-4">
            <div className="space-y-1.5 font-mono text-[12.5px]">
              <div className="flex justify-between">
                <span className="text-surface-900 dark:text-surface-500">Subtotal{lineCount > 0 ? ` · ${lineCount} line${lineCount === 1 ? '' : 's'}` : ''}</span>
                <span>{formatCurrency(totals.subtotal)}</span>
              </div>
              {totals.discountAmount > 0 && (
                <div className="flex justify-between text-emerald-700 dark:text-emerald-400">
                  <span>Discount</span>
                  <span>-{formatCurrency(totals.discountAmount)}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-surface-900 dark:text-surface-500">Tax{taxPct ? ` (${taxPct}%)` : ''}</span>
                <span>{formatCurrency(totals.tax)}</span>
              </div>
              {paid > 0 && (
                <div className="flex justify-between text-cyan-700 dark:text-cyan-400">
                  <span>Paid</span>
                  <span>-{formatCurrency(paid)}</span>
                </div>
              )}
              <div className="mt-2 flex items-end justify-between border-t border-surface-200 dark:border-surface-700 pt-3">
                <span className="font-sans text-[10.5px] uppercase tracking-[0.12em] text-surface-500">Due now</span>
                <span className="font-display text-4xl text-primary-700 dark:text-primary-500 tabular-nums">{formatCurrency(Math.max(0, totals.total - paid))}</span>
              </div>
            </div>
            {/* Footer action stack: Discount on its own row. When a repair
                line is present we surface a second primary path — "Save
                ticket" — alongside Charge so the cashier can create the
                server-side ticket WITHOUT collecting payment now. Without
                this, the only commit was Charge → tender, which made it
                unclear when the ticket was actually persisted. */}
            <div className="mt-4 flex flex-col gap-2">
              <button
                type="button"
                onClick={onDiscount}
                disabled={locked}
                className="inline-flex items-center justify-center gap-1.5 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-xs font-semibold text-surface-700 dark:text-surface-200 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50"
              >
                <Tag className="h-3.5 w-3.5" /> Discount
                <span className="ml-1 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[9px] text-surface-400">⌘D</span>
              </button>
              {hasRepair && (
                <button
                  type="button"
                  onClick={onSaveTicket}
                  disabled={locked || saveTicketBusy || paidLegs.length > 0}
                  className="inline-flex items-center justify-center gap-2 rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2.5 text-sm font-semibold text-surface-800 dark:text-surface-100 hover:border-primary-500 dark:hover:border-primary-500/40 disabled:opacity-50"
                  title="Create the repair ticket now and collect payment later at pickup"
                >
                  <Wrench className="h-4 w-4" />
                  {saveTicketBusy ? 'Saving…' : 'Save ticket · pay later'}
                </button>
              )}
              <button
                type="button"
                onClick={onTender}
                disabled={locked || cartItems.length === 0}
                className={cn(primaryButton, 'w-full py-3 text-base')}
              >
                <CreditCard className="h-4 w-4" />
                Charge {formatCurrency(Math.max(0, totals.total - paid))}
                <span className="ml-2 rounded border border-black/15 bg-black/5 px-1.5 font-mono text-[10px]">⌘↵</span>
              </button>
              {hasRepair && (
                <p className="text-center text-[10.5px] text-surface-500 dark:text-surface-400">
                  Save ticket: creates ticket, no payment. Charge: creates ticket and takes payment now.
                </p>
              )}
            </div>
          </div>
        </>
      )}
      {partModal && partModalRepair && (
        <Modal
          title={`Add part to ${partModalRepair.serviceName}`}
          onClose={() => setPartModal(null)}
          footer={
            <div className="flex justify-end gap-2">
              <button type="button" className={ghostButton} onClick={() => setPartModal(null)}>Cancel</button>
              <button type="button" className={primaryButton} onClick={commitPart}>Add part</button>
            </div>
          }
        >
          <div className="grid gap-3">
            <div className="text-xs text-surface-500">
              Attaches to <span className="font-semibold text-surface-700 dark:text-surface-300">{partModalRepair.serviceName}</span>
              {partModalRepair.device.device_name && <> · {partModalRepair.device.device_name}</>}
            </div>
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Part name</span>
              <input
                value={partModal.name}
                onChange={(e) => setPartModal({ ...partModal, name: e.target.value })}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); commitPart(); } }}
                className={inputClass}
                placeholder="e.g. iPhone 13 battery cell"
                autoFocus
              />
            </label>
            <label className="block">
              <span className="mb-1 block text-sm font-semibold">Price</span>
              <input
                value={partModal.price}
                onChange={(e) => setPartModal({ ...partModal, price: e.target.value })}
                onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); commitPart(); } }}
                className={inputClass}
                inputMode="decimal"
                placeholder="0.00"
              />
            </label>
          </div>
        </Modal>
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
function RepairCategoryStep({ draft, setDraft, onContinue, onQuick }: {
  draft: RepairDraft;
  setDraft: React.Dispatch<React.SetStateAction<RepairDraft>>;
  onCancel: () => void;
  onContinue: () => void;
  onQuick: () => void;
}) {
  // Footer Continue + footer Cancel were both redundant on this step:
  // tile click auto-advances, and the topbar already shows "Cancel intake".
  // Dropping the footer also resolves the "three back buttons" stack on
  // step 1 (back chevron + Cancel intake + footer Cancel).
  return (
    <div className="mx-auto flex h-full max-w-5xl flex-col gap-3 px-4 pt-3 pb-3">
      {/* Category is the first step — no past steps to jump to. Stepper still
          renders so the user sees where they are in the 5-step flow. */}
      <Stepper step="category" />
      <div className="flex min-h-0 flex-1 flex-col gap-3">
        <div>
          <div className="font-mono text-[11px] uppercase tracking-[0.16em] text-surface-500">Pick a category</div>
          <div className="mt-0.5 text-xs text-surface-600 dark:text-surface-400">
            Tap a tile to continue · <span className="font-mono">Quick check-in</span> skips the device picker.
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
                  if (isQuick) {
                    // Quick check-in is "log it now, identify later" — collapse
                    // the device into the Other catalog category (which has
                    // generic services seeded) and label the device "Walk-in
                    // device" so the issue step doesn't render an empty
                    // catalog. The cashier can still rename later from the
                    // ticket detail.
                    setDraft((prev) => ({
                      ...prev,
                      deviceType: 'other',
                      deviceName: 'Walk-in device',
                      deviceModelId: null,
                    }));
                    onQuick();
                    return;
                  }
                  setDraft((prev) => ({ ...prev, deviceType: tile.value, deviceName: '' }));
                  onContinue();
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
    </div>
  );
}

// "Pixel 10" → { mfg: <Google>, strippedName: "Pixel 10" }. "Apple iPhone 18"
// → { mfg: <Apple>, strippedName: "iPhone 18" }. Returns null if nothing
// matches — the modal then leaves the manufacturer dropdown empty.
function detectManufacturer(input: string, manufacturers: Array<{ id: number; name: string }>) {
  const q = input.trim();
  if (!q) return null;
  for (const m of manufacturers) {
    const prefix = `${m.name} `.toLowerCase();
    if (q.toLowerCase().startsWith(prefix)) {
      return { mfg: m, strippedName: q.slice(prefix.length).trim() };
    }
  }
  // Sub-brand → manufacturer hints. Catches the common case where the cashier
  // types only the model line ("Pixel 10", "iPhone 18 Pro") without prefixing
  // the brand.
  const HINTS: Array<[RegExp, string]> = [
    [/^(iphone|ipad|imac|macbook|mac\s|mac\s?mini|mac\s?studio|apple\s?watch|airpods)\b/i, 'Apple'],
    [/^(galaxy|note\s?\d)\b/i, 'Samsung'],
    [/^pixel\b/i, 'Google'],
    [/^nord\b/i, 'OnePlus'],
    [/^(rog|zenfone|zenbook|vivobook)\b/i, 'Asus'],
    [/^(thinkpad|yoga|legion|ideapad)\b/i, 'Lenovo'],
    [/^(latitude|inspiron|optiplex|xps|alienware)\b/i, 'Dell'],
    [/^(elitebook|pavilion|envy|spectre|omen)\b/i, 'HP'],
    [/^(redmi|poco|mi\s)\b/i, 'Xiaomi'],
    [/^(switch|joy-?con)\b/i, 'Nintendo'],
    [/^(ps\d|playstation)\b/i, 'PlayStation'],
    [/^xbox\b/i, 'Xbox'],
    [/^steam\s?deck\b/i, 'Steam'],
  ];
  for (const [re, mfgName] of HINTS) {
    if (re.test(q)) {
      const m = manufacturers.find((x) => x.name.toLowerCase() === mfgName.toLowerCase());
      if (m) return { mfg: m, strippedName: q };
    }
  }
  return null;
}

/**
 * AddDeviceModal — surfaced from the Device step when search returns no
 * matches. Asks for the two facts the cashier didn't supply by typing alone:
 *
 *   1. Manufacturer (FK to manufacturers; required so the catalog stays clean)
 *   2. Persistence — "Save to catalog" vs one-time use
 *
 * Save = POST /catalog/devices (admin-only on the server). On 401/403 we fall
 * back to one-time use silently so cashiers without admin rights aren't
 * blocked. Either path ends with `onPicked(name, id|null)` so the wizard can
 * advance.
 */
function AddDeviceModal({
  initialName,
  category,
  onClose,
  onPicked,
}: {
  initialName: string;
  category: string;
  onClose: () => void;
  onPicked: (deviceName: string, deviceModelId: number | null) => void;
}) {
  const queryClient = useQueryClient();
  const mfgQuery = useQuery({
    queryKey: ['catalog-manufacturers-all'],
    queryFn: () => api.get<{ data: Array<{ id: number; name: string }> }>('/catalog/manufacturers'),
    staleTime: 5 * 60_000,
  });
  const manufacturers = ((mfgQuery.data?.data as any)?.data ?? mfgQuery.data?.data ?? []) as Array<{ id: number; name: string }>;

  const [mfgId, setMfgId] = useState<number | null>(null);
  const [modelName, setModelName] = useState(initialName.trim());
  const [year, setYear] = useState<string>(String(new Date().getFullYear()));
  const [save, setSave] = useState(true);
  const detectedRef = useRef(false);

  // Auto-detect runs once when the manufacturer list arrives — splits the
  // typed query into mfg + model so the cashier doesn't repeat the brand.
  useEffect(() => {
    if (detectedRef.current) return;
    if (manufacturers.length === 0) return;
    const detected = detectManufacturer(initialName, manufacturers);
    if (detected) {
      setMfgId(detected.mfg.id);
      setModelName(detected.strippedName);
    }
    detectedRef.current = true;
  }, [manufacturers, initialName]);

  const composeFullName = (mfgName: string, name: string) => `${mfgName} ${name}`.replace(/\s+/g, ' ').trim();

  const createMutation = useMutation({
    mutationFn: () =>
      api.post<{ success: boolean; data: { id: number; name: string; manufacturer_name: string } }>(
        '/catalog/devices',
        {
          manufacturer_id: mfgId,
          name: modelName.trim(),
          category,
          release_year: Number(year) || null,
          is_popular: 0,
        },
      ),
    onSuccess: (res) => {
      const created = (res.data as any).data;
      const fullName = composeFullName(created.manufacturer_name ?? '', created.name);
      toast.success(`Saved ${fullName} to catalog`);
      queryClient.invalidateQueries({ queryKey: ['pos-popular-devices'] });
      queryClient.invalidateQueries({ queryKey: ['pos-device-search'] });
      queryClient.invalidateQueries({ queryKey: ['pos-problem-matrix'] });
      onPicked(fullName, created.id);
      onClose();
    },
    onError: (err: any) => {
      const status = err?.response?.status;
      if (status === 401 || status === 403) {
        // Cashier without admin perms — fall back to one-time so the ticket
        // can still progress.
        const mfgName = manufacturers.find((m) => m.id === mfgId)?.name ?? '';
        const fullName = composeFullName(mfgName, modelName.trim());
        toast(`Used ${fullName} for this ticket only — ask an admin to add it to the catalog.`);
        onPicked(fullName, null);
        onClose();
        return;
      }
      toast.error(err?.response?.data?.message || 'Could not save device');
    },
  });

  const handleSubmit = () => {
    const trimmed = modelName.trim();
    if (!mfgId) { toast.error('Pick a manufacturer'); return; }
    if (!trimmed) { toast.error('Device name is required'); return; }
    if (save) {
      createMutation.mutate();
    } else {
      const mfgName = manufacturers.find((m) => m.id === mfgId)?.name ?? '';
      onPicked(composeFullName(mfgName, trimmed), null);
      onClose();
    }
  };

  const submitLabel = save ? 'Save & use' : 'Use this once';
  return (
    <Modal
      title="Add new device"
      onClose={onClose}
      footer={
        <div className="flex items-center justify-end gap-2">
          <button type="button" className={ghostButton} onClick={onClose}>Cancel</button>
          <button
            type="button"
            className={primaryButton}
            onClick={handleSubmit}
            disabled={createMutation.isPending}
          >
            {createMutation.isPending ? 'Saving…' : submitLabel}
          </button>
        </div>
      }
    >
      <div className="grid gap-3">
        <label className="block">
          <span className="mb-1 block font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">Manufacturer</span>
          <select
            className={inputClass}
            value={mfgId ?? ''}
            onChange={(e) => setMfgId(e.target.value ? Number(e.target.value) : null)}
          >
            <option value="">— Select —</option>
            {manufacturers.map((m) => (
              <option key={m.id} value={m.id}>{m.name}</option>
            ))}
          </select>
        </label>
        <label className="block">
          <span className="mb-1 block font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">Model name</span>
          <input
            className={inputClass}
            value={modelName}
            onChange={(e) => setModelName(e.target.value)}
            placeholder="e.g. Pixel 10 Pro"
            autoFocus
          />
          <span className="mt-1 block text-[11px] text-surface-500">No need to repeat the brand — it's added automatically.</span>
        </label>
        <label className="block">
          <span className="mb-1 block font-mono text-[10.5px] uppercase tracking-[0.14em] text-surface-500">Release year</span>
          <input
            type="number"
            inputMode="numeric"
            className={cn(inputClass, 'w-32')}
            value={year}
            onChange={(e) => setYear(e.target.value)}
            min={2010}
            max={new Date().getFullYear() + 1}
          />
          <span className="mt-1 block text-[11px] text-surface-500">Used to pick the default pricing tier.</span>
        </label>
        <label className="mt-2 flex cursor-pointer items-start gap-2 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          <input
            type="checkbox"
            className="mt-0.5"
            checked={save}
            onChange={(e) => setSave(e.target.checked)}
          />
          <span>
            <span className="block text-sm font-semibold text-surface-900 dark:text-surface-100">Save to catalog</span>
            <span className="block text-xs text-surface-500">Next intake will find it in search and reuse the same prices. Untick for one-time devices.</span>
          </span>
        </label>
      </div>
    </Modal>
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
  const [addModalQuery, setAddModalQuery] = useState<string | null>(null);
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
                    onClick={() => setAddModalQuery(effectiveQuery)}
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
      <WizardFooter
        onBack={onBack}
        backLabel="Back"
        onContinue={onContinue}
        continueLabel="Pick issues →"
        continueDisabled={!draft.deviceName.trim()}
      />
      {addModalQuery !== null && (
        <AddDeviceModal
          initialName={addModalQuery}
          category={category}
          onClose={() => setAddModalQuery(null)}
          onPicked={(name, id) => {
            pick(name, id);
            setQuery('');
            setMfgFilter('');
          }}
        />
      )}
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
  // One row at a time — clicking the price chip on a different tile bumps the
  // open editor to that tile so the cashier can't accidentally enter a price
  // for the wrong service.
  const [editingPrice, setEditingPrice] = useState<{ serviceId: number; value: string } | null>(null);

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

  const queryClient = useQueryClient();
  // Persists the per-device labor price to /repair-pricing/matrix so the next
  // intake for the same device + service combo prefills with this price
  // instead of falling back to "Set price". Silent on 401/403 (cashiers
  // without admin perms still get the local-only override) and silent on
  // success too — the chip already updated, no need for a toast.
  const persistMatrixPrice = useMutation({
    mutationFn: ({ deviceModelId, repairServiceId, dollars }: { deviceModelId: number; repairServiceId: number; dollars: number }) =>
      repairPricingApi.updateMatrix({
        updates: [{
          device_model_id: deviceModelId,
          repair_service_id: repairServiceId,
          labor_price: dollars,
        }],
      } as any),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['pos-problem-matrix'] });
    },
    onError: (err: any) => {
      const status = err?.response?.status;
      if (status === 401 || status === 403) return; // cashier without perms — local override stands
      toast.error(err?.response?.data?.message || 'Saved locally — could not update catalog');
    },
  });

  // Commit the price typed in the inline editor. Selects the problem if it
  // wasn't already in the cart so the cashier doesn't have to take a second
  // tap to add it after pricing it. Also persists to the catalog when the
  // device is a known model — next intake of the same device + service
  // shows this price by default instead of "Set price".
  const commitInlinePrice = (row: typeof rows[number], rawValue: string) => {
    const trimmed = rawValue.trim();
    if (!trimmed) { setEditingPrice(null); return; }
    const dollars = Number(trimmed);
    if (!Number.isFinite(dollars) || dollars < 0) {
      toast.error('Enter a valid price');
      return;
    }
    const priceCents = Math.round(dollars * 100);
    setDraft((prev) => {
      const existing = prev.selectedProblems.find((p) => p.repairServiceId === row.serviceId);
      if (existing) {
        return {
          ...prev,
          selectedProblems: prev.selectedProblems.map((p) =>
            p.repairServiceId === row.serviceId ? { ...p, priceCents } : p,
          ),
        };
      }
      const next: SelectedProblem = {
        id: String(row.serviceId),
        repairServiceId: row.serviceId,
        name: row.name,
        category: row.category,
        priceCents,
        isCustom: false,
      };
      return { ...prev, selectedProblems: [...prev.selectedProblems, next] };
    });
    setEditingPrice(null);
    // Catalog persist only makes sense when the device is a known model —
    // custom devices (deviceModelId == null) get the local-only treatment.
    if (draft.deviceModelId != null) {
      persistMatrixPrice.mutate({
        deviceModelId: draft.deviceModelId,
        repairServiceId: row.serviceId,
        dollars,
      });
    }
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
                <div className="grid grid-cols-2 gap-3 sm:grid-cols-3 lg:grid-cols-4">
                  {groupRows.map((row) => {
                    const active = isSelected(row.serviceId);
                    const editingThis = editingPrice?.serviceId === row.serviceId;
                    // Selected price wins over the catalog price — the cashier
                    // may have just typed a per-ticket override.
                    const selectedRow = draft.selectedProblems.find((p) => p.repairServiceId === row.serviceId);
                    const displayPriceCents = selectedRow?.priceCents ?? row.priceCents;
                    const hasPrice = selectedRow != null || row.hasDevicePrice;
                    // Outer div carries the toggle click + keyboard handler so
                    // any pixel of the tile (not just the title) selects the
                    // problem. The price chip is a real button that
                    // stopPropagations so clicking it opens the editor without
                    // also toggling. Outer needs role/tabindex for a11y since
                    // it isn't a real <button>.
                    const handleToggle = () => toggleProblem(row);
                    return (
                      <div
                        key={row.serviceId}
                        role="button"
                        tabIndex={0}
                        onClick={handleToggle}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') {
                            e.preventDefault();
                            handleToggle();
                          }
                        }}
                        className={cn(
                          'group relative flex min-h-[96px] cursor-pointer flex-col items-start justify-between gap-3 rounded-xl bg-white px-4 py-4 text-left shadow-sm transition hover:-translate-y-0.5 hover:shadow-md dark:bg-surface-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/60 focus-visible:ring-offset-2 focus-visible:ring-offset-surface-950',
                          active
                            ? 'ring-2 ring-inset ring-primary-500 bg-primary-500/15 dark:bg-primary-500/15'
                            : 'ring-1 ring-inset ring-surface-300 hover:ring-2 hover:ring-primary-500 dark:ring-surface-600 dark:hover:ring-primary-500/80',
                        )}
                      >
                        <div className="text-sm font-semibold leading-tight text-surface-900 dark:text-surface-50">
                          {row.name}
                        </div>
                        <div className="flex w-full items-center justify-between text-xs">
                          {editingThis ? (
                            <div
                              className="flex items-center gap-1"
                              onClick={(e) => e.stopPropagation()}
                              onKeyDown={(e) => e.stopPropagation()}
                            >
                              <span className="font-mono text-surface-500">$</span>
                              <input
                                type="text"
                                inputMode="decimal"
                                value={editingPrice?.value ?? ''}
                                onChange={(e) => setEditingPrice({ serviceId: row.serviceId, value: e.target.value })}
                                onKeyDown={(e) => {
                                  e.stopPropagation();
                                  if (e.key === 'Enter') { e.preventDefault(); commitInlinePrice(row, editingPrice?.value ?? ''); }
                                  if (e.key === 'Escape') { e.preventDefault(); setEditingPrice(null); }
                                }}
                                onBlur={() => commitInlinePrice(row, editingPrice?.value ?? '')}
                                placeholder="0.00"
                                autoFocus
                                className="w-20 rounded border border-primary-500 bg-white px-1.5 py-0.5 font-mono text-xs text-surface-900 outline-none dark:bg-surface-900 dark:text-surface-50"
                              />
                            </div>
                          ) : (
                            <button
                              type="button"
                              onClick={(e) => {
                                e.stopPropagation();
                                setEditingPrice({
                                  serviceId: row.serviceId,
                                  value: hasPrice ? (displayPriceCents / 100).toFixed(2) : '',
                                });
                              }}
                              className={cn(
                                'rounded px-1.5 py-0.5 font-mono transition',
                                hasPrice
                                  ? 'text-surface-700 hover:bg-primary-500/10 dark:text-surface-300'
                                  : 'text-primary-700 underline decoration-dotted underline-offset-2 hover:text-primary-600 dark:text-primary-400',
                              )}
                              title={hasPrice ? 'Change price' : 'Set price'}
                            >
                              {hasPrice ? formatCurrency(displayPriceCents / 100) : 'Set price'}
                            </button>
                          )}
                          {active && <CheckCircle2 className="h-4 w-4 text-primary-500" />}
                        </div>
                      </div>
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
      {!canContinue && (
        <p className="px-1 text-center text-xs text-surface-500 dark:text-surface-400">
          Select at least one problem to continue.
        </p>
      )}
      <WizardFooter
        onBack={onBack}
        onContinue={onContinue}
        continueLabel="Quote it →"
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
            <span className="mb-1 flex items-baseline justify-between text-sm font-semibold">
              Diagnostic notes
              <span className="text-[11px] font-normal text-surface-500 dark:text-surface-400">public · prints on receipt</span>
            </span>
            <textarea
              className={inputClass}
              rows={3}
              value={draft.diagnostic}
              onChange={(event) => setDraft((prev) => ({ ...prev, diagnostic: event.target.value }))}
              placeholder="Customer-visible diagnosis. Use this for what the customer described or what you found — your call which detail belongs here vs. the internal note."
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
  // Seed the deposit from the quote total (50% suggested) the first time the
  // step mounts, replacing the static `$50.00` default that used to render
  // regardless of the actual quote. Cashier can override via the input below.
  const subtotalCents = draft.selectedProblems.reduce((sum, p) => sum + p.priceCents, 0);
  const seededRef = useRef(false);
  useEffect(() => {
    if (seededRef.current) return;
    seededRef.current = true;
    if (subtotalCents > 0) {
      // BUGHUNT-2026-05-10-20: integer-cents math so the deposit doesn't
      // drift by a cent on float intermediates (e.g. 1999 * 0.5 = 999.5).
      setDraft((prev) => ({ ...prev, depositAmount: (Math.round(subtotalCents / 2) / 100).toFixed(2) }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return (
    <div className="mx-auto flex max-w-5xl flex-col gap-4 px-4 pt-4 pb-6">
      <Stepper step="deposit" onGoToStep={onGoToStep} />
      <Section className="p-6 text-center">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Suggested deposit</div>
        <div className="mt-2 font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(parseMoney(draft.depositAmount))}</div>
        {subtotalCents > 0 && (
          <div className="mt-1 font-mono text-[11px] uppercase tracking-wider text-surface-500">
            of {formatCurrency(subtotalCents / 100)} quote · 50% suggested
          </div>
        )}
        <div className="mt-2 text-sm text-surface-900 dark:text-surface-500">Balance is collected at pickup. Deposit can be changed before tender.</div>
        {(draft.technician || draft.turnaround) && (
          <div className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full border border-surface-200 bg-surface-50 px-3 py-1 text-xs text-surface-700 dark:border-surface-700 dark:bg-surface-900 dark:text-surface-300">
            {draft.technician ? `Tech ${draft.technician}` : 'Tech: TBD'} · {draft.turnaround || 'Turnaround: TBD'}
          </div>
        )}
        <div className="relative mx-auto mt-6 max-w-sm">
          <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 font-display text-3xl text-surface-400">$</span>
          <input
            className={cn(inputClass, 'pl-9 text-center font-display text-4xl')}
            inputMode="decimal"
            value={draft.depositAmount}
            onChange={(event) => setDraft((prev) => ({ ...prev, depositAmount: event.target.value }))}
            aria-label="Deposit amount in dollars"
          />
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
            <button type="button" onClick={onCancel} className={secondaryButton} title="Skip signing — keep the manual waiver checkbox">Skip</button>
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
  blockchypOffline,
  blockchypOfflineReason,
  terminalName,
  customerId,
  onBack,
  onSelect,
}: {
  totalCents: number;
  paidLegs: PaymentLeg[];
  remainingCents: number;
  blockchypConfigured: boolean;
  blockchypOffline: boolean;
  blockchypOfflineReason: string | null;
  terminalName: string;
  customerId: number | null;
  onBack: () => void;
  onSelect: (method: TenderMethod) => void;
}) {
  // Live store-credit balance for the attached customer. Drives the tile's
  // subtitle ("Available · $X · attach customer to use") and disabled state.
  const storeCreditQuery = useQuery({
    queryKey: ['pos-customer-store-credit', customerId],
    queryFn: async () => {
      const res = await api.get<{ data: { amount_cents: number } }>(`/customers/${customerId}/store-credit`);
      return res.data.data;
    },
    enabled: typeof customerId === 'number' && customerId > 0,
    staleTime: 10_000,
  });
  const storeCreditCents = storeCreditQuery.data?.amount_cents ?? 0;
  const storeCreditDisabled = !customerId || storeCreditCents <= 0;
  const storeCreditSubtitle = !customerId
    ? 'Attach a customer to use'
    : storeCreditQuery.isLoading
      ? 'Loading balance…'
      : storeCreditCents > 0
        ? `Available · ${formatCurrency(storeCreditCents / 100)}`
        : 'No store-credit on file';
  const methods: Array<{ method: TenderMethod; title: string; subtitle: string; icon: React.ElementType; disabled?: boolean }> = [
    { method: 'Cash', title: 'Cash', subtitle: 'Type amount · drawer opens on confirm', icon: Banknote },
    {
      method: 'Card',
      title: 'Card · tap · chip · swipe',
      // WEB-UIUX-937: surface terminal-offline state instead of falsely
      // promising "ready". Tile is disabled while offline so a sale can't
      // start against an unreachable terminal.
      subtitle: !blockchypConfigured
        ? 'Pair terminal in settings'
        : blockchypOffline
          ? `Terminal ${terminalName} OFFLINE — ${blockchypOfflineReason ?? 'recent ping failed'}`
          : `Terminal ${terminalName} · ready · tip handled there`,
      icon: CreditCard,
      disabled: !blockchypConfigured || blockchypOffline,
    },
    { method: 'Gift card', title: 'Gift card', subtitle: 'Scan or type code', icon: Gift },
    { method: 'Store credit', title: 'Store credit', subtitle: storeCreditSubtitle, icon: Star, disabled: storeCreditDisabled },
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
        {methods.map(({ method, title, subtitle, icon: Icon, disabled }, index) => {
          const isPrimary = method === 'Cash' || method === 'Card';
          return (
            <button
              key={method}
              type="button"
              onClick={() => onSelect(method)}
              disabled={disabled}
              className={cn(
                'relative rounded-lg border p-5 text-left shadow-sm hover:border-primary-500 disabled:hover:border-surface-200 dark:border-surface-800 dark:bg-surface-900 disabled:opacity-50',
                isPrimary
                  ? 'border-primary-300 bg-primary-50/40 dark:border-primary-800 dark:bg-primary-900/10'
                  : 'border-surface-200 bg-white',
              )}
            >
              <span className="absolute right-3 top-3 rounded border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-900 px-1.5 font-mono text-[10px] text-surface-400">{index + 1}</span>
              <Icon className={cn(isPrimary ? 'h-7 w-7' : 'h-5 w-5', 'text-primary-700 dark:text-primary-500')} />
              <div className={cn('mt-4 font-display', isPrimary ? 'text-3xl' : 'text-xl')}>{title}</div>
              <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">{subtitle}</div>
              {disabled && method === 'Card' && (
                <a
                  href="/settings/hardware"
                  className="mt-2 inline-flex items-center text-xs font-semibold text-primary-700 underline-offset-4 hover:underline dark:text-primary-400"
                  onClick={(e) => e.stopPropagation()}
                >
                  Configure terminal →
                </a>
              )}
            </button>
          );
        })}
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
    const round = (step: number) => Math.ceil(exact / step) * step;
    const presets = [
      { label: 'Exact', value: exact },
      { label: formatCurrency(round(5)), value: round(5) },
      { label: formatCurrency(round(10)), value: round(10) },
      { label: formatCurrency(round(20)), value: round(20) },
      { label: formatCurrency(round(50)), value: round(50) },
      { label: formatCurrency(round(100)), value: round(100) },
    ];
    const seen = new Set<number>();
    return presets.filter((p) => {
      if (p.value <= 0 || seen.has(p.value)) return false;
      seen.add(p.value);
      return true;
    });
  })();
  const tendered = parseMoney(amount);
  const showChange = tendered > 0;
  const change = Math.max(0, tendered - remaining);
  return (
    <div className="mx-auto max-w-xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6">
        <div className="font-mono text-xs uppercase text-surface-900 dark:text-surface-500">Cash received</div>
        <input
          className="mt-2 w-full rounded-lg border border-surface-200 bg-surface-50 px-4 py-3 text-right font-display text-6xl text-primary-800 focus:border-primary-500 focus-visible:outline-none dark:border-surface-700 dark:bg-surface-950 dark:text-primary-500"
          value={amount}
          onChange={(event) => setAmount(event.target.value)}
          onKeyDown={(event) => {
            // Block non-numeric chars on desktop. inputMode='decimal' only
            // hints the soft keyboard; without this guard "abc" reaches the
            // parser and silently zeroes the tender.
            const ok = /[\d.]/.test(event.key)
              || event.key === 'Backspace' || event.key === 'Delete' || event.key === 'Tab'
              || event.key.startsWith('Arrow') || event.metaKey || event.ctrlKey;
            if (!ok) event.preventDefault();
          }}
          inputMode="decimal"
          aria-label="Cash received in dollars"
          autoFocus
        />
        <div className="mt-4 flex flex-wrap gap-2">
          {quick.map((preset) => (
            <button
              key={preset.label}
              type="button"
              onClick={() => setAmount(preset.value.toFixed(2))}
              aria-label={`Set amount to ${formatCurrency(preset.value)}`}
              className={cn(
                'rounded-full px-3 py-1.5 text-sm font-mono font-semibold border transition-colors',
                tendered.toFixed(2) === preset.value.toFixed(2)
                  ? 'bg-primary-500 text-on-primary border-primary-500'
                  : 'border-surface-200 bg-white text-surface-700 hover:border-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200',
              )}
            >
              {preset.label === 'Exact' ? `Exact · ${formatCurrency(preset.value)}` : preset.label}
            </button>
          ))}
        </div>
        {showChange && (
          <div className="mt-5 rounded-lg border border-surface-200 p-4 dark:border-surface-800">
            <div className="flex items-baseline justify-between">
              <div className="text-sm text-surface-900 dark:text-surface-500">Change due</div>
              <div className="font-mono text-[11px] text-surface-500 dark:text-surface-400">drawer auto-opens on confirm</div>
            </div>
            <div className="font-display text-5xl text-emerald-600 dark:text-emerald-400">{formatCurrency(change)}</div>
          </div>
        )}
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

function CardTenderView({ method, amount, setAmount, remainingCents, processing, terminalError, blockchypConfigured, blockchypOffline, blockchypOfflineReason, terminalName, customerId, customerName, onBack, onAccept }: {
  method: TenderMethod;
  amount: string;
  setAmount: (value: string) => void;
  remainingCents: number;
  processing: boolean;
  terminalError: string | null;
  blockchypConfigured: boolean;
  blockchypOffline: boolean;
  blockchypOfflineReason: string | null;
  terminalName: string;
  customerId: number | null;
  customerName: string | null;
  onBack: () => void;
  onAccept: () => void;
}) {
  const requiresTerminal = method === 'Card';
  // Store-credit balance lookup. The Store-credit tile previously accepted any
  // amount blindly; now we read the customer's actual ledger balance and cap
  // the tender. Skips the fetch when no customer is attached or when method
  // isn't Store credit. `enabled` keeps react-query quiet on unrelated views.
  const storeCreditQuery = useQuery({
    queryKey: ['pos-customer-store-credit', customerId],
    queryFn: async () => {
      const res = await api.get<{ data: { amount_cents: number } }>(`/customers/${customerId}/store-credit`);
      return res.data.data;
    },
    enabled: method === 'Store credit' && typeof customerId === 'number' && customerId > 0,
    staleTime: 10_000,
  });
  const storeCreditAvailableCents = storeCreditQuery.data?.amount_cents ?? 0;
  const tenderedCents = Math.round(parseMoney(amount) * 100);
  const overdraft = method === 'Store credit'
    && (!customerId || storeCreditQuery.isLoading
      ? false
      : tenderedCents > storeCreditAvailableCents);
  const noCustomerForStoreCredit = method === 'Store credit' && !customerId;
  const disabled =
    processing
    || (requiresTerminal && !blockchypConfigured)
    // WEB-UIUX-937: block the Charge button when the heartbeat says the
    // terminal is unreachable. Without this gate the SDK call hangs for
    // the full timeout before throwing, leaving the cashier and customer
    // staring at a frozen screen.
    || (requiresTerminal && blockchypOffline)
    || overdraft
    || noCustomerForStoreCredit
    || tenderedCents <= 0;
  // Subscribe to online/offline so the network-fallback banner reflects live
  // state — previously read once at render and never updated.
  const [networkOnline, setNetworkOnline] = useState(
    typeof navigator !== 'undefined' ? navigator.onLine : true,
  );
  useEffect(() => {
    const on = () => setNetworkOnline(true);
    const off = () => setNetworkOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('offline', off);
    };
  }, []);
  // Auto-fill: when the user lands on Store-credit with a positive balance and
  // hasn't typed yet, suggest min(remaining, available). Cashier can edit.
  useEffect(() => {
    if (method !== 'Store credit') return;
    if (!storeCreditQuery.data) return;
    if (parseMoney(amount) > 0) return;
    const suggestion = Math.min(remainingCents, storeCreditAvailableCents);
    if (suggestion > 0) setAmount((suggestion / 100).toFixed(2));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storeCreditQuery.data, method]);
  return (
    <div className="mx-auto max-w-2xl">
      <button type="button" onClick={onBack} className={ghostButton}><ChevronLeft className="h-4 w-4" /> Method picker</button>
      <Section className="mt-4 p-6 text-center">
        {method === 'Card' ? (
          <div className="relative mx-auto h-24 w-24" aria-hidden="true">
            <span className="absolute inset-0 rounded-full bg-cyan-500/10 motion-safe:animate-pulse"></span>
            <span className="absolute inset-3 rounded-full bg-cyan-500/20"></span>
            <CreditCard className="relative mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" style={{ marginTop: '28px' }} />
          </div>
        ) : (
          <Gift className="mx-auto h-10 w-10 text-primary-700 dark:text-primary-500" />
        )}
        <div className="mt-4 font-display text-4xl" role="status" aria-live="polite">
          {processing
            ? (method === 'Card' ? 'Waiting for terminal…' : `Applying ${method}…`)
            : (method === 'Card' ? 'Tap, insert, or swipe' : method)}
        </div>
        <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">
          {method === 'Card'
            ? (!blockchypConfigured
                ? 'Terminal is not configured.'
                : blockchypOffline
                  ? `Terminal OFFLINE — ${blockchypOfflineReason ?? 'recent ping failed'}. Power-cycle or run Test Connection.`
                  : `Customer terminal mirrors the prompt + handles tip.`)
            : method === 'Store credit'
              ? (customerName
                  ? `Apply from ${customerName}'s store-credit ledger. Cap is the live balance.`
                  : 'Store credit needs a customer. Attach one before tendering.')
              : 'Enter the amount to apply. Scan or validate the code before tendering.'}
        </div>
        {method === 'Store credit' && customerId && (
          <div className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full bg-primary-500/10 px-3 py-1 font-mono text-[11px] text-primary-700 dark:text-primary-400">
            <Star className="h-3 w-3" aria-hidden="true" />
            {storeCreditQuery.isLoading
              ? 'Balance · loading…'
              : `Available · ${formatCurrency(storeCreditAvailableCents / 100)}`}
          </div>
        )}
        {method === 'Store credit' && !customerId && (
          <div role="alert" className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full bg-rose-500/10 px-3 py-1 font-mono text-[11px] text-rose-700 dark:text-rose-400">
            <AlertTriangle className="h-3 w-3" aria-hidden="true" />
            No customer attached
          </div>
        )}
        {method === 'Card' && !blockchypConfigured && (
          <a
            href="/settings/hardware"
            className="mx-auto mt-3 inline-flex items-center gap-1 text-xs font-semibold text-primary-700 underline-offset-4 hover:underline dark:text-primary-400"
          >
            Configure terminal in settings →
          </a>
        )}
        {method === 'Card' && blockchypConfigured && (
          <div className="mx-auto mt-3 inline-flex items-center gap-2 rounded-full bg-surface-100 px-3 py-1 font-mono text-[11px] text-cyan-700 dark:bg-surface-800 dark:text-cyan-400">
            <span aria-hidden="true" className="text-[10px]">●</span> Terminal {terminalName} · paired
          </div>
        )}
        <label className="mx-auto mt-5 block max-w-sm text-left">
          <span className="mb-1 block text-sm font-semibold">{method} amount</span>
          <input
            className={cn(inputClass, overdraft && 'border-rose-400 focus:border-rose-500')}
            value={amount}
            onChange={(event) => setAmount(event.target.value)}
            onKeyDown={(event) => {
              const ok = /[\d.]/.test(event.key)
                || event.key === 'Backspace' || event.key === 'Delete' || event.key === 'Tab'
                || event.key.startsWith('Arrow') || event.metaKey || event.ctrlKey;
              if (!ok) event.preventDefault();
            }}
            inputMode="decimal"
            aria-label={`${method} amount in dollars`}
            aria-invalid={overdraft || undefined}
          />
          <div className="mt-1.5 font-mono text-[11px] text-surface-500 dark:text-surface-400">Edit to take partial · remainder bounces back to method picker</div>
          {overdraft && (
            <div role="alert" className="mt-1.5 inline-flex items-center gap-1 text-[11px] font-semibold text-rose-600 dark:text-rose-400">
              <AlertTriangle className="h-3 w-3" aria-hidden="true" />
              Exceeds available balance ({formatCurrency(storeCreditAvailableCents / 100)})
            </div>
          )}
        </label>
        <div className="mt-4 text-sm text-surface-900 dark:text-surface-500">Remaining balance is {formatCurrency(fromCents(remainingCents))}.</div>
        {!networkOnline && (
          <div role="status" aria-live="polite" className="mt-4 flex items-center gap-2 rounded-lg border border-amber-400/40 bg-amber-500/10 p-3 text-left text-xs text-amber-700 dark:text-amber-400">
            <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
            <span>Network in fallback (Wi-Fi reconnecting) · cellular backup ready.</span>
          </div>
        )}
        {terminalError && (
          <div role="alert" aria-live="assertive" className="mt-5 rounded-lg border border-red-300 bg-red-50 p-3 text-left text-sm text-red-700 dark:border-red-800 dark:bg-red-950/30 dark:text-red-300">
            <div className="flex items-start gap-2">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
              <div className="min-w-0 flex-1">
                <div>{terminalError}</div>
                <button
                  type="button"
                  onClick={onAccept}
                  disabled={disabled}
                  className="mt-2 inline-flex items-center gap-1 rounded-md border border-red-300 bg-white px-2.5 py-1 text-xs font-semibold text-red-700 hover:bg-red-100 disabled:opacity-50 dark:border-red-700 dark:bg-red-900/30 dark:text-red-200 dark:hover:bg-red-900/50"
                >
                  <RotateCcw className="h-3 w-3" aria-hidden="true" /> Try again
                </button>
              </div>
            </div>
          </div>
        )}
        <button
          type="button"
          onClick={onAccept}
          disabled={disabled}
          aria-busy={processing}
          className={cn(primaryButton, 'mt-5 w-full py-3 text-base')}
        >
          {processing ? 'Processing…' : method === 'Card' ? 'Send to terminal' : `Apply ${method}`}
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
      {/* overflow-x-auto so the action column never gets clipped by the cart
          rail on narrower viewports — the X used to land off-screen on
          1280-wide laptops. Last col is sized to fit the Resume + ✕ pair
          (~160px) and stays right-anchored. */}
      <div className="overflow-x-auto rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
        <div className="grid min-w-[920px] grid-cols-[minmax(180px,1fr)_minmax(180px,1.4fr)_100px_120px_120px_minmax(160px,auto)] gap-3 border-b border-surface-200 px-4 py-3 font-mono text-[11px] uppercase tracking-[0.14em] text-surface-500 dark:border-surface-700 dark:text-surface-500">
          <span>Customer</span>
          <span>Items</span>
          <span>Total</span>
          <span>Held by</span>
          <span>Held since</span>
          <span className="text-right">Actions</span>
        </div>
        {loading ? (
          <div className="space-y-2 p-4">
            {[0, 1, 2].map((i) => (
              <div key={i} aria-hidden="true" className="h-10 motion-safe:animate-pulse rounded-lg bg-surface-100 dark:bg-surface-900" />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="p-8 text-center text-sm text-surface-700 dark:text-surface-400">
            {rows.length === 0 ? (
              'No held sales right now.'
            ) : (
              <>
                No held sales match &ldquo;{filterPills.find((p) => p.id === filter)?.label}&rdquo;.
                {filter !== 'all' && (
                  <button type="button" onClick={() => setFilter('all')} className="ml-2 font-semibold text-primary-700 underline-offset-4 hover:underline dark:text-primary-400">
                    Show all
                  </button>
                )}
              </>
            )}
          </div>
        ) : (
          filtered.map((row) => (
            <div key={row.id} className="grid min-w-[920px] grid-cols-[minmax(180px,1fr)_minmax(180px,1.4fr)_100px_120px_120px_minmax(160px,auto)] items-center gap-3 border-b border-surface-200 px-4 py-3 text-sm last:border-b-0 dark:border-surface-700">
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
    // BUGHUNT-2026-05-10-19: refund cap must be live — a sale in another
    // tab between modal-open and refund-click would leave the cached
    // drawer balance stale and let a refund go through against an
    // insufficient cash drawer. Refetch on every mount/window-focus.
    staleTime: 0,
    refetchOnMount: 'always',
    refetchOnWindowFocus: true,
  });
  const drawerCashOnHand = drawerZReportQuery.data ? fromCents(drawerZReportQuery.data.expected_cents) : null;

  // BUGHUNT-2026-05-10-18: include the line's tax allocation in the refund
  // preview. Each invoice line carries `tax_amount` aggregated over its
  // ordered qty; allocate proportionally to the refunded qty so a partial
  // return refunds the correct tax slice. Falls back to 0 if tax_amount is
  // null/undefined (legacy line items without per-line tax) so the legacy
  // unit_price-only behaviour still works for those.
  const selectedTotal = selections.reduce((sum, selection) => {
    const line = invoice?.line_items?.find((item: any) => item.id === selection.line_item_id);
    if (!line) return sum;
    const unitPrice = Number(line.unit_price ?? line.price ?? 0);
    const lineQty = Math.max(1, Number(line.quantity ?? 1));
    const lineTax = Number(line.tax_amount ?? 0);
    const refundQty = Number(selection.quantity ?? 0);
    const subtotal = unitPrice * refundQty;
    const taxAlloc = lineTax > 0 ? (lineTax * refundQty) / lineQty : 0;
    return sum + subtotal + taxAlloc;
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
          {refundMethod === 'cash' && drawerCashOnHand !== null && cashShort && (
            <div role="alert" aria-live="assertive" className="border-b border-rose-200 bg-rose-50 px-4 py-2.5 text-sm text-rose-700 dark:border-rose-900 dark:bg-rose-950/40 dark:text-rose-300">
              <span className="inline-flex items-center gap-2">
                <AlertTriangle className="h-4 w-4 shrink-0" aria-hidden="true" />
                Drawer short — {formatCurrency(drawerCashOnHand)} on hand, need {formatCurrency(selectedTotal)}. Cash-in or pick a different refund method.
              </span>
            </div>
          )}
          <div className="divide-y divide-surface-200 dark:divide-surface-800">
            {(!invoice.line_items || invoice.line_items.length === 0) ? (
              <div className="px-4 py-6 text-center text-sm text-surface-500 dark:text-surface-400">
                No returnable lines on this invoice.
              </div>
            ) : invoice.line_items.map((line: any) => {
              const selected = selections.some((item) => item.line_item_id === line.id);
              const originalQty = Number(line.quantity ?? line.original_quantity ?? 1);
              const returnableQty = Number(line.returnable_quantity ?? originalQty);
              const alreadyReturned = Math.max(0, originalQty - returnableQty);
              return (
                <button key={line.id} type="button" onClick={() => toggleLine(line)} className="grid w-full grid-cols-[32px_1fr_120px] gap-3 px-4 py-3 text-left hover:bg-surface-50 dark:hover:bg-surface-900">
                  <span aria-hidden="true" className={cn('mt-1 h-5 w-5 rounded border', selected ? 'border-primary-500 bg-primary-500' : 'border-surface-300 dark:border-surface-700')} />
                  <span>
                    <span className="block font-semibold">{line.description || line.name}</span>
                    <span className="text-sm text-surface-900 dark:text-surface-500">
                      Returnable qty {returnableQty}
                      {alreadyReturned > 0 && (
                        <span className="ml-2 text-surface-500 dark:text-surface-400">· {alreadyReturned} already returned</span>
                      )}
                    </span>
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
            {refundMethod === 'cash' && drawerCashOnHand !== null && !cashShort && selectedTotal > 0 && (
              <p className="mt-2 inline-flex items-center gap-1 text-xs text-emerald-600 dark:text-emerald-400">
                <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />
                Drawer covers — {formatCurrency(drawerCashOnHand)} on hand · refund {formatCurrency(selectedTotal)} leaves {formatCurrency(drawerCashOnHand - selectedTotal)}.
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
  const priceNum = parseMoney(price);
  const discountNum = parseMoney(discount);
  const priceValid = Number.isFinite(priceNum) && priceNum >= 0;
  const discountValid = Number.isFinite(discountNum) && discountNum >= 0;
  const nameValid = name.trim().length > 0;
  const canSave = priceValid && discountValid && nameValid;
  return (
    <Modal
      title="Edit Cart Line"
      onClose={onClose}
      footer={
        <div className="flex items-center justify-between gap-2">
          {!canSave && (
            <span className="font-mono text-[11px] text-rose-600 dark:text-rose-400">
              {!nameValid ? 'Line name required' : !priceValid ? 'Enter a valid price' : 'Enter a valid discount'}
            </span>
          )}
          <div className="ml-auto flex gap-2">
            <button type="button" className={secondaryButton} onClick={onClose}>Cancel</button>
            <button
              type="button"
              className={cn(primaryButton, !canSave && 'pointer-events-none opacity-50')}
              disabled={!canSave}
              onClick={() => {
                if (!canSave) return;
                if (item.type === 'repair') onSave({ serviceName: name.trim(), laborPrice: priceNum, lineDiscount: discountNum } as Partial<CartItem>);
                if (item.type === 'product') onSave({ name: name.trim(), unitPrice: priceNum } as Partial<CartItem>);
                if (item.type === 'misc') onSave({ name: name.trim(), unitPrice: priceNum } as Partial<CartItem>);
              }}
            >
              Save line
            </button>
          </div>
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

function ReceiptView({ sale, onNext, onProcessRefund }: { sale: CompletedSale; onNext: () => void; onProcessRefund?: () => void }) {
  // Print by cloning the receipt panel into a fresh popup window. Earlier
  // `@media print { body * { visibility: hidden } [panel] { visible } }`
  // approaches kept producing an empty preview — the panel sits inside a
  // chain of grid + overflow ancestors, and at least one of them strips its
  // children out of the print layout regardless of visibility/position
  // overrides. A self-contained popup with only the receipt markup sidesteps
  // the whole ancestor mess and gives us a deterministic page to print.
  const triggerPrint = (mode: 'thermal' | 'letter') => {
    const panel = document.querySelector('[data-receipt-panel]');
    if (!panel) {
      toast.error('Receipt not ready yet');
      return;
    }
    const popup = window.open('', '_blank', 'width=520,height=720');
    if (!popup) {
      toast.error('Popup blocked — allow popups for this site to print');
      return;
    }
    // Copy stylesheets + inline <style> tags from the host document so the
    // cloned receipt keeps its Tailwind / design-system styling. Vite dev
    // injects styles as <style> tags; production has <link rel="stylesheet">.
    const headLinks = Array.from(
      document.head.querySelectorAll('link[rel="stylesheet"], style'),
    ).map((node) => node.outerHTML).join('\n');
    const pageRule = mode === 'thermal'
      ? '@page { size: 80mm auto; margin: 4mm; }'
      : '@page { size: letter; margin: 12mm; }';
    const panelWidth = mode === 'thermal' ? '72mm' : '186mm';
    const fontSize = mode === 'thermal' ? '11px' : '12px';
    const html = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8" />
<title>Receipt ${sale.orderId}</title>
${headLinks}
<style>
  ${pageRule}
  html, body { background: #fff !important; color: #000 !important; margin: 0; padding: 8px; font-size: ${fontSize}; }
  body { font-family: ui-monospace, Menlo, Consolas, monospace; }
  [data-receipt-panel] {
    width: ${panelWidth};
    max-width: ${panelWidth};
    background: #fff !important;
    color: #000 !important;
    border: none !important;
    box-shadow: none !important;
    padding: 0 !important;
    margin: 0 auto !important;
  }
  [data-letter-only] { display: ${mode === 'letter' ? 'block' : 'none'} !important; }
  .no-print { display: none !important; }
</style>
</head>
<body>
${panel.outerHTML}
</body>
</html>`;
    popup.document.open();
    popup.document.write(html);
    popup.document.close();
    const fire = () => {
      try {
        popup.focus();
        popup.print();
      } finally {
        // Close shortly after — Chrome blocks the JS thread until the print
        // dialog is dismissed, so the close runs once the user is done.
        setTimeout(() => popup.close(), 250);
      }
    };
    if (popup.document.readyState === 'complete') {
      setTimeout(fire, 50);
    } else {
      popup.addEventListener('load', fire, { once: true });
      // Fallback in case `load` never fires (e.g. blocked stylesheets):
      setTimeout(fire, 800);
    }
  };

  const handleShare = (kind: 'SMS' | 'Email') => {
    toast(`${kind} delivery is coming soon`);
  };

  return (
    <div className="h-full overflow-auto p-4">
      <div className="mx-auto grid max-w-6xl gap-4 lg:grid-cols-[minmax(0,1fr)_420px]">
        <div className="flex flex-col gap-4">
          <Section className="p-6 text-center">
            <CheckCircle2 className="mx-auto h-14 w-14 text-emerald-600 dark:text-emerald-400" />
            <div className="mt-4 font-display text-5xl">Payment complete</div>
            <div className="mt-2 font-display text-7xl text-primary-800 dark:text-primary-500">{formatCurrency(sale.total)}</div>
            <div className="mt-1 text-sm text-surface-900 dark:text-surface-500">{sale.orderId} · {sale.customerName}</div>
            {sale.change > 0 && <Pill tone="success" className="mt-4">Change due {formatCurrency(sale.change)}</Pill>}
          </Section>
          <div className="grid gap-3 sm:grid-cols-2 no-print">
            <button
              type="button"
              onClick={() => handleShare('SMS')}
              className="rounded-lg border border-surface-200 bg-white p-4 text-center font-semibold hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900"
            >
              <MessageSquare className="mx-auto h-5 w-5 text-primary-700 dark:text-primary-500" aria-hidden="true" />
              <span className="mt-2 block">SMS</span>
            </button>
            <button
              type="button"
              onClick={() => handleShare('Email')}
              className="rounded-lg border border-surface-200 bg-white p-4 text-center font-semibold hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900"
            >
              <Mail className="mx-auto h-5 w-5 text-primary-700 dark:text-primary-500" aria-hidden="true" />
              <span className="mt-2 block">Email</span>
            </button>
          </div>
          <div className="grid gap-3 sm:grid-cols-2 no-print">
            <button
              type="button"
              onClick={() => triggerPrint('thermal')}
              className="rounded-lg border border-surface-200 bg-white p-4 text-left hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900"
            >
              <div className="flex items-center gap-2">
                <Printer className="h-5 w-5 text-primary-700 dark:text-primary-500" aria-hidden="true" />
                <span className="font-semibold">Print receipt</span>
              </div>
              <p className="mt-1 text-[11px] text-surface-500">Thermal · 80 mm roll · customer copy</p>
            </button>
            <button
              type="button"
              onClick={() => triggerPrint('letter')}
              className="rounded-lg border border-surface-200 bg-white p-4 text-left hover:border-primary-500 dark:border-surface-800 dark:bg-surface-900"
            >
              <div className="flex items-center gap-2">
                <FileText className="h-5 w-5 text-primary-700 dark:text-primary-500" aria-hidden="true" />
                <span className="font-semibold">Print service doc</span>
              </div>
              <p className="mt-1 text-[11px] text-surface-500">Letter · 8.5 × 11 in · workshop / file copy</p>
            </button>
          </div>
          <p className="text-[11px] text-surface-500 no-print">
            Save-as-PDF is available from the system print dialog on every device.
          </p>
          <Section className="p-5">
            <div className="flex items-center gap-3">
              <Star className="h-8 w-8 text-cyan-700 dark:text-cyan-400" />
              <div className="flex-1">
                <div className="font-semibold">Loyalty updated</div>
                <div className="text-sm text-surface-900 dark:text-surface-500">Points and warranty history are attached when a customer is selected.</div>
              </div>
            </div>
          </Section>
          <div className="flex flex-wrap gap-2 no-print">
            <button type="button" onClick={onNext} className={primaryButton}>Next sale</button>
            {sale.invoiceId && <button type="button" onClick={() => window.location.assign(`/invoices/${sale.invoiceId}`)} className={secondaryButton}>Open invoice</button>}
            {/* WEB-UIUX-433: inline refund affordance — saves the 5-click Invoices→find→open→Credit Note dance. */}
            {onProcessRefund && (
              <button
                type="button"
                onClick={onProcessRefund}
                className={secondaryButton}
              >
                Process refund
              </button>
            )}
          </div>
        </div>
        <Section className="p-5 font-mono text-sm" data-receipt-panel>
          <div className="text-center font-display text-3xl">BIZARRE REPAIR</div>
          <div data-letter-only style={{ display: 'none' }} className="mt-1 text-center text-[11px]">
            123 Main St · 555-0100 · hello@bizarrerepair.example
          </div>
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
          {sale.discount > 0 && <div className="flex justify-between text-emerald-700 dark:text-emerald-400"><span>Discount</span><span>-{formatCurrency(sale.discount)}</span></div>}
          <div className="flex justify-between"><span>Tax</span><span>{formatCurrency(sale.tax)}</span></div>
          <div className="mt-2 flex justify-between font-bold"><span>Total</span><span>{formatCurrency(sale.total)}</span></div>
          <div className="my-4 border-t border-dashed border-surface-300 dark:border-surface-700" />
          {sale.payments.map((leg, index) => (
            <div key={`${leg.method}-${index}`} className="flex justify-between"><span>{leg.method}</span><span>{formatCurrency(leg.amount)}</span></div>
          ))}
          {sale.change > 0 && <div className="flex justify-between"><span>Change</span><span>{formatCurrency(sale.change)}</span></div>}
          <div className="mt-6 text-center text-xs text-surface-900 dark:text-surface-500">Thank you.</div>
          <div data-letter-only style={{ display: 'none' }} className="mt-6 border-t border-dashed border-surface-300 pt-4 text-[11px] dark:border-surface-700">
            <div className="font-semibold">Service authorization</div>
            <p className="mt-1 leading-relaxed">
              Customer authorizes the work itemized above. Diagnostic deposits are non-refundable
              if the device cannot be repaired due to undisclosed prior damage. Liquid-damage
              repairs are best-effort. We are not responsible for data loss; please back up
              before service.
            </p>
            <div className="mt-6 grid grid-cols-2 gap-6">
              <div>
                <div className="border-b border-surface-400 pb-1">&nbsp;</div>
                <div className="mt-1 text-[10px]">Customer signature</div>
              </div>
              <div>
                <div className="border-b border-surface-400 pb-1">&nbsp;</div>
                <div className="mt-1 text-[10px]">Date</div>
              </div>
            </div>
            <div className="mt-6 flex justify-between text-[10px] text-surface-500">
              <span>Workshop copy</span>
              <span>Page 1 of 1</span>
            </div>
          </div>
        </Section>
      </div>
    </div>
  );
}
