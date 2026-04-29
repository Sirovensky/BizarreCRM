/**
 * PartnerReportPage — YTD lender/partner report (audit 47.15)
 * Produces a print-ready HTML report showing revenue, gross profit, margin,
 * receivables, and inventory value.
 *
 * WEB-S6-023 (2026-04-26): replaced bare window.open with an async fetch so
 * slow/erroring PDF generation surfaces as a spinner + toast instead of
 * a silent blank new tab.
 */

import { useState } from 'react';
import { Briefcase, Download, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { reportApi } from '@/api/endpoints';

export function PartnerReportPage() {
  const thisYear = new Date().getFullYear();
  const [year, setYear] = useState(String(thisYear));
  const [generating, setGenerating] = useState(false);

  const openReport = async () => {
    setGenerating(true);
    try {
      // Preflight: hit the same URL via axios (which carries credentials) to
      // confirm the server can build the report before we open the new tab.
      // On success, open the tab — the browser will reuse the cookie and render
      // the HTML report directly. On failure, we get the server error message.
      const url = reportApi.partnerReportPdfUrl(year);
      await api.get(url, { responseType: 'text' });
      window.open(url, '_blank', 'noopener');
    } catch (err: any) {
      const msg: string =
        err?.response?.data?.message ??
        err?.response?.data?.error ??
        err?.message ??
        'Failed to generate partner report';
      toast.error(msg);
    } finally {
      setGenerating(false);
    }
  };

  // @audit-fixed: dark mode classes added throughout (was missing all dark: variants)
  return (
    <div className="p-6 max-w-3xl">
      <div className="flex items-center gap-2 mb-4">
        <Briefcase className="text-surface-600 dark:text-surface-400" aria-hidden="true" />
        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Partner / Lender Report</h1>
      </div>
      <p className="text-surface-600 dark:text-surface-400 mb-6">
        Year-to-date business summary suitable for sharing with lenders, partners, or investors.
        Includes revenue, gross profit, margin, outstanding receivables, and inventory value at cost.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <label className="flex flex-col">
          <span className="text-xs font-semibold uppercase text-surface-500 dark:text-surface-400">Year</span>
          <select
            value={year}
            onChange={e => setYear(e.target.value)}
            className="mt-1 rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-3 py-2"
          >
            {Array.from({ length: 10 }, (_, i) => thisYear - i).map(y => (
              <option key={y} value={y}>{y}</option>
            ))}
          </select>
        </label>
      </div>

      <button
        type="button"
        onClick={openReport}
        disabled={generating}
        className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
      >
        {generating ? (
          <><Loader2 size={16} className="animate-spin" /> Generating…</>
        ) : (
          <><Download size={16} /> Generate Partner Report</>
        )}
      </button>
    </div>
  );
}

export default PartnerReportPage;
