import { useState, useEffect, useRef, useCallback, Fragment, lazy, Suspense } from 'react';
import { useLocation, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Store, Users, ListChecks, Receipt, CreditCard,
  Save, Plus, Trash2, Pencil, X, Check, Loader2,
  AlertCircle, Eye, EyeOff, Shield, ChevronDown, ChevronLeft, ChevronRight, Tag, Wrench,
  ShoppingCart, FileText, Printer, ClipboardCheck, Bell, Database, Upload, Image, MessageSquare, Download, AlertTriangle,
  ScrollText,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi, rdImportApi, rsImportApi, mraImportApi, factoryWipeApi, catalogApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { RepairPricingTab } from './RepairPricingTab';
import { TicketsRepairsSettings } from './TicketsRepairsSettings';
import { PosSettings } from './PosSettings';
import { InvoiceSettings } from './InvoiceSettings';
import { ReceiptSettings } from './ReceiptSettings';
import { ConditionsTab } from './ConditionsTab';
import { NotificationTemplatesTab } from './NotificationTemplatesTab';
import { BlockChypSettings } from './BlockChypSettings';
const SmsVoiceSettings = lazy(() => import('./SmsVoiceSettings').then(m => ({ default: m.SmsVoiceSettings })));
import { AuditLogsTab } from './AuditLogsTab';

// ─── Types ────────────────────────────────────────────────────────────────────

type Tab = 'store' | 'statuses' | 'tax' | 'payment' | 'payment-terminal' | 'users' | 'customer-groups' | 'repair-pricing' | 'tickets-repairs' | 'pos' | 'invoices' | 'receipts' | 'conditions' | 'notifications' | 'sms-voice' | 'data-import' | 'supplier-catalog' | 'audit-logs';

interface TicketStatus {
  id: number;
  name: string;
  color: string;
  sort_order: number;
  is_default: number;
  is_closed: number;
  is_cancelled: number;
  notify_customer: number;
  notification_template: string | null;
}

interface TaxClass {
  id: number;
  name: string;
  rate: number;
  is_default: number;
}

interface PaymentMethod {
  id: number;
  name: string;
  sort_order: number;
  is_active: number;
}

interface UserRecord {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  is_active: number;
  created_at: string;
}

// ─── Reusable Components ──────────────────────────────────────────────────────

function LoadingState() {
  return (
    <div className="flex items-center justify-center py-20">
      <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
      <span className="ml-3 text-surface-500">Loading...</span>
    </div>
  );
}

function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
      <p className="text-sm text-surface-500">{message}</p>
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-12">
      <p className="text-sm text-surface-400 dark:text-surface-500">{message}</p>
    </div>
  );
}

// ─── Tab Config ───────────────────────────────────────────────────────────────

const TABS: { key: Tab; label: string; icon: any }[] = [
  { key: 'store', label: 'Store Info', icon: Store },
  { key: 'statuses', label: 'Ticket Statuses', icon: ListChecks },
  { key: 'tax', label: 'Tax Classes', icon: Receipt },
  { key: 'payment', label: 'Payment Methods', icon: CreditCard },
  { key: 'payment-terminal', label: 'Payment Terminal', icon: Shield },
  { key: 'customer-groups', label: 'Customer Groups', icon: Tag },
  { key: 'users', label: 'Users', icon: Users },
  { key: 'repair-pricing', label: 'Repair Pricing', icon: Wrench },
  { key: 'tickets-repairs', label: 'Tickets & Repairs', icon: ListChecks },
  { key: 'pos', label: 'POS', icon: ShoppingCart },
  { key: 'invoices', label: 'Invoices', icon: FileText },
  { key: 'receipts', label: 'Receipts', icon: Printer },
  { key: 'conditions', label: 'Conditions', icon: ClipboardCheck },
  { key: 'notifications', label: 'Notifications', icon: Bell },
  { key: 'sms-voice', label: 'SMS & Voice', icon: MessageSquare },
  { key: 'data-import', label: 'Data & Import', icon: Database },
  { key: 'audit-logs', label: 'Audit Logs', icon: ScrollText },
  // Supplier Catalog sync is platform-level (managed by super admin, not per-shop).
  // Shops access the catalog via the /catalog page (read-only search).
  // Sync runs automatically via daily cron — no manual trigger needed in settings.
] as const;

// ─── Store Info Tab ───────────────────────────────────────────────────────────

function formatStorePhone(phone: string): string {
  const digits = phone.replace(/\D/g, '');
  if (digits.length === 10) return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11 && digits[0] === '1') return `+1 (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  return phone;
}

function StoreInfoTab() {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'store'],
    queryFn: async () => {
      const res = await settingsApi.getStore();
      return res.data.data.store as Record<string, string>;
    },
  });

  useEffect(() => {
    if (data) {
      setForm(data);
      setDirty(false);
    }
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: (formData: Record<string, string>) => settingsApi.updateStore(formData),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'store'] });
      setDirty(false);
      toast.success('Store settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function handleChange(key: string, value: string) {
    setForm((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  // Logo upload mutation
  const logoInputRef = useRef<HTMLInputElement>(null);
  const logoMutation = useMutation({
    mutationFn: (file: File) => {
      const fd = new FormData();
      fd.append('logo', file);
      return settingsApi.uploadLogo(fd);
    },
    onSuccess: (res) => {
      const logoPath = (res.data as any)?.data?.store_logo;
      if (logoPath) {
        setForm((prev) => ({ ...prev, store_logo: logoPath }));
      }
      queryClient.invalidateQueries({ queryKey: ['settings', 'store'] });
      toast.success('Logo uploaded');
    },
    onError: () => toast.error('Failed to upload logo'),
  });

  // Business hours
  const DAYS = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'] as const;
  const DAY_LABELS: Record<string, string> = { mon: 'Monday', tue: 'Tuesday', wed: 'Wednesday', thu: 'Thursday', fri: 'Friday', sat: 'Saturday', sun: 'Sunday' };

  const parseHours = (json: string | undefined): Record<string, { open: boolean; from: string; to: string }> => {
    try {
      if (json) return JSON.parse(json);
    } catch { /* invalid JSON — use defaults */ }
    const defaults: Record<string, { open: boolean; from: string; to: string }> = {};
    for (const d of DAYS) {
      defaults[d] = { open: d !== 'sat' && d !== 'sun', from: '09:00', to: '17:00' };
    }
    return defaults;
  };

  const hours = parseHours(form['business_hours']);

  function handleHoursChange(day: string, field: 'open' | 'from' | 'to', value: boolean | string) {
    const updated = { ...hours, [day]: { ...hours[day], [field]: value } };
    handleChange('business_hours', JSON.stringify(updated));
  }

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load store settings" />;

  const fields = [
    { key: 'store_name', label: 'Store Name', type: 'text' },
    { key: 'address', label: 'Address', type: 'text' },
    { key: 'phone', label: 'Phone', type: 'tel' },
    { key: 'email', label: 'Email', type: 'email' },
    { key: 'timezone', label: 'Timezone', type: 'text' },
    { key: 'currency', label: 'Currency', type: 'text' },
    { key: 'receipt_header', label: 'Receipt Header', type: 'text', placeholder: 'e.g. Thank you for choosing our shop!' },
    { key: 'receipt_footer', label: 'Receipt Footer', type: 'text', placeholder: 'e.g. 30-day warranty on all repairs' },
  ] as { key: string; label: string; type: string; placeholder?: string }[];

  return (
    <div className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Store Information</h3>
        <button
          onClick={() => saveMutation.mutate(form)}
          disabled={!dirty || saveMutation.isPending}
          className={cn(
            'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
            dirty
              ? 'bg-blue-600 text-white hover:bg-blue-700'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-400 cursor-not-allowed'
          )}
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      {/* SET-2: Logo Upload */}
      <div className="p-6 border-b border-surface-100 dark:border-surface-800">
        <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-2">Store Logo</label>
        <div className="flex items-center gap-4">
          {form['store_logo'] ? (
            <img
              src={form['store_logo']}
              alt="Store logo"
              className="h-16 w-16 rounded-lg border border-surface-200 dark:border-surface-700 object-contain bg-white dark:bg-surface-800"
            />
          ) : (
            <div className="h-16 w-16 rounded-lg border-2 border-dashed border-surface-300 dark:border-surface-600 flex items-center justify-center bg-surface-50 dark:bg-surface-800">
              <Image className="h-6 w-6 text-surface-400" />
            </div>
          )}
          <div>
            <input
              ref={logoInputRef}
              type="file"
              accept="image/jpeg,image/png,image/webp,image/gif"
              className="hidden"
              onChange={(e) => {
                const file = e.target.files?.[0];
                if (file) logoMutation.mutate(file);
                e.target.value = '';
              }}
            />
            <button
              onClick={() => logoInputRef.current?.click()}
              disabled={logoMutation.isPending}
              className="inline-flex items-center gap-2 px-3 py-1.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors"
            >
              {logoMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Upload className="h-4 w-4" />}
              {form['store_logo'] ? 'Change Logo' : 'Upload Logo'}
            </button>
            <p className="text-xs text-surface-400 mt-1">JPEG, PNG, WebP or GIF. Max 5MB. Used on invoices and receipts.</p>
          </div>
        </div>
      </div>

      <div className="p-6 grid grid-cols-1 md:grid-cols-2 gap-5">
        {fields.map((f) => (
          <div key={f.key}>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">{f.label}</label>
            <input
              type={f.type}
              value={f.key === 'phone' ? formatStorePhone(form[f.key] || '') : (form[f.key] || '')}
              onChange={(e) => {
                const val = f.key === 'phone' ? e.target.value.replace(/[^\d+\-() ]/g, '') : e.target.value;
                handleChange(f.key, val);
              }}
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder={f.placeholder || f.label}
            />
          </div>
        ))}
      </div>

      {/* SET-1: Business Hours */}
      <div className="border-t border-surface-100 dark:border-surface-800">
        <div className="p-4 flex items-center justify-between">
          <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Business Hours</h4>
          <p className="text-xs text-surface-400">Set your weekly operating hours</p>
        </div>
        <div className="px-4 pb-4">
          <div className="space-y-2">
            {DAYS.map((day) => (
              <div key={day} className="flex items-center gap-3">
                <span className="w-24 text-sm font-medium text-surface-700 dark:text-surface-300">{DAY_LABELS[day]}</span>
                <label className="relative inline-flex items-center cursor-pointer">
                  <input
                    type="checkbox"
                    checked={hours[day]?.open ?? false}
                    onChange={(e) => handleHoursChange(day, 'open', e.target.checked)}
                    className="sr-only peer"
                  />
                  <div className="w-9 h-5 bg-surface-200 peer-focus:outline-none peer-focus:ring-2 peer-focus:ring-blue-300 dark:peer-focus:ring-blue-800 rounded-full peer dark:bg-surface-700 peer-checked:after:translate-x-full peer-checked:after:border-white after:content-[''] after:absolute after:top-[2px] after:left-[2px] after:bg-white after:border-surface-300 after:border after:rounded-full after:h-4 after:w-4 after:transition-all dark:border-surface-600 peer-checked:bg-blue-600" />
                </label>
                {hours[day]?.open ? (
                  <div className="flex items-center gap-2">
                    <input
                      type="time"
                      value={hours[day]?.from || '09:00'}
                      onChange={(e) => handleHoursChange(day, 'from', e.target.value)}
                      className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
                    />
                    <span className="text-xs text-surface-400">to</span>
                    <input
                      type="time"
                      value={hours[day]?.to || '17:00'}
                      onChange={(e) => handleHoursChange(day, 'to', e.target.value)}
                      className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
                    />
                  </div>
                ) : (
                  <span className="text-xs text-surface-400 italic">Closed</span>
                )}
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Referral Sources */}
      <ReferralSourcesSection />
    </div>
  );
}

function ReferralSourcesSection() {
  const queryClient = useQueryClient();
  const [newSource, setNewSource] = useState('');

  const { data } = useQuery({
    queryKey: ['settings', 'referral-sources'],
    queryFn: async () => {
      const res = await settingsApi.getReferralSources();
      return (res.data?.data?.referral_sources || res.data?.data || []) as { id: number; name: string }[];
    },
  });
  const sources = data || [];

  const createMut = useMutation({
    mutationFn: (name: string) => settingsApi.createReferralSource({ name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'referral-sources'] });
      setNewSource('');
      toast.success('Referral source added');
    },
    onError: () => toast.error('Failed to add source'),
  });

  return (
    <div className="border-t border-surface-100 dark:border-surface-800">
      <div className="p-4 flex items-center justify-between">
        <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Referral Sources</h4>
        <p className="text-xs text-surface-400">"How did you find us?" options</p>
      </div>
      <div className="px-4 pb-4">
        <div className="flex gap-2 mb-3">
          <input
            value={newSource}
            onChange={(e) => setNewSource(e.target.value)}
            placeholder="Add referral source..."
            onKeyDown={(e) => { if (e.key === 'Enter' && newSource.trim()) createMut.mutate(newSource.trim()); }}
            className="flex-1 px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <button
            onClick={() => newSource.trim() && createMut.mutate(newSource.trim())}
            disabled={!newSource.trim()}
            className="px-3 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50"
          >
            <Plus className="h-4 w-4" />
          </button>
        </div>
        <div className="flex flex-wrap gap-2">
          {sources.map((s) => (
            <span key={s.id} className="inline-flex items-center gap-1 rounded-full bg-surface-100 dark:bg-surface-700 px-3 py-1 text-xs font-medium text-surface-700 dark:text-surface-300">
              {s.name}
            </span>
          ))}
          {sources.length === 0 && <p className="text-xs text-surface-400">No referral sources yet</p>}
        </div>
      </div>
    </div>
  );
}

// ─── Ticket Statuses Tab ──────────────────────────────────────────────────────

function StatusesTab() {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<Partial<TicketStatus>>({});
  const [showAdd, setShowAdd] = useState(false);
  const [addForm, setAddForm] = useState({ name: '', color: '#6b7280', sort_order: 0, is_default: 0, is_closed: 0, is_cancelled: 0, notify_customer: 0 });

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'statuses'],
    queryFn: async () => {
      const res = await settingsApi.getStatuses();
      return res.data.data.statuses as TicketStatus[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (d: any) => settingsApi.createStatus(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'statuses'] });
      setShowAdd(false);
      setAddForm({ name: '', color: '#6b7280', sort_order: 0, is_default: 0, is_closed: 0, is_cancelled: 0, notify_customer: 0 });
      toast.success('Status created');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create status'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => settingsApi.updateStatus(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'statuses'] });
      setEditing(null);
      toast.success('Status updated');
    },
    onError: () => toast.error('Failed to update status'),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteStatus(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'statuses'] });
      toast.success('Status deleted');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to delete status'),
  });

  function startEdit(status: TicketStatus) {
    setEditing(status.id);
    setEditForm({ name: status.name, color: status.color, sort_order: status.sort_order, is_closed: status.is_closed, is_cancelled: status.is_cancelled, notify_customer: status.notify_customer });
  }

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load statuses" />;

  const statuses = data || [];

  return (
    <div className="space-y-4">
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Ticket Statuses</h3>
          <button
            onClick={() => setShowAdd(!showAdd)}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Plus className="h-4 w-4" /> Add Status
          </button>
        </div>

        {/* Add Form */}
        {showAdd && (
          <div className="p-4 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/30">
            <div className="flex flex-wrap items-end gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Name</label>
                <input
                  type="text"
                  value={addForm.name}
                  onChange={(e) => setAddForm({ ...addForm, name: e.target.value })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500 w-48"
                  placeholder="Status name"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Color</label>
                <div className="flex items-center gap-2">
                  <input
                    type="color"
                    value={addForm.color}
                    onChange={(e) => setAddForm({ ...addForm, color: e.target.value })}
                    className="h-9 w-9 rounded border border-surface-200 dark:border-surface-700 cursor-pointer"
                  />
                  <input
                    type="text"
                    value={addForm.color}
                    onChange={(e) => setAddForm({ ...addForm, color: e.target.value })}
                    className="px-2 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24 font-mono"
                  />
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Order</label>
                <input
                  type="number"
                  value={addForm.sort_order}
                  onChange={(e) => setAddForm({ ...addForm, sort_order: parseInt(e.target.value) || 0 })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-20 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
                <input type="checkbox" checked={!!addForm.is_closed} onChange={(e) => setAddForm({ ...addForm, is_closed: e.target.checked ? 1 : 0 })} className="rounded" />
                Closed
              </label>
              <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
                <input type="checkbox" checked={!!addForm.is_cancelled} onChange={(e) => setAddForm({ ...addForm, is_cancelled: e.target.checked ? 1 : 0 })} className="rounded" />
                Cancelled
              </label>
              <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
                <input type="checkbox" checked={!!addForm.notify_customer} onChange={(e) => setAddForm({ ...addForm, notify_customer: e.target.checked ? 1 : 0 })} className="rounded" />
                Notify Customer
              </label>
              <div className="flex gap-2">
                <button
                  onClick={() => createMutation.mutate(addForm)}
                  disabled={!addForm.name || createMutation.isPending}
                  className="inline-flex items-center gap-1 px-3 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
                >
                  {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                  Create
                </button>
                <button onClick={() => setShowAdd(false)} className="px-3 py-2 text-sm text-surface-500 hover:text-surface-700 dark:hover:text-surface-300">
                  Cancel
                </button>
              </div>
            </div>
          </div>
        )}

        {/* Status List */}
        {statuses.length === 0 ? (
          <EmptyState message="No statuses configured" />
        ) : (
          <div className="divide-y divide-surface-100 dark:divide-surface-800">
            {statuses.map((s) => (
              <div key={s.id} className="px-4 py-3 flex items-center gap-4 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                {editing === s.id ? (
                  /* Inline edit */
                  <div className="flex flex-wrap items-center gap-3 flex-1">
                    <input
                      type="text"
                      value={editForm.name || ''}
                      onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                      className="px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-40"
                    />
                    <input
                      type="color"
                      value={editForm.color || '#6b7280'}
                      onChange={(e) => setEditForm({ ...editForm, color: e.target.value })}
                      className="h-8 w-8 rounded border border-surface-200 dark:border-surface-700 cursor-pointer"
                    />
                    <input
                      type="number"
                      value={editForm.sort_order ?? 0}
                      onChange={(e) => setEditForm({ ...editForm, sort_order: parseInt(e.target.value) || 0 })}
                      className="px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-16"
                    />
                    <label className="flex items-center gap-1 text-xs text-surface-500">
                      <input type="checkbox" checked={!!editForm.is_closed} onChange={(e) => setEditForm({ ...editForm, is_closed: e.target.checked ? 1 : 0 })} className="rounded" />
                      Closed
                    </label>
                    <label className="flex items-center gap-1 text-xs text-surface-500">
                      <input type="checkbox" checked={!!editForm.is_cancelled} onChange={(e) => setEditForm({ ...editForm, is_cancelled: e.target.checked ? 1 : 0 })} className="rounded" />
                      Cancel
                    </label>
                    <button
                      onClick={() => updateMutation.mutate({ id: s.id, data: editForm })}
                      disabled={updateMutation.isPending}
                      className="p-1.5 text-green-600 hover:bg-green-50 dark:hover:bg-green-900/30 rounded"
                    >
                      {updateMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                    </button>
                    <button onClick={() => setEditing(null)} className="p-1.5 text-surface-400 hover:text-surface-600 rounded">
                      <X className="h-4 w-4" />
                    </button>
                  </div>
                ) : (
                  /* Display row */
                  <>
                    <span className="h-4 w-4 rounded-full flex-shrink-0" style={{ backgroundColor: s.color }} />
                    <span className="font-medium text-surface-900 dark:text-surface-100 min-w-32">{s.name}</span>
                    <span className="text-xs text-surface-400 font-mono">{s.color}</span>
                    <span className="text-xs text-surface-400">order: {s.sort_order}</span>
                    <div className="flex gap-2 ml-auto">
                      {!!s.is_default && <span className="text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 rounded-full px-2 py-0.5">Default</span>}
                      {!!s.is_closed && <span className="text-xs bg-green-100 dark:bg-green-900/30 text-green-700 dark:text-green-400 rounded-full px-2 py-0.5">Closed</span>}
                      {!!s.is_cancelled && <span className="text-xs bg-red-100 dark:bg-red-900/30 text-red-700 dark:text-red-400 rounded-full px-2 py-0.5">Cancelled</span>}
                      {!!s.notify_customer && <span className="text-xs bg-amber-100 dark:bg-amber-900/30 text-amber-700 dark:text-amber-400 rounded-full px-2 py-0.5">Notifies</span>}
                    </div>
                    <div className="flex gap-1 ml-2">
                      <button onClick={() => startEdit(s)} className="p-1.5 text-surface-400 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/30 rounded transition-colors">
                        <Pencil className="h-3.5 w-3.5" />
                      </button>
                      <button
                        onClick={async () => {
                          if (await confirm(`Delete status "${s.name}"? This cannot be undone.`, { danger: true })) {
                            deleteMutation.mutate(s.id);
                          }
                        }}
                        className="p-1.5 text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/30 rounded transition-colors"
                      >
                        <Trash2 className="h-3.5 w-3.5" />
                      </button>
                    </div>
                  </>
                )}
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Tax Classes Tab ──────────────────────────────────────────────────────────

function TaxClassesTab() {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [addForm, setAddForm] = useState({ name: '', rate: '', is_default: 0 });
  const [editing, setEditing] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<Partial<TaxClass>>({});

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'tax-classes'],
    queryFn: async () => {
      const res = await settingsApi.getTaxClasses();
      return res.data.data.tax_classes as TaxClass[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (d: any) => settingsApi.createTaxClass(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'tax-classes'] });
      setShowAdd(false);
      setAddForm({ name: '', rate: '', is_default: 0 });
      toast.success('Tax class created');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => settingsApi.updateTaxClass(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'tax-classes'] });
      setEditing(null);
      toast.success('Tax class updated');
    },
    onError: () => toast.error('Failed to update'),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteTaxClass(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'tax-classes'] });
      toast.success('Tax class deleted');
    },
    onError: () => toast.error('Failed to delete'),
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load tax classes" />;

  const taxClasses = data || [];

  return (
    <div className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Tax Classes</h3>
        <button
          onClick={() => setShowAdd(!showAdd)}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          <Plus className="h-4 w-4" /> Add Tax Class
        </button>
      </div>

      {showAdd && (
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/30">
          <div className="flex flex-wrap items-end gap-3">
            <div>
              <label className="block text-xs font-medium text-surface-500 mb-1">Name</label>
              <input
                type="text"
                value={addForm.name}
                onChange={(e) => setAddForm({ ...addForm, name: e.target.value })}
                className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-48 focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="e.g., Colorado Sales Tax"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-500 mb-1">Rate (%)</label>
              <input
                type="number"
                step="0.001"
                value={addForm.rate}
                onChange={(e) => setAddForm({ ...addForm, rate: e.target.value })}
                className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-28 focus:outline-none focus:ring-2 focus:ring-blue-500"
                placeholder="8.865"
              />
            </div>
            <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
              <input type="checkbox" checked={!!addForm.is_default} onChange={(e) => setAddForm({ ...addForm, is_default: e.target.checked ? 1 : 0 })} className="rounded" />
              Default
            </label>
            <button
              onClick={() => createMutation.mutate({ ...addForm, rate: parseFloat(addForm.rate) || 0 })}
              disabled={!addForm.name || createMutation.isPending}
              className="inline-flex items-center gap-1 px-3 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
            >
              {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
              Create
            </button>
            <button onClick={() => setShowAdd(false)} className="px-3 py-2 text-sm text-surface-500 hover:text-surface-700">Cancel</button>
          </div>
        </div>
      )}

      {taxClasses.length === 0 ? (
        <EmptyState message="No tax classes configured" />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800">
                <th className="text-left px-4 py-3 font-medium text-surface-500">Name</th>
                <th className="text-right px-4 py-3 font-medium text-surface-500">Rate</th>
                <th className="text-center px-4 py-3 font-medium text-surface-500">Default</th>
                <th className="text-right px-4 py-3 font-medium text-surface-500 w-24">Actions</th>
              </tr>
            </thead>
            <tbody>
              {taxClasses.map((tc) => (
                <tr key={tc.id} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                  {editing === tc.id ? (
                    <>
                      <td className="px-4 py-2">
                        <input
                          type="text" value={editForm.name || ''}
                          onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                          className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-full"
                        />
                      </td>
                      <td className="px-4 py-2">
                        <input
                          type="number" step="0.001" value={editForm.rate ?? ''}
                          onChange={(e) => setEditForm({ ...editForm, rate: parseFloat(e.target.value) || 0 })}
                          className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24 text-right"
                        />
                      </td>
                      <td className="px-4 py-2 text-center">
                        <input type="checkbox" checked={!!editForm.is_default} onChange={(e) => setEditForm({ ...editForm, is_default: e.target.checked ? 1 : 0 })} className="rounded" />
                      </td>
                      <td className="px-4 py-2 text-right">
                        <div className="flex gap-1 justify-end">
                          <button onClick={() => updateMutation.mutate({ id: tc.id, data: editForm })} className="p-1.5 text-green-600 hover:bg-green-50 dark:hover:bg-green-900/30 rounded">
                            <Check className="h-3.5 w-3.5" />
                          </button>
                          <button onClick={() => setEditing(null)} className="p-1.5 text-surface-400 hover:text-surface-600 rounded">
                            <X className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </>
                  ) : (
                    <>
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{tc.name}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{tc.rate}%</td>
                      <td className="px-4 py-3 text-center">
                        {tc.is_default ? <span className="text-xs bg-blue-100 dark:bg-blue-900/30 text-blue-700 dark:text-blue-400 rounded-full px-2 py-0.5">Default</span> : '--'}
                      </td>
                      <td className="px-4 py-3 text-right">
                        <div className="flex gap-1 justify-end">
                          <button
                            onClick={() => { setEditing(tc.id); setEditForm({ name: tc.name, rate: tc.rate, is_default: tc.is_default }); }}
                            className="p-1.5 text-surface-400 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/30 rounded transition-colors"
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </button>
                          <button
                            onClick={async () => { if (await confirm(`Delete "${tc.name}"?`, { danger: true })) deleteMutation.mutate(tc.id); }}
                            className="p-1.5 text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/30 rounded transition-colors"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {/* Default Tax Class Per Item Type */}
      <DefaultTaxPerType taxClasses={taxClasses} />
    </div>
  );
}

function DefaultTaxPerType({ taxClasses }: { taxClasses: TaxClass[] }) {
  const queryClient = useQueryClient();
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
  });

  const saveMut = useMutation({
    mutationFn: (d: Record<string, string>) => settingsApi.updateConfig(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      toast.success('Default tax classes saved');
    },
  });

  const config = configData || {};
  const ITEM_TYPES = [
    { key: 'tax_default_parts', label: 'Parts' },
    { key: 'tax_default_services', label: 'Services / Labor' },
    { key: 'tax_default_accessories', label: 'Accessories' },
  ];

  return (
    <div className="mt-6 border-t border-surface-100 dark:border-surface-800 pt-4 px-4 pb-4">
      <h4 className="text-sm font-semibold text-surface-700 dark:text-surface-300 mb-3">Default Tax Class Per Item Type</h4>
      <div className="space-y-3">
        {ITEM_TYPES.map((it) => (
          <div key={it.key} className="flex items-center justify-between">
            <span className="text-sm text-surface-600 dark:text-surface-400">{it.label}</span>
            <select
              value={config[it.key] || ''}
              onChange={(e) => saveMut.mutate({ [it.key]: e.target.value })}
              className="px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            >
              <option value="">No default</option>
              {taxClasses.map((tc) => (
                <option key={tc.id} value={String(tc.id)}>{tc.name} ({tc.rate}%)</option>
              ))}
            </select>
          </div>
        ))}
      </div>
    </div>
  );
}

// ─── Payment Methods Tab ──────────────────────────────────────────────────────

function PaymentMethodsTab() {
  const queryClient = useQueryClient();
  const [newName, setNewName] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'payment-methods'],
    queryFn: async () => {
      const res = await settingsApi.getPaymentMethods();
      return res.data.data.payment_methods as PaymentMethod[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (name: string) => settingsApi.createPaymentMethod({ name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'payment-methods'] });
      setNewName('');
      toast.success('Payment method added');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create'),
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load payment methods" />;

  const methods = data || [];

  return (
    <div className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Payment Methods</h3>
      </div>

      {/* Add form */}
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center gap-3">
        <input
          type="text"
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && newName.trim()) createMutation.mutate(newName.trim()); }}
          className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 flex-1 focus:outline-none focus:ring-2 focus:ring-blue-500"
          placeholder="New payment method name..."
        />
        <button
          onClick={() => { if (newName.trim()) createMutation.mutate(newName.trim()); }}
          disabled={!newName.trim() || createMutation.isPending}
          className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
        >
          {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
          Add
        </button>
      </div>

      {methods.length === 0 ? (
        <EmptyState message="No payment methods configured" />
      ) : (
        <div className="divide-y divide-surface-100 dark:divide-surface-800">
          {methods.map((m, i) => (
            <div key={m.id} className="px-4 py-3 flex items-center gap-3 hover:bg-surface-50 dark:hover:bg-surface-800/30">
              <CreditCard className="h-4 w-4 text-surface-400" />
              <span className="font-medium text-surface-900 dark:text-surface-100">{m.name}</span>
              <span className="ml-auto text-xs text-surface-400">#{i + 1}</span>
            </div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── Users Tab ────────────────────────────────────────────────────────────────

function UsersTab() {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [addForm, setAddForm] = useState({ username: '', email: '', password: '', first_name: '', last_name: '', role: 'technician' });
  const [showPassword, setShowPassword] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<any>({});

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'users'],
    queryFn: async () => {
      const res = await settingsApi.getUsers();
      return res.data.data.users as UserRecord[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (d: any) => settingsApi.createUser(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'users'] });
      setShowAdd(false);
      setAddForm({ username: '', email: '', password: '', first_name: '', last_name: '', role: 'technician' });
      toast.success('User created');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create user'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => settingsApi.updateUser(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'users'] });
      setEditingId(null);
      toast.success('User updated');
    },
    onError: () => toast.error('Failed to update user'),
  });

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load users" />;

  const users = data || [];
  const roles = ['admin', 'manager', 'technician', 'cashier'];

  return (
    <div className="space-y-4">
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Users</h3>
          <button
            onClick={() => setShowAdd(!showAdd)}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Plus className="h-4 w-4" /> Add User
          </button>
        </div>

        {/* Add User Form */}
        {showAdd && (
          <div className="p-5 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/30">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl">
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">First Name *</label>
                <input
                  type="text" value={addForm.first_name}
                  onChange={(e) => setAddForm({ ...addForm, first_name: e.target.value })}
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Last Name *</label>
                <input
                  type="text" value={addForm.last_name}
                  onChange={(e) => setAddForm({ ...addForm, last_name: e.target.value })}
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Username *</label>
                <input
                  type="text" value={addForm.username}
                  onChange={(e) => setAddForm({ ...addForm, username: e.target.value })}
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Email *</label>
                <input
                  type="email" value={addForm.email}
                  onChange={(e) => setAddForm({ ...addForm, email: e.target.value })}
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Password <span className="text-surface-400 font-normal">(optional — user sets on first login)</span></label>
                <div className="relative">
                  <input
                    type={showPassword ? 'text' : 'password'} value={addForm.password}
                    onChange={(e) => setAddForm({ ...addForm, password: e.target.value })}
                    className="w-full px-3 py-2 pr-9 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600"
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                  </button>
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Role</label>
                <select
                  value={addForm.role}
                  onChange={(e) => setAddForm({ ...addForm, role: e.target.value })}
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                >
                  {roles.map((r) => <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>)}
                </select>
              </div>
            </div>
            <div className="flex gap-2 mt-4">
              <button
                onClick={() => createMutation.mutate(addForm)}
                disabled={!addForm.username || !addForm.first_name || !addForm.last_name || createMutation.isPending}
                className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 transition-colors"
              >
                {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Plus className="h-4 w-4" />}
                Create User
              </button>
              <button onClick={() => setShowAdd(false)} className="px-4 py-2 text-sm text-surface-500 hover:text-surface-700">Cancel</button>
            </div>
          </div>
        )}

        {/* User List */}
        {users.length === 0 ? (
          <EmptyState message="No users found" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Name</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Username</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Email</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Role</th>
                  <th className="text-center px-4 py-3 font-medium text-surface-500">Active</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500 w-32">Actions</th>
                </tr>
              </thead>
              <tbody>
                {users.map((u) => (
                  <Fragment key={u.id}>
                  <tr className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    {editingId === u.id ? (
                      <>
                        <td className="px-4 py-2">
                          <div className="flex gap-1">
                            <input
                              type="text" value={editForm.first_name || ''} placeholder="First"
                              onChange={(e) => setEditForm({ ...editForm, first_name: e.target.value })}
                              className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24"
                            />
                            <input
                              type="text" value={editForm.last_name || ''} placeholder="Last"
                              onChange={(e) => setEditForm({ ...editForm, last_name: e.target.value })}
                              className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24"
                            />
                          </div>
                        </td>
                        <td className="px-4 py-2 text-surface-500">{u.username}</td>
                        <td className="px-4 py-2">
                          <input
                            type="email" value={editForm.email || ''}
                            onChange={(e) => setEditForm({ ...editForm, email: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-44"
                          />
                        </td>
                        <td className="px-4 py-2">
                          <select
                            value={editForm.role || 'technician'}
                            onChange={(e) => setEditForm({ ...editForm, role: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                          >
                            {roles.map((r) => <option key={r} value={r}>{r.charAt(0).toUpperCase() + r.slice(1)}</option>)}
                          </select>
                        </td>
                        <td className="px-4 py-2 text-center">
                          <input
                            type="checkbox" checked={!!editForm.is_active}
                            onChange={(e) => setEditForm({ ...editForm, is_active: e.target.checked ? 1 : 0 })}
                            className="rounded"
                          />
                        </td>
                        <td className="px-4 py-2 text-right">
                          <div className="flex gap-1 justify-end">
                            <button
                              onClick={() => updateMutation.mutate({ id: u.id, data: editForm })}
                              disabled={updateMutation.isPending}
                              className="p-1.5 text-green-600 hover:bg-green-50 dark:hover:bg-green-900/30 rounded"
                            >
                              {updateMutation.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
                            </button>
                            <button onClick={() => setEditingId(null)} className="p-1.5 text-surface-400 hover:text-surface-600 rounded">
                              <X className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">
                          {u.first_name} {u.last_name}
                        </td>
                        <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{u.username}</td>
                        <td className="px-4 py-3 text-surface-600 dark:text-surface-400">{u.email}</td>
                        <td className="px-4 py-3">
                          <span className={cn(
                            'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-xs font-medium',
                            u.role === 'admin' ? 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-400' :
                            u.role === 'manager' ? 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400' :
                            u.role === 'cashier' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400' :
                            'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                          )}>
                            {u.role === 'admin' && <Shield className="h-3 w-3" />}
                            {u.role.charAt(0).toUpperCase() + u.role.slice(1)}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-center">
                          {u.is_active ? (
                            <span className="inline-block h-2.5 w-2.5 rounded-full bg-green-500" title="Active" />
                          ) : (
                            <span className="inline-block h-2.5 w-2.5 rounded-full bg-surface-300" title="Inactive" />
                          )}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <button
                            onClick={() => {
                              setEditingId(u.id);
                              setEditForm({
                                first_name: u.first_name,
                                last_name: u.last_name,
                                email: u.email,
                                role: u.role,
                                is_active: u.is_active,
                                commission_type: (u as any).commission_type || 'none',
                                commission_rate: (u as any).commission_rate || 0,
                              });
                            }}
                            className="p-1.5 text-surface-400 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/30 rounded transition-colors"
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </button>
                        </td>
                      </>
                    )}
                  </tr>
                  {/* Commission row (expanded when editing) */}
                  {editingId === u.id && (
                    <tr className="bg-surface-50/50 dark:bg-surface-800/20 border-b border-surface-100 dark:border-surface-800">
                      <td colSpan={6} className="px-6 py-3">
                        <div className="flex items-center gap-4 text-sm">
                          <span className="text-xs font-medium text-surface-500 uppercase tracking-wider">Commission:</span>
                          <select
                            value={editForm.commission_type || 'none'}
                            onChange={(e) => setEditForm({ ...editForm, commission_type: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                          >
                            <option value="none">No Commission</option>
                            <option value="percent_ticket">% per Ticket</option>
                            <option value="percent_service">% per Service</option>
                            <option value="flat_per_ticket">Flat $ per Ticket</option>
                          </select>
                          {editForm.commission_type && editForm.commission_type !== 'none' && (
                            <div className="flex items-center gap-1">
                              <input
                                type="number"
                                step="0.5"
                                value={editForm.commission_rate ?? 0}
                                onChange={(e) => setEditForm({ ...editForm, commission_rate: parseFloat(e.target.value) || 0 })}
                                className="w-20 px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
                              />
                              <span className="text-xs text-surface-400">
                                {editForm.commission_type?.startsWith('percent') ? '%' : '$'}
                              </span>
                            </div>
                          )}
                        </div>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Role Permissions */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Role Permissions</h3>
          <p className="text-xs text-surface-500 mt-1">Configure which modules each role can access</p>
        </div>
        <div className="overflow-x-auto">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800">
                <th className="text-left px-4 py-3 font-medium text-surface-500">Module</th>
                {roles.map((r) => (
                  <th key={r} className="text-center px-4 py-3 font-medium text-surface-500">
                    {r.charAt(0).toUpperCase() + r.slice(1)}
                    {r === 'admin' && <div className="text-xs font-normal text-green-600 dark:text-green-400">All permissions</div>}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {['Tickets', 'Customers', 'Invoices', 'Inventory', 'POS', 'Reports', 'Settings', 'Employees'].map((mod) => (
                <tr key={mod} className="border-b border-surface-50 dark:border-surface-800/50">
                  <td className="px-4 py-2 text-surface-700 dark:text-surface-300">{mod}</td>
                  {roles.map((role) => {
                    const isAdmin = role === 'admin';
                    const allowed = isAdmin || (role === 'manager') || ['Tickets', 'Customers', 'POS'].includes(mod) || (role === 'technician' && mod === 'Inventory');
                    return (
                      <td key={role} className="px-4 py-2 text-center">
                        {isAdmin ? (
                          <span className="inline-flex items-center gap-1 text-green-600 dark:text-green-400" title="Admin always has full access">
                            <svg className="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2.5}><path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" /></svg>
                          </span>
                        ) : (
                          <input
                            type="checkbox"
                            checked={allowed}
                            className="rounded border-surface-300 text-primary-600"
                            readOnly
                            title={`${role} access to ${mod}`}
                          />
                        )}
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <div className="px-4 py-3 text-xs text-surface-400">
          Admin role always has full access to all modules. Granular per-action permissions coming soon.
        </div>
      </div>
    </div>
  );
}

// ─── Customer Groups Tab ─────────────────────────────────────────────────────

interface CustomerGroupRecord {
  id: number;
  name: string;
  discount_pct: number;
  discount_type: string;
  auto_apply: number;
  description: string | null;
}

function CustomerGroupsTab() {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<Partial<CustomerGroupRecord>>({});
  const [showAdd, setShowAdd] = useState(false);
  const [addForm, setAddForm] = useState({ name: '', discount_pct: 0, discount_type: 'percentage', auto_apply: 1, description: '' });

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'customer-groups'],
    queryFn: async () => {
      const res = await settingsApi.getCustomerGroups();
      return (res.data.data || []) as CustomerGroupRecord[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (d: any) => settingsApi.createCustomerGroup(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      setShowAdd(false);
      setAddForm({ name: '', discount_pct: 0, discount_type: 'percentage', auto_apply: 1, description: '' });
      toast.success('Customer group created');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create group'),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => settingsApi.updateCustomerGroup(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      setEditing(null);
      toast.success('Customer group updated');
    },
    onError: () => toast.error('Failed to update group'),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteCustomerGroup(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      toast.success('Customer group deleted');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to delete group'),
  });

  function startEdit(group: CustomerGroupRecord) {
    setEditing(group.id);
    setEditForm({ name: group.name, discount_pct: group.discount_pct, discount_type: group.discount_type, auto_apply: group.auto_apply, description: group.description });
  }

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load customer groups" />;

  const groups = data || [];

  return (
    <div className="space-y-4">
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <div>
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Customer Groups</h3>
            <p className="text-xs text-surface-400 mt-0.5">Define discount tiers that auto-apply when selecting a group member</p>
          </div>
          <button
            onClick={() => setShowAdd(!showAdd)}
            className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            <Plus className="h-4 w-4" /> Add Group
          </button>
        </div>

        {/* Add Form */}
        {showAdd && (
          <div className="p-4 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/30">
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Group Name</label>
                <input
                  type="text"
                  value={addForm.name}
                  onChange={(e) => setAddForm({ ...addForm, name: e.target.value })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500 w-full"
                  placeholder="e.g. VIP, Wholesale, Employee"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Discount</label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={addForm.discount_pct || ''}
                    onChange={(e) => setAddForm({ ...addForm, discount_pct: parseFloat(e.target.value) || 0 })}
                    className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24 focus:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0"
                  />
                  <select
                    value={addForm.discount_type}
                    onChange={(e) => setAddForm({ ...addForm, discount_type: e.target.value })}
                    className="px-2 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="percentage">%</option>
                    <option value="fixed">$ Fixed</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Description</label>
                <input
                  type="text"
                  value={addForm.description}
                  onChange={(e) => setAddForm({ ...addForm, description: e.target.value })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500 w-full"
                  placeholder="Optional description"
                />
              </div>
            </div>
            <div className="flex items-center gap-4 mt-3">
              <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
                <input type="checkbox" checked={!!addForm.auto_apply} onChange={(e) => setAddForm({ ...addForm, auto_apply: e.target.checked ? 1 : 0 })} className="rounded" />
                Auto-apply on checkout
              </label>
              <button
                onClick={() => {
                  if (!addForm.name.trim()) return toast.error('Group name is required');
                  createMutation.mutate(addForm);
                }}
                disabled={createMutation.isPending}
                className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50"
              >
                {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Create
              </button>
              <button onClick={() => setShowAdd(false)} className="text-sm text-surface-400 hover:text-surface-600">Cancel</button>
            </div>
          </div>
        )}

        {/* Groups List */}
        {groups.length === 0 ? (
          <EmptyState message="No customer groups defined yet" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800 text-left text-xs font-medium text-surface-500 uppercase tracking-wider">
                  <th className="px-4 py-3">Name</th>
                  <th className="px-4 py-3">Discount</th>
                  <th className="px-4 py-3">Auto-Apply</th>
                  <th className="px-4 py-3">Description</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                {groups.map((group) => (
                  <tr key={group.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                    {editing === group.id ? (
                      <>
                        <td className="px-4 py-2">
                          <input
                            type="text"
                            value={editForm.name || ''}
                            onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-32 focus:outline-none focus:ring-1 focus:ring-blue-500"
                          />
                        </td>
                        <td className="px-4 py-2">
                          <div className="flex items-center gap-1">
                            <input
                              type="number"
                              min="0"
                              step="0.01"
                              value={editForm.discount_pct || ''}
                              onChange={(e) => setEditForm({ ...editForm, discount_pct: parseFloat(e.target.value) || 0 })}
                              className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-20 focus:outline-none focus:ring-1 focus:ring-blue-500"
                            />
                            <select
                              value={editForm.discount_type || 'percentage'}
                              onChange={(e) => setEditForm({ ...editForm, discount_type: e.target.value })}
                              className="px-1 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-blue-500"
                            >
                              <option value="percentage">%</option>
                              <option value="fixed">$</option>
                            </select>
                          </div>
                        </td>
                        <td className="px-4 py-2">
                          <input
                            type="checkbox"
                            checked={!!editForm.auto_apply}
                            onChange={(e) => setEditForm({ ...editForm, auto_apply: e.target.checked ? 1 : 0 })}
                            className="rounded"
                          />
                        </td>
                        <td className="px-4 py-2">
                          <input
                            type="text"
                            value={editForm.description || ''}
                            onChange={(e) => setEditForm({ ...editForm, description: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-full focus:outline-none focus:ring-1 focus:ring-blue-500"
                          />
                        </td>
                        <td className="px-4 py-2 text-right">
                          <div className="flex items-center justify-end gap-1">
                            <button
                              onClick={() => updateMutation.mutate({ id: group.id, data: editForm })}
                              disabled={updateMutation.isPending}
                              className="p-1 text-green-600 hover:bg-green-50 dark:hover:bg-green-900/20 rounded transition-colors"
                            >
                              <Check className="h-4 w-4" />
                            </button>
                            <button onClick={() => setEditing(null)} className="p-1 text-surface-400 hover:text-surface-600 rounded transition-colors">
                              <X className="h-4 w-4" />
                            </button>
                          </div>
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="px-4 py-3">
                          <span className="font-medium text-surface-900 dark:text-surface-100">{group.name}</span>
                        </td>
                        <td className="px-4 py-3">
                          {group.discount_pct > 0 ? (
                            <span className="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-700 dark:bg-green-900/30 dark:text-green-400">
                              {group.discount_type === 'fixed' ? `$${group.discount_pct}` : `${group.discount_pct}%`} off
                            </span>
                          ) : (
                            <span className="text-surface-400 text-xs">None</span>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          <span className={cn(
                            'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                            group.auto_apply
                              ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                              : 'bg-surface-100 text-surface-400 dark:bg-surface-800 dark:text-surface-500'
                          )}>
                            {group.auto_apply ? 'Yes' : 'No'}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-surface-500 dark:text-surface-400 text-xs">
                          {group.description || '-'}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <div className="flex items-center justify-end gap-1">
                            <button onClick={() => startEdit(group)} className="p-1 text-surface-400 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20 rounded transition-colors">
                              <Pencil className="h-3.5 w-3.5" />
                            </button>
                            <button onClick={async () => { if (await confirm(`Delete group "${group.name}"?`, { danger: true })) deleteMutation.mutate(group.id); }} className="p-1 text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20 rounded transition-colors">
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </td>
                      </>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Main SettingsPage ────────────────────────────────────────────────────────

// Keywords for each settings tab for search filtering
const TAB_KEYWORDS: Record<Tab, string[]> = {
  'store': ['store', 'name', 'address', 'phone', 'email', 'timezone', 'currency', 'receipt', 'header', 'footer'],
  'statuses': ['status', 'ticket', 'workflow', 'open', 'closed', 'cancelled', 'hold', 'color', 'notify'],
  'tax': ['tax', 'rate', 'class', 'colorado', 'exempt', 'sales tax'],
  'payment': ['payment', 'method', 'cash', 'credit', 'debit', 'card', 'zelle', 'venmo', 'paypal'],
  'payment-terminal': ['blockchyp', 'terminal', 'payment', 'signature', 'card reader', 'tip'],
  'customer-groups': ['customer', 'group', 'pricing', 'tier', 'discount'],
  'users': ['user', 'employee', 'admin', 'role', 'permission', 'password', 'pin'],
  'repair-pricing': ['repair', 'pricing', 'grade', 'aftermarket', 'oem', 'premium', 'labor'],
  'tickets-repairs': ['ticket', 'repair', 'default', 'prefix', 'auto', 'assign'],
  'pos': ['pos', 'point of sale', 'checkout', 'receipt', 'cart'],
  'invoices': ['invoice', 'due', 'payment', 'terms', 'numbering'],
  'receipts': ['receipt', 'print', 'thermal', 'logo', 'template', 'header', 'footer'],
  'conditions': ['condition', 'pre-repair', 'post-repair', 'checklist', 'damage'],
  'notifications': ['notification', 'sms', 'email', 'template', 'auto', 'send', 'alert'],
  'sms-voice': ['sms', 'mms', 'voice', 'call', 'phone', 'twilio', 'telnyx', 'bandwidth', 'plivo', 'vonage', 'provider', 'recording', 'transcription', '10dlc'],
  'data-import': ['import', 'data', 'repairdesk', 'csv', 'migration', 'tools', 'reconcile', 'cogs', 'cost', 'sync', 'fix', 'export', 'maintenance'],
  'supplier-catalog': ['catalog', 'supplier', 'mobilesentrix', 'phonelcdparts', 'plp', 'parts', 'scrape', 'sync'],
  'audit-logs': ['audit', 'log', 'security', 'event', 'history', 'trail'],
};

export function SettingsPage() {
  // Read tab from URL path (e.g. /settings/users → 'users')
  const location = useLocation();
  const initialTab = (() => {
    const path = location.pathname.replace(/^\/settings\/?/, '');
    const validTabs = TABS.map(t => t.key);
    return validTabs.includes(path as Tab) ? (path as Tab) : 'store';
  })();
  const navigate = useNavigate();
  const [activeTab, setActiveTabState] = useState<Tab>(initialTab);
  const setActiveTab = (tab: Tab) => {
    setActiveTabState(tab);
    navigate(`/settings/${tab}`, { replace: true });
  };
  const [searchQuery, setSearchQuery] = useState('');
  const scrollRef = useRef<HTMLDivElement>(null);
  const [showLeftArrow, setShowLeftArrow] = useState(false);
  const [showRightArrow, setShowRightArrow] = useState(false);

  // Filter tabs based on search query
  const filteredTabs = searchQuery.trim()
    ? TABS.filter((tab) => {
        const q = searchQuery.toLowerCase();
        return tab.label.toLowerCase().includes(q) ||
          TAB_KEYWORDS[tab.key]?.some((kw) => kw.includes(q));
      })
    : TABS;

  const checkScroll = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    setShowLeftArrow(el.scrollLeft > 4);
    setShowRightArrow(el.scrollLeft + el.clientWidth < el.scrollWidth - 4);
  }, []);

  useEffect(() => {
    checkScroll();
    const el = scrollRef.current;
    if (!el) return;
    el.addEventListener('scroll', checkScroll, { passive: true });
    const ro = new ResizeObserver(checkScroll);
    ro.observe(el);
    return () => { el.removeEventListener('scroll', checkScroll); ro.disconnect(); };
  }, [checkScroll]);

  const scroll = (dir: 'left' | 'right') => {
    scrollRef.current?.scrollBy({ left: dir === 'left' ? -200 : 200, behavior: 'smooth' });
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-start justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Settings</h1>
          <p className="text-surface-500 dark:text-surface-400">Configure your CRM preferences</p>
        </div>
        <div className="relative">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => {
              setSearchQuery(e.target.value);
              // Auto-select first matching tab
              if (e.target.value.trim()) {
                const q = e.target.value.toLowerCase();
                const match = TABS.find((tab) =>
                  tab.label.toLowerCase().includes(q) ||
                  TAB_KEYWORDS[tab.key]?.some((kw) => kw.includes(q))
                );
                if (match) setActiveTab(match.key);
              }
            }}
            placeholder="Search settings..."
            className="w-56 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-sm placeholder:text-surface-400 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
          />
          {searchQuery && (
            <button onClick={() => setSearchQuery('')} className="absolute right-2 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600">
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>

      {/* Tab navigation with scroll arrows */}
      <div className="mb-6 flex items-center gap-0 relative">
        {showLeftArrow && (
          <div className="absolute left-0 z-10 flex items-center pointer-events-none">
            <button
              onClick={() => scroll('left')}
              className="pointer-events-auto shrink-0 rounded-lg p-2 bg-white/90 dark:bg-surface-800/90 text-surface-700 hover:bg-surface-100 dark:text-surface-200 dark:hover:bg-surface-700 shadow-md border border-surface-200 dark:border-surface-700"
            >
              <ChevronLeft className="h-5 w-5" />
            </button>
            <div className="w-8 h-full bg-gradient-to-r from-surface-100 dark:from-surface-800 to-transparent" />
          </div>
        )}
        <div
          ref={scrollRef}
          className={cn(
            'flex-1 min-w-0 bg-surface-100 dark:bg-surface-800 rounded-lg p-1 overflow-x-auto flex gap-0.5',
          )}
          style={{ scrollbarWidth: 'none' }}
        >
          {filteredTabs.map((tab) => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.key}
                onClick={() => setActiveTab(tab.key)}
                className={cn(
                  'flex items-center gap-1 px-2.5 py-1.5 text-xs font-medium rounded-md transition-colors whitespace-nowrap shrink-0',
                  activeTab === tab.key
                    ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                    : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
                )}
              >
                <Icon className="h-3.5 w-3.5" />
                {tab.label}
              </button>
            );
          })}
        </div>
        {showRightArrow && (
          <div className="absolute right-0 z-10 flex items-center pointer-events-none">
            <div className="w-8 h-full bg-gradient-to-l from-surface-100 dark:from-surface-800 to-transparent" />
            <button
              onClick={() => scroll('right')}
              className="pointer-events-auto shrink-0 rounded-lg p-2 bg-white/90 dark:bg-surface-800/90 text-surface-700 hover:bg-surface-100 dark:text-surface-200 dark:hover:bg-surface-700 shadow-md border border-surface-200 dark:border-surface-700"
            >
              <ChevronRight className="h-5 w-5" />
            </button>
          </div>
        )}
      </div>

      {/* Tab Content */}
      {activeTab === 'store' && <StoreInfoTab />}
      {activeTab === 'statuses' && <StatusesTab />}
      {activeTab === 'tax' && <TaxClassesTab />}
      {activeTab === 'payment' && <PaymentMethodsTab />}
      {activeTab === 'payment-terminal' && <BlockChypSettings />}
      {activeTab === 'customer-groups' && <CustomerGroupsTab />}
      {activeTab === 'users' && <UsersTab />}
      {activeTab === 'repair-pricing' && <RepairPricingTab />}
      {activeTab === 'tickets-repairs' && <TicketsRepairsSettings />}
      {activeTab === 'pos' && <PosSettings />}
      {activeTab === 'invoices' && <InvoiceSettings />}
      {activeTab === 'receipts' && <ReceiptSettings />}
      {activeTab === 'conditions' && <ConditionsTab />}
      {activeTab === 'notifications' && <NotificationTemplatesTab />}
      {activeTab === 'sms-voice' && <Suspense fallback={<div className="py-8 text-center"><Loader2 className="h-6 w-6 animate-spin mx-auto" /></div>}><SmsVoiceSettings /></Suspense>}
      {activeTab === 'data-import' && <DataImportTab />}
      {activeTab === 'supplier-catalog' && <SupplierCatalogEmbed />}
      {activeTab === 'audit-logs' && <AuditLogsTab />}
    </div>
  );
}

// ─── Import Section (with category checkboxes) ─────────────────────────────

function ImportSection({ apiKey, isActive, onStarted }: { apiKey: string; isActive: boolean; onStarted: () => void }) {
  const [entities, setEntities] = useState<Record<string, boolean>>({
    customers: true,
    tickets: true,
    invoices: true,
    inventory: true,
    sms: true,
  });

  const toggleEntity = (key: string) => setEntities(prev => ({ ...prev, [key]: !prev[key] }));
  const selectedEntities = Object.entries(entities).filter(([, v]) => v).map(([k]) => k);

  const importMut = useMutation({
    mutationFn: () => rdImportApi.start({ api_key: apiKey, entities: selectedEntities }),
    onSuccess: () => {
      toast.success('Import started!');
      onStarted();
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Import failed to start'),
  });

  const entityLabels: Record<string, { label: string; desc: string }> = {
    customers: { label: 'Customers', desc: 'Names, phones, emails, addresses' },
    tickets: { label: 'Tickets', desc: 'Repair tickets with devices, notes, history' },
    invoices: { label: 'Invoices', desc: 'Invoices with line items and payments' },
    inventory: { label: 'Inventory', desc: 'Products, parts, and services' },
    sms: { label: 'SMS Messages', desc: 'SMS conversation history' },
  };

  return (
    <div className="card p-4">
      <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-1">Import from RepairDesk</h4>
      <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
        Select which data to import. Existing records will not be duplicated.
      </p>
      <div className="space-y-2 mb-4">
        {Object.entries(entityLabels).map(([key, { label, desc }]) => (
          <label key={key} className="flex items-start gap-2 p-2 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 cursor-pointer">
            <input
              type="checkbox"
              checked={entities[key]}
              onChange={() => toggleEntity(key)}
              className="h-4 w-4 mt-0.5 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <div>
              <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</span>
              <p className="text-xs text-surface-400">{desc}</p>
            </div>
          </label>
        ))}
      </div>
      <button
        onClick={() => importMut.mutate()}
        disabled={importMut.isPending || !apiKey || selectedEntities.length === 0 || isActive}
        className="btn-primary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm"
      >
        {importMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
        {isActive ? 'Import in Progress...' : `Import ${selectedEntities.length} ${selectedEntities.length === 1 ? 'category' : 'categories'}`}
      </button>
    </div>
  );
}

// ─── Supplier Catalog Sync Section ───────────────────────────────────────────

function SupplierCatalogSyncSection() {
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);

  // Tenant catalog stats (existing endpoint)
  const { data: statsData } = useQuery({
    queryKey: ['catalog-stats'],
    queryFn: () => catalogApi.getStats(),
    staleTime: 30_000,
  });
  const tenantTotal = (statsData as any)?.data?.data?.total_catalog ?? 0;

  // Template catalog count (new endpoint)
  const { data: templateData } = useQuery({
    queryKey: ['catalog-template-count'],
    queryFn: () => catalogApi.templateCount(),
    staleTime: 30_000,
  });
  const templateCount = (templateData as any)?.data?.data?.count ?? 0;

  // Auto-sync toggle (reads from store_config)
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
    staleTime: 30_000,
  });
  const autoSync = (configData as any)?.data?.data?.catalog_auto_sync === '1';

  const toggleAutoSync = useMutation({
    mutationFn: () => settingsApi.updateConfig({ catalog_auto_sync: autoSync ? '0' : '1' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      toast.success(autoSync ? 'Auto-sync disabled' : 'Auto-sync enabled');
    },
    onError: () => toast.error('Failed to update auto-sync setting'),
  });

  // Load from template
  const loadMut = useMutation({
    mutationFn: () => catalogApi.loadFromTemplate(),
    onSuccess: (res) => {
      const copied = (res as any)?.data?.data?.copied ?? 0;
      if (copied > 0) {
        toast.success(`Loaded ${copied.toLocaleString()} catalog items from template`);
      } else {
        toast.success('Catalog is already up to date (0 new items)');
      }
      queryClient.invalidateQueries({ queryKey: ['catalog-stats'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to load catalog'),
  });

  return (
    <div className="mb-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 overflow-hidden shadow-sm">
      <button
        onClick={() => setExpanded(prev => !prev)}
        className="flex w-full items-center justify-between px-3 py-2 text-left hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
      >
        <div className="flex items-center gap-2">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Supplier Catalog</h3>
          <span className="text-xs text-surface-400 dark:text-surface-500 hidden sm:inline">&middot; Pre-populate parts catalog from shared template</span>
        </div>
        <ChevronDown className={cn('h-4 w-4 text-surface-400 transition-transform duration-200 shrink-0', expanded && 'rotate-180')} />
      </button>
      {expanded && (
        <div className="border-t border-surface-200 dark:border-surface-700 p-4 space-y-4">
          {/* Stats */}
          <div className="grid grid-cols-2 gap-4 max-w-md">
            <div className="bg-surface-50 dark:bg-surface-800 rounded-lg p-3">
              <p className="text-xs font-medium text-surface-500 dark:text-surface-400 uppercase tracking-wide">Your Catalog</p>
              <p className="text-lg font-bold text-surface-900 dark:text-surface-100 mt-1">{tenantTotal.toLocaleString()}</p>
              <p className="text-xs text-surface-400">items</p>
            </div>
            <div className="bg-surface-50 dark:bg-surface-800 rounded-lg p-3">
              <p className="text-xs font-medium text-surface-500 dark:text-surface-400 uppercase tracking-wide">Template Catalog</p>
              <p className="text-lg font-bold text-surface-900 dark:text-surface-100 mt-1">{templateCount.toLocaleString()}</p>
              <p className="text-xs text-surface-400">items available</p>
            </div>
          </div>

          {/* Actions */}
          <div className="flex flex-wrap items-center gap-3">
            <button
              onClick={() => loadMut.mutate()}
              disabled={loadMut.isPending || templateCount === 0}
              className="btn-primary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm"
            >
              {loadMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
              Load Latest Catalog
            </button>

            <label className="flex items-center gap-2 cursor-pointer select-none">
              <button
                type="button"
                role="switch"
                aria-checked={autoSync}
                onClick={() => toggleAutoSync.mutate()}
                disabled={toggleAutoSync.isPending}
                className={cn(
                  'relative inline-flex h-5 w-9 shrink-0 rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none',
                  autoSync ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600',
                )}
              >
                <span className={cn(
                  'pointer-events-none inline-block h-4 w-4 rounded-full bg-white shadow transform ring-0 transition duration-200 ease-in-out',
                  autoSync ? 'translate-x-4' : 'translate-x-0',
                )} />
              </button>
              <span className="text-sm text-surface-700 dark:text-surface-300">Auto-sync daily</span>
            </label>
          </div>

          {templateCount === 0 && (
            <p className="text-xs text-amber-600 dark:text-amber-400">
              Template catalog is empty. Run a supplier scrape first to populate it.
            </p>
          )}
        </div>
      )}
    </div>
  );
}

// ─── Data Import Tab ─────────────────────────────────────────────────────────

type ImportSource = 'repairdesk' | 'repairshopr' | 'myrepairapp';

function DataImportTab() {
  const activeSource: ImportSource = 'repairdesk'; // default for cancel routing
  const navigate = useNavigate();

  // ── Shared import progress polling (all sources) ──
  const [polling, setPolling] = useState(false);

  const { data: rdStatusData, refetch: refetchRdStatus } = useQuery({
    queryKey: ['import-status-rd'],
    queryFn: () => rdImportApi.status(),
    refetchInterval: polling ? 3000 : false,
  });
  const { data: rsStatusData, refetch: refetchRsStatus } = useQuery({
    queryKey: ['import-status-rs'],
    queryFn: () => rsImportApi.status(),
    refetchInterval: polling ? 3000 : false,
  });
  const { data: mraStatusData, refetch: refetchMraStatus } = useQuery({
    queryKey: ['import-status-mra'],
    queryFn: () => mraImportApi.status(),
    refetchInterval: polling ? 3000 : false,
  });

  const rdImportStatus = rdStatusData?.data?.data;
  const rsImportStatus = rsStatusData?.data?.data;
  const mraImportStatus = mraStatusData?.data?.data;

  const anyActive = rdImportStatus?.is_active || rsImportStatus?.is_active || mraImportStatus?.is_active;

  useEffect(() => {
    if (anyActive && !polling) setPolling(true);
    if (!anyActive && polling) setPolling(false);
  }, [anyActive, polling]);

  const refetchAll = () => { refetchRdStatus(); refetchRsStatus(); refetchMraStatus(); };
  const startPolling = () => { setPolling(true); refetchAll(); };

  // Combine runs from all sources
  const allRuns = [
    ...(rdImportStatus?.runs || []).map((r: any) => ({ ...r, source: 'RepairDesk' })),
    ...(rsImportStatus?.runs || []).map((r: any) => ({ ...r, source: 'RepairShopr' })),
    ...(mraImportStatus?.runs || []).map((r: any) => ({ ...r, source: 'MyRepairApp' })),
  ].sort((a: any, b: any) => new Date(b.created_at || 0).getTime() - new Date(a.created_at || 0).getTime());

  // Find whichever source is currently active (for progress bar)
  const activeImportStatus = rdImportStatus?.is_active ? rdImportStatus : rsImportStatus?.is_active ? rsImportStatus : mraImportStatus?.is_active ? mraImportStatus : null;

  // Cancel for active source
  const cancelMutRd = useMutation({ mutationFn: () => rdImportApi.cancel(), onSuccess: () => { toast.success('Cancel requested'); refetchAll(); } });
  const cancelMutRs = useMutation({ mutationFn: () => rsImportApi.cancel(), onSuccess: () => { toast.success('Cancel requested'); refetchAll(); } });
  const cancelMutMra = useMutation({ mutationFn: () => mraImportApi.cancel(), onSuccess: () => { toast.success('Cancel requested'); refetchAll(); } });

  const handleCancel = () => {
    if (rdImportStatus?.is_active) cancelMutRd.mutate();
    else if (rsImportStatus?.is_active) cancelMutRs.mutate();
    else if (mraImportStatus?.is_active) cancelMutMra.mutate();
  };
  const cancelPending = cancelMutRd.isPending || cancelMutRs.isPending || cancelMutMra.isPending;

  // ── Factory Wipe ──
  const [wipeConfirmText, setWipeConfirmText] = useState('');
  const [wipePassword, setWipePassword] = useState('');
  const [wipeCategories, setWipeCategories] = useState<Record<string, boolean>>({});

  const { data: wipeCounts } = useQuery({
    queryKey: ['factory-wipe-counts'],
    queryFn: () => factoryWipeApi.counts(),
    staleTime: 30_000,
  });
  const counts: Record<string, number> = (wipeCounts as any)?.data?.data ?? {};

  const wipeMut = useMutation({
    mutationFn: () => factoryWipeApi.wipe({ confirm: wipeConfirmText, password: wipePassword, categories: wipeCategories }),
    onSuccess: () => {
      toast.success('Wipe complete. Selected data has been deleted.');
      setWipeConfirmText('');
      setWipePassword('');
      setWipeCategories({});
      navigate('/');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Factory wipe failed'),
  });

  const toggleCategory = (key: string) =>
    setWipeCategories(prev => ({ ...prev, [key]: !prev[key] }));
  const anyWipeCategorySelected = Object.values(wipeCategories).some(Boolean);

  // Dependency warnings
  const wipeWarnings: string[] = [];
  if (wipeCategories.customers && !wipeCategories.tickets)
    wipeWarnings.push('Customer references on existing tickets will be removed');
  if (wipeCategories.tickets && !wipeCategories.invoices)
    wipeWarnings.push('Ticket references on existing invoices will be removed');
  if (wipeCategories.inventory && !wipeCategories.tickets)
    wipeWarnings.push('Inventory references on existing ticket parts will be removed');

  const [expandedSource, setExpandedSource] = useState<ImportSource | null>(null);
  const toggleSource = (src: ImportSource) => setExpandedSource(prev => prev === src ? null : src);

  const sources: { key: ImportSource; label: string; description: string }[] = [
    { key: 'repairdesk', label: 'RepairDesk', description: 'Import customers, tickets, invoices, inventory, and SMS from RepairDesk' },
    { key: 'repairshopr', label: 'RepairShopr', description: 'Import customers, tickets, invoices, and inventory from RepairShopr' },
    { key: 'myrepairapp', label: 'MyRepairApp', description: 'Import customers, tickets, invoices, and inventory from MyRepairApp' },
  ];

  return (
    <div>
      {/* Collapsible import sources */}
      {sources.map(({ key, label, description }) => (
        <div key={key} className="mb-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 overflow-hidden shadow-sm">
          <button
            onClick={() => toggleSource(key)}
            className="flex w-full items-center justify-between px-3 py-2 text-left hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
          >
            <div className="flex items-center gap-2">
              <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">{label}</h3>
              <span className="text-xs text-surface-400 dark:text-surface-500 hidden sm:inline">&middot; {description}</span>
            </div>
            <ChevronDown className={cn('h-4 w-4 text-surface-400 transition-transform duration-200 shrink-0', expandedSource === key && 'rotate-180')} />
          </button>
          {expandedSource === key && (
            <div className="border-t border-surface-200 dark:border-surface-700">
              {key === 'repairdesk' && (
                <RepairDeskImportSection importStatus={rdImportStatus} onStarted={startPolling} />
              )}
              {key === 'repairshopr' && (
                <RepairShoprImportSection importStatus={rsImportStatus} onStarted={startPolling} />
              )}
              {key === 'myrepairapp' && (
                <MyRepairAppImportSection importStatus={mraImportStatus} onStarted={startPolling} />
              )}
            </div>
          )}
        </div>
      ))}

      {/* Supplier Catalog Pre-population */}
      <SupplierCatalogSyncSection />

      {/* Import Progress (all sources) */}
      {allRuns.length > 0 && (
        <div className="mt-6 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-3 shadow-sm">
          <div className="flex items-center justify-between mb-3">
            <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Import Progress</h3>
            {anyActive && (
              <button onClick={handleCancel} disabled={cancelPending}
                className="btn-secondary text-sm text-red-600">
                Cancel Import
              </button>
            )}
          </div>

          {activeImportStatus?.overall && (
            <div className="mb-4 p-3 bg-surface-50 dark:bg-surface-800 rounded-lg">
              <div className="flex justify-between text-sm mb-2">
                <span>Overall: {activeImportStatus.overall.completed_entities}/{activeImportStatus.overall.total_entities} entities</span>
                <span>{activeImportStatus.overall.imported} imported, {activeImportStatus.overall.skipped} skipped, {activeImportStatus.overall.errors} errors</span>
              </div>
              <div className="w-full bg-surface-200 dark:bg-surface-700 rounded-full h-2">
                <div
                  className="bg-primary-600 h-2 rounded-full transition-all"
                  style={{ width: `${activeImportStatus.overall.total_entities ? (activeImportStatus.overall.completed_entities / activeImportStatus.overall.total_entities) * 100 : 0}%` }}
                />
              </div>
            </div>
          )}

          <div className="divide-y divide-surface-100 dark:divide-surface-800">
            {allRuns.slice(0, 15).map((run: any) => (
              <div key={`${run.source}-${run.id}`} className="flex items-center gap-3 text-sm py-2">
                <span className="text-xs font-medium text-surface-400 w-20 shrink-0">{run.source}</span>
                <span className={cn(
                  'inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium',
                  run.status === 'completed' ? 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300' :
                  run.status === 'running' ? 'bg-blue-100 text-blue-800 dark:bg-blue-900/30 dark:text-blue-300' :
                  run.status === 'failed' ? 'bg-red-100 text-red-800 dark:bg-red-900/30 dark:text-red-300' :
                  run.status === 'cancelled' ? 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300' :
                  'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-300'
                )}>
                  {run.status === 'running' && <Loader2 className="h-3 w-3 animate-spin mr-1" />}
                  {run.status}
                </span>
                <span className="font-medium text-surface-700 dark:text-surface-300 capitalize">{run.entity_type}</span>
                <span className="text-surface-500">
                  {run.imported}/{run.total_records} imported
                  {run.errors > 0 && <span className="text-red-500 ml-1">({run.errors} errors)</span>}
                </span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* Factory Wipe — always visible, outside source tabs */}
      <div className="mt-8 rounded-lg border-2 border-red-300 dark:border-red-800 bg-white dark:bg-surface-900 p-3 shadow-sm">
        <div className="flex items-start gap-2 mb-3">
          <AlertTriangle className="h-5 w-5 text-red-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="text-sm font-semibold text-red-600 dark:text-red-400">Factory Wipe</h3>
            <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">
              Select what to delete. A backup will be created automatically before proceeding.
            </p>
          </div>
        </div>

        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4 max-w-2xl">
          {/* Business Data */}
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500 mb-1.5">Business Data</p>
            <div className="space-y-1">
              {([
                ['customers', 'Customers'],
                ['tickets', 'Tickets'],
                ['invoices', 'Invoices'],
                ['inventory', 'Inventory'],
                ['sms', 'SMS Messages'],
                ['leads_estimates', 'Leads & Estimates'],
                ['expenses_pos', 'Expenses & POS'],
              ] as const).map(([key, label]) => (
                <label key={key} className="flex items-center gap-1.5 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={!!wipeCategories[key]}
                    onChange={() => toggleCategory(key)}
                    className="h-3.5 w-3.5 rounded border-surface-300 dark:border-surface-600 text-red-600 focus:ring-red-500"
                  />
                  <span className="text-sm text-surface-700 dark:text-surface-300">{label}</span>
                  {counts[key] != null && (
                    <span className="text-xs text-surface-400 dark:text-surface-500">({counts[key].toLocaleString()})</span>
                  )}
                </label>
              ))}
            </div>
          </div>

          {/* System / Advanced */}
          <div>
            <p className="text-[10px] font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500 mb-1.5">Advanced — Reset to Defaults</p>
            <div className="space-y-1">
              {([
                ['reset_settings', 'Store Settings'],
                ['reset_users', 'Users (keeps current admin)'],
                ['reset_statuses', 'Ticket Statuses'],
                ['reset_tax_classes', 'Tax Classes'],
                ['reset_payment_methods', 'Payment Methods'],
                ['reset_templates', 'Templates (SMS, notifications, checklists)'],
              ] as const).map(([key, label]) => (
                <label key={key} className="flex items-center gap-1.5 cursor-pointer">
                  <input
                    type="checkbox"
                    checked={!!wipeCategories[key]}
                    onChange={() => toggleCategory(key)}
                    className="h-3.5 w-3.5 rounded border-surface-300 dark:border-surface-600 text-red-600 focus:ring-red-500"
                  />
                  <span className="text-sm text-surface-700 dark:text-surface-300">{label}</span>
                </label>
              ))}
            </div>
          </div>
        </div>

        {/* Dependency warnings */}
        {wipeWarnings.length > 0 && (
          <div className="mt-2 space-y-0.5 max-w-2xl">
            {wipeWarnings.map((w) => (
              <p key={w} className="text-xs text-amber-600 dark:text-amber-400">&#x26A0; {w}</p>
            ))}
          </div>
        )}

        {/* Confirmation */}
        <div className="mt-4 flex flex-wrap items-end gap-2 max-w-2xl">
          <input
            type="text"
            value={wipeConfirmText}
            onChange={(e) => setWipeConfirmText(e.target.value)}
            placeholder='Type "FACTORY WIPE"'
            className="input w-44"
          />
          <input
            type="password"
            value={wipePassword}
            onChange={(e) => setWipePassword(e.target.value)}
            placeholder="Admin password"
            className="input w-44"
          />
          <button
            onClick={async () => {
              const selectedLabels = Object.entries(wipeCategories).filter(([, v]) => v).map(([k]) => k).join(', ');
              const ok = await confirm(
                `This will permanently delete the selected data (${selectedLabels}). This cannot be undone.`,
                { title: 'Factory Wipe', confirmLabel: 'Wipe Selected Data', danger: true },
              );
              if (ok) wipeMut.mutate();
            }}
            disabled={!anyWipeCategorySelected || wipeConfirmText !== 'FACTORY WIPE' || !wipePassword || wipeMut.isPending}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {wipeMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <AlertTriangle className="h-4 w-4" />}
            Wipe Selected Data
          </button>
        </div>
      </div>

      <div className="h-24" />
    </div>
  );
}

// ─── RepairDesk Import Section ──────────────────────────────────────────────

function RepairDeskImportSection({ importStatus, onStarted }: { importStatus: any; onStarted: () => void }) {
  const [apiKey, setApiKey] = useState('');
  const [apiKeySaved, setApiKeySaved] = useState(false);
  const [confirmText, setConfirmText] = useState('');
  const [nuclearPassword, setNuclearPassword] = useState('');
  const queryClient = useQueryClient();
  const isActive = importStatus?.is_active;

  // Load saved API key from store_config on mount
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
    staleTime: 30_000,
  });
  useEffect(() => {
    const saved = (configData as any)?.data?.data?.rd_api_key;
    if (saved && !apiKey) {
      setApiKey(saved);
      setApiKeySaved(true);
    }
  }, [configData]); // intentional: sync from server data only when configData changes

  const saveKeyMut = useMutation({
    mutationFn: () => settingsApi.updateConfig({ rd_api_key: apiKey.trim() }),
    onSuccess: () => {
      toast.success('API key saved');
      setApiKeySaved(true);
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
    },
    onError: () => toast.error('Failed to save API key'),
  });

  const testMut = useMutation({
    mutationFn: () => rdImportApi.testConnection(apiKey),
    onSuccess: (res) => {
      const data = res.data?.data;
      if (data?.ok) toast.success(`Connected! ${data.totalCustomers} customers found.`);
      else toast.error(`Connection failed: ${data?.message}`);
    },
    onError: () => toast.error('Connection test failed'),
  });

  const nuclearMut = useMutation({
    mutationFn: () => rdImportApi.nuclear(apiKey, nuclearPassword),
    onSuccess: () => {
      toast.success('Nuclear wipe + reimport started!');
      setConfirmText('');
      setNuclearPassword('');
      onStarted();
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Nuclear import failed'),
  });

  return (
    <>
      {/* API Key */}
      <div className="card p-4">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-4">API Key</h4>
        <div className="flex gap-3">
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="RepairDesk API Key (Bearer token)"
            className="flex-1 input"
          />
          <button onClick={() => saveKeyMut.mutate()} disabled={saveKeyMut.isPending || !apiKey.trim()}
            className="btn-secondary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm whitespace-nowrap">
            {saveKeyMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Save className="h-3.5 w-3.5" />}
            Save
          </button>
          <button onClick={() => testMut.mutate()} disabled={testMut.isPending || !apiKey}
            className="btn-secondary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm whitespace-nowrap">
            {testMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
            Test
          </button>
        </div>
        {apiKeySaved && <p className="text-xs text-green-600 dark:text-green-400 mt-2 flex items-center gap-1"><Check className="h-3 w-3" />API key saved to database</p>}
      </div>

      {/* Standard Import */}
      <ImportSection apiKey={apiKey} isActive={isActive} onStarted={onStarted} />

      {/* Reset & Reimport */}
      <div className="mt-6 rounded-lg border border-amber-300 dark:border-amber-800 bg-white dark:bg-surface-900 p-4">
        <div className="flex items-start gap-2 mb-3">
          <AlertCircle className="h-5 w-5 text-amber-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="text-sm font-semibold text-amber-600 dark:text-amber-400">Reset &amp; Reimport</h3>
            <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">
              This will <strong>only delete data that was imported</strong> from this source. Manually created records are preserved. Then reimports everything fresh.
            </p>
          </div>
        </div>

        <div className="space-y-3 max-w-md">
          <input
            type="text"
            value={confirmText}
            onChange={(e) => setConfirmText(e.target.value)}
            placeholder='Type "NUCLEAR" to confirm'
            className="input w-full"
          />
          <input
            type="password"
            value={nuclearPassword}
            onChange={(e) => setNuclearPassword(e.target.value)}
            placeholder="Your password"
            className="input w-full"
          />
          <button
            onClick={() => nuclearMut.mutate()}
            disabled={confirmText !== 'NUCLEAR' || !nuclearPassword || nuclearMut.isPending || isActive || !apiKey}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {nuclearMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Database className="h-4 w-4" />}
            Wipe &amp; Reimport Everything
          </button>
        </div>
      </div>
    </>
  );
}

// ─── RepairShopr Import Section ─────────────────────────────────────────────

function RepairShoprImportSection({ importStatus, onStarted }: { importStatus: any; onStarted: () => void }) {
  const [apiKey, setApiKey] = useState('');
  const [subdomain, setSubdomain] = useState('');
  const [confirmText, setConfirmText] = useState('');
  const [nuclearPassword, setNuclearPassword] = useState('');
  const isActive = importStatus?.is_active;

  const [entities, setEntities] = useState<Record<string, boolean>>({
    customers: true,
    tickets: true,
    invoices: true,
    inventory: true,
  });
  const toggleEntity = (key: string) => setEntities(prev => ({ ...prev, [key]: !prev[key] }));
  const selectedEntities = Object.entries(entities).filter(([, v]) => v).map(([k]) => k);

  const entityLabels: Record<string, { label: string; desc: string }> = {
    customers: { label: 'Customers', desc: 'Names, phones, emails, addresses' },
    tickets: { label: 'Tickets', desc: 'Repair tickets with devices and notes' },
    invoices: { label: 'Invoices', desc: 'Invoices with line items and payments' },
    inventory: { label: 'Inventory', desc: 'Products, parts, and services' },
  };

  const testMut = useMutation({
    mutationFn: () => rsImportApi.testConnection({ api_key: apiKey, subdomain }),
    onSuccess: (res) => {
      const data = res.data?.data;
      if (data?.ok) toast.success(`Connected to ${subdomain}.repairshopr.com!`);
      else toast.error(`Connection failed: ${data?.message}`);
    },
    onError: () => toast.error('Connection test failed'),
  });

  const importMut = useMutation({
    mutationFn: () => rsImportApi.start({ api_key: apiKey, subdomain, entities: selectedEntities }),
    onSuccess: () => { toast.success('Import started!'); onStarted(); },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Import failed to start'),
  });

  const nuclearMut = useMutation({
    mutationFn: () => rsImportApi.nuclear({ api_key: apiKey, subdomain, confirm: 'NUCLEAR', password: nuclearPassword }),
    onSuccess: () => {
      toast.success('Nuclear wipe + reimport started!');
      setConfirmText('');
      setNuclearPassword('');
      onStarted();
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Nuclear import failed'),
  });

  return (
    <>
      {/* Connection */}
      <div className="card p-4">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-4">API Key</h4>
        <div className="flex gap-3 mb-3">
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="RepairShopr API Key"
            className="flex-1 input"
          />
          <div className="flex items-center rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 overflow-hidden">
            <input
              type="text"
              value={subdomain}
              onChange={(e) => setSubdomain(e.target.value)}
              placeholder="myshop"
              className="w-28 px-3 py-2 text-sm bg-transparent text-surface-900 dark:text-surface-100 focus:outline-none"
            />
            <span className="px-3 py-2 text-xs text-surface-400 bg-surface-50 dark:bg-surface-700 border-l border-surface-200 dark:border-surface-600 whitespace-nowrap">.repairshopr.com</span>
          </div>
          <button onClick={() => testMut.mutate()} disabled={testMut.isPending || !apiKey || !subdomain}
            className="btn-secondary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm whitespace-nowrap">
            {testMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
            Test Connection
          </button>
        </div>
      </div>

      {/* Entity selection + Import */}
      <div className="card p-4">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-1">Import from RepairShopr</h4>
        <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
          Select which data to import. Existing records will not be duplicated.
        </p>
        <div className="space-y-2 mb-4">
          {Object.entries(entityLabels).map(([key, { label, desc }]) => (
            <label key={key} className="flex items-start gap-2 p-2 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 cursor-pointer">
              <input type="checkbox" checked={entities[key]} onChange={() => toggleEntity(key)}
                className="h-4 w-4 mt-0.5 rounded border-surface-300 text-primary-600 focus:ring-primary-500" />
              <div>
                <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</span>
                <p className="text-xs text-surface-400">{desc}</p>
              </div>
            </label>
          ))}
        </div>
        <button
          onClick={() => importMut.mutate()}
          disabled={importMut.isPending || !apiKey || !subdomain || selectedEntities.length === 0 || isActive}
          className="btn-primary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm"
        >
          {importMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          {isActive ? 'Import in Progress...' : `Import ${selectedEntities.length} ${selectedEntities.length === 1 ? 'category' : 'categories'}`}
        </button>
      </div>

      {/* Reset & Reimport */}
      <div className="card p-4 border border-amber-300 dark:border-amber-800">
        <div className="flex items-start gap-3 mb-4">
          <AlertCircle className="h-6 w-6 text-amber-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-semibold text-amber-600 dark:text-amber-400">Reset &amp; Reimport</h3>
            <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
              This will <strong>delete ALL data</strong> and reimport everything fresh from RepairShopr.
            </p>
          </div>
        </div>
        <div className="space-y-3 max-w-md">
          <input type="text" value={confirmText} onChange={(e) => setConfirmText(e.target.value)}
            placeholder='Type "NUCLEAR" to confirm' className="input w-full" />
          <input type="password" value={nuclearPassword} onChange={(e) => setNuclearPassword(e.target.value)}
            placeholder="Your password" className="input w-full" />
          <button
            onClick={() => nuclearMut.mutate()}
            disabled={confirmText !== 'NUCLEAR' || !nuclearPassword || nuclearMut.isPending || isActive || !apiKey || !subdomain}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {nuclearMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Database className="h-4 w-4" />}
            Wipe &amp; Reimport Everything
          </button>
        </div>
      </div>
    </>
  );
}

// ─── MyRepairApp Import Section ─────────────────────────────────────────────

function MyRepairAppImportSection({ importStatus, onStarted }: { importStatus: any; onStarted: () => void }) {
  const [apiKey, setApiKey] = useState('');
  const [confirmText, setConfirmText] = useState('');
  const [nuclearPassword, setNuclearPassword] = useState('');
  const isActive = importStatus?.is_active;

  const [entities, setEntities] = useState<Record<string, boolean>>({
    customers: true,
    tickets: true,
    invoices: true,
    inventory: true,
  });
  const toggleEntity = (key: string) => setEntities(prev => ({ ...prev, [key]: !prev[key] }));
  const selectedEntities = Object.entries(entities).filter(([, v]) => v).map(([k]) => k);

  const entityLabels: Record<string, { label: string; desc: string }> = {
    customers: { label: 'Customers', desc: 'Names, phones, emails, addresses' },
    tickets: { label: 'Tickets', desc: 'Repair tickets with devices and notes' },
    invoices: { label: 'Invoices', desc: 'Invoices with line items and payments' },
    inventory: { label: 'Inventory', desc: 'Products, parts, and services' },
  };

  const testMut = useMutation({
    mutationFn: () => mraImportApi.testConnection({ api_key: apiKey }),
    onSuccess: (res) => {
      const data = res.data?.data;
      if (data?.ok) toast.success('Connected to MyRepairApp!');
      else toast.error(`Connection failed: ${data?.message}`);
    },
    onError: () => toast.error('Connection test failed'),
  });

  const importMut = useMutation({
    mutationFn: () => mraImportApi.start({ api_key: apiKey, entities: selectedEntities }),
    onSuccess: () => { toast.success('Import started!'); onStarted(); },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Import failed to start'),
  });

  const nuclearMut = useMutation({
    mutationFn: () => mraImportApi.nuclear({ api_key: apiKey, confirm: 'NUCLEAR', password: nuclearPassword }),
    onSuccess: () => {
      toast.success('Nuclear wipe + reimport started!');
      setConfirmText('');
      setNuclearPassword('');
      onStarted();
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Nuclear import failed'),
  });

  return (
    <>
      {/* Connection */}
      <div className="card p-4">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-4">API Key</h4>
        <div className="flex gap-3">
          <input
            type="password"
            value={apiKey}
            onChange={(e) => setApiKey(e.target.value)}
            placeholder="MyRepairApp API Key"
            className="flex-1 input"
          />
          <button onClick={() => testMut.mutate()} disabled={testMut.isPending || !apiKey}
            className="btn-secondary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm whitespace-nowrap">
            {testMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <Check className="h-3.5 w-3.5" />}
            Test Connection
          </button>
        </div>
      </div>

      {/* Entity selection + Import */}
      <div className="card p-4">
        <h4 className="text-xs font-semibold uppercase tracking-wide text-surface-500 mb-1">Import from MyRepairApp</h4>
        <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
          Select which data to import. Existing records will not be duplicated.
        </p>
        <div className="space-y-2 mb-4">
          {Object.entries(entityLabels).map(([key, { label, desc }]) => (
            <label key={key} className="flex items-start gap-2 p-2 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 cursor-pointer">
              <input type="checkbox" checked={entities[key]} onChange={() => toggleEntity(key)}
                className="h-4 w-4 mt-0.5 rounded border-surface-300 text-primary-600 focus:ring-primary-500" />
              <div>
                <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</span>
                <p className="text-xs text-surface-400">{desc}</p>
              </div>
            </label>
          ))}
        </div>
        <button
          onClick={() => importMut.mutate()}
          disabled={importMut.isPending || !apiKey || selectedEntities.length === 0 || isActive}
          className="btn-primary flex items-center gap-2 disabled:opacity-50 px-4 py-2 text-sm"
        >
          {importMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Download className="h-4 w-4" />}
          {isActive ? 'Import in Progress...' : `Import ${selectedEntities.length} ${selectedEntities.length === 1 ? 'category' : 'categories'}`}
        </button>
      </div>

      {/* Reset & Reimport */}
      <div className="card p-4 border border-amber-300 dark:border-amber-800">
        <div className="flex items-start gap-3 mb-4">
          <AlertCircle className="h-6 w-6 text-amber-500 flex-shrink-0 mt-0.5" />
          <div>
            <h3 className="font-semibold text-amber-600 dark:text-amber-400">Reset &amp; Reimport</h3>
            <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
              This will <strong>delete ALL data</strong> and reimport everything fresh from MyRepairApp.
            </p>
          </div>
        </div>
        <div className="space-y-3 max-w-md">
          <input type="text" value={confirmText} onChange={(e) => setConfirmText(e.target.value)}
            placeholder='Type "NUCLEAR" to confirm' className="input w-full" />
          <input type="password" value={nuclearPassword} onChange={(e) => setNuclearPassword(e.target.value)}
            placeholder="Your password" className="input w-full" />
          <button
            onClick={() => nuclearMut.mutate()}
            disabled={confirmText !== 'NUCLEAR' || !nuclearPassword || nuclearMut.isPending || isActive || !apiKey}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm bg-red-600 hover:bg-red-700 text-white rounded-lg font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {nuclearMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Database className="h-4 w-4" />}
            Wipe &amp; Reimport Everything
          </button>
        </div>
      </div>
    </>
  );
}

// ─── Supplier Catalog (embedded from CatalogPage) ────────────────────────────

const LazyCatalogPage = lazy(() => import('../catalog/CatalogPage').then(m => ({ default: m.CatalogPage })));

function SupplierCatalogEmbed() {
  return (
    <Suspense fallback={<div className="p-8 text-center text-surface-400">Loading catalog...</div>}>
      <LazyCatalogPage />
    </Suspense>
  );
}

// ─── Data Tools Tab ──────────────────────────────────────────────────────────

function DataToolsTab() {
  const [syncRunning, setSyncRunning] = useState(false);
  const [syncResult, setSyncResult] = useState<any>(null);

  const runSyncCosts = async () => {
    setSyncRunning(true);
    setSyncResult(null);
    try {
      const res = await catalogApi.syncCostPrices();
      setSyncResult(res.data.data);
      toast.success(`Synced ${res.data.data.updated} cost prices`);
    } catch (e: any) {
      toast.error(e?.response?.data?.message || 'Sync failed');
    } finally { setSyncRunning(false); }
  };

  return (
    <div className="p-6 space-y-6">
      <div>
        <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100 mb-1">Data Tools</h3>
        <p className="text-sm text-surface-500 dark:text-surface-400">Maintenance scripts for data reconciliation and cleanup. These can be run multiple times safely.</p>
      </div>

      {/* Sync Cost Prices */}
      <div className="rounded-lg border border-surface-200 dark:border-surface-700 p-5">
        <div className="flex items-start justify-between">
          <div>
            <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Sync Cost Prices from Catalog</h4>
            <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">
              Match phone/tablet parts in inventory to PLP/Mobilesentrix catalog and fill missing cost prices.
              Only updates items with $0 cost — never overwrites existing prices. Safe to run multiple times.
            </p>
          </div>
          <button
            onClick={runSyncCosts}
            disabled={syncRunning}
            className="shrink-0 inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50 transition-colors"
          >
            {syncRunning ? <><Loader2 className="h-4 w-4 animate-spin" /> Syncing...</> : 'Sync Cost Prices'}
          </button>
        </div>
        {syncResult && (
          <div className="mt-4 rounded-lg bg-surface-50 dark:bg-surface-800/50 p-4 text-sm space-y-2">
            <div className="grid grid-cols-2 gap-3">
              <div className="text-center">
                <p className="text-lg font-bold text-green-600">{syncResult.updated}</p>
                <p className="text-[10px] uppercase text-surface-500">Updated</p>
              </div>
              <div className="text-center">
                <p className="text-lg font-bold text-blue-600">{syncResult.matched}</p>
                <p className="text-[10px] uppercase text-surface-500">Matched</p>
              </div>
            </div>
            {syncResult.details?.length > 0 && (
              <details className="mt-2">
                <summary className="cursor-pointer text-xs font-medium text-primary-600 dark:text-primary-400">
                  View {syncResult.details.length} matches
                </summary>
                <div className="mt-2 max-h-64 overflow-y-auto space-y-1">
                  {syncResult.details.map((m: any, i: number) => (
                    <div key={i} className="flex items-center gap-2 text-[11px] text-surface-600 dark:text-surface-400">
                      <span className="font-medium truncate max-w-[200px]" title={m.item_name}>{m.item_name}</span>
                      <span className="text-surface-300">→</span>
                      <span className="truncate max-w-[250px] text-green-600" title={m.catalog_name}>{m.catalog_name}</span>
                      <span className="shrink-0 font-mono">${m.price.toFixed(2)}</span>
                    </div>
                  ))}
                </div>
              </details>
            )}
            {syncResult.updated === 0 && (
              <p className="text-xs text-surface-400 mt-1">All inventory items already have cost prices set, or no matching catalog items found.</p>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
