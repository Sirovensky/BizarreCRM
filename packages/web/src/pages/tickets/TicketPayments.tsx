import { Link } from 'react-router-dom';
import { useMutation } from '@tanstack/react-query';
import {
  DollarSign, FileText, TrendingUp, ExternalLink, Loader2,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency, formatDate } from '@/utils/format';
import type { Ticket, TicketDevice } from '@bizarre-crm/shared';

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketPaymentsProps {
  ticket: Ticket;
  ticketId: number;
  devices: TicketDevice[];
  invoice: any;
  paidAmount: number;
  dueAmount: number;
  allParts: any[];
  totalCost: number;
  estimatedProfit: number;
  invalidateTicket: () => void;
  onNavigate: (path: string) => void;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketPayments({
  ticket,
  ticketId,
  devices,
  invoice,
  paidAmount,
  dueAmount,
  allParts,
  totalCost,
  estimatedProfit,
  invalidateTicket,
  onNavigate,
}: TicketPaymentsProps) {
  const updateDeviceMut = useMutation({
    mutationFn: ({ deviceId, data }: { deviceId: number; data: any }) =>
      ticketApi.updateDevice(deviceId, data),
    onSuccess: () => { toast.success('Device updated'); invalidateTicket(); },
    onError: () => toast.error('Failed to update device'),
  });

  const updatePartMut = useMutation({
    mutationFn: ({ partId, data }: { partId: number; data: any }) =>
      ticketApi.updatePart(partId, data),
    onSuccess: () => { toast.success('Part updated'); invalidateTicket(); },
    onError: () => toast.error('Failed to update part'),
  });

  const convertInvoiceMut = useMutation({
    mutationFn: () => ticketApi.convertToInvoice(ticketId),
    onSuccess: (res) => {
      const inv = res?.data?.data;
      toast.success('Invoice generated');
      invalidateTicket();
      if (inv?.id) onNavigate(`/invoices/${inv.id}`);
    },
    onError: () => toast.error('Failed to generate invoice'),
  });

  return (
    <>
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

          {/* Estimated Profit */}
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
                  invoice.status === 'paid' ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300'
                    : invoice.status === 'partial' ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300'
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
    </>
  );
}
