import { useState, useCallback, useEffect } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2 } from 'lucide-react';
import { settingsApi } from '@/api/endpoints';
import { useUiStore } from '@/stores/uiStore';
import { usePlanStore } from '@/stores/planStore';
import type { ExtraCardId, PendingWrites, WizardPhase } from './wizardTypes';
import { StepWelcome } from './steps/StepWelcome';
import { StepStoreInfo } from './steps/StepStoreInfo';
import { StepTrialInfo } from './steps/StepTrialInfo';
import { ExtrasHub } from './ExtrasHub';
import { StepBusinessHours } from './steps/StepBusinessHours';
import { StepTax } from './steps/StepTax';
import { StepLogo } from './steps/StepLogo';
import { StepReceipts } from './steps/StepReceipts';
import { StepImport } from './steps/StepImport';
import { StepSmsProvider } from './steps/StepSmsProvider';
import { StepEmailSmtp } from './steps/StepEmailSmtp';
import { StepDefaultStatuses } from './steps/StepDefaultStatuses';
import { StepReview } from './steps/StepReview';
import { StepShopType } from './steps/StepShopType';
import { SkipToDashboard } from './SkipToDashboard';

/**
 * First-run setup wizard shell.
 *
 * State machine:
 *   welcome -> store -> trialInfo -> hub -> review -> done
 *
 * Mandatory phases (welcome, store) run linearly with validation. trialInfo
 * is purely informational. Hub is non-sequential — user picks any extras.
 * Review shows the summary and flushes everything via a single PUT /settings/config.
 *
 * Skip can be triggered from any phase via the SkipToDashboard button; the
 * user's partial data is still flushed, and wizard_completed='skipped' is set.
 */
export function SetupPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { setTheme } = useUiStore();
  const fetchPlan = usePlanStore((s) => s.fetchPlan);

  // Populate planStore on mount so StepTrialInfo reflects the live trial status.
  // SetupPage renders outside AppShell (which is the normal fetchPlan trigger),
  // so without this call planStore stays at hasFetched=false / trialActive=false
  // and the trial info step always shows the "inactive" warning.
  useEffect(() => {
    fetchPlan();
  }, [fetchPlan]);

  // Short-circuit: if the wizard gate already decided this user doesn't belong here,
  // redirect them. This handles the case where someone manually navigates to /setup
  // after finishing — they shouldn't be able to re-enter the wizard.
  const { data: setupData, isLoading: checkingStatus } = useQuery({
    queryKey: ['setup-status'],
    queryFn: () => settingsApi.getSetupStatus(),
    staleTime: 10_000,
  });
  const wizardCompleted = (setupData as any)?.data?.data?.wizard_completed;
  const setupCompleted = (setupData as any)?.data?.data?.setup_completed;
  const existingStoreName = (setupData as any)?.data?.data?.store_name;

  // Wizard state
  const [phase, setPhase] = useState<WizardPhase>('welcome');
  const [activeCard, setActiveCard] = useState<ExtraCardId | null>(null);
  const [completedCards, setCompletedCards] = useState<Set<ExtraCardId>>(new Set());
  const [pending, setPending] = useState<PendingWrites>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const update = useCallback((patch: Partial<PendingWrites>) => {
    setPending((prev) => ({ ...prev, ...patch }));
  }, []);

  // ── Phase transitions ────────────────────────────────────────────
  const goWelcome = useCallback(() => setPhase('welcome'), []);
  const goStore = useCallback(() => setPhase('store'), []);
  const goShopType = useCallback(() => setPhase('shopType'), []);
  const goTrialInfo = useCallback(() => setPhase('trialInfo'), []);
  const goHub = useCallback(() => { setPhase('hub'); setActiveCard(null); }, []);
  const goReview = useCallback(() => { setPhase('review'); setActiveCard(null); }, []);

  const openCard = useCallback((card: ExtraCardId) => setActiveCard(card), []);
  const closeCard = useCallback(() => setActiveCard(null), []);
  const completeCard = useCallback((card: ExtraCardId) => {
    setCompletedCards((prev) => {
      const next = new Set(prev);
      next.add(card);
      return next;
    });
    setActiveCard(null);
  }, []);

  // ── Commit / skip ────────────────────────────────────────────────
  /**
   * Flush the pending bundle to the server as a single PUT /settings/config.
   * Also writes wizard_completed as 'true' or 'skipped'. On success, refetches
   * the setup-status query and navigates to the dashboard.
   */
  const flushAndExit = useCallback(async (mode: 'complete' | 'skip') => {
    setSaving(true);
    setError('');
    try {
      const writes: Record<string, string> = {};
      for (const [key, value] of Object.entries(pending)) {
        if (value !== undefined && value !== null && value !== '') {
          writes[key] = String(value);
        }
      }
      writes.wizard_completed = mode === 'complete' ? 'true' : 'skipped';
      // Mandatory fields aren't strictly required on skip but we still write whatever we have
      await settingsApi.updateConfig(writes);
      // Persist theme to localStorage as well (uiStore already does this when setTheme is called,
      // but if the user changed theme via StepWelcome we already called setTheme there; this is
      // belt-and-suspenders).
      if (pending.theme) setTheme(pending.theme);
      // Refetch setup-status so the wizard gate in App.tsx sees the new value
      await queryClient.refetchQueries({ queryKey: ['setup-status'] });
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      setPhase('done');
      navigate('/', { replace: true });
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Failed to save setup. Please try again.');
    } finally {
      setSaving(false);
    }
  }, [pending, setTheme, queryClient, navigate]);

  const handleSkip = useCallback(() => flushAndExit('skip'), [flushAndExit]);
  const handleComplete = useCallback(() => flushAndExit('complete'), [flushAndExit]);

  // Pre-fill store_name from the existing store_config value once data arrives.
  useEffect(() => {
    if (existingStoreName && !pending.store_name) {
      setPending((prev) => ({ ...prev, store_name: existingStoreName }));
    }
    // Run only when existingStoreName changes (i.e. when the query resolves).
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existingStoreName]);

  // ── Guards ───────────────────────────────────────────────────────
  if (checkingStatus) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 to-surface-100 dark:from-surface-950 dark:to-surface-900">
        <Loader2 className="h-8 w-8 animate-spin text-primary-600" />
      </div>
    );
  }

  // If the user finished or skipped the wizard in a previous session, don't let them re-enter
  if (wizardCompleted === 'true' || wizardCompleted === 'skipped' || wizardCompleted === 'grandfathered') {
    return <Navigate to="/" replace />;
  }

  // If they don't even have admin setup done, this page isn't right yet (shouldn't happen because
  // the gate in App.tsx sends them to /setup anyway, but guard defensively)
  if (setupCompleted === false) {
    // Render the legacy minimal setup inline — since the first step of the wizard collects
    // enough to satisfy setup_completed anyway, we just let them start the wizard normally.
    // (Intentional: wizard Phase 1+2 writes store_name + address/phone/email/timezone/currency
    // and the backend sets setup_completed on the same PUT.)
  }

  // ── Render the active step ───────────────────────────────────────
  const renderStep = () => {
    const stepProps = { pending, onUpdate: update, onNext: () => {}, onBack: () => {} };
    const subProps = { pending, onUpdate: update, onComplete: () => {}, onCancel: closeCard };

    if (phase === 'welcome') {
      return <StepWelcome {...stepProps} onNext={goStore} onBack={() => {}} />;
    }
    if (phase === 'store') {
      return <StepStoreInfo {...stepProps} onNext={goShopType} onBack={goWelcome} />;
    }
    if (phase === 'shopType') {
      return <StepShopType {...stepProps} onNext={goTrialInfo} onBack={goStore} />;
    }
    if (phase === 'trialInfo') {
      return <StepTrialInfo {...stepProps} onNext={goHub} onBack={goShopType} />;
    }
    if (phase === 'review') {
      return (
        <StepReview
          pending={pending}
          completedCards={completedCards}
          onBack={goHub}
          onComplete={handleComplete}
          onSkip={handleSkip}
          saving={saving}
          error={error}
        />
      );
    }
    if (phase === 'hub') {
      if (activeCard === 'hours') {
        return <StepBusinessHours {...subProps} onComplete={() => completeCard('hours')} />;
      }
      if (activeCard === 'tax') {
        return <StepTax {...subProps} onComplete={() => completeCard('tax')} />;
      }
      if (activeCard === 'logo') {
        return <StepLogo {...subProps} onComplete={() => completeCard('logo')} />;
      }
      if (activeCard === 'receipts') {
        return <StepReceipts {...subProps} onComplete={() => completeCard('receipts')} />;
      }
      if (activeCard === 'import') {
        return <StepImport {...subProps} onComplete={() => completeCard('import')} />;
      }
      if (activeCard === 'sms') {
        return <StepSmsProvider {...subProps} onComplete={() => completeCard('sms')} />;
      }
      if (activeCard === 'email') {
        return <StepEmailSmtp {...subProps} onComplete={() => completeCard('email')} />;
      }
      if (activeCard === 'notifications') {
        return <StepDefaultStatuses {...subProps} onComplete={() => completeCard('notifications')} />;
      }
      return (
        <ExtrasHub
          completedCards={completedCards}
          onOpenCard={openCard}
          onFinish={goReview}
          onBack={goTrialInfo}
        />
      );
    }
    return null;
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-surface-50 to-surface-100 dark:from-surface-950 dark:to-surface-900">
      {/* Top bar with phase indicator + skip */}
      <div className="sticky top-0 z-10 border-b border-surface-200 bg-white/80 backdrop-blur dark:border-surface-700 dark:bg-surface-900/80">
        <div className="mx-auto flex max-w-4xl items-center justify-between px-6 py-3">
          <div className="flex items-center gap-4">
            <span className="font-['League_Spartan'] text-lg font-bold tracking-wide text-primary-700 dark:text-primary-400">
              BIZARRECRM SETUP
            </span>
            <PhaseIndicator phase={phase} />
          </div>
          <SkipToDashboard onSkip={handleSkip} disabled={saving} />
        </div>
      </div>

      {/* Body */}
      <div className="mx-auto max-w-4xl px-6 py-8">
        {error && (
          <div className="mb-4 rounded-lg border border-red-200 bg-red-50 p-3 text-sm text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300">
            {error}
          </div>
        )}
        {renderStep()}
      </div>
    </div>
  );
}

/**
 * Small phase indicator in the top bar. Shows dots for each mandatory+info step
 * and a "hub" pill when on the extras hub or review.
 */
function PhaseIndicator({ phase }: { phase: WizardPhase }) {
  const steps: Array<{ id: WizardPhase; label: string }> = [
    { id: 'welcome', label: 'Welcome' },
    { id: 'store', label: 'Store info' },
    { id: 'shopType', label: 'Shop type' },
    { id: 'trialInfo', label: 'Trial' },
    { id: 'hub', label: 'Extras' },
    { id: 'review', label: 'Done' },
  ];
  const currentIndex = steps.findIndex((s) => s.id === phase);

  return (
    <div className="hidden items-center gap-2 md:flex">
      {steps.map((step, idx) => {
        const active = idx === currentIndex;
        const done = idx < currentIndex;
        return (
          <div key={step.id} className="flex items-center gap-2">
            <div
              className={`flex h-6 w-6 items-center justify-center rounded-full text-xs font-bold ${
                active
                  ? 'bg-primary-600 text-white'
                  : done
                  ? 'bg-green-500 text-white'
                  : 'bg-surface-200 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
              }`}
            >
              {done ? '✓' : idx + 1}
            </div>
            <span
              className={`text-xs ${
                active
                  ? 'font-semibold text-surface-900 dark:text-surface-100'
                  : 'text-surface-500 dark:text-surface-400'
              }`}
            >
              {step.label}
            </span>
            {idx < steps.length - 1 && <div className="h-px w-4 bg-surface-300 dark:bg-surface-600" />}
          </div>
        );
      })}
    </div>
  );
}
