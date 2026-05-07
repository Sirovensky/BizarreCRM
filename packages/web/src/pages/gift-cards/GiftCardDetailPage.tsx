import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useFocusTrap } from '@/hooks/useFocusTrap';
import { useBodyScrollLock } from '@/hooks/useBodyScrollLock';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Eye, EyeOff, RefreshCw, Loader2, AlertCircle, Gift, ReceiptText } from 'lucide-react';
import toast from 'react-hot-toast';
import { giftCardApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { SkeletonCard, SkeletonTable } from '@/components/shared/Skeleton';
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
  onClose: () => void;
}

function ReloadModal({ cardId, onClose }: ReloadModalProps) {
  const queryClient = useQueryClient();
  const [amount, setAmount] = useState('');
  const [amountError, setAmountError] = useState<string | null>(null);
  // WEB-UIUX-557: focus-trap + scroll-lock (component only mounts when open).
  const dialogRef = useFocusTrap(true, { initialFocusSelector: 'input[type="number"]' }) as { current: HTMLDivElement | null };
  useBodyScrollLock(true);

  const reloadMutation = useMutation({
    mutationFn: (value: number) => giftCardApi.reload(cardId, { amount: value }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['gift-card', cardId] });
      toast.success('Gift card reloaded');
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
        <p id="gift-card-reload-help" className="mt-2 mb-5 text-xs text-surface-500 dark:text-surface-400">
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
          <ArrowLeft className="h-4 w-4" /> Gift Cards
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
          <ArrowLeft className="h-4 w-4" /> Gift Cards
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
      <button
        onClick={() => navigate('/gift-cards')}
        className="flex items-center gap-1.5 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200 mb-6"
      >
        <ArrowLeft className="h-4 w-4" />
        Gift Cards
      </button>

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
                  {showCode ? card.code : `****${card.code.slice(-4)}`}
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

          <div className="text-right">
            <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{formatBalance(card.current_balance)}</p>
            <p className="text-xs text-surface-500 dark:text-surface-400">of {formatBalance(card.initial_balance)} initial</p>
          </div>
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
              <dd className="mt-0.5 text-surface-700 dark:text-surface-300 truncate">{card.recipient_email}</dd>
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
        </dl>

        {/* WEB-UIUX-1442: server allows reload on any status except disabled; show button for 'used' too (secondary tone indicates topping up a depleted card) */}
        {card.status !== 'disabled' && canReload && (
          <div className="mt-4 pt-4 border-t border-surface-100 dark:border-surface-800">
            <button
              onClick={() => setShowReloadModal(true)}
              className={`flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg border ${
                card.status === 'used'
                  ? 'border-surface-200 dark:border-surface-700 text-surface-400 dark:text-surface-500 hover:bg-surface-50 dark:hover:bg-surface-800'
                  : 'border-surface-200 dark:border-surface-700 text-surface-700 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800'
              }`}
            >
              <RefreshCw className="h-4 w-4" />
              Reload balance
            </button>
          </div>
        )}
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
                      <th className="text-right px-5 py-2.5 font-medium text-surface-500 dark:text-surface-400">Amount</th>
                    </tr>
                  </thead>
                  <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                    {pageTxs.map((tx) => (
                      <tr key={tx.id}>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{formatDate(tx.created_at)}</td>
                        <td className="px-5 py-3 text-surface-700 dark:text-surface-300">{txLabel(tx.type, tx.amount)}</td>
                        <td className="px-5 py-3 text-surface-500 dark:text-surface-400">{tx.notes ?? '—'}</td>
                        <td className={`px-5 py-3 text-right font-medium ${txColor(tx.type, tx.amount)}`}>
                          {/* Fixer-WW: sign driven by tx.type so redemptions always
                              render `-$X` (matches POS convention) and -0 amounts
                              no longer flash as `+$0.00` (Math.abs trips -0). */}
                          {tx.type === 'redemption' ? '-' : tx.amount > 0 ? '+' : tx.amount < 0 ? '-' : ''}{formatCurrency(tx.amount)}
                        </td>
                      </tr>
                    ))}
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
        <ReloadModal cardId={card.id} onClose={() => setShowReloadModal(false)} />
      )}
    </div>
  );
}
