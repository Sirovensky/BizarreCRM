import { useEffect, useRef } from 'react';
import { useQuery } from '@tanstack/react-query';
import { X, Printer, TrendingUp, TrendingDown, Minus, AlertTriangle, RotateCcw } from 'lucide-react';
import { api } from '@/api/client';
import { settingsApi } from '@/api/endpoints';
import { formatCents, formatDateTime } from '@/utils/format';

/**
 * Z-report modal (audit §43.4, §43.8).
 *
 * Displays the end-of-shift report once a drawer is closed: payment method
 * breakdown, expected vs counted, over/short variance, transaction totals.
 * Also includes a "Print" button that opens the browser print dialog on a
 * minimal, receipt-shaped view.
 */

interface ZReport {
  shift_id: number;
  opened_at: string;
  closed_at: string;
  opening_float_cents: number;
  expected_cents: number;
  // WEB-UIUX-1162: null while the shift is in progress — no till count yet.
  counted_cents: number | null;
  variance_cents: number | null;
  /** Server-tagged when the shift is still open. Client renders an
   * "awaiting close" placeholder instead of a phantom variance banner. */
  in_progress?: boolean;
  // WEB-UIUX-1170: audit context surfaced on the Z-report — opener/closer
  // name, total minutes on shift, and any manager notes captured at close.
  opened_by_name?: string | null;
  closed_by_name?: string | null;
  duration_minutes?: number | null;
  notes?: string | null;
  payment_breakdown: Array<{ method: string; cents: number; count: number }>;
  totals: {
    gross_cents: number;
    refund_cents: number;
    net_cents: number;
    transaction_count: number;
  };
}

interface ZReportResponse {
  data: ZReport;
}

interface ZReportModalProps {
  shiftId: number;
  onClose: () => void;
}

/**
 * Locale-aware cents → currency formatter. Pre WEB-UIUX-1174 this helper was
 * named `formatSignedCents` and implied +/- sign handling that it never did —
 * locale formatCents() already encodes negatives via the locale's convention
 * (parentheses or hyphen). Kept as a thin wrapper purely to coerce NaN/∞
 * inputs to $0.00 instead of leaking "NaN" into the printable report.
 */
function formatMoney(cents: number): string {
  if (!Number.isFinite(cents)) return formatCents(0);
  return formatCents(cents);
}

export function ZReportModal({ shiftId, onClose }: ZReportModalProps) {
  const { data, isLoading, isError, refetch, isFetching } = useQuery({
    queryKey: ['pos-enrich', 'z-report', shiftId],
    queryFn: async () => {
      const res = await api.get<ZReportResponse>(`/pos-enrich/drawer/${shiftId}/z-report`);
      return res.data.data;
    },
  });
  // WEB-UIUX-1166: variance warn threshold lives in store_config so high-volume
  // stores can raise it past $5 without code changes. Default 500 cents.
  const { data: cfgData } = useQuery<Record<string, string>>({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 5 * 60_000,
  });
  const varianceWarnCents = Math.max(0, parseInt(cfgData?.['pos_variance_warn_cents'] ?? '500', 10) || 500);
  // Restore focus to the opener button after the modal unmounts so keyboard
  // users land back where they were.
  const triggerRef = useRef<HTMLElement | null>(null);
  useEffect(() => {
    triggerRef.current = (document.activeElement as HTMLElement) ?? null;
    return () => {
      const el = triggerRef.current;
      if (el && document.contains(el)) {
        try { el.focus({ preventScroll: true }); } catch { /* noop */ }
      }
    };
  }, []);

  // WEB-W3-016: inject a print-only <style> that hides everything on the page
  // EXCEPT the modal content, then call window.print(). The style tag is
  // mounted once (on modal open) and removed on unmount so it never leaks into
  // other print contexts. Using a data attribute instead of a class selector
  // avoids any coupling to Tailwind utility names that could change.
  useEffect(() => {
    const style = document.createElement('style');
    style.setAttribute('data-z-report-print', 'true');
    style.textContent = `
@media print {
  body > * { display: none !important; }
  [data-z-report-modal] { display: block !important; position: static !important; }
  [data-z-report-modal] > * { display: block !important; }
  [data-z-report-modal] .no-print { display: none !important; }
}
    `.trim();
    document.head.appendChild(style);
    return () => { style.remove(); };
  }, []);

  const handlePrint = () => window.print();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="z-report-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div
        data-z-report-modal
        className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl bg-white shadow-2xl dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 id="z-report-title" className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Z-Report · Shift #{shiftId}
          </h3>
          {/* no-print: header buttons are not useful on paper */}
          <div className="no-print flex items-center gap-1">
            <button
              onClick={handlePrint}
              aria-label="Print"
              className="btn-icon btn-sm text-surface-500"
            >
              <Printer className="h-4 w-4" />
            </button>
            <button
              onClick={onClose}
              aria-label="Close"
              className="btn-icon btn-sm"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="space-y-4 p-5">
          {isLoading && (
            <div aria-busy="true" aria-label="Loading Z-report" className="space-y-2">
              {[0, 1, 2].map((i) => (
                <div key={i} aria-hidden="true" className="h-8 motion-safe:animate-pulse rounded bg-surface-100 dark:bg-surface-800" />
              ))}
            </div>
          )}
          {isError && (
            <div role="alert" aria-live="assertive" className="space-y-3 text-center">
              <div className="inline-flex items-center gap-2 text-sm text-rose-600 dark:text-rose-400">
                <AlertTriangle className="h-4 w-4" aria-hidden="true" />
                Failed to load Z-report
              </div>
              <button
                type="button"
                onClick={() => refetch()}
                disabled={isFetching}
                className="inline-flex items-center gap-1 rounded-md border border-surface-200 bg-white px-3 py-1.5 text-xs font-semibold text-surface-700 hover:bg-surface-50 disabled:opacity-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
              >
                <RotateCcw className={`h-3 w-3 ${isFetching ? 'motion-safe:animate-spin' : ''}`} aria-hidden="true" />
                {isFetching ? 'Retrying…' : 'Retry'}
              </button>
            </div>
          )}
          {data && <ZReportBody report={data} varianceWarnCents={varianceWarnCents} />}
        </div>
      </div>
    </div>
  );
}

interface ZReportBodyProps {
  report: ZReport;
  varianceWarnCents: number;
}

function ZReportBody({ report, varianceWarnCents }: ZReportBodyProps) {
  // WEB-UIUX-1162: when the shift is still open, the server returns
  // counted_cents/variance_cents = null + in_progress=true. Render an
  // "awaiting close" placeholder instead of the red phantom-short banner.
  const inProgress = report.in_progress || report.variance_cents === null;
  const variance = report.variance_cents ?? 0;
  const varianceClass =
    inProgress
      ? 'text-surface-500 dark:text-surface-400'
      : variance === 0
        ? 'text-green-600 dark:text-green-400'
        : variance > 0
          ? 'text-blue-600 dark:text-blue-400'
          : 'text-red-600 dark:text-red-400';
  const VarianceIcon = inProgress
    ? AlertTriangle
    : variance === 0 ? Minus : variance > 0 ? TrendingUp : TrendingDown;

  return (
    <>
      <div className="space-y-1 text-xs text-surface-500 dark:text-surface-400">
        <div>
          Opened: {formatDateTime(report.opened_at)}
          {report.opened_by_name && <span> · by {report.opened_by_name}</span>}
        </div>
        <div>
          Closed: {inProgress ? 'In progress — shift not yet closed' : formatDateTime(report.closed_at)}
          {!inProgress && report.closed_by_name && <span> · by {report.closed_by_name}</span>}
        </div>
        {report.duration_minutes != null && (
          <div>
            Duration: {Math.floor(report.duration_minutes / 60)}h {report.duration_minutes % 60}m
            <span className="ml-1 text-surface-400">(shift #{report.shift_id})</span>
          </div>
        )}
        {report.notes && (
          <div className="mt-1 italic text-surface-600 dark:text-surface-300">Note: {report.notes}</div>
        )}
      </div>

      <div className="space-y-2 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
        <ReportRow label="Opening Float" value={formatMoney(report.opening_float_cents)} />
        <ReportRow label="Expected" value={formatMoney(report.expected_cents)} />
        <ReportRow
          label="Counted"
          value={report.counted_cents === null ? 'Awaiting close' : formatMoney(report.counted_cents)}
        />
        <div className="mt-2 border-t border-surface-200 pt-2 dark:border-surface-700">
          <div className={`flex items-center justify-between text-sm font-semibold ${varianceClass}`}>
            <span className="flex items-center gap-1.5">
              <VarianceIcon className="h-4 w-4" />
              Variance
            </span>
            <span>
              {inProgress
                ? 'Awaiting close'
                : variance === 0 ? 'Balanced' : variance > 0 ? `Over by ${formatCents(variance)}` : `Short by ${formatCents(Math.abs(variance))}`}
            </span>
          </div>
          {!inProgress && varianceWarnCents > 0 && Math.abs(variance) >= varianceWarnCents && (
            <div className="mt-1 flex items-center gap-1 text-[11px] text-amber-600 dark:text-amber-400">
              <AlertTriangle className="h-3 w-3" />
              Variance ≥ {formatCents(varianceWarnCents)} — investigate before next shift
            </div>
          )}
        </div>
      </div>

      <div>
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Payment Breakdown
        </div>
        <div className="space-y-1 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          {/* WEB-UIUX-1186: disambiguate empty state — "No payments" alone looks
              like a query failure; clarify it means zero transactions this shift. */}
          {report.payment_breakdown.length === 0 && (
            <div className="text-xs text-surface-400">No payments recorded during this shift (zero transactions)</div>
          )}
          {report.payment_breakdown.map((p) => (
            <ReportRow
              key={p.method}
              label={`${p.method} (${p.count})`}
              value={formatMoney(p.cents)}
            />
          ))}
        </div>
      </div>

      <div>
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Shift Totals
        </div>
        <div className="space-y-1 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          <ReportRow label="Gross Sales" value={formatMoney(report.totals.gross_cents)} />
          <ReportRow label="Refunds" value={formatMoney(report.totals.refund_cents)} />
          <ReportRow label="Net" value={formatMoney(report.totals.net_cents)} bold />
          <ReportRow label="Transactions" value={String(report.totals.transaction_count)} />
        </div>
      </div>
    </>
  );
}

interface ReportRowProps {
  label: string;
  value: string;
  bold?: boolean;
}

function ReportRow({ label, value, bold }: ReportRowProps) {
  return (
    <div className={`flex items-center justify-between text-sm ${bold ? 'font-semibold' : ''}`}>
      <span className="text-surface-600 dark:text-surface-400">{label}</span>
      <span className="text-surface-900 dark:text-surface-100">{value}</span>
    </div>
  );
}
