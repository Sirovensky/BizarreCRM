interface SkeletonLineProps {
  width?: string;
  height?: string;
}

export function SkeletonLine({ width = '100%', height = '1rem' }: SkeletonLineProps) {
  return (
    <div
      className="animate-pulse rounded bg-surface-200 dark:bg-surface-700"
      style={{ width, height }}
    />
  );
}

export function SkeletonCard() {
  return (
    <div className="animate-pulse rounded-lg border border-surface-200 dark:border-surface-700 p-4 space-y-3">
      <SkeletonLine width="60%" height="1.25rem" />
      <SkeletonLine width="80%" />
      <SkeletonLine width="40%" />
      <SkeletonLine width="70%" />
    </div>
  );
}

interface SkeletonTableProps {
  rows?: number;
  cols?: number;
}

export function SkeletonTable({ rows = 5, cols = 4 }: SkeletonTableProps) {
  return (
    <div className="animate-pulse">
      {/* Header row */}
      <div className="flex gap-4 border-b border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800/50 px-4 py-3">
        {Array.from({ length: cols }).map((_, i) => (
          <div
            key={i}
            className="h-3 rounded bg-surface-200 dark:bg-surface-700"
            style={{ width: `${80 + Math.random() * 120}px` }}
          />
        ))}
      </div>
      {/* Body rows */}
      {Array.from({ length: rows }).map((_, rowIdx) => (
        <div
          key={rowIdx}
          className="flex gap-4 px-4 py-4 border-b border-surface-100 dark:border-surface-700/50"
        >
          {Array.from({ length: cols }).map((_, colIdx) => (
            <div
              key={colIdx}
              className="h-4 rounded bg-surface-100 dark:bg-surface-700/50"
              style={{ width: `${60 + ((rowIdx + colIdx) % 3) * 40}px` }}
            />
          ))}
        </div>
      ))}
    </div>
  );
}
