/**
 * SettingsResetToDefaults — expanded "reset" panel that shows the user exactly
 * which keys will change and what they'll change to BEFORE running the reset.
 *
 * Differs from the compact `ResetDefaultsButton` (which is a single click-and-
 * go control): this component renders a per-setting diff so users can see the
 * scope of the operation. That matters because some settings tabs have 30+
 * keys and a blind "reset all" on production data would be terrifying.
 *
 * Defaults come from settingsMetadata's `getDefaultsForTab` helper so there's
 * still a single source of truth. The mutation target is the normal
 * settingsApi.updateConfig endpoint, which the backend allow-lists anyway.
 */

import { useMemo, useState } from 'react';
import { RotateCcw, ChevronDown, Loader2, AlertTriangle } from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import {
  getDefaultsForTab,
  getSettingsForTab,
  type SettingDef,
} from '../settingsMetadata';

export interface SettingsResetToDefaultsProps {
  /** The settings tab this panel resets */
  tab: string;
  /** Human-readable label for the confirmation (defaults to the tab ID) */
  label?: string;
  /** Called after a successful reset (e.g. to refresh form state) */
  onReset?: () => void;
  /** Extra className for layout */
  className?: string;
}

interface DiffRow {
  def: SettingDef;
  current: string;
  next: string;
  willChange: boolean;
}

export function SettingsResetToDefaults({
  tab,
  label,
  onReset,
  className,
}: SettingsResetToDefaultsProps) {
  const queryClient = useQueryClient();
  const [expanded, setExpanded] = useState(false);
  const [confirming, setConfirming] = useState(false);

  const definitions = useMemo(() => getSettingsForTab(tab), [tab]);

  // Load the current store_config so we can render a real diff.
  const { data: currentConfig } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 15_000,
  });

  const diffRows = useMemo<DiffRow[]>(() => {
    if (!currentConfig) return [];
    const defaults = getDefaultsForTab(tab);
    return definitions.map((def) => {
      const current = currentConfig[def.key] ?? '';
      const next = defaults[def.key] ?? '';
      return { def, current, next, willChange: current !== next };
    });
  }, [currentConfig, definitions, tab]);

  const changingRows = diffRows.filter((r) => r.willChange);

  const mutation = useMutation({
    mutationFn: async () => {
      const defaults = getDefaultsForTab(tab);
      await settingsApi.updateConfig(defaults);
      return defaults;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      toast.success(`${label ?? tab} reset to defaults`);
      setConfirming(false);
      setExpanded(false);
      onReset?.();
    },
    onError: () => {
      toast.error('Failed to reset settings');
      setConfirming(false);
    },
  });

  // If the tab has no registered defaults, render nothing.
  if (definitions.length === 0) return null;

  return (
    <section
      className={cn(
        'rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800/60',
        className
      )}
    >
      <header
        className="flex cursor-pointer items-center justify-between gap-2"
        onClick={() => setExpanded((v) => !v)}
      >
        <div className="flex items-center gap-2">
          <RotateCcw className="h-4 w-4 text-surface-500" />
          <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
            Reset {label ?? tab} to defaults
          </h4>
          <span className="rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-mono text-surface-500 dark:bg-surface-800">
            {definitions.length} settings
          </span>
        </div>
        <ChevronDown
          className={cn(
            'h-4 w-4 text-surface-400 transition-transform',
            expanded && 'rotate-180'
          )}
        />
      </header>

      {expanded && (
        <div className="mt-3">
          {!currentConfig ? (
            <p className="py-3 text-center text-xs text-surface-400">Loading current values…</p>
          ) : changingRows.length === 0 ? (
            <p className="py-3 text-center text-xs text-surface-500">
              Every setting already matches its default. Nothing to reset.
            </p>
          ) : (
            <>
              <p className="mb-2 text-xs text-surface-500 dark:text-surface-400">
                The following {changingRows.length} value
                {changingRows.length === 1 ? '' : 's'} will change:
              </p>
              <ul className="max-h-56 space-y-1 overflow-y-auto rounded-lg border border-surface-100 bg-surface-50 p-2 dark:border-surface-800 dark:bg-surface-800/40">
                {changingRows.map((row) => (
                  <li
                    key={row.def.key}
                    className="flex items-start justify-between gap-2 rounded px-2 py-1 text-[11px]"
                  >
                    <span className="truncate font-medium text-surface-700 dark:text-surface-200">
                      {row.def.label}
                    </span>
                    <span className="shrink-0 font-mono text-surface-500">
                      <s className="opacity-60">{truncate(row.current)}</s>
                      <span className="mx-1">→</span>
                      <span className="text-surface-800 dark:text-surface-100">
                        {truncate(row.next)}
                      </span>
                    </span>
                  </li>
                ))}
              </ul>

              <ResetFooter
                confirming={confirming}
                running={mutation.isPending}
                onConfirm={() => {
                  if (!confirming) {
                    setConfirming(true);
                    return;
                  }
                  mutation.mutate();
                }}
                onCancel={() => setConfirming(false)}
              />
            </>
          )}
        </div>
      )}
    </section>
  );
}

function truncate(str: string, max = 24): string {
  if (!str) return '""';
  return str.length > max ? `${str.slice(0, max)}…` : str;
}

interface ResetFooterProps {
  confirming: boolean;
  running: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

function ResetFooter({ confirming, running, onConfirm, onCancel }: ResetFooterProps) {
  return (
    <div className="mt-3 flex items-center justify-between gap-2">
      <p className="flex items-center gap-1 text-[11px] text-amber-600 dark:text-amber-400">
        <AlertTriangle className="h-3 w-3" />
        This cannot be undone from the UI.
      </p>
      <div className="flex items-center gap-2">
        {confirming && (
          <button
            type="button"
            onClick={onCancel}
            className="rounded-lg border border-surface-200 px-3 py-1 text-xs text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
        )}
        <button
          type="button"
          onClick={onConfirm}
          disabled={running}
          className={cn(
            'rounded-lg px-3 py-1 text-xs font-semibold text-white transition-colors',
            confirming ? 'bg-red-600 hover:bg-red-700' : 'bg-surface-700 hover:bg-surface-800'
          )}
        >
          {running ? <Loader2 className="h-3 w-3 animate-spin" /> : confirming ? 'Yes, reset' : 'Reset to defaults'}
        </button>
      </div>
    </div>
  );
}
