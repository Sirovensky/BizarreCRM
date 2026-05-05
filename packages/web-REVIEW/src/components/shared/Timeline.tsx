import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────────

interface TimelineEntry {
  id: string;
  icon?: React.ReactNode;
  iconBg?: string;
  title: React.ReactNode;
  subtitle?: React.ReactNode;
  content?: React.ReactNode;
  timestamp: string;
}

interface TimelineProps {
  entries: TimelineEntry[];
  emptyMessage?: string;
  maxHeight?: string;
}

// ─── Component ───────────────────────────────────────────────────────

export function Timeline({
  entries,
  emptyMessage = 'No activity yet',
  maxHeight,
}: TimelineProps) {
  if (entries.length === 0) {
    return (
      <div className="flex items-center justify-center py-12 text-surface-400 dark:text-surface-500">
        <p className="text-sm">{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div
      className={cn('relative', maxHeight && 'overflow-y-auto')}
      style={maxHeight ? { maxHeight } : undefined}
    >
      <div className="space-y-0">
        {entries.map((entry, idx) => {
          const isLast = idx === entries.length - 1;
          return (
            <div key={entry.id} className="relative flex gap-4 pb-6 last:pb-0">
              {/* Vertical line */}
              {!isLast && (
                <div
                  className="absolute left-[15px] top-8 bottom-0 w-px bg-surface-200 dark:bg-surface-700"
                  aria-hidden
                />
              )}

              {/* Icon dot */}
              <div className="relative z-10 flex-shrink-0">
                <div
                  className={cn(
                    'flex h-8 w-8 items-center justify-center rounded-full',
                    entry.iconBg ?? 'bg-surface-100 dark:bg-surface-700',
                  )}
                >
                  {entry.icon ?? (
                    <div className="h-2 w-2 rounded-full bg-surface-400 dark:bg-surface-500" />
                  )}
                </div>
              </div>

              {/* Content */}
              <div className="flex-1 min-w-0 pt-0.5">
                <div className="flex items-start justify-between gap-2">
                  <div className="text-sm font-medium text-surface-900 dark:text-surface-100">
                    {entry.title}
                  </div>
                  <time className="flex-shrink-0 text-xs text-surface-400 dark:text-surface-500 whitespace-nowrap">
                    {entry.timestamp}
                  </time>
                </div>
                {entry.subtitle && (
                  <div className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">
                    {entry.subtitle}
                  </div>
                )}
                {entry.content && (
                  <div className="mt-2 rounded-lg border border-surface-100 bg-surface-50 p-3 text-sm text-surface-600 dark:border-surface-700 dark:bg-surface-800/50 dark:text-surface-400">
                    {entry.content}
                  </div>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
