import { useState } from 'react';
import type { JSX } from 'react';
import {
  CreditCard,
  Eye,
  EyeOff,
  Wifi,
  CheckCircle2,
  XCircle,
  Loader2,
  ArrowLeft,
  ArrowRight,
} from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps } from '../wizardTypes';

/**
 * Step 14 — Payment terminal (BlockChyp).
 *
 * Mirrors `#screen-14` in `docs/setup-wizard-preview.html`. Two stacked cards:
 *
 *   1. BlockChyp credentials — API key, bearer token, signing key. All three
 *      are sensitive, so each input renders as a `password` field with an
 *      eye toggle to reveal/hide while typing. Persisted to
 *      `blockchyp_api_key`, `blockchyp_bearer_token`, `blockchyp_signing_key`.
 *
 *   2. Pair terminal — terminal name + LAN IP. Disabled until all three creds
 *      above are non-empty (you can't pair without auth). Persisted to
 *      `blockchyp_terminal_name`, `blockchyp_terminal_ip`.
 *
 * "Test connection" is a stub — the real BlockChyp heartbeat call is wired up
 * by the BlockChyp service in a later batch. For now it shows a toast and
 * flips a placeholder status pill (idle → checking → unverified). This keeps
 * the UI honest: we never claim a connection succeeded when no call was made.
 *
 * Skip path: user clicks Skip → onNext() advances without enrolling. The POS
 * will show a "card payments disabled" banner until creds are saved later
 * from Settings → Payments. Per project memory, BlockChyp creds are
 * shop-owned, never platform-shared (PCI scope minimization).
 */

type TestStatus = 'idle' | 'checking' | 'unverified' | 'ok' | 'fail';

const IPV4_RE = /^(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)$/;

function SecretInput({
  id,
  label,
  value,
  onChange,
  placeholder,
}: {
  id: string;
  label: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}): JSX.Element {
  const [shown, setShown] = useState(false);
  return (
    <div>
      <label
        htmlFor={id}
        className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
      >
        {label}
      </label>
      <div className="relative">
        <input
          id={id}
          type={shown ? 'text' : 'password'}
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder={placeholder}
          autoComplete="off"
          spellCheck={false}
          className="block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 pr-10 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
        />
        <button
          type="button"
          onClick={() => setShown((s) => !s)}
          aria-label={shown ? `Hide ${label}` : `Show ${label}`}
          aria-pressed={shown}
          className="absolute inset-y-0 right-0 flex items-center px-3 text-surface-400 hover:text-surface-600 dark:text-surface-500 dark:hover:text-surface-300"
        >
          {shown ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
        </button>
      </div>
    </div>
  );
}

export function StepPaymentTerminal({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const [apiKey, setApiKey] = useState<string>(pending.blockchyp_api_key ?? '');
  const [bearer, setBearer] = useState<string>(pending.blockchyp_bearer_token ?? '');
  const [signing, setSigning] = useState<string>(pending.blockchyp_signing_key ?? '');
  const [terminalName, setTerminalName] = useState<string>(
    pending.blockchyp_terminal_name ?? '',
  );
  const [terminalIp, setTerminalIp] = useState<string>(pending.blockchyp_terminal_ip ?? '');
  const [testStatus, setTestStatus] = useState<TestStatus>('idle');

  const credsComplete =
    apiKey.trim().length > 0 && bearer.trim().length > 0 && signing.trim().length > 0;
  const ipValid = terminalIp.trim().length === 0 || IPV4_RE.test(terminalIp.trim());

  // Push every change up so the wizard shell's bulk PUT /settings/config
  // captures partial state even if the user backs out and the shell flushes
  // on Skip-to-Dashboard.
  const persist = (patch: {
    api?: string;
    bearer?: string;
    signing?: string;
    name?: string;
    ip?: string;
  }) => {
    onUpdate({
      blockchyp_api_key: patch.api ?? apiKey,
      blockchyp_bearer_token: patch.bearer ?? bearer,
      blockchyp_signing_key: patch.signing ?? signing,
      blockchyp_terminal_name: patch.name ?? terminalName,
      blockchyp_terminal_ip: patch.ip ?? terminalIp,
    });
  };

  const handleApiChange = (v: string) => {
    setApiKey(v);
    persist({ api: v });
  };
  const handleBearerChange = (v: string) => {
    setBearer(v);
    persist({ bearer: v });
  };
  const handleSigningChange = (v: string) => {
    setSigning(v);
    persist({ signing: v });
  };
  const handleNameChange = (v: string) => {
    setTerminalName(v);
    persist({ name: v });
  };
  const handleIpChange = (v: string) => {
    setTerminalIp(v);
    persist({ ip: v });
  };

  const handleTestConnection = () => {
    if (!credsComplete) {
      toast.error('Enter BlockChyp credentials first.');
      return;
    }
    if (!ipValid || terminalIp.trim().length === 0) {
      toast.error('Enter a valid terminal IPv4 address first.');
      return;
    }
    setTestStatus('checking');
    // Stub — the real BlockChyp heartbeat is wired up by the BlockChyp
    // service in a later batch. We deliberately do NOT mark success here;
    // we mark "unverified" so nobody mistakes this for a real check.
    window.setTimeout(() => {
      setTestStatus('unverified');
      toast('Heartbeat will be wired with BlockChyp service once creds verified.', {
        icon: 'i',
      });
    }, 400);
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const cardBase =
    'bg-white dark:bg-surface-800 rounded-xl border border-surface-200 dark:border-surface-700 p-6 mb-4';

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Payment terminal
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          BlockChyp is the single processor for card-present and card-not-present
          payments. Shop-owned credentials — you can also set this up later from
          Settings &rarr; Payments.
        </p>
      </div>

      <div>
        {/* ── Card 1 — BlockChyp credentials ─────────────────────── */}
        <section className={cardBase} aria-labelledby="bc-creds-title">
          <header className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950">
              <CreditCard className="h-5 w-5" />
            </div>
            <div>
              <h2
                id="bc-creds-title"
                className="text-lg font-semibold text-surface-900 dark:text-surface-100"
              >
                BlockChyp credentials
              </h2>
              <p className="text-xs text-surface-500 dark:text-surface-400">
                Encrypted at rest. Never shared with the platform.
              </p>
            </div>
          </header>

          <div className="space-y-4">
            <SecretInput
              id="blockchyp-api-key"
              label="API key"
              value={apiKey}
              onChange={handleApiChange}
              placeholder="ABC123XY..."
            />
            <SecretInput
              id="blockchyp-bearer-token"
              label="Bearer token"
              value={bearer}
              onChange={handleBearerChange}
              placeholder="Long-lived token from BlockChyp dashboard"
            />
            <SecretInput
              id="blockchyp-signing-key"
              label="Signing key"
              value={signing}
              onChange={handleSigningChange}
              placeholder="HMAC signing secret"
            />
          </div>

          <p className="mt-4 text-xs leading-relaxed text-surface-500 dark:text-surface-400">
            Don&apos;t have BlockChyp creds yet? Sign up at{' '}
            <span className="font-medium text-surface-700 dark:text-surface-300">
              blockchyp.com
            </span>{' '}
            &mdash; Bizarre CRM uses BlockChyp as its single payment processor (CP +
            CNP). You&apos;ll get keys after underwriting completes (~24-48 hr).
          </p>
        </section>

        {/* ── Card 2 — Pair terminal ─────────────────────────────── */}
        <section
          className={`${cardBase} ${credsComplete ? '' : 'opacity-60'}`}
          aria-labelledby="bc-pair-title"
          aria-disabled={!credsComplete}
        >
          <header className="mb-4 flex items-center gap-3">
            <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950">
              <Wifi className="h-5 w-5" />
            </div>
            <div>
              <h2
                id="bc-pair-title"
                className="text-lg font-semibold text-surface-900 dark:text-surface-100"
              >
                Pair terminal
              </h2>
              <p className="text-xs text-surface-500 dark:text-surface-400">
                {credsComplete
                  ? 'Give the terminal a name and enter its LAN IP.'
                  : 'Fill in BlockChyp credentials above to enable pairing.'}
              </p>
            </div>
          </header>

          <fieldset disabled={!credsComplete} className="space-y-4">
            <div>
              <label
                htmlFor="blockchyp-terminal-name"
                className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
              >
                Terminal name
              </label>
              <input
                id="blockchyp-terminal-name"
                type="text"
                value={terminalName}
                onChange={(e) => handleNameChange(e.target.value)}
                placeholder="Front counter"
                autoComplete="off"
                className="block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 disabled:cursor-not-allowed disabled:bg-surface-50 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500 dark:disabled:bg-surface-800"
              />
            </div>

            <div>
              <label
                htmlFor="blockchyp-terminal-ip"
                className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300"
              >
                Terminal IP
              </label>
              <input
                id="blockchyp-terminal-ip"
                type="text"
                inputMode="numeric"
                value={terminalIp}
                onChange={(e) => handleIpChange(e.target.value)}
                placeholder="192.168.1.42"
                autoComplete="off"
                aria-invalid={!ipValid || undefined}
                className={
                  !ipValid
                    ? 'block w-full rounded-lg border border-red-400 bg-white px-3 py-2 text-sm text-surface-900 shadow-sm focus:border-red-500 focus:outline-none focus:ring-2 focus:ring-red-500/20 dark:bg-surface-900 dark:text-surface-100'
                    : 'block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 disabled:cursor-not-allowed disabled:bg-surface-50 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500 dark:disabled:bg-surface-800'
                }
              />
              {!ipValid ? (
                <p className="mt-1 text-[11px] text-red-500">
                  Use a basic IPv4 address like 192.168.1.42.
                </p>
              ) : (
                <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
                  LAN address printed on the BlockChyp terminal.
                </p>
              )}
            </div>

            <div className="flex items-center gap-3 pt-1">
              <button
                type="button"
                onClick={handleTestConnection}
                disabled={
                  !credsComplete ||
                  testStatus === 'checking' ||
                  terminalIp.trim().length === 0 ||
                  !ipValid
                }
                className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-60 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
              >
                {testStatus === 'checking' ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : testStatus === 'ok' ? (
                  <CheckCircle2 className="h-4 w-4 text-green-600" />
                ) : testStatus === 'fail' ? (
                  <XCircle className="h-4 w-4 text-red-500" />
                ) : (
                  <Wifi className="h-4 w-4" />
                )}
                Test connection
              </button>
              {testStatus === 'unverified' ? (
                <span className="text-xs font-medium text-surface-500 dark:text-surface-400">
                  Stub &mdash; real heartbeat lands with BlockChyp service.
                </span>
              ) : testStatus === 'ok' ? (
                <span className="text-xs font-medium text-green-700 dark:text-green-400">
                  Connected
                </span>
              ) : testStatus === 'fail' ? (
                <span className="text-xs font-medium text-red-600 dark:text-red-400">
                  Unreachable
                </span>
              ) : null}
            </div>
          </fieldset>
        </section>

        {/* ── Footer — Back / Skip / Continue ────────────────────── */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
              title="Set up later from Settings &rarr; Payments."
            >
              Skip
            </button>
            <button
              type="button"
              onClick={onNext}
              disabled={!ipValid}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
            >
              Continue
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepPaymentTerminal;
