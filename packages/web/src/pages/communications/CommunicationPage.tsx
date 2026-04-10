import { useState, useEffect, useRef, useCallback } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Search, Send, MessageSquare, Plus, Phone, User, AlertCircle,
  CheckCheck, Check, Clock, X, FileText, Flag, Pin, Ticket,
  Bell, Loader2, UserPlus, ChevronDown, ChevronUp, Paperclip, Image, CalendarClock,
  Archive, PhoneCall, PhoneIncoming, PhoneOutgoing, PhoneMissed, Play, Mic, Info,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { smsApi, customerApi, ticketApi, voiceApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatPhone } from '@/utils/format';
import { useDraft } from '@/hooks/useDraft';

// ─── Types ──────────────────────────────────────────────────────────
interface Conversation {
  conv_phone: string;
  last_message_at: string;
  last_message: string;
  last_direction: 'inbound' | 'outbound';
  last_status?: string;
  message_count: number;
  unread_count: number;
  customer?: { id: number; first_name: string; last_name: string } | null;
  is_flagged?: boolean;
  is_pinned?: boolean;
  is_archived?: boolean;
  recent_ticket?: { id: number; order_id: string; status_name: string; status_color: string } | null;
}

interface SmsMessage {
  id: number;
  from_number: string;
  to_number: string;
  conv_phone: string;
  message: string;
  status: 'sent' | 'delivered' | 'failed' | 'queued' | 'sending' | 'scheduled';
  direction: 'inbound' | 'outbound';
  provider: string;
  entity_type?: string;
  entity_id?: number;
  user_id?: number;
  sender_name?: string;
  media_urls?: string;
  media_local_paths?: string;
  message_type?: string;
  send_at?: string;
  delivered_at?: string;
  error?: string;
  created_at: string;
}

interface CallLog {
  id: number;
  direction: 'inbound' | 'outbound';
  from_number: string;
  to_number: string;
  conv_phone: string;
  provider: string;
  provider_call_id?: string;
  status: string;
  duration_secs?: number;
  recording_url?: string;
  recording_local_path?: string;
  transcription?: string;
  transcription_status: string;
  call_mode: string;
  user_id?: number;
  user_name?: string;
  entity_type?: string;
  entity_id?: number;
  created_at: string;
  updated_at: string;
}

interface SmsTemplate {
  id: number;
  name: string;
  content: string;
  category: string | null;
}

// ─── Helpers ────────────────────────────────────────────────────────

/** Parse an ISO date string as UTC (SQLite datetime('now') returns UTC without Z suffix) */
function parseUtc(iso: string): Date {
  if (!iso) return new Date();
  // If no explicit timezone indicator (Z, +HH:MM, -HH:MM), treat as UTC
  if (!iso.endsWith('Z') && !iso.includes('+') && !/[-]\d{2}:\d{2}$/.test(iso)) {
    // Normalize: ensure T separator and append Z for UTC
    const normalized = iso.includes('T') ? iso : iso.replace(' ', 'T');
    return new Date(normalized + 'Z');
  }
  return new Date(iso);
}

function formatTime(iso: string) {
  const d = parseUtc(iso);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffDays === 0) {
    return d.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  }
  if (diffDays === 1) return 'Yesterday';
  if (diffDays < 7) return d.toLocaleDateString('en-US', { weekday: 'short' });
  return d.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
}

function formatMessageTime(iso: string) {
  return parseUtc(iso).toLocaleTimeString('en-US', {
    hour: 'numeric',
    minute: '2-digit',
  });
}

function formatMessageDate(iso: string) {
  const d = parseUtc(iso);
  const now = new Date();
  const diffMs = now.getTime() - d.getTime();
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffDays === 0) return 'Today';
  if (diffDays === 1) return 'Yesterday';
  return d.toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric' });
}

function truncate(text: string, len: number) {
  if (!text) return '';
  return text.length > len ? text.slice(0, len) + '...' : text;
}

// ─── Status icon for message delivery (ENR-SMS8: detailed tooltip) ──
function StatusIcon({ status, className, deliveredAt, error }: {
  status: string;
  className?: string;
  deliveredAt?: string;
  error?: string;
}) {
  const statusLabels: Record<string, string> = {
    delivered: 'Delivered',
    sent: 'Sent',
    failed: 'Failed',
    queued: 'Queued',
    sending: 'Sending',
    scheduled: 'Scheduled',
  };

  const label = statusLabels[status] || status;
  const deliveredTime = deliveredAt ? parseUtc(deliveredAt).toLocaleString() : '';
  const tooltip = [
    label,
    deliveredTime ? `at ${deliveredTime}` : '',
    error ? `Error: ${error}` : '',
  ].filter(Boolean).join(' — ');

  const wrap = (icon: React.ReactNode) => (
    <span title={tooltip} className="inline-flex">{icon}</span>
  );

  switch (status) {
    case 'delivered':
      return wrap(<CheckCheck className={cn('h-3 w-3 text-blue-300', className)} />);
    case 'sent':
      return wrap(<Check className={cn('h-3 w-3 text-blue-300/70', className)} />);
    case 'failed':
      return wrap(<AlertCircle className={cn('h-3 w-3 text-red-400', className)} />);
    case 'queued':
    case 'sending':
      return wrap(<Clock className={cn('h-3 w-3 text-blue-300/50', className)} />);
    case 'scheduled':
      return wrap(<CalendarClock className={cn('h-3 w-3 text-amber-400', className)} />);
    default:
      return null;
  }
}

// Smaller status icon for conversation list (uses surface colors)
function ConvStatusIcon({ status }: { status?: string }) {
  if (!status) return null;
  switch (status) {
    case 'delivered':
      return <CheckCheck className="h-3 w-3 text-primary-500" />;
    case 'sent':
      return <Check className="h-3 w-3 text-surface-400" />;
    case 'failed':
      return <AlertCircle className="h-3 w-3 text-red-500" />;
    case 'scheduled':
      return <CalendarClock className="h-3 w-3 text-amber-500" />;
    default:
      return null;
  }
}

// ─── Template Picker (ENR-SMS5: variable chips + preview) ───────────
function TemplatePicker({
  onSelect,
  onInsertVariable,
  onClose,
}: {
  onSelect: (template: SmsTemplate) => void;
  onInsertVariable: (variable: string) => void;
  onClose: () => void;
}) {
  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
  });
  const templates: SmsTemplate[] = (tplData?.data as any)?.data?.templates ?? [];
  const availableVars: string[] = (tplData?.data as any)?.data?.available_variables ?? [];
  const [filter, setFilter] = useState('');
  const [activeSection, setActiveSection] = useState<'templates' | 'variables'>('templates');

  // Group by category
  const grouped = templates.reduce<Record<string, SmsTemplate[]>>((acc, t) => {
    const cat = t.category || 'General';
    (acc[cat] ??= []).push(t);
    return acc;
  }, {});

  const filteredGrouped = Object.entries(grouped).reduce<Record<string, SmsTemplate[]>>((acc, [cat, tpls]) => {
    const filtered = tpls.filter(t =>
      t.name.toLowerCase().includes(filter.toLowerCase()) ||
      t.content.toLowerCase().includes(filter.toLowerCase())
    );
    if (filtered.length > 0) acc[cat] = filtered;
    return acc;
  }, {});

  const categoryLabels: Record<string, string> = {
    status_update: 'Status Updates',
    appointment: 'Appointments',
    estimate: 'Estimates',
    review: 'Reviews',
    general: 'General',
  };

  const variableLabels: Record<string, string> = {
    customer_name: 'Full Name',
    first_name: 'First Name',
    last_name: 'Last Name',
    ticket_id: 'Ticket #',
    device_name: 'Device',
    store_name: 'Store Name',
    store_phone: 'Store Phone',
    order_id: 'Order ID',
  };

  return (
    <div className="absolute bottom-full left-0 mb-2 min-w-[340px] max-h-80 overflow-hidden rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
      {/* Section tabs */}
      <div className="flex border-b border-surface-200 dark:border-surface-700">
        <button
          onClick={() => setActiveSection('templates')}
          className={cn(
            'flex-1 py-1.5 text-[11px] font-semibold transition-colors',
            activeSection === 'templates'
              ? 'border-b-2 border-primary-500 text-primary-600 dark:text-primary-400'
              : 'text-surface-400 hover:text-surface-600',
          )}
        >
          Templates
        </button>
        <button
          onClick={() => setActiveSection('variables')}
          className={cn(
            'flex-1 py-1.5 text-[11px] font-semibold transition-colors',
            activeSection === 'variables'
              ? 'border-b-2 border-primary-500 text-primary-600 dark:text-primary-400'
              : 'text-surface-400 hover:text-surface-600',
          )}
        >
          Variables
        </button>
      </div>

      {activeSection === 'variables' ? (
        /* ENR-SMS5: Variable chips section */
        <div className="p-3">
          <p className="mb-2 text-[10px] text-surface-400">
            Click a variable to insert it at cursor position. Variables are replaced with actual values when sending.
          </p>
          <div className="flex flex-wrap gap-1.5">
            {availableVars.map((v) => (
              <button
                key={v}
                onClick={() => { onInsertVariable(`{{${v}}}`); onClose(); }}
                className="inline-flex items-center gap-1 rounded-full bg-primary-50 px-2.5 py-1 text-[11px] font-medium text-primary-700 hover:bg-primary-100 dark:bg-primary-900/20 dark:text-primary-400 dark:hover:bg-primary-900/30 transition-colors"
                title={`Inserts {{${v}}} — resolves to ${variableLabels[v] || v}`}
              >
                <span className="opacity-50">{'{{'}</span>
                {variableLabels[v] || v}
                <span className="opacity-50">{'}}'}</span>
              </button>
            ))}
          </div>
          {availableVars.length === 0 && (
            <p className="text-xs text-surface-400 text-center py-4">No variables available</p>
          )}
        </div>
      ) : (
        <>
          {/* Search */}
          <div className="border-b border-surface-200 p-2 dark:border-surface-700">
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-surface-400" />
              <input
                type="text"
                value={filter}
                onChange={(e) => setFilter(e.target.value)}
                placeholder="Search templates..."
                autoFocus
                className="w-full rounded-lg border-0 bg-surface-50 py-1.5 pl-8 pr-3 text-xs text-surface-900 placeholder:text-surface-400 focus:outline-none focus:ring-1 focus:ring-primary-400 dark:bg-surface-700 dark:text-surface-100"
          />
        </div>
      </div>
      {/* Template list */}
      <div className="max-h-56 overflow-y-auto">
        {Object.keys(filteredGrouped).length === 0 ? (
          <div className="p-4 text-center text-xs text-surface-400">No templates found</div>
        ) : (
          Object.entries(filteredGrouped).map(([cat, tpls]) => (
            <div key={cat}>
              <div className="sticky top-0 bg-surface-50 px-3 py-1.5 text-[10px] font-semibold uppercase tracking-wider text-surface-400 dark:bg-surface-800">
                {categoryLabels[cat] || cat}
              </div>
              {tpls.map((tpl) => (
                <button
                  key={tpl.id}
                  onClick={() => {
                    onSelect(tpl);
                    onClose();
                  }}
                  className="flex w-full flex-col gap-0.5 px-3 py-2 text-left hover:bg-surface-50 dark:hover:bg-surface-700"
                >
                  <span className="text-xs font-medium text-surface-900 dark:text-surface-100">{tpl.name}</span>
                  <span className="truncate text-[11px] text-surface-500">{tpl.content}</span>
                </button>
              ))}
            </div>
          ))
        )}
      </div>
        </>
      )}
    </div>
  );
}

// ─── Call Log Panel (ENR-V) ─────────────────────────────────────────
function CallLogPanel() {
  const [page, setPage] = useState(1);
  const [expandedCall, setExpandedCall] = useState<number | null>(null);

  const { data: callsData, isLoading } = useQuery({
    queryKey: ['voice-calls', page],
    queryFn: () => voiceApi.calls({ page, pagesize: 20 }),
  });

  const calls: CallLog[] = (callsData?.data as any)?.data?.calls ?? [];
  const pagination = (callsData?.data as any)?.data?.pagination;

  function formatDuration(secs: number | undefined): string {
    if (!secs) return '--';
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return m > 0 ? `${m}m ${s}s` : `${s}s`;
  }

  function callStatusColor(status: string): string {
    switch (status) {
      case 'completed': return 'text-green-600 bg-green-50 dark:text-green-400 dark:bg-green-900/20';
      case 'initiated': case 'ringing': case 'in-progress': return 'text-blue-600 bg-blue-50 dark:text-blue-400 dark:bg-blue-900/20';
      case 'failed': case 'busy': case 'no-answer': return 'text-red-600 bg-red-50 dark:text-red-400 dark:bg-red-900/20';
      default: return 'text-surface-600 bg-surface-100 dark:text-surface-400 dark:bg-surface-700';
    }
  }

  function DirectionIcon({ direction, status }: { direction: string; status: string }) {
    if (status === 'failed' || status === 'no-answer' || status === 'busy') {
      return <PhoneMissed className="h-4 w-4 text-red-500" />;
    }
    return direction === 'inbound'
      ? <PhoneIncoming className="h-4 w-4 text-blue-500" />
      : <PhoneOutgoing className="h-4 w-4 text-green-500" />;
  }

  return (
    <div className="flex flex-1 flex-col bg-surface-50 dark:bg-surface-900">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-surface-200 bg-white px-4 py-3 dark:border-surface-700 dark:bg-surface-800">
        <div className="flex items-center gap-2">
          <PhoneCall className="h-5 w-5 text-primary-500" />
          <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100">Call Log</h2>
        </div>
        {pagination && (
          <span className="text-xs text-surface-400">
            {pagination.total} call{pagination.total !== 1 ? 's' : ''}
          </span>
        )}
      </div>

      {/* Call list */}
      <div className="flex-1 overflow-y-auto">
        {isLoading ? (
          <div className="flex items-center justify-center py-12">
            <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary-500 border-t-transparent" />
          </div>
        ) : calls.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12 text-surface-400">
            <PhoneCall className="mb-2 h-8 w-8" />
            <p className="text-sm">No calls recorded yet</p>
          </div>
        ) : (
          <div className="divide-y divide-surface-100 dark:divide-surface-700">
            {calls.map((call) => (
              <div key={call.id} className="bg-white dark:bg-surface-800">
                <button
                  onClick={() => setExpandedCall(expandedCall === call.id ? null : call.id)}
                  className="flex w-full items-center gap-3 px-4 py-3 text-left hover:bg-surface-50 dark:hover:bg-surface-700/50 transition-colors"
                >
                  <DirectionIcon direction={call.direction} status={call.status} />
                  <div className="min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-medium text-surface-900 dark:text-surface-100">
                        {formatPhone(call.direction === 'inbound' ? call.from_number : call.to_number)}
                      </span>
                      <span className={cn(
                        'rounded-full px-1.5 py-0.5 text-[10px] font-medium',
                        callStatusColor(call.status),
                      )}>
                        {call.status}
                      </span>
                    </div>
                    <div className="flex items-center gap-2 text-xs text-surface-400">
                      <span>{call.direction === 'inbound' ? 'Incoming' : 'Outgoing'}</span>
                      {call.user_name && <><span>&middot;</span><span>{call.user_name}</span></>}
                      <span>&middot;</span>
                      <span>{formatTime(call.created_at)}</span>
                    </div>
                  </div>
                  <div className="text-right shrink-0">
                    <span className="text-sm font-medium text-surface-700 dark:text-surface-300">
                      {formatDuration(call.duration_secs)}
                    </span>
                    {(call.recording_url || call.recording_local_path) && (
                      <div className="flex items-center gap-0.5 text-[10px] text-primary-500 mt-0.5 justify-end">
                        <Mic className="h-3 w-3" />
                        Recorded
                      </div>
                    )}
                  </div>
                </button>

                {/* Expanded details */}
                {expandedCall === call.id && (
                  <div className="border-t border-surface-100 bg-surface-50 px-4 py-3 dark:border-surface-700 dark:bg-surface-800/50">
                    <div className="grid grid-cols-2 gap-2 text-xs">
                      <div>
                        <span className="text-surface-400">From:</span>
                        <span className="ml-1 text-surface-700 dark:text-surface-300">{formatPhone(call.from_number)}</span>
                      </div>
                      <div>
                        <span className="text-surface-400">To:</span>
                        <span className="ml-1 text-surface-700 dark:text-surface-300">{formatPhone(call.to_number)}</span>
                      </div>
                      <div>
                        <span className="text-surface-400">Mode:</span>
                        <span className="ml-1 text-surface-700 dark:text-surface-300">{call.call_mode}</span>
                      </div>
                      <div>
                        <span className="text-surface-400">Provider:</span>
                        <span className="ml-1 text-surface-700 dark:text-surface-300">{call.provider || '--'}</span>
                      </div>
                      <div className="col-span-2">
                        <span className="text-surface-400">Time:</span>
                        <span className="ml-1 text-surface-700 dark:text-surface-300">
                          {parseUtc(call.created_at).toLocaleString()}
                        </span>
                      </div>
                    </div>

                    {/* Recording player */}
                    {(call.recording_local_path || call.recording_url) && (
                      <div className="mt-2 flex items-center gap-2">
                        <Play className="h-4 w-4 text-primary-500 shrink-0" />
                        <audio
                          controls
                          preload="none"
                          className="h-8 flex-1"
                          src={call.recording_local_path || call.recording_url || ''}
                        />
                      </div>
                    )}

                    {/* Transcription */}
                    {call.transcription && (
                      <div className="mt-2 rounded-lg bg-white p-2 text-xs text-surface-700 dark:bg-surface-700 dark:text-surface-300">
                        <p className="mb-1 text-[10px] font-semibold uppercase tracking-wider text-surface-400">Transcription</p>
                        <p className="whitespace-pre-wrap">{call.transcription}</p>
                      </div>
                    )}
                    {call.transcription_status === 'pending' && (
                      <p className="mt-2 text-[10px] text-surface-400 italic">Transcription in progress...</p>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Pagination */}
      {pagination && pagination.total_pages > 1 && (
        <div className="flex items-center justify-between border-t border-surface-200 bg-white px-4 py-2 dark:border-surface-700 dark:bg-surface-800">
          <button
            onClick={() => setPage((p) => Math.max(1, p - 1))}
            disabled={page <= 1}
            className="rounded-lg px-3 py-1 text-xs font-medium text-surface-600 hover:bg-surface-100 disabled:opacity-50 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Previous
          </button>
          <span className="text-xs text-surface-400">
            Page {page} of {pagination.total_pages}
          </span>
          <button
            onClick={() => setPage((p) => Math.min(pagination.total_pages, p + 1))}
            disabled={page >= pagination.total_pages}
            className="rounded-lg px-3 py-1 text-xs font-medium text-surface-600 hover:bg-surface-100 disabled:opacity-50 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Next
          </button>
        </div>
      )}
    </div>
  );
}

// ─── New message modal ──────────────────────────────────────────────
function NewMessageModal({ onClose, onStart }: {
  onClose: () => void;
  onStart: (phone: string) => void;
}) {
  const [phoneInput, setPhoneInput] = useState('');
  const [searchQuery, setSearchQuery] = useState('');
  const inputRef = useRef<HTMLInputElement>(null);

  const { data: searchResults } = useQuery({
    queryKey: ['customer-search-sms', searchQuery],
    queryFn: () => customerApi.search(searchQuery),
    enabled: searchQuery.length >= 2,
  });

  useEffect(() => { inputRef.current?.focus(); }, []);

  const customers = (searchResults?.data as any)?.data ?? [];

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div className="w-full max-w-md rounded-xl bg-white shadow-2xl dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">New Message</h3>
          <button onClick={onClose} className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5 text-surface-500" />
          </button>
        </div>
        <div className="p-4 space-y-3">
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Phone number
            </label>
            <input
              ref={inputRef}
              type="tel"
              value={phoneInput}
              onChange={(e) => setPhoneInput(e.target.value)}
              placeholder="(303) 555-1234"
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              onKeyDown={(e) => {
                if (e.key === 'Enter' && phoneInput.trim()) {
                  onStart(phoneInput.replace(/\D/g, ''));
                }
              }}
            />
          </div>
          <div className="relative">
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Or search customer
            </label>
            <input
              type="text"
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
              placeholder="Name, phone, or email..."
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
            {customers.length > 0 && (
              <div className="absolute left-0 right-0 top-full z-10 mt-1 max-h-48 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                {customers.map((c: any) => (
                  <button
                    key={c.id}
                    onClick={() => onStart((c.mobile || c.phone || '').replace(/\D/g, ''))}
                    className="flex w-full items-center gap-3 px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700"
                  >
                    <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary-100 text-primary-600 dark:bg-primary-900/30 dark:text-primary-400">
                      <User className="h-4 w-4" />
                    </div>
                    <div>
                      <div className="font-medium text-surface-900 dark:text-surface-100">
                        {c.first_name} {c.last_name}
                      </div>
                      <div className="text-xs text-surface-500">
                        {formatPhone(c.mobile || c.phone || '')}
                      </div>
                    </div>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          <button
            onClick={onClose}
            className="rounded-lg px-4 py-2 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
          <button
            onClick={() => phoneInput.trim() && onStart(phoneInput.replace(/\D/g, ''))}
            disabled={!phoneInput.trim()}
            className="rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50"
          >
            Start Conversation
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Link Customer Popover (COM-1) ──────────────────────────────────
function LinkCustomerPopover({
  phone,
  onLinked,
  onClose,
}: {
  phone: string;
  onLinked: (customer: { id: number; first_name: string; last_name: string }) => void;
  onClose: () => void;
}) {
  const navigate = useNavigate();
  const [searchQuery, setSearchQuery] = useState('');
  const queryClient = useQueryClient();

  const { data: searchResults } = useQuery({
    queryKey: ['customer-search-link', searchQuery],
    queryFn: () => customerApi.search(searchQuery),
    enabled: searchQuery.length >= 2,
  });
  const customers = (searchResults?.data as any)?.data ?? [];

  const createMut = useMutation({
    mutationFn: () => customerApi.create({ first_name: 'New', last_name: 'Customer', mobile: phone } as any),
    onSuccess: (res) => {
      const cust = (res.data as any)?.data;
      if (cust) {
        onLinked({ id: cust.id, first_name: cust.first_name, last_name: cust.last_name });
        queryClient.invalidateQueries({ queryKey: ['sms-conversations'] });
        queryClient.invalidateQueries({ queryKey: ['sms-messages', phone] });
        toast.success('Customer created and linked');
      }
      onClose();
    },
    onError: () => toast.error('Failed to create customer'),
  });

  const linkExisting = useMutation({
    // For now we just navigate to customer create with phone pre-filled, or we can just
    // update the customer's phone. Since the SMS system auto-resolves by phone, creating
    // a customer with this phone number is sufficient.
    mutationFn: (customerId: number) => customerApi.update(customerId, { mobile: phone } as any),
    onSuccess: (_res, customerId) => {
      const c = customers.find((c: any) => c.id === customerId);
      if (c) {
        onLinked({ id: c.id, first_name: c.first_name, last_name: c.last_name });
      }
      queryClient.invalidateQueries({ queryKey: ['sms-conversations'] });
      queryClient.invalidateQueries({ queryKey: ['sms-messages', phone] });
      toast.success('Phone linked to customer');
      onClose();
    },
    onError: () => toast.error('Failed to link customer'),
  });

  return (
    <div className="absolute left-0 top-full z-30 mt-1 w-72 rounded-xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-800">
      <div className="p-3 border-b border-surface-200 dark:border-surface-700">
        <p className="text-xs font-semibold text-surface-500 uppercase tracking-wider mb-2">Link to Customer</p>
        <input
          type="text"
          value={searchQuery}
          onChange={(e) => setSearchQuery(e.target.value)}
          placeholder="Search by name..."
          autoFocus
          className="w-full rounded-lg border border-surface-300 px-3 py-1.5 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100 focus:outline-none focus:ring-1 focus:ring-primary-400"
        />
      </div>
      <div className="max-h-40 overflow-y-auto">
        {customers.length > 0 ? customers.map((c: any) => (
          <button
            key={c.id}
            onClick={() => linkExisting.mutate(c.id)}
            className="flex w-full items-center gap-2 px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700"
          >
            <div className="flex h-7 w-7 items-center justify-center rounded-full bg-primary-100 text-primary-600 dark:bg-primary-900/30 dark:text-primary-400">
              <User className="h-3.5 w-3.5" />
            </div>
            <div className="min-w-0">
              <div className="text-xs font-medium text-surface-900 dark:text-surface-100 truncate">{c.first_name} {c.last_name}</div>
              <div className="text-[10px] text-surface-500">{c.mobile || c.phone || c.email || ''}</div>
            </div>
          </button>
        )) : searchQuery.length >= 2 ? (
          <div className="px-3 py-3 text-xs text-surface-400 text-center">No customers found</div>
        ) : (
          <div className="px-3 py-3 text-xs text-surface-400 text-center">Type to search...</div>
        )}
      </div>
      <div className="border-t border-surface-200 dark:border-surface-700 p-2">
        <button
          onClick={() => navigate(`/customers/new?phone=${phone}`)}
          className="flex w-full items-center gap-2 rounded-lg px-3 py-2 text-sm font-medium text-primary-600 hover:bg-primary-50 dark:text-primary-400 dark:hover:bg-primary-900/20"
        >
          <UserPlus className="h-4 w-4" />
          Create New Customer
        </button>
      </div>
    </div>
  );
}

// ─── Thread Search (COM-2) ──────────────────────────────────────────
function ThreadSearchBar({
  messages,
  scrollContainerRef,
}: {
  messages: SmsMessage[];
  scrollContainerRef: React.RefObject<HTMLDivElement | null>;
}) {
  const [query, setQuery] = useState('');
  const [matchIndex, setMatchIndex] = useState(0);
  const [matchCount, setMatchCount] = useState(0);

  useEffect(() => {
    if (!query.trim()) {
      // Clear highlights
      clearHighlights();
      setMatchCount(0);
      setMatchIndex(0);
      return;
    }
    const count = highlightMatches(query);
    setMatchCount(count);
    setMatchIndex(count > 0 ? 0 : -1);
    if (count > 0) scrollToMatch(0);
  }, [query, messages.length]);

  function clearHighlights() {
    const container = scrollContainerRef.current;
    if (!container) return;
    container.querySelectorAll('mark[data-thread-search]').forEach((el) => {
      const parent = el.parentNode;
      if (parent) {
        parent.replaceChild(document.createTextNode(el.textContent || ''), el);
        parent.normalize();
      }
    });
  }

  function highlightMatches(q: string): number {
    clearHighlights();
    const container = scrollContainerRef.current;
    if (!container || !q.trim()) return 0;
    const lowerQ = q.toLowerCase();
    let count = 0;
    // Find all message text nodes in .msg-text elements
    const msgEls = container.querySelectorAll('[data-msg-text]');
    msgEls.forEach((el) => {
      const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
      const textNodes: Text[] = [];
      let node: Text | null;
      while ((node = walker.nextNode() as Text)) textNodes.push(node);

      for (const textNode of textNodes) {
        const text = textNode.textContent || '';
        const lowerText = text.toLowerCase();
        let idx = lowerText.indexOf(lowerQ);
        if (idx === -1) continue;

        const frag = document.createDocumentFragment();
        let lastIdx = 0;
        while (idx !== -1) {
          frag.appendChild(document.createTextNode(text.slice(lastIdx, idx)));
          const mark = document.createElement('mark');
          mark.setAttribute('data-thread-search', '');
          mark.setAttribute('data-match-idx', String(count));
          mark.className = 'bg-yellow-300 dark:bg-yellow-700 rounded-sm px-0.5';
          mark.textContent = text.slice(idx, idx + q.length);
          frag.appendChild(mark);
          count++;
          lastIdx = idx + q.length;
          idx = lowerText.indexOf(lowerQ, lastIdx);
        }
        frag.appendChild(document.createTextNode(text.slice(lastIdx)));
        textNode.parentNode?.replaceChild(frag, textNode);
      }
    });
    return count;
  }

  function scrollToMatch(idx: number) {
    const container = scrollContainerRef.current;
    if (!container) return;
    // Remove active class from previous
    container.querySelectorAll('mark[data-thread-search].ring-2').forEach((el) => {
      el.classList.remove('ring-2', 'ring-orange-400');
    });
    const target = container.querySelector(`mark[data-match-idx="${idx}"]`);
    if (target) {
      target.classList.add('ring-2', 'ring-orange-400');
      target.scrollIntoView({ behavior: 'smooth', block: 'center' });
    }
  }

  function handleNext() {
    if (matchCount === 0) return;
    const next = (matchIndex + 1) % matchCount;
    setMatchIndex(next);
    scrollToMatch(next);
  }

  function handlePrev() {
    if (matchCount === 0) return;
    const prev = (matchIndex - 1 + matchCount) % matchCount;
    setMatchIndex(prev);
    scrollToMatch(prev);
  }

  return (
    <div className="flex items-center gap-2 border-b border-surface-200 bg-white px-3 py-1.5 dark:border-surface-700 dark:bg-surface-800">
      <Search className="h-3.5 w-3.5 text-surface-400 shrink-0" />
      <input
        type="text"
        value={query}
        onChange={(e) => setQuery(e.target.value)}
        onKeyDown={(e) => {
          if (e.key === 'Enter') {
            e.preventDefault();
            if (e.shiftKey) handlePrev(); else handleNext();
          }
          if (e.key === 'Escape') {
            setQuery('');
          }
        }}
        placeholder="Search in conversation..."
        className="flex-1 bg-transparent text-sm text-surface-900 dark:text-surface-100 placeholder:text-surface-400 focus:outline-none"
      />
      {query && (
        <>
          <span className="text-xs text-surface-400 shrink-0">
            {matchCount > 0 ? `${matchIndex + 1}/${matchCount}` : '0/0'}
          </span>
          <button onClick={handlePrev} className="p-0.5 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400" title="Previous match">
            <ChevronUp className="h-3.5 w-3.5" />
          </button>
          <button onClick={handleNext} className="p-0.5 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400" title="Next match">
            <ChevronDown className="h-3.5 w-3.5" />
          </button>
          <button onClick={() => setQuery('')} className="p-0.5 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400" title="Clear search">
            <X className="h-3.5 w-3.5" />
          </button>
        </>
      )}
    </div>
  );
}

// ─── Main Component ─────────────────────────────────────────────────
export function CommunicationPage() {
  const queryClient = useQueryClient();
  const [mainView, setMainView] = useState<'messages' | 'calls'>('messages');
  const [selectedPhone, setSelectedPhone] = useState<string | null>(null);
  const [searchFilter, setSearchFilter] = useState('');
  const [activeTab, setActiveTab] = useState<'all' | 'unread' | 'flagged' | 'pinned' | 'archived'>('all');
  const [composeText, setComposeText, clearSmsDraft, hasSmsDraft] = useDraft(selectedPhone ? `draft_sms_${selectedPhone}` : 'draft_sms_none');
  const [showNewMessage, setShowNewMessage] = useState(false);
  const [showTemplates, setShowTemplates] = useState(false);
  const [attachedMedia, setAttachedMedia] = useState<{ url: string; contentType: string; preview: string } | null>(null);
  const [uploading, setUploading] = useState(false);
  const [scheduledAt, setScheduledAt] = useState<string>('');
  const [showSchedulePicker, setShowSchedulePicker] = useState(false);
  const imageInputRef = useRef<HTMLInputElement>(null);
  const [showReminder, setShowReminder] = useState(false);
  const [showLinkCustomer, setShowLinkCustomer] = useState(false);
  const [showThreadSearch, setShowThreadSearch] = useState(false);
  const [linkedCustomerOverride, setLinkedCustomerOverride] = useState<Record<string, { id: number; first_name: string; last_name: string }>>({});
  const messagesEndRef = useRef<HTMLDivElement>(null);
  const messagesContainerRef = useRef<HTMLDivElement>(null);
  const composeRef = useRef<HTMLTextAreaElement>(null);
  const templateBtnRef = useRef<HTMLButtonElement>(null);

  // Revoke previous object URL when attachedMedia changes or component unmounts
  const prevPreviewRef = useRef<string | null>(null);
  useEffect(() => {
    if (prevPreviewRef.current && prevPreviewRef.current !== attachedMedia?.preview) {
      URL.revokeObjectURL(prevPreviewRef.current);
    }
    prevPreviewRef.current = attachedMedia?.preview ?? null;
    return () => {
      if (prevPreviewRef.current) {
        URL.revokeObjectURL(prevPreviewRef.current);
      }
    };
  }, [attachedMedia]);

  // Fetch conversations (include archived when that tab is active)
  const includeArchived = activeTab === 'archived';
  const { data: convData, isLoading: convLoading } = useQuery({
    queryKey: ['sms-conversations', includeArchived],
    queryFn: () => smsApi.conversations(includeArchived ? { include_archived: '1' } as any : undefined),
    refetchInterval: 15000,
  });
  const conversations: Conversation[] = (convData?.data as any)?.data?.conversations ?? [];

  // Fetch messages for selected conversation
  const { data: msgData, isLoading: msgLoading } = useQuery({
    queryKey: ['sms-messages', selectedPhone],
    queryFn: () => smsApi.messages(selectedPhone!),
    enabled: !!selectedPhone,
    refetchInterval: 10000,
  });

  // Mark conversation as read when selected
  const markReadMutation = useMutation({
    mutationFn: (phone: string) => smsApi.markRead(phone),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sms-conversations'] });
    },
  });
  const markReadRef = useRef(markReadMutation.mutate);
  markReadRef.current = markReadMutation.mutate;

  useEffect(() => {
    if (selectedPhone) {
      markReadRef.current(selectedPhone);
    }
  }, [selectedPhone]);
  const messages: SmsMessage[] = (msgData?.data as any)?.data?.messages ?? [];
  const rawThreadCustomer = (msgData?.data as any)?.data?.customer ?? null;
  const threadCustomer = (selectedPhone && linkedCustomerOverride[selectedPhone]) || rawThreadCustomer;

  // Fetch customer tickets for right panel
  const { data: customerTicketsData, isLoading: customerTicketsLoading } = useQuery({
    queryKey: ['customer-tickets-sms', threadCustomer?.id],
    queryFn: () => customerApi.getTickets(threadCustomer.id, { page: 1 }),
    enabled: !!threadCustomer?.id,
  });
  const customerTickets: any[] = (customerTicketsData?.data as any)?.data?.tickets ?? (customerTicketsData?.data as any)?.data ?? [];

  // Reminder helpers
  const handleSetReminder = useCallback((phone: string, label: string, ms: number) => {
    const reminders = JSON.parse(localStorage.getItem('sms_reminders') || '[]');
    reminders.push({ phone, label, due: Date.now() + ms, created: Date.now() });
    localStorage.setItem('sms_reminders', JSON.stringify(reminders));
    toast.success(`Reminder set: ${label}`);
    setShowReminder(false);
  }, []);

  // Flag/pin mutations
  const toggleFlagMut = useMutation({
    mutationFn: (phone: string) => smsApi.toggleFlag(phone),
    onMutate: async (phone) => {
      await queryClient.cancelQueries({ queryKey: ['sms-conversations'] });
      const prev = queryClient.getQueryData(['sms-conversations']);
      queryClient.setQueryData(['sms-conversations'], (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.conversations ?? [];
        const c = list.find((c: any) => c.conv_phone === phone);
        if (c) c.is_flagged = !c.is_flagged;
        return clone;
      });
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(['sms-conversations'], ctx.prev);
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['sms-conversations'] }),
  });

  const togglePinMut = useMutation({
    mutationFn: (phone: string) => smsApi.togglePin(phone),
    onMutate: async (phone) => {
      await queryClient.cancelQueries({ queryKey: ['sms-conversations'] });
      const prev = queryClient.getQueryData(['sms-conversations']);
      queryClient.setQueryData(['sms-conversations'], (old: any) => {
        if (!old) return old;
        const clone = JSON.parse(JSON.stringify(old));
        const list = clone?.data?.data?.conversations ?? [];
        const c = list.find((c: any) => c.conv_phone === phone);
        if (c) c.is_pinned = !c.is_pinned;
        return clone;
      });
      return { prev };
    },
    onError: (_err, _vars, ctx) => {
      if (ctx?.prev) queryClient.setQueryData(['sms-conversations'], ctx.prev);
    },
    onSettled: () => queryClient.invalidateQueries({ queryKey: ['sms-conversations'] }),
  });

  // ENR-SMS7: Archive/unarchive mutation
  const toggleArchiveMut = useMutation({
    mutationFn: (phone: string) => smsApi.toggleArchive(phone),
    onSuccess: (_data, phone) => {
      queryClient.invalidateQueries({ queryKey: ['sms-conversations'] });
      const isNowArchived = !conversations.find((c) => c.conv_phone === phone)?.is_archived;
      toast.success(isNowArchived ? 'Conversation archived' : 'Conversation unarchived');
      if (isNowArchived && selectedPhone === phone) {
        setSelectedPhone(null);
      }
    },
    onError: () => toast.error('Failed to update archive status'),
  });

  // Send message mutation
  const sendMutation = useMutation({
    mutationFn: (data: { to: string; message: string; send_at?: string }) => smsApi.send(data),
    onSuccess: (_data, variables) => {
      clearSmsDraft();
      setScheduledAt('');
      setShowSchedulePicker(false);
      // Reset textarea height
      if (composeRef.current) {
        composeRef.current.style.height = 'auto';
      }
      queryClient.invalidateQueries({ queryKey: ['sms-messages', selectedPhone] });
      queryClient.invalidateQueries({ queryKey: ['sms-conversations'] });
      toast.success(variables.send_at ? 'Message scheduled' : 'Message sent');
    },
    onError: () => {
      toast.error('Failed to send message');
    },
  });

  // Auto-scroll to bottom when messages change
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  // Close template picker on outside click
  useEffect(() => {
    if (!showTemplates) return;
    const handler = (e: MouseEvent) => {
      if (templateBtnRef.current && !templateBtnRef.current.contains(e.target as Node)) {
        // Check if click is inside the template picker
        const picker = templateBtnRef.current.closest('.relative')?.querySelector('[data-template-picker]');
        if (picker && picker.contains(e.target as Node)) return;
        setShowTemplates(false);
      }
    };
    document.addEventListener('mousedown', handler);
    return () => document.removeEventListener('mousedown', handler);
  }, [showTemplates]);

  // Close reminder popover on outside click
  useEffect(() => {
    if (!showReminder) return;
    const handler = (e: MouseEvent) => setShowReminder(false);
    const timer = setTimeout(() => document.addEventListener('click', handler), 0);
    return () => { clearTimeout(timer); document.removeEventListener('click', handler); };
  }, [showReminder]);

  // Close link customer popover on outside click
  useEffect(() => {
    if (!showLinkCustomer) return;
    const handler = () => setShowLinkCustomer(false);
    const timer = setTimeout(() => document.addEventListener('click', handler), 0);
    return () => { clearTimeout(timer); document.removeEventListener('click', handler); };
  }, [showLinkCustomer]);

  // Close schedule picker on outside click
  useEffect(() => {
    if (!showSchedulePicker) return;
    const handler = (e: MouseEvent) => {
      const target = e.target as HTMLElement;
      if (target.closest('[data-schedule-picker]')) return;
      setShowSchedulePicker(false);
    };
    const timer = setTimeout(() => document.addEventListener('click', handler), 0);
    return () => { clearTimeout(timer); document.removeEventListener('click', handler); };
  }, [showSchedulePicker]);

  // Filter conversations by search + tab (client-side for instant feedback)
  const filtered = conversations.filter((c) => {
    // Tab filter
    if (activeTab === 'unread' && (c.unread_count ?? 0) === 0) return false;
    if (activeTab === 'flagged' && !c.is_flagged) return false;
    if (activeTab === 'pinned' && !c.is_pinned) return false;
    if (activeTab === 'archived' && !c.is_archived) return false;
    // Hide archived from non-archived tabs
    if (activeTab !== 'archived' && c.is_archived) return false;

    if (!searchFilter) return true;
    const q = searchFilter.toLowerCase();
    const name = c.customer ? `${c.customer.first_name} ${c.customer.last_name}`.toLowerCase() : '';
    return name.includes(q) || c.conv_phone.includes(q) || (c.last_message || '').toLowerCase().includes(q);
  });

  // Group messages by date for separators
  const groupedMessages = messages.reduce<{ date: string; messages: SmsMessage[] }[]>((acc, msg) => {
    const dateStr = formatMessageDate(msg.created_at);
    const last = acc[acc.length - 1];
    if (last && last.date === dateStr) {
      last.messages.push(msg);
    } else {
      acc.push({ date: dateStr, messages: [msg] });
    }
    return acc;
  }, []);

  const handleSend = useCallback(() => {
    if ((!composeText.trim() && !attachedMedia) || !selectedPhone) return;
    const payload: any = { to: selectedPhone, message: composeText.trim() };
    if (attachedMedia) {
      payload.media = [{ url: attachedMedia.url, contentType: attachedMedia.contentType }];
    }
    if (scheduledAt) {
      payload.send_at = new Date(scheduledAt).toISOString();
    }
    sendMutation.mutate(payload, {
      onSuccess: () => setAttachedMedia(null),
    });
  }, [composeText, selectedPhone, sendMutation, attachedMedia, scheduledAt]);

  const handleImageSelect = useCallback(async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setUploading(true);
    try {
      const res = await smsApi.uploadMedia(file);
      const data = res.data?.data;
      if (data) {
        setAttachedMedia({ url: data.url, contentType: data.contentType, preview: URL.createObjectURL(file) });
      }
    } catch (err) {
      toast.error('Upload failed');
    } finally {
      setUploading(false);
      if (imageInputRef.current) imageInputRef.current.value = '';
    }
  }, []);

  const handleTemplateSelect = useCallback((tpl: SmsTemplate) => {
    setComposeText(tpl.content);
    // Focus the textarea after inserting template
    setTimeout(() => composeRef.current?.focus(), 50);
  }, []);

  const displayName = (conv: Conversation) =>
    conv.customer ? `${conv.customer.first_name} ${conv.customer.last_name}` : null;

  // Character count helpers
  const charCount = composeText.length;
  const segmentCount = charCount <= 160 ? 1 : Math.ceil(charCount / 153);

  return (
    <div className="flex overflow-hidden -m-6" style={{ height: 'calc(100vh - 4rem - var(--dev-banner-h, 0px))' }}>
      {/* ── Left Panel: Conversation List ── */}
      <div className="flex w-full flex-col border-r border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800 md:w-80 lg:w-96">
        {/* Header with Messages/Calls toggle */}
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-2 dark:border-surface-700">
          <div className="flex items-center gap-1 rounded-lg bg-surface-100 p-0.5 dark:bg-surface-700">
            <button
              onClick={() => setMainView('messages')}
              className={cn(
                'flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors',
                mainView === 'messages'
                  ? 'bg-white text-surface-900 shadow-sm dark:bg-surface-600 dark:text-surface-100'
                  : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
              )}
            >
              <MessageSquare className="h-3.5 w-3.5" />
              Messages
            </button>
            <button
              onClick={() => setMainView('calls')}
              className={cn(
                'flex items-center gap-1.5 rounded-md px-3 py-1.5 text-xs font-medium transition-colors',
                mainView === 'calls'
                  ? 'bg-white text-surface-900 shadow-sm dark:bg-surface-600 dark:text-surface-100'
                  : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
              )}
            >
              <PhoneCall className="h-3.5 w-3.5" />
              Calls
            </button>
          </div>
          {mainView === 'messages' && (
            <button
              onClick={() => setShowNewMessage(true)}
              className="flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-primary-700"
            >
              <Plus className="h-4 w-4" />
              New
            </button>
          )}
        </div>

        {mainView === 'messages' ? (<>
        {/* Search */}
        <div className="px-3 py-2">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
            <input
              type="text"
              placeholder="Search conversations..."
              value={searchFilter}
              onChange={(e) => setSearchFilter(e.target.value)}
              className="w-full rounded-lg border border-surface-200 bg-surface-50 py-2 pl-9 pr-3 text-sm text-surface-900 placeholder:text-surface-400 focus:border-primary-400 focus:outline-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
        </div>

        {/* Filter tabs */}
        <div className="flex border-b border-surface-200 dark:border-surface-700">
          {(['all', 'unread', 'flagged', 'pinned', 'archived'] as const).map((tab) => {
            const labels: Record<typeof tab, string> = { all: 'All', unread: 'Unread', flagged: 'Flagged', pinned: 'Pinned', archived: 'Archived' };
            const counts: Record<typeof tab, number> = {
              all: conversations.filter((c) => !c.is_archived).length,
              unread: conversations.filter((c) => (c.unread_count ?? 0) > 0 && !c.is_archived).length,
              flagged: conversations.filter((c) => c.is_flagged && !c.is_archived).length,
              pinned: conversations.filter((c) => c.is_pinned && !c.is_archived).length,
              archived: conversations.filter((c) => c.is_archived).length,
            };
            return (
              <button
                key={tab}
                onClick={() => setActiveTab(tab)}
                className={cn(
                  'flex-1 py-2 text-xs font-medium transition-colors',
                  activeTab === tab
                    ? 'border-b-2 border-primary-500 text-primary-600 dark:text-primary-400'
                    : 'text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200',
                )}
              >
                {labels[tab]}
                {counts[tab] > 0 && (
                  <span className={cn(
                    'ml-1 inline-flex h-4 min-w-[1rem] items-center justify-center rounded-full px-1 text-[10px] font-bold',
                    activeTab === tab
                      ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400'
                      : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
                  )}>
                    {counts[tab]}
                  </span>
                )}
              </button>
            );
          })}
        </div>

        {/* Conversation list */}
        <div className="flex-1 overflow-y-auto">
          {convLoading ? (
            <div className="space-y-1 p-2">
              {Array.from({ length: 8 }).map((_, i) => (
                <div key={i} className="animate-pulse rounded-lg p-3">
                  <div className="flex items-center gap-3">
                    <div className="h-10 w-10 rounded-full bg-surface-200 dark:bg-surface-700" />
                    <div className="flex-1 space-y-2">
                      <div className="h-4 w-24 rounded bg-surface-200 dark:bg-surface-700" />
                      <div className="h-3 w-36 rounded bg-surface-200 dark:bg-surface-700" />
                    </div>
                  </div>
                </div>
              ))}
            </div>
          ) : filtered.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-12 text-surface-400">
              <MessageSquare className="mb-2 h-8 w-8" />
              <p className="text-sm">No conversations found</p>
            </div>
          ) : (
            <div className="space-y-0.5 p-1">
              {filtered.map((conv) => {
                const hasUnread = (conv.unread_count ?? 0) > 0;
                return (
                  <button
                    key={conv.conv_phone}
                    onClick={() => setSelectedPhone(conv.conv_phone)}
                    className={cn(
                      'flex w-full items-center gap-3 rounded-lg px-3 py-3 text-left transition-colors',
                      selectedPhone === conv.conv_phone
                        ? 'bg-primary-50 dark:bg-primary-900/20'
                        : 'hover:bg-surface-50 dark:hover:bg-surface-700/50',
                    )}
                  >
                    {/* Avatar with unread dot */}
                    <div className="relative shrink-0">
                      <div className={cn(
                        'flex h-10 w-10 items-center justify-center rounded-full text-sm font-semibold',
                        conv.customer
                          ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400'
                          : 'bg-surface-200 text-surface-600 dark:bg-surface-600 dark:text-surface-300',
                      )}>
                        {conv.customer
                          ? `${conv.customer.first_name?.[0] || ''}${conv.customer.last_name?.[0] || ''}`
                          : <Phone className="h-4 w-4" />}
                      </div>
                      {hasUnread && (
                        <span className="absolute -right-0.5 -top-0.5 flex h-4 min-w-[1rem] items-center justify-center rounded-full bg-primary-500 px-1 text-[10px] font-bold text-white">
                          {conv.unread_count > 9 ? '9+' : conv.unread_count}
                        </span>
                      )}
                    </div>

                    <div className="min-w-0 flex-1">
                      <div className="flex items-center justify-between">
                        <div className="flex items-center gap-1 min-w-0">
                          {conv.is_pinned && <Pin className="h-3 w-3 shrink-0 text-primary-500" style={{ fill: 'currentColor' }} />}
                          {conv.is_flagged && <Flag className="h-3 w-3 shrink-0 text-amber-500" style={{ fill: 'currentColor' }} />}
                          <span className={cn(
                            'truncate text-sm text-surface-900 dark:text-surface-100',
                            hasUnread ? 'font-semibold' : 'font-medium',
                          )}>
                            {displayName(conv) || (
                              <span>
                                <span className="italic text-surface-400">Unknown Caller</span>
                                {' '}
                                <span className="text-xs text-surface-500">{formatPhone(conv.conv_phone)}</span>
                              </span>
                            )}
                          </span>
                        </div>
                        <div className="flex items-center gap-0.5 ml-2 shrink-0">
                          <button
                            onClick={(e) => { e.stopPropagation(); togglePinMut.mutate(conv.conv_phone); }}
                            className={cn(
                              'rounded p-0.5 transition-colors',
                              conv.is_pinned
                                ? 'text-primary-500 hover:text-primary-600'
                                : 'text-transparent hover:text-surface-400',
                            )}
                            title={conv.is_pinned ? 'Unpin' : 'Pin'}
                          >
                            <Pin className="h-3 w-3" />
                          </button>
                          <button
                            onClick={(e) => { e.stopPropagation(); toggleFlagMut.mutate(conv.conv_phone); }}
                            className={cn(
                              'rounded p-0.5 transition-colors',
                              conv.is_flagged
                                ? 'text-amber-500 hover:text-amber-600'
                                : 'text-transparent hover:text-surface-400',
                            )}
                            title={conv.is_flagged ? 'Unflag' : 'Flag'}
                          >
                            <Flag className="h-3 w-3" />
                          </button>
                          <span className={cn(
                            'text-xs',
                            hasUnread ? 'font-semibold text-primary-600 dark:text-primary-400' : 'text-surface-400',
                          )}>
                            {formatTime(conv.last_message_at)}
                          </span>
                        </div>
                      </div>
                      <div className="mt-0.5 flex items-center gap-1">
                        {conv.last_direction === 'outbound' && (
                          <ConvStatusIcon status={conv.last_status} />
                        )}
                        <p className={cn(
                          'truncate text-xs',
                          hasUnread
                            ? 'font-medium text-surface-700 dark:text-surface-200'
                            : 'text-surface-500 dark:text-surface-400',
                        )}>
                          {conv.last_direction === 'outbound' && (
                            <span className="text-surface-400">You: </span>
                          )}
                          {truncate(conv.last_message || '', 50)}
                        </p>
                      </div>
                      {conv.recent_ticket && (
                        <div className="mt-0.5">
                          <span
                            className="inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[10px] font-medium"
                            style={{ backgroundColor: `${conv.recent_ticket.status_color}18`, color: conv.recent_ticket.status_color }}
                            title={`${conv.recent_ticket.order_id} — ${conv.recent_ticket.status_name}`}
                          >
                            <Ticket className="h-2.5 w-2.5" />
                            {conv.recent_ticket.order_id}
                          </span>
                        </div>
                      )}
                    </div>
                  </button>
                );
              })}
            </div>
          )}
        </div>
        </>) : (
          /* Call log view fills the left panel when calls tab is active */
          <div className="flex-1 flex flex-col text-center text-surface-400 py-8">
            <PhoneCall className="mx-auto mb-2 h-8 w-8" />
            <p className="text-sm">Call log shown in main panel</p>
          </div>
        )}
      </div>

      {/* ── Right Panel: Message Thread or Call Log ── */}
      {mainView === 'calls' ? (
        <CallLogPanel />
      ) : (
      <div className="flex flex-1 flex-col bg-surface-50 dark:bg-surface-900">
        {!selectedPhone ? (
          /* Empty state */
          <div className="flex flex-1 flex-col items-center justify-center text-surface-400">
            <MessageSquare className="mb-4 h-16 w-16 text-surface-300 dark:text-surface-600" />
            <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
              Select a conversation
            </h2>
            <p className="mt-1 text-sm">Choose a conversation from the list to view messages</p>
          </div>
        ) : (
          <>
            {/* Thread header */}
            <div className="flex items-center gap-3 border-b border-surface-200 bg-white px-4 py-3 dark:border-surface-700 dark:bg-surface-800">
              <div className={cn(
                'flex h-10 w-10 shrink-0 items-center justify-center rounded-full text-sm font-semibold',
                threadCustomer
                  ? 'bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400'
                  : 'bg-surface-200 text-surface-600 dark:bg-surface-600 dark:text-surface-300',
              )}>
                {threadCustomer
                  ? `${threadCustomer.first_name?.[0] || ''}${threadCustomer.last_name?.[0] || ''}`
                  : <Phone className="h-4 w-4" />}
              </div>
              <div className="min-w-0 flex-1">
                <div className="font-medium text-surface-900 dark:text-surface-100">
                  {threadCustomer
                    ? (
                      <Link
                        to={`/customers/${threadCustomer.id}`}
                        className="hover:text-primary-600 hover:underline"
                      >
                        {threadCustomer.first_name} {threadCustomer.last_name}
                      </Link>
                    )
                    : <span className="flex items-center gap-2">
                        <span className="italic text-surface-400">Unknown Caller</span>
                        <a href={`tel:+1${selectedPhone}`} className="text-sm text-surface-500 hover:text-primary-600 hover:underline" title="Call this number">{formatPhone(selectedPhone)}</a>
                        <div className="relative">
                          <button
                            onClick={() => setShowLinkCustomer(!showLinkCustomer)}
                            className="inline-flex items-center gap-1 rounded-md bg-primary-50 dark:bg-primary-900/20 text-primary-600 dark:text-primary-400 px-2 py-0.5 text-xs font-medium hover:bg-primary-100 dark:hover:bg-primary-900/30 transition-colors"
                          >
                            <UserPlus className="h-3 w-3" />
                            Link Customer
                          </button>
                          {showLinkCustomer && selectedPhone && (
                            <LinkCustomerPopover
                              phone={selectedPhone}
                              onLinked={(cust) => {
                                setLinkedCustomerOverride((prev) => ({ ...prev, [selectedPhone!]: cust }));
                                setShowLinkCustomer(false);
                              }}
                              onClose={() => setShowLinkCustomer(false)}
                            />
                          )}
                        </div>
                      </span>}
                </div>
                <div className="flex flex-wrap items-center gap-2 text-xs text-surface-500">
                  <a href={`tel:+1${selectedPhone}`} className="hover:text-primary-600 hover:underline" title="Call this number">
                    {formatPhone(selectedPhone)}
                  </a>
                  {threadCustomer && (
                    <>
                      <span>&middot;</span>
                      <Link
                        to={`/customers/${threadCustomer.id}`}
                        className="text-primary-500 hover:underline"
                      >
                        View customer
                      </Link>
                    </>
                  )}
                  {(() => {
                    const tickets: { id: number; order_id: string; status_name: string; status_color: string; device_name?: string; total?: number }[] =
                      (msgData?.data as any)?.data?.recent_tickets ?? [];
                    if (tickets.length === 0) return null;
                    return (
                      <>
                        <span>&middot;</span>
                        {tickets.map((t) => (
                          <Link
                            key={t.id}
                            to={`/tickets/${t.id}`}
                            className="inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium hover:opacity-80 transition-opacity"
                            style={{ backgroundColor: `${t.status_color}18`, color: t.status_color }}
                            title={`${t.order_id} — ${t.device_name || 'Unknown'} — ${t.status_name}${t.total ? ` — $${Number(t.total).toFixed(2)}` : ''}`}
                          >
                            <Ticket className="h-2.5 w-2.5" />
                            {t.order_id}
                            {t.device_name && <span className="opacity-75" title={t.device_name}>· {t.device_name}</span>}
                          </Link>
                        ))}
                      </>
                    );
                  })()}
                </div>
              </div>

              {/* Thread action buttons */}
              <div className="flex items-center gap-1 shrink-0">
                {(() => {
                  const conv = conversations.find((c) => c.conv_phone === selectedPhone);
                  return (
                    <>
                      <button
                        onClick={() => selectedPhone && toggleFlagMut.mutate(selectedPhone)}
                        className={cn(
                          'flex h-8 w-8 items-center justify-center rounded-lg transition-colors',
                          conv?.is_flagged
                            ? 'bg-amber-50 text-amber-500 hover:bg-amber-100 dark:bg-amber-900/20 dark:hover:bg-amber-900/30'
                            : 'text-surface-400 hover:bg-surface-100 hover:text-amber-500 dark:hover:bg-surface-700',
                        )}
                        title={conv?.is_flagged ? 'Unflag' : 'Flag'}
                      >
                        <Flag className="h-4 w-4" style={conv?.is_flagged ? { fill: 'currentColor' } : undefined} />
                      </button>
                      <button
                        onClick={() => selectedPhone && togglePinMut.mutate(selectedPhone)}
                        className={cn(
                          'flex h-8 w-8 items-center justify-center rounded-lg transition-colors',
                          conv?.is_pinned
                            ? 'bg-primary-50 text-primary-500 hover:bg-primary-100 dark:bg-primary-900/20 dark:hover:bg-primary-900/30'
                            : 'text-surface-400 hover:bg-surface-100 hover:text-primary-500 dark:hover:bg-surface-700',
                        )}
                        title={conv?.is_pinned ? 'Unpin' : 'Pin'}
                      >
                        <Pin className="h-4 w-4" style={conv?.is_pinned ? { fill: 'currentColor' } : undefined} />
                      </button>
                      <button
                        onClick={() => {
                          if (selectedPhone) {
                            markReadMutation.mutate(selectedPhone);
                            toast.success('Marked as resolved');
                          }
                        }}
                        className="flex h-8 items-center gap-1 rounded-lg px-2 text-surface-400 transition-colors hover:bg-green-50 hover:text-green-600 dark:hover:bg-green-900/20 dark:hover:text-green-400"
                        title="Mark resolved (read)"
                      >
                        <CheckCheck className="h-4 w-4" />
                        <span className="text-xs font-medium">Resolved</span>
                      </button>
                      {/* ENR-SMS7: Archive button */}
                      <button
                        onClick={() => selectedPhone && toggleArchiveMut.mutate(selectedPhone)}
                        className={cn(
                          'flex h-8 items-center gap-1 rounded-lg px-2 transition-colors',
                          conv?.is_archived
                            ? 'bg-surface-100 text-surface-600 hover:bg-surface-200 dark:bg-surface-700 dark:text-surface-300'
                            : 'text-surface-400 hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-700 dark:hover:text-surface-300',
                        )}
                        title={conv?.is_archived ? 'Unarchive conversation' : 'Archive conversation'}
                      >
                        <Archive className="h-4 w-4" />
                        <span className="text-xs font-medium">{conv?.is_archived ? 'Unarchive' : 'Archive'}</span>
                      </button>
                      {/* Click-to-call */}
                      <button
                        onClick={async () => {
                          if (!selectedPhone) return;
                          try {
                            await voiceApi.call({ to: `+1${selectedPhone}`, mode: 'bridge' });
                            toast.success('Calling...');
                          } catch { toast.error('Call failed'); }
                        }}
                        className="flex h-8 items-center gap-1 rounded-lg px-2 text-surface-400 transition-colors hover:bg-green-50 hover:text-green-600 dark:hover:bg-green-900/20 dark:hover:text-green-400"
                        title="Call customer"
                      >
                        <Phone className="h-4 w-4" />
                        <span className="text-xs font-medium">Call</span>
                      </button>
                      {/* Set Reminder */}
                      <div className="relative">
                        <button
                          onClick={() => setShowReminder(!showReminder)}
                          className={cn(
                            'flex h-8 items-center gap-1 rounded-lg px-2 transition-colors',
                            showReminder
                              ? 'bg-indigo-50 text-indigo-600 dark:bg-indigo-900/20 dark:text-indigo-400'
                              : 'text-surface-400 hover:bg-indigo-50 hover:text-indigo-600 dark:hover:bg-indigo-900/20 dark:hover:text-indigo-400',
                          )}
                          title="Set reminder"
                        >
                          <Bell className="h-4 w-4" />
                          <span className="text-xs font-medium">Remind</span>
                        </button>
                        {showReminder && selectedPhone && (
                          <div className="absolute right-0 top-full z-20 mt-1 w-48 rounded-xl border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                            <div className="p-1.5">
                              <p className="px-2 py-1 text-[10px] font-semibold uppercase tracking-wider text-surface-400">Follow up in</p>
                              {[
                                { label: '1 hour', ms: 3600_000 },
                                { label: '4 hours', ms: 14400_000 },
                                { label: 'Tomorrow', ms: 86400_000 },
                                { label: '3 days', ms: 259200_000 },
                              ].map((opt) => (
                                <button
                                  key={opt.label}
                                  onClick={() => handleSetReminder(selectedPhone!, opt.label, opt.ms)}
                                  className="flex w-full items-center gap-2 rounded-lg px-2 py-1.5 text-sm text-surface-700 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-700"
                                >
                                  <Clock className="h-3.5 w-3.5 text-surface-400" />
                                  {opt.label}
                                </button>
                              ))}
                            </div>
                          </div>
                        )}
                      </div>
                    </>
                  );
                })()}
              </div>
            </div>

            {/* Thread search bar (COM-2) */}
            <ThreadSearchBar messages={messages} scrollContainerRef={messagesContainerRef} />

            {/* Messages area */}
            <div ref={messagesContainerRef} className="flex-1 overflow-y-auto px-4 py-4">
              {msgLoading ? (
                <div className="flex items-center justify-center py-12">
                  <div className="h-6 w-6 animate-spin rounded-full border-2 border-primary-500 border-t-transparent" />
                </div>
              ) : messages.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-surface-400">
                  <MessageSquare className="mb-2 h-8 w-8" />
                  <p className="text-sm">No messages yet. Send the first one!</p>
                </div>
              ) : (
                <div className="space-y-4">
                  {groupedMessages.map((group) => (
                    <div key={group.date}>
                      {/* Date separator */}
                      <div className="mb-3 flex items-center gap-3">
                        <div className="flex-1 border-t border-surface-200 dark:border-surface-700" />
                        <span className="rounded-full bg-surface-100 px-3 py-0.5 text-xs font-medium text-surface-500 dark:bg-surface-800 dark:text-surface-400">
                          {group.date}
                        </span>
                        <div className="flex-1 border-t border-surface-200 dark:border-surface-700" />
                      </div>
                      {/* Messages */}
                      <div className="space-y-2">
                        {group.messages.map((msg) => (
                          <div
                            key={msg.id}
                            className={cn(
                              'flex',
                              msg.direction === 'outbound' ? 'justify-end' : 'justify-start',
                            )}
                          >
                            <div
                              className={cn(
                                'max-w-[75%] rounded-2xl px-4 py-2',
                                msg.direction === 'outbound'
                                  ? 'bg-primary-600 text-white'
                                  : 'bg-white text-surface-900 shadow-sm dark:bg-surface-700 dark:text-surface-100',
                              )}
                            >
                              {/* MMS media images */}
                              {msg.media_local_paths && (() => {
                                try {
                                  const paths = JSON.parse(msg.media_local_paths) as string[];
                                  return paths.length > 0 ? (
                                    <div className="flex flex-wrap gap-1 mb-1">
                                      {paths.map((p: string, idx: number) => (
                                        <a key={idx} href={p} target="_blank" rel="noopener noreferrer">
                                          <img src={p} alt="MMS" className="max-w-[200px] max-h-[200px] rounded-lg object-cover" loading="lazy" />
                                        </a>
                                      ))}
                                    </div>
                                  ) : null;
                                } catch { return null; }
                              })()}
                              {msg.media_urls && !msg.media_local_paths && (() => {
                                try {
                                  const urls = JSON.parse(msg.media_urls) as string[];
                                  return urls.length > 0 ? (
                                    <div className="flex flex-wrap gap-1 mb-1">
                                      {urls.map((u: string, idx: number) => (
                                        <a key={idx} href={u} target="_blank" rel="noopener noreferrer">
                                          <img src={u} alt="MMS" className="max-w-[200px] max-h-[200px] rounded-lg object-cover" loading="lazy" />
                                        </a>
                                      ))}
                                    </div>
                                  ) : null;
                                } catch { return null; }
                              })()}
                              {msg.message_type === 'mms' && !msg.message ? null : (
                                <p data-msg-text className="whitespace-pre-wrap text-sm leading-relaxed">{msg.message}</p>
                              )}
                              <div className={cn(
                                'mt-1 flex items-center gap-1',
                                msg.direction === 'outbound' ? 'justify-end' : 'justify-start',
                              )}>
                                <span className={cn(
                                  'text-[10px]',
                                  msg.direction === 'outbound' ? 'text-blue-200' : 'text-surface-400',
                                )}>
                                  {formatMessageTime(msg.created_at)}
                                  {msg.sender_name && msg.direction === 'outbound' && (
                                    <> &middot; {msg.sender_name}</>
                                  )}
                                </span>
                                {msg.direction === 'outbound' && <StatusIcon status={msg.status} deliveredAt={msg.delivered_at} error={msg.error} />}
                                {msg.status === 'scheduled' && msg.send_at && (
                                  <span className="text-[10px] text-amber-500">
                                    Scheduled: {new Date(msg.send_at).toLocaleString()}
                                  </span>
                                )}
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    </div>
                  ))}
                </div>
              )}
              <div ref={messagesEndRef} />
            </div>

            {/* Compose bar */}
            <div className="border-t border-surface-200 bg-white px-4 py-3 dark:border-surface-700 dark:bg-surface-800">
              {/* Multi-segment SMS warning */}
              {segmentCount > 1 && (
                <div className="mb-2 rounded-lg bg-amber-50 px-3 py-1.5 text-xs text-amber-700 dark:bg-amber-900/20 dark:text-amber-400">
                  Message will be sent as {segmentCount} segments ({charCount} characters)
                </div>
              )}
              {/* Attached media preview */}
              {attachedMedia && (
                <div className="mb-2 flex items-center gap-2 rounded-lg bg-surface-100 dark:bg-surface-700 p-2">
                  <img src={attachedMedia.preview} alt="Attached" className="h-16 w-16 rounded-lg object-cover" />
                  <div className="flex-1 text-xs text-surface-500">Image attached (MMS)</div>
                  <button onClick={() => setAttachedMedia(null)} className="text-surface-400 hover:text-red-500"><X className="h-4 w-4" /></button>
                </div>
              )}
              <div className="flex items-end gap-2">
                {/* Image attach button */}
                <input ref={imageInputRef} type="file" accept="image/jpeg,image/png,image/gif,image/webp" className="hidden" onChange={handleImageSelect} />
                <button
                  onClick={() => imageInputRef.current?.click()}
                  disabled={uploading}
                  className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border border-surface-300 text-surface-500 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-400 dark:hover:bg-surface-700 disabled:opacity-50 transition-colors"
                  title="Attach image (MMS)"
                >
                  {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Paperclip className="h-4 w-4" />}
                </button>
                {/* Template button */}
                <div className="relative" data-template-picker>
                  <button
                    ref={templateBtnRef}
                    onClick={() => setShowTemplates(!showTemplates)}
                    className={cn(
                      'flex h-10 w-10 shrink-0 items-center justify-center rounded-xl border transition-colors',
                      showTemplates
                        ? 'border-primary-400 bg-primary-50 text-primary-600 dark:border-primary-600 dark:bg-primary-900/20 dark:text-primary-400'
                        : 'border-surface-300 text-surface-500 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-400 dark:hover:bg-surface-700',
                    )}
                    title="Insert template"
                  >
                    <FileText className="h-4 w-4" />
                  </button>
                  {showTemplates && (
                    <TemplatePicker
                      onSelect={handleTemplateSelect}
                      onInsertVariable={(variable) => {
                        const el = composeRef.current;
                        if (el) {
                          const start = el.selectionStart ?? composeText.length;
                          const end = el.selectionEnd ?? composeText.length;
                          const updated = composeText.slice(0, start) + variable + composeText.slice(end);
                          setComposeText(updated);
                          // Restore cursor after variable
                          setTimeout(() => {
                            el.focus();
                            el.setSelectionRange(start + variable.length, start + variable.length);
                          }, 50);
                        } else {
                          setComposeText(composeText + variable);
                        }
                      }}
                      onClose={() => setShowTemplates(false)}
                    />
                  )}
                </div>

                {/* Text area */}
                <div className="relative flex-1">
                  <textarea
                    ref={composeRef}
                    value={composeText}
                    onChange={(e) => setComposeText(e.target.value)}
                    onKeyDown={(e) => {
                      if (e.key === 'Enter' && !e.shiftKey) {
                        e.preventDefault();
                        handleSend();
                      }
                    }}
                    placeholder="Type a message..."
                    rows={1}
                    className="max-h-24 min-h-[2.5rem] w-full resize-none rounded-xl border border-surface-300 px-4 py-2.5 pr-16 text-sm text-surface-900 placeholder:text-surface-400 focus:border-primary-400 focus:outline-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                    style={{ height: 'auto' }}
                    onInput={(e) => {
                      const el = e.target as HTMLTextAreaElement;
                      el.style.height = 'auto';
                      el.style.height = Math.min(el.scrollHeight, 96) + 'px';
                    }}
                  />
                  <span className={cn(
                    'absolute bottom-1.5 right-3 text-[10px]',
                    charCount > 160 ? 'text-amber-500' : 'text-surface-400',
                  )}>
                    {hasSmsDraft && <span className="mr-2 text-green-500">Draft saved</span>}
                    {charCount}/160{segmentCount > 1 && ` (${segmentCount} msgs)`}
                  </span>
                </div>

                {/* Schedule toggle button */}
                <div className="relative">
                  <button
                    onClick={() => {
                      setShowSchedulePicker((v) => !v);
                      if (showSchedulePicker) setScheduledAt('');
                    }}
                    className={cn(
                      'flex h-10 shrink-0 items-center justify-center rounded-xl border px-2.5 text-sm transition-colors',
                      scheduledAt
                        ? 'border-amber-400 bg-amber-50 text-amber-700 dark:border-amber-600 dark:bg-amber-900/20 dark:text-amber-400'
                        : 'border-surface-300 text-surface-500 hover:bg-surface-100 dark:border-surface-600 dark:text-surface-400 dark:hover:bg-surface-700',
                    )}
                    title={scheduledAt ? `Scheduled: ${new Date(scheduledAt).toLocaleString()}` : 'Schedule message'}
                  >
                    <CalendarClock className="h-4 w-4" />
                  </button>
                  {showSchedulePicker && (
                    <div data-schedule-picker className="absolute bottom-12 right-0 z-50 rounded-lg border border-surface-200 bg-white p-3 shadow-lg dark:border-surface-600 dark:bg-surface-800 min-w-[260px]">
                      <label className="mb-1.5 block text-xs font-medium text-surface-600 dark:text-surface-300">
                        Send at
                      </label>
                      <input
                        type="datetime-local"
                        value={scheduledAt}
                        min={new Date(Date.now() + 60000).toISOString().slice(0, 16)}
                        onChange={(e) => setScheduledAt(e.target.value)}
                        className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 focus:border-primary-400 focus:outline-none dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                      />
                      {scheduledAt && (
                        <div className="mt-2 flex items-center justify-between">
                          <span className="text-xs text-amber-600 dark:text-amber-400">
                            {new Date(scheduledAt).toLocaleString()}
                          </span>
                          <button
                            onClick={() => { setScheduledAt(''); setShowSchedulePicker(false); }}
                            className="text-xs text-red-500 hover:text-red-700"
                          >
                            Clear
                          </button>
                        </div>
                      )}
                    </div>
                  )}
                </div>

                {/* Send button */}
                <button
                  onClick={handleSend}
                  disabled={(!composeText.trim() && !attachedMedia) || sendMutation.isPending}
                  className={cn(
                    'flex h-10 shrink-0 items-center justify-center gap-1.5 rounded-xl px-4 text-sm font-medium text-white transition-colors disabled:opacity-50',
                    scheduledAt
                      ? 'bg-amber-600 hover:bg-amber-700'
                      : 'bg-primary-600 hover:bg-primary-700',
                  )}
                  title={scheduledAt ? `Schedule for ${new Date(scheduledAt).toLocaleString()}` : 'Send message'}
                >
                  {sendMutation.isPending ? (
                    <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                  ) : scheduledAt ? (
                    <><CalendarClock className="h-4 w-4" /> Schedule</>
                  ) : (
                    <><Send className="h-4 w-4" /> Send</>
                  )}
                </button>
              </div>
            </div>
          </>
        )}
      </div>
      )}

      {/* ── Right Panel: Customer & Tickets ── */}
      {selectedPhone && threadCustomer && (
        <div className="hidden xl:flex w-[280px] flex-col border-l border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
          {/* Customer header */}
          <div className="border-b border-surface-200 px-4 py-4 dark:border-surface-700">
            <div className="flex items-center gap-3">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary-100 text-sm font-semibold text-primary-700 dark:bg-primary-900/30 dark:text-primary-400">
                {threadCustomer.first_name?.[0] || ''}{threadCustomer.last_name?.[0] || ''}
              </div>
              <div className="min-w-0">
                <Link
                  to={`/customers/${threadCustomer.id}`}
                  className="block truncate text-sm font-semibold text-surface-900 hover:text-primary-600 dark:text-surface-100"
                >
                  {threadCustomer.first_name} {threadCustomer.last_name}
                </Link>
                <a
                  href={`tel:+1${selectedPhone}`}
                  className="block text-xs text-surface-500 hover:text-primary-600"
                >
                  {formatPhone(selectedPhone)}
                </a>
              </div>
            </div>
          </div>

          {/* Tickets section */}
          <div className="flex-1 overflow-y-auto">
            <div className="px-4 py-3">
              <h3 className="text-xs font-semibold uppercase tracking-wider text-surface-400 mb-2">Tickets</h3>
              {customerTicketsLoading ? (
                <div className="flex items-center justify-center py-6">
                  <Loader2 className="h-5 w-5 animate-spin text-primary-500" />
                </div>
              ) : customerTickets.length === 0 ? (
                <p className="text-xs text-surface-400 py-4 text-center">No tickets found</p>
              ) : (
                <div className="space-y-2">
                  {customerTickets.map((t: any) => (
                    <Link
                      key={t.id}
                      to={`/tickets/${t.id}`}
                      className="block rounded-lg border border-surface-100 p-2.5 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-700/50 transition-colors"
                    >
                      <div className="flex items-center justify-between mb-1">
                        <span className="text-xs font-semibold text-primary-600 dark:text-primary-400">
                          {t.order_id || `T-${String(t.id).padStart(4, '0')}`}
                        </span>
                        <span
                          className="inline-flex items-center gap-1 rounded-full px-1.5 py-0.5 text-[9px] font-medium"
                          style={{
                            backgroundColor: `${t.status_color || '#888'}18`,
                            color: t.status_color || '#888',
                          }}
                        >
                          <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: t.status_color || '#888' }} />
                          {t.status_name || '--'}
                        </span>
                      </div>
                      {(t.device_name || t.devices?.[0]?.name) && (
                        <p className="text-xs text-surface-600 dark:text-surface-300 truncate">
                          {t.device_name || t.devices?.[0]?.name}
                        </p>
                      )}
                      <p className="text-[10px] text-surface-400 mt-0.5">
                        {t.created_at ? formatTime(t.created_at) : '--'}
                      </p>
                    </Link>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Quick actions */}
          <div className="border-t border-surface-200 px-4 py-3 dark:border-surface-700">
            <Link
              to={`/tickets/new?customer_id=${threadCustomer.id}`}
              className="flex w-full items-center justify-center gap-1.5 rounded-lg bg-primary-600 px-3 py-2 text-xs font-medium text-white hover:bg-primary-700 transition-colors"
            >
              <Plus className="h-3.5 w-3.5" />
              New Ticket
            </Link>
          </div>
        </div>
      )}

      {/* New message modal */}
      {showNewMessage && (
        <NewMessageModal
          onClose={() => setShowNewMessage(false)}
          onStart={(phone) => {
            setSelectedPhone(phone);
            setShowNewMessage(false);
          }}
        />
      )}
    </div>
  );
}
