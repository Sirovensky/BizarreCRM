import { useState, useCallback, useEffect, useMemo } from 'react';
import { Navigate, useNavigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Loader2 } from 'lucide-react';
import { settingsApi, authApi } from '@/api/endpoints';
import { useUiStore } from '@/stores/uiStore';
import type { PendingWrites, WizardPhase } from './wizardTypes';
import { WIZARD_BODY_ORDER } from './wizardTypes';
import { WizardBreadcrumb } from './components/WizardBreadcrumb';
import { StepWelcome } from './steps/StepWelcome';
import { StepStoreInfo } from './steps/StepStoreInfo';
import { StepImportHandoff } from './steps/StepImportHandoff';
import { StepShopType } from './steps/StepShopType';
import { StepReview } from './steps/StepReview';
import { SkipToDashboard } from './SkipToDashboard';
// Wave 3 — pre-wizard auth screens
import { StepFirstLogin } from './steps/StepFirstLogin';
import { StepForcePassword } from './steps/StepForcePassword';
import { StepSignup } from './steps/StepSignup';
import { StepVerifyEmail } from './steps/StepVerifyEmail';
import { StepTwoFactorSetup } from './steps/StepTwoFactorSetup';
// Wave 4 — new wizard body steps
import { StepRepairPricing } from './steps/StepRepairPricing';
import { StepPaymentTerminal } from './steps/StepPaymentTerminal';
import { StepFirstEmployees } from './steps/StepFirstEmployees';
import { StepNotificationTemplates } from './steps/StepNotificationTemplates';
import { StepReceiptPrinter } from './steps/StepReceiptPrinter';
import { StepCashDrawer } from './steps/StepCashDrawer';
import { StepBookingPolicy } from './steps/StepBookingPolicy';
import { StepWarrantyDefaults } from './steps/StepWarrantyDefaults';
import { StepBackupDestination } from './steps/StepBackupDestination';
import { StepMobileAppQr } from './steps/StepMobileAppQr';
import { StepDone } from './steps/StepDone';
// Wave 5 — body steps rewritten to StepProps
import { StepDefaultStatuses } from './steps/StepDefaultStatuses';
import { StepBusinessHours } from './steps/StepBusinessHours';
import { StepTax } from './steps/StepTax';
import { StepReceipts } from './steps/StepReceipts';
import { StepLogo } from './steps/StepLogo';
import { StepSmsProvider } from './steps/StepSmsProvider';
import { StepEmailSmtp } from './steps/StepEmailSmtp';

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

  // SetupPage runs behind ProtectedRoute → user is already authenticated
  // when this component mounts. Use the body-only order so the Back button
  // from 'welcome' is correctly disabled (no auth phase to walk back into).
  // The full SELF/SAAS orders remain exported for forward-compat if we ever
  // route the pre-auth screens through this shell.
  // authSetupData is read in flushAndExit() below for skip-count bumping.
  const orderedPhases = useMemo<WizardPhase[]>(() => WIZARD_BODY_ORDER, []);

  // ── Persistent wizard state ─────────────────────────────────────
  // sessionStorage survives page refreshes within the same tab so the user
  // never loses progress to F5 / browser autoreload / Vite HMR. Cleared
  // when the wizard finishes (complete/skip flushAndExit) AND when the tab
  // closes — a brand-new tab starts a fresh wizard. Keyed per session so
  // multiple tabs of the same browser don't collide.
  const STORAGE_KEY = 'bizarrecrm:setup-wizard:v1';
  type Persisted = { phase: WizardPhase; pending: PendingWrites };

  const [phase, setPhase] = useState<WizardPhase>(() => {
    if (typeof window === 'undefined') return 'welcome';
    try {
      const raw = sessionStorage.getItem(STORAGE_KEY);
      if (!raw) return 'welcome';
      const parsed = JSON.parse(raw) as Persisted;
      // Validate phase is in the body order — otherwise restart fresh.
      if (parsed.phase && WIZARD_BODY_ORDER.includes(parsed.phase)) {
        return parsed.phase;
      }
    } catch {
      // Corrupt JSON or storage disabled — fall through to default.
    }
    return 'welcome';
  });
  const [pending, setPending] = useState<PendingWrites>(() => {
    if (typeof window === 'undefined') return {};
    try {
      const raw = sessionStorage.getItem(STORAGE_KEY);
      if (!raw) return {};
      const parsed = JSON.parse(raw) as Persisted;
      return parsed.pending ?? {};
    } catch {
      return {};
    }
  });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  // Persist every state change so a refresh restores both phase + pending.
  useEffect(() => {
    if (typeof window === 'undefined') return;
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify({ phase, pending } satisfies Persisted));
    } catch {
      // Storage quota exceeded / disabled — silently ignore. Worst case the
      // user loses partial state on refresh, which is the pre-fix behavior.
    }
  }, [phase, pending]);

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

      // Wizard finished successfully (complete or skip) — clear persisted
      // state so a future revisit to /setup starts fresh instead of resuming
      // a stale half-complete session.
      try {
        sessionStorage.removeItem(STORAGE_KEY);
      } catch {
        /* ignore */
      }

      // Render the StepDone screen with its non-duplicate Settings deep-link
      // cards instead of jumping straight to /dashboard. The user navigates
      // to /dashboard from the StepDone CTA. Skip path still goes direct.
      if (mode === 'complete') {
        setPhase('done');
      } else {
        navigate('/dashboard', { replace: true });
      }
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
      <div className="flex min-h-screen items-center justify-center bg-surface-50 dark:bg-surface-900">
        <Loader2 className="h-8 w-8 animate-spin text-primary-600" />
      </div>
    );
  }
  // If the wizard is already complete, redirect — UNLESS the user is currently
  // on the 'done' phase, which means flushAndExit just transitioned them here
  // intentionally to show the StepDone screen with its deep-link cards before
  // they leave. Without this exception the gate fires immediately after
  // setPhase('done') and the user never sees the Done UI.
  //
  // 'skipped' is intentionally NOT in this list: when App.tsx Gate 3 forces an
  // admin back here after a prior skip (skip_count < 3), the wizard must re-render
  // instead of bouncing back to '/'. Otherwise Gate 3 ↔ this redirect form an
  // infinite loop until the browser kills history API calls.
  if (
    phase !== 'done' &&
    (wizardCompleted === 'true' || wizardCompleted === 'grandfathered')
  ) {
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
      // Pre-wizard auth phases (Wave 3)
      case 'firstLogin':
        return <StepFirstLogin {...stepProps} />;
      case 'forcePassword':
        return <StepForcePassword {...stepProps} />;
      case 'signup':
        return <StepSignup {...stepProps} />;
      case 'verifyEmail':
        return <StepVerifyEmail {...stepProps} />;
      case 'twoFactorSetup':
        return <StepTwoFactorSetup {...stepProps} />;

      // Wizard body
      case 'welcome':
        return <StepWelcome {...stepProps} />;
      case 'shopType':
        return <StepShopType {...stepProps} />;
      case 'store':
        return <StepStoreInfo {...stepProps} />;
      case 'importHandoff':
        return <StepImportHandoff {...stepProps} />;
      case 'repairPricing':
        return <StepRepairPricing {...stepProps} />;
      case 'defaultStatuses':
        return <StepDefaultStatuses {...stepProps} />;
      case 'businessHours':
        return <StepBusinessHours {...stepProps} />;
      case 'tax':
        return <StepTax {...stepProps} />;
      case 'receipts':
        return <StepReceipts {...stepProps} />;
      case 'logo':
        return <StepLogo {...stepProps} />;
      case 'paymentTerminal':
        return <StepPaymentTerminal {...stepProps} />;
      case 'firstEmployees':
        return <StepFirstEmployees {...stepProps} />;
      case 'smsProvider':
        return <StepSmsProvider {...stepProps} />;
      case 'emailSmtp':
        return <StepEmailSmtp {...stepProps} />;
      case 'notificationTemplates':
        return <StepNotificationTemplates {...stepProps} />;
      case 'receiptPrinter':
        return <StepReceiptPrinter {...stepProps} />;
      case 'cashDrawer':
        return <StepCashDrawer {...stepProps} />;
      case 'bookingPolicy':
        return <StepBookingPolicy {...stepProps} />;
      case 'warrantyDefaults':
        return <StepWarrantyDefaults {...stepProps} />;
      case 'backupDestination':
        return <StepBackupDestination {...stepProps} />;
      case 'mobileAppQr':
        return <StepMobileAppQr {...stepProps} />;

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
        return <StepDone {...stepProps} />;

      default:
        return null;
    }
  };

  return (
    <div className="min-h-screen bg-surface-50 dark:bg-surface-900">
      {/* Top bar — brand + skip only. Step counter intentionally removed:
          the per-step WizardBreadcrumb pill below already shows current
          phase + prev/next neighbors with consistent body-order numbering. */}
      <div className="sticky top-0 z-10 border-b border-surface-200 bg-white/80 backdrop-blur dark:border-surface-700 dark:bg-surface-900/80">
        <div className="mx-auto flex max-w-5xl items-center justify-between px-6 py-3">
          <span className="font-['League_Spartan'] text-lg font-bold tracking-wide text-primary-700 dark:text-primary-400">
            BIZARRECRM SETUP
          </span>
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
        {/* Single source of truth for breadcrumb. Step files no longer
            render their own — the shell renders one above the active step
            using phase-driven mode. */}
        <div className="mb-6 flex justify-center">
          <WizardBreadcrumb currentPhase={phase} />
        </div>
        {renderStep()}
      </div>
    </div>
  );
}
