import { useState, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useMutation } from '@tanstack/react-query';
import {
  User, Phone, Mail, Tag, MessageSquare, CheckCircle2,
  Receipt, ExternalLink, Calendar,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { ticketApi, voiceApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { cn } from '@/utils/cn';
import { formatDate, formatDateTime, formatPhone } from '@/utils/format';
import type { Ticket, TicketDevice } from '@bizarre-crm/shared';

// ─── Phone Action Row ───────────────────────────────────────────────

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

// ─── Props ──────────────────────────────────────────────────────────

export interface TicketSidebarProps {
  ticket: Ticket;
  ticketId: number;
  devices: TicketDevice[];
  employees: any[];
  onShowSms: () => void;
  invalidateTicket: () => void;
}

// ─── Main Export ────────────────────────────────────────────────────

export function TicketSidebar({
  ticket,
  ticketId,
  devices,
  employees,
  onShowSms,
  invalidateTicket,
}: TicketSidebarProps) {
  const currentUser = useAuthStore((s) => s.user);
  const customer = ticket?.customer;
  const assigned = ticket?.assigned_user;
  const [showAssignDropdown, setShowAssignDropdown] = useState(false);

  const assignMut = useMutation({
    mutationFn: (userId: number | null) => ticketApi.update(ticketId, { assigned_to: userId }),
    onSuccess: () => { toast.success('Ticket assigned'); invalidateTicket(); },
    onError: () => toast.error('Failed to assign'),
  });

  return (
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
                <button
                  onClick={async () => {
                    try {
                      const phone = customer.mobile || customer.phone || '';
                      const res = await voiceApi.call({ to: phone, mode: 'bridge', entity_type: 'ticket', entity_id: ticket.id });
                      if (res.data?.success) toast.success('Calling via provider...');
                      else toast.error((res.data as any)?.message || 'Call failed');
                    } catch { toast.error('Call failed'); }
                  }}
                  className="inline-flex items-center gap-1 px-2 py-1 text-xs font-medium rounded-lg bg-green-50 dark:bg-green-900/20 text-green-600 dark:text-green-400 hover:bg-green-100 dark:hover:bg-green-900/30 transition-colors"
                  title="Call customer via CRM"
                >
                  <Phone className="h-3 w-3" /> Call
                </button>
              )}
              <button onClick={onShowSms}
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
                onSms={onShowSms}
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
  );
}
