import { useState, useCallback, useEffect, useMemo } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2 } from 'lucide-react';
import { settingsApi, authApi } from '@/api/endpoints';
import { useUiStore } from '@/stores/uiStore';
import type { PendingWrites, WizardPhase } from './wizardTypes';
import { WIZARD_ORDER_SELF, WIZARD_ORDER_SAAS, WIZARD_PHASE_LABELS } from './wizardTypes';
import { StepWelcome } from './steps/StepWelcome';
import { StepStoreInfo } from './steps/StepStoreInfo';
import { StepImportHandoff } from './steps/StepImportHandoff';
import { StepShopType } from './steps/StepShopType';
import { StepReview } from './steps/StepReview';
import { SkipToDashboard } from './SkipToDashboard';

/**
 * First-run setup wizard shell.
 *
 * H3 (2026-04-27): replaced welcome→store→hub→review with strict linear
 * `WIZARD_ORDER_SELF` / `WIZARD_ORDER_SAAS` (depending on tenancy mode).
 * `phase` is an index into the active order array. `goNext` / `goBack`
 * shift it. Steps without a real component yet render `<PlaceholderStep>`
 * so the file compiles before agent waves land.
 *
 * Sub-agent waves (see docs/setup-wizard-implementation-plan.md):
 *   Wave 3 → swaps placeholders for StepFirstLogin / StepForcePassword /
 *            StepSignup / StepVerifyEmail / StepTwoFactorSetup
 *   Wave 4 → swaps placeholders for StepRepairPricing / StepPaymentTerminal /
 *            StepFirstEmployees / StepNotificationTemplates / StepReceiptPrinter /
 *            StepCashDrawer / StepBookingPolicy / StepWarrantyDefaults /
 *            StepBackupDestination / StepMobileAppQr / StepDone
 *   Wave 5 → tweaks already-imported StepWelcome / StepShopType / StepStoreInfo /
 *            StepImportHandoff / StepDefaultStatuses / StepBusinessHours /
 *            StepTax / StepReceipts / StepLogo / StepSmsProvider / StepEmailSmtp /
 *            StepReview
 */
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

  const isMultiTenant = authSetupData?.data?.data?.isMultiTenant ?? false;
  const orderedPhases = useMemo<WizardPhase[]>(
    () => (isMultiTenant ? WIZARD_ORDER_SAAS : WIZARD_ORDER_SELF),
    [isMultiTenant],
  );

  // The wizard body starts at 'welcome' for already-authenticated users.
  // Pre-wizard auth (firstLogin/signup/forcePassword/verifyEmail/twoFactorSetup)
  // is rendered only when the gate has not yet redirected here from /login.
  // Our existing gate in App.tsx routes to /setup AFTER auth, so the default
  // entry phase here is 'welcome'.
  const [phase, setPhase] = useState<WizardPhase>('welcome');
  const [pending, setPending] = useState<PendingWrites>({});
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const update = useCallback((patch: Partial<PendingWrites>) => {
    setPending((prev) => ({ ...prev, ...patch }));
  }, []);

  // ── Linear navigation ───────────────────────────────────────────
  const phaseIndex = orderedPhases.indexOf(phase);
  const prevPhase: WizardPhase | undefined = phaseIndex > 0 ? orderedPhases[phaseIndex - 1] : undefined;
  const nextPhase: WizardPhase | undefined =
    phaseIndex >= 0 && phaseIndex < orderedPhases.length - 1 ? orderedPhases[phaseIndex + 1] : undefined;

  const goNext = useCallback(() => {
    if (nextPhase) setPhase(nextPhase);
  }, [nextPhase]);
  const goBack = useCallback(() => {
    if (prevPhase) setPhase(prevPhase);
  }, [prevPhase]);

  // ── Commit / skip ───────────────────────────────────────────────
  const flushAndExit = useCallback(async (mode: 'complete' | 'skip') => {
    setSaving(true);
    setError('');
    try {
      const writes: Record<string, string> = {};
      for (const [key, value] of Object.entries(pending)) {
        // signup_email is in-flow only; never persisted to store_config.
        if (key === 'signup_email') continue;
        if (value !== undefined && value !== null && value !== '') {
          writes[key] = String(value);
        }
      }

      if (mode === 'complete') {
        writes.setup_wizard_completed = 'true';
        writes.wizard_completed = 'true';
      } else {
        const currentSkipCount = authSetupData?.data?.data?.setupWizardSkipCount ?? 0;
        writes.setup_wizard_skipped_at = new Date().toISOString();
        writes.setup_wizard_skip_count = String(currentSkipCount + 1);
        writes.wizard_completed = 'skipped';
      }

      await settingsApi.updateConfig(writes);
      if (pending.theme) setTheme(pending.theme);

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

  useEffect(() => {
    if (existingStoreName && !pending.store_name) {
      setPending((prev) => ({ ...prev, store_name: existingStoreName }));
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [existingStoreName]);

  // ── Guards ──────────────────────────────────────────────────────
  if (checkingStatus) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 to-surface-100 dark:from-surface-950 dark:to-surface-900">
        <Loader2 className="h-8 w-8 animate-spin text-primary-600" />
      </div>
    );
  }
  if (wizardCompleted === 'true' || wizardCompleted === 'skipped' || wizardCompleted === 'grandfathered') {
    return <Navigate to="/" replace />;
  }
  // setupCompleted=false case is handled by App.tsx gate; we let the wizard run anyway.
  void setupCompleted;

  // ── Render the active step ──────────────────────────────────────
  const stepProps = {
    pending,
    onUpdate: update,
    onNext: goNext,
    onBack: goBack,
    onSkip: handleSkip,
  };

  const renderStep = () => {
    switch (phase) {
      // Pre-wizard auth phases — Wave 3 will replace these placeholders.
      case 'firstLogin':
        return <PlaceholderStep phase={phase} {...stepProps} />;
      case 'forcePassword':
        return <PlaceholderStep phase={phase} {...stepProps} />;
      case 'signup':
        return <PlaceholderStep phase={phase} {...stepProps} />;
      case 'verifyEmail':
        return <PlaceholderStep phase={phase} {...stepProps} />;
      case 'twoFactorSetup':
        return <PlaceholderStep phase={phase} {...stepProps} />;

      // Wizard body — already-built steps wired to linear nav.
      // StepWelcome / StepStoreInfo / StepImportHandoff / StepShopType already
      // use the new StepProps signature. The remaining sub-step-style files
      // (StepBusinessHours/Tax/Logo/Receipts/DefaultStatuses/SmsProvider/EmailSmtp)
      // are scheduled for Wave 5 rewrite — until then they render through
      // PlaceholderStep so the wizard remains traversable.
      case 'welcome':
        return <StepWelcome {...stepProps} />;
      case 'shopType':
        return <StepShopType {...stepProps} />;
      case 'store':
        return <StepStoreInfo {...stepProps} />;
      case 'importHandoff':
        return <StepImportHandoff {...stepProps} />;
      case 'defaultStatuses':
      case 'businessHours':
      case 'tax':
      case 'receipts':
      case 'logo':
      case 'smsProvider':
      case 'emailSmtp':
        return <PlaceholderStep phase={phase} {...stepProps} />;

      // New body steps — Wave 4 will replace these placeholders.
      case 'repairPricing':
      case 'paymentTerminal':
      case 'firstEmployees':
      case 'notificationTemplates':
      case 'receiptPrinter':
      case 'cashDrawer':
      case 'bookingPolicy':
      case 'warrantyDefaults':
      case 'backupDestination':
      case 'mobileAppQr':
        return <PlaceholderStep phase={phase} {...stepProps} />;

      case 'review':
        return (
          <StepReview
            pending={pending}
            completedCards={new Set()}
            onBack={goBack}
            onComplete={handleComplete}
            onSkip={handleSkip}
            saving={saving}
            error={error}
          />
        );
      case 'done':
        return <PlaceholderStep phase={phase} {...stepProps} />;

      default:
        return null;
    }
  };

  return (
    <div className="min-h-screen bg-gradient-to-br from-surface-50 to-surface-100 dark:from-surface-950 dark:to-surface-900">
      {/* Top bar with linear progress + skip */}
      <div className="sticky top-0 z-10 border-b border-surface-200 bg-white/80 backdrop-blur dark:border-surface-700 dark:bg-surface-900/80">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-3">
          <div className="flex items-center gap-4">
            <span className="font-['League_Spartan'] text-lg font-bold tracking-wide text-primary-700 dark:text-primary-400">
              BIZARRECRM SETUP
            </span>
            <LinearProgress phase={phase} orderedPhases={orderedPhases} />
          </div>
          <SkipToDashboard onSkip={handleSkip} disabled={saving} />
        </div>
      </div>

      {/* Body */}
      <div className="mx-auto max-w-5xl px-6 py-8">
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
 * Placeholder rendered for any phase whose real Step component hasn't been
 * built yet (Wave 3, 4 sub-agents are still pending). Shows the current
 * phase name + Back / Continue buttons so the wizard remains traversable
 * end-to-end during agent rollout.
 */
function PlaceholderStep({
  phase,
  onNext,
  onBack,
  onSkip,
}: {
  phase: WizardPhase;
  pending: PendingWrites;
  onUpdate: (patch: Partial<PendingWrites>) => void;
  onNext: () => void;
  onBack: () => void;
  onSkip?: () => void;
}) {
  return (
    <div className="rounded-xl border border-amber-200 bg-amber-50 p-8 dark:border-amber-500/30 dark:bg-amber-900/20">
      <p className="text-xs font-semibold uppercase tracking-wider text-amber-700 dark:text-amber-300">
        Pending build (placeholder)
      </p>
      <h2 className="mt-2 text-2xl font-bold text-amber-900 dark:text-amber-100">
        {WIZARD_PHASE_LABELS[phase]}
      </h2>
      <p className="mt-2 text-sm text-amber-800 dark:text-amber-200">
        This step's real UI is still being built by a sub-agent. See{' '}
        <code className="rounded bg-amber-100 px-1 py-0.5 dark:bg-amber-800/40">
          docs/setup-wizard-implementation-plan.md
        </code>{' '}
        for the agent assignment.
      </p>
      <div className="mt-6 flex items-center gap-3">
        <button
          type="button"
          onClick={onBack}
          className="rounded-lg border border-amber-300 bg-white px-4 py-2 text-sm font-medium text-amber-900 hover:bg-amber-100 dark:border-amber-500/40 dark:bg-amber-900/30 dark:text-amber-100"
        >
          Back
        </button>
        <button
          type="button"
          onClick={onNext}
          className="rounded-lg bg-amber-600 px-4 py-2 text-sm font-medium text-white hover:bg-amber-700"
        >
          Continue
        </button>
        {onSkip && (
          <button
            type="button"
            onClick={onSkip}
            className="ml-auto rounded-lg px-3 py-2 text-sm text-amber-700 hover:bg-amber-100 dark:text-amber-300"
          >
            Skip wizard
          </button>
        )}
      </div>
    </div>
  );
}

/**
 * Linear progress indicator for the top bar. Shows current step number
 * out of total + the previous/current/next phase labels.
 */
function LinearProgress({
  phase,
  orderedPhases,
}: {
  phase: WizardPhase;
  orderedPhases: WizardPhase[];
}) {
  const idx = orderedPhases.indexOf(phase);
  if (idx < 0) return null;
  return (
    <div className="hidden items-center gap-3 md:flex">
      <span className="text-xs text-surface-500 dark:text-surface-400">
        Step {idx + 1} / {orderedPhases.length}
      </span>
      <span className="text-sm font-semibold text-surface-900 dark:text-surface-100">
        {WIZARD_PHASE_LABELS[phase]}
      </span>
    </div>
  );
}
