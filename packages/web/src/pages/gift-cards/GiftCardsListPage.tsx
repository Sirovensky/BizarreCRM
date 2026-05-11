import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useNavigate } from 'react-router-dom';
import { Gift, Plus, Search, Loader2, AlertCircle, AlertTriangle, X, ChevronLeft, ChevronRight, Download, Check, Copy, Printer, Mail } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi } from '@/api/endpoints';
import { formatCurrency as formatCurrencyShared, formatCurrencySymbol, formatDate, formatDateTime, dollarsFromMaybeCents } from '@/utils/format';
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
}

const PAGE_SIZE = 50;
const SEARCH_DEBOUNCE_MS = 300;

// ─── Helpers ──────────────────────────────────────────────────────────────────

// dollarsFromMaybeCents imported from @/utils/format (WEB-UIUX-550).
// Server is mid-migration from float-dollars to integer-cents; the heuristic
// lives in the shared util so both gift-card pages stay in sync.
function formatCurrency(amount: number): string {
  return formatCurrencyShared(dollarsFromMaybeCents(amount));
}

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
  });
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
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
              Save this code now — it will not be shown again.
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
                      Save this code — it will not be shown again.
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
              className="px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed"
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
              setForm({ amount: '', recipient_name: '', recipient_email: '', expires_at: '', notes: '' });
            }}
            disabled={!codeSavedConfirmed}
            className="mt-3 w-full px-4 py-2 rounded-lg border border-primary-300 text-primary-700 hover:bg-primary-50 dark:border-primary-700 dark:text-primary-300 dark:hover:bg-primary-950/30 text-sm font-medium disabled:opacity-40 disabled:cursor-not-allowed"
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
                      ? 'bg-primary-600 text-primary-950 border-primary-600'
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
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none flex items-center gap-2"
          >
            {issueMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Issue gift card
          </button>
        </div>
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
    a.download = `gift-cards-outstanding-${new Date().toISOString().slice(0, 10)}.csv`;
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
            <button
              onClick={() => setShowIssueModal(true)}
              className="flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium"
            >
              <Plus className="h-4 w-4" />
              Issue gift card
            </button>
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
              className="mt-4 flex items-center gap-2 px-4 py-2 rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 text-sm font-medium"
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

      {showIssueModal && <IssueModal onClose={() => setShowIssueModal(false)} />}
    </div>
  );
}
