import { useState, useEffect } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Eye, EyeOff, RefreshCw, Loader2, AlertCircle, Gift, ReceiptText, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { SkeletonCard, SkeletonTable } from '@/components/shared/Skeleton';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { EmptyState } from '@/components/shared/EmptyState';
import { useConfirmStore } from '@/stores/confirmStore';
// @audit-fixed (WEB-FF-003 / Fixer-UUU 2026-04-25): inline `$${n.toFixed(2)}` ignored tenant currency. Use shared formatCurrency.
import { formatDate, formatCurrency as formatCurrencyShared, dollarsFromMaybeCents } from '@/utils/format';

// ─── Types ────────────────────────────────────────────────────────────────────

type TxType = 'purchase' | 'redemption' | 'adjustment';

interface Transaction {
  id: number;
  type: TxType;
  amount: number;
  notes: string | null;
  created_at: string;
  // WEB-UIUX-991: server now JOINs users so the row can show who rang the
  // redemption / reload. Null for system-generated or legacy rows.
  by_first_name?: string | null;
  by_last_name?: string | null;
  user_id?: number | null;
  // WEB-UIUX-992: server JOINs invoices so the row can deep-link to the
  // original sale. Null when the tx wasn't tied to an invoice (e.g.
  // purchase outside POS, manual adjustment).
  invoice_id?: number | null;
  invoice_order_id?: string | null;
}

interface GiftCardDetail {
  id: number;
  code: string;
  initial_balance: number;
  current_balance: number;
  status: 'active' | 'used' | 'disabled';
  recipient_name: string | null;
  recipient_email: string | null;
  expires_at: string | null;
  notes: string | null;
  created_at: string;
  transactions: Transaction[];
  // WEB-UIUX-1452: server now joins customers on the detail endpoint.
  customer_id?: number | null;
  customer_first_name?: string | null;
  customer_last_name?: string | null;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────
// dollarsFromMaybeCents is now imported from @/utils/format (WEB-UIUX-550).

function formatCurrency(amount: number): string {
  // Magnitude only — sign is rendered separately by the caller (+/-).
  return formatCurrencyShared(Math.abs(dollarsFromMaybeCents(amount)));
}

function formatBalance(amount: number): string {
  return formatCurrencyShared(dollarsFromMaybeCents(amount));
}

// WEB-UIUX-1444: 'adjustment' label now inspects amount sign — positive = Reload, negative = Adjustment
function txLabel(type: TxType, amount?: number): string {
  switch (type) {
    case 'purchase': return 'Issued';
    case 'redemption': return 'Redeemed';
    case 'adjustment': return (amount !== undefined && amount < 0) ? 'Adjustment' : 'Reload';
  }
}

function txColor(type: TxType, amount: number): string {
  switch (type) {
    case 'purchase': return 'text-green-600 dark:text-green-400';
    case 'redemption':
      // Positive amount = refund/credit back to card → green; negative = spend → red.
      return amount > 0
        ? 'text-green-600 dark:text-green-400'
        : 'text-red-600 dark:text-red-400';
    case 'adjustment': return 'text-blue-600 dark:text-blue-400';
  }
}

function statusBadge(status: GiftCardDetail['status']): string {
  switch (status) {
    case 'active': return 'bg-green-100 text-green-800 dark:bg-green-900/30 dark:text-green-300';
    case 'used': return 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400';
    case 'disabled': return 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300';
  }
}

// ─── Reload Modal ─────────────────────────────────────────────────────────────

const RELOAD_MAX_AMOUNT = 5_000;
const RELOAD_CONFIRM_THRESHOLD = 500;

interface ReloadModalProps {
  cardId: number;
  // WEB-UIUX-1443: pass the current balance so the modal can render a
  // "Current: $X • New: $X+amount" preview without forcing the cashier to
  // close + re-read the tile behind the modal.
  currentBalance: number;
  onClose: () => void;
}

function ReloadModal({ cardId, currentBalance, onClose }: ReloadModalProps) {
  const queryClient = useQueryClient();
  const [amount, setAmount] = useState('');
  const [amountError, setAmountError] = useState<string | null>(null);
  // WEB-UIUX-557: focus-trap + scroll-lock (component only mounts when open).
  const dialogRef = useFocusTrap(true, { initialFocusSelector: 'input[type="number"]' }) as { current: HTMLDivElement | null };
  useBodyScrollLock(true);

  const reloadMutation = useMutation({
    mutationFn: (value: number) => giftCardApi.reload(cardId, { amount: value }),
    onSuccess: (res, value) => {
      queryClient.invalidateQueries({ queryKey: ['gift-card', cardId] });
      // WEB-UIUX-1558: include reloaded amount + new balance in success toast
      const newBalance = (res as any)?.data?.data?.new_balance;
      if (newBalance != null) {
        toast.success(`Reloaded ${formatCurrencyShared(value)} — new balance ${formatCurrencyShared(dollarsFromMaybeCents(newBalance))}`);
      } else {
        toast.success(`Reloaded ${formatCurrencyShared(value)}`);
      }
      onClose();
    },
    onError: (err: unknown) => {
      toast.error(err instanceof Error ? err.message : 'Reload failed');
    },
  });

  async function handleReload() {
    const value = parseFloat(amount);
    if (!Number.isFinite(value) || value <= 0) {
      setAmountError('Enter a valid reload amount.');
      return;
    }
    if (value > RELOAD_MAX_AMOUNT) {
      setAmountError(`Reload amount cannot exceed ${formatCurrencyShared(RELOAD_MAX_AMOUNT)}.`);
      return;
    }
    setAmountError(null);

    if (value >= RELOAD_CONFIRM_THRESHOLD) {
      const ok = await useConfirmStore.getState().confirm({
        title: 'Confirm large reload',
        message: `Reload this gift card by ${formatCurrencyShared(value)}?`,
        confirmLabel: 'Reload gift card',
        danger: true,
      });
      if (!ok) return;
    }

    reloadMutation.mutate(value);
  }

  // Esc-to-close
  useEffect(() => {
    function onKey(e: KeyboardEvent) {
      if (e.key === 'Escape') onClose();
    }
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      ref={dialogRef}
      role="dialog"
      aria-modal="true"
      aria-labelledby="gift-card-reload-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-xl shadow-xl p-6 w-full max-w-sm" onClick={(e) => e.stopPropagation()}>
        <h2 id="gift-card-reload-title" className="text-base font-semibold text-surface-900 dark:text-surface-100 mb-4">Reload gift card</h2>
        <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Amount ($)</label>
        <input
          type="number"
          min="0.01"
          max={RELOAD_MAX_AMOUNT}
          step="0.01"
          value={amount}
          onChange={(e) => {
            setAmount(e.target.value);
            setAmountError(null);
          }}
          placeholder="25.00"
          autoFocus
          aria-invalid={!!amountError}
          aria-describedby="gift-card-reload-help"
          className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
        />
        {/* WEB-UIUX-1443: live balance preview so the cashier sees what the
            card will be at after the reload without dismissing the modal. */}
        <div className="mt-2 mb-3 flex items-baseline justify-between rounded-lg bg-surface-50 dark:bg-surface-800 px-3 py-2 text-xs">
          <span className="text-surface-500 dark:text-surface-400">
            Current: <span className="font-medium text-surface-900 dark:text-surface-100">{formatCurrencyShared(currentBalance)}</span>
          </span>
          {(() => {
            const parsed = parseFloat(amount);
            if (!Number.isFinite(parsed) || parsed <= 0) return <span className="text-surface-400">New: —</span>;
            return (
              <span className="text-surface-500 dark:text-surface-400">
                New: <span className="font-semibold text-primary-700 dark:text-primary-300">{formatCurrencyShared(currentBalance + parsed)}</span>
              </span>
            );
          })()}
        </div>
        <p id="gift-card-reload-help" className="mb-5 text-xs text-surface-500 dark:text-surface-400">
          Maximum reload is {formatCurrencyShared(RELOAD_MAX_AMOUNT)}. Reloads of {formatCurrencyShared(RELOAD_CONFIRM_THRESHOLD)} or more require confirmation.
          {amountError && <span className="mt-1 block text-red-600 dark:text-red-400">{amountError}</span>}
        </p>
        {/* WEB-UIUX-1447: full-width buttons on mobile, row on sm+ */}
        <div className="flex flex-col sm:flex-row sm:justify-end gap-2 sm:gap-3">
          <button
            onClick={onClose}
            className="w-full sm:w-auto px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          <button
            onClick={handleReload}
            disabled={reloadMutation.isPending || !amount}
            className="w-full sm:w-auto flex items-center justify-center gap-2 px-4 py-2 text-sm rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {reloadMutation.isPending && <Loader2 className="h-4 w-4 animate-spin" />}
            Reload
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Page ─────────────────────────────────────────────────────────────────────

const TX_PAGE_SIZE = 50;

export function GiftCardDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const cardId = Number(id);
  const [showCode, setShowCode] = useState(false);
  const [showReloadModal, setShowReloadModal] = useState(false);
  const [txPage, setTxPage] = useState(0);
  // WEB-UIUX-552: gate Reload on server-side permission (gift_cards.reload is
  // admin/manager only). Free-plan cashiers don't have it, so the button must
  // be inert rather than letting them fire a request that returns 403.
  const userRole = useAuthStore((s) => s.user?.role);
  const canReload = userRole === 'admin' || userRole === 'manager';
  // WEB-UIUX-1546: disable / enable share the gift_cards.reload permission
  // server-side, so reuse the canReload flag for the button gate.
  const canDisable = canReload;
  const queryClient = useQueryClient();
  const disableMutation = useMutation({
    mutationFn: (reason: string) => giftCardApi.disable(cardId, { reason }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gift-card', cardId] });
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
      toast.success('Gift card disabled');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.message || 'Failed to disable gift card'),
  });
  // WEB-UIUX-1000: resend the plaintext code to recipient_email (or override).
  const resendCodeMutation = useMutation({
    mutationFn: (email?: string) => giftCardApi.resendCode(cardId, email ? { email } : undefined),
    onSuccess: (res) => {
      const to = res.data?.data?.delivered_to;
      toast.success(`Code resent to ${to}`);
    },
    onError: (err: unknown) => {
      const e = err as { response?: { data?: { message?: string } } };
      toast.error(e?.response?.data?.message ?? 'Could not resend gift-card code');
    },
  });

  const enableMutation = useMutation({
    mutationFn: () => giftCardApi.enable(cardId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gift-card', cardId] });
      queryClient.invalidateQueries({ queryKey: ['gift-cards'] });
      toast.success('Gift card re-enabled');
    },
    onError: (err: any) =>
      toast.error(err?.response?.data?.message || 'Failed to re-enable gift card'),
  });

  const { data, isLoading, isError } = useQuery({
    queryKey: ['gift-card', cardId],
    queryFn: async () => {
      const res = await giftCardApi.get(cardId);
      return (res.data as { data: GiftCardDetail }).data;
    },
    enabled: Number.isFinite(cardId) && cardId > 0,
    staleTime: 30_000,
  });

  if (isLoading) {
    return (
      <div className="p-6 max-w-3xl mx-auto">
        <button onClick={() => navigate('/gift-cards')} className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6">
          <ArrowLeft className="h-4 w-4" /> Gift cards
        </button>
        <div className="space-y-4">
          <SkeletonCard />
          <SkeletonTable rows={5} cols={4} />
        </div>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="p-6 max-w-3xl mx-auto">
        <button onClick={() => navigate('/gift-cards')} className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6">
          <ArrowLeft className="h-4 w-4" /> Gift cards
        </button>
        <EmptyState
          icon={AlertCircle}
          title="Gift card not found"
          description="This gift card may have been removed or the link is invalid."
          actionLabel="Back to Gift Cards"
          onAction={() => navigate('/gift-cards')}
        />
      </div>
    );
  }

  const card = data;

  return (
    <div className="p-6 max-w-3xl mx-auto">
      {/* WEB-UIUX-1006: full breadcrumb path replaces the bare arrow link so
          the navigation pattern matches Estimates / Tickets / Invoices. */}
      <Breadcrumb
        items={[
          { label: 'Gift Cards', href: '/gift-cards' },
          { label: `#${card.id}` },
        ]}
      />

      {/* Card Summary */}
      <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl p-5 mb-5">
        <div className="flex items-start justify-between gap-4">
          <div className="flex items-center gap-3">
            <div className="p-2.5 bg-primary-50 dark:bg-primary-900/20 rounded-lg">
              <Gift className="h-5 w-5 text-primary-600 dark:text-primary-400" />
            </div>
            <div>
              <div className="flex items-center gap-2 mb-0.5">
                <span className="font-mono text-sm text-surface-700 dark:text-surface-300">
                  {showCode ? card.code : `**** **** **** ${card.code.slice(-4)}`}
                </span>
                {/* WEB-UIUX-1451: aria-label for screen readers on eye-toggle */}
                <button
                  onClick={() => setShowCode((v) => !v)}
                  aria-pressed={showCode}
                  aria-label={showCode ? 'Hide code' : 'Show full code'}
                  className="text-surface-400 hover:text-surface-700 dark:hover:text-surface-200"
                  title={showCode ? 'Hide code' : 'Show full code'}
                >
                  {showCode ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              <span className={`inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium capitalize ${statusBadge(card.status)}`}>
                {card.status}
              </span>
            </div>
          </div>

          {(() => {
            // WEB-UIUX-1559: when balance > initial it's because the card
            // has been reloaded; sum the reload transactions to render
            // "Loaded total $X" instead of the jarring "of $50 initial"
            // line that under-states the lifetime amount.
            const initial = dollarsFromMaybeCents(card.initial_balance);
            const current = dollarsFromMaybeCents(card.current_balance);
            const reloadSum = (card.transactions ?? []).reduce((acc, t) => {
              if (t.type === 'adjustment' && (t.amount ?? 0) > 0) return acc + dollarsFromMaybeCents(t.amount);
              return acc;
            }, 0);
            const loadedTotal = initial + reloadSum;
            const reference = loadedTotal > initial ? loadedTotal : initial;
            const pct = reference > 0 ? Math.max(0, Math.min(100, (current / reference) * 100)) : 0;
            const tone = pct >= 60 ? 'bg-emerald-500' : pct >= 20 ? 'bg-amber-500' : 'bg-red-500';
            return (
              <div className="text-right">
                <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{formatBalance(card.current_balance)}</p>
                <p className="text-xs text-surface-500 dark:text-surface-400">
                  {reloadSum > 0
                    ? `of ${formatCurrencyShared(loadedTotal)} loaded total`
                    : `of ${formatBalance(card.initial_balance)} initial`}
                </p>
                {/* WEB-UIUX-1011: progress bar of remaining-vs-reference. */}
                {reference > 0 && (
                  <div className="mt-1 ml-auto h-1.5 w-32 rounded-full bg-surface-200 dark:bg-surface-700 overflow-hidden" title={`${pct.toFixed(0)}% remaining`}>
                    <div className={`h-full ${tone}`} style={{ width: `${pct}%` }} />
                  </div>
                )}
              </div>
            );
          })()}
        </div>

        {/* Meta */}
        <dl className="mt-4 grid grid-cols-2 sm:grid-cols-3 gap-3 text-sm">
          {card.recipient_name && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Recipient</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{card.recipient_name}</dd>
            </div>
          )}
          {card.recipient_email && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Email</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300 truncate" title={card.recipient_email}>{card.recipient_email}</dd>
            </div>
          )}
          {/* WEB-UIUX-1452: link to the customer when card.customer_id is set. */}
          {card.customer_id && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Customer</dt>
              <dd className="mt-0.5">
                <Link to={`/customers/${card.customer_id}`} className="text-primary-600 dark:text-primary-400 hover:underline">
                  {[card.customer_first_name, card.customer_last_name].filter(Boolean).join(' ') || `Customer #${card.customer_id}`}
                </Link>
              </dd>
            </div>
          )}
          <div>
            <dt className="text-xs text-surface-400 uppercase tracking-wide">Issued</dt>
            <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{formatDate(card.created_at)}</dd>
          </div>
          {card.expires_at && (
            <div>
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Expires</dt>
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300">{formatDate(card.expires_at)}</dd>
            </div>
          )}
          {/* WEB-UIUX-990: surface notes captured at issue time so the
              auditor sees the original tag ("corporate gift order #4711",
              "lost-card replacement") instead of having to query the DB. */}
          {card.notes && (
            <div className="col-span-2 sm:col-span-3">
              <dt className="text-xs text-surface-400 uppercase tracking-wide">Notes</dt>
              <dd className="mt-0.5 whitespace-pre-wrap text-surface-700 dark:text-surface-300">{card.notes}</dd>
            </div>
          )}
        </dl>

        {/* WEB-UIUX-1000: resend code by email — works on active cards only. */}
        {canReload && card.status === 'active' && (
          <div className="mt-2">
            <button
              type="button"
              onClick={() => {
                const defaultTo = card.recipient_email || '';
                const target = window.prompt(
                  defaultTo
                    ? `Re-send code to which email?`
                    : 'No recipient email on file. Enter an email to send the code to:',
                  defaultTo,
                );
                if (target === null) return;
                const trimmed = target.trim();
                if (!trimmed) {
                  toast.error('Email is required');
                  return;
                }
                if (!window.confirm(`Send the gift-card code to ${trimmed}?`)) return;
                resendCodeMutation.mutate(trimmed !== defaultTo ? trimmed : undefined);
              }}
              disabled={resendCodeMutation.isPending}
              className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-200 hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed"
              title={card.recipient_email
                ? `Resend code to ${card.recipient_email}`
                : 'No email on file — you will be prompted for one'}
            >
              {resendCodeMutation.isPending
                ? <Loader2 className="h-4 w-4 animate-spin" />
                : <Send className="h-4 w-4" />}
              Resend code by email
            </button>
          </div>
        )}
        {/* WEB-UIUX-1442: server allows reload on any status except disabled; show button for 'used' too (secondary tone indicates topping up a depleted card) */}
        {/* WEB-UIUX-1546: Disable button — reports-stolen / lost-card path. */}
        {canDisable && card.status === 'active' && (
          <div className="mt-2">
            <button
              onClick={async () => {
                const reason = window.prompt(
                  'Why is this gift card being disabled? (optional — e.g. "reported lost", "stolen", "issued in error")',
                  '',
                );
                if (reason === null) return;
                if (!window.confirm('Disable this gift card? It can no longer be redeemed until you re-enable it.')) return;
                disableMutation.mutate(reason);
              }}
              disabled={disableMutation.isPending}
              className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg border border-red-200 dark:border-red-800 text-red-700 dark:text-red-300 hover:bg-red-50 dark:hover:bg-red-900/20 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <AlertCircle className="h-4 w-4" />
              Disable card
            </button>
          </div>
        )}
        {canDisable && card.status === 'disabled' && (
          <div className="mt-2">
            <button
              onClick={() => {
                if (!window.confirm('Re-enable this gift card? It will be redeemable again at its current balance.')) return;
                enableMutation.mutate();
              }}
              disabled={enableMutation.isPending}
              className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg border border-green-200 dark:border-green-800 text-green-700 dark:text-green-300 hover:bg-green-50 dark:hover:bg-green-900/20 disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <RefreshCw className="h-4 w-4" />
              Re-enable card
            </button>
          </div>
        )}
        {card.status !== 'disabled' && canReload && (() => {
          // WEB-UIUX-999: server-side `GIFT_CARD_MAX_AMOUNT = 10_000` rejects
          // any reload that would push balance over $10k. Pre-disable here so
          // the cashier doesn't type, submit, then get a generic toast.
          const GIFT_CARD_MAX_BALANCE = 10_000;
          const atCap = dollarsFromMaybeCents(card.current_balance) >= GIFT_CARD_MAX_BALANCE;
          return (
            <div className="mt-4 pt-4 border-t border-surface-100 dark:border-surface-800">
              {/* WEB-UIUX-1010: promote Reload balance to the primary CTA on
                  active cards — it's the most common action and was visually
                  indistinguishable from Disable/Resend secondary buttons.
                  Used-status cards keep the muted outline since reload is
                  topping up a depleted card, not the main flow. */}
              <button
                onClick={() => setShowReloadModal(true)}
                disabled={atCap}
                title={atCap ? `Card at maximum balance ${formatCurrencyShared(GIFT_CARD_MAX_BALANCE)}` : undefined}
                className={
                  card.status === 'used'
                    ? 'inline-flex items-center gap-2 rounded-lg border border-surface-200 dark:border-surface-700 px-3 py-1.5 text-sm text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-50 disabled:cursor-not-allowed'
                    : 'inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed'
                }
              >
                <RefreshCw className="h-4 w-4" />
                Reload balance
              </button>
            </div>
          );
        })()}
      </div>

      {/* Transaction History */}
      {(() => {
        const txs = card.transactions;
        const totalPages = Math.max(1, Math.ceil(txs.length / TX_PAGE_SIZE));
        const safePage = Math.min(txPage, totalPages - 1);
        const start = safePage * TX_PAGE_SIZE;
        const end = Math.min(start + TX_PAGE_SIZE, txs.length);
        const pageTxs = txs.slice(start, end);
        return (
          <div className="bg-white dark:bg-surface-900 border border-surface-200 dark:border-surface-800 rounded-xl overflow-hidden">
            <div className="px-5 py-3 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between gap-4">
              <h2 className="text-sm font-semibold text-surface-800 dark:text-surface-200">Transaction history</h2>
              {txs.length > 0 && (
                <span className="text-xs text-surface-400 dark:text-surface-500 shrink-0">
                  {start + 1}–{end} of {txs.length}
                </span>
              )}
            </div>
            {txs.length === 0 ? (
              <EmptyState
                icon={ReceiptText}
                title="No transactions yet"
                description="Transactions will appear here once the card is used or reloaded."
              />
            ) : (
              <>
                <div className="overflow-x-auto">
              <table className="w-full text-sm">
                  <thead>
                    <tr className="border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/50">
                      <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Date</th>
                      <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Type</th>
                      <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Notes</th>
                      {/* WEB-UIUX-991: cashier name from JOIN users. */}
                      <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">By</th>
                      {/* WEB-UIUX-992: invoice deep-link for redemptions. */}
                      <th className="text-left px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Invoice</th>
                      <th className="text-right px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                    {pageTxs.map((tx) => {
                      const byName = [tx.by_first_name, tx.by_last_name]
                        .filter(Boolean)
                        .join(' ')
                        .trim();
                      return (
                      <tr key={tx.id}>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{formatDate(tx.created_at)}</td>
                        <td className="px-5 py-3 text-surface-700 dark:text-surface-300">{txLabel(tx.type, tx.amount)}</td>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{tx.notes ?? '—'}</td>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">
                          {byName || (tx.user_id ? `User #${tx.user_id}` : '—')}
                        </td>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">
                          {tx.invoice_id ? (
                            <Link
                              to={`/invoices/${tx.invoice_id}`}
                              className="text-primary-600 dark:text-primary-400 hover:underline font-mono text-xs"
                            >
                              {tx.invoice_order_id ?? `INV-${tx.invoice_id}`}
                            </Link>
                          ) : (
                            '—'
                          )}
                        </td>
                        <td className={`px-5 py-3 text-right font-medium ${txColor(tx.type, tx.amount)}`}>
                          {/* Fixer-WW: sign driven by tx.type so redemptions always
                              render `-$X` (matches POS convention) and -0 amounts
                              no longer flash as `+$0.00` (Math.abs trips -0). */}
                          {tx.type === 'redemption' ? '-' : tx.amount > 0 ? '+' : tx.amount < 0 ? '-' : ''}{formatCurrency(tx.amount)}
                        </td>
                      </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
                {totalPages > 1 && (
                  <div className="flex items-center justify-between px-5 py-3 border-t border-surface-100 dark:border-surface-800">
                    <button
                      onClick={() => setTxPage((p) => Math.max(0, p - 1))}
                      disabled={safePage === 0}
                      className="px-3 py-1.5 text-xs rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      Previous
                    </button>
                    <span className="text-xs text-surface-500 dark:text-surface-400">
                      Page {safePage + 1} of {totalPages}
                    </span>
                    <button
                      onClick={() => setTxPage((p) => Math.min(totalPages - 1, p + 1))}
                      disabled={safePage >= totalPages - 1}
                      className="px-3 py-1.5 text-xs rounded-lg border border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-40 disabled:cursor-not-allowed"
                    >
                      Next
                    </button>
                  </div>
                )}
              </>
            )}
          </div>
        );
      })()}

      {showReloadModal && (
        <ReloadModal
          cardId={card.id}
          currentBalance={dollarsFromMaybeCents(card.current_balance)}
          onClose={() => setShowReloadModal(false)}
        />
      )}
    </div>
  );
}
