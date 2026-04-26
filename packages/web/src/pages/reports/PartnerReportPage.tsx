/**
 * PartnerReportPage — YTD lender/partner report (audit 47.15)
 * Produces a print-ready HTML report showing revenue, gross profit, margin,
 * receivables, and inventory value.
 */

import { useState } from 'react';
import { Briefcase, Download } from 'lucide-react';
import { reportApi } from '@/api/endpoints';

export function PartnerReportPage() {
  const thisYear = new Date().getFullYear();
  const [year, setYear] = useState(String(thisYear));

  const openReport = () => {
    const url = reportApi.partnerReportPdfUrl(year);
    window.open(url, '_blank', 'noopener');
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
        className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-primary-950 hover:bg-primary-700 transition-colors"
      >
        <Download size={16} /> Generate Partner Report
      </button>
    </div>
  );
}

export default PartnerReportPage;
