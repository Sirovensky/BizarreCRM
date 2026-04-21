import { useQuery } from '@tanstack/react-query';
import { X, Printer, TrendingUp, TrendingDown, Minus, AlertTriangle } from 'lucide-react';
import { api } from '@/api/client';
import { formatCents } from '@/utils/format';

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
  counted_cents: number;
  variance_cents: number;
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
 * Signed money formatter. Defers to formatCents() so the locale/currency
 * from store settings is respected — we can't just prepend "$" because
 * non-USD stores would see the wrong glyph.
 */
function formatSignedCents(cents: number): string {
  if (!Number.isFinite(cents)) return formatCents(0);
  return formatCents(cents);
}

export function ZReportModal({ shiftId, onClose }: ZReportModalProps) {
  const { data, isLoading, isError } = useQuery({
    queryKey: ['pos-enrich', 'z-report', shiftId],
    queryFn: async () => {
      const res = await api.get<ZReportResponse>(`/pos-enrich/drawer/${shiftId}/z-report`);
      return res.data.data;
    },
  });

  const handlePrint = () => window.print();

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="max-h-[90vh] w-full max-w-md overflow-y-auto rounded-xl bg-white shadow-2xl dark:bg-surface-900">
        <div className="flex items-center justify-between border-b border-surface-200 px-5 py-3 dark:border-surface-700">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-50">
            Z-Report · Shift #{shiftId}
          </h3>
          <div className="flex items-center gap-1">
            <button
              onClick={handlePrint}
              aria-label="Print"
              className="rounded p-1.5 text-surface-500 hover:bg-surface-100 dark:hover:bg-surface-800"
            >
              <Printer className="h-4 w-4" />
            </button>
            <button
              onClick={onClose}
              aria-label="Close"
              className="rounded p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800"
            >
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="space-y-4 p-5">
          {isLoading && <div className="text-center text-sm text-surface-500">Loading…</div>}
          {isError && <div className="text-center text-sm text-red-500">Failed to load Z-report</div>}
          {data && <ZReportBody report={data} />}
        </div>
      </div>
    </div>
  );
}

interface ZReportBodyProps {
  report: ZReport;
}

function ZReportBody({ report }: ZReportBodyProps) {
  const variance = report.variance_cents;
  const varianceClass =
    variance === 0
      ? 'text-green-600 dark:text-green-400'
      : variance > 0
        ? 'text-blue-600 dark:text-blue-400'
        : 'text-red-600 dark:text-red-400';
  const VarianceIcon = variance === 0 ? Minus : variance > 0 ? TrendingUp : TrendingDown;

  return (
    <>
      <div className="space-y-1 text-xs text-surface-500 dark:text-surface-400">
        <div>Opened: {new Date(report.opened_at).toLocaleString()}</div>
        <div>Closed: {new Date(report.closed_at).toLocaleString()}</div>
      </div>

      <div className="space-y-2 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
        <ReportRow label="Opening Float" value={formatSignedCents(report.opening_float_cents)} />
        <ReportRow label="Expected" value={formatSignedCents(report.expected_cents)} />
        <ReportRow label="Counted" value={formatSignedCents(report.counted_cents)} />
        <div className="mt-2 border-t border-surface-200 pt-2 dark:border-surface-700">
          <div className={`flex items-center justify-between text-sm font-semibold ${varianceClass}`}>
            <span className="flex items-center gap-1.5">
              <VarianceIcon className="h-4 w-4" />
              Variance
            </span>
            <span>{formatSignedCents(Math.abs(variance))} {variance < 0 ? 'short' : variance > 0 ? 'over' : 'exact'}</span>
          </div>
          {Math.abs(variance) >= 500 && (
            <div className="mt-1 flex items-center gap-1 text-[11px] text-amber-600 dark:text-amber-400">
              <AlertTriangle className="h-3 w-3" />
              Variance ≥ $5 — investigate before next shift
            </div>
          )}
        </div>
      </div>

      <div>
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Payment Breakdown
        </div>
        <div className="space-y-1 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          {report.payment_breakdown.length === 0 && (
            <div className="text-xs text-surface-400">No payments recorded</div>
          )}
          {report.payment_breakdown.map((p) => (
            <ReportRow
              key={p.method}
              label={`${p.method} (${p.count})`}
              value={formatSignedCents(p.cents)}
            />
          ))}
        </div>
      </div>

      <div>
        <div className="mb-2 text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
          Shift Totals
        </div>
        <div className="space-y-1 rounded-lg border border-surface-200 p-3 dark:border-surface-700">
          <ReportRow label="Gross Sales" value={formatSignedCents(report.totals.gross_cents)} />
          <ReportRow label="Refunds" value={formatSignedCents(report.totals.refund_cents)} />
          <ReportRow label="Net" value={formatSignedCents(report.totals.net_cents)} bold />
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
