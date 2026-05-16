import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate, Link } from 'react-router-dom';
import { Gift, Plus, Search, Loader2, AlertCircle, AlertTriangle, X, ChevronLeft, ChevronRight, Download, Check, Copy, Printer, Mail, WalletCards } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi, customerApi, type PendingGiftCardIssuance } from '@/api/endpoints';
import { formatCurrency as formatCurrencyShared, formatCurrencySymbol, formatDate, formatDateTime, dollarsFromMaybeCents, formatMaybeCents, toLocalDateString } from '@/utils/format';
// WEB-UIUX-998: CSV export for outstanding liability — PII-gated
import { toCsvRow, CSV_BOM } from '@/utils/csv';
import { useHasRole } from '@/hooks/useHasRole';
// WEB-UIUX-1562: focus trap for Issue modal
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';

// ─── Types ────────────────────────────────────────────────────────────────────

interface GiftCard {
  id: number;
  code: string;
  initial_balance: number;
  current_balance: number;
  // WEB-UIUX-1438: widened to include 'expired' status
  status: 'active' | 'used' | 'disabled' | 'expired';
  recipient_name: string | null;
  recipient_email: string | null;
  expires_at: string | null;
  created_at: string;
  // WEB-UIUX-988: server LEFT-JOINs customers so the row can show the
  // linked customer name + deep-link to the profile. Null for unlinked
  // walk-in cards.
  customer_id?: number | null;
  customer_first_name?: string | null;
  customer_last_name?: string | null;
}

interface GiftCardListData {
  cards: GiftCard[];
  summary: {
    total_cards: number;
    total_outstanding: number;
    active_count: number;
  };
  pagination: {
    page: number;
    per_page: number;
    total: number;
    total_pages: number;
  };
}

interface IssueFormState {
  amount: string;
  recipient_name: string;
  recipient_email: string;
  expires_at: string;
  // WEB-UIUX-989: server validates notes up to 1000 chars
  notes: string;
  // WEB-UIUX-1430: optional customer link. server validates against customers
  // table; null means an unlinked walk-in card.
  customer_id: number | null;
  customer_label: string;
}

const PAGE_SIZE = 50;
const SEARCH_DEBOUNCE_MS = 300;

// ─── Helpers ──────────────────────────────────────────────────────────────────

// WEB-UIUX-1014: use shared formatMaybeCents wrapper (was a local
// formatCurrency duplicating GiftCardDetailPage). Single source for the
// cents-vs-dollars heuristic + tenant currency formatter.
const formatCurrency = (amount: number): string => formatMaybeCents(amount);

function maskCode(code: string): string {
  if (!code) return code;
  // WEB-UIUX-1437: show first 4 + last 4 (e.g. "A4F2 **** 9HX2") so a
  // cashier on the phone with a customer ("I think it starts with A4...")
  // can match by prefix OR suffix. Codes are 32-char base32; revealing 8
  // chars total still leaves 24 unknown bits — not a brute-force vector
  // (server enforces per-IP rate limiting on /gift-cards/lookup).
  if (code.length <= 8) return code;
  return `${code.slice(0, 4)} **** ${code.slice(-4)}`;
}

// WEB-UIUX-1012: added default case so unknown future statuses (e.g. 'expired') never return undefined
function statusBadge(status: string): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'used': return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
    case 'disabled': return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300';
    // WEB-UIUX-1438: amber tone for expired cards
    case 'expired': return 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300';
    default: return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
  }
}

function localDateInputValue(date = new Date()): string {
  const offsetMs = date.getTimezoneOffset() * 60_000;
  return new Date(date.getTime() - offsetMs).toISOString().slice(0, 10);
}

function isPastDateInputValue(value: string): boolean {
  return Boolean(value) && value < localDateInputValue();
}

// WEB-UIUX-997: returns true when expires_at is within 30 days from now (and not already expired)
function isExpiringSoon(expiresAt: string | null): boolean {
  if (!expiresAt) return false;
  const exp = new Date(expiresAt).getTime();
  const now = Date.now();
  const msIn30Days = 30 * 24 * 60 * 60 * 1000;
  return exp > now && exp - now <= msIn30Days;
}

// ─── Issue Modal ─────────────────────────────────────────────────────────────

interface IssueModalProps {
  onClose: () => void;
}

function IssueModal({ onClose }: IssueModalProps) {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<IssueFormState>({
    amount: '',
    recipient_name: '',
    recipient_email: '',
    expires_at: '',
    notes: '', // WEB-UIUX-989
    customer_id: null,
    customer_label: '',
  });
  // WEB-UIUX-1430: customer picker — debounced search hits /customers/search
  // when the operator types ≥2 chars; selecting fills customer_id + a
  // human-readable label, and clears the dropdown.
  const [customerSearch, setCustomerSearch] = useState('');
  const [showCustomerDropdown, setShowCustomerDropdown] = useState(false);
  const [debouncedCustomerSearch, setDebouncedCustomerSearch] = useState('');
  useEffect(() => {
    const t = window.setTimeout(() => setDebouncedCustomerSearch(customerSearch.trim()), 250);
    return () => window.clearTimeout(t);
  }, [customerSearch]);
  const { data: customerData } = useQuery({
    queryKey: ['gift-card-issue-customer-search', debouncedCustomerSearch],
    queryFn: ({ signal }) => customerApi.search(debouncedCustomerSearch, signal),
    enabled: debouncedCustomerSearch.length >= 2 && showCustomerDropdown,
    staleTime: 30_000,
  });
  const customerResults: Array<{ id: number; first_name?: string | null; last_name?: string | null; email?: string | null; phone?: string | null }> =
    customerData?.data?.data ?? [];
  const [issuedCode, setIssuedCode] = useState<string | null>(null);
  const todayDateInputValue = localDateInputValue();
  const expiresInPast = isPastDateInputValue(form.expires_at);
  // WEB-UIUX-1562: focus trap — modal always mounted when open
  const dialogRef = useFocusTrap(true);
  useBodyScrollLock(true);

  function update(field: keyof IssueFormState, value: string): void {
    setForm((prev) => ({ ...prev, [field]: value }));
  }

  // WEB-UIUX-1449: global keydown listener so Esc fires even when focus is inside an input
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  const issueMutation = useMutation({
    mutationFn: () => {
      const amount = parseFloat(form.amount);
      if (!Number.isFinite(amount) || amount <= 0) {
        throw new Error('Enter a valid amount');
      }
      if (isPastDateInputValue(form.expires_at)) {
        throw new Error('Expiry date cannot be in the past');
      }
      return giftCardApi.issue({
        amount,
        recipient_name: form.recipient_name || null,
        recipient_email: form.recipient_email || null,
        expires_at: form.expires_at || null,
        // WEB-UIUX-989: include notes (server validates ≤1000 chars)
        notes: form.notes || null,
        // WEB-UIUX-1430: link the card to a customer record so the
        // customer detail page can render "Gift cards held by this
        // customer" without an extra lookup.
        customer_id: form.customer_id,
      });
    },
    onSuccess: (res) => {
      const code: string = (res.data as { data: { code: string } }).data.code;
      setIssuedCode(code);
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
      toast.success('Gift card issued');
    },
    onError: (err: unknown) => {
      // WEB-UIUX-994: surface server-provided message (e.g. "amount exceeds $10,000")
      const msg =
        (err as any)?.response?.data?.message ??
        (err instanceof Error ? err.message : 'Failed to issue gift card');
      toast.error(msg);
    },
  });

  const [codeSavedConfirmed, setCodeSavedConfirmed] = useState(false);

  if (issuedCode) {
    return (
      <div
        className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
        role="presentation"
      >
        {/* WEB-UIUX-1562: focus trap ref on inner dialog */}
        <div
          ref={dialogRef}
          role="dialog"
          aria-modal="true"
          aria-labelledby="gift-card-issued-title"
          className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-md"
        >
          <h2 id="gift-card-issued-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100 mb-1">Gift card issued</h2>
          {/* WEB-UIUX-1016: aria-live region so screen readers announce the issued code */}
          <div role="status" aria-live="polite">
            {/* WEB-UIUX-1544: detail-page reveal is permission-gated
                (gift_cards.issue / gift_cards.redeem) and audited per
                reveal — the code is recoverable for privileged users on
                the card's detail page, not "shown only once". Copy
                updated to reflect reality while still urging the
                cashier to hand it off securely. */}
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
              Save this code now — keep it private and hand it to the recipient through a trusted channel.
            </p>
            <div className="font-mono text-2xl text-center tracking-widest py-4 px-3 bg-surface-100 dark:bg-surface-800 rounded-lg text-surface-900 dark:text-surface-100 select-all mb-4 break-all">
              {/* WEB-UIUX-1005: 4-char groups improve transcription accuracy
                  (Wickelgren chunking research). Render as space-joined groups
                  while keeping select-all so cashier can copy the raw value. */}
              {issuedCode.replace(/(.{4})/g, '$1 ').trim()}
            </div>
          </div>
          <label className="flex items-center gap-2 mb-4 cursor-pointer select-none">
            <input
              type="checkbox"
              checked={codeSavedConfirmed}
              onChange={(e) => setCodeSavedConfirmed(e.target.checked)}
              className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
            />
            <span className="text-sm text-surface-700 dark:text-surface-300">I have saved the code</span>
          </label>
          {/* WEB-UIUX-1004: "I've saved the code" reinforces the consequence of closing */}
          {/* WEB-UIUX-1552: Copy code button for quick clipboard access */}
          {/* WEB-UIUX-1553: 4-action handoff bar so the cashier doesn't
              transcribe the code by hand. Copy / Print / Email (mailto:) /
              Done. Print writes a minimal printable doc to a hidden
              iframe so the browser print dialog opens with just the
              card detail. Email is mailto: — full server-side delivery
              tracked under UIUX-1545 (separate gated feature). */}
          <div className="grid grid-cols-2 gap-2">
            <button
              onClick={() => {
                navigator.clipboard.writeText(issuedCode!).then(() => toast.success('Code copied'));
              }}
              className="flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 text-sm font-medium"
            >
              <Copy className="h-4 w-4" /> Copy code
            </button>
            <button
              onClick={() => {
                const amt = parseFloat(form.amount || '0') || 0;
                const grouped = issuedCode!.replace(/(.{4})/g, '$1 ').trim();
                const recipient = form.recipient_name || 'the recipient';
                const html = `<!doctype html><html><head><title>Gift card ${grouped}</title>
                  <style>body{font-family:system-ui,sans-serif;padding:24px;max-width:480px;margin:0 auto;color:#111}
                  h1{font-size:18px;margin:0 0 8px}
                  .code{font-family:ui-monospace,Menlo,Consolas,monospace;font-size:24px;letter-spacing:2px;background:#f4f4f5;padding:12px 16px;border-radius:8px;margin:16px 0;word-break:break-all}
                  .amt{font-size:32px;font-weight:700;color:#16a34a;margin:8px 0}
                  .meta{font-size:12px;color:#555;line-height:1.6}</style></head>
                  <body>
                    <h1>Gift card receipt</h1>
                    <div class="amt">$${amt.toFixed(2)}</div>
                    <div class="code">${grouped}</div>
                    <div class="meta">
                      Recipient: ${recipient}<br/>
                      ${form.recipient_email ? `Email: ${form.recipient_email}<br/>` : ''}
                      Issued: ${new Date().toLocaleString()}<br/>
                      Save this code — keep it private and hand it to the recipient through a trusted channel.
                    </div>
                  </body></html>`;
                const w = window.open('', '_blank', 'width=520,height=600');
                if (!w) {
                  toast.error('Pop-up blocked — allow pop-ups to print.');
                  return;
                }
                w.document.write(html);
                w.document.close();
                w.focus();
                w.print();
              }}
              className="flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 text-sm font-medium"
            >
              <Printer className="h-4 w-4" /> Print receipt
            </button>
            {form.recipient_email ? (
              <button
                onClick={() => {
                  const amt = parseFloat(form.amount || '0') || 0;
                  const grouped = issuedCode!.replace(/(.{4})/g, '$1 ').trim();
                  const subject = encodeURIComponent(`Your gift card — $${amt.toFixed(2)}`);
                  const body = encodeURIComponent(
                    `Hi ${form.recipient_name || ''},\n\nA $${amt.toFixed(2)} gift card has been issued for you:\n\nCode: ${grouped}\n\nPresent this code in-store to redeem. Keep it private.\n`,
                  );
                  window.location.href = `mailto:${form.recipient_email}?subject=${subject}&body=${body}`;
                }}
                className="flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 text-sm font-medium"
              >
                <Mail className="h-4 w-4" /> Email recipient
              </button>
            ) : (
              <button
                disabled
                title="Add a recipient email when issuing to enable this"
                className="flex items-center justify-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-400 dark:text-surface-500 cursor-not-allowed text-sm font-medium opacity-60"
              >
                <Mail className="h-4 w-4" /> Email recipient
              </button>
            )}
            <button
              onClick={() => { setCodeSavedConfirmed(false); onClose(); }}
              disabled={!codeSavedConfirmed}
              className="px-4 py-2 rounded-lg bg-primary-600 text-on-primary hover:bg-primary-700 text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
            >
              I&apos;ve saved the code
            </button>
          </div>
          {/* WEB-UIUX-1450: "Issue another" shortcut for sales bursts so the
              cashier doesn't have to close + re-open the modal between
              walk-ins. Resets form state to the initial blank values. */}
          <button
            onClick={() => {
              if (!codeSavedConfirmed) {
                toast.error('Confirm you saved the code before issuing another.');
                return;
              }
              setIssuedCode(null);
              setCodeSavedConfirmed(false);
              setForm({ amount: '', recipient_name: '', recipient_email: '', expires_at: '', notes: '', customer_id: null, customer_label: '' });
              setCustomerSearch('');
            }}
            disabled={!codeSavedConfirmed}
            className="mt-3 w-full px-4 py-2 rounded-lg border border-primary-300 text-primary-700 hover:bg-primary-50 dark:border-primary-700 dark:text-primary-300 dark:hover:bg-primary-950/30 text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Issue another
          </button>
        </div>
      </div>
    );
  }

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40"
      onClick={onClose}
      role="presentation"
    >
      {/* WEB-UIUX-1562: focus trap ref on inner dialog */}
      <div
        ref={dialogRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="issue-gift-card-title"
        className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-md"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between mb-5">
          <h2 id="issue-gift-card-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">Issue gift card</h2>
          <button onClick={onClose} className="text-surface-400 hover:text-surface-700 dark:hover:text-surface-200">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="space-y-4">
          <div>
            {/* WEB-UIUX-993: use tenant currency symbol instead of hard-coded "$" */}
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Initial value ({formatCurrencySymbol()}) <span className="text-red-500">*</span>
            </label>
            {/* WEB-UIUX-1554: denomination preset buttons for common amounts */}
            <div className="flex flex-wrap gap-2 mb-2">
              {[25, 50, 100, 200, 500].map((preset) => (
                <button
                  key={preset}
                  type="button"
                  onClick={() => update('amount', String(preset))}
                  className={`px-3 py-1.5 text-sm font-medium rounded-lg border transition-colors ${
                    form.amount === String(preset)
                      ? 'bg-primary-600 text-on-primary border-primary-600'
                      : 'border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800'
                  }`}
                >
                  {formatCurrencyShared(preset)}
                </button>
              ))}
            </div>
            {/* WEB-UIUX-994: max="10000" matches server $10k cap — freeform "Custom" fallback below presets */}
            <input
              // WEB-UIUX-1003: autoFocus matches ReloadModal pattern so cashier on
              // quiet POS does not have to tab-stop through DOM to start typing.
              autoFocus
              type="number"
              // WEB-UIUX-1566: $0.01 gift cards make no business sense; bumped to $1 minimum
              // and whole-dollar step to match real-world denominations.
              min="1"
              max="10000"
              step="1"
              value={form.amount}
              onChange={(e) => update('amount', e.target.value)}
              placeholder="Custom amount"
              aria-describedby="gift-card-amount-hint"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
            {/* WEB-UIUX-1433: surface the server cap inline so $15,000 typos
                are caught before submit, not via opaque toast. */}
            <p id="gift-card-amount-hint" className="mt-1 text-xs text-surface-500 dark:text-surface-400">
              $1 — $10,000 per card
            </p>
          </div>
          {/* WEB-UIUX-1430: link card to a customer record. Optional —
              walk-in gifts can stay unlinked. When set, the customer's
              detail page can render "Gift cards held by this customer". */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Link to customer (optional)
            </label>
            {form.customer_id ? (
              <div className="flex items-center justify-between gap-2 rounded-lg border border-primary-300 bg-primary-50 px-3 py-2 text-sm dark:border-primary-700 dark:bg-primary-900/20">
                <span className="text-surface-800 dark:text-surface-100 truncate">
                  {form.customer_label || `Customer #${form.customer_id}`}
                </span>
                <button
                  type="button"
                  onClick={() => {
                    setForm((p) => ({ ...p, customer_id: null, customer_label: '' }));
                    setCustomerSearch('');
                  }}
                  className="text-xs text-primary-700 hover:underline dark:text-primary-300"
                >
                  Clear
                </button>
              </div>
            ) : (
              <div className="relative">
                <input
                  type="text"
                  value={customerSearch}
                  onChange={(e) => { setCustomerSearch(e.target.value); setShowCustomerDropdown(true); }}
                  onFocus={() => setShowCustomerDropdown(true)}
                  placeholder="Search name / phone / email…"
                  className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500"
                />
                {showCustomerDropdown && debouncedCustomerSearch.length >= 2 && customerResults.length > 0 && (
                  <ul className="absolute z-10 mt-1 max-h-48 w-full overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
                    {customerResults.slice(0, 8).map((c) => {
                      const name = [c.first_name, c.last_name].filter(Boolean).join(' ').trim() || `Customer #${c.id}`;
                      const meta = [c.email, c.phone].filter(Boolean).join(' · ');
                      return (
                        <li key={c.id}>
                          <button
                            type="button"
                            onClick={() => {
                              setForm((p) => ({
                                ...p,
                                customer_id: c.id,
                                customer_label: name,
                                // Pre-fill recipient name / email when blank so
                                // the operator doesn't retype data we already
                                // have on the customer record.
                                recipient_name: p.recipient_name || name,
                                recipient_email: p.recipient_email || (c.email ?? ''),
                              }));
                              setCustomerSearch('');
                              setShowCustomerDropdown(false);
                            }}
                            className="block w-full px-3 py-2 text-left text-sm hover:bg-surface-50 dark:hover:bg-surface-700"
                          >
                            <span className="font-medium text-surface-900 dark:text-surface-100">{name}</span>
                            {meta && <span className="block text-xs text-surface-500 dark:text-surface-400">{meta}</span>}
                          </button>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </div>
            )}
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Recipient name (optional)
            </label>
            <input
              type="text"
              value={form.recipient_name}
              onChange={(e) => update('recipient_name', e.target.value)}
              placeholder="Jane Smith"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Recipient email (optional, stored only)
            </label>
            <input
              type="email"
              value={form.recipient_email}
              onChange={(e) => update('recipient_email', e.target.value)}
              placeholder="jane@example.com"
              // WEB-UIUX-1564: client-side regex validation so garbage emails don't slip through
              // (server validates length only). aria-invalid surfaces inline error to AT.
              aria-invalid={form.recipient_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.recipient_email) ? 'true' : undefined}
              aria-describedby="gift-card-email-hint"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800 aria-[invalid=true]:border-red-500"
            />
            {/* WEB-UIUX-1435: server stores the email but never sends a
                delivery notification. Spell that out so the cashier knows
                to hand the code over in person / via a separate channel. */}
            <p id="gift-card-email-hint" className="mt-1 text-xs text-amber-700 dark:text-amber-300">
              Stored for records only — no email is sent. Hand the code to the recipient yourself.
            </p>
            {form.recipient_email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.recipient_email) && (
              <p className="mt-1 text-xs text-red-600 dark:text-red-400">Enter a valid email address.</p>
            )}
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Expiry date (optional)
            </label>
            <input
              type="date"
              min={todayDateInputValue}
              value={form.expires_at}
              onChange={(e) => update('expires_at', e.target.value)}
              aria-invalid={expiresInPast ? 'true' : undefined}
              aria-describedby={expiresInPast ? 'gift-card-expiry-error' : undefined}
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
            />
            {expiresInPast && (
              <p id="gift-card-expiry-error" className="mt-1 text-xs text-red-600 dark:text-red-400">
                Expiry date cannot be in the past.
              </p>
            )}
          </div>
          {/* WEB-UIUX-989: notes field — server validates ≤1000 chars */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Notes (optional)
            </label>
            <textarea
              value={form.notes}
              onChange={(e) => update('notes', e.target.value)}
              maxLength={1000}
              rows={3}
              placeholder="Internal note about this gift card…"
              className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800 resize-none"
            />
            <p className="mt-0.5 text-xs text-surface-400 text-right">{form.notes.length}/1000</p>
          </div>
        </div>

        <div className="mt-6 flex justify-end gap-3">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          {/* WEB-UIUX-1002: gate on parseFloat > 0 && isFinite, not just !form.amount, to reject "abc" */}
          <button
            onClick={() => issueMutation.mutate()}
            disabled={issueMutation.isPending || !(parseFloat(form.amount) > 0 && Number.isFinite(parseFloat(form.amount))) || expiresInPast}
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none flex items-center gap-2"
          >
            {issueMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Issue gift card
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Redeem modal (WEB-UIUX-1543) ────────────────────────────────────────────

interface RedeemModalProps { onClose: () => void; }

function RedeemModal({ onClose }: RedeemModalProps) {
  const queryClient = useQueryClient();
  const [code, setCode] = useState('');
  const [amount, setAmount] = useState('');
  const [invoiceId, setInvoiceId] = useState('');
  const [lookupCard, setLookupCard] = useState<any | null>(null);
  const [lookupError, setLookupError] = useState<string | null>(null);
  const [lookupLoading, setLookupLoading] = useState(false);
  // WEB-UIUX-1013: 429 rate-limit retry-after countdown. While >0 the lookup
  // button is disabled with a visible "Retry in Ns" hint so the cashier
  // doesn't bang on a locked endpoint and accidentally fingerprint as abuse.
  const [lookupRetryIn, setLookupRetryIn] = useState(0);

  // Tick the retry-after counter down every second; clears when it hits 0.
  useEffect(() => {
    if (lookupRetryIn <= 0) return;
    const id = setInterval(() => {
      setLookupRetryIn((n) => Math.max(0, n - 1));
    }, 1000);
    return () => clearInterval(id);
  }, [lookupRetryIn]);
  const [redeemError, setRedeemError] = useState<string | null>(null);
  const [success, setSuccess] = useState<{ new_balance: number } | null>(null);

  const handleLookup = async () => {
    setLookupError(null);
    setRedeemError(null);
    setSuccess(null);
    setLookupCard(null);
    const trimmed = code.trim();
    if (!trimmed) {
      setLookupError('Enter a gift-card code.');
      return;
    }
    setLookupLoading(true);
    try {
      const res = await giftCardApi.lookup(trimmed);
      // Server returns { success, data: { id, current_balance, status, expires_at, ... } }
      const card = (res as any)?.data?.data ?? (res as any)?.data ?? null;
      if (!card) {
        setLookupError('Card not found.');
        return;
      }
      setLookupCard(card);
      const balanceCandidate = Number(card.current_balance);
      if (Number.isFinite(balanceCandidate) && !amount) {
        setAmount(balanceCandidate.toFixed(2));
      }
    } catch (err: any) {
      const status = err?.response?.status;
      const serverMsg = err?.response?.data?.message;
      if (status === 429) {
        const retry = Math.max(1, Number(err?.response?.data?.retry_after_seconds ?? 60));
        setLookupRetryIn(retry);
        setLookupError(serverMsg || 'Too many lookup attempts.');
      } else if (status === 404) {
        setLookupError(serverMsg || 'Gift card not found.');
      } else if (status === 400) {
        setLookupError(serverMsg || 'Gift card is used or expired.');
      } else {
        setLookupError(serverMsg || 'Could not look up gift card.');
      }
    } finally {
      setLookupLoading(false);
    }
  };

  const redeemMut = useMutation({
    mutationFn: () => {
      const amt = Number(amount);
      const invId = invoiceId.trim() ? Number(invoiceId) : null;
      return giftCardApi.redeem(Number(lookupCard?.id), { amount: amt, invoice_id: invId });
    },
    onSuccess: (res: any) => {
      setSuccess({ new_balance: Number(res?.data?.data?.new_balance ?? 0) });
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
    },
    onError: (err: any) => {
      setRedeemError(err?.response?.data?.message || 'Redeem failed.');
    },
  });

  const handleRedeem = () => {
    setRedeemError(null);
    if (!lookupCard) {
      setRedeemError('Look up a card first.');
      return;
    }
    const amt = Number(amount);
    if (!Number.isFinite(amt) || amt <= 0) {
      setRedeemError('Enter a positive amount.');
      return;
    }
    const balance = Number(lookupCard.current_balance) || 0;
    if (amt > balance + 0.005) {
      setRedeemError(`Amount exceeds card balance of ${formatCurrency(balance)}.`);
      return;
    }
    redeemMut.mutate();
  };

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="redeem-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 id="redeem-modal-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Redeem gift card</h2>
          <button aria-label="Close" onClick={onClose} className="rounded p-1 text-surface-400 hover:text-surface-600">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-2">
          <label className="block text-sm font-medium text-surface-700 dark:text-surface-300">Card code</label>
          <div className="flex gap-2">
            <input
              value={code}
              onChange={(e) => { setCode(e.target.value); setLookupCard(null); setSuccess(null); }}
              placeholder="e.g. GC-ABCD-1234"
              className="input flex-1 font-mono uppercase"
              autoFocus
            />
            <button
              type="button"
              onClick={handleLookup}
              disabled={lookupLoading || !code.trim() || lookupRetryIn > 0}
              className="rounded-lg bg-surface-100 px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-200 disabled:opacity-50 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              {lookupRetryIn > 0
                ? `Retry in ${lookupRetryIn}s`
                : lookupLoading
                  ? 'Looking…'
                  : 'Look up'}
            </button>
          </div>
          {lookupError && (
            <p role="alert" className="text-sm text-red-600 dark:text-red-400">
              {lookupError}
              {lookupRetryIn > 0 && <> Retry in <strong>{lookupRetryIn}s</strong>.</>}
            </p>
          )}
        </div>
        {lookupCard && (
          <div className="rounded-lg border border-surface-200 bg-surface-50 p-3 text-sm dark:border-surface-700 dark:bg-surface-800/50">
            <div className="flex items-center justify-between">
              <span className="text-surface-500 dark:text-surface-400">Balance</span>
              <span className="font-mono font-semibold text-surface-900 dark:text-surface-100">
                {formatCurrency(Number(lookupCard.current_balance) || 0)}
              </span>
            </div>
            <div className="flex items-center justify-between">
              <span className="text-surface-500 dark:text-surface-400">Status</span>
              <span className="font-mono text-surface-700 dark:text-surface-300">{lookupCard.status}</span>
            </div>
            {lookupCard.expires_at && (
              <div className="flex items-center justify-between">
                <span className="text-surface-500 dark:text-surface-400">Expires</span>
                <span className="text-surface-700 dark:text-surface-300">{formatDate(lookupCard.expires_at)}</span>
              </div>
            )}
          </div>
        )}
        {lookupCard && lookupCard.status === 'active' && (
          <>
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount to redeem</label>
              <input
                type="number" step="0.01" min="0.01"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder={(Number(lookupCard.current_balance) || 0).toFixed(2)}
                className="input w-full"
              />
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Apply to invoice ID (optional)</label>
              <input
                value={invoiceId}
                onChange={(e) => setInvoiceId(e.target.value.replace(/[^0-9]/g, ''))}
                placeholder="e.g. 1024"
                className="input w-full font-mono"
              />
              <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">Leave blank to record a balance-only redemption.</p>
            </div>
            {redeemError && (
              <p role="alert" className="text-sm text-red-600 dark:text-red-400">{redeemError}</p>
            )}
            {success && (
              <div className="rounded-lg border border-emerald-200 bg-emerald-50 px-3 py-2 text-sm text-emerald-700 dark:border-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300">
                Redeemed. New balance: {formatCurrency(success.new_balance)}.
              </div>
            )}
            <button
              type="button"
              onClick={handleRedeem}
              disabled={redeemMut.isPending || !!success}
              className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {redeemMut.isPending ? 'Redeeming…' : `Redeem ${amount ? formatCurrency(Number(amount) || 0) : ''}`}
            </button>
          </>
        )}
        {lookupCard && lookupCard.status !== 'active' && (
          <div className="rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-sm text-amber-700 dark:border-amber-700 dark:bg-amber-900/30 dark:text-amber-300">
            Card is <span className="font-mono">{lookupCard.status}</span> — cannot redeem.
          </div>
        )}
      </div>
    </div>
  );
}

// ─── Skeleton ─────────────────────────────────────────────────────────────────

function TableSkeleton() {
  return (
    <div className="animate-pulse space-y-3">
      {Array.from({ length: 5 }).map((_, i) => (
        <div key={i} className="h-12 bg-surface-100 dark:bg-surface-800 rounded-lg" />
      ))}
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

export function GiftCardsListPage() {
  const navigate = useNavigate();
  const [keyword, setKeyword] = useState('');
  const [debouncedKeyword, setDebouncedKeyword] = useState('');
  const [statusFilter, setStatusFilter] = useState('');
  const [page, setPage] = useState(1);
  const [showIssueModal, setShowIssueModal] = useState(false);
  // WEB-UIUX-1543: dedicated lookup → redeem modal for customer's physical
  // card. Lives alongside IssueModal so the gift-card surface owns both
  // ends of the lifecycle.
  const [showRedeemModal, setShowRedeemModal] = useState(false);
  const searchKeyword = debouncedKeyword.trim();
  // WEB-UIUX-998: CSV export gated behind admin/manager role (PII-sensitive)
  const canExport = useHasRole(['admin', 'manager']);

  useEffect(() => {
    const timeoutId = window.setTimeout(() => {
      setDebouncedKeyword(keyword);
      setPage(1);
    }, SEARCH_DEBOUNCE_MS);
    return () => window.clearTimeout(timeoutId);
  }, [keyword]);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['gift-cards', { keyword: searchKeyword, status: statusFilter, page, per_page: PAGE_SIZE }],
    queryFn: async () => {
      const res = await giftCardApi.list({
        keyword: searchKeyword || undefined,
        status: statusFilter || undefined,
        page,
        per_page: PAGE_SIZE,
      });
      return (res.data as { data: GiftCardListData }).data;
    },
    staleTime: 30_000,
  });

  const cards = data?.cards ?? [];
  const summary = data?.summary;
  const pagination = data?.pagination;
  const totalPages = Math.max(1, pagination?.total_pages ?? 1);
  const hasActiveFilters = Boolean(keyword.trim() || statusFilter);
  const firstResult = pagination && pagination.total > 0
    ? (pagination.page - 1) * pagination.per_page + 1
    : 0;
  const lastResult = pagination && pagination.total > 0
    ? Math.min(pagination.page * pagination.per_page, pagination.total)
    : 0;

  function updateKeyword(value: string): void {
    setKeyword(value);
  }

  function updateStatusFilter(value: string): void {
    setStatusFilter(value);
    setPage(1);
  }

  // WEB-UIUX-998: Export current page of gift cards as CSV (outstanding-liability report).
  // PII-sensitive — only rendered when canExport is true (admin/manager).
  function handleExportCsv(): void {
    if (!cards.length) return;
    const headers = ['code_last4', 'recipient', 'balance', 'expires_at', 'status', 'issued_at'];
    const rows = cards.map((card) =>
      toCsvRow([
        maskCode(card.code),
        card.recipient_name ?? card.recipient_email ?? '',
        dollarsFromMaybeCents(card.current_balance).toFixed(2),
        card.expires_at ?? '',
        card.status,
        card.created_at,
      ])
    );
    const csv = CSV_BOM + [headers.join(','), ...rows].join('\n');
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `gift-cards-outstanding-${toLocalDateString(new Date())}.csv`;
    a.click();
    URL.revokeObjectURL(url);
  }

  return (
    <div className="p-6 max-w-7xl mx-auto">
      {/* Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <Gift className="h-6 w-6 text-primary-600" />
          <div>
            {/* WEB-UIUX-1565: standardize on sentence case to match
                "Issue gift card" / "Gift card issued" / "Reload gift card". */}
            <h1 className="text-xl font-semibold text-surface-900 dark:text-surface-100">Gift cards</h1>
            {summary && (
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {summary.active_count} active &middot; {formatCurrency(summary.total_outstanding)} outstanding
              </p>
            )}
          </div>
        </div>
        <div className="flex items-center gap-2">
          {/* WEB-UIUX-998: CSV export for outstanding liability — admin/manager only */}
          {canExport && cards.length > 0 && (
            <button
              onClick={handleExportCsv}
              title="Export gift card liability as CSV"
              className="flex items-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 text-sm font-medium"
            >
              <Download className="h-4 w-4" />
              Export CSV
            </button>
          )}
          {/* WEB-UIUX-1446: hide header CTA on empty state — empty-state centered button takes over */}
          {cards.length > 0 && (
            <>
              {/* WEB-UIUX-1543: dedicated Redeem-by-code surface so the
                  customer's physical card can be applied to an invoice
                  without leaving the gift-cards page. Modal does
                  lookup → balance/status preview → redeem against an
                  invoice id input. */}
              <button
                onClick={() => setShowRedeemModal(true)}
                className="flex items-center gap-2 px-4 py-2 rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-800 text-sm font-medium"
              >
                <WalletCards className="h-4 w-4" />
                Redeem code
              </button>
              <button
                onClick={() => setShowIssueModal(true)}
                className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-on-primary hover:bg-primary-700 text-sm font-medium"
              >
                <Plus className="h-4 w-4" />
                Issue gift card
              </button>
            </>
          )}
        </div>
      </div>

      {/* Filters */}
      <div className="flex gap-3 mb-5">
        <div className="relative flex-1 max-w-xs">
          <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-surface-400" />
          <input
            type="text"
            value={keyword}
            onChange={(e) => updateKeyword(e.target.value)}
            placeholder="Search code or recipient..."
            className="w-full pl-9 pr-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
          />
        </div>
        <select
          value={statusFilter}
          onChange={(e) => updateStatusFilter(e.target.value)}
          className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-800"
        >
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="used">Used</option>
          {/* WEB-UIUX-1546: Disabled status now wired via /:id/disable +
              /:id/enable endpoints and the Disable button on detail. */}
          <option value="disabled">Disabled</option>
          {/* WEB-UIUX-1438: expired filter option */}
          <option value="expired">Expired</option>
        </select>
      </div>

      {/* Content */}
      {isLoading ? (
        <TableSkeleton />
      ) : isError ? (
        <div className="flex flex-col items-center justify-center py-20">
          <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
          <p className="text-sm text-surface-500">Failed to load gift cards</p>
        </div>
      ) : cards.length === 0 ? (
        <div className="flex flex-col items-center justify-center py-20 text-center">
          <Gift className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-4" />
          <p className="text-base font-medium text-surface-600 dark:text-surface-400">
            {hasActiveFilters ? 'No gift cards match these filters' : 'No gift cards yet - issue one to get started'}
          </p>
          {!hasActiveFilters && (
            <button
              onClick={() => setShowIssueModal(true)}
              className="mt-4 flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-on-primary hover:bg-primary-700 text-sm font-medium"
            >
              <Plus className="h-4 w-4" />
              Issue gift card
            </button>
          )}
        </div>
      ) : (
        <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl overflow-hidden">
          <table className="w-full text-sm">
            <thead>
              <tr className="border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Code</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Recipient</th>
                {/* WEB-UIUX-1008: header right-aligned to match cell alignment */}
                <th className="text-right px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Balance</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Status</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Created</th>
                <th className="text-left px-4 py-3 font-medium text-surface-500 dark:text-surface-400">Expires</th>
                <th className="px-4 py-3" />
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
              {cards.map((card) => (
                <tr key={card.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/40">
                  <td className="px-4 py-3 font-mono text-surface-900 dark:text-surface-100">
                    {maskCode(card.code)}
                  </td>
                  <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
                    {card.recipient_name ?? <span className="text-surface-400">—</span>}
                    {card.recipient_email && (
                      // WEB-UIUX-1448: title attribute exposes the full email
                      // on hover/focus so truncated addresses remain readable.
                      <div
                        className="text-xs text-surface-400 truncate max-w-[160px]"
                        title={card.recipient_email}
                      >
                        {card.recipient_email}
                      </div>
                    )}
                    {/* WEB-UIUX-988: deep-link to the linked customer profile when
                        the card was issued against a customer record. Drops the
                        "retype the name to find the card" friction. */}
                    {card.customer_id && (
                      <div className="text-xs">
                        <Link
                          to={`/customers/${card.customer_id}`}
                          onClick={(e) => e.stopPropagation()}
                          className="text-primary-600 dark:text-primary-400 hover:underline"
                        >
                          {[card.customer_first_name, card.customer_last_name].filter(Boolean).join(' ') || `Customer #${card.customer_id}`}
                        </Link>
                      </div>
                    )}
                  </td>
                  <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">
                    {formatCurrency(card.current_balance)}
                  </td>
                  <td className="px-4 py-3">
                    {/* WEB-UIUX-1453: Check icon prefix distinguishes 'used' badge from placeholder/default tone */}
                    <span className={`inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium capitalize ${statusBadge(card.status)}`}>
                      {card.status === 'used' && <Check className="h-3 w-3" />}
                      {card.status}
                    </span>
                  </td>
                  {/* WEB-UIUX-1567: title tooltip surfaces full timestamp so
                      multiple cards issued the same day stay reconcilable
                      against shift logs even though the cell only shows date. */}
                  <td
                    className="px-4 py-3 text-surface-500 dark:text-surface-400"
                    title={formatDateTime(card.created_at)}
                  >
                    {formatDate(card.created_at)}
                  </td>
                  {/* WEB-UIUX-997: yellow warning icon when expiring within 30 days */}
                  <td className="px-4 py-3 text-surface-500 dark:text-surface-400">
                    {card.expires_at ? (
                      <span className="inline-flex items-center gap-1">
                        {isExpiringSoon(card.expires_at) && (
                          <AlertTriangle
                            className="h-3.5 w-3.5 text-yellow-500 shrink-0"
                            aria-label="Expiring soon"
                          />
                        )}
                        {formatDate(card.expires_at)}
                      </span>
                    ) : (
                      <span className="text-surface-400">—</span>
                    )}
                  </td>
                  <td className="px-4 py-3">
                    <button
                      onClick={() => navigate(`/gift-cards/${card.id}`)}
                      className="text-primary-600 hover:text-primary-700 text-xs font-medium"
                    >
                      View
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          {pagination && (
            <div className="flex flex-col gap-3 border-t border-surface-200 px-4 py-3 dark:border-surface-800 sm:flex-row sm:items-center sm:justify-between">
              <p className="text-sm text-surface-500 dark:text-surface-400">
                {pagination.total === 0
                  ? 'No results'
                  : `Showing ${firstResult}-${lastResult} of ${pagination.total}`}
              </p>
              <div className="flex items-center gap-3">
                <p className="text-sm text-surface-500 dark:text-surface-400">
                  Page {pagination.total === 0 ? 0 : pagination.page} of {pagination.total === 0 ? 0 : totalPages}
                </p>
                {pagination.total_pages > 1 && (
                  <div className="flex items-center gap-2">
                    <button
                      aria-label="Previous page"
                      onClick={() => setPage((currentPage) => Math.max(1, currentPage - 1))}
                      disabled={pagination.page <= 1}
                      className="inline-flex items-center justify-center gap-1 rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                    >
                      <ChevronLeft className="h-4 w-4" />
                      Previous
                    </button>
                    <button
                      aria-label="Next page"
                      onClick={() => setPage((currentPage) => Math.min(totalPages, currentPage + 1))}
                      disabled={pagination.page >= totalPages}
                      className="inline-flex items-center justify-center gap-1 rounded-lg border border-surface-200 px-3 py-1.5 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                    >
                      Next
                      <ChevronRight className="h-4 w-4" />
                    </button>
                  </div>
                )}
              </div>
            </div>
          )}
        </div>
      )}

      {/* WEB-UIUX-1001: admin-only approver inbox for manager-initiated
          issuances over the dual-control threshold. Hidden behind a useHasRole
          check inside the component so non-admins never fire the query. */}
      <PendingIssuancesInbox />

      {showIssueModal && <IssueModal onClose={() => setShowIssueModal(false)} />}
      {showRedeemModal && <RedeemModal onClose={() => setShowRedeemModal(false)} />}
    </div>
  );
}

/**
 * WEB-UIUX-1001: pending gift-card issuances awaiting admin approval. Only
 * renders for admin users (manager + cashier never hit the route either way
 * — server returns 403). Pending tab is the default + most common
 * landing-place; approved/declined surfaces are reachable via the status
 * pill row for audit follow-up.
 */
function PendingIssuancesInbox() {
  const isAdmin = useHasRole('admin');
  const queryClient = useQueryClient();
  const [statusTab, setStatusTab] = useState<'pending' | 'approved' | 'declined' | 'cancelled'>('pending');
  const [declineId, setDeclineId] = useState<number | null>(null);
  const [declineReason, setDeclineReason] = useState('');

  const inboxQuery = useQuery({
    queryKey: ['gift-cards', 'pending-issuances', statusTab],
    queryFn: async () => {
      const res = await giftCardApi.pendingIssuances(statusTab);
      return res.data.data;
    },
    enabled: isAdmin,
    staleTime: 30_000,
  });

  const approveMut = useMutation({
    mutationFn: (id: number) => giftCardApi.approvePendingIssuance(id),
    onSuccess: (res) => {
      const code = res.data?.data?.code;
      toast.success(
        code
          ? `Approved · code ${code.slice(0, 4)}…${code.slice(-4)} minted`
          : 'Issuance approved',
      );
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
    },
    onError: (err: unknown) => {
      const msg = (err as { response?: { data?: { message?: string } } })
        ?.response?.data?.message ?? 'Approval failed';
      toast.error(msg);
    },
  });

  const declineMut = useMutation({
    mutationFn: ({ id, reason }: { id: number; reason?: string }) =>
      giftCardApi.declinePendingIssuance(id, reason),
    onSuccess: () => {
      toast.success('Issuance declined');
      setDeclineId(null);
      setDeclineReason('');
      queryClient.invalidateQueries({ queryKey: ['gift-cards', 'pending-issuances'] });
    },
    onError: (err: unknown) => {
      const msg = (err as { response?: { data?: { message?: string } } })
        ?.response?.data?.message ?? 'Decline failed';
      toast.error(msg);
    },
  });

  if (!isAdmin) return null;
  const rows: PendingGiftCardIssuance[] = inboxQuery.data ?? [];
  // Hide the section entirely when the default Pending tab is empty so a
  // tenant with zero outstanding approvals doesn't see an empty card. The
  // approver can still hit the queue by switching tabs from a populated
  // state once they have any history.
  if (statusTab === 'pending' && !inboxQuery.isLoading && rows.length === 0) {
    return null;
  }

  const requesterLabel = (r: PendingGiftCardIssuance) =>
    [r.requester_first, r.requester_last].filter(Boolean).join(' ').trim() || 'unknown';
  const customerLabel = (r: PendingGiftCardIssuance) => {
    const name = [r.customer_first, r.customer_last].filter(Boolean).join(' ').trim();
    return name || r.recipient_name || '—';
  };

  return (
    <section className="mt-8 rounded-xl border border-amber-300 bg-amber-50/40 dark:border-amber-500/30 dark:bg-amber-500/5 p-4">
      <header className="mb-3 flex items-center justify-between gap-2">
        <div>
          <h2 className="text-base font-semibold text-surface-900 dark:text-surface-100">
            Pending gift-card issuances
          </h2>
          <p className="text-xs text-surface-500 dark:text-surface-400">
            Manager-initiated issuances over the dual-control threshold land here for admin approval.
          </p>
        </div>
        <div className="flex items-center gap-1 text-xs">
          {(['pending', 'approved', 'declined', 'cancelled'] as const).map((s) => (
            <button
              key={s}
              type="button"
              onClick={() => setStatusTab(s)}
              className={`rounded-full px-2.5 py-1 capitalize ${
                statusTab === s
                  ? 'bg-amber-200 text-amber-900 dark:bg-amber-500/30 dark:text-amber-100'
                  : 'bg-white/60 text-surface-600 hover:bg-white dark:bg-surface-800 dark:text-surface-300'
              }`}
            >
              {s}
            </button>
          ))}
        </div>
      </header>

      {inboxQuery.isLoading ? (
        <p className="text-sm text-surface-500 dark:text-surface-400">Loading…</p>
      ) : rows.length === 0 ? (
        <p className="text-sm text-surface-500 dark:text-surface-400">
          No {statusTab} issuances.
        </p>
      ) : (
        <ul className="divide-y divide-amber-200 dark:divide-amber-500/30 rounded-md border border-amber-200 dark:border-amber-500/30 bg-white dark:bg-surface-900">
          {rows.map((r) => (
            <li key={r.id} className="flex flex-wrap items-center justify-between gap-3 px-3 py-2 text-sm">
              <div className="min-w-0 flex-1">
                <p className="font-medium text-surface-900 dark:text-surface-100">
                  {formatCurrency(r.amount)} · {customerLabel(r)}
                </p>
                <p className="text-xs text-surface-500 dark:text-surface-400">
                  Requested by {requesterLabel(r)} · {formatDate(r.created_at)}
                  {r.recipient_email && <> · {r.recipient_email}</>}
                </p>
                {r.status === 'declined' && r.decline_reason && (
                  <p className="text-xs text-red-600 dark:text-red-400 mt-0.5">
                    Reason: {r.decline_reason}
                  </p>
                )}
              </div>
              {r.status === 'pending' ? (
                <div className="flex items-center gap-2 text-xs">
                  <button
                    type="button"
                    onClick={() => {
                      if (confirm(`Approve and mint a ${formatCurrency(r.amount)} gift card?`)) {
                        approveMut.mutate(r.id);
                      }
                    }}
                    disabled={approveMut.isPending}
                    className="rounded-md bg-green-600 px-3 py-1.5 font-medium text-white hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    {approveMut.isPending && approveMut.variables === r.id ? 'Approving…' : 'Approve'}
                  </button>
                  <button
                    type="button"
                    onClick={() => { setDeclineId(r.id); setDeclineReason(''); }}
                    disabled={declineMut.isPending}
                    className="rounded-md border border-red-300 px-3 py-1.5 font-medium text-red-700 hover:bg-red-50 dark:border-red-500/30 dark:text-red-300 dark:hover:bg-red-900/20 disabled:opacity-50 disabled:cursor-not-allowed"
                  >
                    Decline
                  </button>
                </div>
              ) : (
                <span className="text-xs uppercase tracking-wide text-surface-500 dark:text-surface-400">
                  {r.status}
                </span>
              )}
            </li>
          ))}
        </ul>
      )}

      {declineId != null && (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4" role="dialog" aria-modal="true">
          <div className="w-full max-w-md rounded-xl bg-white dark:bg-surface-900 p-5 shadow-xl">
            <h3 className="text-base font-semibold mb-2 text-surface-900 dark:text-surface-100">
              Decline issuance
            </h3>
            <p className="text-xs text-surface-500 dark:text-surface-400 mb-3">
              Optional reason (≤ 500 chars). The requester sees this on their audit timeline.
            </p>
            <textarea
              value={declineReason}
              onChange={(e) => setDeclineReason(e.target.value)}
              maxLength={500}
              rows={3}
              className="w-full rounded-md border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 p-2 text-sm text-surface-900 dark:text-surface-100"
              placeholder="e.g. amount looks wrong, customer not on file…"
            />
            <div className="mt-4 flex justify-end gap-2">
              <button
                type="button"
                onClick={() => { setDeclineId(null); setDeclineReason(''); }}
                className="rounded-md border border-surface-300 dark:border-surface-700 px-3 py-1.5 text-sm font-medium text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => declineMut.mutate({ id: declineId, reason: declineReason.trim() || undefined })}
                disabled={declineMut.isPending}
                className="rounded-md bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {declineMut.isPending ? 'Declining…' : 'Decline'}
              </button>
            </div>
          </div>
        </div>
      )}
    </section>
  );
}
