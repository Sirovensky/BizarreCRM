import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, Package, CheckCircle2, AlertCircle, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { loanerApi, type LoanerDevice } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatDate } from '@/utils/format';

// ─── Return Dialog ─────────────────────────────────────────────────────────

interface ReturnDialogProps {
  device: LoanerDevice;
  onClose: () => void;
}

function ReturnDialog({ device, onClose }: ReturnDialogProps) {
  const queryClient = useQueryClient();
  const [conditionIn, setConditionIn] = useState('good');
  const [damageNotes, setDamageNotes] = useState('');

  const returnMutation = useMutation({
    mutationFn: () =>
      loanerApi.returnDevice(device.id, {
        condition_in: conditionIn,
        notes: damageNotes.trim() || undefined,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['loaners'] });
      toast.success(`${device.name} marked as returned`);
      onClose();
    },
    onError: (e: unknown) => {
      const err = e as { response?: { data?: { message?: string } } };
      toast.error(err?.response?.data?.message || 'Failed to mark device as returned');
    },
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="loaner-return-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-sm p-6" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between mb-4">
          <h2 id="loaner-return-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">Mark Returned</h2>
          <button aria-label="Close" onClick={onClose} className="rounded p-1 text-surface-400 hover:text-surface-600">
            <X className="h-4 w-4" />
          </button>
        </div>
        <p className="text-sm text-surface-500 dark:text-surface-400 mb-4">
          Returning <span className="font-semibold text-surface-900 dark:text-surface-100">{device.name}</span>
          {device.loaned_to ? ` from ${device.loaned_to}` : ''}.
        </p>
        <div className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Return Condition
            </label>
            <select
              value={conditionIn}
              onChange={(e) => setConditionIn(e.target.value)}
              className="input w-full"
            >
              <option value="good">Good</option>
              <option value="fair">Fair</option>
              <option value="damaged">Damaged</option>
              <option value="missing">Missing parts</option>
            </select>
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
              Damage Notes <span className="text-surface-400 font-normal">(optional)</span>
            </label>
            <textarea
              value={damageNotes}
              onChange={(e) => setDamageNotes(e.target.value)}
              rows={3}
              className="input w-full resize-none"
              placeholder="Describe any damage or missing items..."
            />
          </div>
        </div>
        <div className="flex gap-3 mt-6">
          <button
            onClick={onClose}
            className="flex-1 px-4 py-2.5 text-sm font-medium rounded-lg border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={() => returnMutation.mutate()}
            disabled={returnMutation.isPending}
            className="flex-1 px-4 py-2.5 bg-green-600 hover:bg-green-700 text-white rounded-lg text-sm font-medium transition-colors disabled:opacity-50"
          >
            {returnMutation.isPending ? 'Returning...' : 'Confirm Return'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Main Page ─────────────────────────────────────────────────────────────

export function LoanersPage() {
  const [returningDevice, setReturningDevice] = useState<LoanerDevice | null>(null);

  const { data, isLoading } = useQuery({
    queryKey: ['loaners'],
    queryFn: () => loanerApi.list({ per_page: 100 }),
    staleTime: 30_000,
  });

  const devices: LoanerDevice[] = data?.data?.data ?? [];

  if (isLoading) {
    return (
      <div className="flex items-center justify-center h-64">
        <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
      </div>
    );
  }

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Loaner Devices</h1>
        <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
          Track devices loaned to customers during repairs.
        </p>
      </div>

      {devices.length === 0 ? (
        <div className="text-center py-20 text-surface-400">
          <Package className="h-12 w-12 mx-auto mb-3 opacity-30" />
          <p className="text-sm">No loaner devices configured.</p>
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {devices.map((device) => {
            const isOut = device.status === 'loaned' || device.is_loaned_out;
            return (
              <div
                key={device.id}
                className="card p-5 flex flex-col gap-3"
              >
                {/* Header */}
                <div className="flex items-start justify-between gap-2">
                  <div className="flex items-center gap-2 min-w-0">
                    <Package className="h-5 w-5 flex-shrink-0 text-surface-400" />
                    <span className="font-semibold text-surface-900 dark:text-surface-100 truncate">
                      {device.name}
                    </span>
                  </div>
                  <span
                    className={cn(
                      'inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-medium flex-shrink-0',
                      isOut
                        ? 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400'
                        : 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
                    )}
                  >
                    {isOut ? (
                      <><AlertCircle className="h-3 w-3" /> Loaned out</>
                    ) : (
                      <><CheckCircle2 className="h-3 w-3" /> Available</>
                    )}
                  </span>
                </div>

                {/* Details */}
                <div className="text-xs text-surface-500 dark:text-surface-400 space-y-0.5">
                  <p>Condition: <span className="capitalize">{device.condition}</span></p>
                  {device.loaned_to && (
                    <p>Loaned to: <span className="font-medium text-surface-700 dark:text-surface-300">{device.loaned_to}</span></p>
                  )}
                  {device.notes && <p className="truncate" title={device.notes}>Note: {device.notes}</p>}
                  <p>Updated: {formatDate(device.updated_at)}</p>
                </div>

                {/* Action */}
                {isOut && (
                  <button
                    type="button"
                    onClick={() => setReturningDevice(device)}
                    className="mt-auto inline-flex items-center justify-center gap-2 px-3 py-2 text-sm font-medium rounded-lg bg-green-600 hover:bg-green-700 text-white transition-colors"
                  >
                    <CheckCircle2 aria-hidden="true" className="h-4 w-4" /> Mark Returned
                  </button>
                )}
              </div>
            );
          })}
        </div>
      )}

      {returningDevice && (
        <ReturnDialog device={returningDevice} onClose={() => setReturningDevice(null)} />
      )}
    </div>
  );
}
