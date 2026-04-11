/**
 * SampleDataCard — Day-1 Onboarding (audit section 42, idea 3)
 *
 * Offers the shop owner a one-click way to populate the database with
 * 5 fake customers + 10 tickets + 3 invoices tagged `[Sample]` so the
 * dashboard has real charts, tables, and search results to explore on
 * day one. A matching "Remove sample data" button deletes EXACTLY the
 * rows the loader inserted — see the server-side sampleData.ts for the
 * entity tracking design.
 *
 * UX decisions:
 *   - Only renders if nothing is loaded yet AND first_customer_at is null
 *     (sample loader would feel weird if they already have real data).
 *   - Shows a confirmation step before destructive removal.
 *   - Emits a toast + optimistically invalidates React Query caches so
 *     dashboards refresh immediately.
 */
import { useCallback, useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { Database, Trash2, CheckCircle2, Loader2, Sparkles } from 'lucide-react';
import toast from 'react-hot-toast';
import { onboardingApi, type OnboardingState } from '@/api/endpoints';

interface SampleDataCardProps {
  state: OnboardingState;
  onChanged?: () => void;
}

export function SampleDataCard({ state, onChanged }: SampleDataCardProps) {
  const queryClient = useQueryClient();
  const [confirmingRemoval, setConfirmingRemoval] = useState(false);

  const loadMutation = useMutation({
    mutationFn: () => onboardingApi.loadSampleData(),
    onSuccess: () => {
      toast.success('Sample data loaded. Explore away!');
      queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard-kpis'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard-summary'] });
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      onChanged?.();
    },
    onError: () => {
      toast.error('Failed to load sample data.');
    },
  });

  const removeMutation = useMutation({
    mutationFn: () => onboardingApi.removeSampleData(),
    onSuccess: () => {
      toast.success('Sample data removed.');
      queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard-kpis'] });
      queryClient.invalidateQueries({ queryKey: ['dashboard-summary'] });
      queryClient.invalidateQueries({ queryKey: ['customers'] });
      queryClient.invalidateQueries({ queryKey: ['tickets'] });
      queryClient.invalidateQueries({ queryKey: ['invoices'] });
      setConfirmingRemoval(false);
      onChanged?.();
    },
    onError: () => {
      toast.error('Failed to remove sample data.');
      setConfirmingRemoval(false);
    },
  });

  const handleLoad = useCallback(() => {
    loadMutation.mutate();
  }, [loadMutation]);

  const handleRemove = useCallback(() => {
    if (!confirmingRemoval) {
      setConfirmingRemoval(true);
      return;
    }
    removeMutation.mutate();
  }, [confirmingRemoval, removeMutation]);

  // Loaded state: show "Remove" button.
  if (state.sample_data_loaded) {
    const counts = state.sample_data_counts;
    return (
      <div className="mb-4 flex items-center justify-between gap-3 rounded-xl border border-amber-200 bg-amber-50 p-4 dark:border-amber-800/50 dark:bg-amber-900/20">
        <div className="flex items-start gap-3">
          <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-amber-100 dark:bg-amber-900/40">
            <CheckCircle2 className="h-4.5 w-4.5 text-amber-600 dark:text-amber-400" />
          </div>
          <div>
            <p className="text-sm font-semibold text-amber-900 dark:text-amber-100">
              Sample data is active
            </p>
            <p className="text-xs text-amber-700 dark:text-amber-300">
              {counts
                ? `${counts.customers} customers, ${counts.tickets} tickets, ${counts.invoices} invoices tagged [Sample].`
                : 'Demo rows are loaded and tagged [Sample].'}
              {' '}Remove them before real customers start arriving.
            </p>
          </div>
        </div>
        <button
          type="button"
          onClick={handleRemove}
          disabled={removeMutation.isPending}
          className="flex shrink-0 items-center gap-1.5 rounded-lg border border-amber-300 bg-white px-3 py-2 text-xs font-semibold text-amber-700 transition-colors hover:bg-amber-100 disabled:opacity-50 dark:border-amber-700 dark:bg-amber-900/30 dark:text-amber-200 dark:hover:bg-amber-900/50"
        >
          {removeMutation.isPending ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Trash2 className="h-3.5 w-3.5" />
          )}
          {confirmingRemoval ? 'Click again to confirm' : 'Remove sample data'}
        </button>
      </div>
    );
  }

  // Empty state: only show the offer if the shop genuinely has no data yet.
  if (state.first_customer_at) return null;

  return (
    <div className="mb-4 flex items-center justify-between gap-3 rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800">
      <div className="flex items-start gap-3">
        <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-100 dark:bg-primary-500/20">
          <Database className="h-4.5 w-4.5 text-primary-600 dark:text-primary-400" />
        </div>
        <div>
          <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">
            Want to explore with sample data?
          </p>
          <p className="text-xs text-surface-500 dark:text-surface-400">
            We'll create 5 demo customers, 10 tickets, and 3 invoices. All tagged{' '}
            <code className="rounded bg-surface-100 px-1 py-0.5 text-[11px] dark:bg-surface-700">[Sample]</code>{' '}
            and removable with one click.
          </p>
        </div>
      </div>
      <button
        type="button"
        onClick={handleLoad}
        disabled={loadMutation.isPending}
        className="flex shrink-0 items-center gap-1.5 rounded-lg bg-primary-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-primary-700 disabled:opacity-50"
      >
        {loadMutation.isPending ? (
          <Loader2 className="h-3.5 w-3.5 animate-spin" />
        ) : (
          <Sparkles className="h-3.5 w-3.5" />
        )}
        Load sample data
      </button>
    </div>
  );
}
