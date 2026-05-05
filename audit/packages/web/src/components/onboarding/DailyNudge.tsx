/**
 * DailyNudge — Day-3/5/7 re-engagement nudges (Phase B2)
 *
 * Shows one contextual nudge based on how many days have passed since signup.
 * Visible even when the checklist is dismissed (different purpose).
 * Dismissed via PATCH /onboarding/state and invalidates the cached query.
 */
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { X, Users, Bell, RotateCcw, ArrowRight } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { onboardingApi, type OnboardingState } from '@/api/endpoints';

interface DailyNudgeProps {
  preloadedState: OnboardingState | null;
}

type NudgeVariant = 'day3' | 'day5' | 'day7';

interface NudgeConfig {
  variant: NudgeVariant;
  icon: typeof Users;
  title: string;
  body: string;
  ctaLabel: string;
  ctaHref: string;
  patchKey: 'nudge_day3_seen' | 'nudge_day5_seen' | 'nudge_day7_seen';
}

const NUDGE_CONFIGS: Record<NudgeVariant, NudgeConfig> = {
  day3: {
    variant: 'day3',
    icon: Users,
    title: 'Invite your first technician',
    body: 'Add a team member so they can create tickets and view their queue.',
    ctaLabel: 'Go to Users',
    ctaHref: '/settings/users',
    patchKey: 'nudge_day3_seen',
  },
  day5: {
    variant: 'day5',
    icon: Bell,
    title: 'Set up customer notifications',
    body: 'Send automatic SMS updates when a ticket status changes.',
    ctaLabel: 'Configure SMS',
    ctaHref: '/settings/sms-voice',
    patchKey: 'nudge_day5_seen',
  },
  day7: {
    variant: 'day7',
    icon: RotateCcw,
    title: 'Try a refund',
    body: 'Need to reverse a payment? Open an invoice and use the Refund action.',
    ctaLabel: 'View Invoices',
    ctaHref: '/invoices',
    patchKey: 'nudge_day7_seen',
  },
};

function computeActiveNudge(state: OnboardingState): NudgeConfig | null {
  if (!state.created_at) return null;

  const created = new Date(state.created_at);
  const now = new Date();
  const daysSinceSignup = Math.floor((now.getTime() - created.getTime()) / (1000 * 60 * 60 * 24));

  // Show highest applicable unseen nudge
  if (daysSinceSignup >= 7 && !state.nudge_day7_seen) return NUDGE_CONFIGS.day7;
  if (daysSinceSignup >= 5 && !state.nudge_day5_seen) return NUDGE_CONFIGS.day5;
  if (daysSinceSignup >= 3 && !state.nudge_day3_seen) return NUDGE_CONFIGS.day3;
  return null;
}

export function DailyNudge({ preloadedState }: DailyNudgeProps) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  const dismissMutation = useMutation({
    mutationFn: (key: 'nudge_day3_seen' | 'nudge_day5_seen' | 'nudge_day7_seen') =>
      onboardingApi.patchState({ [key]: true }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
    },
    onError: () => {
      toast.error('Could not dismiss nudge');
    },
  });

  if (!preloadedState) return null;

  const nudge = computeActiveNudge(preloadedState);
  if (!nudge) return null;

  const Icon = nudge.icon;

  const handleDismiss = () => {
    dismissMutation.mutate(nudge.patchKey);
  };

  const handleCta = () => {
    handleDismiss();
    navigate(nudge.ctaHref);
  };

  return (
    <div className="mb-4 flex items-center gap-3 rounded-2xl border border-primary-200 bg-gradient-to-r from-primary-50 to-white px-4 py-3 shadow-sm dark:border-primary-500/30 dark:from-primary-500/10 dark:to-surface-900">
      <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary-100 dark:bg-primary-500/20">
        <Icon className="h-4 w-4 text-primary-600 dark:text-primary-400" />
      </div>

      <div className="flex-1 min-w-0">
        <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{nudge.title}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400">{nudge.body}</p>
      </div>

      <button
        type="button"
        onClick={handleCta}
        className="flex shrink-0 items-center gap-1.5 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-semibold text-primary-950 transition-colors hover:bg-primary-700"
      >
        {nudge.ctaLabel}
        <ArrowRight className="h-3 w-3" />
      </button>

      <button
        type="button"
        onClick={handleDismiss}
        disabled={dismissMutation.isPending}
        className="shrink-0 rounded-md p-1 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800 dark:hover:text-surface-300 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
        aria-label="Got it"
        title="Got it"
      >
        <X className="h-4 w-4" />
      </button>
    </div>
  );
}
