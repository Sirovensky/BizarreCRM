import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Loader2, Printer, ArrowRightLeft, Send, Pencil, Save, X,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { estimateApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { useState } from 'react';

const STATUS_COLORS: Record<string, string> = {
  draft: '#6b7280',
  sent: '#3b82f6',
  approved: '#22c55e',
  rejected: '#ef4444',
  converted: '#8b5cf6',
};

export function EstimateDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [notes, setNotes] = useState('');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['estimate', id],
    queryFn: () => estimateApi.get(Number(id)),
  });

  const estimate = data?.data?.data;

  const convertMut = useMutation({
    mutationFn: () => estimateApi.convert(Number(id)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      toast.success('Converted to ticket');
      const ticketId = res.data?.data?.ticket_id;
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: () => toast.error('Failed to convert'),
  });

  const updateMut = useMutation({
    mutationFn: (d: any) => estimateApi.update(Number(id), d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      setEditing(false);
      toast.success('Estimate updated');
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

  if (isError || !estimate) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <p className="text-lg font-medium text-surface-600 dark:text-surface-400">Estimate not found</p>
        <Link to="/estimates" className="mt-4 text-sm text-primary-600 hover:underline">Back to estimates</Link>
      </div>
    );
  }

  const color = STATUS_COLORS[estimate.status] || '#6b7280';
  const lineItems: any[] = estimate.line_items || [];

  return (
    <div>
      <Breadcrumb items={[
        { label: 'Estimates', href: '/estimates' },
        { label: estimate.order_id ? `EST-${estimate.order_id}` : `Estimate #${id}` },
      ]} />
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <button onClick={() => navigate('/estimates')} className="rounded-lg p-2 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div>
            <div className="flex items-center gap-3">
              <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
                Estimate {estimate.order_id}
              </h1>
              <span
                className="inline-flex items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
                style={{ backgroundColor: `${color}18`, color }}
              >
                <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                {estimate.status}
              </span>
            </div>
            <p className="text-sm text-surface-500">Created {formatDate(estimate.created_at)}</p>
          </div>
        </div>
        <div className="flex items-center gap-2">
          {estimate.status !== 'converted' && estimate.status !== 'rejected' && (
            <button
              onClick={async () => { if (await confirm('Convert this estimate to a ticket?')) convertMut.mutate(); }}
              disabled={convertMut.isPending}
              className="inline-flex items-center gap-2 rounded-lg border border-green-300 px-4 py-2 text-sm font-medium text-green-700 hover:bg-green-50 dark:border-green-700 dark:text-green-400 dark:hover:bg-green-950/30"
            >
              <ArrowRightLeft className="h-4 w-4" />
              Convert to Ticket
            </button>
          )}
          <button
            onClick={() => window.print()}
            className="inline-flex items-center gap-2 rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Printer className="h-4 w-4" />
            Print
          </button>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Customer info */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Customer</h3>
            {estimate.customer_first_name ? (
              <div>
                <p className="font-medium text-surface-900 dark:text-surface-100">
                  {estimate.customer_first_name} {estimate.customer_last_name}
                </p>
                {estimate.customer_email && <p className="text-sm text-surface-500">{estimate.customer_email}</p>}
                {(estimate.customer_phone || estimate.customer_mobile) && (
                  <p className="text-sm text-surface-500">{estimate.customer_mobile || estimate.customer_phone}</p>
                )}
                {estimate.address1 && (
                  <p className="text-sm text-surface-500 mt-1">
                    {estimate.address1}{estimate.city && `, ${estimate.city}`}{estimate.state && `, ${estimate.state}`} {estimate.postcode}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-sm text-surface-400 italic">No customer linked</p>
            )}
          </div>

          {/* Line items */}
          <div className="card overflow-hidden">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Line Items</h3>
            </div>
            {lineItems.length === 0 ? (
              <p className="p-4 text-sm text-surface-400">No line items</p>
            ) : (
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 dark:border-surface-800">
                    <th className="text-left px-4 py-3 font-medium text-surface-500">Item</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Qty</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Price</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Total</th>
                  </tr>
                </thead>
                <tbody>
                  {lineItems.map((li: any) => (
                    <tr key={li.id} className="border-b border-surface-50 dark:border-surface-800/50">
                      <td className="px-4 py-3">
                        <p className="font-medium text-surface-900 dark:text-surface-100">{li.item_name || li.description || li.name || 'Item'}</p>
                        {li.item_sku && <p className="text-xs text-surface-400">SKU: {li.item_sku}</p>}
                      </td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{li.quantity}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(li.unit_price ?? li.price ?? 0)}</td>
                      <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(li.total ?? li.quantity * (li.unit_price ?? li.price ?? 0))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          {/* Notes */}
          <div className="card p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Notes</h3>
              {!editing && (
                <button onClick={() => { setEditing(true); setNotes(estimate.notes || ''); }}
                  className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1">
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
            </div>
            {editing ? (
              <div className="space-y-2">
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500/20"
                />
                <div className="flex gap-2">
                  <button onClick={() => updateMut.mutate({ notes })} disabled={updateMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50">
                    <Save className="h-3 w-3" /> Save
                  </button>
                  <button onClick={() => setEditing(false)} className="text-xs text-surface-500 hover:text-surface-700">Cancel</button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-surface-600 dark:text-surface-400 whitespace-pre-wrap">
                {estimate.notes || <span className="italic text-surface-400">No notes</span>}
              </p>
            )}
          </div>
        </div>

        {/* Sidebar summary */}
        <div className="space-y-6">
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-4">Summary</h3>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-surface-500">Subtotal</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.subtotal)}</span>
              </div>
              {estimate.discount > 0 && (
                <div className="flex justify-between text-green-600">
                  <span>Discount</span>
                  <span>-{formatCurrency(estimate.discount)}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-surface-500">Tax</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.total_tax)}</span>
              </div>
              <div className="flex justify-between pt-2 border-t border-surface-200 dark:border-surface-700 font-bold text-base">
                <span className="text-surface-900 dark:text-surface-100">Total</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.total)}</span>
              </div>
            </div>
          </div>

          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Details</h3>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-surface-500">Created</dt>
                <dd className="text-surface-900 dark:text-surface-100">{formatDate(estimate.created_at)}</dd>
              </div>
              {estimate.valid_until && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Valid Until</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{formatDate(estimate.valid_until)}</dd>
                </div>
              )}
              {estimate.created_by_first_name && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Created By</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{estimate.created_by_first_name} {estimate.created_by_last_name}</dd>
                </div>
              )}
              {estimate.ticket_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Ticket</dt>
                  <dd>
                    <Link to={`/tickets/${estimate.ticket_id}`} className="text-primary-600 hover:underline">
                      View Ticket
                    </Link>
                  </dd>
                </div>
              )}
            </dl>
          </div>
        </div>
      </div>
    </div>
  );
}
