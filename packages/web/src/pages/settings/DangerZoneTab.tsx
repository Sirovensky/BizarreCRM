// PROD59 — Settings > Danger Zone tab. Three-step self-service tenant
// termination UI. Backed by POST /api/v1/admin/terminate-tenant with action
// ∈ { request, confirm, finalize }.
//
// UX contract:
//   Step 1 → request button mints a 5-minute token + emails the shop admin.
//   Step 2 → input of the exact subdomain slug (case-sensitive).
//   Step 3 → input of the literal phrase "DELETE ALL DATA PERMANENTLY".
//   Step 4 → paper-trail confirmation screen with the 30-day grace window
//            and the scheduled permanent-delete timestamp.
//
// The modal uses local state only — no Zustand / React Query cache updates
// are needed because success NAVIGATES the user away (their tenant is gone).

import { useEffect, useMemo, useState } from 'react';
import { AlertTriangle, CheckCircle, Loader2, ShieldAlert } from 'lucide-react';
import toast from 'react-hot-toast';
import { useHasRole } from '@/hooks/useHasRole';
import { formatDateTime } from '@/utils/format';
import { tenantTerminationApi } from '@/api/endpoints';

const TERMINATION_PHRASE = 'DELETE ALL DATA PERMANENTLY';

type Step = 'intro' | 'request' | 'confirm_slug' | 'confirm_phrase' | 'done';

interface DoneState {
  deletionScheduledAt: string;
  permanentDeleteAt: string;
  graceDays: number;
}

export function DangerZoneTab() {
  // FIXED-by-Fixer-A20 — WEB-FAE-001: replaced ad-hoc `user?.role === 'admin'`
  // literal with the shared `useHasRole` hook (matches `<PermissionBoundary>`).
  const isAdmin = useHasRole('admin');
  const [open, setOpen] = useState(false);

  return (
    <div className="max-w-3xl">
      <div className="rounded-lg border-2 border-red-300 dark:border-red-800 bg-white dark:bg-surface-900 p-4 shadow-sm">
        <div className="flex items-start gap-3 mb-3">
          <ShieldAlert className="h-6 w-6 text-red-500 flex-shrink-0 mt-0.5" />
          <div>
            <h2 className="text-base font-semibold text-red-600 dark:text-red-400">
              Danger Zone
            </h2>
            <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
              Irreversible actions. Read every sentence before clicking anything.
            </p>
          </div>
        </div>

        <div className="border-t border-red-200 dark:border-red-900/40 pt-4">
          <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
            Terminate this shop
          </h3>
          <p className="text-sm text-surface-600 dark:text-surface-400 mt-1">
            Permanently schedule deletion of your entire account, including every
            ticket, invoice, customer, user, and SMS message. Your data will be
            kept in cold storage for <strong>30 days</strong>; after that, it is
            unrecoverable. Your subdomain will also be released from DNS.
          </p>
          <ul className="text-xs text-surface-500 dark:text-surface-500 mt-2 list-disc pl-5 space-y-0.5">
            <li>Only a shop administrator can initiate this.</li>
            <li>Three typed confirmations are required.</li>
            <li>You have up to 30 days to contact support and restore.</li>
          </ul>

          <button
            type="button"
            onClick={() => setOpen(true)}
            disabled={!isAdmin}
            className="mt-4 inline-flex items-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            <AlertTriangle className="h-4 w-4" />
            Request Account Termination
          </button>
          {!isAdmin && (
            <p className="mt-2 text-xs text-surface-500">
              Only users with the admin role can request account termination.
            </p>
          )}
        </div>
      </div>

      {open && <TerminationModal onClose={() => setOpen(false)} />}
    </div>
  );
}

interface TerminationModalProps {
  onClose: () => void;
}

function TerminationModal({ onClose }: TerminationModalProps) {
  const [step, setStep] = useState<Step>('intro');
  const [loading, setLoading] = useState(false);

  const [token, setToken] = useState<string | null>(null);
  const [tokenExpiresAt, setTokenExpiresAt] = useState<string | null>(null);
  const [typedSlug, setTypedSlug] = useState('');
  const [typedPhrase, setTypedPhrase] = useState('');
  const [doneState, setDoneState] = useState<DoneState | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const canFinalize = useMemo(
    () => typedPhrase === TERMINATION_PHRASE,
    [typedPhrase],
  );

  async function handleRequest() {
    setLoading(true);
    setErrorMessage(null);
    try {
      const res = await tenantTerminationApi.request();
      const data = (res as any)?.data?.data;
      if (!data?.token) {
        throw new Error((res as any)?.data?.message || 'Termination request was rejected');
      }
      setToken(data.token);
      setTokenExpiresAt(data.expires_at || null);
      setStep('confirm_slug');
      toast.success('Confirmation email sent. Check your inbox.');
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || 'Unable to start termination';
      setErrorMessage(msg);
    } finally {
      setLoading(false);
    }
  }

  async function handleConfirmSlug() {
    if (!token) return;
    setLoading(true);
    setErrorMessage(null);
    try {
      await tenantTerminationApi.confirm(token, typedSlug);
      setStep('confirm_phrase');
    } catch (err: any) {
      const msg = err?.response?.data?.message || 'Subdomain did not match';
      setErrorMessage(msg);
    } finally {
      setLoading(false);
    }
  }

  async function handleFinalize() {
    if (!token) return;
    setLoading(true);
    setErrorMessage(null);
    try {
      const res = await tenantTerminationApi.finalize(token, typedSlug, typedPhrase);
      const payload = (res as any)?.data;
      if (!payload?.success) {
        throw new Error(payload?.message || 'Termination was rejected');
      }
      setDoneState({
        deletionScheduledAt: payload.deletion_scheduled_at,
        permanentDeleteAt: payload.permanent_delete_at,
        graceDays: payload.grace_days,
      });
      setStep('done');
    } catch (err: any) {
      const msg = err?.response?.data?.message || err?.message || 'Termination failed';
      setErrorMessage(msg);
    } finally {
      setLoading(false);
    }
  }

  // Esc closes the modal except on the final "done" step, where the user must
  // confirm via the explicit Close button so they don't dismiss the legal
  // paper-trail screen by accident.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && step !== 'done') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [step, onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="danger-zone-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4"
      onClick={(e) => { if (e.target === e.currentTarget && step !== 'done') onClose(); }}
    >
      <div className="w-full max-w-lg rounded-lg bg-white dark:bg-surface-900 shadow-xl border border-red-300 dark:border-red-800">
        <div className="flex items-center justify-between border-b border-surface-200 dark:border-surface-700 px-5 py-4">
          <h2 id="danger-zone-title" className="text-base font-semibold text-red-600 dark:text-red-400 flex items-center gap-2">
            <ShieldAlert className="h-5 w-5" />
            Terminate Account
          </h2>
          {step !== 'done' && (
            <button
              type="button"
              onClick={onClose}
              className="text-surface-400 hover:text-surface-600"
            >
              Cancel
            </button>
          )}
        </div>

        <div className="px-5 py-4 space-y-4">
          {errorMessage && (
            <div role="alert" aria-live="polite" className="rounded-md bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 p-3 text-sm text-red-700 dark:text-red-300">
              {errorMessage}
            </div>
          )}

          {step === 'intro' && (
            <StepIntro
              onBegin={() => setStep('request')}
              onCancel={onClose}
            />
          )}

          {step === 'request' && (
            <StepRequest
              loading={loading}
              onRequest={handleRequest}
              onBack={() => setStep('intro')}
            />
          )}

          {step === 'confirm_slug' && (
            <StepConfirmSlug
              typedSlug={typedSlug}
              setTypedSlug={setTypedSlug}
              tokenExpiresAt={tokenExpiresAt}
              loading={loading}
              onConfirm={handleConfirmSlug}
              onBack={() => {
                // Reset the termination token + typed slug on back-nav so a
                // second handleRequest starts fresh. Without this, a stale
                // (potentially server-consumed) token lingers and confirm
                // would silently fail.
                setToken(null);
                setTypedSlug('');
                setErrorMessage(null);
                setStep('request');
              }}
            />
          )}

          {step === 'confirm_phrase' && (
            <StepConfirmPhrase
              typedPhrase={typedPhrase}
              setTypedPhrase={setTypedPhrase}
              canFinalize={canFinalize}
              loading={loading}
              onFinalize={handleFinalize}
              onBack={() => {
                setTypedPhrase('');
                setErrorMessage(null);
                setStep('confirm_slug');
              }}
            />
          )}

          {step === 'done' && doneState && (
            <StepDone data={doneState} onClose={onClose} />
          )}
        </div>
      </div>
    </div>
  );
}

function StepIntro({ onBegin, onCancel }: { onBegin: () => void; onCancel: () => void }) {
  return (
    <>
      <p className="text-sm text-surface-700 dark:text-surface-300">
        You are about to start the account-termination flow. Three separate
        confirmations are required, and the first one sends an email to your
        shop admin address so unauthorized terminations are flagged immediately.
      </p>
      <ul className="text-sm text-surface-600 dark:text-surface-400 list-disc pl-5 space-y-1">
        <li>Step 1 — request termination (email sent).</li>
        <li>Step 2 — type your subdomain slug exactly.</li>
        <li>Step 3 — type the literal phrase <code>DELETE ALL DATA PERMANENTLY</code>.</li>
      </ul>
      <div className="flex gap-3 pt-2">
        <button
          type="button"
          onClick={onBegin}
          className="rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700"
        >
          Continue
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-md border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-semibold text-surface-700 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          Nevermind
        </button>
      </div>
    </>
  );
}

function StepRequest({
  loading,
  onRequest,
  onBack,
}: {
  loading: boolean;
  onRequest: () => void;
  onBack: () => void;
}) {
  return (
    <>
      <p className="text-sm text-surface-700 dark:text-surface-300">
        Click <strong>Request Account Termination</strong> to send the one-time
        token email. The token is valid for 5 minutes. After this step, you
        still have two more confirmations before anything is deleted.
      </p>
      <div className="flex gap-3 pt-2">
        <button
          type="button"
          onClick={onRequest}
          disabled={loading}
          className="inline-flex items-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50"
        >
          {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <AlertTriangle className="h-4 w-4" />}
          Request Account Termination
        </button>
        <button
          type="button"
          onClick={onBack}
          className="rounded-md border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-semibold text-surface-700 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          Back
        </button>
      </div>
    </>
  );
}

function StepConfirmSlug({
  typedSlug,
  setTypedSlug,
  tokenExpiresAt,
  loading,
  onConfirm,
  onBack,
}: {
  typedSlug: string;
  setTypedSlug: (v: string) => void;
  tokenExpiresAt: string | null;
  loading: boolean;
  onConfirm: () => void;
  onBack: () => void;
}) {
  return (
    <>
      <p className="text-sm text-surface-700 dark:text-surface-300">
        Type your tenant slug <em>exactly</em> (case-sensitive) to confirm you
        know which shop you're deleting.
      </p>
      {tokenExpiresAt && (
        <p className="text-xs text-surface-500">
          Token expires at {formatDateTime(tokenExpiresAt)}.
        </p>
      )}
      <input
        type="text"
        value={typedSlug}
        onChange={(e) => setTypedSlug(e.target.value)}
        placeholder="e.g. bizarreelectronics"
        autoComplete="off"
        spellCheck={false}
        className="block w-full rounded-md border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2"
      />
      <div className="flex gap-3 pt-2">
        <button
          type="button"
          onClick={onConfirm}
          disabled={loading || typedSlug.length === 0}
          className="inline-flex items-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          Confirm slug
        </button>
        <button
          type="button"
          onClick={onBack}
          className="rounded-md border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-semibold text-surface-700 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          Back
        </button>
      </div>
    </>
  );
}

function StepConfirmPhrase({
  typedPhrase,
  setTypedPhrase,
  canFinalize,
  loading,
  onFinalize,
  onBack,
}: {
  typedPhrase: string;
  setTypedPhrase: (v: string) => void;
  canFinalize: boolean;
  loading: boolean;
  onFinalize: () => void;
  onBack: () => void;
}) {
  return (
    <>
      <p className="text-sm text-surface-700 dark:text-surface-300">
        Type the phrase below exactly (including spaces, uppercase, no trailing
        punctuation) to finalize deletion:
      </p>
      <p className="rounded-md bg-surface-100 dark:bg-surface-800 px-3 py-2 font-mono text-sm text-red-600 dark:text-red-400">
        {TERMINATION_PHRASE}
      </p>
      <input
        type="text"
        value={typedPhrase}
        onChange={(e) => setTypedPhrase(e.target.value)}
        placeholder="Type the phrase here"
        autoComplete="off"
        spellCheck={false}
        className="block w-full rounded-md border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-red-500 focus-visible:ring-offset-2"
      />
      <div className="flex gap-3 pt-2">
        <button
          type="button"
          onClick={onFinalize}
          disabled={loading || !canFinalize}
          className="inline-flex items-center gap-2 rounded-md bg-red-600 px-4 py-2 text-sm font-semibold text-white shadow-sm hover:bg-red-700 disabled:opacity-50"
        >
          {loading && <Loader2 className="h-4 w-4 animate-spin" />}
          Permanently delete my account
        </button>
        <button
          type="button"
          onClick={onBack}
          className="rounded-md border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-semibold text-surface-700 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          Back
        </button>
      </div>
    </>
  );
}

function StepDone({ data, onClose }: { data: DoneState; onClose: () => void }) {
  return (
    <>
      <div className="flex items-center gap-3">
        <CheckCircle className="h-6 w-6 text-green-500" />
        <h3 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
          Termination scheduled.
        </h3>
      </div>
      <p className="text-sm text-surface-700 dark:text-surface-300">
        Your account has been taken offline and is now in a {data.graceDays}-day
        grace window. Contact support before this window closes if you change
        your mind.
      </p>
      <dl className="rounded-md border border-surface-200 dark:border-surface-700 p-3 text-sm space-y-2">
        <div className="flex items-center justify-between">
          <dt className="text-surface-500">Scheduled at</dt>
          <dd className="font-mono text-xs text-surface-900 dark:text-surface-100">
            {formatDateTime(data.deletionScheduledAt)}
          </dd>
        </div>
        <div className="flex items-center justify-between">
          <dt className="text-surface-500">Permanent delete on</dt>
          <dd className="font-mono text-xs text-red-600 dark:text-red-400">
            {formatDateTime(data.permanentDeleteAt)}
          </dd>
        </div>
      </dl>
      <p className="text-xs text-surface-500">
        You will be signed out on your next action. Save this page for your records.
      </p>
      <div className="pt-2">
        <button
          type="button"
          onClick={onClose}
          className="rounded-md border border-surface-300 dark:border-surface-700 px-4 py-2 text-sm font-semibold text-surface-700 dark:text-surface-300 hover:bg-surface-100 dark:hover:bg-surface-800"
        >
          Close
        </button>
      </div>
    </>
  );
}
