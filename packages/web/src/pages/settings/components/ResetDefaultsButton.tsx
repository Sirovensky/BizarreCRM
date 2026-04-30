/**
 * ResetDefaultsButton — one-click "restore defaults" for an entire settings
 * tab. Reads the default values from settingsMetadata so we don't hardcode
 * defaults in two places. The mutation target is the normal updateConfig
 * endpoint, so it plays nicely with the existing settings pipeline.
 *
 * Always prompts for confirmation — a misclick here could wipe a lot of
 * carefully tuned configuration.
 */

import { useState } from 'react';
import { RotateCcw, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { settingsApi } from '@/api/endpoints';
import { getDefaultsForTab, getSettingsForTab } from '../settingsMetadata';
import { cn } from '@/utils/cn';

export interface ResetDefaultsButtonProps {
  /** Which tab to reset — must match settingsMetadata.tab */
  tab: string;
  /** Human-readable label for the confirmation prompt */
  label?: string;
  /** Optional className for layout */
  className?: string;
  /** Called after a successful reset, e.g. to re-fetch form state */
  onReset?: () => void;
}

export function ResetDefaultsButton({
  tab,
  label,
  className,
  onReset,
}: ResetDefaultsButtonProps) {
  const queryClient = useQueryClient();
  const [confirming, setConfirming] = useState(false);
  const settingsCount = getSettingsForTab(tab).length;

  const mutation = useMutation({
    mutationFn: async () => {
      const defaults = getDefaultsForTab(tab);
      if (Object.keys(defaults).length === 0) {
        throw new Error(`No defaults registered for "${tab}"`);
      }
      await settingsApi.updateConfig(defaults);
      return defaults;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      toast.success(`${label ?? tab} settings reset to defaults`);
      setConfirming(false);
      onReset?.();
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to reset settings';
      toast.error(msg);
      setConfirming(false);
    },
  });

  // Hide entirely if there are no defaults registered for this tab
  if (settingsCount === 0) return null;

  if (!confirming) {
    return (
      <button
        type="button"
        onClick={() => setConfirming(true)}
        className={cn(
          'inline-flex items-center gap-1.5 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-xs font-medium text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-400 dark:hover:bg-surface-700',
          className
        )}
        title={`Reset ${settingsCount} settings to defaults`}
      >
        <RotateCcw className="h-3 w-3" />
        Reset to defaults
      </button>
    );
  }

  return (
    <div
      className={cn(
        'inline-flex items-center gap-2 rounded-lg border border-amber-300 bg-amber-50 px-3 py-1.5 dark:border-amber-500/40 dark:bg-amber-500/10',
        className
      )}
    >
      <span className="text-xs text-amber-700 dark:text-amber-300">
        Reset {settingsCount} settings?
      </span>
      <button
        type="button"
        onClick={() => mutation.mutate()}
        disabled={mutation.isPending}
        className="rounded bg-red-600 px-2 py-0.5 text-xs font-semibold text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
      >
        {mutation.isPending ? (
          <Loader2 className="h-3 w-3 animate-spin" />
        ) : (
          'Yes, reset'
        )}
      </button>
      <button
        type="button"
        onClick={() => setConfirming(false)}
        className="rounded px-2 py-0.5 text-xs text-surface-600 hover:bg-white dark:text-surface-400 dark:hover:bg-surface-800"
      >
        Cancel
      </button>
    </div>
  );
}
