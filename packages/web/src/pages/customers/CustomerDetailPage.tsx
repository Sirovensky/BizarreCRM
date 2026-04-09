import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft,
  Pencil,
  Trash2,
  Save,
  Loader2,
  Ticket,
  FileText,
  MessageSquare,
  Monitor,
  User,
  Plus,
  X,
  AlertCircle,
  DollarSign,
  TrendingUp,
  Calendar,
  ShoppingCart,
  Shield,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { customerApi, smsApi } from '@/api/endpoints';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatPhoneAsYouType, stripPhone } from '@/utils/phoneFormat';
import { CopyButton } from '@/components/shared/CopyButton';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { BackButton } from '@/components/shared/BackButton';
import type {
  Customer,
  UpdateCustomerInput,
  CustomerAsset,
} from '@bizarre-crm/shared';

/** Safely parse tags which may be an array, a JSON string, or a plain string */
function parseTags(tags: unknown): string[] {
  if (Array.isArray(tags)) return tags;
  if (typeof tags === 'string') {
    try { const p = JSON.parse(tags); if (Array.isArray(p)) return p; } catch { /* not JSON */ }
    return tags ? [tags] : [];
  }
  return [];
}

type TabId = 'info' | 'tickets' | 'invoices' | 'communications' | 'assets';

const tabs: { id: TabId; label: string; icon: typeof User }[] = [
  { id: 'info', label: 'Info', icon: User },
  { id: 'tickets', label: 'Tickets', icon: Ticket },
  { id: 'invoices', label: 'Invoices', icon: FileText },
  { id: 'communications', label: 'Communications', icon: MessageSquare },
  { id: 'assets', label: 'Assets', icon: Monitor },
];

export function CustomerDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const customerId = Number(id);
  const isValidId = id != null && !isNaN(customerId) && customerId > 0;

  const [activeTab, setActiveTab] = useState<TabId>('info');

  // Fetch customer
  const {
    data: customerRes,
    isLoading,
    isError,
  } = useQuery({
    queryKey: ['customer', customerId],
    queryFn: () => customerApi.get(customerId),
    enabled: isValidId,
  });

  const customer: Customer | undefined = customerRes?.data?.data;

  // Track recent views
  useEffect(() => {
    if (!customer) return;
    const key = 'recent_views';
    try {
      const existing: { type: string; id: number; label: string; path: string }[] = JSON.parse(localStorage.getItem(key) || '[]');
      const label = `${customer.first_name} ${customer.last_name}`.trim();
      const entry = { type: 'customer', id: customer.id, label, path: `/customers/${customer.id}` };
      const filtered = existing.filter((e) => !(e.type === 'customer' && e.id === customer.id));
      filtered.unshift(entry);
      localStorage.setItem(key, JSON.stringify(filtered.slice(0, 5)));
    } catch { /* ignore */ }
  }, [customer?.id]);

  // Delete mutation
  const deleteMutation = useMutation({
    mutationFn: () => customerApi.delete(customerId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['customer', customerId] });
      toast.success('Customer deleted');
      navigate('/customers');
    },
    onError: () => toast.error('Failed to delete customer'),
  });

  const [showDeleteConfirm, setShowDeleteConfirm] = useState(false);

  const handleDelete = () => {
    if (!customer) return;
    setShowDeleteConfirm(true);
  };

  if (isLoading) {
    return <DetailSkeleton />;
  }

  if (!isValidId || isError || !customer) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-16 w-16 text-red-400 mb-4" />
        <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
          {!isValidId ? 'Invalid Customer ID' : 'Customer not found'}
        </h2>
        <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
          {!isValidId
            ? 'The URL contains an invalid customer ID.'
            : 'The customer you are looking for does not exist or has been deleted.'}
        </p>
        <Link
          to="/customers"
          className="mt-4 inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium text-sm transition-colors"
        >
          <ArrowLeft className="h-4 w-4" />
          Back to Customers
        </Link>
      </div>
    );
  }

  const fullName = `${customer.first_name} ${customer.last_name}`.trim();

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Customers', href: '/customers' },
        { label: fullName || 'Customer' },
      ]} />
      {/* Header */}
      <div className="mb-6 flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
        <div className="flex items-center gap-4">
          <BackButton to="/customers" />
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                {fullName}
              </h1>
              {customer.code && (
                <span className="px-2.5 py-0.5 rounded-full text-xs font-mono font-medium bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400">
                  {customer.code}
                </span>
              )}
            </div>
            <p className="text-surface-500 dark:text-surface-400 text-sm">
              {customer.type === 'business' ? 'Business' : 'Individual'}
              {customer.organization && ` \u00b7 ${customer.organization}`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          <button
            onClick={() => navigate(`/pos?customer=${customerId}`)}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-semibold text-white bg-green-600 rounded-lg hover:bg-green-700 transition-colors shadow-sm"
          >
            <ShoppingCart className="h-4 w-4" />
            New Ticket
          </button>
          <button
            onClick={handleDelete}
            disabled={deleteMutation.isPending}
            className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-red-600 dark:text-red-400 border border-red-200 dark:border-red-800 rounded-lg hover:bg-red-50 dark:hover:bg-red-900/20 transition-colors"
          >
            <Trash2 className="h-4 w-4" />
            Delete
          </button>
        </div>
      </div>

      {/* Tabs */}
      <div className="border-b border-surface-200 dark:border-surface-700 mb-6">
        <div className="flex gap-1 -mb-px">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            return (
              <button
                key={tab.id}
                onClick={() => setActiveTab(tab.id)}
                className={cn(
                  'inline-flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors',
                  activeTab === tab.id
                    ? 'border-primary-500 text-primary-600 dark:text-primary-400'
                    : 'border-transparent text-surface-500 hover:text-surface-700 dark:hover:text-surface-300 hover:border-surface-300 dark:hover:border-surface-600',
                )}
              >
                <Icon className="h-4 w-4" />
                {tab.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Customer analytics cards */}
      <CustomerAnalyticsBar customerId={customerId} />

      {/* Tab content */}
      {activeTab === 'info' && (
        <InfoTab customer={customer} customerId={customerId} />
      )}
      {activeTab === 'tickets' && <TicketsTab customerId={customerId} />}
      {activeTab === 'invoices' && <InvoicesTab customerId={customerId} />}
      {activeTab === 'communications' && <CommunicationsTab phone={customer.mobile || customer.phone} />}
      {activeTab === 'assets' && <AssetsTab customerId={customerId} />}

      <ConfirmDialog
        open={showDeleteConfirm}
        title="Delete Customer"
        message={`Are you sure you want to delete "${customer ? `${customer.first_name} ${customer.last_name}`.trim() : ''}"? This action cannot be undone.`}
        confirmLabel="Delete"
        danger
        requireTyping
        confirmText={customer ? `${customer.first_name} ${customer.last_name}`.trim() : ''}
        onConfirm={() => { setShowDeleteConfirm(false); deleteMutation.mutate(); }}
        onCancel={() => setShowDeleteConfirm(false)}
      />
    </div>
  );
}

// ==================== Customer Analytics Bar ====================

function CustomerAnalyticsBar({ customerId }: { customerId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-analytics', customerId],
    queryFn: () => customerApi.analytics(customerId),
    enabled: !!customerId,
    staleTime: 60_000,
  });

  const analytics = data?.data?.data;
  if (isLoading || !analytics) return null;

  const formatCurrency = (amount: number) =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);

  const cards = [
    {
      label: 'Lifetime Value',
      value: formatCurrency(analytics.lifetime_value || 0),
      icon: DollarSign,
      color: 'text-green-600 bg-green-50 dark:text-green-400 dark:bg-green-900/20',
    },
    {
      label: 'Total Tickets',
      value: analytics.total_tickets || 0,
      icon: Ticket,
      color: 'text-blue-600 bg-blue-50 dark:text-blue-400 dark:bg-blue-900/20',
    },
    {
      label: 'Avg Ticket',
      value: formatCurrency(analytics.avg_ticket_value || 0),
      icon: TrendingUp,
      color: 'text-purple-600 bg-purple-50 dark:text-purple-400 dark:bg-purple-900/20',
    },
    {
      label: 'Last Visit',
      value: analytics.days_since_last_visit != null
        ? analytics.days_since_last_visit === 0
          ? 'Today'
          : `${analytics.days_since_last_visit}d ago`
        : 'Never',
      icon: Calendar,
      color: 'text-amber-600 bg-amber-50 dark:text-amber-400 dark:bg-amber-900/20',
    },
  ];

  return (
    <div className="grid grid-cols-2 sm:grid-cols-4 gap-3 mb-6">
      {cards.map((card) => {
        const Icon = card.icon;
        return (
          <div key={card.label} className="rounded-xl border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 p-3">
            <div className="flex items-center gap-2.5">
              <div className={`flex h-8 w-8 items-center justify-center rounded-lg ${card.color}`}>
                <Icon className="h-4 w-4" />
              </div>
              <div>
                <p className="text-xs text-surface-500 dark:text-surface-400">{card.label}</p>
                <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{card.value}</p>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ==================== Info Tab ====================

function InfoTab({
  customer,
  customerId,
}: {
  customer: Customer;
  customerId: number;
}) {
  const queryClient = useQueryClient();

  const [form, setForm] = useState({
    first_name: customer.first_name || '',
    last_name: customer.last_name || '',
    type: customer.type || 'individual',
    organization: customer.organization || '',
    email: customer.email || '',
    phone: customer.phone || '',
    mobile: customer.mobile || '',
    address1: customer.address1 || '',
    address2: customer.address2 || '',
    city: customer.city || '',
    state: customer.state || '',
    postcode: customer.postcode || '',
    country: customer.country || 'US',
    referred_by: customer.referred_by || '',
    comments: customer.comments || '',
    tags: parseTags(customer.tags).join(', '),
    email_opt_in: customer.email_opt_in,
    sms_opt_in: customer.sms_opt_in,
    tax_number: customer.tax_number || '',
  });

  // Reset form when customer changes
  useEffect(() => {
    setForm({
      first_name: customer.first_name || '',
      last_name: customer.last_name || '',
      type: customer.type || 'individual',
      organization: customer.organization || '',
      email: customer.email || '',
      phone: customer.phone || '',
      mobile: customer.mobile || '',
      address1: customer.address1 || '',
      address2: customer.address2 || '',
      city: customer.city || '',
      state: customer.state || '',
      postcode: customer.postcode || '',
      country: customer.country || 'US',
      referred_by: customer.referred_by || '',
      comments: customer.comments || '',
      tags: parseTags(customer.tags).join(', '),
      email_opt_in: customer.email_opt_in,
      sms_opt_in: customer.sms_opt_in,
      tax_number: customer.tax_number || '',
    });
  }, [customer]);

  const updateMutation = useMutation({
    mutationFn: (data: UpdateCustomerInput) =>
      customerApi.update(customerId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['customer', customerId] });
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      toast.success('Customer updated');
    },
    onError: () => toast.error('Failed to update customer'),
  });

  const updateField = (key: string, value: any) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const handleSave = () => {
    if (!form.first_name.trim()) {
      toast.error('First name is required');
      return;
    }

    const payload: UpdateCustomerInput = {
      first_name: form.first_name.trim(),
      last_name: form.last_name.trim() || undefined,
      type: form.type as 'individual' | 'business',
      organization: form.organization.trim() || undefined,
      email: form.email.trim() || undefined,
      phone: stripPhone(form.phone) || undefined,
      mobile: stripPhone(form.mobile) || undefined,
      address1: form.address1.trim() || undefined,
      address2: form.address2.trim() || undefined,
      city: form.city.trim() || undefined,
      state: form.state.trim() || undefined,
      postcode: form.postcode.trim() || undefined,
      country: form.country.trim() || undefined,
      referred_by: form.referred_by.trim() || undefined,
      comments: form.comments.trim() || undefined,
      tax_number: form.tax_number.trim() || undefined,
      tags: form.tags
        .split(',')
        .map((t) => t.trim())
        .filter(Boolean),
      email_opt_in: form.email_opt_in,
      sms_opt_in: form.sms_opt_in,
    };

    updateMutation.mutate(payload);
  };

  return (
    <div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Basic Info */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Basic Information
          </h3>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="First Name" required>
                <input
                  type="text"
                  value={form.first_name}
                  onChange={(e) => updateField('first_name', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="Last Name">
                <input
                  type="text"
                  value={form.last_name}
                  onChange={(e) => updateField('last_name', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
            <FieldBlock label="Type">
              <select
                value={form.type}
                onChange={(e) => updateField('type', e.target.value)}
                className="input"
              >
                <option value="individual">Individual</option>
                <option value="business">Business</option>
              </select>
            </FieldBlock>
            <FieldBlock label="Organization">
              <input
                type="text"
                value={form.organization}
                onChange={(e) => updateField('organization', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Tax Number">
              <input
                type="text"
                value={form.tax_number}
                onChange={(e) => updateField('tax_number', e.target.value)}
                className="input"
              />
            </FieldBlock>
          </div>
        </div>

        {/* Contact */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Contact Information
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Email">
              <input
                type="email"
                value={form.email}
                onChange={(e) => updateField('email', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Phone">
              <div className="flex items-center gap-1">
                <input
                  type="tel"
                  value={form.phone}
                  onChange={(e) => updateField('phone', formatPhoneAsYouType(e.target.value))}
                  className="input flex-1"
                />
                {form.phone && <CopyButton text={stripPhone(form.phone)} />}
              </div>
            </FieldBlock>
            <FieldBlock label="Mobile">
              <div className="flex items-center gap-1">
                <input
                  type="tel"
                  value={form.mobile}
                  onChange={(e) => updateField('mobile', formatPhoneAsYouType(e.target.value))}
                  className="input flex-1"
                />
                {form.mobile && <CopyButton text={stripPhone(form.mobile)} />}
              </div>
            </FieldBlock>

            {/* Phone list from API */}
            {customer.phones && customer.phones.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Additional Phones
                </label>
                <div className="space-y-1">
                  {customer.phones.map((p) => (
                    <div
                      key={p.id}
                      className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400"
                    >
                      <span className="px-1.5 py-0.5 rounded text-xs bg-surface-100 dark:bg-surface-700 text-surface-500 dark:text-surface-400">
                        {p.label}
                      </span>
                      <span>{p.phone}</span>
                      {p.is_primary && (
                        <span className="text-xs text-primary-600 dark:text-primary-400">
                          Primary
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}

            {/* Email list from API */}
            {customer.emails && customer.emails.length > 0 && (
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                  Additional Emails
                </label>
                <div className="space-y-1">
                  {customer.emails.map((em) => (
                    <div
                      key={em.id}
                      className="flex items-center gap-2 text-sm text-surface-600 dark:text-surface-400"
                    >
                      <span className="px-1.5 py-0.5 rounded text-xs bg-surface-100 dark:bg-surface-700 text-surface-500 dark:text-surface-400">
                        {em.label}
                      </span>
                      <span>{em.email}</span>
                      {em.is_primary && (
                        <span className="text-xs text-primary-600 dark:text-primary-400">
                          Primary
                        </span>
                      )}
                    </div>
                  ))}
                </div>
              </div>
            )}
          </div>
        </div>

        {/* Address */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Address
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Address Line 1">
              <input
                type="text"
                value={form.address1}
                onChange={(e) => updateField('address1', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Address Line 2">
              <input
                type="text"
                value={form.address2}
                onChange={(e) => updateField('address2', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="City">
                <input
                  type="text"
                  value={form.city}
                  onChange={(e) => updateField('city', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="State">
                <input
                  type="text"
                  value={form.state}
                  onChange={(e) => updateField('state', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <FieldBlock label="Postcode">
                <input
                  type="text"
                  value={form.postcode}
                  onChange={(e) => updateField('postcode', e.target.value)}
                  className="input"
                />
              </FieldBlock>
              <FieldBlock label="Country">
                <input
                  type="text"
                  value={form.country}
                  onChange={(e) => updateField('country', e.target.value)}
                  className="input"
                />
              </FieldBlock>
            </div>
          </div>
        </div>

        {/* Additional */}
        <div className="card p-6">
          <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">
            Additional Information
          </h3>
          <div className="space-y-4">
            <FieldBlock label="Referred By">
              <input
                type="text"
                value={form.referred_by}
                onChange={(e) => updateField('referred_by', e.target.value)}
                className="input"
              />
            </FieldBlock>
            <FieldBlock label="Tags">
              <input
                type="text"
                value={form.tags}
                onChange={(e) => updateField('tags', e.target.value)}
                className="input"
                placeholder="Comma separated tags"
              />
            </FieldBlock>
            <FieldBlock label="Comments">
              <textarea
                value={form.comments}
                onChange={(e) => updateField('comments', e.target.value)}
                className="input min-h-[80px] resize-y"
                rows={3}
              />
            </FieldBlock>
            <div className="flex items-center gap-6 pt-2">
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={form.email_opt_in}
                  onChange={(e) => updateField('email_opt_in', e.target.checked)}
                  className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-sm text-surface-700 dark:text-surface-300">
                  Email opt-in
                </span>
              </label>
              <label className="flex items-center gap-2 cursor-pointer">
                <input
                  type="checkbox"
                  checked={form.sms_opt_in}
                  onChange={(e) => updateField('sms_opt_in', e.target.checked)}
                  className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-sm text-surface-700 dark:text-surface-300">
                  SMS opt-in
                </span>
              </label>
            </div>
          </div>
        </div>
      </div>

      {/* Save */}
      <div className="mt-6 flex justify-end">
        <button
          onClick={handleSave}
          disabled={updateMutation.isPending}
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors shadow-sm disabled:opacity-60 disabled:cursor-not-allowed"
        >
          {updateMutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          {updateMutation.isPending ? 'Saving...' : 'Save Changes'}
        </button>
      </div>
    </div>
  );
}

// ==================== Tickets Tab ====================

function TicketsTab({ customerId }: { customerId: number }) {
  const navigate = useNavigate();
  const { data, isLoading } = useQuery({
    queryKey: ['customer-tickets', customerId],
    queryFn: () => customerApi.getTickets(customerId),
  });

  const tickets = data?.data?.data?.tickets || [];

  if (isLoading) {
    return <TabSkeleton />;
  }

  if (tickets.length === 0) {
    return (
      <EmptyTabState
        icon={Ticket}
        title="No tickets"
        description="This customer has no repair tickets yet."
      />
    );
  }

  // Sort by created_at descending (newest first)
  const sorted = [...tickets].sort((a: any, b: any) =>
    new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  );

  return (
    <div className="card p-6">
      <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-4 flex items-center gap-2">
        <Ticket className="h-4 w-4" />
        Repair History
      </h3>
      <div className="relative">
        {/* Vertical timeline line */}
        <div className="absolute left-[9px] top-2 bottom-2 w-0.5 bg-surface-200 dark:bg-surface-700" />

        <div className="space-y-0">
          {sorted.map((ticket: any, idx: number) => {
            const statusColor = ticket.status?.color || '#6b7280';
            const deviceName = ticket.devices?.[0]?.device_name || 'Unknown device';
            const serviceName = ticket.devices?.[0]?.service_name || ticket.devices?.[0]?.issue || '';
            const isLast = idx === sorted.length - 1;

            return (
              <div
                key={ticket.id}
                className="relative flex gap-4 group cursor-pointer"
                onClick={() => navigate(`/tickets/${ticket.id}`)}
              >
                {/* Timeline dot */}
                <div className="relative z-10 flex-shrink-0 mt-3">
                  <div
                    className="h-[18px] w-[18px] rounded-full border-[3px] border-white dark:border-surface-900 group-hover:scale-110 transition-transform"
                    style={{ backgroundColor: statusColor }}
                  />
                </div>

                {/* Content card */}
                <div className={cn(
                  'flex-1 rounded-lg p-3 hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors',
                  !isLast && 'mb-1',
                )}>
                  <div className="flex items-start justify-between gap-2">
                    <div className="min-w-0">
                      <div className="flex items-center gap-2 flex-wrap">
                        <span className="text-sm font-mono font-medium text-surface-700 dark:text-surface-300">
                          T-{String(ticket.order_id || ticket.id).replace('T-', '')}
                        </span>
                        <StatusBadge
                          label={ticket.status?.name || 'Unknown'}
                          color={ticket.status?.color}
                        />
                      </div>
                      <p className="text-sm text-surface-800 dark:text-surface-200 mt-0.5">
                        {deviceName}
                      </p>
                      {serviceName && (
                        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5 truncate">
                          {serviceName}
                        </p>
                      )}
                    </div>
                    <div className="text-right flex-shrink-0">
                      <span className="text-sm font-medium text-surface-700 dark:text-surface-300">
                        ${Number(ticket.total || 0).toFixed(2)}
                      </span>
                      <p className="text-xs text-surface-400 dark:text-surface-500 mt-0.5">
                        {new Date(ticket.created_at).toLocaleDateString('en-US', {
                          month: 'short',
                          day: 'numeric',
                          year: 'numeric',
                        })}
                      </p>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </div>
  );
}

// ==================== Invoices Tab ====================

function InvoicesTab({ customerId }: { customerId: number }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-invoices', customerId],
    queryFn: () => customerApi.getInvoices(customerId),
  });

  const invoices = data?.data?.data?.invoices || [];

  if (isLoading) {
    return <TabSkeleton />;
  }

  if (invoices.length === 0) {
    return (
      <EmptyTabState
        icon={FileText}
        title="No invoices"
        description="This customer has no invoices yet."
      />
    );
  }

  const statusColors: Record<string, string> = {
    paid: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
    unpaid:
      'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
    partial:
      'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
    refunded:
      'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
    void: 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
  };

  return (
    <div className="card overflow-hidden">
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead>
            <tr className="border-b border-surface-200 dark:border-surface-700">
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">ID</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Status</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Total</th>
              <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Paid</th>
              <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Date</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
            {invoices.map((inv: any) => (
              <tr
                key={inv.id}
                className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
              >
                <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                  #{inv.order_id || inv.id}
                </td>
                <td className="px-4 py-3 text-sm">
                  <span
                    className={cn(
                      'badge',
                      statusColors[inv.status] || statusColors.unpaid,
                    )}
                  >
                    {inv.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-sm text-right font-medium text-surface-700 dark:text-surface-300">
                  ${Number(inv.total || 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-sm text-right text-surface-600 dark:text-surface-400">
                  ${Number(inv.amount_paid || 0).toFixed(2)}
                </td>
                <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400">
                  {new Date(inv.created_at).toLocaleDateString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

// ==================== Communications Tab ====================

function CommunicationsTab({ phone }: { phone?: string | null }) {
  const { data, isLoading } = useQuery({
    queryKey: ['customer-sms', phone],
    queryFn: () => smsApi.messages(phone!),
    enabled: !!phone,
  });
  const messages: any[] = data?.data?.data?.messages || data?.data?.data || [];

  if (!phone) {
    return <EmptyTabState icon={MessageSquare} title="No Phone Number" description="Add a phone number to this customer to view SMS history." />;
  }

  if (isLoading) {
    return <div className="flex items-center justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400" /></div>;
  }

  if (messages.length === 0) {
    return <EmptyTabState icon={MessageSquare} title="No Messages" description="No SMS messages found for this customer." />;
  }

  return (
    <div className="space-y-2 max-h-96 overflow-y-auto">
      {messages.map((msg: any, i: number) => (
        <div key={msg.id || i} className={cn('flex', msg.direction === 'outbound' ? 'justify-end' : 'justify-start')}>
          <div className={cn(
            'max-w-[75%] rounded-lg px-3 py-2 text-sm',
            msg.direction === 'outbound'
              ? 'bg-primary-600 text-white rounded-br-none'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-900 dark:text-surface-100 rounded-bl-none'
          )}>
            <p>{msg.message || msg.content}</p>
            <p className={cn('text-[10px] mt-1', msg.direction === 'outbound' ? 'text-primary-200' : 'text-surface-400')}>
              {msg.date_time ? new Date(msg.date_time).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : ''}
            </p>
          </div>
        </div>
      ))}
    </div>
  );
}

// ==================== Assets Tab ====================

function AssetsTab({ customerId }: { customerId: number }) {
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editingAsset, setEditingAsset] = useState<CustomerAsset | null>(null);
  const [assetForm, setAssetForm] = useState({
    name: '',
    device_type: '',
    serial: '',
    imei: '',
    color: '',
    notes: '',
  });

  const { data, isLoading } = useQuery({
    queryKey: ['customer-assets', customerId],
    queryFn: () => customerApi.getAssets(customerId),
  });

  const assets: CustomerAsset[] = (() => {
    const d = data?.data?.data;
    return Array.isArray(d) ? d : d?.assets || [];
  })();

  const addMutation = useMutation({
    mutationFn: (assetData: Partial<CustomerAsset>) =>
      customerApi.addAsset(customerId, assetData),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset added');
      resetForm();
    },
    onError: () => toast.error('Failed to add asset'),
  });

  const updateAssetMutation = useMutation({
    mutationFn: ({
      assetId,
      data,
    }: {
      assetId: number;
      data: Partial<CustomerAsset>;
    }) => customerApi.updateAsset(assetId, data),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset updated');
      resetForm();
    },
    onError: () => toast.error('Failed to update asset'),
  });

  const deleteAssetMutation = useMutation({
    mutationFn: (assetId: number) => customerApi.deleteAsset(assetId),
    onSuccess: () => {
      queryClient.invalidateQueries({
        queryKey: ['customer-assets', customerId],
      });
      toast.success('Asset deleted');
    },
    onError: () => toast.error('Failed to delete asset'),
  });

  const resetForm = () => {
    setShowForm(false);
    setEditingAsset(null);
    setAssetForm({
      name: '',
      device_type: '',
      serial: '',
      imei: '',
      color: '',
      notes: '',
    });
  };

  const startEdit = (asset: CustomerAsset) => {
    setEditingAsset(asset);
    setAssetForm({
      name: asset.name || '',
      device_type: asset.device_type || '',
      serial: asset.serial || '',
      imei: asset.imei || '',
      color: asset.color || '',
      notes: asset.notes || '',
    });
    setShowForm(true);
  };

  const handleSubmitAsset = () => {
    if (!assetForm.name.trim()) {
      toast.error('Asset name is required');
      return;
    }

    const payload: Partial<CustomerAsset> = {
      name: assetForm.name.trim(),
      device_type: assetForm.device_type.trim() || null,
      serial: assetForm.serial.trim() || null,
      imei: assetForm.imei.trim() || null,
      color: assetForm.color.trim() || null,
      notes: assetForm.notes.trim() || null,
    };

    if (editingAsset) {
      updateAssetMutation.mutate({ assetId: editingAsset.id, data: payload });
    } else {
      addMutation.mutate(payload);
    }
  };

  const handleDeleteAsset = async (asset: CustomerAsset) => {
    if (
      await confirm(
        `Delete asset "${asset.name}"? This action cannot be undone.`,
        { danger: true },
      )
    ) {
      deleteAssetMutation.mutate(asset.id);
    }
  };

  if (isLoading) {
    return <TabSkeleton />;
  }

  return (
    <div>
      {/* Add button */}
      <div className="flex justify-end mb-4">
        <button
          onClick={() => {
            resetForm();
            setShowForm(true);
          }}
          className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-lg transition-colors shadow-sm"
        >
          <Plus className="h-4 w-4" />
          Add Asset
        </button>
      </div>

      {/* Inline Form */}
      {showForm && (
        <div className="card p-4 mb-4">
          <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">
            {editingAsset ? 'Edit Asset' : 'New Asset'}
          </h4>
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3">
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Name <span className="text-red-500">*</span>
              </label>
              <input
                type="text"
                value={assetForm.name}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, name: e.target.value }))
                }
                className="input"
                placeholder="iPhone 15 Pro"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Type
              </label>
              <input
                type="text"
                value={assetForm.device_type}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, device_type: e.target.value }))
                }
                className="input"
                placeholder="Phone, Laptop, etc."
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Serial
              </label>
              <input
                type="text"
                value={assetForm.serial}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, serial: e.target.value }))
                }
                className="input"
                placeholder="Serial number"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                IMEI
              </label>
              <input
                type="text"
                value={assetForm.imei}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, imei: e.target.value }))
                }
                className="input"
                placeholder="IMEI number"
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Color
              </label>
              <input
                type="text"
                value={assetForm.color}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, color: e.target.value }))
                }
                className="input"
                placeholder="Black, Silver, etc."
              />
            </div>
            <div>
              <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
                Notes
              </label>
              <input
                type="text"
                value={assetForm.notes}
                onChange={(e) =>
                  setAssetForm((f) => ({ ...f, notes: e.target.value }))
                }
                className="input"
                placeholder="Additional notes"
              />
            </div>
          </div>
          <div className="flex items-center justify-end gap-2 mt-3">
            <button
              onClick={resetForm}
              className="px-3 py-1.5 text-sm text-surface-600 dark:text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800 rounded-md transition-colors"
            >
              Cancel
            </button>
            <button
              onClick={handleSubmitAsset}
              disabled={addMutation.isPending || updateAssetMutation.isPending}
              className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium text-white bg-primary-600 hover:bg-primary-700 rounded-md transition-colors disabled:opacity-60"
            >
              {(addMutation.isPending || updateAssetMutation.isPending) && (
                <Loader2 className="h-3.5 w-3.5 animate-spin" />
              )}
              {editingAsset ? 'Update' : 'Add'}
            </button>
          </div>
        </div>
      )}

      {/* Assets table */}
      {assets.length === 0 && !showForm ? (
        <EmptyTabState
          icon={Monitor}
          title="No assets"
          description="No devices or assets registered for this customer."
        />
      ) : assets.length > 0 ? (
        <div className="card overflow-hidden">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead>
                <tr className="border-b border-surface-200 dark:border-surface-700">
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Name</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Type</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Serial</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">IMEI</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Color</th>
                  <th className="px-4 py-3 text-left text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Notes</th>
                  <th className="px-4 py-3 text-right text-xs font-semibold uppercase tracking-wider text-surface-500 dark:text-surface-400 bg-surface-50 dark:bg-surface-800/50">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-700/50">
                {assets.map((asset) => (
                  <tr
                    key={asset.id}
                    className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors"
                  >
                    <td className="px-4 py-3 text-sm font-medium text-surface-900 dark:text-surface-100">
                      {asset.name}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-600 dark:text-surface-400">
                      {asset.device_type || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                      {asset.serial || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm font-mono text-surface-600 dark:text-surface-400">
                      {asset.imei || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-600 dark:text-surface-400">
                      {asset.color || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-surface-500 dark:text-surface-400 max-w-[200px] truncate">
                      {asset.notes || '—'}
                    </td>
                    <td className="px-4 py-3 text-sm text-right">
                      <div className="flex items-center justify-end gap-1">
                        <button
                          onClick={() => startEdit(asset)}
                          className="p-1.5 rounded-md text-surface-400 hover:text-amber-600 hover:bg-amber-50 dark:hover:text-amber-400 dark:hover:bg-amber-900/20 transition-colors"
                          title="Edit"
                        >
                          <Pencil className="h-4 w-4" />
                        </button>
                        <button
                          onClick={() => handleDeleteAsset(asset)}
                          className="p-1.5 rounded-md text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:text-red-400 dark:hover:bg-red-900/20 transition-colors"
                          title="Delete"
                        >
                          <Trash2 className="h-4 w-4" />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ) : null}
    </div>
  );
}

// ==================== Shared Components ====================

function FieldBlock({
  label,
  required,
  children,
}: {
  label: string;
  required?: boolean;
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
        {label}
        {required && <span className="text-red-500 ml-0.5">*</span>}
      </label>
      {children}
    </div>
  );
}

function StatusBadge({ label, color }: { label: string; color?: string }) {
  return (
    <span
      className="badge"
      style={
        color
          ? {
              backgroundColor: `${color}20`,
              color: color,
            }
          : undefined
      }
    >
      {label}
    </span>
  );
}

function EmptyTabState({
  icon: Icon,
  title,
  description,
}: {
  icon: typeof User;
  title: string;
  description: string;
}) {
  return (
    <div className="card flex flex-col items-center justify-center py-16">
      <Icon className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-3" />
      <h3 className="text-base font-medium text-surface-600 dark:text-surface-400">
        {title}
      </h3>
      <p className="text-sm text-surface-400 dark:text-surface-500 mt-1">
        {description}
      </p>
    </div>
  );
}

function TabSkeleton() {
  return (
    <div className="card p-6 animate-pulse">
      <div className="space-y-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="flex gap-4">
            <div className="h-4 w-16 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-24 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" />
            <div className="h-4 w-20 rounded bg-surface-200 dark:bg-surface-700" />
          </div>
        ))}
      </div>
    </div>
  );
}

function DetailSkeleton() {
  return (
    <div className="animate-pulse">
      <div className="mb-6 flex items-center gap-4">
        <div className="h-10 w-10 rounded-lg bg-surface-200 dark:bg-surface-700" />
        <div>
          <div className="h-7 w-48 rounded bg-surface-200 dark:bg-surface-700 mb-2" />
          <div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" />
        </div>
      </div>
      <div className="flex gap-4 mb-6 border-b border-surface-200 dark:border-surface-700 pb-3">
        {Array.from({ length: 5 }).map((_, i) => (
          <div
            key={i}
            className="h-5 w-20 rounded bg-surface-200 dark:bg-surface-700"
          />
        ))}
      </div>
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="card p-6">
            <div className="h-5 w-32 rounded bg-surface-200 dark:bg-surface-700 mb-4" />
            <div className="space-y-3">
              {Array.from({ length: 3 }).map((_, j) => (
                <div key={j} className="h-9 rounded bg-surface-100 dark:bg-surface-700/50" />
              ))}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
