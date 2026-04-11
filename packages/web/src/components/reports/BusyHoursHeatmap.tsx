/**
 * BusyHoursHeatmap — 7 day × 24 hour grid colored by ticket volume (audit 47.3)
 * Guides staffing decisions. Pulls from /reports/busy-hours-heatmap.
 */

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

function bucketColor(value: number, peak: number): string {
  if (value === 0) return 'bg-gray-50';
  const pct = peak > 0 ? value / peak : 0;
  if (pct >= 0.75) return 'bg-blue-700';
  if (pct >= 0.5) return 'bg-blue-500';
  if (pct >= 0.25) return 'bg-blue-300';
  return 'bg-blue-100';
}

const HOUR_LABELS = Array.from({ length: 24 }, (_, i) =>
  i === 0 ? '12a' : i < 12 ? `${i}a` : i === 12 ? '12p' : `${i - 12}p`
);

export function BusyHoursHeatmap({ days = 30 }: { days?: number }) {
  const { data, isLoading, error } = useQuery({
    queryKey: ['reports', 'busy-hours', days],
    queryFn: async () => {
      const res = await reportApi.busyHoursHeatmap(days);
      return res.data.data as HeatmapData;
    },
  });

  if (isLoading) {
    return <div className="h-64 rounded-xl border border-gray-200 bg-gray-50 animate-pulse" />;
  }
  if (error || !data) {
    return <div className="rounded-xl border border-red-200 bg-red-50 p-4 text-red-700">Heatmap unavailable.</div>;
  }

  return (
    <div className="rounded-xl border border-gray-200 bg-white p-4">
      <div className="mb-3 flex items-center gap-2 text-sm font-semibold text-gray-700">
        <Clock size={16} /> Busy Hours &mdash; last {data.days_analyzed} days
      </div>
      <div className="overflow-x-auto">
        <div className="inline-block min-w-full">
          <div className="flex">
            <div className="w-10" />
            {HOUR_LABELS.map((h, i) => (
              <div key={i} className="w-6 text-[9px] text-center text-gray-500">{h}</div>
            ))}
          </div>
          {data.day_labels.map((day, dow) => (
            <div key={dow} className="flex items-center">
              <div className="w-10 text-xs text-gray-600 font-medium">{day}</div>
              {data.grid[dow].map((count, hour) => (
                <div
                  key={hour}
                  className={cn(
                    'w-6 h-6 border border-white transition',
                    bucketColor(count, data.peak),
                  )}
                  title={`${day} ${HOUR_LABELS[hour]}: ${count} tickets`}
                />
              ))}
            </div>
          ))}
        </div>
      </div>
      <div className="mt-3 flex items-center gap-2 text-xs text-gray-500">
        Peak: <strong className="text-gray-800">{data.peak}</strong> tickets / hour &middot; darker = busier
      </div>
    </div>
  );
}
