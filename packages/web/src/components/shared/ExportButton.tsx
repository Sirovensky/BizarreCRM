import { useState, useCallback } from 'react';
import { Download, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────────

interface ExportButtonProps {
  fetchData: () => Promise<Blob>;
  filename: string;
  label?: string;
  disabled?: boolean;
  className?: string;
}

// ─── Component ───────────────────────────────────────────────────────

export function ExportButton({
  fetchData,
  filename,
  label = 'Export CSV',
  disabled = false,
  className,
}: ExportButtonProps) {
  const [isExporting, setIsExporting] = useState(false);

  const handleExport = useCallback(async () => {
    if (isExporting || disabled) return;
    setIsExporting(true);
    try {
      const blob = await fetchData();
      const url = URL.createObjectURL(blob);
      const link = document.createElement('a');
      link.href = url;
      link.download = filename;
      document.body.appendChild(link);
      link.click();
      document.body.removeChild(link);
      URL.revokeObjectURL(url);
    } catch {
      toast.error('Export failed');
    } finally {
      setIsExporting(false);
    }
  }, [fetchData, filename, isExporting, disabled]);

  return (
    <button
      type="button"
      onClick={handleExport}
      disabled={disabled || isExporting}
      className={cn(
        'inline-flex items-center gap-2 rounded-lg border px-3 py-2 text-sm font-medium transition-colors',
        'border-surface-200 bg-white text-surface-700 hover:bg-surface-50',
        'dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700',
        (disabled || isExporting) && 'opacity-50 cursor-not-allowed',
        className,
      )}
    >
      {isExporting ? (
        <Loader2 className="h-4 w-4 animate-spin" />
      ) : (
        <Download className="h-4 w-4" />
      )}
      {isExporting ? 'Exporting...' : label}
    </button>
  );
}
