/**
 * TaxReportPage — one-click tax-time report (audit 47.13)
 * Opens the server-rendered HTML in a new tab so owners can Print-to-PDF.
 */

import { useState } from 'react';
import { FileText, Download } from 'lucide-react';
import { reportApi } from '@/api/endpoints';

export function TaxReportPage() {
  const thisYear = new Date().getFullYear();
  const [from, setFrom] = useState(`${thisYear}-01-01`);
  const [to, setTo] = useState(new Date().toISOString().slice(0, 10));
  const [jurisdiction, setJurisdiction] = useState('default');

  const openReport = () => {
    const url = reportApi.taxReportPdfUrl(from, to, jurisdiction);
    window.open(url, '_blank', 'noopener');
  };

  return (
    <div className="p-6 max-w-3xl">
      <div className="flex items-center gap-2 mb-4">
        <FileText className="text-gray-600" />
        <h1 className="text-2xl font-bold">Tax Report</h1>
      </div>
      <p className="text-gray-600 mb-6">
        Generate an accountant-ready tax summary for any date range. The report opens in a new
        tab as a print-ready HTML document &mdash; use your browser's Print &rarr; Save as PDF to
        hand off to your accountant.
      </p>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-6">
        <label className="flex flex-col">
          <span className="text-xs font-semibold uppercase text-gray-500">From</span>
          <input
            type="date"
            value={from}
            onChange={e => setFrom(e.target.value)}
            className="mt-1 rounded-md border px-3 py-2"
          />
        </label>
        <label className="flex flex-col">
          <span className="text-xs font-semibold uppercase text-gray-500">To</span>
          <input
            type="date"
            value={to}
            onChange={e => setTo(e.target.value)}
            className="mt-1 rounded-md border px-3 py-2"
          />
        </label>
        <label className="flex flex-col">
          <span className="text-xs font-semibold uppercase text-gray-500">Jurisdiction</span>
          <input
            type="text"
            value={jurisdiction}
            onChange={e => setJurisdiction(e.target.value)}
            placeholder="e.g. California, State"
            className="mt-1 rounded-md border px-3 py-2"
          />
        </label>
      </div>

      <button
        type="button"
        onClick={openReport}
        className="inline-flex items-center gap-2 rounded-lg bg-gray-800 px-4 py-2 text-white hover:bg-gray-900"
      >
        <Download size={16} /> Generate Tax Report
      </button>
    </div>
  );
}

export default TaxReportPage;
