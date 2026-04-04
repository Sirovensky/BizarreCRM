import { useState, useEffect, useRef, useCallback } from 'react';
import { useDraft } from '@/hooks/useDraft';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, ChevronDown, ChevronRight, Check, Smartphone, Tablet, Laptop, Monitor, Gamepad2,
  Tv, HelpCircle, MessageSquare, Clock, User, Phone, Mail, Tag, Calendar,
  FileText, Printer, Copy, Trash2, MoreHorizontal, Send, Flag, Loader2,
  Wrench, AlertCircle, History, DollarSign, ExternalLink, Edit3, Save, X,
  Plus, Search, Camera, Upload, Package, ShoppingCart, CircleDot, CheckCircle2,
  CreditCard, Receipt, TrendingUp, Timer, MapPin, Image,
} from 'lucide-react';
import toast from 'react-hot-toast';
import DOMPurify from 'dompurify';
import { ticketApi, settingsApi, catalogApi, invoiceApi, employeeApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { cn } from '@/utils/cn';
import { getIFixitUrl } from '@/utils/ifixit';
import { QuickSmsModal } from '@/components/shared/QuickSmsModal';
import { CopyButton } from '@/components/shared/CopyButton';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { BackButton } from '@/components/shared/BackButton';
import { PrintPreviewModal } from '@/components/shared/PrintPreviewModal';
import type { Ticket, TicketStatus, TicketNote, TicketDevice, TicketHistory } from '@bizarre-crm/shared';

// ─── Helpers ────────────────────────────────────────────────────────
function formatTicketId(orderId: string | number) {
  const str = String(orderId);
  if (str.startsWith('T-')) return str;
  return `T-${str.padStart(4, '0')}`;
}

function formatDate(iso: string | null | undefined) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleDateString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
  });
}

function formatDateTime(iso: string | null | undefined) {
  if (!iso) return '—';
  const d = new Date(iso);
  if (isNaN(d.getTime())) return '—';
  return d.toLocaleString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric',
    hour: 'numeric', minute: '2-digit',
  });
}

function formatCurrency(amount: number | null | undefined) {
  if (amount == null || isNaN(amount)) return '$0.00';
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
}

function initials(first?: string, last?: string) {
  return `${(first || '?').charAt(0)}${(last || '').charAt(0)}`.toUpperCase();
}

function timeAgo(iso: string) {
  const ts = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z';
  const diff = Date.now() - new Date(ts).getTime();
  if (diff < 0) return 'just now';
  const mins = Math.floor(diff / 60000);
  if (mins < 60) return `${mins}m ago`;
  const hrs = Math.floor(mins / 60);
  if (hrs < 24) return `${hrs}h ago`;
  const days = Math.floor(hrs / 24);
  return `${days}d ago`;
}

const DEVICE_ICONS: Record<string, typeof Smartphone> = {
  Phone: Smartphone, Tablet, Laptop, Desktop: Monitor,
  'Game Console': Gamepad2, TV: Tv, Other: HelpCircle,
};

const NOTE_TYPES = [
  { value: 'internal', label: 'Internal' },
  { value: 'diagnostic', label: 'Diagnostic' },
  { value: 'email', label: 'Email' },
];

const NOTE_TAB_FILTERS = ['All', 'Internal', 'Diagnostic', 'Email'] as const;

const PART_STATUS_COLORS: Record<string, string> = {
  available: 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300',
  missing: 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300',
  ordered: 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300',
  received: 'bg-purple-100 text-purple-800 dark:bg-purple-900/30 dark:text-purple-300',
};

// ─── Device History Popover ─────────────────────────────────────────
function DeviceHistoryPopover({ imei, serial, currentTicketId }: { imei?: string; serial?: string; currentTicketId: number }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  const { data, isLoading } = useQuery({
    queryKey: ['device-history', imei, serial],
    queryFn: () => ticketApi.deviceHistory({ imei: imei || undefined, serial: serial || undefined }),
    enabled: open,
  });

  const history = (data?.data?.data || []).filter((t: any) => t.id !== currentTicketId);

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div ref={ref} className="relative inline-flex">
      <button
        onClick={() => setOpen(!open)}
        className="inline-flex items-center gap-1 text-xs text-amber-600 hover:text-amber-700 dark:text-amber-400 dark:hover:text-amber-300 hover:underline"
        title="View past repairs for this device"
      >
        <History className="h-3 w-3" /> History
      </button>
      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-72 rounded-lg border border-surface-200 bg-white p-3 shadow-lg dark:border-surface-700 dark:bg-surface-800">
          <p className="mb-2 text-xs font-semibold text-surface-700 dark:text-surface-300">Past repairs for this device</p>
          {isLoading ? (
            <div className="flex justify-center py-4"><Loader2 className="h-4 w-4 animate-spin text-surface-400" /></div>
          ) : history.length === 0 ? (
            <p className="text-xs text-surface-400 py-2">No previous repairs found.</p>
          ) : (
            <div className="space-y-1.5 max-h-48 overflow-y-auto">
              {history.map((t: any) => (
                <button
                  key={t.id}
                  onClick={() => { setOpen(false); navigate(`/tickets/${t.id}`); }}
                  className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700 transition-colors"
                >
                  <span className="h-2 w-2 rounded-full shrink-0" style={{ backgroundColor: t.status_color || '#888' }} />
                  <span className="font-medium text-primary-600 dark:text-primary-400">{t.order_id}</span>
                  <span className="text-surface-500 truncate flex-1">{t.device_name}</span>
                  <span className="text-surface-400 shrink-0">{timeAgo(t.created_at)}</span>
                </button>
              ))}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Phone Action Row (call / text popup) ──────────────────────────
function PhoneActionRow({ phone, customerName, ticketId, onSms }: { phone: string; customerName: string; ticketId: number; onSms: () => void }) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);
  const navigate = useNavigate();

  useEffect(() => {
    if (!open) return;
    const handleClick = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    };
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div ref={ref} className="relative flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
      <Phone className="h-3.5 w-3.5 text-surface-400" />
      <button
        onClick={() => setOpen(!open)}
        className="hover:text-primary-600 dark:hover:text-primary-400 underline decoration-dotted underline-offset-2 transition-colors"
      >
        {phone}
      </button>
      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 w-44 rounded-lg border border-surface-200 bg-white p-1 shadow-lg dark:border-surface-700 dark:bg-surface-800">
          <a
            href={`tel:${phone}`}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
            onClick={() => setOpen(false)}
          >
            <Phone className="h-3.5 w-3.5 text-green-500" />
            Call {customerName.split(' ')[0]}
          </a>
          <button
            onClick={() => { setOpen(false); onSms(); }}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            <MessageSquare className="h-3.5 w-3.5 text-blue-500" />
            Send SMS
          </button>
          <button
            onClick={() => { setOpen(false); navigate(`/communications?phone=${encodeURIComponent(phone)}`); }}
            className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
          >
            <ExternalLink className="h-3.5 w-3.5 text-surface-400" />
            SMS History
          </button>
        </div>
      )}
    </div>
  );
}

// ─── Collapsible Section ────────────────────────────────────────────
function AccordionSection({
  title,
  icon: Icon,
  count,
  defaultOpen = true,
  actions,
  children,
}: {
  title: string;
  icon?: typeof Plus;
  count?: number;
  defaultOpen?: boolean;
  actions?: React.ReactNode;
  children: React.ReactNode;
}) {
  const [open, setOpen] = useState(defaultOpen);
  return (
    <div className="border-b border-surface-100 dark:border-surface-800 last:border-b-0">
      <div className="flex w-full items-center gap-2 px-4 py-3 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
        <div
          role="button"
          onClick={() => setOpen((v) => !v)}
          className="flex items-center gap-2 flex-1 cursor-pointer"
        >
          <ChevronRight className={cn('h-4 w-4 text-surface-400 transition-transform', open && 'rotate-90')} />
          {Icon && <Icon className="h-4 w-4 text-surface-400" />}
          <span className="text-sm font-semibold text-surface-800 dark:text-surface-200">{title}</span>
          {count !== undefined && (
            <span className="ml-1 text-xs text-surface-400">({count})</span>
          )}
        </div>
        {actions && (
          <div className="flex items-center gap-1">
            {actions}
          </div>
        )}
      </div>
      {open && <div className="px-4 pb-4">{children}</div>}
    </div>
  );
}

// ─── Status Dropdown ────────────────────────────────────────────────
function HeaderStatusDropdown({
  currentStatus,
  statuses,
  onSelect,
  isPending,
}: {
  currentStatus?: TicketStatus;
  statuses: TicketStatus[];
  onSelect: (id: number) => void;
  isPending: boolean;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        disabled={isPending}
        className="inline-flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold transition-opacity hover:opacity-80 disabled:opacity-50 border"
        style={{
          backgroundColor: `${currentStatus?.color ?? '#6b7280'}15`,
          color: currentStatus?.color ?? '#6b7280',
          borderColor: `${currentStatus?.color ?? '#6b7280'}40`,
        }}
      >
        {isPending ? (
          <Loader2 className="h-4 w-4 animate-spin" />
        ) : (
          <span className="h-2.5 w-2.5 rounded-full" style={{ backgroundColor: currentStatus?.color ?? '#6b7280' }} />
        )}
        {currentStatus?.name ?? 'Unknown'}
        <ChevronDown className="h-4 w-4" />
      </button>

      {open && (
        <div className="absolute left-0 top-full z-50 mt-1 min-w-[18rem] rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div className="max-h-80 overflow-y-auto py-1">
            {statuses.map((s) => (
              <button
                key={s.id}
                onClick={() => { onSelect(s.id); setOpen(false); }}
                className={cn(
                  'flex w-full items-center gap-2.5 px-3 py-2 text-left text-sm transition-colors hover:bg-surface-50 dark:hover:bg-surface-700',
                  s.id === currentStatus?.id && 'bg-surface-50 dark:bg-surface-700',
                )}
              >
                <span className="h-2.5 w-2.5 rounded-full shrink-0" style={{ backgroundColor: s.color }} />
                <span className="text-surface-700 dark:text-surface-200" title={s.name}>{s.name}</span>
                {s.id === currentStatus?.id && <Check className="ml-auto h-4 w-4 shrink-0 text-primary-500" />}
              </button>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Actions dropdown ───────────────────────────────────────────────
function ActionsDropdown({ onPrint, onDuplicate, onDelete }: {
  onPrint: () => void; onDuplicate: () => void; onDelete: () => void;
}) {
  const [open, setOpen] = useState(false);
  const ref = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClick(e: MouseEvent) {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, [open]);

  return (
    <div className="relative" ref={ref}>
      <button
        onClick={() => setOpen((v) => !v)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800"
      >
        <MoreHorizontal className="h-4 w-4" /> More
      </button>
      {open && (
        <div className="absolute right-0 top-full z-50 mt-1 w-48 rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div className="py-1">
            <button onClick={() => { onPrint(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 transition-colors hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-700">
              <Printer className="h-4 w-4" /> Print
            </button>
            <button onClick={() => { onDuplicate(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-surface-700 transition-colors hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-700">
              <Copy className="h-4 w-4" /> Duplicate
            </button>
            <hr className="my-1 border-surface-200 dark:border-surface-700" />
            <button onClick={() => { onDelete(); setOpen(false); }}
              className="flex w-full items-center gap-2 px-3 py-2 text-sm text-red-600 transition-colors hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-950/30">
              <Trash2 className="h-4 w-4" /> Delete
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

// ─── Print Dropdown ─────────────────────────────────────────────────
function PrintButton({ ticketId, invoiceId }: { ticketId: number; invoiceId?: number | null }) {
  const [showModal, setShowModal] = useState(false);
  return (
    <>
      <button
        onClick={() => setShowModal(true)}
        className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 px-3 py-2 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800"
      >
        <Printer className="h-4 w-4" /> Print
      </button>
      {showModal && (
        <PrintPreviewModal ticketId={ticketId} invoiceId={invoiceId} onClose={() => setShowModal(false)} />
      )}
    </>
  );
}

// ─── Parts Search Modal ─────────────────────────────────────────────
function PartsSearchModal({
  deviceId,
  ticketId,
  deviceModelId,
  onClose,
  onPartAdded,
}: {
  deviceId: number;
  ticketId: number;
  deviceModelId?: number;
  onClose: () => void;
  onPartAdded: () => void;
}) {
  const [query, setQuery] = useState('');
  const [debouncedQuery, setDebouncedQuery] = useState('');
  const queryClient = useQueryClient();

  useEffect(() => {
    const timer = setTimeout(() => setDebouncedQuery(query), 300);
    return () => clearTimeout(timer);
  }, [query]);

  const { data: searchData, isLoading: searching } = useQuery({
    queryKey: ['parts-search', debouncedQuery, deviceModelId],
    queryFn: () => catalogApi.partsSearch({ q: debouncedQuery, device_model_id: deviceModelId }),
    enabled: debouncedQuery.length >= 2,
  });

  const results = searchData?.data?.data;
  const inventoryItems = results?.inventoryItems || [];
  const supplierItems = results?.supplierItems || [];

  const addPartMut = useMutation({
    mutationFn: (data: { inventory_item_id: number; quantity: number; price: number }) =>
      ticketApi.addParts(deviceId, data),
    onSuccess: () => {
      toast.success('Part added');
      onPartAdded();
    },
    onError: () => toast.error('Failed to add part'),
  });

  const addSupplierPartMut = useMutation({
    mutationFn: async (item: any) => {
      const importRes = await catalogApi.importItem(item.id, { markup_pct: 0, in_stock_qty: 0 });
      const inventoryItem = importRes?.data?.data;
      if (!inventoryItem?.id) throw new Error('Import failed');
      await ticketApi.addParts(deviceId, {
        inventory_item_id: inventoryItem.id,
        quantity: 1,
        price: item.price || 0,
      });
      const ticketRes = await ticketApi.get(ticketId);
      const ticket = ticketRes?.data?.data;
      const device = ticket?.devices?.find((d: any) => d.id === deviceId);
      const lastPart = device?.parts?.[device.parts.length - 1];
      if (lastPart) {
        await ticketApi.updatePart(lastPart.id, { status: 'missing' });
        await catalogApi.addToOrderQueue({
          catalog_item_id: item.id,
          inventory_item_id: inventoryItem.id,
          name: item.name,
          sku: item.sku,
          supplier_url: item.product_url,
          image_url: item.image_url,
          unit_price: item.price,
          quantity_needed: 1,
          ticket_device_part_id: lastPart.id,
          ticket_id: ticketId,
        });
      }
      return inventoryItem;
    },
    onSuccess: () => {
      toast.success('Supplier part added and queued for ordering');
      onPartAdded();
      queryClient.invalidateQueries({ queryKey: ['order-queue-summary'] });
    },
    onError: () => toast.error('Failed to add supplier part'),
  });

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center pt-20 bg-black/40" onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}>
      <div className="w-full max-w-2xl rounded-xl bg-white dark:bg-surface-800 shadow-2xl border border-surface-200 dark:border-surface-700 max-h-[70vh] flex flex-col">
        <div className="flex items-center gap-3 p-4 border-b border-surface-200 dark:border-surface-700">
          <Search className="h-5 w-5 text-surface-400" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder="Search parts by name, SKU, or description..."
            className="flex-1 bg-transparent text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none text-sm"
            autoFocus
          />
          <button onClick={onClose} className="p-1 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="flex-1 overflow-y-auto p-2">
          {debouncedQuery.length < 2 && (
            <p className="text-center text-sm text-surface-400 py-8">Type at least 2 characters to search</p>
          )}
          {searching && (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-5 w-5 animate-spin text-primary-500" />
            </div>
          )}
          {!searching && debouncedQuery.length >= 2 && (
            <>
              {inventoryItems.filter((i: any) => i.in_stock > 0).length > 0 && (
                <div className="mb-3">
                  <p className="px-3 py-1.5 text-xs font-semibold uppercase text-green-600 dark:text-green-400">In Stock</p>
                  {inventoryItems.filter((i: any) => i.in_stock > 0).map((item: any) => (
                    <div key={`inv-${item.id}`} className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-green-50 dark:hover:bg-green-900/10 group">
                      <div className="h-2 w-2 rounded-full bg-green-500 flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
                        <p className="text-xs text-surface-500">{item.sku ? `SKU: ${item.sku} · ` : ''}Stock: {item.in_stock} · {formatCurrency(item.price)}</p>
                      </div>
                      <button
                        onClick={() => addPartMut.mutate({ inventory_item_id: item.id, quantity: 1, price: item.price })}
                        disabled={addPartMut.isPending}
                        className="opacity-0 group-hover:opacity-100 inline-flex items-center gap-1 rounded-md bg-green-600 text-white px-2.5 py-1 text-xs font-medium hover:bg-green-700 transition-all disabled:opacity-50"
                      >
                        {addPartMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
                        Add
                      </button>
                    </div>
                  ))}
                </div>
              )}
              {inventoryItems.filter((i: any) => i.in_stock <= 0).length > 0 && (
                <div className="mb-3">
                  <p className="px-3 py-1.5 text-xs font-semibold uppercase text-amber-600 dark:text-amber-400">Out of Stock (In Inventory)</p>
                  {inventoryItems.filter((i: any) => i.in_stock <= 0).map((item: any) => (
                    <div key={`inv-oos-${item.id}`} className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-amber-50 dark:hover:bg-amber-900/10 group">
                      <div className="h-2 w-2 rounded-full bg-amber-500 flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
                        <p className="text-xs text-surface-500">{item.sku ? `SKU: ${item.sku} · ` : ''}Out of stock · {formatCurrency(item.price)}</p>
                      </div>
                      <button
                        onClick={() => addPartMut.mutate({ inventory_item_id: item.id, quantity: 1, price: item.price })}
                        disabled={addPartMut.isPending}
                        className="opacity-0 group-hover:opacity-100 inline-flex items-center gap-1 rounded-md bg-amber-600 text-white px-2.5 py-1 text-xs font-medium hover:bg-amber-700 transition-all disabled:opacity-50"
                      >
                        {addPartMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Plus className="h-3 w-3" />}
                        Add (order needed)
                      </button>
                    </div>
                  ))}
                </div>
              )}
              {supplierItems.length > 0 && (
                <div className="mb-3">
                  <p className="px-3 py-1.5 text-xs font-semibold uppercase text-yellow-600 dark:text-yellow-400">Available from Supplier</p>
                  {supplierItems.slice(0, 20).map((item: any) => (
                    <div key={`sup-${item.id}`} className="flex items-center gap-3 px-3 py-2 rounded-lg hover:bg-yellow-50 dark:hover:bg-yellow-900/10 group">
                      <div className="h-2 w-2 rounded-full bg-yellow-500 flex-shrink-0" />
                      <div className="flex-1 min-w-0">
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100 truncate">{item.name}</p>
                        <p className="text-xs text-surface-500">
                          {item.source} · {item.sku ? `SKU: ${item.sku} · ` : ''}{formatCurrency(item.price || 0)}
                        </p>
                      </div>
                      {item.product_url && (
                        <a href={item.product_url} target="_blank" rel="noopener noreferrer"
                          className="p-1 text-blue-500 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded">
                          <ExternalLink className="h-3.5 w-3.5" />
                        </a>
                      )}
                      <button
                        onClick={() => addSupplierPartMut.mutate(item)}
                        disabled={addSupplierPartMut.isPending}
                        className="opacity-0 group-hover:opacity-100 inline-flex items-center gap-1 rounded-md bg-yellow-600 text-white px-2.5 py-1 text-xs font-medium hover:bg-yellow-700 transition-all disabled:opacity-50"
                      >
                        {addSupplierPartMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <ShoppingCart className="h-3 w-3" />}
                        Add + Order
                      </button>
                    </div>
                  ))}
                </div>
              )}
              {inventoryItems.length === 0 && supplierItems.length === 0 && (
                <p className="text-center text-sm text-surface-400 py-8">No parts found for "{debouncedQuery}"</p>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Device Edit Form ───────────────────────────────────────────────
function DeviceEditForm({
  device,
  onSave,
  onCancel,
  isPending,
}: {
  device: any;
  onSave: (data: any) => void;
  onCancel: () => void;
  isPending: boolean;
}) {
  const [form, setForm] = useState({
    device_name: device.device_name || '',
    imei: device.imei || '',
    serial: device.serial || '',
    security_code: device.security_code || '',
    additional_notes: device.additional_notes || '',
    price: device.price ?? 0,
  });

  return (
    <div className="space-y-3 mt-3 pt-3 border-t border-surface-200 dark:border-surface-700">
      <div className="grid grid-cols-2 gap-3">
        <div>
          <label className="block text-xs font-medium text-surface-500 mb-1">Device Name</label>
          <input
            value={form.device_name}
            onChange={(e) => setForm({ ...form, device_name: e.target.value })}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
          />
        </div>
        <div>
          <label className="block text-xs font-medium text-surface-500 mb-1">Price</label>
          <input
            type="number" step="0.01"
            value={form.price}
            onChange={(e) => setForm({ ...form, price: parseFloat(e.target.value) || 0 })}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
          />
        </div>
      </div>
      <div className="grid grid-cols-3 gap-3">
        <div>
          <label className="block text-xs font-medium text-surface-500 mb-1">IMEI</label>
          <input value={form.imei} onChange={(e) => setForm({ ...form, imei: e.target.value })}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
            placeholder="IMEI number" />
        </div>
        <div>
          <label className="block text-xs font-medium text-surface-500 mb-1">Serial</label>
          <input value={form.serial} onChange={(e) => setForm({ ...form, serial: e.target.value })}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
            placeholder="Serial number" />
        </div>
        <div>
          <label className="block text-xs font-medium text-surface-500 mb-1">Passcode</label>
          <input value={form.security_code} onChange={(e) => setForm({ ...form, security_code: e.target.value })}
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
            placeholder="Device passcode" />
        </div>
      </div>
      <div>
        <label className="block text-xs font-medium text-surface-500 mb-1">Issue / Notes</label>
        <textarea value={form.additional_notes} onChange={(e) => setForm({ ...form, additional_notes: e.target.value })}
          rows={2}
          className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-1.5 text-sm dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none"
          placeholder="Describe the issue..." />
      </div>
      <div className="flex justify-end gap-2">
        <button onClick={onCancel} className="px-3 py-1.5 text-sm rounded-lg border border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-800">
          Cancel
        </button>
        <button onClick={() => onSave(form)} disabled={isPending}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm rounded-lg bg-primary-600 text-white hover:bg-primary-700 disabled:opacity-50">
          {isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
          Save
        </button>
      </div>
    </div>
  );
}

// ─── Photo Upload Section ───────────────────────────────────────────
function PhotoUploadSection({
  ticketId,
  deviceId,
  onUploaded,
}: {
  ticketId: number;
  deviceId: number;
  onUploaded: () => void;
}) {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [photoType, setPhotoType] = useState<'pre' | 'post'>('pre');

  const uploadMut = useMutation({
    mutationFn: (files: FileList) => {
      const formData = new FormData();
      Array.from(files).forEach((f) => formData.append('photos', f));
      formData.append('type', photoType);
      formData.append('ticket_device_id', String(deviceId));
      return ticketApi.uploadPhotos(ticketId, formData);
    },
    onSuccess: () => {
      toast.success('Photos uploaded');
      onUploaded();
      if (fileInputRef.current) fileInputRef.current.value = '';
    },
    onError: () => toast.error('Failed to upload photos'),
  });

  return (
    <div className="flex items-center gap-2">
      <select value={photoType} onChange={(e) => setPhotoType(e.target.value as 'pre' | 'post')}
        className="rounded-md border border-surface-200 bg-surface-50 px-2 py-1 text-xs dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300">
        <option value="pre">Pre-repair</option>
        <option value="post">Post-repair</option>
      </select>
      <input ref={fileInputRef} type="file" accept="image/*" multiple
        onChange={(e) => { if (e.target.files && e.target.files.length > 0) uploadMut.mutate(e.target.files); }}
        className="hidden" />
      <button onClick={() => fileInputRef.current?.click()} disabled={uploadMut.isPending}
        className="inline-flex items-center gap-1.5 rounded-md border border-surface-200 dark:border-surface-700 px-3 py-2 min-h-[44px] min-w-[44px] text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors disabled:opacity-50">
        {uploadMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
        Upload Photos
      </button>
    </div>
  );
}

// ─── Loading skeleton ───────────────────────────────────────────────
function DetailSkeleton() {
  return (
    <div className="animate-pulse space-y-6">
      <div className="flex items-center gap-4">
        <div className="h-8 w-8 rounded bg-surface-200 dark:bg-surface-700" />
        <div className="h-7 w-48 rounded bg-surface-200 dark:bg-surface-700" />
        <div className="h-7 w-24 rounded-full bg-surface-200 dark:bg-surface-700" />
      </div>
      <div className="grid grid-cols-3 gap-6">
        <div className="col-span-2 space-y-6">
          <div className="card h-48 p-6"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
          <div className="card h-64 p-6"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
        </div>
        <div className="space-y-4">
          <div className="card h-40 p-4"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
          <div className="card h-32 p-4"><div className="h-full rounded bg-surface-100 dark:bg-surface-800" /></div>
        </div>
      </div>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────
export function TicketDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const ticketId = Number(id);

  // ─── Fetch ticket ─────────────────────────────────────────────────
  const { data: ticketData, isLoading, error } = useQuery({
    queryKey: ['ticket', ticketId],
    queryFn: () => ticketApi.get(ticketId),
    enabled: !!ticketId,
  });
  const ticket: Ticket | undefined = ticketData?.data?.data;

  // ─── Fetch statuses ───────────────────────────────────────────────
  const { data: statusData } = useQuery({
    queryKey: ['ticket-statuses'],
    queryFn: () => settingsApi.getStatuses(),
  });
  const statuses: TicketStatus[] = statusData?.data?.data?.statuses || statusData?.data?.statuses || [];

  // ─── Fetch history ────────────────────────────────────────────────
  const { data: historyData } = useQuery({
    queryKey: ['ticket-history', ticketId],
    queryFn: () => ticketApi.getHistory(ticketId),
    enabled: !!ticketId,
  });
  const history: TicketHistory[] = (() => {
    const d = historyData?.data?.data;
    return Array.isArray(d) ? d : d?.history || ticket?.history || [];
  })();

  // ─── Fetch invoice (if linked) ────────────────────────────────────
  const { data: invoiceData } = useQuery({
    queryKey: ['invoice', ticket?.invoice_id],
    queryFn: () => invoiceApi.get(ticket!.invoice_id!),
    enabled: !!ticket?.invoice_id,
  });
  const invoice = invoiceData?.data?.data?.invoice;

  // ─── Mutations ────────────────────────────────────────────────────
  const invalidateTicket = useCallback(() => {
    queryClient.invalidateQueries({ queryKey: ['ticket', ticketId] });
    queryClient.invalidateQueries({ queryKey: ['ticket-history', ticketId] });
  }, [queryClient, ticketId]);

  const changeStatusMut = useMutation({
    mutationFn: (statusId: number) => ticketApi.changeStatus(ticketId, statusId),
    onSuccess: (_data, newStatusId) => {
      const prevStatusId = ticket?.status_id;
      const newName = statuses.find((s) => s.id === newStatusId)?.name ?? 'Unknown';
      invalidateTicket();
      toast((t) => (
        <span className="flex items-center gap-2 text-sm">
          Status changed to <b>{newName}</b>
          {prevStatusId != null && prevStatusId !== newStatusId && (
            <button
              className="ml-2 rounded bg-surface-200 px-2 py-0.5 text-xs font-medium hover:bg-surface-300 dark:bg-surface-700 dark:hover:bg-surface-600"
              onClick={() => { toast.dismiss(t.id); changeStatusMut.mutate(prevStatusId); }}
            >
              Undo
            </button>
          )}
        </span>
      ), { duration: 5000 });
    },
    onError: () => toast.error('Failed to change status'),
  });

  const addNoteMut = useMutation({
    mutationFn: (data: { type: string; content: string; is_flagged?: boolean }) =>
      ticketApi.addNote(ticketId, data),
    onSuccess: () => { toast.success('Note added'); clearNoteDraft(); invalidateTicket(); },
    onError: () => toast.error('Failed to add note'),
  });

  const deleteMut = useMutation({
    mutationFn: () => ticketApi.delete(ticketId),
    onSuccess: () => { toast.success('Ticket deleted'); navigate('/tickets'); },
    onError: () => toast.error('Failed to delete ticket'),
  });

  const convertInvoiceMut = useMutation({
    mutationFn: () => ticketApi.convertToInvoice(ticketId),
    onSuccess: (res) => {
      const inv = res?.data?.data;
      toast.success('Invoice generated');
      invalidateTicket();
      if (inv?.id) navigate(`/invoices/${inv.id}`);
    },
    onError: () => toast.error('Failed to generate invoice'),
  });

  const updateDeviceMut = useMutation({
    mutationFn: ({ deviceId, data }: { deviceId: number; data: any }) =>
      ticketApi.updateDevice(deviceId, data),
    onSuccess: () => { toast.success('Device updated'); setEditingDeviceId(null); invalidateTicket(); },
    onError: () => toast.error('Failed to update device'),
  });

  const removePartMut = useMutation({
    mutationFn: (partId: number) => ticketApi.removePart(partId),
    onSuccess: () => { toast.success('Part removed'); invalidateTicket(); },
    onError: () => toast.error('Failed to remove part'),
  });

  const updatePartMut = useMutation({
    mutationFn: ({ partId, data }: { partId: number; data: any }) =>
      ticketApi.updatePart(partId, data),
    onSuccess: () => { toast.success('Part updated'); invalidateTicket(); },
    onError: () => toast.error('Failed to update part'),
  });

  const deletePhotoMut = useMutation({
    mutationFn: (photoId: number) => ticketApi.deletePhoto(photoId),
    onSuccess: () => { toast.success('Photo deleted'); invalidateTicket(); },
    onError: () => toast.error('Failed to delete photo'),
  });

  // ─── Employees + Assign ────────────────────────────────────────────
  const currentUser = useAuthStore((s) => s.user);
  const { data: employeesData } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
    staleTime: 60_000,
  });
  const employees: any[] = employeesData?.data?.data || [];

  const assignMut = useMutation({
    mutationFn: (userId: number | null) => ticketApi.update(ticketId, { assigned_to: userId }),
    onSuccess: () => { toast.success('Ticket assigned'); invalidateTicket(); },
    onError: () => toast.error('Failed to assign'),
  });

  // ─── UI state ──────────────────────────────────────────────────────
  const [showAssignDropdown, setShowAssignDropdown] = useState(false);
  const [showSms, setShowSms] = useState(false);
  const [noteType, setNoteType] = useState('internal');
  const [noteContent, setNoteContent, clearNoteDraft, hasNoteDraft] = useDraft(`draft_note_ticket_${ticketId}`);
  const [noteFlagged, setNoteFlagged] = useState(false);
  const [noteTabFilter, setNoteTabFilter] = useState<typeof NOTE_TAB_FILTERS[number]>('All');
  const [editingDeviceId, setEditingDeviceId] = useState<number | null>(null);
  const [partsSearchDeviceId, setPartsSearchDeviceId] = useState<number | null>(null);
  const [activeTab, setActiveTab] = useState<'overview' | 'notes' | 'photos' | 'parts'>('overview');
  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  // ─── Track recent views ────────────────────────────────────────────
  useEffect(() => {
    if (!ticket) return;
    const key = 'recent_views';
    try {
      const existing: { type: string; id: number; label: string; path: string }[] = JSON.parse(localStorage.getItem(key) || '[]');
      const entry = { type: 'ticket', id: ticket.id, label: formatTicketId(ticket.order_id || ticket.id), path: `/tickets/${ticket.id}` };
      const filtered = existing.filter((e) => !(e.type === 'ticket' && e.id === ticket.id));
      filtered.unshift(entry);
      localStorage.setItem(key, JSON.stringify(filtered.slice(0, 5)));
    } catch { /* ignore */ }
  }, [ticket?.id]);

  // ─── Derived data ─────────────────────────────────────────────────
  const customer = ticket?.customer;
  const devices: TicketDevice[] = ticket?.devices || [];
  const notes: TicketNote[] = ticket?.notes || [];
  const currentStatus = statuses.find((s) => s.id === ticket?.status_id) || ticket?.status;
  const assigned = ticket?.assigned_user;

  const filteredNotes = noteTabFilter === 'All'
    ? notes
    : notes.filter((n) => n.type === noteTabFilter.toLowerCase());

  // Calculate billing totals
  const allParts = devices.flatMap((d: any) => (d.parts || []).map((p: any) => ({ ...p, deviceName: d.device_name })));
  const partsTotal = allParts.reduce((sum: number, p: any) => sum + (p.price * p.quantity), 0);
  const serviceTotal = devices.reduce((sum, d) => sum + d.price, 0);
  const paidAmount = invoice?.payments?.reduce((sum: number, p: any) => sum + Number(p.amount), 0) || 0;
  const dueAmount = (ticket?.total || 0) - paidAmount;

  // Estimated profit (rough: total minus cost prices)
  const totalCost = allParts.reduce((sum: number, p: any) => sum + ((p.cost_price || 0) * p.quantity), 0);
  const estimatedProfit = (ticket?.total || 0) - totalCost;

  // Repair time (since creation)
  const repairTimeMs = ticket ? Date.now() - new Date(ticket.created_at).getTime() : 0;
  const repairDays = Math.floor(repairTimeMs / 86400000);
  const repairHours = Math.floor((repairTimeMs % 86400000) / 3600000);

  // ─── Error / loading ──────────────────────────────────────────────
  if (isLoading) {
    return (
      <div>
        <div className="mb-6 flex items-center gap-4">
          <BackButton to="/tickets" />
          <div className="h-7 w-32 animate-pulse rounded bg-surface-200 dark:bg-surface-700" />
        </div>
        <DetailSkeleton />
      </div>
    );
  }

  if (error || !ticket) {
    return (
      <div>
        <div className="mb-6 flex items-center gap-4">
          <BackButton to="/tickets" />
        </div>
        <div className="card flex flex-col items-center justify-center py-20">
          <AlertCircle className="mb-4 h-16 w-16 text-red-300" />
          <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">Ticket Not Found</h2>
          <p className="text-sm text-surface-400">The ticket you are looking for does not exist or has been deleted.</p>
        </div>
      </div>
    );
  }

  // ─── Render ───────────────────────────────────────────────────────
  return (
    <>
    <div>
      {/* ═══════ STICKY TOP HEADER BAR ═══════ */}
      <div className="sticky -top-6 z-20 -mx-6 mb-6 border-b border-transparent bg-surface-50/95 px-6 pt-6 pb-4 backdrop-blur-sm dark:bg-surface-950/95 [.scrolled_&]:border-surface-200 dark:[.scrolled_&]:border-surface-800 [.scrolled_&]:shadow-sm">
        <Breadcrumb items={[
          { label: 'Tickets', href: '/tickets' },
          { label: formatTicketId(ticket.order_id || ticket.id) },
        ]} />

        {/* Main header row */}
        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={() => navigate('/tickets')}
            className="rounded-lg p-2 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800 dark:hover:text-surface-300"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>

          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100 flex items-center gap-1.5">
            Ticket {formatTicketId(ticket.order_id || ticket.id)}
            <CopyButton text={formatTicketId(ticket.order_id || ticket.id)} />
          </h1>

          {/* Device name pill(s) */}
          {devices.map((d: any) => (
            <span key={d.id} className="inline-flex items-center gap-1.5 rounded-full bg-surface-100 dark:bg-surface-800 px-3 py-1 text-xs font-medium text-surface-600 dark:text-surface-300">
              {(d.imei || d.serial) && <span className="h-2 w-2 rounded-full bg-green-500" title="Has IMEI/Serial" />}
              {d.device_name}
            </span>
          ))}

          {/* Status dropdown */}
          <HeaderStatusDropdown
            currentStatus={currentStatus}
            statuses={statuses}
            onSelect={(sId) => changeStatusMut.mutate(sId)}
            isPending={changeStatusMut.isPending}
          />

          {/* Checkout button — left of other actions */}
          <div className="ml-auto flex items-center gap-2">
            <button
              onClick={() => navigate(`/pos?ticket=${ticketId}`)}
              className="inline-flex items-center gap-2 rounded-lg bg-teal-600 px-5 py-2 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-teal-700 active:bg-teal-800"
            >
              <ShoppingCart className="h-4 w-4" />
              Checkout
            </button>
            <PrintButton ticketId={ticketId} invoiceId={(ticket as any)?.invoice_id} />
            <ActionsDropdown
              onPrint={() => {}}
              onDuplicate={() => toast('Duplicate not yet implemented')}
              onDelete={() => setShowDeleteConfirm(true)}
            />
          </div>
        </div>
      </div>

      {/* ═══════ TAB BUTTONS ═══════ */}
      <div className="mb-4 flex gap-1 border-b border-surface-200 dark:border-surface-700">
        {([
          { key: 'overview', label: 'Overview' },
          { key: 'notes', label: 'Notes & History' },
          { key: 'photos', label: 'Photos' },
          { key: 'parts', label: 'Parts & Billing' },
        ] as const).map((tab) => (
          <button
            key={tab.key}
            onClick={() => setActiveTab(tab.key)}
            className={cn(
              'whitespace-nowrap px-4 py-2.5 text-sm font-medium border-b-2 transition-colors',
              activeTab === tab.key
                ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300',
            )}
          >
            {tab.label}
            {tab.key === 'photos' && (() => {
              const count = devices.reduce((sum, d: any) => sum + (d.photos?.length || 0), 0);
              return count > 0 ? <span className="ml-1.5 text-[10px] bg-surface-200 dark:bg-surface-700 rounded-full px-1.5 py-0.5">{count}</span> : null;
            })()}
            {tab.key === 'parts' && (() => {
              const count = devices.reduce((sum, d: any) => sum + (d.parts?.length || 0), 0);
              return count > 0 ? <span className="ml-1.5 text-[10px] bg-surface-200 dark:bg-surface-700 rounded-full px-1.5 py-0.5">{count}</span> : null;
            })()}
            {tab.key === 'notes' && notes.length > 0 && (
              <span className="ml-1.5 text-[10px] bg-surface-200 dark:bg-surface-700 rounded-full px-1.5 py-0.5">{notes.length}</span>
            )}
          </button>
        ))}
      </div>

      {/* ═══════ TWO-COLUMN LAYOUT ═══════ */}
      <div className="grid grid-cols-1 gap-6 lg:grid-cols-[1fr_380px]">
        {/* ─── LEFT PANEL (main content, ~65%) ──────────────────── */}
        <div className="space-y-6">
          {/* Per-device cards — shown on overview tab */}
          {(activeTab === 'overview' || activeTab === 'parts') && devices.map((device: any) => {
            const DevIcon = DEVICE_ICONS[device.device_type || ''] || Smartphone;
            const parts = device.parts || [];
            const photos = device.photos || [];
            const prePhotos = photos.filter((p: any) => p.type === 'pre');
            const postPhotos = photos.filter((p: any) => p.type === 'post');
            const isEditing = editingDeviceId === device.id;

            return (
              <div key={device.id} className="card overflow-hidden">
                {/* Device header card */}
                <div className="bg-surface-50 dark:bg-surface-800/50 px-5 py-4 border-b border-surface-200 dark:border-surface-700">
                  <div className="flex items-start gap-4">
                    <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-white dark:bg-surface-800 border border-surface-200 dark:border-surface-700 shadow-sm text-surface-500 dark:text-surface-400">
                      <DevIcon className="h-6 w-6" />
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-3">
                        <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
                          {device.device_name}
                        </h3>
                        <button
                          onClick={() => {
                            const newPrice = prompt('Service / Labor Price:', String(device.price));
                            if (newPrice !== null && !isNaN(parseFloat(newPrice))) {
                              updateDeviceMut.mutate({ deviceId: device.id, data: { price: parseFloat(newPrice) } });
                            }
                          }}
                          className="text-lg font-bold text-surface-900 dark:text-surface-100 hover:text-primary-600 dark:hover:text-primary-400 cursor-pointer transition-colors"
                          title="Click to edit price"
                        >
                          {formatCurrency(device.price)}
                        </button>
                        <a href={getIFixitUrl(device.device_name, device.ifixit_url)} target="_blank" rel="noopener noreferrer"
                          className="inline-flex items-center gap-1 text-xs text-blue-500 hover:text-blue-600 hover:underline"
                          title="iFixit Repair Guide">
                          <Wrench className="h-3 w-3" /> iFixit
                        </a>
                        {(device.imei || device.serial) && (
                          <DeviceHistoryPopover imei={device.imei} serial={device.serial} currentTicketId={ticketId} />
                        )}
                      </div>
                      {(device.device_type || device.service?.name) && (
                        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">
                          {device.device_type ? device.device_type.charAt(0).toUpperCase() + device.device_type.slice(1) : ''}{device.device_type && device.service?.name ? ' — ' : ''}{device.service?.name || ''}
                        </p>
                      )}
                      <div className="flex flex-wrap items-center gap-4 mt-2 text-xs text-surface-500 dark:text-surface-400">
                        {/* Assignee */}
                        <span className="inline-flex items-center gap-1.5">
                          <div className="h-5 w-5 rounded-full bg-primary-100 dark:bg-primary-900/30 flex items-center justify-center text-[10px] font-bold text-primary-700 dark:text-primary-300">
                            {initials(device.assigned_user?.first_name || assigned?.first_name, device.assigned_user?.last_name || assigned?.last_name)}
                          </div>
                          {device.assigned_user?.first_name || assigned?.first_name || 'Unassigned'} {device.assigned_user?.last_name || assigned?.last_name || ''}
                        </span>
                        {/* Due date */}
                        {(device.due_on || ticket.due_on) && (
                          <span className="inline-flex items-center gap-1">
                            <Calendar className="h-3 w-3" />
                            Due: {formatDate(device.due_on || ticket.due_on!)}
                          </span>
                        )}
                        {/* Task type */}
                        <span className="inline-flex items-center gap-1">
                          <MapPin className="h-3 w-3" />
                          {ticket.source || 'In-Store'}
                        </span>
                        {/* Repair timer */}
                        <span className="inline-flex items-center gap-1">
                          <Timer className="h-3 w-3" />
                          {repairDays > 0 ? `${repairDays}d ${repairHours}h` : `${repairHours}h`}
                        </span>
                      </div>
                    </div>
                    {/* Actions */}
                    <div className="flex items-center gap-1">
                      {!isEditing && (
                        <button onClick={() => setEditingDeviceId(device.id)}
                          className="rounded-lg p-2 text-surface-400 hover:bg-surface-200 dark:hover:bg-surface-700 hover:text-surface-600 dark:hover:text-surface-300 transition-colors" title="Edit device">
                          <Edit3 className="h-5 w-5" />
                        </button>
                      )}
                      <button onClick={() => toast('Duplicate device not yet implemented')}
                        className="rounded-lg p-2 text-surface-400 hover:bg-surface-200 dark:hover:bg-surface-700 hover:text-surface-600 dark:hover:text-surface-300 transition-colors" title="Duplicate device">
                        <Copy className="h-5 w-5" />
                      </button>
                    </div>
                  </div>

                  {/* Status badge */}
                  {device.status && (
                    <div className="mt-3">
                      <span className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-1 text-xs font-semibold"
                        style={{
                          backgroundColor: `${device.status.color || '#6b7280'}15`,
                          color: device.status.color || '#6b7280',
                        }}>
                        <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: device.status.color || '#6b7280' }} />
                        {device.status.name}
                      </span>
                    </div>
                  )}
                </div>

                {/* Device edit form */}
                {isEditing && (
                  <div className="px-5 py-4 border-b border-surface-200 dark:border-surface-700">
                    <DeviceEditForm
                      device={device}
                      onSave={(data) => updateDeviceMut.mutate({ deviceId: device.id, data })}
                      onCancel={() => setEditingDeviceId(null)}
                      isPending={updateDeviceMut.isPending}
                    />
                  </div>
                )}

                {/* Accordion sections */}
                <div>
                  {/* Asset Issues / Service */}
                  <AccordionSection title="Asset Issues / Service" icon={Wrench}>
                    <div className="flex items-center justify-between rounded-lg bg-surface-50 dark:bg-surface-800/50 px-3 py-2">
                      <div>
                        <p className="text-sm font-medium text-surface-800 dark:text-surface-200">
                          {device.service?.name || 'Labor / Service Charge'}
                        </p>
                        <p className="text-xs text-surface-500">{device.device_name}</p>
                      </div>
                      <button
                        onClick={() => {
                          const newPrice = prompt('Service / Labor Price:', String(device.price));
                          if (newPrice !== null && !isNaN(parseFloat(newPrice))) {
                            updateDeviceMut.mutate({ deviceId: device.id, data: { price: parseFloat(newPrice) } });
                          }
                        }}
                        className="text-sm font-semibold text-surface-900 dark:text-surface-100 hover:text-primary-600 dark:hover:text-primary-400 cursor-pointer transition-colors"
                        title="Click to edit price"
                      >
                        {formatCurrency(device.price)}
                      </button>
                    </div>
                    {device.additional_notes && !isEditing && (
                      <p className="mt-2 text-xs text-surface-500 dark:text-surface-400 italic px-1">
                        {device.additional_notes}
                      </p>
                    )}
                  </AccordionSection>

                  {/* Attached Parts */}
                  <AccordionSection
                    title="Attached Parts"
                    icon={Package}
                    count={parts.length}
                    actions={
                      <button
                        onClick={() => setPartsSearchDeviceId(device.id)}
                        className="inline-flex items-center gap-1 rounded-md bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/30 px-2 py-0.5 text-xs font-medium transition-colors"
                      >
                        <Plus className="h-3 w-3" /> Add Part
                      </button>
                    }
                  >
                    {parts.length === 0 ? (
                      <p className="text-xs text-surface-400 italic py-1">No parts added yet</p>
                    ) : (
                      <div className="space-y-1.5">
                        {parts.map((p: any) => (
                          <div key={p.id} className="flex items-center gap-2 rounded-lg bg-surface-50 dark:bg-surface-800/50 px-3 py-2 group">
                            <div className="flex-1 min-w-0">
                              <div className="flex items-center gap-2">
                                <span className="text-xs font-medium text-surface-800 dark:text-surface-200 truncate">
                                  {p.item_name || `Item #${p.inventory_item_id}`}
                                </span>
                                <span className="text-xs text-surface-500">x{p.quantity}</span>
                                {p.status && p.status !== 'available' && (
                                  <span className={cn('text-[10px] font-medium px-1.5 py-0.5 rounded', PART_STATUS_COLORS[p.status] || '')}>
                                    {p.status}
                                  </span>
                                )}
                              </div>
                              {p.item_sku && <span className="text-[10px] text-surface-400">SKU: {p.item_sku}</span>}
                            </div>
                            <span className="text-xs font-medium text-surface-700 dark:text-surface-300">
                              {formatCurrency(p.price * p.quantity)}
                            </span>
                            <select
                              value={p.status || 'available'}
                              onChange={(e) => updatePartMut.mutate({ partId: p.id, data: { status: e.target.value } })}
                              className="opacity-0 group-hover:opacity-100 transition-opacity rounded border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-[10px] px-1 py-0.5 focus:outline-none focus:opacity-100"
                            >
                              <option value="available">Available</option>
                              <option value="missing">Missing</option>
                              <option value="ordered">Ordered</option>
                              <option value="received">Received</option>
                            </select>
                            <button
                              onClick={() => { if (confirm('Remove this part?')) removePartMut.mutate(p.id); }}
                              className="opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded text-red-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20"
                              title="Remove part"
                            >
                              <X className="h-3 w-3" />
                            </button>
                          </div>
                        ))}
                      </div>
                    )}
                  </AccordionSection>

                  {/* Additional Details */}
                  <AccordionSection title="Additional Details" icon={FileText} defaultOpen={false}>
                    <div className="grid grid-cols-2 gap-x-6 gap-y-2 text-xs">
                      {device.imei && (
                        <div className="flex justify-between"><span className="text-surface-500">IMEI</span><span className="font-mono text-surface-700 dark:text-surface-300">{device.imei}</span></div>
                      )}
                      {device.serial && (
                        <div className="flex justify-between"><span className="text-surface-500">Serial</span><span className="font-mono text-surface-700 dark:text-surface-300">{device.serial}</span></div>
                      )}
                      {device.security_code && (
                        <div className="flex justify-between"><span className="text-surface-500">Passcode</span><span className="font-mono text-surface-700 dark:text-surface-300">{device.security_code}</span></div>
                      )}
                      {device.color && (
                        <div className="flex justify-between"><span className="text-surface-500">Color</span><span className="text-surface-700 dark:text-surface-300">{device.color}</span></div>
                      )}
                      {device.network && (
                        <div className="flex justify-between"><span className="text-surface-500">Network</span><span className="text-surface-700 dark:text-surface-300">{device.network}</span></div>
                      )}
                      {device.device_location && (
                        <div className="flex justify-between"><span className="text-surface-500">Location</span><span className="text-surface-700 dark:text-surface-300">{device.device_location}</span></div>
                      )}
                      {device.warranty && (
                        <div className="flex justify-between"><span className="text-surface-500">Warranty</span><span className="text-surface-700 dark:text-surface-300">{device.warranty_days} days</span></div>
                      )}
                    </div>
                  </AccordionSection>

                  {/* Pre/Post Repair Images */}
                  <AccordionSection
                    title="Pre/Post Repair Images"
                    icon={Image}
                    count={photos.length}
                    defaultOpen={photos.length > 0}
                  >
                    {prePhotos.length > 0 && (
                      <div className="mb-3">
                        <p className="text-xs font-medium text-amber-600 dark:text-amber-400 mb-1.5">Pre-Repair</p>
                        <div className="flex flex-wrap gap-2">
                          {prePhotos.map((photo: any) => (
                            <div key={photo.id} className="relative group">
                              <a href={`/uploads/${photo.file_path}`} target="_blank" rel="noopener noreferrer">
                                <img src={`/uploads/${photo.file_path}`} alt={photo.caption || 'Pre-repair'}
                                  className="h-20 w-20 rounded-lg object-cover border border-surface-200 dark:border-surface-700 group-hover:opacity-80 transition-opacity" />
                              </a>
                              <button onClick={() => { if (confirm('Delete this photo?')) deletePhotoMut.mutate(photo.id); }}
                                className="absolute -top-1 -right-1 hidden group-hover:flex items-center justify-center h-5 w-5 rounded-full bg-red-500 text-white shadow">
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    {postPhotos.length > 0 && (
                      <div className="mb-3">
                        <p className="text-xs font-medium text-green-600 dark:text-green-400 mb-1.5">Post-Repair</p>
                        <div className="flex flex-wrap gap-2">
                          {postPhotos.map((photo: any) => (
                            <div key={photo.id} className="relative group">
                              <a href={`/uploads/${photo.file_path}`} target="_blank" rel="noopener noreferrer">
                                <img src={`/uploads/${photo.file_path}`} alt={photo.caption || 'Post-repair'}
                                  className="h-20 w-20 rounded-lg object-cover border border-surface-200 dark:border-surface-700 group-hover:opacity-80 transition-opacity" />
                              </a>
                              <button onClick={() => { if (confirm('Delete this photo?')) deletePhotoMut.mutate(photo.id); }}
                                className="absolute -top-1 -right-1 hidden group-hover:flex items-center justify-center h-5 w-5 rounded-full bg-red-500 text-white shadow">
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    <PhotoUploadSection ticketId={ticketId} deviceId={device.id} onUploaded={invalidateTicket} />
                  </AccordionSection>

                  {/* Pre/Post Repair Conditions */}
                  {(device.pre_conditions?.length > 0 || device.post_conditions?.length > 0) && (
                    <AccordionSection title="Pre/Post Repair Conditions" icon={CheckCircle2} defaultOpen={false}>
                      {device.pre_conditions?.length > 0 && (
                        <div className="mb-3">
                          <p className="text-xs font-semibold text-surface-600 dark:text-surface-300 mb-1">Pre-Repair</p>
                          <div className="flex flex-wrap gap-1.5">
                            {device.pre_conditions.map((c: string, i: number) => (
                              <span key={i} className="inline-flex items-center gap-1 rounded-full bg-amber-50 dark:bg-amber-900/20 px-2 py-0.5 text-xs text-amber-700 dark:text-amber-300">
                                <CheckCircle2 className="h-3 w-3" /> {c}
                              </span>
                            ))}
                          </div>
                        </div>
                      )}
                      {device.post_conditions?.length > 0 && (
                        <div>
                          <p className="text-xs font-semibold text-surface-600 dark:text-surface-300 mb-1">Post-Repair</p>
                          <div className="flex flex-wrap gap-1.5">
                            {device.post_conditions.map((c: string, i: number) => (
                              <span key={i} className="inline-flex items-center gap-1 rounded-full bg-green-50 dark:bg-green-900/20 px-2 py-0.5 text-xs text-green-700 dark:text-green-300">
                                <CheckCircle2 className="h-3 w-3" /> {c}
                              </span>
                            ))}
                          </div>
                        </div>
                      )}
                    </AccordionSection>
                  )}
                </div>
              </div>
            );
          })}

          {(activeTab === 'overview' || activeTab === 'parts') && devices.length === 0 && (
            <div className="card p-6">
              <p className="py-8 text-center text-sm text-surface-400">No devices on this ticket</p>
            </div>
          )}

          {/* ═══════ PHOTOS TAB — all device photos in one view ═══════ */}
          {activeTab === 'photos' && (
            <div className="card p-6 space-y-6">
              <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100 flex items-center gap-2">
                <Image className="h-5 w-5 text-surface-400" /> All Device Photos
              </h2>
              {devices.map((device: any) => {
                const photos = device.photos || [];
                const prePhotos = photos.filter((p: any) => p.type === 'pre');
                const postPhotos = photos.filter((p: any) => p.type === 'post');
                if (photos.length === 0 && !device.id) return null;
                return (
                  <div key={device.id}>
                    <h3 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-2">{device.device_name}</h3>
                    {prePhotos.length > 0 && (
                      <div className="mb-3">
                        <p className="text-xs font-medium text-amber-600 dark:text-amber-400 mb-1.5">Pre-Repair</p>
                        <div className="flex flex-wrap gap-2">
                          {prePhotos.map((photo: any) => (
                            <div key={photo.id} className="relative group">
                              <a href={`/uploads/${photo.file_path}`} target="_blank" rel="noopener noreferrer">
                                <img src={`/uploads/${photo.file_path}`} alt={photo.caption || 'Pre-repair'}
                                  className="h-24 w-24 rounded-lg object-cover border border-surface-200 dark:border-surface-700 group-hover:opacity-80 transition-opacity" />
                              </a>
                              <button onClick={() => { if (confirm('Delete this photo?')) deletePhotoMut.mutate(photo.id); }}
                                className="absolute -top-1 -right-1 hidden group-hover:flex items-center justify-center h-5 w-5 rounded-full bg-red-500 text-white shadow">
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    {postPhotos.length > 0 && (
                      <div className="mb-3">
                        <p className="text-xs font-medium text-green-600 dark:text-green-400 mb-1.5">Post-Repair</p>
                        <div className="flex flex-wrap gap-2">
                          {postPhotos.map((photo: any) => (
                            <div key={photo.id} className="relative group">
                              <a href={`/uploads/${photo.file_path}`} target="_blank" rel="noopener noreferrer">
                                <img src={`/uploads/${photo.file_path}`} alt={photo.caption || 'Post-repair'}
                                  className="h-24 w-24 rounded-lg object-cover border border-surface-200 dark:border-surface-700 group-hover:opacity-80 transition-opacity" />
                              </a>
                              <button onClick={() => { if (confirm('Delete this photo?')) deletePhotoMut.mutate(photo.id); }}
                                className="absolute -top-1 -right-1 hidden group-hover:flex items-center justify-center h-5 w-5 rounded-full bg-red-500 text-white shadow">
                                <X className="h-3 w-3" />
                              </button>
                            </div>
                          ))}
                        </div>
                      </div>
                    )}
                    <PhotoUploadSection ticketId={ticketId} deviceId={device.id} onUploaded={invalidateTicket} />
                  </div>
                );
              })}
              {devices.every((d: any) => !(d.photos?.length)) && (
                <p className="text-sm text-surface-400 text-center py-6">No photos yet. Upload photos for each device above.</p>
              )}
            </div>
          )}

          {/* ═══════ NOTES SECTION ═══════ */}
          {(activeTab === 'notes' || activeTab === 'overview') && (
          <div className="card p-6">
            {/* Tabs: selecting a tab both filters AND sets the compose type */}
            <div className="flex gap-1 border-b border-surface-200 dark:border-surface-700 mb-4 overflow-x-auto">
              {NOTE_TAB_FILTERS.map((tab) => {
                const typeForTab = tab === 'All' ? noteType : tab.toLowerCase();
                return (
                  <button key={tab} onClick={() => {
                    setNoteTabFilter(tab);
                    if (tab !== 'All') setNoteType(tab.toLowerCase());
                  }}
                    className={cn(
                      'whitespace-nowrap px-3 py-2.5 text-sm font-medium border-b-2 transition-colors',
                      noteTabFilter === tab
                        ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                        : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300',
                    )}>
                    {tab}
                    {tab !== 'All' && (() => {
                      const count = notes.filter(n => n.type === tab.toLowerCase()).length;
                      return count > 0 ? <span className="ml-1.5 text-[10px] bg-surface-200 dark:bg-surface-700 rounded-full px-1.5 py-0.5">{count}</span> : null;
                    })()}
                  </button>
                );
              })}
            </div>

            {/* Compose area at top (like RepairDesk) */}
            <div className="mb-4 border border-surface-200 dark:border-surface-700 rounded-lg overflow-hidden">
              <div className="flex items-center gap-3 px-3 py-2 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                <span className="text-xs text-surface-500">Type:</span>
                <select value={noteType} onChange={(e) => { setNoteType(e.target.value); setNoteTabFilter(e.target.value === 'internal' ? 'Internal' : e.target.value === 'diagnostic' ? 'Diagnostic' : e.target.value === 'email' ? 'Email' : 'All'); }}
                  className="rounded border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800 px-2 py-1 text-xs font-medium text-surface-700 dark:text-surface-300 focus:outline-none focus:ring-1 focus:ring-primary-500/30">
                  {NOTE_TYPES.map((t) => <option key={t.value} value={t.value}>{t.label}</option>)}
                </select>
                <button onClick={() => setNoteFlagged((v) => !v)}
                  className={cn('rounded p-1 transition-colors',
                    noteFlagged ? 'bg-amber-50 text-amber-500 dark:bg-amber-950/30' : 'text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700',
                  )} title="Flag this note">
                  <Flag className="h-3.5 w-3.5" />
                </button>
                <div className="ml-auto flex items-center gap-2">
                  <button
                    onClick={() => {
                      if (!noteContent.trim()) { toast.error('Note cannot be empty'); return; }
                      setNoteFlagged(true);
                      addNoteMut.mutate({ type: noteType, content: noteContent.trim(), is_flagged: true });
                    }}
                    disabled={addNoteMut.isPending || !noteContent.trim()}
                    className="inline-flex items-center gap-1 rounded-md border border-surface-200 dark:border-surface-700 px-2.5 py-1 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700 disabled:opacity-50 transition-colors"
                  >
                    <Flag className="h-3 w-3" /> Save & Flag
                  </button>
                  <button
                    onClick={() => {
                      if (!noteContent.trim()) { toast.error('Note cannot be empty'); return; }
                      addNoteMut.mutate({ type: noteType, content: noteContent.trim(), is_flagged: noteFlagged });
                    }}
                    disabled={addNoteMut.isPending || !noteContent.trim()}
                    className="inline-flex items-center gap-1 rounded-md bg-primary-600 hover:bg-primary-700 text-white px-3 py-1 text-xs font-medium disabled:opacity-50 transition-colors"
                  >
                    {addNoteMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Send className="h-3 w-3" />}
                    Save
                  </button>
                </div>
              </div>
              <textarea value={noteContent} onChange={(e) => setNoteContent(e.target.value)}
                rows={3} placeholder={`Enter ${noteType} comment...`}
                className="w-full px-3 py-2 text-sm bg-white dark:bg-surface-900 text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none resize-y" />
            </div>

            {/* Note list */}
            {filteredNotes.length === 0 ? (
              <p className="py-6 text-center text-sm text-surface-400">No notes yet</p>
            ) : (
              <div className="space-y-3">
                {filteredNotes.map((note) => {
                  const bgColor = note.type === 'diagnostic'
                    ? 'bg-amber-50/50 dark:bg-amber-900/10 border-l-2 border-l-amber-400'
                    : note.type === 'email'
                    ? 'bg-blue-50/50 dark:bg-blue-900/10 border-l-2 border-l-blue-400'
                    : '';
                  return (
                    <div key={note.id} className={cn('flex gap-3 rounded-lg p-3', bgColor)}>
                      <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary-100 text-xs font-medium text-primary-700 dark:bg-primary-900/30 dark:text-primary-300">
                        {initials(note.user?.first_name, note.user?.last_name)}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2 flex-wrap">
                          <span className="text-sm font-medium text-surface-800 dark:text-surface-200">
                            {note.user ? `${note.user.first_name} ${note.user.last_name}` : 'System'}
                          </span>
                          <span className={cn('text-[10px] font-medium px-1.5 py-0.5 rounded',
                            note.type === 'diagnostic' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                            : note.type === 'email' ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                            : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                          )}>{note.type}</span>
                          {note.is_flagged && <Flag className="h-3 w-3 text-amber-500" />}
                          <span className="text-xs text-surface-400">{formatDateTime(note.created_at)}</span>
                        </div>
                        <p className="mt-1 text-sm text-surface-700 dark:text-surface-300 whitespace-pre-wrap">{note.content}</p>
                      </div>
                      <div className="flex items-start gap-1 opacity-0 group-hover:opacity-100">
                        <button className="p-1 rounded text-surface-400 hover:text-amber-500 hover:bg-amber-50 dark:hover:bg-amber-900/20" title="Flag">
                          <Flag className="h-3 w-3" />
                        </button>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          )}

          {/* ═══════ ACTIVITY TIMELINE ═══════ */}
          {(activeTab === 'notes' || activeTab === 'overview') && (
          <div className="card p-6">
            <div className="mb-4 flex items-center gap-2">
              <History className="h-5 w-5 text-surface-400" />
              <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100">Activity Timeline</h2>
            </div>

            {history.length === 0 ? (
              <p className="py-6 text-center text-sm text-surface-400">No activity yet</p>
            ) : (
              <div className="relative space-y-0">
                <div className="absolute left-[15px] top-2 bottom-2 w-px bg-surface-200 dark:bg-surface-700" />
                {history.map((event) => (
                  <div key={event.id} className="relative flex gap-3 pb-4">
                    <div className="relative z-10 flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400">
                      {event.user ? (
                        <span className="text-[10px] font-semibold">{initials(event.user.first_name, event.user.last_name)}</span>
                      ) : (
                        <Clock className="h-3.5 w-3.5" />
                      )}
                    </div>
                    <div className="flex-1 pt-1">
                      <p className="text-sm text-surface-700 dark:text-surface-300"
                        dangerouslySetInnerHTML={{
                          __html: DOMPurify.sanitize(event.description || '', {
                            ALLOWED_TAGS: ['b', 'i', 'em', 'strong'],
                            ALLOWED_ATTR: [],
                          })
                        }}
                      />
                      <p className="mt-0.5 text-xs text-surface-400">
                        {event.user ? `${event.user.first_name} ${event.user.last_name}` : 'System'}
                        {' '}&middot;{' '}{formatDateTime(event.created_at)}
                        {' '}&middot;{' '}<span className="text-surface-300 dark:text-surface-500">{timeAgo(event.created_at)}</span>
                      </p>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
          )}
        </div>

        {/* ─── RIGHT PANEL (sidebar, ~35%) ──────────────────────── */}
        <div className="space-y-4">
          {/* Customer Information */}
          {customer && (
            <div className="card p-5">
              <div className="mb-3 flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <User className="h-4 w-4 text-surface-400" />
                  <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Customer Information</h3>
                </div>
                <div className="flex items-center gap-1">
                  {(customer.mobile || customer.phone) && (
                    <a href={`tel:${customer.mobile || customer.phone}`}
                      className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 hover:bg-green-100 dark:hover:bg-green-900/30 transition-colors"
                      title="Call">
                      <Phone className="h-3 w-3" /> Call
                    </a>
                  )}
                  <button onClick={() => setShowSms(true)}
                    className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/30 transition-colors"
                    title="Send SMS">
                    <MessageSquare className="h-3 w-3" /> SMS
                  </button>
                  {customer.email && (
                    <a href={`mailto:${customer.email}`}
                      className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-amber-50 dark:bg-amber-900/20 text-amber-600 dark:text-amber-400 hover:bg-amber-100 dark:hover:bg-amber-900/30 transition-colors"
                      title="Email">
                      <Mail className="h-3 w-3" /> Email
                    </a>
                  )}
                </div>
              </div>
              <div className="space-y-2.5">
                <Link to={`/customers/${customer.id}`}
                  className="text-sm font-semibold text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300">
                  {customer.first_name} {customer.last_name}
                </Link>
                {customer.email && (
                  <div className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
                    <Mail className="h-3.5 w-3.5 text-surface-400" />
                    <a href={`mailto:${customer.email}`} className="hover:text-primary-600 truncate">{customer.email}</a>
                  </div>
                )}
                {(customer.mobile || customer.phone) && (
                  <PhoneActionRow
                    phone={(customer.mobile || customer.phone)!}
                    customerName={`${customer.first_name} ${customer.last_name}`}
                    ticketId={ticketId}
                    onSms={() => setShowSms(true)}
                  />
                )}
                {customer.organization && (
                  <div className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400">
                    <Tag className="h-3.5 w-3.5 text-surface-400" />
                    <span>{customer.organization}</span>
                  </div>
                )}
                <div className="pt-2 flex gap-2">
                  <Link to={`/customers/${customer.id}`}
                    className="flex-1 text-center rounded-lg border border-surface-200 dark:border-surface-700 px-2 py-1.5 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
                    More
                  </Link>
                  <Link to={`/customers/${customer.id}#assets`}
                    className="flex-1 text-center rounded-lg border border-surface-200 dark:border-surface-700 px-2 py-1.5 text-xs font-medium text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors">
                    Customer Assets
                  </Link>
                </div>
              </div>
            </div>
          )}

          {/* Warranty Information */}
          {devices.some((d) => d.warranty) && (
            <div className="card p-5">
              <div className="mb-3 flex items-center gap-2">
                <CheckCircle2 className="h-4 w-4 text-surface-400" />
                <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Warranty Information</h3>
              </div>
              {devices.filter((d) => d.warranty).map((d) => {
                const daysRemaining = d.warranty_days ? Math.max(0, d.warranty_days - Math.floor((Date.now() - new Date(d.created_at).getTime()) / 86400000)) : 0;
                return (
                  <div key={d.id} className="flex items-center justify-between text-sm mb-1.5 last:mb-0">
                    <span className="text-surface-600 dark:text-surface-400">{d.service?.name || d.device_name}</span>
                    <span className={cn(
                      'rounded-full px-2 py-0.5 text-xs font-medium',
                      daysRemaining > 30 ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                        : daysRemaining > 0 ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300'
                        : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                    )}>
                      {daysRemaining > 0 ? `${daysRemaining} days left` : 'Expired'}
                    </span>
                  </div>
                );
              })}
            </div>
          )}

          {/* Billing Card */}
          <div className="card p-5">
            <div className="mb-3 flex items-center gap-2">
              <DollarSign className="h-4 w-4 text-surface-400" />
              <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Billing</h3>
            </div>
            <div className="space-y-2 text-sm">
              {/* Line items: service charges */}
              {devices.map((d) => (
                <div key={d.id} className="flex justify-between items-center">
                  <span className="text-surface-600 dark:text-surface-400 truncate pr-2" title={`${d.device_name} — ${d.service?.name || 'Labor'}`}>
                    {d.service?.name || 'Labor / Service'} — {d.device_name}
                  </span>
                  <button
                    onClick={() => {
                      const newPrice = prompt('Service / Labor Price:', String(d.price));
                      if (newPrice !== null && !isNaN(parseFloat(newPrice))) {
                        updateDeviceMut.mutate({ deviceId: d.id, data: { price: parseFloat(newPrice) } });
                      }
                    }}
                    className="text-surface-800 dark:text-surface-200 shrink-0 hover:text-primary-600 dark:hover:text-primary-400 cursor-pointer transition-colors"
                    title="Click to edit"
                  >
                    {formatCurrency(d.price)}
                  </button>
                </div>
              ))}
              {/* Line items: parts */}
              {allParts.map((p: any) => (
                <div key={p.id} className="flex justify-between items-center">
                  <span className="text-surface-600 dark:text-surface-400 truncate pr-2">
                    {p.item_name || `Part #${p.inventory_item_id}`} x{p.quantity}
                  </span>
                  <button
                    onClick={() => {
                      const newPrice = prompt('Part price per unit:', String(p.price));
                      if (newPrice !== null && !isNaN(parseFloat(newPrice))) {
                        updatePartMut.mutate({ partId: p.id, data: { price: parseFloat(newPrice) } });
                      }
                    }}
                    className="text-surface-800 dark:text-surface-200 shrink-0 hover:text-primary-600 dark:hover:text-primary-400 cursor-pointer transition-colors"
                    title="Click to edit"
                  >
                    {formatCurrency(p.price * p.quantity)}
                  </button>
                </div>
              ))}

              <div className="border-t border-surface-100 dark:border-surface-800 pt-2 mt-2 space-y-1.5">
                <div className="flex justify-between">
                  <span className="text-surface-500 dark:text-surface-400">Subtotal</span>
                  <span className="text-surface-800 dark:text-surface-200">{formatCurrency(ticket.subtotal)}</span>
                </div>
                {ticket.discount > 0 && (
                  <div className="flex justify-between">
                    <span className="text-surface-500 dark:text-surface-400">
                      Discount{ticket.discount_reason ? ` (${ticket.discount_reason})` : ''}
                    </span>
                    <span className="text-red-500">-{formatCurrency(ticket.discount)}</span>
                  </div>
                )}
                <div className="flex justify-between">
                  <span className="text-surface-500 dark:text-surface-400">Tax</span>
                  <span className="text-surface-800 dark:text-surface-200">{formatCurrency(ticket.total_tax)}</span>
                </div>
              </div>

              {/* Total / Paid / Due badges */}
              <div className="border-t border-surface-200 dark:border-surface-700 pt-3 mt-2 space-y-2">
                <div className="flex justify-between items-center">
                  <span className="font-semibold text-surface-900 dark:text-surface-100">Total</span>
                  <span className="inline-flex items-center rounded-lg bg-surface-100 dark:bg-surface-800 px-3 py-1 font-bold text-surface-900 dark:text-surface-100">
                    {formatCurrency(ticket.total)}
                  </span>
                </div>
                <div className="flex justify-between items-center">
                  <span className={paidAmount > 0 ? "text-green-600 dark:text-green-400 font-medium" : "text-surface-400 dark:text-surface-500 font-medium"}>Paid</span>
                  <span className={paidAmount > 0 ? "inline-flex items-center rounded-lg bg-green-50 dark:bg-green-900/20 px-3 py-1 font-bold text-green-700 dark:text-green-300" : "inline-flex items-center rounded-lg bg-surface-50 dark:bg-surface-800 px-3 py-1 font-bold text-surface-400 dark:text-surface-500"}>
                    {formatCurrency(paidAmount)}
                  </span>
                </div>
                {dueAmount > 0 && (
                  <div className="flex justify-between items-center">
                    <span className="text-red-600 dark:text-red-400 font-medium">Due</span>
                    <span className="inline-flex items-center rounded-lg bg-red-50 dark:bg-red-900/20 px-3 py-1 font-bold text-red-700 dark:text-red-300">
                      {formatCurrency(dueAmount)}
                    </span>
                  </div>
                )}
              </div>

              {/* Estimated Profit — only shown when cost data exists */}
              {totalCost > 0 && (
              <div className="border-t border-surface-100 dark:border-surface-800 pt-2 mt-2">
                <div className="flex justify-between items-center">
                  <span className="text-surface-500 dark:text-surface-400 flex items-center gap-1">
                    <TrendingUp className="h-3 w-3" /> Est. Profit
                  </span>
                  <span className={cn('text-sm font-semibold', estimatedProfit >= 0 ? 'text-green-600 dark:text-green-400' : 'text-red-600 dark:text-red-400')}>
                    {formatCurrency(estimatedProfit)}
                  </span>
                </div>
              </div>
              )}
            </div>
          </div>

          {/* Ticket Summary */}
          <div className="card p-5">
            <div className="mb-3 flex items-center gap-2">
              <Receipt className="h-4 w-4 text-surface-400" />
              <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Ticket Summary</h3>
            </div>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between items-center relative">
                <span className="text-surface-500 dark:text-surface-400">Assignee</span>
                <div className="relative">
                  <button
                    onClick={() => setShowAssignDropdown(!showAssignDropdown)}
                    className="text-surface-700 dark:text-surface-300 hover:text-teal-600 dark:hover:text-teal-400 border-b border-dashed border-surface-300 dark:border-surface-600 cursor-pointer"
                  >
                    {assigned ? `${assigned.first_name} ${assigned.last_name}` : 'Unassigned'}
                  </button>
                  {showAssignDropdown && (
                    <div className="absolute right-0 top-full z-20 mt-1 w-48 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                      {currentUser && (!assigned || assigned.id !== currentUser.id) && (
                        <button
                          onClick={() => { assignMut.mutate(currentUser.id); setShowAssignDropdown(false); }}
                          className="w-full px-3 py-2 text-left text-xs font-medium text-teal-600 hover:bg-teal-50 dark:text-teal-400 dark:hover:bg-teal-900/20"
                        >
                          Assign to me
                        </button>
                      )}
                      {employees.map((emp: any) => (
                        <button
                          key={emp.id}
                          onClick={() => { assignMut.mutate(emp.id); setShowAssignDropdown(false); }}
                          className={cn('w-full px-3 py-1.5 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700',
                            ticket?.assigned_to === emp.id ? 'font-bold text-teal-600 dark:text-teal-400' : 'text-surface-700 dark:text-surface-300'
                          )}
                        >
                          {emp.first_name} {emp.last_name}
                        </button>
                      ))}
                      {assigned && (
                        <button
                          onClick={() => { assignMut.mutate(null as any); setShowAssignDropdown(false); }}
                          className="w-full border-t border-surface-200 px-3 py-1.5 text-left text-xs text-red-500 hover:bg-red-50 dark:border-surface-700 dark:hover:bg-red-900/10"
                        >
                          Unassign
                        </button>
                      )}
                    </div>
                  )}
                </div>
              </div>
              <div className="flex justify-between">
                <span className="text-surface-500 dark:text-surface-400">Created</span>
                <span className="text-surface-700 dark:text-surface-300">{formatDateTime(ticket.created_at)}</span>
              </div>
              <div className="flex justify-between">
                <span className="text-surface-500 dark:text-surface-400">Updated</span>
                <span className="text-surface-700 dark:text-surface-300">{formatDateTime(ticket.updated_at)}</span>
              </div>
              {ticket.due_on && (
                <div className="flex justify-between">
                  <span className="text-surface-500 dark:text-surface-400">Due Date</span>
                  <span className="font-medium text-surface-800 dark:text-surface-200">{formatDate(ticket.due_on)}</span>
                </div>
              )}
              {ticket.source && (
                <div className="flex justify-between">
                  <span className="text-surface-500 dark:text-surface-400">Source</span>
                  <span className="text-surface-700 dark:text-surface-300">{ticket.source}</span>
                </div>
              )}
              {ticket.referral_source && (
                <div className="flex justify-between">
                  <span className="text-surface-500 dark:text-surface-400">Referral</span>
                  <span className="text-surface-700 dark:text-surface-300">{ticket.referral_source}</span>
                </div>
              )}
            </div>
          </div>

          {/* Invoice card */}
          <div className="card p-5">
            <div className="mb-3 flex items-center gap-2">
              <FileText className="h-4 w-4 text-surface-400" />
              <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Invoice</h3>
            </div>
            {ticket.invoice_id ? (
              <div className="space-y-2 text-sm">
                <div className="flex justify-between items-center">
                  <Link to={`/invoices/${ticket.invoice_id}`}
                    className="inline-flex items-center gap-1.5 font-medium text-primary-600 hover:text-primary-700 dark:text-primary-400">
                    <ExternalLink className="h-3.5 w-3.5" />
                    Invoice #{invoice?.order_id || ticket.invoice_id}
                  </Link>
                  {invoice?.status && (
                    <span className={cn('rounded-full px-2 py-0.5 text-xs font-medium',
                      invoice.status === 'Paid' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                        : invoice.status === 'Partial' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300'
                        : 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300'
                    )}>
                      {invoice.status}
                    </span>
                  )}
                </div>
                {invoice && (
                  <>
                    <div className="flex justify-between text-xs text-surface-500 dark:text-surface-400">
                      <span>Created</span>
                      <span>{formatDate(invoice.created_at || invoice.created_date)}</span>
                    </div>
                    {invoice.due_on && (
                      <div className="flex justify-between text-xs text-surface-500 dark:text-surface-400">
                        <span>Due</span>
                        <span>{formatDate(invoice.due_on)}</span>
                      </div>
                    )}
                    <div className="flex justify-between text-xs">
                      <span className="text-surface-500 dark:text-surface-400">Amount</span>
                      <span className="font-medium text-surface-800 dark:text-surface-200">{formatCurrency(invoice.total)}</span>
                    </div>
                    <div className="flex justify-between text-xs">
                      <span className="text-surface-500 dark:text-surface-400">Paid</span>
                      <span className={cn('font-medium', paidAmount > 0 ? 'text-green-600 dark:text-green-400' : 'text-surface-400 dark:text-surface-500')}>{formatCurrency(paidAmount)}</span>
                    </div>
                  </>
                )}
              </div>
            ) : (
              <button onClick={() => convertInvoiceMut.mutate()} disabled={convertInvoiceMut.isPending}
                className="inline-flex items-center gap-1.5 rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800 disabled:opacity-50">
                {convertInvoiceMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FileText className="h-3.5 w-3.5" />}
                Generate Invoice
              </button>
            )}
          </div>

          {/* Labels */}
          {ticket.labels && ticket.labels.length > 0 && (
            <div className="card p-5">
              <div className="mb-3 flex items-center gap-2">
                <Tag className="h-4 w-4 text-surface-400" />
                <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Labels</h3>
              </div>
              <div className="flex flex-wrap gap-1.5">
                {ticket.labels.map((label) => (
                  <span key={label}
                    className="inline-flex items-center rounded-full bg-surface-100 px-2.5 py-0.5 text-xs font-medium text-surface-700 dark:bg-surface-700 dark:text-surface-300">
                    {label}
                  </span>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>

    {/* SMS Modal */}
    {showSms && customer && (
      <QuickSmsModal
        onClose={() => setShowSms(false)}
        customer={customer as any}
        ticket={{ id: ticketId, order_id: (ticket as any)?.order_id || '' }}
        device={devices[0] ? { name: (devices[0] as any).device_name || (devices[0] as any).name || '' } : undefined}
      />
    )}

    {/* Parts Search Modal */}
    {/* Sticky quick-note input at bottom */}
    <div className="fixed bottom-0 left-0 right-0 z-40 border-t border-surface-200 bg-white/95 backdrop-blur-sm dark:border-surface-700 dark:bg-surface-900/95 px-4 py-2 md:left-64">
      <form
        className="mx-auto flex max-w-4xl items-center gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          if (!noteContent.trim()) return;
          addNoteMut.mutate({ type: 'internal', content: noteContent.trim(), is_flagged: false });
        }}
      >
        <div className="relative flex-1">
          <input
            type="text"
            value={noteContent}
            onChange={(e) => setNoteContent(e.target.value)}
            placeholder="Quick note... (Enter to save)"
            className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          />
          {hasNoteDraft && (
            <span className="absolute right-2 top-1/2 -translate-y-1/2 text-[10px] text-surface-400">Draft saved</span>
          )}
        </div>
        <button
          type="submit"
          disabled={addNoteMut.isPending || !noteContent.trim()}
          className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50"
        >
          {addNoteMut.isPending ? '...' : 'Add Note'}
        </button>
      </form>
    </div>

    {partsSearchDeviceId && (
      <PartsSearchModal
        deviceId={partsSearchDeviceId}
        ticketId={ticketId}
        deviceModelId={devices.find((d: any) => d.id === partsSearchDeviceId)?.device_model_id ?? undefined}
        onClose={() => setPartsSearchDeviceId(null)}
        onPartAdded={() => {
          setPartsSearchDeviceId(null);
          invalidateTicket();
        }}
      />
    )}

    <ConfirmDialog
      open={showDeleteConfirm}
      title={`Delete Ticket ${ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : ''}`}
      message="This action cannot be undone. All ticket data, notes, photos, and parts will be permanently deleted."
      confirmLabel="Delete"
      danger
      requireTyping
      confirmText={ticket ? `T-${String(ticket.order_id).padStart(4, '0')}` : 'DELETE'}
      onConfirm={() => { setShowDeleteConfirm(false); deleteMut.mutate(); }}
      onCancel={() => setShowDeleteConfirm(false)}
    />
    </>
  );
}
