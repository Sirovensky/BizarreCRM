/**
 * BulkActionsBar — one-click operations that affect many settings at once.
 * Examples: "Enable all notifications", "Disable all dead Pro features". The
 * critical audit called for this so shops don't have to click through 30
 * individual toggles during initial setup.
 *
 * The bar is intentionally minimal — it exposes a list of predefined actions
 * rather than letting users build arbitrary multi-toggle updates. That keeps
 * the UX safe and aligns with the allowed_config_keys server-side whitelist.
 */

import { useState } from 'react';
import { Loader2, Zap, BellRing, BellOff, ShieldCheck, Crown } from 'lucide-react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { SETTINGS_METADATA } from '../settingsMetadata';

export interface BulkAction {
  id: string;
  label: string;
  description: string;
  icon: typeof Zap;
  /** Keys to update, mapped to the new value */
  build: () => Record<string, string>;
  /** Visual category — drives button color */
  tone?: 'enable' | 'disable' | 'neutral';
}

const BUILTIN_ACTIONS: BulkAction[] = [
  {
    id: 'enable-all-notifications',
    label: 'Enable all notifications',
    description: 'Turns on customer feedback, SMS notifications, and ticket status alerts.',
    icon: BellRing,
    tone: 'enable',
    build: () => ({
      feedback_enabled: '1',
      feedback_auto_sms: '1',
      ticket_auto_status_on_reply: '1',
    }),
  },
  {
    id: 'disable-all-notifications',
    label: 'Disable all notifications',
    description: 'Silences all automatic customer SMS/email notifications. Use for vacation mode.',
    icon: BellOff,
    tone: 'disable',
    build: () => ({
      feedback_enabled: '0',
      feedback_auto_sms: '0',
      auto_reply_enabled: '0',
      ticket_auto_status_on_reply: '0',
    }),
  },
  {
    id: 'enable-safety-requirements',
    label: 'Enable all safety requirements',
    description: 'Requires pre/post condition checks, parts entry, diagnostic notes, and IMEI capture.',
    icon: ShieldCheck,
    tone: 'enable',
    build: () => ({
      repair_require_pre_condition: '1',
      repair_require_post_condition: '1',
      repair_require_parts: '1',
      repair_require_diagnostic: '1',
      repair_require_imei: '1',
      repair_require_customer: '1',
    }),
  },
  {
    id: 'disable-coming-soon',
    label: 'Hide "coming soon" toggles',
    description: 'Resets all non-working UI toggles to their default so they stop cluttering the interface.',
    icon: Crown,
    tone: 'neutral',
    build: () => {
      const out: Record<string, string> = {};
      for (const s of SETTINGS_METADATA) {
        if (s.status !== 'coming_soon') continue;
        if (s.type === 'boolean') out[s.key] = s.default ? '1' : '0';
        else out[s.key] = String(s.default ?? '');
      }
      return out;
    },
  },
];

export interface BulkActionsBarProps {
  /** Additional actions to show alongside the built-in ones */
  extraActions?: BulkAction[];
  /** Extra className */
  className?: string;
}

export function BulkActionsBar({ extraActions = [], className }: BulkActionsBarProps) {
  const queryClient = useQueryClient();
  const [runningId, setRunningId] = useState<string | null>(null);
  const actions = [...BUILTIN_ACTIONS, ...extraActions];

  const mutation = useMutation({
    mutationFn: async (payload: Record<string, string>) => {
      await settingsApi.updateConfig(payload);
      return payload;
    },
    onSuccess: (payload) => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      toast.success(`Updated ${Object.keys(payload).length} settings`);
      setRunningId(null);
    },
    onError: () => {
      toast.error('Bulk action failed');
      setRunningId(null);
    },
  });

  function run(action: BulkAction) {
    const payload = action.build();
    if (Object.keys(payload).length === 0) {
      toast('Nothing to change', { icon: 'ℹ' });
      return;
    }
    setRunningId(action.id);
    mutation.mutate(payload);
  }

  return (
    <div
      className={cn(
        'rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800/60',
        className
      )}
    >
      <div className="mb-3 flex items-center gap-2">
        <Zap className="h-4 w-4 text-surface-500" />
        <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
          Bulk Actions
        </h4>
      </div>
      <p className="mb-3 text-xs text-surface-500 dark:text-surface-400">
        Apply common configurations in one click. Each action updates several related toggles at once.
      </p>
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {actions.map((action) => {
          const Icon = action.icon;
          const isRunning = runningId === action.id;
          return (
            <button
              key={action.id}
              type="button"
              onClick={() => run(action)}
              disabled={mutation.isPending}
              className={cn(
                'flex items-start gap-2 rounded-lg border p-3 text-left transition-colors',
                'border-surface-200 bg-surface-50 hover:border-primary-300 hover:bg-primary-50/50 dark:border-surface-700 dark:bg-surface-800 dark:hover:border-primary-500/50 dark:hover:bg-primary-500/10',
                mutation.isPending && 'opacity-50'
              )}
            >
              <div
                className={cn(
                  'flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg',
                  action.tone === 'enable' && 'bg-green-100 text-green-600 dark:bg-green-500/20 dark:text-green-300',
                  action.tone === 'disable' && 'bg-red-100 text-red-600 dark:bg-red-500/20 dark:text-red-300',
                  (!action.tone || action.tone === 'neutral') && 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-300'
                )}
              >
                {isRunning ? <Loader2 className="h-4 w-4 animate-spin" /> : <Icon className="h-4 w-4" />}
              </div>
              <div className="min-w-0 flex-1">
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
                  {action.label}
                </p>
                <p className="mt-0.5 text-[11px] text-surface-500 dark:text-surface-400">
                  {action.description}
                </p>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
