import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation } from '@tanstack/react-query';
import {
  Plus, X, Search, User, Smartphone, Tablet, Laptop, Monitor, Gamepad2,
  Tv, HelpCircle, Loader2, ChevronDown,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, customerApi, settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { BackButton } from '@/components/shared/BackButton';
import type { CreateTicketDeviceInput } from '@bizarre-crm/shared';

// ─── Types ──────────────────────────────────────────────────────────
interface CustomerResult {
  id: number;
  first_name: string;
  last_name: string;
  phone: string | null;
  mobile: string | null;
  email: string | null;
  organization: string | null;
}

interface NewCustomerForm {
  first_name: string;
  last_name: string;
  phone: string;
  email: string;
}

interface DeviceForm {
  _key: string;
  device_name: string;
  device_type: string;
  imei: string;
  serial: string;
  security_code: string;
  price: string;
  additional_notes: string;
}

const DEVICE_TYPES = [
  { value: 'Phone', icon: Smartphone },
  { value: 'Tablet', icon: Tablet },
  { value: 'Laptop', icon: Laptop },
  { value: 'Desktop', icon: Monitor },
  { value: 'Game Console', icon: Gamepad2 },
  { value: 'TV', icon: Tv },
  { value: 'Other', icon: HelpCircle },
];

const SOURCES = ['Walk-in', 'Phone', 'Online', 'Referral'];

function makeDevice(): DeviceForm {
  return {
    _key: (crypto.randomUUID?.() ?? Math.random().toString(36).slice(2) + Date.now().toString(36)),
    device_name: '',
    device_type: 'Phone',
    imei: '',
    serial: '',
    security_code: '',
    price: '',
    additional_notes: '',
  };
}

// ─── Section wrapper ────────────────────────────────────────────────
function Section({ title, step, children }: { title: string; step: number; children: React.ReactNode }) {
  return (
    <div className="card p-4 md:p-6">
      <div className="mb-5 flex items-center gap-3">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-primary-600 text-xs font-bold text-white">
          {step}
        </span>
        <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">{title}</h2>
      </div>
      {children}
    </div>
  );
}

// ─── Input helpers ──────────────────────────────────────────────────
function FormLabel({ label, required, htmlFor }: { label: string; required?: boolean; htmlFor?: string }) {
  return (
    <label htmlFor={htmlFor} className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
      {label}
      {required && <span className="ml-0.5 text-red-500">*</span>}
    </label>
  );
}

function TextInput({
  label, required, value, onChange, placeholder, type = 'text', prefix,
}: {
  label: string; required?: boolean; value: string; onChange: (v: string) => void;
  placeholder?: string; type?: string; prefix?: string;
}) {
  return (
    <div>
      <FormLabel label={label} required={required} />
      <div className="relative">
        {prefix && (
          <span className="pointer-events-none absolute left-3 top-1/2 -translate-y-1/2 text-sm text-surface-400">
            {prefix}
          </span>
        )}
        <input
          type={type}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          className={cn(
            'w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400',
            'dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100',
            'focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500',
            prefix && 'pl-7',
          )}
        />
      </div>
    </div>
  );
}

function SelectInput({
  label, value, onChange, options, placeholder,
}: {
  label: string; value: string; onChange: (v: string) => void;
  options: { value: string; label: string }[]; placeholder?: string;
}) {
  return (
    <div>
      <FormLabel label={label} />
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500"
      >
        {placeholder && <option value="">{placeholder}</option>}
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────
export function TicketCreatePage() {
  const navigate = useNavigate();

  // ─── Customer state ─────────────────────────────────────────────
  const [customerSearch, setCustomerSearch] = useState('');
  const [selectedCustomer, setSelectedCustomer] = useState<CustomerResult | null>(null);
  const [showNewCustomer, setShowNewCustomer] = useState(false);
  const [newCustomer, setNewCustomer] = useState<NewCustomerForm>({
    first_name: '', last_name: '', phone: '', email: '',
  });
  const [searchOpen, setSearchOpen] = useState(false);
  const searchRef = useRef<HTMLDivElement>(null);

  // Debounced customer search
  const [debouncedSearch, setDebouncedSearch] = useState('');
  const debounceRef = useRef<ReturnType<typeof setTimeout>>(undefined);
  useEffect(() => {
    clearTimeout(debounceRef.current);
    debounceRef.current = setTimeout(() => setDebouncedSearch(customerSearch), 300);
    return () => clearTimeout(debounceRef.current);
  }, [customerSearch]);

  const { data: searchData, isLoading: searchLoading } = useQuery({
    queryKey: ['customer-search', debouncedSearch],
    queryFn: () => customerApi.search(debouncedSearch),
    enabled: debouncedSearch.length >= 2,
  });
  const searchResults: CustomerResult[] = (() => {
    const d = searchData?.data?.data;
    return Array.isArray(d) ? d : d?.customers || [];
  })();

  // Close search dropdown on outside click
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (searchRef.current && !searchRef.current.contains(e.target as Node)) setSearchOpen(false);
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // ─── Devices state ────────────────────────────────────────────────
  const [devices, setDevices] = useState<DeviceForm[]>([makeDevice()]);

  function updateDevice(key: string, field: keyof DeviceForm, value: string) {
    setDevices((prev) =>
      prev.map((d) => (d._key === key ? { ...d, [field]: value } : d)),
    );
  }

  function removeDevice(key: string) {
    setDevices((prev) => prev.filter((d) => d._key !== key));
  }

  // ─── Summary state ────────────────────────────────────────────────
  const [source, setSource] = useState('Walk-in');
  const [referredBy, setReferredBy] = useState('');
  const [assignedTo, setAssignedTo] = useState('');
  const [labels, setLabels] = useState('');
  const [dueDate, setDueDate] = useState('');

  // ─── Statuses ─────────────────────────────────────────────────────
  const { data: statusData } = useQuery({
    queryKey: ['ticket-statuses'],
    queryFn: () => settingsApi.getStatuses(),
  });
  const statuses = statusData?.data?.data?.statuses || statusData?.data?.statuses || [];

  // ─── Users (technicians) ──────────────────────────────────────────
  const { data: usersData } = useQuery({
    queryKey: ['users'],
    queryFn: () => settingsApi.getUsers(),
  });
  const users: { id: number; first_name: string; last_name: string }[] =
    usersData?.data?.data?.users || usersData?.data?.data || [];

  // ─── Form errors ──────────────────────────────────────────────────
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});

  // ─── Referral sources ─────────────────────────────────────────────
  const { data: referralData } = useQuery({
    queryKey: ['referral-sources'],
    queryFn: () => settingsApi.getReferralSources(),
  });
  const referralSources: { id: number; name: string }[] =
    referralData?.data?.data?.referral_sources || referralData?.data?.data?.sources || [];

  // ─── Tax classes ──────────────────────────────────────────────────
  const { data: taxClassData } = useQuery({
    queryKey: ['tax-classes'],
    queryFn: () => settingsApi.getTaxClasses(),
  });
  const taxClasses: { id: number; name: string; rate: number; is_default?: boolean }[] =
    taxClassData?.data?.data?.tax_classes || taxClassData?.data?.data || [];
  const defaultTaxRate = (taxClasses.find((tc) => tc.is_default)?.rate ?? taxClasses[0]?.rate ?? 0) / 100;

  // Computed totals
  const subtotal = devices.reduce((sum, d) => sum + (parseFloat(d.price) || 0), 0);
  const tax = subtotal * defaultTaxRate;
  const total = subtotal + tax;

  // ─── Create customer mutation ─────────────────────────────────────
  const createCustomerMut = useMutation({
    mutationFn: (data: NewCustomerForm) =>
      customerApi.create(data as any),
    onSuccess: (res) => {
      const created = res?.data?.data;
      if (created) {
        setSelectedCustomer(created);
        setShowNewCustomer(false);
        toast.success('Customer created');
      }
    },
    onError: () => toast.error('Failed to create customer'),
  });

  // ─── Submit mutation ──────────────────────────────────────────────
  const createTicketMut = useMutation({
    mutationFn: (data: any) => ticketApi.create(data),
    onSuccess: (res) => {
      const ticket = res?.data?.data;
      toast.success('Ticket created successfully');
      navigate(ticket?.id ? `/tickets/${ticket.id}` : '/tickets');
    },
    onError: () => toast.error('Failed to create ticket'),
  });

  function handleSubmit() {
    const newErrors: Record<string, string> = {};
    if (!selectedCustomer) {
      newErrors.customer = 'Please select or create a customer';
    }
    if (devices.length === 0 || devices.every((d) => !d.device_name.trim())) {
      newErrors.devices = 'Please add at least one device with a name';
    }
    if (Object.keys(newErrors).length > 0) {
      setFormErrors(newErrors);
      return;
    }
    setFormErrors({});

    const ticketDevices: CreateTicketDeviceInput[] = devices
      .filter((d) => d.device_name.trim())
      .map((d) => ({
        device_name: d.device_name.trim(),
        device_type: d.device_type || undefined,
        imei: d.imei || undefined,
        serial: d.serial || undefined,
        security_code: d.security_code || undefined,
        price: parseFloat(d.price) || 0,
        additional_notes: d.additional_notes || undefined,
      }));

    createTicketMut.mutate({
      customer_id: selectedCustomer!.id,
      source: source || undefined,
      referral_source: referredBy || undefined,
      assigned_to: assignedTo ? Number(assignedTo) : undefined,
      labels: labels ? labels.split(',').map((l) => l.trim()).filter(Boolean) : undefined,
      due_on: dueDate || undefined,
      devices: ticketDevices,
    });
  }

  // ─── Render ───────────────────────────────────────────────────────
  return (
    <div className="mx-auto max-w-4xl">
      {/* Header */}
      <div className="mb-6 flex items-center gap-4">
        <BackButton to="/tickets" />
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Create Ticket</h1>
          <p className="text-surface-500 dark:text-surface-400">Open a new repair ticket</p>
        </div>
      </div>

      <div className="space-y-6">
        {/* ─── Step 1: Customer ──────────────────────────────────────── */}
        <Section title="Customer" step={1}>
          {selectedCustomer ? (
            <div className="flex items-center justify-between rounded-lg border border-primary-200 bg-primary-50/50 p-4 dark:border-primary-800 dark:bg-primary-950/20">
              <div className="flex items-center gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-full bg-primary-100 text-primary-600 dark:bg-primary-900 dark:text-primary-400">
                  <User className="h-5 w-5" />
                </div>
                <div>
                  <p className="font-medium text-surface-900 dark:text-surface-100">
                    {selectedCustomer.first_name} {selectedCustomer.last_name}
                  </p>
                  <p className="text-sm text-surface-500 dark:text-surface-400">
                    {[selectedCustomer.mobile || selectedCustomer.phone, selectedCustomer.email]
                      .filter(Boolean)
                      .join(' · ')}
                  </p>
                </div>
              </div>
              <button
                onClick={() => { setSelectedCustomer(null); setCustomerSearch(''); }}
                className="rounded-lg p-1.5 text-surface-400 transition-colors hover:bg-surface-200 hover:text-surface-600 dark:hover:bg-surface-700"
              >
                <X className="h-4 w-4" />
              </button>
            </div>
          ) : (
            <>
              {/* Search */}
              <div className="relative" ref={searchRef}>
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                  <input
                    type="text"
                    value={customerSearch}
                    onChange={(e) => { setCustomerSearch(e.target.value); setSearchOpen(true); }}
                    onFocus={() => setSearchOpen(true)}
                    placeholder="Search by name, phone, or email..."
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 py-2.5 pl-10 pr-4 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500"
                  />
                  {searchLoading && (
                    <Loader2 className="absolute right-3 top-1/2 h-4 w-4 -translate-y-1/2 animate-spin text-surface-400" />
                  )}
                </div>

                {/* Search results dropdown */}
                {searchOpen && debouncedSearch.length >= 2 && (
                  <div className="absolute left-0 right-0 top-full z-50 mt-1 max-h-60 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                    {searchResults.length === 0 && !searchLoading && (
                      <div className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">
                        No customers found
                      </div>
                    )}
                    {searchResults.map((c) => (
                      <button
                        key={c.id}
                        onClick={() => {
                          setSelectedCustomer(c);
                          setSearchOpen(false);
                          setCustomerSearch('');
                          setFormErrors((prev) => { const n = { ...prev }; delete n.customer; return n; });
                        }}
                        className="flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors hover:bg-surface-50 dark:hover:bg-surface-700"
                      >
                        <div className="flex h-8 w-8 items-center justify-center rounded-full bg-surface-100 text-xs font-medium text-surface-600 dark:bg-surface-700 dark:text-surface-300">
                          {c.first_name.charAt(0)}{c.last_name.charAt(0)}
                        </div>
                        <div>
                          <p className="text-sm font-medium text-surface-800 dark:text-surface-200">
                            {c.first_name} {c.last_name}
                          </p>
                          <p className="text-xs text-surface-500 dark:text-surface-400">
                            {[c.mobile || c.phone, c.email].filter(Boolean).join(' · ')}
                          </p>
                        </div>
                      </button>
                    ))}
                  </div>
                )}
              </div>

              {/* Create new customer toggle */}
              <div className="mt-3">
                <button
                  onClick={() => setShowNewCustomer((v) => !v)}
                  className="inline-flex items-center gap-1.5 text-sm font-medium text-primary-600 transition-colors hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300"
                >
                  <Plus className="h-4 w-4" />
                  {showNewCustomer ? 'Cancel New Customer' : 'Create New Customer'}
                </button>
              </div>

              {/* Inline new customer form */}
              {showNewCustomer && (
                <div className="mt-4 rounded-lg border border-surface-200 bg-surface-50/50 p-4 dark:border-surface-700 dark:bg-surface-800/50">
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <TextInput
                      label="First Name"
                      required
                      value={newCustomer.first_name}
                      onChange={(v) => setNewCustomer((p) => ({ ...p, first_name: v }))}
                      placeholder="John"
                    />
                    <TextInput
                      label="Last Name"
                      required
                      value={newCustomer.last_name}
                      onChange={(v) => setNewCustomer((p) => ({ ...p, last_name: v }))}
                      placeholder="Doe"
                    />
                    <TextInput
                      label="Phone"
                      value={newCustomer.phone}
                      onChange={(v) => setNewCustomer((p) => ({ ...p, phone: v }))}
                      placeholder="(555) 123-4567"
                      type="tel"
                    />
                    <TextInput
                      label="Email"
                      value={newCustomer.email}
                      onChange={(v) => setNewCustomer((p) => ({ ...p, email: v }))}
                      placeholder="john@example.com"
                      type="email"
                    />
                  </div>
                  <div className="mt-4">
                    <button
                      onClick={() => {
                        if (!newCustomer.first_name.trim() || !newCustomer.last_name.trim()) {
                          toast.error('First and last name are required');
                          return;
                        }
                        createCustomerMut.mutate(newCustomer);
                      }}
                      disabled={createCustomerMut.isPending}
                      className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white transition-colors hover:bg-primary-700 disabled:opacity-50"
                    >
                      {createCustomerMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
                      Create Customer
                    </button>
                  </div>
                </div>
              )}
            </>
          )}
          {formErrors.customer && (
            <p className="mt-2 text-xs text-red-500">{formErrors.customer}</p>
          )}
        </Section>

        {/* ─── Step 2: Devices ───────────────────────────────────────── */}
        <Section title="Devices" step={2}>
          <div className="space-y-4">
            {devices.map((device, idx) => (
              <div
                key={device._key}
                className="relative rounded-lg border border-surface-200 bg-surface-50/50 p-4 dark:border-surface-700 dark:bg-surface-800/50"
              >
                {/* Device header */}
                <div className="mb-4 flex items-center justify-between">
                  <h3 className="text-sm font-medium text-surface-700 dark:text-surface-300">
                    Device {idx + 1}
                  </h3>
                  {devices.length > 1 && (
                    <button
                      onClick={() => removeDevice(device._key)}
                      className="rounded-lg p-1 text-surface-400 transition-colors hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-950/30"
                      title="Remove device"
                    >
                      <X className="h-4 w-4" />
                    </button>
                  )}
                </div>

                <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                  <TextInput
                    label="Device Name"
                    required
                    value={device.device_name}
                    onChange={(v) => updateDevice(device._key, 'device_name', v)}
                    placeholder="iPhone 15 Pro Max"
                  />
                  <SelectInput
                    label="Device Type"
                    value={device.device_type}
                    onChange={(v) => updateDevice(device._key, 'device_type', v)}
                    options={DEVICE_TYPES.map((t) => ({ value: t.value, label: t.value }))}
                  />
                  <TextInput
                    label="IMEI"
                    value={device.imei}
                    onChange={(v) => updateDevice(device._key, 'imei', v)}
                    placeholder="Enter IMEI number"
                  />
                  <TextInput
                    label="Serial Number"
                    value={device.serial}
                    onChange={(v) => updateDevice(device._key, 'serial', v)}
                    placeholder="Enter serial number"
                  />
                  <TextInput
                    label="Security Code"
                    value={device.security_code}
                    onChange={(v) => updateDevice(device._key, 'security_code', v)}
                    placeholder="Enter passcode"
                  />
                  <TextInput
                    label="Price"
                    value={device.price}
                    onChange={(v) => updateDevice(device._key, 'price', v)}
                    placeholder="0.00"
                    type="number"
                    prefix="$"
                  />
                </div>

                <div className="mt-4">
                  <FormLabel label="Additional Notes" />
                  <textarea
                    value={device.additional_notes}
                    onChange={(e) => updateDevice(device._key, 'additional_notes', e.target.value)}
                    rows={2}
                    placeholder="Notes about the device condition, issue, etc."
                    className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500"
                  />
                </div>
              </div>
            ))}

            <button
              onClick={() => setDevices((prev) => [...prev, makeDevice()])}
              className="inline-flex items-center gap-2 rounded-lg border-2 border-dashed border-surface-300 px-4 py-2.5 text-sm font-medium text-surface-600 transition-colors hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:text-surface-400 dark:hover:border-primary-500 dark:hover:text-primary-400"
            >
              <Plus className="h-4 w-4" />
              Add Device
            </button>
          </div>
          {formErrors.devices && (
            <p className="mt-2 text-xs text-red-500">{formErrors.devices}</p>
          )}
        </Section>

        {/* ─── Step 3: Summary ───────────────────────────────────────── */}
        <Section title="Summary" step={3}>
          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <SelectInput
              label="Source"
              value={source}
              onChange={setSource}
              options={SOURCES.map((s) => ({ value: s, label: s }))}
            />
            <SelectInput
              label="Referred By"
              value={referredBy}
              onChange={setReferredBy}
              options={referralSources.map((r) => ({ value: r.name, label: r.name }))}
              placeholder="Select..."
            />
            <SelectInput
              label="Assigned To"
              value={assignedTo}
              onChange={setAssignedTo}
              options={users.map((u) => ({ value: String(u.id), label: `${u.first_name} ${u.last_name}` }))}
              placeholder="Unassigned"
            />
            <TextInput
              label="Labels"
              value={labels}
              onChange={setLabels}
              placeholder="e.g. urgent, vip (comma-separated)"
            />
            <div>
              <FormLabel label="Due Date" />
              <input
                type="date"
                value={dueDate}
                onChange={(e) => setDueDate(e.target.value)}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500"
              />
            </div>
          </div>

          {/* Totals */}
          <div className="mt-6 flex justify-end">
            <div className="w-full max-w-xs space-y-2">
              <div className="flex items-center justify-between text-sm">
                <span className="text-surface-500 dark:text-surface-400">Subtotal</span>
                <span className="font-medium text-surface-800 dark:text-surface-200">
                  ${subtotal.toFixed(2)}
                </span>
              </div>
              <div className="flex items-center justify-between text-sm">
                <span className="text-surface-500 dark:text-surface-400">Tax</span>
                <span className="font-medium text-surface-800 dark:text-surface-200">
                  ${tax.toFixed(2)}
                </span>
              </div>
              <div className="border-t border-surface-200 pt-2 dark:border-surface-700">
                <div className="flex items-center justify-between">
                  <span className="font-semibold text-surface-900 dark:text-surface-100">Total</span>
                  <span className="text-lg font-bold text-surface-900 dark:text-surface-100">
                    ${total.toFixed(2)}
                  </span>
                </div>
              </div>
            </div>
          </div>

          {/* Submit */}
          <div className="mt-6 flex items-center justify-end gap-3 border-t border-surface-200 pt-6 dark:border-surface-700">
            <button
              onClick={() => navigate('/tickets')}
              className="rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-medium text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmit}
              disabled={createTicketMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-2.5 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
            >
              {createTicketMut.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
              Create Ticket
            </button>
          </div>
        </Section>
      </div>
    </div>
  );
}
