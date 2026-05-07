import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { AlertTriangle, ChevronDown, ChevronUp, Clock, Hash } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { CopyButton } from '@/components/shared/CopyButton';
import { formatDate } from '@/utils/format';
import { EmptyState, SummaryCard, getReportQueryState } from './ReportHelpers';

interface StalledTicketsData {
  rows: {
    tech_name: string;
    stalled_count: number;
    ticket_ids: string;
    oldest_update: string;
    max_days_stalled: number;
  }[];
  from: string;
  to: string;
}

export function StalledTicketsTab({ from, to }: { from: string; to: string }) {
  const [expandedTicketIdsKey, setExpandedTicketIdsKey] = useState<string | null>(null);
  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['reports', 'stalled-tickets', from, to],
    queryFn: async () => {
      const res = await reportApi.stalledTickets({ from_date: from, to_date: to });
      return res.data.data as StalledTicketsData;
    },
  });

  const reportState = getReportQueryState({
    data,
    error,
    isError,
    isLoading,
    fallbackError: 'Failed to load stalled tickets report',
  });
  if (reportState.status !== 'ready') return reportState.view;

  const { rows } = reportState.data;
  const totalStalled = rows.reduce((sum, r) => sum + r.stalled_count, 0);
  const maxDaysStalled = rows.length > 0 ? Math.max(...rows.map((r) => r.max_days_stalled)) : 0;

  return (
    <div className="space-y-6">
      {/* Summary Cards */}
      <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
        <SummaryCard
          label="Total Stalled" value={String(totalStalled)}
          icon={AlertTriangle} color="text-amber-500" bg="bg-amber-50 dark:bg-amber-950"
        />
        <SummaryCard
          label="Technicians Affected" value={String(rows.length)}
          icon={Hash} color="text-blue-500" bg="bg-blue-50 dark:bg-blue-950"
        />
        <SummaryCard
          label="Longest Stall" value={maxDaysStalled > 0 ? `${maxDaysStalled} days` : 'None'}
          icon={Clock} color="text-red-500" bg="bg-red-50 dark:bg-red-950"
        />
      </div>

      {/* Alert Banner */}
      {totalStalled > 0 && (
        <div className="card p-4 border-l-4 border-amber-500 flex items-center gap-3">
          <AlertTriangle className="h-5 w-5 text-amber-500 flex-shrink-0" />
          <span className="text-sm text-surface-700 dark:text-surface-300">
            <strong className="text-amber-600 dark:text-amber-400">{totalStalled}</strong> tickets have not been updated in 7+ days
          </span>
        </div>
      )}

      {/* Stalled Tickets Table */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Stalled Tickets by Technician</h3>
          <p className="text-xs text-surface-500 mt-0.5">Open tickets with no update for 7+ days, grouped by assignee</p>
        </div>
        {rows.length === 0 ? (
          <EmptyState message="No stalled tickets found -- all tickets are progressing" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Technician</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Stalled Count</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500">Max Days Stalled</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Oldest Update</th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Ticket IDs</th>
                </tr>
              </thead>
              <tbody>
                {rows.map((r, index) => {
                  const ticketIds = r.ticket_ids?.trim();
                  const rowKey = `${r.tech_name}-${index}`;
                  const panelId = `stalled-ticket-ids-${index}`;
                  const isExpanded = expandedTicketIdsKey === rowKey;
                  const splitTicketIds = ticketIds
                    ? ticketIds.split(',').map((id) => id.trim()).filter(Boolean)
                    : [];

                  return (
                    <tr key={rowKey} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                      <td className="px-4 py-3 font-medium text-surface-900 dark:text-surface-100">{r.tech_name}</td>
                      <td className="px-4 py-3 text-right">
                        <span className={`font-bold ${r.stalled_count >= 5 ? 'text-red-600 dark:text-red-400' : 'text-amber-600 dark:text-amber-400'}`}>
                          {r.stalled_count}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-right">
                        <span className={`font-bold ${r.max_days_stalled >= 30 ? 'text-red-600 dark:text-red-400' : r.max_days_stalled >= 14 ? 'text-amber-600 dark:text-amber-400' : 'text-surface-900 dark:text-surface-100'}`}>
                          {r.max_days_stalled}d
                        </span>
                      </td>
                      <td className="px-4 py-3 text-surface-600 dark:text-surface-400">
                        {r.oldest_update ? formatDate(r.oldest_update) : '--'}
                      </td>
                      <td className="px-4 py-3 text-surface-500 font-mono text-xs max-w-[300px]">
                        {ticketIds ? (
                          <div className="space-y-2">
                            <div className="flex min-w-0 items-center gap-1.5">
                              <button
                                type="button"
                                onClick={() => setExpandedTicketIdsKey(isExpanded ? null : rowKey)}
                                className="flex min-w-0 max-w-[260px] items-center gap-1 rounded text-left text-surface-600 hover:text-primary-600 focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-2 focus:ring-offset-white dark:text-surface-300 dark:hover:text-primary-400 dark:focus:ring-offset-surface-900"
                                title={ticketIds}
                                aria-expanded={isExpanded}
                                aria-controls={panelId}
                                aria-label={`${isExpanded ? 'Hide' : 'Show'} full ticket IDs for ${r.tech_name}`}
                              >
                                <span className="min-w-0 truncate">{ticketIds}</span>
                                {isExpanded ? (
                                  <ChevronUp aria-hidden="true" className="h-3.5 w-3.5 flex-shrink-0" />
                                ) : (
                                  <ChevronDown aria-hidden="true" className="h-3.5 w-3.5 flex-shrink-0" />
                                )}
                              </button>
                              <CopyButton
                                text={ticketIds}
                                className="btn-icon btn-xs h-6 w-6 flex-shrink-0 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
                              />
                            </div>
                            {isExpanded && (
                              <div
                                id={panelId}
                                className="max-w-[300px] rounded-md border border-surface-200 bg-surface-50 p-2 text-surface-700 shadow-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-200"
                              >
                                <div className="mb-1 flex items-center justify-between gap-2">
                                  <span className="text-[11px] font-semibold uppercase text-surface-500 dark:text-surface-400">Full IDs</span>
                                  <CopyButton
                                    text={ticketIds}
                                    className="btn-icon btn-xs h-6 w-6 flex-shrink-0 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
                                  />
                                </div>
                                <div className="flex flex-wrap gap-1.5">
                                  {splitTicketIds.map((ticketId, ticketIndex) => (
                                    <span
                                      key={`${ticketId}-${ticketIndex}`}
                                      className="select-all break-all rounded bg-white px-1.5 py-0.5 text-[11px] text-surface-700 ring-1 ring-surface-200 dark:bg-surface-800 dark:text-surface-200 dark:ring-surface-700"
                                    >
                                      {ticketId}
                                    </span>
                                  ))}
                                </div>
                              </div>
                            )}
                          </div>
                        ) : (
                          '--'
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
