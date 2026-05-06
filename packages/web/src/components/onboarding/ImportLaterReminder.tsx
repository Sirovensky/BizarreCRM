import { useState } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, Database, X } from 'lucide-react';
import { cn } from '@/utils/cn';

interface ImportLaterReminderProps {
  setupImportChoice?: 'will_import' | 'later' | 'fresh' | null;
}

export function ImportLaterReminder({ setupImportChoice }: ImportLaterReminderProps) {
  const [dismissed, setDismissed] = useState(false);

  if (setupImportChoice !== 'later' || dismissed) return null;

  return (
    <div
      className="mb-4 rounded-2xl border border-amber-200 bg-amber-50 p-4 shadow-sm dark:border-amber-500/30 dark:bg-amber-500/10"
      data-testid="import-later-reminder"
    >
      <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
        <div className="flex min-w-0 items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-300">
            <Database className="h-5 w-5" />
          </div>
          <div className="min-w-0">
            <h2 className="text-sm font-semibold text-surface-900 dark:text-surface-50">
              Ready to import your old data?
            </h2>
            <p className="mt-1 text-sm text-surface-600 dark:text-surface-300">
              During setup you chose to do it later. You can bring in customers, tickets, invoices, and inventory from Data & Import.
            </p>
          </div>
        </div>

        <div className="flex shrink-0 items-center gap-2 sm:pl-3">
          <Link
            to="/settings/data"
            className="btn btn-sm btn-primary gap-1.5"
          >
            Import now
            <ArrowRight className="h-3.5 w-3.5" />
          </Link>
          <button
            type="button"
            onClick={() => setDismissed(true)}
            className={cn(
              'btn-icon btn-sm text-surface-500 hover:bg-amber-100 hover:text-surface-700',
              'dark:text-surface-300 dark:hover:bg-amber-500/20 dark:hover:text-surface-100',
            )}
            aria-label="Dismiss import reminder"
            title="Not now"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
