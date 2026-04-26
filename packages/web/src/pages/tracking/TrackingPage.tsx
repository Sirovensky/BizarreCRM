import { useState, useEffect, useRef } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import {
  Search, Phone, Loader2, AlertCircle, MapPin, Clock, PhoneCall,
  ChevronRight, FileText, MessageSquare, Send, CheckCircle2,
  DollarSign, ArrowLeft,
} from 'lucide-react';
import axios from 'axios';
import { safeColor } from '../../utils/safeColor';
// WEB-FM-008 (Fixer-B20 2026-04-25): replace the local `formatDate(iso)` (which
// hardcoded `en-US` and was actually shaped as date+time) with the shared
// `formatDateTime` helper from `utils/format`. Same shape, locale-aware.
import { formatDateTime } from '@/utils/format';
// WEB-FV-006 (Fixer-B21 2026-04-25): the embed-config fetch is best-effort
// (fallback values render fine), but the previous `.catch(() => {})` lost
// every signal that the public tracking surface was failing. Route through
// `safeRunAsync` so a Sentry breadcrumb is attached when the customer-facing
// endpoint goes down — ops still get the alert, the user still sees the
// fallback header copy.
import { safeRunAsync } from '@/utils/safeRun';

// ---------- Types ----------
interface TrackingTicket {
  order_id: string;
  status: { name: string; color: string; is_closed: boolean };
  customer_first_name: string | null;
  devices: { name: string; type: string | null }[];
  created_at: string;
  updated_at: string;
  tracking_token: string | null;
}

interface PortalDevice {
  name: string;
  type: string | null;
  status: string | null;
  due_on: string | null;
  notes: string | null;
}

interface HistoryEntry {
  action: string;
  description: string | null;
  old_value: string | null;
  new_value: string | null;
  created_at: string;
}

interface PortalMessage {
  id: number;
  content: string;
  type: string;
  created_at: string;
  author: string | null;
}

interface InvoiceSummary {
  order_id: string;
  status: string;
  subtotal: number;
  discount: number;
  tax: number;
  total: number;
  amount_paid: number;
  amount_due: number;
  line_items?: { description: string; quantity: number; unit_price: number; total: number }[];
  payments?: { amount: number; method: string; date: string }[];
}

interface PortalData {
  order_id: string;
  status: { name: string; color: string; is_closed: boolean };
  customer_first_name: string | null;
  due_on: string | null;
  created_at: string;
  updated_at: string;
  devices: PortalDevice[];
  history: HistoryEntry[];
  messages: PortalMessage[];
  invoice: InvoiceSummary | null;
  store: Record<string, string>;
}

// ---------- Status progress mapping ----------
const STATUS_PROGRESS: Record<string, number> = {
  'open': 0,
  'in progress': 1,
  'waiting for parts': 1,
  'waiting on customer': 1,
  'on hold': 1,
  'parts arrived': 2,
  'warranty repair': 1,
  'closed': 3,
  'cancelled': -1,
};

function getProgress(statusName: string): number {
  return STATUS_PROGRESS[statusName.toLowerCase()] ?? 1;
}

const PROGRESS_STEPS = ['Received', 'In Progress', 'Ready', 'Complete'];

// ---------- Component ----------
export function TrackingPage() {
  const { orderId: routeOrderId } = useParams<{ orderId: string }>();
  const [searchParams] = useSearchParams();
  const tokenParam = searchParams.get('token');

  const [phoneInput, setPhoneInput] = useState('');
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [results, setResults] = useState<TrackingTicket[]>([]);
  const [portalData, setPortalData] = useState<PortalData | null>(null);
  const [activeTab, setActiveTab] = useState<'status' | 'timeline' | 'invoice' | 'message'>('status');
  const [messageText, setMessageText] = useState('');
  const [sendingMessage, setSendingMessage] = useState(false);
  const [messageSent, setMessageSent] = useState(false);
  const [fullInvoice, setFullInvoice] = useState<InvoiceSummary | null>(null);
  const [loadingInvoice, setLoadingInvoice] = useState(false);
  const [storeConfig, setStoreConfig] = useState<Record<string, string> | null>(null);

  const messageInputRef = useRef<HTMLTextAreaElement>(null);

  // Load store config on mount (public endpoint, no auth needed)
  useEffect(() => {
    // WEB-FV-006 (Fixer-B21 2026-04-25): swap the silent `.catch(() => {})` for
    // `safeRunAsync` so a breadcrumb fires when the public embed-config call
    // is down. Tracking is the unauthenticated customer surface; previously
    // a degraded `/portal/embed/config` was invisible to ops.
    void safeRunAsync(async () => {
      const res = await axios.get('/api/v1/portal/embed/config');
      const cfg = res.data?.data;
      if (cfg) {
        setStoreConfig({
          store_name: cfg.name || '',
          store_phone: cfg.phone || '',
          store_address: cfg.address || '',
          store_hours: cfg.hours || '',
        });
      }
    }, { tag: 'tracking:embedConfig', level: 'warning' });
  }, []);

  // Auto-search if URL has orderId+token or just token.
  //
  // FA-M13: ticket-number-only lookup is intentionally unavailable in this
  // public form. The tracking portal endpoints require a token that the
  // server scopes to the specific ticket, so without it we cannot safely
  // resolve a ticket by its user-visible order ID (guessable). If a future
  // pass adds order-ID lookup, pair it with a second factor (phone last 4
  // or email) and hit a new server endpoint — do NOT call the token-scoped
  // endpoints with a stub token.
  useEffect(() => {
    if (tokenParam && routeOrderId) {
      loadPortalData(routeOrderId, tokenParam);
    } else if (tokenParam) {
      lookupByToken(tokenParam);
    }
  }, [routeOrderId, tokenParam]); // intentional: functions are stable component-scoped defs

  async function lookupByToken(token: string) {
    setLoading(true);
    setError('');
    setResults([]);
    setPortalData(null);
    try {
      const res = await axios.get(`/api/v1/track/token/${encodeURIComponent(token)}`);
      const ticket = res.data.data as TrackingTicket;
      setResults([ticket]);
      // Now load full portal data
      if (ticket.tracking_token) {
        await loadPortalData(ticket.order_id, ticket.tracking_token);
      }
    } catch {
      setError('Invalid or expired tracking link.');
    } finally {
      setLoading(false);
    }
  }

  async function loadPortalData(orderId: string, token: string) {
    setLoading(true);
    setError('');
    try {
      const res = await axios.get(`/api/v1/track/portal/${encodeURIComponent(orderId)}?token=${encodeURIComponent(token)}`);
      setPortalData(res.data.data as PortalData);
      setActiveTab('status');
    } catch (err: any) {
      if (err.response?.status === 404) {
        // FA-M13: public form only supports phone lookup — guide the user
        // back to that flow instead of referencing a ticket number they
        // cannot enter here.
        setError('We could not find your repair. Please re-open the tracking link from your receipt or search by phone number.');
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  async function lookupByPhone(phone: string) {
    setLoading(true);
    setError('');
    setResults([]);
    setPortalData(null);
    try {
      const res = await axios.post('/api/v1/track/lookup', { phone });
      const tickets = res.data.data as TrackingTicket[];
      if (tickets.length === 0) {
        setError('No tickets found for that phone number.');
      } else if (tickets.length === 1 && tickets[0].tracking_token) {
        setResults(tickets);
        await loadPortalData(tickets[0].order_id, tickets[0].tracking_token);
      } else {
        setResults(tickets);
      }
    } catch (err: any) {
      // WEB-FC-024: surface server's Retry-After header on 429s
      if (err?.response?.status === 429) {
        const raw = err.response.headers?.['retry-after'] ?? err.response.headers?.['Retry-After'];
        const secs = raw ? parseInt(String(raw), 10) : NaN;
        if (Number.isFinite(secs) && secs > 0) {
          const human = secs < 60 ? `${secs}s` : `${Math.ceil(secs / 60)} minute${Math.ceil(secs / 60) === 1 ? '' : 's'}`;
          setError(`Too many attempts. Please try again in ${human}.`);
        } else {
          setError('Too many attempts. Please try again later.');
        }
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!phoneInput.trim() || phoneInput.replace(/\D/g, '').length < 4) return;
    lookupByPhone(phoneInput.trim());
  }

  function selectTicketFromList(ticket: TrackingTicket) {
    if (ticket.tracking_token) {
      loadPortalData(ticket.order_id, ticket.tracking_token);
    }
  }

  async function sendMessage() {
    if (!portalData || !messageText.trim()) return;
    const token = tokenParam || results[0]?.tracking_token;
    if (!token) return;

    setSendingMessage(true);
    try {
      await axios.post(
        `/api/v1/track/portal/${encodeURIComponent(portalData.order_id)}/message?token=${encodeURIComponent(token)}`,
        { content: messageText.trim() }
      );
      setMessageText('');
      setMessageSent(true);
      setTimeout(() => setMessageSent(false), 4000);
      // Reload portal data to get updated messages
      await loadPortalData(portalData.order_id, token);
    } catch {
      setError('Failed to send message. Please try again.');
    } finally {
      setSendingMessage(false);
    }
  }

  async function loadFullInvoice() {
    if (!portalData || fullInvoice) return;
    const token = tokenParam || results[0]?.tracking_token;
    if (!token) return;
    setLoadingInvoice(true);
    try {
      const res = await axios.get(
        `/api/v1/track/portal/${encodeURIComponent(portalData.order_id)}/invoice?token=${encodeURIComponent(token)}`
      );
      if (res.data.data) {
        setFullInvoice(res.data.data as InvoiceSummary);
      }
    } catch { /* ignore */ }
    finally { setLoadingInvoice(false); }
  }

  function goBack() {
    setPortalData(null);
    setFullInvoice(null);
    if (results.length <= 1) {
      setResults([]);
    }
  }

  const storeName = portalData?.store?.store_name || storeConfig?.store_name || 'Repair Shop';
  const storePhone = portalData?.store?.store_phone || storeConfig?.store_phone || '';
  const storeAddress = portalData?.store?.store_address || storeConfig?.store_address || '';
  const storeCity = portalData?.store?.store_city || '';
  const storeState = portalData?.store?.store_state || '';
  const storeZip = portalData?.store?.store_zip || '';
  const storeHours = portalData?.store?.store_hours || storeConfig?.store_hours || '';

  return (
    <div className="min-h-screen bg-gradient-to-br from-slate-50 to-primary-50 dark:from-surface-950 dark:to-surface-900 flex flex-col">
      {/* Header */}
      <header className="bg-white dark:bg-surface-900 shadow-sm border-b border-slate-200 dark:border-surface-700">
        <div className="max-w-2xl mx-auto px-4 py-5 text-center">
          <h1 className="text-2xl font-bold text-slate-800 dark:text-surface-100">{storeName}</h1>
          <p className="text-sm text-slate-500 dark:text-surface-400 mt-1">Repair Status Portal</p>
        </div>
      </header>

      {/* Main */}
      <main className="flex-1 max-w-2xl w-full mx-auto px-4 py-8">

        {/* WEB-FL-020: deprecation notice for the legacy /track/:orderId
            deep-link without a token. Old SMS receipts hit this URL; we
            need to nudge customers toward the tokenized link before the
            server route can be retired. */}
        {routeOrderId && !tokenParam && !portalData && (
          <div className="bg-amber-50 dark:bg-amber-900/30 border border-amber-200 dark:border-amber-700 text-amber-800 dark:text-amber-200 rounded-xl p-4 mb-6 flex items-start gap-3">
            <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0" />
            <p className="text-sm">
              This older tracking link is being retired. Please look for a newer
              tracking link in your most recent receipt or SMS, or use the
              phone-number lookup below to find your repair.
            </p>
          </div>
        )}

        {/* Portal view — when we have full portal data */}
        {portalData ? (
          <div className="space-y-4">
            {/* Back / search again */}
            <button
              type="button"
              onClick={goBack}
              className="text-sm text-primary-600 hover:text-primary-800 flex items-center gap-1 mb-2"
            >
              <ArrowLeft className="w-4 h-4" /> Search again
            </button>

            {/* Status card */}
            <div className="bg-white dark:bg-surface-900 rounded-xl shadow-sm border border-slate-200 dark:border-surface-700 overflow-hidden">
              <div className="px-5 py-5 border-b border-slate-100 dark:border-surface-800">
                <div className="flex items-start justify-between">
                  <div>
                    <h2 className="text-xl font-bold font-mono text-slate-800 dark:text-surface-100">{portalData.order_id}</h2>
                    {portalData.customer_first_name && (
                      <p className="text-sm text-slate-500 dark:text-surface-400 mt-0.5">Hello, {portalData.customer_first_name}</p>
                    )}
                  </div>
                  <span
                    className="px-3 py-1.5 rounded-full text-sm font-semibold text-white"
                    style={{ backgroundColor: safeColor(portalData.status.color) }}
                  >
                    {portalData.status.name}
                  </span>
                </div>
              </div>

              {/* Progress bar */}
              {portalData.status.name.toLowerCase() !== 'cancelled' && (
                <div className="px-5 py-5 border-b border-slate-100 dark:border-surface-800 bg-slate-50/50 dark:bg-surface-800/40">
                  <ProgressIndicator step={getProgress(portalData.status.name)} />
                </div>
              )}

              {/* Estimated completion */}
              {portalData.due_on && !portalData.status.is_closed && (
                <div className="px-5 py-3 border-b border-slate-100 dark:border-surface-800 bg-primary-50/50 dark:bg-primary-900/20">
                  <p className="text-sm text-primary-700 dark:text-primary-300 flex items-center gap-2">
                    <Clock className="w-4 h-4" />
                    Estimated completion: <strong>{formatDateTime(portalData.due_on)}</strong>
                  </p>
                </div>
              )}
            </div>

            {/* Tab navigation */}
            <div className="flex bg-white dark:bg-surface-900 rounded-xl shadow-sm border border-slate-200 dark:border-surface-700 overflow-hidden">
              {[
                { key: 'status' as const, label: 'Details', icon: Search },
                { key: 'timeline' as const, label: 'Timeline', icon: Clock },
                { key: 'invoice' as const, label: 'Invoice', icon: FileText },
                { key: 'message' as const, label: 'Message', icon: MessageSquare },
              ].map(tab => (
                <button
                  key={tab.key}
                  type="button"
                  onClick={() => { setActiveTab(tab.key); if (tab.key === 'invoice') loadFullInvoice(); }}
                  className={`flex-1 py-3 px-2 text-xs sm:text-sm font-medium flex items-center justify-center gap-1.5 transition-colors border-b-2 ${
                    activeTab === tab.key
                      ? 'border-primary-600 text-primary-600 bg-primary-50/50 dark:text-primary-400 dark:bg-primary-900/20'
                      : 'border-transparent text-slate-500 dark:text-surface-400 hover:text-slate-700 dark:hover:text-surface-200 hover:bg-slate-50 dark:hover:bg-surface-800/50'
                  }`}
                >
                  <tab.icon className="w-4 h-4" />
                  {tab.label}
                </button>
              ))}
            </div>

            {/* Tab content */}
            <div className="bg-white dark:bg-surface-900 rounded-xl shadow-sm border border-slate-200 dark:border-surface-700 overflow-hidden">

              {/* Details tab */}
              {activeTab === 'status' && (
                <div className="p-5 space-y-5">
                  {/* Devices */}
                  {portalData.devices.length > 0 && (
                    <div>
                      <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">Device(s) Being Repaired</h3>
                      <div className="space-y-3">
                        {portalData.devices.map((d, i) => (
                          <div key={i} className="bg-slate-50 rounded-lg p-4">
                            <div className="flex items-center justify-between">
                              <span className="font-medium text-slate-800">{d.name || 'Device'}</span>
                              {d.status && (
                                <span className="text-xs px-2 py-1 bg-slate-200 text-slate-600 rounded-full">{d.status}</span>
                              )}
                            </div>
                            {d.type && <p className="text-xs text-slate-500 mt-1">Type: {d.type}</p>}
                            {d.due_on && <p className="text-xs text-slate-500 mt-1">Due: {formatDateTime(d.due_on)}</p>}
                            {d.notes && <p className="text-sm text-slate-600 mt-2">{d.notes}</p>}
                          </div>
                        ))}
                      </div>
                    </div>
                  )}

                  {/* Dates */}
                  <div className="grid grid-cols-2 gap-4">
                    <div>
                      <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1">Checked In</h3>
                      <p className="text-sm text-slate-700 flex items-center gap-1.5">
                        <Clock className="w-3.5 h-3.5 text-slate-400" />
                        {formatDateTime(portalData.created_at)}
                      </p>
                    </div>
                    <div>
                      <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-1">Last Updated</h3>
                      <p className="text-sm text-slate-700 flex items-center gap-1.5">
                        <Clock className="w-3.5 h-3.5 text-slate-400" />
                        {formatDateTime(portalData.updated_at)}
                      </p>
                    </div>
                  </div>
                </div>
              )}

              {/* Timeline tab */}
              {activeTab === 'timeline' && (
                <div className="p-5">
                  <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-4">Status History</h3>
                  {portalData.history.length === 0 ? (
                    <p className="text-sm text-slate-400 py-4 text-center">No status changes recorded yet.</p>
                  ) : (
                    <div className="relative">
                      {/* Vertical line */}
                      <div className="absolute left-3 top-2 bottom-2 w-0.5 bg-slate-200" />
                      <ul className="space-y-4">
                        {portalData.history.map((h, i) => (
                          <li key={i} className="relative pl-9">
                            {/* Dot */}
                            <div className={`absolute left-1.5 top-1 w-3 h-3 rounded-full border-2 ${
                              i === portalData.history.length - 1
                                ? 'bg-primary-500 border-primary-500'
                                : 'bg-white border-slate-300'
                            }`} />
                            <div>
                              <p className="text-sm text-slate-800 font-medium">
                                {formatAction(h)}
                              </p>
                              <p className="text-xs text-slate-400 mt-0.5">{formatDateTime(h.created_at)}</p>
                            </div>
                          </li>
                        ))}
                      </ul>
                    </div>
                  )}
                </div>
              )}

              {/* Invoice tab */}
              {activeTab === 'invoice' && (
                <div className="p-5">
                  {loadingInvoice && (
                    <div className="text-center py-8">
                      <Loader2 className="w-6 h-6 animate-spin text-primary-500 mx-auto" />
                    </div>
                  )}
                  {(() => { const inv = fullInvoice ?? portalData.invoice; return inv ? (
                    <div className="space-y-4">
                      <div className="flex items-center justify-between">
                        <h3 className="text-sm font-semibold text-slate-700">Invoice {inv.order_id}</h3>
                        <InvoiceStatusBadge status={inv.status} />
                      </div>

                      {/* Line items (if we loaded the full invoice) */}
                      {inv.line_items && inv.line_items.length > 0 && (
                        <div className="border border-slate-200 rounded-lg overflow-x-auto">
                          <table className="w-full text-sm">
                            <thead className="bg-slate-50">
                              <tr>
                                <th className="text-left px-3 py-2 text-xs font-semibold text-slate-500">Item</th>
                                <th className="text-right px-3 py-2 text-xs font-semibold text-slate-500">Qty</th>
                                <th className="text-right px-3 py-2 text-xs font-semibold text-slate-500">Total</th>
                              </tr>
                            </thead>
                            <tbody className="divide-y divide-slate-100">
                              {inv.line_items.map((li, i) => (
                                <tr key={i}>
                                  <td className="px-3 py-2 text-slate-700">{li.description || 'Service'}</td>
                                  <td className="px-3 py-2 text-right text-slate-600">{li.quantity}</td>
                                  <td className="px-3 py-2 text-right text-slate-700">${li.total.toFixed(2)}</td>
                                </tr>
                              ))}
                            </tbody>
                          </table>
                        </div>
                      )}

                      {/* Totals */}
                      <div className="bg-slate-50 rounded-lg p-4 space-y-2">
                        <div className="flex justify-between text-sm">
                          <span className="text-slate-500">Subtotal</span>
                          <span className="text-slate-700">${inv.subtotal.toFixed(2)}</span>
                        </div>
                        {inv.discount > 0 && (
                          <div className="flex justify-between text-sm">
                            <span className="text-slate-500">Discount</span>
                            <span className="text-green-600">-${inv.discount.toFixed(2)}</span>
                          </div>
                        )}
                        <div className="flex justify-between text-sm">
                          <span className="text-slate-500">Tax</span>
                          <span className="text-slate-700">${inv.tax.toFixed(2)}</span>
                        </div>
                        <div className="flex justify-between text-sm font-bold border-t border-slate-200 pt-2">
                          <span className="text-slate-800">Total</span>
                          <span className="text-slate-800">${inv.total.toFixed(2)}</span>
                        </div>
                        {inv.amount_paid > 0 && (
                          <div className="flex justify-between text-sm">
                            <span className="text-slate-500">Paid</span>
                            <span className="text-green-600">${inv.amount_paid.toFixed(2)}</span>
                          </div>
                        )}
                        {inv.amount_due > 0 && (
                          <div className="flex justify-between text-sm font-semibold">
                            <span className="text-red-600">Amount Due</span>
                            <span className="text-red-600">${inv.amount_due.toFixed(2)}</span>
                          </div>
                        )}
                      </div>
                    </div>
                  ) : (
                    <div className="py-8 text-center">
                      <DollarSign className="w-10 h-10 text-slate-300 mx-auto mb-3" />
                      <p className="text-sm text-slate-400">No invoice has been generated for this repair yet.</p>
                      <p className="text-xs text-slate-400 mt-1">An invoice will appear here once your repair is complete.</p>
                    </div>
                  ); })()}
                </div>
              )}

              {/* Message tab */}
              {activeTab === 'message' && (
                <div className="p-5 space-y-4">
                  <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider">Send Us a Message</h3>
                  <p className="text-sm text-slate-500">
                    Have a question about your repair? Send us a message and we will get back to you.
                  </p>

                  {/* Previous messages */}
                  {portalData.messages.length > 0 && (
                    <div className="space-y-2">
                      <h4 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mt-4">Your Messages</h4>
                      {portalData.messages.map(m => (
                        <div key={m.id} className="bg-primary-50 rounded-lg p-3">
                          <p className="text-sm text-slate-700">{m.content}</p>
                          <p className="text-xs text-slate-400 mt-1">{formatDateTime(m.created_at)}</p>
                        </div>
                      ))}
                    </div>
                  )}

                  {/* Message form */}
                  {portalData.status.is_closed ? (
                    <div className="bg-slate-50 rounded-lg p-4 text-center">
                      <p className="text-sm text-slate-500">This ticket is closed. Please call us if you need further assistance.</p>
                    </div>
                  ) : (
                    <>
                      <textarea
                        ref={messageInputRef}
                        value={messageText}
                        onChange={(e) => setMessageText(e.target.value)}
                        placeholder="Type your message here..."
                        maxLength={2000}
                        rows={4}
                        className="w-full rounded-lg border border-slate-300 px-4 py-3 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-transparent resize-none"
                      />
                      <div className="flex items-center justify-between">
                        <span className="text-xs text-slate-400">{messageText.length}/2000</span>
                        <button
                          type="button"
                          onClick={sendMessage}
                          disabled={sendingMessage || !messageText.trim()}
                          className="bg-primary-600 hover:bg-primary-700 text-primary-950 px-5 py-2.5 rounded-lg font-medium text-sm transition-colors disabled:opacity-50 flex items-center gap-2"
                        >
                          {sendingMessage ? (
                            <Loader2 className="w-4 h-4 animate-spin" />
                          ) : (
                            <Send className="w-4 h-4" />
                          )}
                          Send
                        </button>
                      </div>
                    </>
                  )}

                  {/* Success toast */}
                  {messageSent && (
                    <div className="bg-green-50 border border-green-200 text-green-700 rounded-lg p-3 flex items-center gap-2">
                      <CheckCircle2 className="w-4 h-4 flex-shrink-0" />
                      <p className="text-sm">Message sent! We will respond as soon as possible.</p>
                    </div>
                  )}
                </div>
              )}
            </div>

            {/* Call us card */}
            {storePhone && (
              <div className="bg-white rounded-xl shadow-sm border border-slate-200 p-5">
                <h3 className="text-xs font-semibold text-slate-400 uppercase tracking-wider mb-3">Need Help?</h3>
                <a
                  href={`tel:${storePhone.replace(/\D/g, '')}`}
                  className="flex items-center gap-3 bg-green-50 hover:bg-green-100 border border-green-200 rounded-lg px-4 py-3 transition-colors"
                >
                  <PhoneCall className="w-5 h-5 text-green-600" />
                  <div>
                    <p className="text-sm font-semibold text-green-800">Call Us</p>
                    <p className="text-sm text-green-600">{storePhone}</p>
                  </div>
                </a>
              </div>
            )}
          </div>
        ) : (
          <>
            {/* Search form */}
            <div className="bg-white dark:bg-surface-900 rounded-xl shadow-sm border border-slate-200 dark:border-surface-700 p-6 mb-6">
              <form onSubmit={handleSubmit} className="flex gap-3">
                <input
                  type="tel"
                  placeholder="Phone number or last 4 digits"
                  value={phoneInput}
                  onChange={(e) => setPhoneInput(e.target.value)}
                  className="flex-1 rounded-lg border border-slate-300 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100 dark:placeholder-surface-400 px-4 py-3 text-base focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:border-transparent"
                  autoFocus
                />
                <button
                  type="submit"
                  disabled={loading}
                  className="bg-primary-600 hover:bg-primary-700 text-primary-950 px-6 py-3 rounded-lg font-medium transition-colors disabled:opacity-50 flex items-center gap-2"
                >
                  {loading ? <Loader2 className="w-5 h-5 animate-spin" /> : <Search className="w-5 h-5" />}
                  Track
                </button>
              </form>
            </div>

            {/* Error */}
            {error && (
              <div className="bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-700 text-red-700 dark:text-red-300 rounded-xl p-4 mb-6 flex items-start gap-3">
                <AlertCircle className="w-5 h-5 mt-0.5 flex-shrink-0" />
                <p className="text-sm">{error}</p>
              </div>
            )}

            {/* Multi-ticket list (phone lookup) */}
            {results.length > 1 && !portalData && (
              <div className="bg-white dark:bg-surface-900 rounded-xl shadow-sm border border-slate-200 dark:border-surface-700 overflow-hidden mb-6">
                <div className="px-5 py-3 border-b border-slate-100 dark:border-surface-800 bg-slate-50 dark:bg-surface-800/50">
                  <h2 className="text-sm font-semibold text-slate-600 dark:text-surface-300">
                    Found {results.length} ticket{results.length > 1 ? 's' : ''}
                  </h2>
                </div>
                <ul className="divide-y divide-slate-100 dark:divide-surface-800">
                  {results.map((t) => (
                    <li key={t.order_id}>
                      <button
                        type="button"
                        onClick={() => selectTicketFromList(t)}
                        className="w-full px-5 py-4 flex items-center justify-between hover:bg-slate-50 dark:hover:bg-surface-800/50 transition-colors text-left"
                      >
                        <div>
                          <span className="font-mono font-semibold text-slate-800 dark:text-surface-100">{t.order_id}</span>
                          <span className="ml-3 text-sm text-slate-500 dark:text-surface-400">
                            {t.devices.map(d => d.name).join(', ') || 'Device'}
                          </span>
                        </div>
                        <div className="flex items-center gap-2">
                          <span
                            className="px-2.5 py-1 rounded-full text-xs font-medium text-white"
                            style={{ backgroundColor: safeColor(t.status.color) }}
                          >
                            {t.status.name}
                          </span>
                          <ChevronRight className="w-4 h-4 text-slate-400 dark:text-surface-500" />
                        </div>
                      </button>
                    </li>
                  ))}
                </ul>
              </div>
            )}

            {/* Loading state */}
            {loading && !results.length && (
              <div className="text-center py-12">
                <Loader2 className="w-8 h-8 animate-spin text-primary-500 mx-auto" />
                <p className="text-sm text-slate-500 dark:text-surface-400 mt-3">Looking up your repair...</p>
              </div>
            )}
          </>
        )}
      </main>

      {/* Footer */}
      <footer className="bg-white dark:bg-surface-900 border-t border-slate-200 dark:border-surface-700 py-6 mt-auto">
        <div className="max-w-2xl mx-auto px-4 text-center space-y-2">
          <p className="text-sm font-medium text-slate-700 dark:text-surface-200">{storeName}</p>
          {(storeAddress || storeCity || storeState) && (
            <p className="text-xs text-slate-500 dark:text-surface-400 flex items-center justify-center gap-1.5">
              <MapPin className="w-3.5 h-3.5" />
              {[storeAddress, storeCity, storeState, storeZip].filter(Boolean).join(', ')}
            </p>
          )}
          {storePhone && (
            <a
              href={`tel:${storePhone.replace(/\D/g, '')}`}
              className="text-xs text-primary-600 dark:text-primary-400 hover:text-primary-800 dark:hover:text-primary-300 flex items-center justify-center gap-1.5"
            >
              <PhoneCall className="w-3.5 h-3.5" />
              {storePhone}
            </a>
          )}
          {storeHours && (
            <p className="text-xs text-slate-400 dark:text-surface-500 mt-2">
              Hours: {storeHours}
            </p>
          )}
        </div>
      </footer>
    </div>
  );
}

// ---------- Helper: format history action for display ----------
function formatAction(h: HistoryEntry): string {
  if (h.action === 'status_change' || h.action === 'status_changed') {
    if (h.old_value && h.new_value) {
      return `Status changed from "${h.old_value}" to "${h.new_value}"`;
    }
    return h.description || 'Status updated';
  }
  if (h.action === 'created' || h.action === 'ticket_created') {
    return 'Ticket created';
  }
  if (h.action === 'customer_message') {
    return 'You sent a message';
  }
  if (h.action === 'note_added') {
    return 'Staff added an update';
  }
  if (h.action === 'assigned') {
    return `Assigned to technician`;
  }
  // Fallback
  return h.description || h.action.replace(/_/g, ' ');
}

// ---------- Invoice status badge ----------
function InvoiceStatusBadge({ status }: { status: string }) {
  // WEB-FC-025: ship dark-mode variants so chips stay legible on dark phone UAs
  const colors: Record<string, string> = {
    paid: 'bg-green-100 text-green-700 dark:bg-green-900/40 dark:text-green-200',
    partial: 'bg-amber-100 text-amber-700 dark:bg-amber-900/40 dark:text-amber-200',
    unpaid: 'bg-red-100 text-red-700 dark:bg-red-900/40 dark:text-red-200',
    draft: 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300',
    voided: 'bg-slate-100 text-slate-400 dark:bg-slate-800 dark:text-slate-500',
  };
  const cls = colors[status.toLowerCase()] || 'bg-slate-100 text-slate-600 dark:bg-slate-800 dark:text-slate-300';
  return (
    <span className={`px-2.5 py-1 rounded-full text-xs font-medium ${cls}`}>
      {status.charAt(0).toUpperCase() + status.slice(1)}
    </span>
  );
}

// ---------- Progress indicator sub-component ----------
function ProgressIndicator({ step }: { step: number }) {
  return (
    <div className="flex items-center justify-between">
      {PROGRESS_STEPS.map((label, i) => {
        const isActive = i <= step;
        const isCurrent = i === step;
        return (
          <div key={label} className="flex-1 flex flex-col items-center relative">
            {i > 0 && (
              <div
                className={`absolute top-3 right-1/2 w-full h-0.5 -translate-y-1/2 ${
                  i <= step ? 'bg-primary-500' : 'bg-slate-200'
                }`}
                style={{ zIndex: 0 }}
              />
            )}
            <div
              className={`relative z-10 w-6 h-6 rounded-full flex items-center justify-center text-xs font-bold transition-colors ${
                isCurrent
                  ? 'bg-primary-600 text-primary-950 ring-4 ring-primary-100'
                  : isActive
                  ? 'bg-primary-500 text-primary-950'
                  : 'bg-slate-200 text-slate-400'
              }`}
            >
              {isActive ? '\u2713' : i + 1}
            </div>
            <span className={`mt-2 text-xs font-medium ${isActive ? 'text-primary-600' : 'text-slate-400'}`}>
              {label}
            </span>
          </div>
        );
      })}
    </div>
  );
}
