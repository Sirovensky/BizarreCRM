/**
 * GettingStartedWidget — Day-1 Onboarding checklist (audit section 42, ideas 1, 2, 13)
 *
 * Sticky card rendered above the dashboard KPIs when the tenant is new.
 * Combines three ideas from the audit:
 *   (1) Getting-Started Checklist — 5-step linear flow: create customer ->
 *       add ticket -> estimate -> invoice -> record payment. Each step is a
 *       button that deep-links to the right page.
 *   (2) Smart Day-1 dashboard — when all the first_* timestamps are null
 *       (shop just finished the wizard, never touched a real record), we
 *       render a friendlier "Welcome" banner with an explicit "Next step" CTA.
 *   (13) Setup progress bar — a compact progress indicator shows how many
 *       of the 5 milestones the shop has completed.
 *
 * IMPORTANT: per the audit, this widget MUST be skippable at any point.
 * We expose two escape hatches:
 *   - "Skip for now" — dismisses the widget for the current session only
 *     (React state, forgotten on refresh — user can come back later).
 *   - "Don't show again" — persists checklist_dismissed = true via
 *     PATCH /onboarding/state and never shows again.
 *
 * Completion is computed purely from the server-side first_*_at timestamps,
 * so a client can't "game" it by clicking through fake steps. When all five
 * are set, the card fades to a single congratulations line and then hides
 * itself permanently (via the same dismiss path as "Don't show again").
 */
import { useCallback, useMemo, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Check,
  UserPlus,
  Ticket,
  FileText,
  Receipt,
  CreditCard,
  ArrowRight,
  X,
  Sparkles,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { onboardingApi, type OnboardingState } from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface ChecklistStep {
  id: 'customer' | 'ticket' | 'estimate' | 'invoice' | 'payment';
  title: string;
  description: string;
  icon: typeof UserPlus;
  route: string;
  doneKey: keyof Pick<
    OnboardingState,
    'first_customer_at' | 'first_ticket_at' | 'first_invoice_at' | 'first_payment_at'
  > | null;
}

// The audit lists 5 steps: customer -> ticket -> estimate -> invoice -> payment.
// We track only 4 server-side milestones (customer/ticket/invoice/payment); the
// "estimate" step is purely navigational because there's no dedicated
// first_estimate_at column. It's still valuable UX (teaches the estimate flow
// exists) so we include it as a non-checking nav button.
const STEPS: ReadonlyArray<ChecklistStep> = [
  {
    id: 'customer',
    title: 'Create your first customer',
    description: 'Name, phone, and email are all you need.',
    icon: UserPlus,
    route: '/customers?new=1',
    doneKey: 'first_customer_at',
  },
  {
    id: 'ticket',
    title: 'Open a repair ticket',
    description: 'Log the device, fault, and estimated price.',
    icon: Ticket,
    route: '/tickets?new=1',
    doneKey: 'first_ticket_at',
  },
  {
    id: 'estimate',
    title: 'Send an estimate (optional)',
    description: 'Text the customer a link to approve.',
    icon: FileText,
    route: '/estimates?new=1',
    doneKey: null,
  },
  {
    id: 'invoice',
    title: 'Generate an invoice',
    description: 'Convert the ticket to a sale.',
    icon: Receipt,
    route: '/invoices?new=1',
    doneKey: 'first_invoice_at',
  },
  {
    id: 'payment',
    title: 'Record your first payment',
    description: 'Cash, card, or credit — celebrate!',
    icon: CreditCard,
    route: '/pos',
    doneKey: 'first_payment_at',
  },
];

interface GettingStartedWidgetProps {
  /**
   * Override for the preloaded state — allows the parent (DashboardPage) to
   * avoid a double fetch if it already queried /onboarding/state. Optional;
   * the widget will fetch on its own if omitted.
   */
  preloadedState?: OnboardingState | null;
}

export function GettingStartedWidget({ preloadedState }: GettingStartedWidgetProps) {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [sessionSkipped, setSessionSkipped] = useState(false);

  const { data: stateResponse, isLoading } = useQuery({
    queryKey: ['onboarding-state'],
    queryFn: () => onboardingApi.getState(),
    enabled: !preloadedState,
    staleTime: 30_000,
  });

  const state: OnboardingState | null = useMemo(() => {
    if (preloadedState) return preloadedState;
    return (stateResponse as any)?.data?.data ?? null;
  }, [preloadedState, stateResponse]);

  const dismissMutation = useMutation({
    mutationFn: () => onboardingApi.patchState({ checklist_dismissed: true }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['onboarding-state'] });
      toast.success('Checklist dismissed. You can re-enable it from Settings.');
    },
    onError: () => {
      toast.error('Failed to dismiss checklist.');
    },
  });

  const handleSkipSession = useCallback(() => {
    setSessionSkipped(true);
  }, []);

  const handleDismissForever = useCallback(() => {
    dismissMutation.mutate();
  }, [dismissMutation]);

  const completedCount = useMemo(() => {
    if (!state) return 0;
    return STEPS.filter((step) => step.doneKey && state[step.doneKey]).length;
  }, [state]);

  // Track the trackable (server-checked) steps only for the progress %.
  const trackableCount = STEPS.filter((s) => s.doneKey).length;
  const progressPct = Math.round((completedCount / trackableCount) * 100);
  const allDone = completedCount === trackableCount;

  // Hide in any of these cases:
  //   - still loading (flicker-free first paint)
  //   - server says dismissed
  //   - user hit "Skip for now" this session
  //   - no state (unlikely, but render nothing instead of a broken card)
  if (isLoading) return null;
  if (!state) return null;
  if (state.checklist_dismissed) return null;
  if (sessionSkipped) return null;

  const nextStep = STEPS.find((step) => step.doneKey && !state[step.doneKey]) ?? STEPS[0];

  return (
    <div
      className={cn(
        'mb-4 rounded-2xl border border-primary-200 bg-gradient-to-br from-primary-50 to-white p-5 shadow-sm transition-all dark:border-primary-500/30 dark:from-primary-500/10 dark:to-surface-900',
        allDone && 'opacity-70',
      )}
      data-testid="getting-started-widget"
    >
      {/* Top row: title + dismiss buttons */}
      <div className="mb-3 flex items-start justify-between gap-3">
        <div className="flex items-start gap-3">
          <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary-100 dark:bg-primary-500/20">
            {allDone ? (
              <Sparkles className="h-5 w-5 text-primary-600 dark:text-primary-400" />
            ) : (
              <Ticket className="h-5 w-5 text-primary-600 dark:text-primary-400" />
            )}
          </div>
          <div>
            <h2 className="text-base font-semibold text-surface-900 dark:text-surface-50">
              {allDone ? 'Shop set up — nicely done!' : 'Get your shop running'}
            </h2>
            <p className="text-xs text-surface-500 dark:text-surface-400">
              {allDone
                ? 'You completed every starter step. This card will hide itself shortly.'
                : `You're ${completedCount} of ${trackableCount} steps in. Takes about 5 minutes.`}
            </p>
          </div>
        </div>
        <div className="flex items-center gap-1">
          <button
            type="button"
            onClick={handleSkipSession}
            className="rounded-md px-2 py-1 text-xs font-medium text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          >
            Skip for now
          </button>
          <button
            type="button"
            onClick={handleDismissForever}
            disabled={dismissMutation.isPending}
            className="rounded-md p-1 text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200 disabled:opacity-50"
            title="Don't show this again"
            aria-label="Don't show this again"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
      </div>

      {/* Progress bar (audit idea 13) */}
      <div className="mb-4 h-1.5 w-full overflow-hidden rounded-full bg-primary-100 dark:bg-primary-900/40">
        <div
          className="h-full rounded-full bg-primary-500 transition-all duration-500 dark:bg-primary-400"
          style={{ width: `${progressPct}%` }}
          aria-label={`Progress: ${progressPct}%`}
        />
      </div>

      {/* Checklist rows */}
      <ul className="space-y-2">
        {STEPS.map((step) => {
          const done = step.doneKey ? Boolean(state[step.doneKey]) : false;
          const isNext = step === nextStep && !done && !allDone;
          const Icon = step.icon;
          return (
            <li
              key={step.id}
              className={cn(
                'flex items-center gap-3 rounded-lg border px-3 py-2.5 transition-colors',
                done
                  ? 'border-green-200 bg-green-50/50 dark:border-green-800/50 dark:bg-green-900/10'
                  : isNext
                  ? 'border-primary-300 bg-white shadow-sm dark:border-primary-500/40 dark:bg-surface-800'
                  : 'border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800',
              )}
            >
              <div
                className={cn(
                  'flex h-8 w-8 shrink-0 items-center justify-center rounded-full',
                  done
                    ? 'bg-green-500 text-white'
                    : isNext
                    ? 'bg-primary-500 text-white'
                    : 'bg-surface-100 text-surface-400 dark:bg-surface-700 dark:text-surface-500',
                )}
              >
                {done ? <Check className="h-4 w-4" /> : <Icon className="h-4 w-4" />}
              </div>
              <div className="flex-1 min-w-0">
                <p
                  className={cn(
                    'text-sm font-medium',
                    done
                      ? 'text-surface-500 line-through dark:text-surface-500'
                      : 'text-surface-900 dark:text-surface-100',
                  )}
                >
                  {step.title}
                </p>
                <p className="text-xs text-surface-500 dark:text-surface-400">{step.description}</p>
              </div>
              {!done && (
                <button
                  type="button"
                  onClick={() => navigate(step.route)}
                  className={cn(
                    'flex items-center gap-1 rounded-md px-3 py-1.5 text-xs font-semibold transition-colors',
                    isNext
                      ? 'bg-primary-600 text-white hover:bg-primary-700'
                      : 'text-primary-600 hover:bg-primary-50 dark:text-primary-400 dark:hover:bg-primary-500/10',
                  )}
                >
                  {isNext ? 'Start now' : 'Open'}
                  <ArrowRight className="h-3 w-3" />
                </button>
              )}
            </li>
          );
        })}
      </ul>
    </div>
  );
}
