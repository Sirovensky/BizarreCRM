import { useState, useEffect, useRef } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { DollarSign, Lock, Unlock, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
// @audit-fixed (WEB-FF-003 / Fixer-UUU 2026-04-25): drawer-cap toast used hardcoded "$" — switch to formatCurrency for tenant currency.
import { formatCents, formatCurrency } from '@/utils/format';
import { ZReportModal } from './ZReportModal';
import { useUnifiedPosActionVisibility } from './permissions';

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
      reason: `Amount exceeds ${formatCurrency(DRAWER_CAP_DOLLARS)} drawer cap`,
    };
  }
  return { ok: true, cents: Math.round(n * 100) };
}

export function CashDrawerWidget() {
  const qc = useQueryClient();
  const [openModal, setOpenModal] = useState<'open' | 'close' | null>(null);
  const [zReportShiftId, setZReportShiftId] = useState<number | null>(null);
  const { canCloseDrawerShift } = useUnifiedPosActionVisibility();

  const { data: shift, isLoading } = useQuery({
    queryKey: ['pos-enrich', 'drawer-current'],
    queryFn: async () => {
      const res = await api.get<CurrentShiftResponse>('/pos-enrich/drawer/current');
      return res.data.data;
    },
    staleTime: 30_000,
  });

  // WEB-UIUX-1180: render a disabled placeholder while loading so the layout
  // does not shift (returning null collapses the widget's reserved space).
  if (isLoading) {
    return (
      <button disabled className="btn btn-sm border border-surface-300 bg-surface-50 text-surface-400 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-500 opacity-60 cursor-not-allowed">
        Loading…
      </button>
    );
  }

  const handleClosed = (shiftId: number) => {
    setOpenModal(null);
    setZReportShiftId(shiftId);
    qc.invalidateQueries({ queryKey: ['pos-enrich', 'drawer-current'] });
  };

  return (
    <>
      <div className="flex items-center gap-2">
        {shift && canCloseDrawerShift ? (
          <button
            onClick={() => setOpenModal('close')}
            className="btn btn-sm border border-amber-300 bg-amber-50 text-amber-700 hover:bg-amber-100 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300"
            title={`Shift opened at ${new Date(shift.opened_at).toLocaleTimeString()} · float ${formatCents(shift.opening_float_cents)}`}
          >
            <Unlock className="h-4 w-4" />
            Close Shift
          </button>
        ) : shift ? (
          <span
            className="inline-flex h-9 items-center gap-2 rounded-md border border-surface-300 px-3 text-sm font-medium text-surface-600 dark:border-surface-600 dark:text-surface-300"
            title={`Shift opened at ${new Date(shift.opened_at).toLocaleTimeString()} · float ${formatCents(shift.opening_float_cents)}`}
          >
            <Unlock className="h-4 w-4" />
            Shift Open
          </span>
        ) : (
          <button
            onClick={() => setOpenModal('open')}
            className="btn btn-sm border border-teal-300 bg-teal-50 text-teal-700 hover:bg-teal-100 dark:border-teal-500/30 dark:bg-teal-500/10 dark:text-teal-300"
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
  // WEB-UIUX-1177: track inline error so we can keep the amount value and
  // refocus the input instead of swallowing the failure into a toast.
  const [error, setError] = useState('');
  const amountRef = useRef<HTMLInputElement>(null);

  // WEB-UIUX-1177: re-focus amount input whenever an error is set.
  useEffect(() => {
    if (error) amountRef.current?.focus();
  }, [error]);

  const submit = async () => {
    const parsed = centsFromInput(amount);
    if (!parsed.ok) {
      setError(parsed.reason ?? 'Enter a valid opening float');
      return;
    }
    setError('');
    setSubmitting(true);
    try {
      // WEB-UIUX-1178: use server response to include shift id + float in toast.
      const resp = await api.post('/pos-enrich/drawer/open', {
        opening_float_cents: parsed.cents,
        notes: notes.trim() || undefined,
      });
      const openedShift = resp.data?.data;
      if (openedShift?.id != null) {
        toast.success(
          `Shift #${openedShift.id} opened (float ${formatCurrency(openedShift.opening_float_cents / 100)})`
        );
      } else {
        toast.success('Shift opened');
      }
      onOpened();
    } catch (err) {
      const msg = err instanceof Error ? err.message : 'Failed to open shift';
      setError(msg);
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
          <button onClick={onClose} className="btn-icon btn-xs" aria-label="Close">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="space-y-3 p-5">
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Opening Float ($)</span>
            <input
              ref={amountRef}
              type="text" inputMode="decimal" pattern="[0-9.]*"
              step="0.01"
              min="0"
              value={amount}
              onChange={(e) => { setAmount(e.target.value); setError(''); }}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder=""
              autoFocus
              // WEB-UIUX-1184: aria-describedby chains hint + error ids when both present.
              aria-describedby={`open-shift-hint${error ? ' open-shift-error' : ''}`}
            />
          </label>
          {/* WEB-UIUX-1184: always-visible hint for screen readers + sighted users */}
          <p id="open-shift-hint" className="text-xs text-surface-400 dark:text-surface-500">
            Enter amount in dollars and cents
          </p>
          {error && (
            <p id="open-shift-error" role="alert" aria-live="polite" className="text-xs text-red-500">
              {error}
            </p>
          )}
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Notes (optional)</span>
            <input
              type="text"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="Morning shift"
            />
          </label>
          <button
            onClick={submit}
            disabled={submitting}
            className="btn btn-md w-full bg-teal-600 text-white hover:bg-teal-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
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
  const qc = useQueryClient();

  const submit = async () => {
    const parsed = centsFromInput(counted);
    if (!parsed.ok) {
      toast.error(parsed.reason ?? 'Enter a valid counted amount');
      return;
    }
    setSubmitting(true);
    try {
      // WEB-UIUX-1167: capture response and seed z-report cache before onClosed/openZReport
      // so the ZReportModal never has to round-trip to fetch data it already has.
      const resp = await api.post(`/pos-enrich/drawer/${shift.id}/close`, {
        closing_counted_cents: parsed.cents,
        notes: notes.trim() || undefined,
      });
      if (resp.data?.data) {
        qc.setQueryData(['pos-enrich', 'z-report', shift.id], resp.data.data);
      }
      // WEB-UIUX-1178: use server response (shift_id + variance_cents) for a
      // meaningful close toast rather than a generic "Shift closed" message.
      const zReport = resp.data?.data;
      if (zReport?.shift_id != null && zReport?.variance_cents != null) {
        const v = zReport.variance_cents;
        const varianceLabel =
          v === 0
            ? 'balanced'
            : v > 0
              ? `over by ${formatCents(v)}`
              : `short by ${formatCents(Math.abs(v))}`;
        toast.success(`Shift #${zReport.shift_id} closed — ${varianceLabel}`);
      } else {
        toast.success('Shift closed');
      }
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
          <button onClick={onClose} className="btn-icon btn-xs" aria-label="Close">
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
              type="text" inputMode="decimal" pattern="[0-9.]*"
              step="0.01"
              min="0"
              value={counted}
              onChange={(e) => setCounted(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              // WEB-UIUX-1184: empty placeholder (was "0.00") to avoid implying a default value.
              placeholder=""
              autoFocus
              aria-describedby="close-shift-hint"
            />
          </label>
          {/* WEB-UIUX-1184: aria hint for the counted cash input */}
          <p id="close-shift-hint" className="text-xs text-surface-400 dark:text-surface-500">
            Enter amount in dollars and cents
          </p>
          <label className="block">
            <span className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400">Notes (optional)</span>
            <input
              type="text"
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="w-full rounded-lg border border-surface-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:border-teal-500 focus-visible:ring-2 focus-visible:ring-teal-500/20 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
              placeholder="End of day"
            />
          </label>
          <button
            onClick={submit}
            disabled={submitting}
            className="btn btn-md w-full bg-amber-600 text-white hover:bg-amber-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
          >
            {submitting ? 'Closing...' : 'Close Shift & View Z-Report'}
          </button>
        </div>
      </div>
    </div>
  );
}
