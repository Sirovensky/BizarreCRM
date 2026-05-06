/**
 * PartnerReportPage — YTD lender/partner report (audit 47.15)
 * Produces a print-ready HTML report showing revenue, gross profit, margin,
 * receivables, and inventory value.
 *
 * WEB-FC-014 (2026-05-06): validate the selected year, fetch the HTML report
 * through the authenticated API client, then open a blob URL so auth/server
 * failures stay in-page instead of rendering 401 HTML in a new tab.
 */

import { useState } from 'react';
import { AlertCircle, Briefcase, Download, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { formatApiError } from '@/utils/apiError';

const REPORT_ERROR_FALLBACK = 'Failed to generate partner report';
const REPORT_BLOB_REVOKE_MS = 60_000;

type ReportErrorLike = {
  response?: {
    status?: number;
    data?: unknown;
  };
};

function messageFromEnvelope(data: unknown): string | null {
  if (!data || typeof data !== 'object') return null;

  const envelope = data as {
    code?: unknown;
    error?: unknown;
    message?: unknown;
    request_id?: unknown;
  };
  const message =
    typeof envelope.message === 'string'
      ? envelope.message
      : typeof envelope.error === 'string'
        ? envelope.error
        : null;

  if (!message) return null;

  const suffixParts: string[] = [];
  if (typeof envelope.code === 'string') suffixParts.push(envelope.code);
  if (typeof envelope.request_id === 'string') {
    suffixParts.push(`ref ${envelope.request_id.slice(0, 8)}`);
  }

  return suffixParts.length > 0 ? `${message} (${suffixParts.join(', ')})` : message;
}

function messageFromText(text: string): string | null {
  const trimmed = text.trim();
  if (!trimmed) return null;

  try {
    const parsed = JSON.parse(trimmed) as unknown;
    const message = messageFromEnvelope(parsed);
    if (message) return message;
  } catch {
    // Non-JSON error bodies fall through to the plain-text handling below.
  }

  if (/^</.test(trimmed)) return null;
  return trimmed.length > 240 ? `${trimmed.slice(0, 237)}...` : trimmed;
}

async function partnerReportErrorMessage(err: unknown): Promise<string> {
  const error = err as ReportErrorLike;
  const status = error.response?.status;

  if (status === 401) {
    return 'Your session has expired. Sign in again to generate the partner report.';
  }

  const data = error.response?.data;
  const envelopeMessage = messageFromEnvelope(data);
  if (envelopeMessage) return envelopeMessage;

  if (typeof data === 'string') {
    const textMessage = messageFromText(data);
    if (textMessage) return textMessage;
  }

  if (typeof Blob !== 'undefined' && data instanceof Blob) {
    const text = await data.text().catch(() => '');
    const textMessage = messageFromText(text);
    if (textMessage) return textMessage;
  }

  if (status === 403) return 'You do not have permission to generate partner reports.';
  if (!error.response) return 'Cannot reach the server. Check your connection and try again.';
  if (status && status >= 500) return 'The server could not generate the partner report. Please try again.';

  return formatApiError(err) || REPORT_ERROR_FALLBACK;
}

function openLoadingReportTab(): Window | null {
  const reportWindow = window.open('', '_blank');
  if (!reportWindow) return null;

  try {
    reportWindow.opener = null;
    reportWindow.document.write(
      '<!doctype html><title>Preparing partner report</title><body style="font-family:system-ui,-apple-system,sans-serif;margin:40px;color:#111;">Preparing partner report...</body>',
    );
    reportWindow.document.close();
  } catch {
    // Best-effort only; the fetched blob still replaces this placeholder.
  }

  return reportWindow;
}

export function PartnerReportPage() {
  const thisYear = new Date().getFullYear();
  const yearOptions = Array.from({ length: 10 }, (_, i) => thisYear - i);
  const oldestYear = yearOptions[yearOptions.length - 1] ?? thisYear;
  const [year, setYear] = useState(String(thisYear));
  const [generating, setGenerating] = useState(false);
  const [yearError, setYearError] = useState<string | null>(null);
  const [reportError, setReportError] = useState<string | null>(null);

  const openReport = async () => {
    const selectedYear = Number(year);
    if (!Number.isInteger(selectedYear) || !yearOptions.includes(selectedYear)) {
      setReportError(null);
      setYearError(`Pick a reporting year from ${oldestYear} to ${thisYear}.`);
      return;
    }

    const reportWindow = openLoadingReportTab();
    if (!reportWindow) {
      const message = 'The browser blocked the report tab. Allow pop-ups for this CRM and try again.';
      setYearError(null);
      setReportError(message);
      toast.error(message);
      return;
    }

    setYearError(null);
    setReportError(null);
    setGenerating(true);
    try {
      const response = await api.get<Blob>('/reports/partner-report.pdf', {
        params: { year: selectedYear },
        responseType: 'blob',
        headers: { Accept: 'text/html' },
      });
      const contentTypeHeader = response.headers['content-type'];
      const contentType =
        typeof contentTypeHeader === 'string' ? contentTypeHeader : 'text/html; charset=utf-8';
      const reportBlob = response.data.type
        ? response.data
        : new Blob([response.data], { type: contentType });
      const objectUrl = URL.createObjectURL(reportBlob);

      if (reportWindow.closed) {
        URL.revokeObjectURL(objectUrl);
        const message = 'Report generated, but the report tab was closed before it could open.';
        setReportError(message);
        toast.error(message);
        return;
      }

      reportWindow.location.replace(objectUrl);
      setTimeout(() => URL.revokeObjectURL(objectUrl), REPORT_BLOB_REVOKE_MS);
    } catch (err: unknown) {
      if (!reportWindow.closed) reportWindow.close();
      const message = await partnerReportErrorMessage(err);
      setReportError(message);
      toast.error(message);
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
            onChange={e => {
              setYear(e.target.value);
              setYearError(null);
              setReportError(null);
            }}
            aria-invalid={yearError ? true : undefined}
            aria-describedby={yearError ? 'partner-year-error' : undefined}
            className="mt-1 rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-3 py-2"
          >
            {yearOptions.map(y => (
              <option key={y} value={y}>{y}</option>
            ))}
          </select>
          {yearError ? (
            <p id="partner-year-error" role="alert" className="mt-1 text-xs text-red-600 dark:text-red-400">
              {yearError}
            </p>
          ) : null}
        </label>
      </div>

      {reportError ? (
        <div
          role="alert"
          className="mb-4 flex items-start gap-2 rounded-md border border-red-200 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300"
        >
          <AlertCircle size={16} className="mt-0.5 shrink-0" aria-hidden="true" />
          <span>{reportError}</span>
        </div>
      ) : null}

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
