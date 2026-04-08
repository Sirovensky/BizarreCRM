import { useMemo, useCallback } from 'react';
import { ArrowUp, ArrowDown, ArrowUpDown, ChevronLeft, ChevronRight } from 'lucide-react';
import { cn } from '@/utils/cn';
import { SkeletonTable } from './Skeleton';

// ─── Types ───────────────────────────────────────────────────────────

interface Column<T> {
  key: string;
  label: string;
  sortable?: boolean;
  render?: (row: T) => React.ReactNode;
  className?: string;
}

interface DataTableProps<T> {
  columns: Column<T>[];
  data: T[];
  keyExtractor: (row: T) => string | number;
  isLoading?: boolean;
  emptyMessage?: string;
  // Pagination
  page?: number;
  totalPages?: number;
  total?: number;
  onPageChange?: (page: number) => void;
  // Sorting
  sortBy?: string;
  sortOrder?: 'ASC' | 'DESC';
  onSort?: (key: string) => void;
  // Selection
  selectable?: boolean;
  selectedIds?: Set<string | number>;
  onSelectionChange?: (ids: Set<string | number>) => void;
  // Row interaction
  onRowClick?: (row: T) => void;
}

// ─── Pagination helpers ──────────────────────────────────────────────

function getPageNumbers(current: number, total: number): number[] {
  if (total <= 7) {
    return Array.from({ length: total }, (_, i) => i + 1);
  }
  if (current <= 4) {
    return [1, 2, 3, 4, 5, 6, 7];
  }
  if (current >= total - 3) {
    return Array.from({ length: 7 }, (_, i) => total - 6 + i);
  }
  return Array.from({ length: 7 }, (_, i) => current - 3 + i);
}

// ─── SortHeader sub-component ────────────────────────────────────────

function SortIndicator({ sortBy, sortOrder, columnKey }: {
  sortBy?: string;
  sortOrder?: 'ASC' | 'DESC';
  columnKey: string;
}) {
  const isActive = sortBy === columnKey;
  if (isActive && sortOrder === 'ASC') {
    return <ArrowUp className="h-3.5 w-3.5 text-primary-500" />;
  }
  if (isActive && sortOrder === 'DESC') {
    return <ArrowDown className="h-3.5 w-3.5 text-primary-500" />;
  }
  return <ArrowUpDown className="h-3.5 w-3.5 opacity-30" />;
}

// ─── DataTable ───────────────────────────────────────────────────────

export function DataTable<T>({
  columns,
  data,
  keyExtractor,
  isLoading = false,
  emptyMessage = 'No data found',
  page,
  totalPages,
  total,
  onPageChange,
  sortBy,
  sortOrder,
  onSort,
  selectable = false,
  selectedIds,
  onSelectionChange,
  onRowClick,
}: DataTableProps<T>) {
  const allSelected = data.length > 0 && selectedIds?.size === data.length;
  const someSelected = (selectedIds?.size ?? 0) > 0 && !allSelected;

  const handleSelectAll = useCallback(() => {
    if (!onSelectionChange) return;
    if (allSelected) {
      onSelectionChange(new Set());
    } else {
      onSelectionChange(new Set(data.map(keyExtractor)));
    }
  }, [allSelected, data, keyExtractor, onSelectionChange]);

  const handleSelectRow = useCallback((id: string | number) => {
    if (!onSelectionChange || !selectedIds) return;
    const next = new Set(selectedIds);
    if (next.has(id)) {
      next.delete(id);
    } else {
      next.add(id);
    }
    onSelectionChange(next);
  }, [selectedIds, onSelectionChange]);

  const pageNumbers = useMemo(
    () => (totalPages ? getPageNumbers(page ?? 1, totalPages) : []),
    [page, totalPages],
  );

  const showPagination = totalPages != null && totalPages > 1 && onPageChange;

  const perPage = total != null && totalPages != null && totalPages > 0
    ? Math.ceil(total / totalPages)
    : data.length;

  // ─── Loading state ───────────────────────────────────────────────
  if (isLoading) {
    return <SkeletonTable rows={8} cols={columns.length + (selectable ? 1 : 0)} />;
  }

  // ─── Empty state ─────────────────────────────────────────────────
  if (data.length === 0) {
    return (
      <div className="flex flex-col items-center justify-center py-20 text-surface-400 dark:text-surface-500">
        <p className="text-sm">{emptyMessage}</p>
      </div>
    );
  }

  return (
    <div className="flex flex-col">
      {/* Table */}
      <div className="overflow-auto">
        <table className="w-full text-left text-sm">
          <thead className="sticky top-0 z-10 bg-white dark:bg-surface-900">
            <tr className="border-b border-surface-200 dark:border-surface-700">
              {selectable && (
                <th className="px-4 py-3 w-10">
                  <input
                    type="checkbox"
                    checked={allSelected}
                    ref={(el) => { if (el) el.indeterminate = someSelected; }}
                    onChange={handleSelectAll}
                    className="rounded border-surface-300 dark:border-surface-600"
                  />
                </th>
              )}
              {columns.map((col) => {
                const isSortable = col.sortable && onSort;
                return (
                  <th
                    key={col.key}
                    className={cn(
                      'px-4 py-3 font-medium text-surface-500 dark:text-surface-400',
                      isSortable && 'cursor-pointer select-none hover:text-surface-700 dark:hover:text-surface-200 transition-colors',
                      col.className,
                    )}
                    onClick={isSortable ? () => onSort(col.key) : undefined}
                  >
                    <div className={cn(
                      'inline-flex items-center gap-1',
                      col.className?.includes('text-right') && 'justify-end',
                    )}>
                      {col.label}
                      {isSortable && (
                        <SortIndicator sortBy={sortBy} sortOrder={sortOrder} columnKey={col.key} />
                      )}
                    </div>
                  </th>
                );
              })}
            </tr>
          </thead>
          <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
            {data.map((row) => {
              const id = keyExtractor(row);
              const isSelected = selectedIds?.has(id) ?? false;
              return (
                <tr
                  key={id}
                  className={cn(
                    'transition-colors',
                    isSelected
                      ? 'bg-primary-50 dark:bg-primary-950/20'
                      : 'hover:bg-surface-50 dark:hover:bg-surface-800/50',
                    onRowClick && 'cursor-pointer',
                  )}
                  onClick={onRowClick ? () => onRowClick(row) : undefined}
                >
                  {selectable && (
                    <td className="px-4 py-3 w-10">
                      <input
                        type="checkbox"
                        checked={isSelected}
                        onChange={(e) => {
                          e.stopPropagation();
                          handleSelectRow(id);
                        }}
                        onClick={(e) => e.stopPropagation()}
                        className="rounded border-surface-300 dark:border-surface-600"
                      />
                    </td>
                  )}
                  {columns.map((col) => (
                    <td key={col.key} className={cn('px-4 py-3 text-surface-700 dark:text-surface-300', col.className)}>
                      {col.render
                        ? col.render(row)
                        : String((row as Record<string, unknown>)[col.key] ?? '')}
                    </td>
                  ))}
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      {/* Pagination footer */}
      {(showPagination || total != null) && (
        <div className="flex items-center justify-between border-t border-surface-200 dark:border-surface-700 px-4 py-3">
          {total != null && (
            <p className="text-xs sm:text-sm text-surface-500 dark:text-surface-400">
              Showing {((page ?? 1) - 1) * perPage + 1}&ndash;{Math.min((page ?? 1) * perPage, total)} of {total}
            </p>
          )}
          {showPagination && (
            <div className="flex items-center gap-1">
              <button
                disabled={(page ?? 1) <= 1}
                onClick={() => onPageChange((page ?? 1) - 1)}
                className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700"
              >
                <ChevronLeft className="h-4 w-4" />
              </button>
              {pageNumbers.map((num) => (
                <button
                  key={num}
                  onClick={() => onPageChange(num)}
                  className={cn(
                    'h-8 w-8 rounded-lg text-sm font-medium transition-colors',
                    num === (page ?? 1)
                      ? 'bg-primary-600 text-white'
                      : 'text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700',
                  )}
                >
                  {num}
                </button>
              ))}
              <button
                disabled={(page ?? 1) >= (totalPages ?? 1)}
                onClick={() => onPageChange((page ?? 1) + 1)}
                className="rounded-lg p-1.5 text-surface-500 transition-colors hover:bg-surface-100 disabled:opacity-50 dark:hover:bg-surface-700"
              >
                <ChevronRight className="h-4 w-4" />
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}
