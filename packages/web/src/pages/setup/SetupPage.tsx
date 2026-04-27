import { useState, useCallback, useEffect } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2 } from 'lucide-react';
import { settingsApi, authApi } from '@/api/endpoints';
import { useUiStore } from '@/stores/uiStore';
import type { ExtraCardId, PendingWrites, WizardPhase } from './wizardTypes';
import { StepWelcome } from './steps/StepWelcome';
import { StepStoreInfo } from './steps/StepStoreInfo';
import { ExtrasHub } from './ExtrasHub';
import { StepBusinessHours } from './steps/StepBusinessHours';
import { StepTax } from './steps/StepTax';
import { StepLogo } from './steps/StepLogo';
import { StepReceipts } from './steps/StepReceipts';
import { StepImport } from './steps/StepImport';
import { StepImportHandoff } from './steps/StepImportHandoff';
import { StepSmsProvider } from './steps/StepSmsProvider';
import { StepEmailSmtp } from './steps/StepEmailSmtp';
import { StepDefaultStatuses } from './steps/StepDefaultStatuses';
import { StepReview } from './steps/StepReview';
import { SkipToDashboard } from './SkipToDashboard';

/**
 * First-run setup wizard shell.
 *
 * State machine:
 *   welcome -> store -> hub -> review -> done
 *
 * Mandatory phases (welcome, store) run linearly with validation.
 * Hub is non-sequential — user picks any extras.
 * Review shows the summary and flushes everything via a single PUT /settings/config.
 *
 * Skip can be triggered from any phase via the SkipToDashboard button; the
 * user's partial data is still flushed, and wizard_completed='skipped' is set.
 */
// Shape of the `GET /settings/setup-status` payload used by the wizard.
interface SetupStatusPayload {
  wizard_completed?: string | boolean | null;
  setup_completed?: string | boolean | null;
  store_name?: string | null;
  [key: string]: unknown;
}

export function SetupPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { setTheme } = useUiStore();

  // Short-circuit: if the wizard gate already decided this user doesn't belong here,
  // redirect them. This handles the case where someone manually navigates to /setup
  // after finishing — they shouldn't be able to re-enter the wizard.
  const { data: setupData, isLoading: checkingStatus } = useQuery<{
    data?: { data?: SetupStatusPayload };
  }>({
    queryKey: ['setup-status'],
    queryFn: async () => {
      const res = await settingsApi.getSetupStatus();
      return res as { data?: { data?: SetupStatusPayload } };
    },
    staleTime: 10_000,
  });
  const wizardCompleted = setupData?.data?.data?.wizard_completed;
  const setupCompleted = setupData?.data?.data?.setup_completed;
  const existingStoreName = setupData?.data?.data?.store_name;

  // SSW1: read setup_wizard_skip_count from auth-setup-status so Skip can increment it.
  const { data: authSetupData } = useQuery<{
    data: { success: boolean; data: {
      needsSetup: boolean;
      isMultiTenant: boolean;
      setupWizardCompleted: boolean;
      setupWizardSkippedAt: string | null;
      setupWizardSkipCount: number;
    } };
  }>({
    queryKey: ['auth-setup-status'],
    queryFn: () => authApi.setupStatus(),
    staleTime: 10_000,
  });

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
  const goImportHandoff = useCallback(() => setPhase('importHandoff'), []);
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
   *
   * Complete: writes non-empty pending values + setup_wizard_completed='true'.
   * Skip: writes non-empty pending values + setup_wizard_skipped_at (ISO timestamp)
   *       + setup_wizard_skip_count (current + 1). Empty / null / undefined values
   *       in `pending` are intentionally omitted so the server can apply defaults.
   *
   * Both modes also write the legacy wizard_completed key for Gate 2 compatibility.
   * After either mode, navigates to /dashboard.
   */
  const flushAndExit = useCallback(async (mode: 'complete' | 'skip') => {
    setSaving(true);
    setError('');
    try {
      // Only flush keys that have an actual value — empty strings, null, and
      // undefined are deliberately excluded so the server applies its own defaults.
      const writes: Record<string, string> = {};
      for (const [key, value] of Object.entries(pending)) {
        if (value !== undefined && value !== null && value !== '') {
          writes[key] = String(value);
        }
      }

      if (mode === 'complete') {
        // Mark wizard done via both new and legacy keys.
        writes.setup_wizard_completed = 'true';
        writes.wizard_completed = 'true';
      } else {
        // Skip: record the timestamp and bump the skip counter.
        const currentSkipCount = authSetupData?.data?.data?.setupWizardSkipCount ?? 0;
        writes.setup_wizard_skipped_at = new Date().toISOString();
        writes.setup_wizard_skip_count = String(currentSkipCount + 1);
        writes.wizard_completed = 'skipped';
      }

      await settingsApi.updateConfig(writes);

      // Persist theme to localStorage as well (uiStore already does this when
      // setTheme is called, but if the user changed theme via StepWelcome we
      // already called setTheme there; this is belt-and-suspenders).
      if (pending.theme) setTheme(pending.theme);

      // Refetch both setup-status queries so the wizard gates in App.tsx see
      // the updated values and don't redirect back to /setup immediately.
      await Promise.all([
        queryClient.refetchQueries({ queryKey: ['setup-status'] }),
        queryClient.refetchQueries({ queryKey: ['auth-setup-status'] }),
      ]);
      queryClient.invalidateQueries({ queryKey: ['settings'] });

      setPhase('done');
      navigate('/dashboard', { replace: true });
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Failed to save setup. Please try again.');
    } finally {
      setSaving(false);
    }
  }, [pending, authSetupData, setTheme, queryClient, navigate]);

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
      return <StepStoreInfo {...stepProps} onNext={goImportHandoff} onBack={goWelcome} />;
    }
    if (phase === 'importHandoff') {
      return <StepImportHandoff {...stepProps} onNext={goHub} onBack={goStore} />;
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
          onBack={goStore}
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
    { id: 'importHandoff', label: 'Import' },
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
                  ? 'bg-primary-600 text-primary-950'
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
