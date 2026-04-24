import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { DollarSign, ArrowUpCircle, ArrowDownCircle, Loader2, Clock } from 'lucide-react';
import toast from 'react-hot-toast';
import { posApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

// Each recent cash-drawer event the register endpoint returns. `first_name`/
// `last_name` come from the joined user row; keeping them optional so the UI
// still renders if the server dropped the join.
interface CashRegisterHistoryEntry {
  id: number;
  type: 'cash_in' | 'cash_out';
  amount: number;
  reason?: string | null;
  first_name?: string | null;
  last_name?: string | null;
  [key: string]: unknown;
}

export function CashRegisterPage() {
  const queryClient = useQueryClient();
  const [cashAction, setCashAction] = useState<'in' | 'out' | null>(null);
  const [amount, setAmount] = useState('');
  const [reason, setReason] = useState('');

  const { data, isLoading } = useQuery({
    queryKey: ['cash-register'],
    queryFn: () => posApi.register(),
    refetchInterval: 30000,
    staleTime: 25_000, // just under the 30s interval
  });

  // SCAN-1121: server returns `{ cash_in, cash_out, cash_sales, net, entries }`
  // (see pos.routes.ts GET /register). This page was reading
  // `cash_payments`/`balance`/`recent` — all undefined — so Balance + Cash
  // Payments cards were permanently $0 and the history was always empty.
  // Align the UI keys with the actual envelope and keep the local type
  // in sync.
  const register = data?.data?.data || {};
  const history: CashRegisterHistoryEntry[] = Array.isArray(register.entries)
    ? (register.entries as CashRegisterHistoryEntry[])
    : [];

  const cashInMut = useMutation({
    mutationFn: () => posApi.cashIn({ amount: parseFloat(amount), reason: reason || undefined }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cash-register'] });
      toast.success('Cash in recorded');
      setCashAction(null); setAmount(''); setReason('');
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } } | undefined;
      toast.error(err?.response?.data?.message || 'Failed');
    },
  });

  const cashOutMut = useMutation({
    mutationFn: () => posApi.cashOut({ amount: parseFloat(amount), reason: reason || undefined }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['cash-register'] });
      toast.success('Cash out recorded');
      setCashAction(null); setAmount(''); setReason('');
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } } | undefined;
      toast.error(err?.response?.data?.message || 'Failed');
    },
  });

  const handleSubmit = () => {
    if (!amount || parseFloat(amount) <= 0) return toast.error('Enter a valid amount');
    if (cashAction === 'in') cashInMut.mutate();
    else cashOutMut.mutate();
  };

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Cash Register</h1>
        <p className="text-sm text-surface-500 dark:text-surface-400">Today's cash register summary</p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-6">
        <div className="card p-4">
          <p className="text-xs text-surface-500 mb-1">Cash In</p>
          <p className="text-xl font-bold text-green-600">{formatCurrency(register.cash_in || 0)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-surface-500 mb-1">Cash Out</p>
          <p className="text-xl font-bold text-red-600">{formatCurrency(register.cash_out || 0)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-surface-500 mb-1">Cash Payments</p>
          <p className="text-xl font-bold text-blue-600">{formatCurrency(register.cash_sales || 0)}</p>
        </div>
        <div className="card p-4">
          <p className="text-xs text-surface-500 mb-1">Balance</p>
          <p className={cn('text-xl font-bold', (register.net || 0) >= 0 ? 'text-surface-900 dark:text-surface-100' : 'text-red-600')}>
            {formatCurrency(register.net || 0)}
          </p>
        </div>
      </div>

      {/* Action buttons */}
      <div className="flex gap-3 mb-6">
        <button onClick={() => setCashAction(cashAction === 'in' ? null : 'in')}
          className={cn('inline-flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-colors',
            cashAction === 'in' ? 'bg-green-600 text-white' : 'border border-green-200 dark:border-green-800 text-green-700 dark:text-green-400 hover:bg-green-50 dark:hover:bg-green-900/20')}>
          <ArrowUpCircle className="h-4 w-4" /> Cash In
        </button>
        <button onClick={() => setCashAction(cashAction === 'out' ? null : 'out')}
          className={cn('inline-flex items-center gap-2 rounded-lg px-4 py-2.5 text-sm font-medium transition-colors',
            cashAction === 'out' ? 'bg-red-600 text-white' : 'border border-red-200 dark:border-red-800 text-red-700 dark:text-red-400 hover:bg-red-50 dark:hover:bg-red-900/20')}>
          <ArrowDownCircle className="h-4 w-4" /> Cash Out
        </button>
      </div>

      {/* Cash in/out form */}
      {cashAction && (
        <div className="card p-5 mb-6">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100 mb-3">
            {cashAction === 'in' ? 'Cash In' : 'Cash Out'}
          </h3>
          <div className="flex gap-3">
            <input type="number" step="0.01" min="0" value={amount} onChange={(e) => setAmount(e.target.value)}
              placeholder="Amount" className="w-32 px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <input value={reason} onChange={(e) => setReason(e.target.value)}
              placeholder="Reason (optional)" className="flex-1 px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <button onClick={handleSubmit} disabled={cashInMut.isPending || cashOutMut.isPending}
              className={cn('px-4 py-2 text-sm font-medium text-white rounded-lg disabled:opacity-50',
                cashAction === 'in' ? 'bg-green-600 hover:bg-green-700' : 'bg-red-600 hover:bg-red-700')}>
              {(cashInMut.isPending || cashOutMut.isPending) ? <Loader2 className="h-4 w-4 animate-spin" /> : 'Record'}
            </button>
          </div>
        </div>
      )}

      {/* History */}
      <div className="card overflow-hidden">
        <div className="px-4 py-3 border-b border-surface-200 dark:border-surface-700">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">Today's History</h3>
        </div>
        {isLoading ? (
          <div className="flex justify-center py-12"><Loader2 className="h-6 w-6 animate-spin text-surface-400" /></div>
        ) : history.length === 0 ? (
          <div className="text-center py-12 text-surface-400">
            <DollarSign className="h-10 w-10 mx-auto mb-2 text-surface-300" />
            <p>No cash register activity today</p>
          </div>
        ) : (
          <div className="divide-y divide-surface-100 dark:divide-surface-800">
            {history.map((entry) => (
              <div key={entry.id} className="flex items-center gap-3 px-4 py-3">
                <div className={cn('flex h-8 w-8 items-center justify-center rounded-full',
                  entry.type === 'cash_in' ? 'bg-green-100 text-green-600 dark:bg-green-900/30' : 'bg-red-100 text-red-600 dark:bg-red-900/30')}>
                  {entry.type === 'cash_in' ? <ArrowUpCircle className="h-4 w-4" /> : <ArrowDownCircle className="h-4 w-4" />}
                </div>
                <div className="flex-1 min-w-0">
                  <p className="text-sm text-surface-900 dark:text-surface-100 font-medium capitalize">{entry.type.replace('_', ' ')}</p>
                  {entry.reason && <p className="text-xs text-surface-500 truncate">{entry.reason}</p>}
                </div>
                <div className="text-right shrink-0">
                  <p className={cn('text-sm font-medium', entry.type === 'cash_in' ? 'text-green-600' : 'text-red-600')}>
                    {entry.type === 'cash_in' ? '+' : '-'}{formatCurrency(entry.amount)}
                  </p>
                  <p className="text-[10px] text-surface-400">
                    {entry.first_name} {entry.last_name}
                  </p>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>
    </div>
  );
}
