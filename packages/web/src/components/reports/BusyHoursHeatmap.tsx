/**
 * BusyHoursHeatmap — 7 day × 24 hour grid colored by ticket volume (audit 47.3)
 * Guides staffing decisions. Pulls from /reports/busy-hours-heatmap.
 */

import { useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { Clock } from 'lucide-react';
import { reportApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface HeatmapData {
  grid: number[][];       // [dow][hour] -> count
  peak: number;
  days_analyzed: number;
  day_labels: string[];
}

// Heat scale: dim cold → bright hot. Empty stays a flat dark/light cell so
// the eye reads it as "no activity". User flagged the prior darker=busier
// scale as inverted — bright cells now mean "more tickets land here".
function bucketColor(value: number, peak: number): string {
  if (value === 0) return 'bg-gray-100 dark:bg-surface-900';
  const pct = peak > 0 ? value / peak : 0;
  if (pct >= 0.75) return 'bg-amber-300 dark:bg-amber-300';
  if (pct >= 0.5)  return 'bg-amber-400/80 dark:bg-amber-400/80';
  if (pct >= 0.25) return 'bg-amber-500/60 dark:bg-amber-500/55';
  return 'bg-amber-500/30 dark:bg-amber-500/25';
}

const HOUR_LABELS = Array.from({ length: 24 }, (_, i) =>
  i === 0 ? '12a' : i < 12 ? `${i}a` : i === 12 ? '12p' : `${i - 12}p`
);

function pluralizeTickets(count: number): string {
  return `${count} ticket${count === 1 ? '' : 's'}`;
}

export function BusyHoursHeatmap({ days = 30 }: { days?: number }) {
  const [hoveredSlot, setHoveredSlot] = useState<{ dow: number; hour: number } | null>(null);
  const [selectedSlot, setSelectedSlot] = useState<{ dow: number; hour: number } | null>(null);

  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'busy-hours', days],
    queryFn: async () => {
      const res = await reportApi.busyHoursHeatmap(days);
      return res.data.data as HeatmapData;
    },
  });

  const activeHours = useMemo(() => {
    if (!data) return [];
    return HOUR_LABELS
      .map((label, hour) => ({
        hour,
        label,
        total: data.grid.reduce((sum, row) => sum + Number(row?.[hour] || 0), 0),
      }))
      .filter((h) => h.total > 0);
  }, [data]);
  const activeSlot = hoveredSlot ?? selectedSlot;
  const busiestSlot = useMemo(() => {
    if (!data) return null;
    let best: { dow: number; hour: number; count: number } | null = null;
    data.grid.forEach((row, dow) => {
      row.forEach((count, hour) => {
        if (!best || count > best.count) best = { dow, hour, count: Number(count) };
      });
    });
    return best;
  }, [data]);
  const summarySlot = activeSlot ?? busiestSlot;
  const activeCount = data && activeSlot ? Number(data.grid[activeSlot.dow]?.[activeSlot.hour] || 0) : 0;
  const summaryCount = data && summarySlot ? Number(data.grid[summarySlot.dow]?.[summarySlot.hour] || 0) : 0;
  const summaryLabel = data && summarySlot
    ? `${data.day_labels[summarySlot.dow]} ${HOUR_LABELS[summarySlot.hour]}: ${pluralizeTickets(summaryCount)}`
    : 'No repair activity in this window';

  if (isLoading) {
    return <div className="h-64 rounded-xl border border-gray-200 dark:border-surface-700 bg-gray-50 dark:bg-surface-800 animate-pulse" />;
  }
  if (error || !data) {
    return <div className="rounded-xl border border-red-200 dark:border-red-900 bg-red-50 dark:bg-red-900/20 p-4 text-red-700 dark:text-red-300">Heatmap unavailable.</div>;
  }

  return (
    <div className="rounded-xl border border-gray-200 dark:border-surface-700 bg-white dark:bg-surface-900 p-4">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-gray-700 dark:text-surface-200">
        <Clock size={16} /> Busy Hours &mdash; last {data.days_analyzed} days
      </div>
      {activeHours.length === 0 ? (
        <div className="rounded-lg border border-dashed border-gray-200 dark:border-surface-700 p-6 text-sm text-gray-500 dark:text-surface-400">
          No repair activity in the last {data.days_analyzed} days.
        </div>
      ) : (
        <div className="overflow-x-auto">
          <div className="inline-block min-w-full">
            <div className="flex">
              <div className="w-10" />
              {activeHours.map(({ hour, label }) => (
                <div
                  key={hour}
                  className={cn(
                    'w-7 text-center text-[10px] font-medium transition-colors',
                    activeSlot?.hour === hour
                      ? 'text-amber-700 dark:text-amber-300'
                      : 'text-gray-500 dark:text-surface-400',
                  )}
                >
                  {label}
                </div>
              ))}
            </div>
            {data.day_labels.map((day, dow) => (
              <div key={dow} className="flex items-center">
                <div
                  className={cn(
                    'w-10 text-xs font-medium transition-colors',
                    activeSlot?.dow === dow
                      ? 'text-amber-700 dark:text-amber-300'
                      : 'text-gray-600 dark:text-surface-300',
                  )}
                >
                  {day}
                </div>
                {activeHours.map(({ hour }) => {
                  const count = Number(data.grid[dow]?.[hour] || 0);
                  const isActive = activeSlot?.dow === dow && activeSlot?.hour === hour;
                  const isSelected = selectedSlot?.dow === dow && selectedSlot?.hour === hour;
                  const isRelated = activeSlot?.dow === dow || activeSlot?.hour === hour;

                  return (
                    <button
                      key={hour}
                      type="button"
                      onClick={() => setSelectedSlot((current) => (
                        current?.dow === dow && current?.hour === hour ? null : { dow, hour }
                      ))}
                      onMouseEnter={() => setHoveredSlot({ dow, hour })}
                      onMouseLeave={() => setHoveredSlot(null)}
                      onFocus={() => setHoveredSlot({ dow, hour })}
                      onBlur={() => setHoveredSlot(null)}
                      aria-pressed={isSelected}
                      aria-label={`${day} ${HOUR_LABELS[hour]}: ${pluralizeTickets(count)}`}
                      className={cn(
                        'relative h-7 w-7 cursor-pointer border border-white p-0 transition dark:border-surface-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-400 focus-visible:ring-offset-1 focus-visible:ring-offset-white dark:focus-visible:ring-offset-surface-900',
                        bucketColor(count, data.peak),
                        isActive && 'scale-110 ring-2 ring-amber-500 ring-offset-1 ring-offset-white dark:ring-offset-surface-900 z-10',
                        isSelected && !isActive && 'ring-1 ring-amber-400 ring-offset-1 ring-offset-white dark:ring-offset-surface-900',
                        activeSlot && !isRelated && 'opacity-45',
                        'hover:scale-110',
                      )}
                      title={`${day} ${HOUR_LABELS[hour]}: ${pluralizeTickets(count)}`}
                    />
                  );
                })}
              </div>
            ))}
          </div>
        </div>
      )}
      <div className="mt-3 flex flex-wrap items-center gap-x-2 gap-y-1 text-xs text-gray-500 dark:text-surface-400">
        <span>
          Peak: <strong className="text-gray-800 dark:text-surface-100">{data.peak}</strong> tickets / hour
        </span>
        <span>&middot;</span>
        <span>brighter = busier</span>
        <span>&middot;</span>
        <strong className="text-gray-800 dark:text-surface-100">{summaryLabel}</strong>
        {activeSlot && activeCount === 0 && (
          <span className="text-gray-400 dark:text-surface-500">no tickets in this slot</span>
        )}
      </div>
    </div>
  );
}
