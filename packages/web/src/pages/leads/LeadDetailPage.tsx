import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Loader2, ArrowRightLeft, Pencil, Save, Phone, Mail,
  MapPin, User, Wrench, Calendar, X,
} from 'lucide-react';
import { useState } from 'react';
import toast from 'react-hot-toast';
import { leadApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { Breadcrumb } from '@/components/shared/Breadcrumb';

const STATUS_COLORS: Record<string, string> = {
  new: '#3b82f6',
  contacted: '#f59e0b',
  qualified: '#8b5cf6',
  converted: '#22c55e',
  lost: '#ef4444',
};

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatCurrency(amount: number) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount);
}

export function LeadDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [editingNotes, setEditingNotes] = useState(false);
  const [notes, setNotes] = useState('');
  const [editingStatus, setEditingStatus] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['lead', id],
    queryFn: () => leadApi.get(Number(id)),
  });

  const lead = data?.data?.data;

  const convertMut = useMutation({
    mutationFn: () => leadApi.convert(Number(id)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['lead', id] });
      toast.success('Converted to ticket');
      const ticketId = res.data?.data?.ticket_id;
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: () => toast.error('Failed to convert'),
  });

  const updateMut = useMutation({
    mutationFn: (d: any) => leadApi.update(Number(id), d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['lead', id] });
      setEditingNotes(false);
      setEditingStatus(false);
      toast.success('Lead updated');
    },
    onError: () => toast.error('Failed to update'),
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
      </div>
    );
  }

  if (isError || !lead) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <p className="text-lg font-medium text-surface-600 dark:text-surface-400">Lead not found</p>
        <Link to="/leads" className="mt-4 text-sm text-primary-600 hover:underline">Back to leads</Link>
      </div>
    );
  }

  const color = STATUS_COLORS[lead.status] || '#6b7280';
  const devices: any[] = lead.devices || [];
  const appointments: any[] = lead.appointments || [];
  const statuses = ['new', 'contacted', 'qualified', 'converted', 'lost'];

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Leads', href: '/leads' },
        { label: lead.order_id ? `Lead ${lead.order_id}` : `Lead #${id}` },
      ]} />
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/leads')} className="rounded-lg p-2 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                Lead {lead.order_id}
              </h1>
              {editingStatus ? (
                <div className="flex items-center gap-1">
                  {statuses.map((s) => (
                    <button
                      key={s}
                      onClick={() => updateMut.mutate({ status: s })}
                      className={cn(
                        'rounded-full px-2.5 py-0.5 text-xs font-medium capitalize transition-colors',
                        lead.status === s
                          ? 'ring-2 ring-offset-1 ring-primary-500'
                          : 'hover:opacity-80',
                      )}
                      style={{ backgroundColor: `${STATUS_COLORS[s] || '#6b7280'}18`, color: STATUS_COLORS[s] || '#6b7280' }}
                    >
                      {s}
                    </button>
                  ))}
                  <button onClick={() => setEditingStatus(false)} className="p-0.5 text-surface-400"><X className="h-3.5 w-3.5" /></button>
                </div>
              ) : (
                <button
                  onClick={() => setEditingStatus(true)}
                  className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
                  style={{ backgroundColor: `${color}18`, color }}
                >
                  <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                  {lead.status}
                </button>
              )}
            </div>
            <p className="text-sm text-surface-500">{lead.first_name} {lead.last_name} &middot; Created {formatDate(lead.created_at)}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {lead.status !== 'converted' && (
            <button
              onClick={() => { if (confirm('Convert this lead to a ticket? This will create a new ticket with the lead data.')) convertMut.mutate(); }}
              disabled={convertMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
            >
              <ArrowRightLeft className="h-4 w-4" />
              {convertMut.isPending ? 'Converting...' : 'Convert to Ticket'}
            </button>
          )}
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Contact info */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Contact Information</h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="flex items-center gap-2 text-sm">
                <User className="h-4 w-4 text-surface-400" />
                <span className="text-surface-900 dark:text-surface-100 font-medium">{lead.first_name} {lead.last_name}</span>
              </div>
              {lead.phone && (
                <div className="flex items-center gap-2 text-sm">
                  <Phone className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.phone}</span>
                </div>
              )}
              {lead.email && (
                <div className="flex items-center gap-2 text-sm">
                  <Mail className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.email}</span>
                </div>
              )}
              {(lead.address || lead.zip_code) && (
                <div className="flex items-center gap-2 text-sm">
                  <MapPin className="h-4 w-4 text-surface-400" />
                  <span className="text-surface-600 dark:text-surface-400">{lead.address}{lead.zip_code && ` ${lead.zip_code}`}</span>
                </div>
              )}
            </div>
          </div>

          {/* Devices/Services */}
          {devices.length > 0 && (
            <div className="card overflow-hidden">
              <div className="p-4 border-b border-surface-100 dark:border-surface-800">
                <h3 className="font-semibold text-surface-900 dark:text-surface-100 flex items-center gap-2">
                  <Wrench className="h-4 w-4" /> Devices / Services
                </h3>
              </div>
              <div className="divide-y divide-surface-100 dark:divide-surface-800">
                {devices.map((d: any) => (
                  <div key={d.id} className="px-4 py-3">
                    <div className="flex items-center justify-between">
                      <div>
                        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{d.device_name || 'Device'}</p>
                        {d.problem && <p className="text-xs text-surface-500 mt-0.5">{d.problem}</p>}
                        {d.customer_notes && <p className="text-xs text-surface-400 mt-0.5 italic">{d.customer_notes}</p>}
                      </div>
                      {d.price > 0 && (
                        <span className="text-sm font-medium text-surface-700 dark:text-surface-300">{formatCurrency(d.price)}</span>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {/* Notes */}
          <div className="card p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Notes</h3>
              {!editingNotes && (
                <button onClick={() => { setEditingNotes(true); setNotes(lead.notes || ''); }}
                  className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1">
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
            </div>
            {editingNotes ? (
              <div className="space-y-2">
                <textarea value={notes} onChange={(e) => setNotes(e.target.value)} rows={3}
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500/20" />
                <div className="flex gap-2">
                  <button onClick={() => updateMut.mutate({ notes })} disabled={updateMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50">
                    <Save className="h-3 w-3" /> Save
                  </button>
                  <button onClick={() => setEditingNotes(false)} className="text-xs text-surface-500">Cancel</button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-surface-600 dark:text-surface-400 whitespace-pre-wrap">
                {lead.notes || <span className="italic text-surface-400">No notes</span>}
              </p>
            )}
          </div>
        </div>

        {/* Sidebar */}
        <div className="space-y-6">
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Details</h3>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-surface-500">Created</dt>
                <dd className="text-surface-900 dark:text-surface-100">{formatDate(lead.created_at)}</dd>
              </div>
              {lead.source && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Source</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.source}</dd>
                </div>
              )}
              {lead.referred_by && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Referred By</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.referred_by}</dd>
                </div>
              )}
              {lead.assigned_first_name && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Assigned To</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{lead.assigned_first_name} {lead.assigned_last_name}</dd>
                </div>
              )}
              {lead.customer_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Customer</dt>
                  <dd>
                    <Link to={`/customers/${lead.customer_id}`} className="text-primary-600 hover:underline">
                      {lead.customer_first_name} {lead.customer_last_name}
                    </Link>
                  </dd>
                </div>
              )}
              {lead.ticket_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Ticket</dt>
                  <dd>
                    <Link to={`/tickets/${lead.ticket_id}`} className="text-primary-600 hover:underline">View Ticket</Link>
                  </dd>
                </div>
              )}
            </dl>
          </div>

          {/* Appointments */}
          {appointments.length > 0 && (
            <div className="card p-5">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3 flex items-center gap-2">
                <Calendar className="h-4 w-4" /> Appointments
              </h3>
              <div className="space-y-2">
                {appointments.map((a: any) => (
                  <div key={a.id} className="rounded-lg border border-surface-200 dark:border-surface-700 p-3 text-sm">
                    <p className="font-medium text-surface-900 dark:text-surface-100">{a.title}</p>
                    <p className="text-xs text-surface-500">
                      {new Date(a.start_time).toLocaleString('en-US', { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' })}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
