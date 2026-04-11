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

  return (
    <div className="p-6 max-w-3xl">
      <div className="flex items-center gap-2 mb-4">
        <Briefcase className="text-gray-600" />
        <h1 className="text-2xl font-bold">Partner / Lender Report</h1>
      </div>
      <p className="text-gray-600 mb-6">
        Year-to-date business summary suitable for sharing with lenders, partners, or investors.
        Includes revenue, gross profit, margin, outstanding receivables, and inventory value at cost.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4 mb-6">
        <label className="flex flex-col">
          <span className="text-xs font-semibold uppercase text-gray-500">Year</span>
          <select
            value={year}
            onChange={e => setYear(e.target.value)}
            className="mt-1 rounded-md border px-3 py-2"
          >
            {Array.from({ length: 5 }, (_, i) => thisYear - i).map(y => (
              <option key={y} value={y}>{y}</option>
            ))}
          </select>
        </label>
      </div>

      <button
        type="button"
        onClick={openReport}
        className="inline-flex items-center gap-2 rounded-lg bg-gray-800 px-4 py-2 text-white hover:bg-gray-900"
      >
        <Download size={16} /> Generate Partner Report
      </button>
    </div>
  );
}

export default PartnerReportPage;
