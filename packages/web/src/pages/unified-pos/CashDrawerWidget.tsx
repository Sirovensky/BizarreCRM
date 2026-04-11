import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { DollarSign, Lock, Unlock, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { formatCents } from '@/utils/format';
import { ZReportModal } from './ZReportModal';

// Drawer safety ceilings (criticalaudit-rerun §3, bug 5):
//  - Default: reject > $50,000 closing count or opening float.
//  - High-volume stores can raise this via store_config.pos_high_volume_drawer.
//  - These are UI guard-rails — the server enforces the same limit.
const DRAWER_CAP_CENTS = 5_000_000;
const DRAWER_CAP_DOLLARS = DRAWER_CAP_CENTS / 100;

/**
 * Cash drawer shift widget (audit §43.4, §43.8).
 *
 * Surfaces the current shift: if none is open, prompts to enter an opening
 * float; if open, exposes a "Close shift" button that opens the counting
 * modal and runs the Z-report. All dollar values are entered and displayed
 * normally but the wire format is integer cents (prevents POS5 float drift).
 */

interface DrawerShift {
  id: number;
  opened_by_user_id: number;
  opened_at: string;
  opening_float_cents: number;
  closed_at: string | null;
}

interface CurrentShiftResponse {
  data: DrawerShift | null;
}

/**
 * Parse a dollar-string input into integer cents. Uses Math.round to kill
 * the `parseFloat(x) * 100` float-binary trap where 10.99 becomes
 * 1098.9999999 instead of 1099 (criticalaudit-rerun §3 bug 3).
 *
 * Returns a tagged result so the caller can distinguish "empty input"
 * from "explicit zero" — the latter is a valid cash count.
 */
function centsFromInput(value: string): { ok: boolean; cents: number; reason?: string } {
  const trimmed = value.trim();
  if (!trimmed) return { ok: false, cents: 0, reason: 'Enter an amount' };
  const n = parseFloat(trimmed);
  if (!Number.isFinite(n) || isNaN(n) || n < 0) {
    return { ok: false, cents: 0, reason: 'Enter a non-negative amount' };
  }
  if (n > DRAWER_CAP_DOLLARS) {
    return {
      ok: false,
      cents: 0,
      reason: `Amount exceeds $${DRAWER_CAP_DOLLARS.toLocaleString()} drawer cap`,
    };
  }
  return { ok: true, cents: Math.round(n * 100) };
}

export function CashDrawerWidget() {
  const qc = useQueryClient();
  const [openModal, setOpenModal] = useState<'open' | 'close' | null>(null);
  const [zReportShiftId, setZReportShiftId] = useState<number | null>(null);

  const { data: shift, isLoading } = useQuery({
    queryKey: ['pos-enrich', 'drawer-current'],
    queryFn: async () => {
      const res = await api.get<CurrentShiftResponse>('/pos-enrich/drawer/current');
      return res.data.data;
    },
    staleTime: 30_000,
  });

  if (isLoading) return null;

  const handleClosed = (shiftId: number) => {
    setOpenModal(null);
    setZReportShiftId(shiftId);
    qc.invalidateQueries({ queryKey: ['pos-enrich', 'drawer-current'] });
  };

  return (
    <>
      <div className="flex items-center gap-2">
        {shift ? (
          <button
            onClick={() => setOpenModal('close')}
            className="flex items-center gap-1.5 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 text-sm font-medium text-amber-700 hover:bg-amber-100 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300"
            title={`Shift opened at ${new Date(shift.opened_at).toLocaleTimeString()} · float ${formatCents(shift.opening_float_cents)}`}
          >
            <Unlock className="h-4 w-4" />
            Close Shift
          </button>
        ) : (
          <button
            onClick={() => setOpenModal('open')}
            className="flex items-center gap-1.5 rounded-lg border border-teal-300 bg-teal-50 px-3 py-2 text-sm font-medium text-teal-700 hover:bg-teal-100 dark:border-teal-500/30 dark:bg-teal-500/10 dark:text-teal-300"
          >
            <Lock className="h-4 w-4" />
            Start Shift
          </button>
        )}
      </div>

      {openModal === 'open' && (
        <OpenShiftModal
          onClose={() => setOpenModal(null)}
          onOpened={() => {
            setOpenModal(null);
            qc.invalidateQueries({ queryKey: ['pos-enrich', 'drawer-current'] });
          }}
        />
      )}
      {openModal === 'close' && shift && (
        <CloseShiftModal
          shift={shift}
          onClose={() => setOpenModal(null)}
          onClosed={handleClosed}
        />
      )}
      {zReportShiftId !== null && (
        <ZReportModal shiftId={zReportShiftId} onClose={() => setZReportShiftId(null)} />
      )}
    </>
  );
}

// ── Open shift modal ────────────────────────────────────────────────────────

interface OpenShiftModalProps {
  onClose: () => void;
  onOpened: () => void;
}

function OpenShiftModal({ onClose, onOpened }: OpenShiftModalProps) {
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    const parsed = centsFromInput(amount);
    if (!parsed.ok || parsed.cents <= 0) {
      toast.error(parsed.reason ?? 'Enter a valid opening float');
      return;
    }
    setSubmitting(true);
    try {
      await api.post('/pos-enrich/drawer/open', {
        opening_float_cents: parsed.cents,
        notes: notes.trim() || undefined,
      });
      toast.success('Shift opened');
      onOpened();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to open shift');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Open Cash Drawer Shift
          </h3>
          <button onClick={onClose} className="rounded p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-3 p-5">
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Opening Float ($)</span>
            <input
              type="number"
              step="0.01"
              min="0"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="200.00"
              autoFocus
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Notes (optional)</span>
            <input
              type="text"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="Morning shift"
            />
          </label>
          <button
            onClick={submit}
            disabled={submitting}
            className="w-full rounded-lg bg-teal-600 py-2 text-sm font-medium text-white hover:bg-teal-700 disabled:opacity-50"
          >
            {submitting ? 'Opening...' : 'Open Shift'}
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Close shift modal ───────────────────────────────────────────────────────

interface CloseShiftModalProps {
  shift: DrawerShift;
  onClose: () => void;
  onClosed: (shiftId: number) => void;
}

function CloseShiftModal({ shift, onClose, onClosed }: CloseShiftModalProps) {
  const [counted, setCounted] = useState('');
  const [notes, setNotes] = useState('');
  const [submitting, setSubmitting] = useState(false);

  const submit = async () => {
    const parsed = centsFromInput(counted);
    if (!parsed.ok) {
      toast.error(parsed.reason ?? 'Enter a valid counted amount');
      return;
    }
    setSubmitting(true);
    try {
      await api.post(`/pos-enrich/drawer/${shift.id}/close`, {
        closing_counted_cents: parsed.cents,
        notes: notes.trim() || undefined,
      });
      toast.success('Shift closed');
      onClosed(shift.id);
    } catch (err) {
      toast.error(err instanceof Error ? err.message : 'Failed to close shift');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Close Shift & Count Drawer
          </h3>
          <button onClick={onClose} className="rounded p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-3 p-5">
          <div className="flex items-center gap-2 rounded-lg bg-surface-50 p-3 text-xs text-surface-600 dark:bg-surface-800 dark:text-surface-400">
            <DollarSign className="h-4 w-4" />
            Opened at {new Date(shift.opened_at).toLocaleTimeString()} · float {formatCents(shift.opening_float_cents)}
          </div>
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Counted Cash ($)</span>
            <input
              type="number"
              step="0.01"
              min="0"
              value={counted}
              onChange={(e) => setCounted(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="0.00"
              autoFocus
            />
          </label>
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Notes (optional)</span>
            <input
              type="text"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus:border-teal-500 focus:outline-none focus:ring-1 focus:ring-teal-500 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="End of day"
            />
          </label>
          <button
            onClick={submit}
            disabled={submitting}
            className="w-full rounded-lg bg-amber-600 py-2 text-sm font-medium text-white hover:bg-amber-700 disabled:opacity-50"
          >
            {submitting ? 'Closing...' : 'Close Shift & View Z-Report'}
          </button>
        </div>
      </div>
    </div>
  );
}
