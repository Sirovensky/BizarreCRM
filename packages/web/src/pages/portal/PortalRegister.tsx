import { useEffect, useRef, useState } from 'react';
import * as api from './portalApi';

type CaptchaProvider = api.PortalCaptchaProvider;

interface CaptchaRenderOptions {
  sitekey: string;
  callback: (token: string) => void;
  'expired-callback': () => void;
  'error-callback': () => void;
}

interface CaptchaWidgetApi {
  render: (container: HTMLElement, options: CaptchaRenderOptions) => string | number;
  reset: (widgetId?: string | number) => void;
  remove?: (widgetId: string | number) => void;
}

declare global {
  interface Window {
    turnstile?: CaptchaWidgetApi;
    grecaptcha?: CaptchaWidgetApi;
  }
}

const CAPTCHA_SCRIPTS: Record<CaptchaProvider, string> = {
  hcaptcha: 'https://js.hcaptcha.com/1/api.js?render=explicit',
  turnstile: 'https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit',
  recaptcha: 'https://www.google.com/recaptcha/api.js?render=explicit',
};

const CAPTCHA_SCRIPT_PREFIXES: Record<CaptchaProvider, string> = {
  hcaptcha: 'https://js.hcaptcha.com/1/api.js',
  turnstile: 'https://challenges.cloudflare.com/turnstile/v0/api.js',
  recaptcha: 'https://www.google.com/recaptcha/api.js',
};

function getCaptchaApi(provider: CaptchaProvider): CaptchaWidgetApi | undefined {
  if (provider === 'hcaptcha') return window.hcaptcha;
  if (provider === 'turnstile') return window.turnstile;
  return window.grecaptcha;
}

function mapRegisterError(err: unknown): string {
  const response = (err as { response?: { status?: number; data?: { message?: string } } })?.response;
  const status = response?.status;
  const message = response?.data?.message;
  if (status === 400) return 'Invalid information — please check your inputs';
  if (status === 401) return 'Registration failed — please try again';
  if (status === 403) return message || 'Please complete the verification check';
  if (status === 409) return 'Account already exists — try signing in';
  if (status === 429) return 'Too many attempts — please wait a moment';
  if (status !== undefined && status >= 500) return 'Server error — please try again later';
  return 'Something went wrong';
}

interface PortalRegisterProps {
  onRegistered: (token: string, customerName: string) => void;
  onBack: () => void;
}

type Step = 'phone' | 'code' | 'pin';

export function PortalRegister({ onRegistered, onBack }: PortalRegisterProps) {
  const [step, setStep] = useState<Step>('phone');
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [pin, setPin] = useState('');
  const [pinConfirm, setPinConfirm] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [captchaConfig, setCaptchaConfig] = useState<api.RegisterCaptchaConfig>({ enabled: false });
  const [captchaReady, setCaptchaReady] = useState(true);
  const [captchaToken, setCaptchaToken] = useState('');
  const [captchaError, setCaptchaError] = useState('');
  const captchaContainerRef = useRef<HTMLDivElement | null>(null);
  const captchaWidgetIdRef = useRef<string | number | null>(null);

  useEffect(() => {
    let cancelled = false;
    api.getRegisterCaptchaConfig()
      .then(config => {
        if (cancelled) return;
        setCaptchaConfig(config);
        setCaptchaReady(!config.enabled);
      })
      .catch(() => {
        if (cancelled) return;
        setCaptchaConfig({ enabled: false });
        setCaptchaReady(true);
      });
    return () => { cancelled = true; };
  }, []);

  useEffect(() => {
    if (!captchaConfig.enabled || !captchaConfig.provider || !captchaConfig.site_key) {
      setCaptchaReady(true);
      return;
    }

    let cancelled = false;
    const provider = captchaConfig.provider;
    const siteKey = captchaConfig.site_key;

    function renderWidget() {
      const container = captchaContainerRef.current;
      const widget = getCaptchaApi(provider);
      if (cancelled || !container || !widget || captchaWidgetIdRef.current !== null) return;

      try {
        captchaWidgetIdRef.current = widget.render(container, {
          sitekey: siteKey,
          callback: (token: string) => {
            setCaptchaToken(token);
            setCaptchaError('');
            setError('');
          },
          'expired-callback': () => setCaptchaToken(''),
          'error-callback': () => {
            setCaptchaToken('');
            setCaptchaError('Verification check failed. Please try again.');
          },
        });
        setCaptchaReady(true);
      } catch {
        setCaptchaReady(false);
        setCaptchaError('Could not load the verification check. Please refresh and try again.');
      }
    }

    setCaptchaReady(false);
    setCaptchaToken('');
    setCaptchaError('');
    captchaWidgetIdRef.current = null;
    let pollTimer: ReturnType<typeof setInterval> | null = null;
    let pollTimeout: ReturnType<typeof setTimeout> | null = null;
    if (getCaptchaApi(provider)) {
      renderWidget();
    } else {
      const existingScript = document.querySelector<HTMLScriptElement>(
        `script[src^="${CAPTCHA_SCRIPT_PREFIXES[provider]}"]`,
      );
      const script = existingScript ?? document.createElement('script');
      const onLoad = () => renderWidget();
      const onError = () => {
        if (cancelled) return;
        setCaptchaReady(false);
        setCaptchaError('Could not load the verification check. Please refresh and try again.');
      };

      script.addEventListener('load', onLoad, { once: true });
      script.addEventListener('error', onError, { once: true });
      if (!existingScript) {
        // Listener MUST be wired before src triggers the network request so
        // synchronous cache hits still fire `load`. (BUGHUNT-2026-05-10-29
        // earlier reading.)
        script.src = CAPTCHA_SCRIPTS[provider];
        script.async = true;
        script.defer = true;
        document.head.appendChild(script);
      } else {
        // BUGHUNT-2026-05-10-29: an existing <script> tag may have already
        // fired its `load` event before this effect attached its listener
        // (another component on the same page mounted earlier). `once: true`
        // never re-fires, so we'd sit forever waiting. Poll the global API
        // until it appears, with a 10s ceiling that flips to the error
        // surface so the user sees a deterministic failure instead of an
        // empty widget area.
        pollTimer = setInterval(() => {
          if (cancelled) return;
          if (getCaptchaApi(provider)) {
            if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
            if (pollTimeout) { clearTimeout(pollTimeout); pollTimeout = null; }
            renderWidget();
          }
        }, 200);
        pollTimeout = setTimeout(() => {
          if (cancelled) return;
          if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
          if (!getCaptchaApi(provider)) {
            setCaptchaReady(false);
            setCaptchaError('Verification check failed to load. Please refresh and try again.');
          }
        }, 10_000);
      }
    }

    return () => {
      cancelled = true;
      if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }
      if (pollTimeout) { clearTimeout(pollTimeout); pollTimeout = null; }
      const widget = getCaptchaApi(provider);
      if (captchaWidgetIdRef.current !== null && widget?.remove) {
        widget.remove(captchaWidgetIdRef.current);
      }
      if (captchaContainerRef.current) {
        captchaContainerRef.current.innerHTML = '';
      }
      captchaWidgetIdRef.current = null;
    };
  }, [captchaConfig.enabled, captchaConfig.provider, captchaConfig.site_key]);

  function resetCaptcha() {
    if (!captchaConfig.enabled || !captchaConfig.provider) return;
    setCaptchaToken('');
    const widget = getCaptchaApi(captchaConfig.provider);
    if (widget && captchaWidgetIdRef.current !== null) {
      widget.reset(captchaWidgetIdRef.current);
    }
  }

  async function handleSendCode(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (phone.replace(/\D/g, '').length < 10) {
      setError('Please enter a valid phone number');
      return;
    }
    if (captchaConfig.enabled && !captchaToken) {
      setError('Please complete the verification check');
      return;
    }
    setLoading(true);
    try {
      await api.sendVerificationCode(phone.trim(), captchaConfig.enabled ? captchaToken : undefined);
      setStep('code');
    } catch (err: unknown) {
      setError(mapRegisterError(err));
      resetCaptcha();
    } finally {
      setLoading(false);
    }
  }

  function handleCodeComplete(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (code.length !== 6) {
      setError('Please enter the 6-digit code from your SMS');
      return;
    }
    setStep('pin');
  }

  async function handleSetPin(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (pin.length !== 4) {
      setError('PIN must be exactly 4 digits');
      return;
    }
    if (pin !== pinConfirm) {
      setError('PINs do not match');
      return;
    }
    setLoading(true);
    try {
      const result = await api.verifyAndRegister(phone.trim(), code, pin);
      onRegistered(result.token, result.customer.first_name);
    } catch (err: unknown) {
      setError(mapRegisterError(err));
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className="flex flex-col items-center min-h-screen bg-surface-50 dark:bg-surface-900 px-4 py-8">
      <div className="w-full max-w-md">
        <button onClick={onBack} className="mb-4 text-sm text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-200 flex items-center gap-1">
          <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          Back to login
        </button>

        <div className="rounded-xl bg-white dark:bg-surface-800 shadow-sm border border-surface-200 dark:border-surface-700 p-6">
          <h1 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-1">Create Account</h1>
          <p className="text-sm text-surface-500 dark:text-surface-400 mb-5">
            {step === 'phone' && 'Enter the phone number on file for your repairs.'}
            {step === 'code' && 'Enter the 6-digit code we just sent to your phone.'}
            {step === 'pin' && 'Choose a 4-digit PIN for future sign-ins.'}
          </p>

          {/* Progress indicator */}
          <div className="flex items-center gap-2 mb-6">
            {(['phone', 'code', 'pin'] as Step[]).map((s, i) => (
              <div key={s} className="flex items-center gap-2">
                <div className={`w-7 h-7 rounded-full flex items-center justify-center text-xs font-medium ${
                  step === s ? 'bg-primary-600 text-on-primary' :
                  (['phone', 'code', 'pin'].indexOf(step) > i) ? 'bg-green-500 text-white' :
                  'bg-surface-200 dark:bg-surface-700 text-surface-500 dark:text-surface-400'
                }`}>
                  {(['phone', 'code', 'pin'].indexOf(step) > i) ? (
                    <svg className="w-4 h-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={3}>
                      <path strokeLinecap="round" strokeLinejoin="round" d="M5 13l4 4L19 7" />
                    </svg>
                  ) : i + 1}
                </div>
                {i < 2 && <div className={`w-8 h-0.5 ${(['phone', 'code', 'pin'].indexOf(step) > i) ? 'bg-green-500' : 'bg-surface-200 dark:bg-surface-700'}`} />}
              </div>
            ))}
          </div>

          {error && (
            <div role="alert" aria-live="polite" className="mb-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-4 py-3 text-sm text-red-700 dark:text-red-300">
              {error}
            </div>
          )}

          {step === 'phone' && (
            <form onSubmit={handleSendCode} className="space-y-4">
              <div>
                <label htmlFor="reg-phone" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Phone Number</label>
                <input
                  id="reg-phone"
                  type="tel"
                  inputMode="tel"
                  autoFocus
                  placeholder="(303) 555-1234"
                  value={phone}
                  onChange={e => setPhone(e.target.value)}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                  autoComplete="tel"
                />
              </div>
              {captchaConfig.enabled && (
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Verification</label>
                  <div ref={captchaContainerRef} style={{ minHeight: 78 }} />
                  {!captchaReady && !captchaError && (
                    <p className="mt-2 text-xs text-surface-500 dark:text-surface-400">Loading verification...</p>
                  )}
                  {captchaError && (
                    <p role="alert" className="mt-2 text-xs text-red-600 dark:text-red-300">{captchaError}</p>
                  )}
                </div>
              )}
              <button
                type="submit"
                disabled={loading || (captchaConfig.enabled && !captchaReady)}
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
              >
                {loading ? 'Sending...' : 'Send Verification Code'}
              </button>
            </form>
          )}

          {step === 'code' && (
            <form onSubmit={handleCodeComplete} className="space-y-4">
              <div>
                <label htmlFor="reg-code" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Verification Code</label>
                <input
                  id="reg-code"
                  type="text"
                  inputMode="numeric"
                  placeholder="000000"
                  maxLength={6}
                  value={code}
                  onChange={e => setCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 tracking-[0.5em] text-center font-mono focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                  autoComplete="one-time-code"
                  autoFocus
                />
              </div>
              <button
                type="submit"
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-on-primary hover:bg-primary-700 transition-colors"
              >
                Verify Code
              </button>
              <button
                type="button"
                onClick={() => { setStep('phone'); setCode(''); setError(''); }}
                className="w-full text-sm text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-200"
              >
                Didn't receive it? Go back
              </button>
            </form>
          )}

          {step === 'pin' && (
            <form onSubmit={handleSetPin} className="space-y-4">
              <div>
                <label htmlFor="reg-pin" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Choose a 4-Digit PIN</label>
                <input
                  id="reg-pin"
                  type="password"
                  inputMode="numeric"
                  placeholder="****"
                  maxLength={4}
                  value={pin}
                  onChange={e => setPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 tracking-widest text-center focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                  autoComplete="new-password"
                  autoFocus
                />
              </div>
              <div>
                <label htmlFor="reg-pin-confirm" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Confirm PIN</label>
                <input
                  id="reg-pin-confirm"
                  type="password"
                  inputMode="numeric"
                  placeholder="****"
                  maxLength={4}
                  value={pinConfirm}
                  onChange={e => setPinConfirm(e.target.value.replace(/\D/g, '').slice(0, 4))}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 tracking-widest text-center focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                  autoComplete="new-password"
                />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
              >
                {loading ? 'Creating account...' : 'Create Account'}
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
