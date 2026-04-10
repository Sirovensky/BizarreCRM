import { useState } from 'react';
import {
  Smartphone, Tablet, Laptop, Monitor, Gamepad2, Tv, HelpCircle,
  Wrench, Package, FileText, Image, CheckCircle2, Calendar, Timer, MapPin,
  Plus, X, Copy, Edit3, ShoppingCart, Loader2, Camera,
} from 'lucide-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { ticketApi, catalogApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { getIFixitUrl } from '@/utils/ifixit';
import { formatCurrency, formatDate } from '@/utils/format';
import type { Ticket, TicketDevice } from '@bizarre-crm/shared';

// ─── Constants ──────────────────────────────────────────────────────

const DEVICE_ICONS: Record<string, typeof Smartphone> = {
  Phone: Smartphone, Tablet, Laptop, Desktop: Monitor,
  'Game Console': Gamepad2, TV: Tv, Other: HelpCircle,
};

const PART_STATUS_CONFIG: Record<string, { label: string; color: string; bg: string; next: string }> = {
  available:  { label: 'Available', color: 'text-green-700 dark:text-green-300', bg: 'bg-green-100 dark:bg-green-900/30', next: 'missing' },
  missing:    { label: 'Missing',   color: 'text-red-700 dark:text-red-300',   bg: 'bg-red-100 dark:bg-red-900/30',   next: 'ordered' },
  ordered:    { label: 'Ordered',   color: 'text-amber-700 dark:text-amber-300', bg: 'bg-amber-100 dark:bg-amber-900/30', next: 'received' },
  received:   { label: 'Received',  color: 'text-blue-700 dark:text-blue-300',  bg: 'bg-blue-100 dark:bg-blue-900/30',  next: 'available' },
};

// ─── Helpers ────────────────────────────────────────────────────────

function initials(first?: string, last?: string) {
  return `${(first || '?').charAt(0)}${(last || '').charAt(0)}`.toUpperCase();
}

// ─── Device History Popover ─────────────────────────────────────────

import { useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import { History } from 'lucide-react';
import { timeAgo } from '@/utils/format';

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

// ─── Accordion Section ──────────────────────────────────────────────

import { ChevronRight } from 'lucide-react';

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

// ─── Device Edit Form ───────────────────────────────────────────────

import { Save } from 'lucide-react';

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

// ─── Parts Search Modal ─────────────────────────────────────────────

import { Search, ExternalLink } from 'lucide-react';

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

  const [showQuickAdd, setShowQuickAdd] = useState(false);
  const [qaName, setQaName] = useState('');
  const [qaPrice, setQaPrice] = useState('');
  const [qaQty, setQaQty] = useState('1');

  const addPartMut = useMutation({
    mutationFn: (data: { inventory_item_id: number; quantity: number; price: number }) =>
      ticketApi.addParts(deviceId, data),
    onSuccess: () => {
      toast.success('Part added');
      onPartAdded();
    },
    onError: () => toast.error('Failed to add part'),
  });

  const quickAddMut = useMutation({
    mutationFn: (data: { name: string; price: number; quantity: number }) =>
      ticketApi.quickAddPart(deviceId, data),
    onSuccess: () => {
      toast.success('Part created and added');
      setShowQuickAdd(false);
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
          <button aria-label="Close" onClick={onClose} className="p-1 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400">
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
                  <p className="px-3 py-1.5 text-xs font-semibold uppercase text-amber-600 dark:text-amber-400">Out of Stock</p>
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
                <div className="py-6 px-4">
                  <p className="text-center text-sm text-surface-400 mb-4">No parts found for &quot;{debouncedQuery}&quot;</p>
                  {!showQuickAdd ? (
                    <button
                      onClick={() => { setShowQuickAdd(true); setQaName(debouncedQuery); setQaPrice(''); setQaQty('1'); }}
                      className="mx-auto flex items-center gap-1.5 rounded-lg border border-dashed border-primary-300 dark:border-primary-700 bg-primary-50 dark:bg-primary-900/20 px-4 py-2 text-sm font-medium text-primary-600 dark:text-primary-400 hover:bg-primary-100 dark:hover:bg-primary-900/30 transition-colors"
                    >
                      <Plus className="h-4 w-4" />
                      Quick Add Custom Part
                    </button>
                  ) : (
                    <div className="rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 p-4 space-y-3">
                      <p className="text-xs font-semibold uppercase tracking-wide text-surface-500">Quick Add Part</p>
                      <input
                        value={qaName}
                        onChange={(e) => setQaName(e.target.value)}
                        placeholder="Part name"
                        className="w-full rounded-lg border border-surface-200 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
                        autoFocus
                      />
                      <div className="flex gap-3">
                        <div className="flex-1">
                          <label className="mb-1 block text-xs text-surface-500">Price ($)</label>
                          <input
                            type="number"
                            step="0.01"
                            min="0"
                            value={qaPrice}
                            onChange={(e) => setQaPrice(e.target.value)}
                            placeholder="0.00"
                            className="w-full rounded-lg border border-surface-200 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
                          />
                        </div>
                        <div className="w-20">
                          <label className="mb-1 block text-xs text-surface-500">Qty</label>
                          <input
                            type="number"
                            min="1"
                            value={qaQty}
                            onChange={(e) => setQaQty(e.target.value)}
                            className="w-full rounded-lg border border-surface-200 dark:border-surface-600 bg-white dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none focus:ring-2 focus:ring-primary-500"
                          />
                        </div>
                      </div>
                      <div className="flex items-center justify-end gap-2">
                        <button
                          onClick={() => setShowQuickAdd(false)}
                          className="rounded-lg px-3 py-1.5 text-sm text-surface-500 hover:text-surface-700 dark:hover:text-surface-300 transition-colors"
                        >
                          Cancel
                        </button>
                        <button
                          onClick={() => {
                            if (!qaName.trim()) { toast.error('Name is required'); return; }
                            if (!qaPrice || Number(qaPrice) < 0) { toast.error('Valid price is required'); return; }
                            quickAddMut.mutate({ name: qaName.trim(), price: Number(qaPrice), quantity: Math.max(1, parseInt(qaQty) || 1) });
                          }}
                          disabled={quickAddMut.isPending}
                          className="inline-flex items-center gap-1.5 rounded-lg bg-primary-600 px-4 py-1.5 text-sm font-medium text-white hover:bg-primary-700 transition-colors disabled:opacity-50"
                        >
                          {quickAddMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Plus className="h-3.5 w-3.5" />}
                          Add to Ticket
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketDevicesProps {
  ticket: Ticket;
  ticketId: number;
  devices: TicketDevice[];
  activeTab: 'overview' | 'notes' | 'photos' | 'parts';
  repairDays: number;
  repairHours: number;
  editingDeviceId: number | null;
  setEditingDeviceId: (id: number | null) => void;
  partsSearchDeviceId: number | null;
  setPartsSearchDeviceId: (id: number | null) => void;
  invalidateTicket: () => void;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketDevices({
  ticket,
  ticketId,
  devices,
  activeTab,
  repairDays,
  repairHours,
  editingDeviceId,
  setEditingDeviceId,
  partsSearchDeviceId,
  setPartsSearchDeviceId,
  invalidateTicket,
}: TicketDevicesProps) {
  const queryClient = useQueryClient();
  const assigned = ticket?.assigned_user;

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

  const updatePartStatusMut = useMutation({
    mutationFn: ({ partId, status }: { partId: number; status: string }) =>
      ticketApi.updatePart(partId, { status }),
    onSuccess: (_data, vars) => {
      toast.success(`Part status: ${vars.status}`);
      invalidateTicket();
    },
    onError: () => toast.error('Failed to update part status'),
  });

  const requestPartMut = useMutation({
    mutationFn: (part: { id: number; item_name: string; item_sku?: string; inventory_item_id?: number; price: number }) =>
      catalogApi.addToOrderQueue({
        inventory_item_id: part.inventory_item_id,
        name: part.item_name || `Part #${part.id}`,
        sku: part.item_sku,
        unit_price: part.price,
        quantity_needed: 1,
        ticket_device_part_id: part.id,
        ticket_id: ticketId,
        source: 'ticket',
      }),
    onSuccess: () => {
      toast.success('Part added to order queue');
      queryClient.invalidateQueries({ queryKey: ['order-queue-summary'] });
    },
    onError: () => toast.error('Failed to request part'),
  });

  const deletePhotoMut = useMutation({
    mutationFn: (photoId: number) => ticketApi.deletePhoto(photoId),
    onSuccess: () => { toast.success('Photo deleted'); invalidateTicket(); },
    onError: () => toast.error('Failed to delete photo'),
  });

  return (
    <>
      {/* Per-device cards -- shown on overview and parts tabs */}
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
                    {parts.map((p: any) => {
                      const statusCfg = PART_STATUS_CONFIG[p.status || 'available'] || PART_STATUS_CONFIG.available;
                      return (
                        <div key={p.id} className="flex items-center gap-2 rounded-lg bg-surface-50 dark:bg-surface-800/50 px-3 py-2 group">
                          <div className="flex-1 min-w-0">
                            <div className="flex items-center gap-2">
                              <span className="text-xs font-medium text-surface-800 dark:text-surface-200 truncate">
                                {p.item_name || `Item #${p.inventory_item_id}`}
                              </span>
                              <span className="text-xs text-surface-500">x{p.quantity}</span>
                              <button
                                onClick={() => updatePartStatusMut.mutate({ partId: p.id, status: statusCfg.next })}
                                className={cn('rounded-full px-1.5 py-0.5 text-[10px] font-medium cursor-pointer hover:opacity-80 transition-opacity', statusCfg.bg, statusCfg.color)}
                                title={`Status: ${statusCfg.label} (click to change)`}
                              >
                                {statusCfg.label}
                              </button>
                            </div>
                            {p.item_sku && <span className="text-[10px] text-surface-400">SKU: {p.item_sku}</span>}
                          </div>
                          <span className="text-xs font-medium text-surface-700 dark:text-surface-300">
                            {formatCurrency(p.price * p.quantity)}
                          </span>
                          <button
                            onClick={() => requestPartMut.mutate(p)}
                            className="opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded text-amber-500 hover:text-amber-700 hover:bg-amber-50 dark:hover:bg-amber-900/20"
                            title="Request part (add to order queue)"
                          >
                            <ShoppingCart className="h-3 w-3" />
                          </button>
                          <button
                            onClick={async () => { if (await confirm('Remove this part?', { danger: true })) removePartMut.mutate(p.id); }}
                            className="opacity-0 group-hover:opacity-100 transition-opacity p-0.5 rounded text-red-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20"
                            title="Remove part"
                          >
                            <X className="h-3 w-3" />
                          </button>
                        </div>
                      );
                    })}
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
                          <button onClick={async () => { if (await confirm('Delete this photo?', { danger: true })) deletePhotoMut.mutate(photo.id); }}
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
                          <button onClick={async () => { if (await confirm('Delete this photo?', { danger: true })) deletePhotoMut.mutate(photo.id); }}
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

      {/* Photos Tab -- all device photos in one view */}
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
                          <button onClick={async () => { if (await confirm('Delete this photo?', { danger: true })) deletePhotoMut.mutate(photo.id); }}
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
                          <button onClick={async () => { if (await confirm('Delete this photo?', { danger: true })) deletePhotoMut.mutate(photo.id); }}
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

      {/* Parts Search Modal */}
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
    </>
  );
}
