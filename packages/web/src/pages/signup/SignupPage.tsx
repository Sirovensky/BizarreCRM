import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import type { FormEvent, ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { ArrowRight, CheckCircle2, Eye, EyeOff, Loader2, MailCheck, ShieldCheck, Store, XCircle } from 'lucide-react';
import { Button } from '../../components/shared/Button';
import { FormError } from '../../components/shared/FormError';
import { signupApi } from '../../api/endpoints';
import { redactEmails } from '../../utils/apiError';
import { cn } from '../../utils/cn';
import {
  assessSignupPassword,
  checkPwnedPassword,
  type PasswordStrengthAssessment,
} from '../../utils/passwordSecurity';

const HCAPTCHA_SCRIPT_SRC = 'https://js.hcaptcha.com/1/api.js?render=explicit';

declare global {
  interface Window {
    hcaptcha?: {
      render: (
        container: HTMLElement,
        options: {
          sitekey: string;
          callback: (token: string) => void;
          'expired-callback': () => void;
          'error-callback': () => void;
        },
      ) => string | number;
      reset: (widgetId?: string | number) => void;
    };
  }
}

/* ═══════════════════════════════════════════════════════════════
   Self-service signup page for new repair shops.
   Creates a pending shop via POST /api/v1/signup/, then waits for
   the admin to verify the email before provisioning the tenant.
   ═══════════════════════════════════════════════════════════════ */

// WEB-FG-002 / FIXED-by-Fixer-U 2026-04-25 — allow-list trusted base domains.
// Previously this helper trusted whatever hostname the browser landed on, so
// a phishing landing on `bizarrecrm.evil-co.com` could redirect customers to
// `slug.evil-co.com/login`. Anything off the allow-list falls back to the
// canonical apex so we never craft a link to an attacker-controlled subdomain.
const TRUSTED_BASE_DOMAINS = ['bizarrecrm.com', 'localhost'] as const;

function resolveBaseDomain(hostname: string): string | null {
  if (hostname === 'localhost' || hostname.endsWith('.localhost')) return 'localhost';
  for (const allowed of TRUSTED_BASE_DOMAINS) {
    if (hostname === allowed || hostname.endsWith(`.${allowed}`)) return allowed;
  }
  return null;
}

// Build the tenant URL from a slug
function getTenantUrl(slug: string, path = '/'): string {
  const { protocol, port, hostname } = window.location;
  const portSuffix = port && port !== '443' && port !== '80' ? `:${port}` : '';
  const baseDomain = resolveBaseDomain(hostname) ?? 'bizarrecrm.com';
  return `${protocol}//${slug}.${baseDomain}${portSuffix}${path}`;
}

interface FieldErrors {
  slug?: string;
  shop_name?: string;
  admin_email?: string;
  admin_password?: string;
  confirm_password?: string;
  captcha?: string;
}

type PasswordBreachCheck =
  | { status: 'idle'; password?: string }
  | { status: 'checking'; password: string }
  | { status: 'safe'; password: string }
  | { status: 'breached'; password: string; count: number }
  | { status: 'error'; password: string; message: string };

export function SignupPage() {
  const [slug, setSlug] = useState('');
  const [shopName, setShopName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [passwordBreachCheck, setPasswordBreachCheck] = useState<PasswordBreachCheck>({ status: 'idle' });

  const [slugStatus, setSlugStatus] = useState<'idle' | 'checking' | 'available' | 'taken' | 'invalid'>('idle');
  const [slugMessage, setSlugMessage] = useState('');
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [apiError, setApiError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<{
    slug: string;
    message: string;
    adminEmail: string;
    /** True when the server provisioned the tenant immediately (dev-mode short-circuit). */
    provisioned?: boolean;
    /** Subdomain URL of the new shop, e.g. https://slug.bizarrecrm.com — present when provisioned. */
    tenantUrl?: string;
  } | null>(null);
  const captchaSiteKey = (import.meta.env.VITE_HCAPTCHA_SITE_KEY || '').trim();
  const [captchaToken, setCaptchaToken] = useState('');
  const [captchaReady, setCaptchaReady] = useState(!captchaSiteKey);
  const [captchaError, setCaptchaError] = useState('');

  const slugTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const captchaContainerRef = useRef<HTMLDivElement | null>(null);
  const captchaWidgetIdRef = useRef<string | number | null>(null);
  const passwordCheckTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const passwordCheckAbortRef = useRef<AbortController | null>(null);
  const latestPasswordRef = useRef('');

  const passwordStrength = useMemo(
    () => assessSignupPassword(password, { email, shopName, slug }),
    [email, password, shopName, slug],
  );
  const activePasswordBreachCheck: PasswordBreachCheck = passwordBreachCheck.password === password
    ? passwordBreachCheck
    : { status: 'idle', password };

  // Auto-generate slug from shop name
  const handleShopNameChange = (name: string) => {
    setShopName(name);
    // Only auto-fill slug if user hasn't manually edited it
    if (!slug || slug === slugify(shopName)) {
      setSlug(slugify(name));
    }
  };

  // WEB-FA-016 (Fixer-KKK 2026-04-25): track the most-recently-requested slug
  // so out-of-order responses (server slow on "abc", fast on "abcd") don't
  // overwrite the visible status with a stale "available"/"taken" verdict
  // for an old value. Public checkSlug endpoint has no abort surface yet,
  // so we ignore stale resolves at the consumer side.
  const latestSlugRef = useRef<string>('');

  // Debounced slug availability check
  const checkSlug = useCallback((value: string) => {
    if (slugTimerRef.current) clearTimeout(slugTimerRef.current);
    latestSlugRef.current = value;

    if (!value || value.length < 3) {
      setSlugStatus(value ? 'invalid' : 'idle');
      setSlugMessage(value ? 'At least 3 characters' : '');
      return;
    }
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(value)) {
      setSlugStatus('invalid');
      setSlugMessage('Only lowercase letters, numbers, and hyphens');
      return;
    }

    setSlugStatus('checking');
    setSlugMessage('');

    slugTimerRef.current = setTimeout(async () => {
      try {
        const res = await signupApi.checkSlug(value);
        // Drop stale results: user has typed further since this fired.
        if (latestSlugRef.current !== value) return;
        const { available, reason } = res.data.data;
        setSlugStatus(available ? 'available' : 'taken');
        setSlugMessage(available ? 'Available!' : (reason || 'Already taken'));
      } catch {
        if (latestSlugRef.current !== value) return;
        setSlugStatus('idle');
        setSlugMessage('Could not check availability');
      }
    }, 400);
  }, []);

  useEffect(() => {
    checkSlug(slug);
    return () => { if (slugTimerRef.current) clearTimeout(slugTimerRef.current); };
  }, [slug, checkSlug]);

  useEffect(() => {
    if (!captchaSiteKey) {
      setCaptchaReady(true);
      return;
    }

    let cancelled = false;
    const renderCaptcha = () => {
      if (cancelled || !captchaContainerRef.current || !window.hcaptcha || captchaWidgetIdRef.current !== null) {
        return;
      }

      try {
        captchaWidgetIdRef.current = window.hcaptcha.render(captchaContainerRef.current, {
          sitekey: captchaSiteKey,
          callback: (token: string) => {
            setCaptchaToken(token);
            setCaptchaError('');
            setFieldErrors(prev => ({ ...prev, captcha: undefined }));
          },
          'expired-callback': () => {
            setCaptchaToken('');
            setCaptchaError('Verification expired. Please complete it again.');
          },
          'error-callback': () => {
            setCaptchaToken('');
            setCaptchaError('Verification failed to load. Please refresh and try again.');
          },
        });
        setCaptchaReady(true);
      } catch {
        setCaptchaReady(false);
        setCaptchaError('Verification failed to load. Please refresh and try again.');
      }
    };

    if (window.hcaptcha) {
      renderCaptcha();
      return () => { cancelled = true; };
    }

    const existingScript = document.querySelector<HTMLScriptElement>('script[src^="https://js.hcaptcha.com/1/api.js"]');
    const script = existingScript || document.createElement('script');
    const handleLoad = () => renderCaptcha();
    const handleError = () => {
      if (!cancelled) {
        setCaptchaReady(false);
        setCaptchaError('Verification failed to load. Please refresh and try again.');
      }
    };

    script.addEventListener('load', handleLoad);
    script.addEventListener('error', handleError);
    if (!existingScript) {
      script.src = HCAPTCHA_SCRIPT_SRC;
      script.async = true;
      script.defer = true;
      // WEB-FA-010: forward the page's CSP nonce (set by the server in a
      // <meta name="csp-nonce" content="..."> tag, mirroring the React 19
      // pattern) so this dynamically appended <script> survives a strict
      // `script-src 'nonce-…'` policy. Falls through silently when no
      // nonce meta is present (dev / non-CSP deployments).
      const nonce = document
        .querySelector<HTMLMetaElement>('meta[name="csp-nonce"]')
        ?.content;
      if (nonce) script.setAttribute('nonce', nonce);
      document.head.appendChild(script);
    }

    return () => {
      cancelled = true;
      script.removeEventListener('load', handleLoad);
      script.removeEventListener('error', handleError);
    };
  }, [captchaSiteKey]);

  useEffect(() => {
    latestPasswordRef.current = password;
    if (passwordCheckTimerRef.current) clearTimeout(passwordCheckTimerRef.current);
    passwordCheckAbortRef.current?.abort();

    if (!password || password.length < 8 || !passwordStrength.isAcceptable) {
      setPasswordBreachCheck({ status: 'idle', password });
      return () => {
        if (passwordCheckTimerRef.current) clearTimeout(passwordCheckTimerRef.current);
      };
    }

    setPasswordBreachCheck(prev => (
      prev.password === password && (prev.status === 'safe' || prev.status === 'breached')
        ? prev
        : { status: 'idle', password }
    ));

    passwordCheckTimerRef.current = setTimeout(() => {
      const controller = new AbortController();
      passwordCheckAbortRef.current = controller;
      setPasswordBreachCheck({ status: 'checking', password });

      checkPwnedPassword(password, controller.signal)
        .then(result => {
          if (controller.signal.aborted || latestPasswordRef.current !== password) return;
          setPasswordBreachCheck(result.compromised
            ? { status: 'breached', password, count: result.count }
            : { status: 'safe', password });
          if (!result.compromised) {
            setFieldErrors(prev => {
              const current = prev.admin_password ?? '';
              if (!current.startsWith('Finish checking') && !current.startsWith('Password breach check')) {
                return prev;
              }
              return { ...prev, admin_password: undefined };
            });
          }
        })
        .catch(error => {
          if (controller.signal.aborted || latestPasswordRef.current !== password) return;
          const message = error instanceof Error && error.message
            ? error.message
            : 'Password breach check is unavailable.';
          setPasswordBreachCheck({ status: 'error', password, message });
        });
    }, 450);

    return () => {
      if (passwordCheckTimerRef.current) clearTimeout(passwordCheckTimerRef.current);
      passwordCheckAbortRef.current?.abort();
    };
  }, [password, passwordStrength.isAcceptable]);

  const validate = (): boolean => {
    const errors: FieldErrors = {};
    if (!slug || slug.length < 3) errors.slug = 'Shop URL is required (min 3 characters)';
    if (slugStatus === 'taken') errors.slug = 'This name is already taken';
    if (slugStatus === 'invalid') errors.slug = 'Invalid format';
    if (!shopName.trim() || shopName.trim().length < 2) errors.shop_name = 'Shop name is required';
    if (!email.trim() || !/\S+@\S+\.\S+/.test(email)) errors.admin_email = 'Valid email is required';
    if (!password || password.length < 8) {
      errors.admin_password = 'Password must be at least 8 characters';
    } else if (!passwordStrength.isAcceptable) {
      errors.admin_password = passwordStrength.suggestions[0] || 'Choose a stronger password';
    } else if (activePasswordBreachCheck.status === 'breached') {
      errors.admin_password = `Choose a different password. This one appears in ${formatBreachCount(activePasswordBreachCheck.count)}.`;
    } else if (activePasswordBreachCheck.status === 'checking') {
      errors.admin_password = 'Finish checking this password against breach data before creating the shop.';
    } else if (activePasswordBreachCheck.status === 'error') {
      errors.admin_password = `${activePasswordBreachCheck.message} Try again before creating the shop.`;
    } else if (activePasswordBreachCheck.status !== 'safe') {
      errors.admin_password = 'Password breach check has not completed yet.';
    }
    if (password !== confirmPassword) errors.confirm_password = 'Passwords do not match';
    if (captchaSiteKey && !captchaToken) errors.captcha = 'Please complete the verification check';
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSubmit = async (e: FormEvent<HTMLFormElement>) => {
    e.preventDefault();
    setApiError('');
    if (!validate()) return;

    setSubmitting(true);
    try {
      // Gate the dev-captcha fallback strictly on Vite's DEV flag so production
      // builds never ship a token the backend test-mode would accept. When no
      // site key is configured in production, send an empty string and let the
      // backend reject the request — failing closed is safer than failing open.
      const captchaTokenToSend = captchaSiteKey
        ? captchaToken
        : import.meta.env.DEV
          ? 'dev-captcha-token'
          : '';
      const res = await signupApi.createShop({
        slug: slug.toLowerCase().trim(),
        shop_name: shopName.trim(),
        admin_email: email.trim(),
        admin_password: password,
        captcha_token: captchaTokenToSend,
      });
      const data = res.data.data as {
        message: string;
        tenant_id?: number;
        url?: string;
        accessToken?: string;
      };
      // Detect dev-mode auto-provision (server returns tenant_id + url + accessToken).
      // In that case the shop is ALREADY live; we should not tell the user to
      // check their email. Show a "ready" screen with the deep-link instead.
      const provisioned = Boolean(data.tenant_id && data.url);
      setSuccess({
        slug: slug.toLowerCase().trim(),
        message: data.message,
        adminEmail: email.trim(),
        provisioned,
        tenantUrl: data.url,
      });
      // Redirect after brief success message is no longer performed automatically,
      // as the user needs to check their email for the token URL.
    } catch (err: unknown) {
      const apiErr = err as { response?: { data?: { message?: string; error?: string } } } | undefined;
      const msg = apiErr?.response?.data?.message
        || apiErr?.response?.data?.error
        || (err instanceof Error ? err.message : '')
        || 'Something went wrong. Please try again.';
      // WEB-FJ-019: signup is an unauthenticated public surface; redact any
      // email-shaped substring the server echoed back (e.g. "An account
      // already exists for x@y.com") so a screenshot or shoulder-surf can't
      // exfiltrate it.
      setApiError(redactEmails(msg));
      if (captchaWidgetIdRef.current !== null) {
        window.hcaptcha?.reset(captchaWidgetIdRef.current);
        setCaptchaToken('');
      }
    } finally {
      setSubmitting(false);
    }
  };

  // Success state
  if (success) {
    // Two distinct shapes:
    //   provisioned=true  → shop is already live (dev-mode short-circuit); show
    //                       "Open your shop" CTA pointing at the subdomain URL
    //                       returned by the server. NO "check your email" copy
    //                       because there is no email to wait for.
    //   provisioned=false → production path; verification email pending; user
    //                       must click the link to finish provisioning.
    const fallbackUrl = success.tenantUrl || getTenantUrl(success.slug, '/login?fresh=1');
    const successMessage = success.provisioned
      ? getProvisionedSuccessMessage(success, fallbackUrl)
      : (success.message || `We've sent a confirmation link to help finish creating your shop at ${success.slug}.`);
    const SuccessIcon = success.provisioned ? CheckCircle2 : MailCheck;

    return (
      <main className="flex min-h-screen items-center justify-center bg-surface-50 px-4 py-10 font-sans text-surface-900 dark:bg-surface-950 dark:text-surface-100 sm:px-6">
        <section className="w-full max-w-md rounded-lg border border-surface-200 bg-white p-8 text-center shadow-xl shadow-surface-900/10 dark:border-surface-700 dark:bg-surface-900 dark:shadow-black/30">
          <div className="mx-auto mb-5 flex h-14 w-14 items-center justify-center rounded-full bg-cyan-50 text-cyan-700 dark:bg-cyan-400/10 dark:text-cyan-300">
            <SuccessIcon className="h-7 w-7" aria-hidden="true" />
          </div>
          <h2 className="font-display text-4xl font-semibold text-cyan-800 dark:text-cyan-200">
            {success.provisioned ? 'Shop ready!' : 'Check Your Email'}
          </h2>
          <p className="mt-3 text-base leading-7 text-surface-600 dark:text-surface-300">
            {successMessage}
          </p>

          {success.provisioned && (
            <a
              href={fallbackUrl}
              className="mt-6 inline-flex h-12 items-center justify-center gap-2 rounded-lg bg-surface-900 px-5 text-sm font-semibold text-primary-100 transition-colors hover:bg-surface-800 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-600 focus-visible:ring-offset-2 focus-visible:ring-offset-white dark:bg-primary-500 dark:text-on-primary dark:hover:bg-primary-400 dark:focus-visible:ring-primary-400 dark:focus-visible:ring-offset-surface-900"
            >
              Open your shop
              <ArrowRight className="h-4 w-4" aria-hidden="true" />
            </a>
          )}

          <div className={cn('text-sm text-surface-500 dark:text-surface-400', success.provisioned ? 'mt-4' : 'mt-6')}>
            <Link to="/" className="font-semibold text-cyan-800 underline-offset-4 hover:underline dark:text-cyan-300">
              Return to home
            </Link>
          </div>
        </section>
      </main>
    );
  }

  const passwordAriaDescribedBy = [
    fieldErrors.admin_password ? 'signup-password-error' : undefined,
    password ? 'signup-password-security' : undefined,
  ].filter(Boolean).join(' ') || undefined;
  const passwordCheckPending = password.length >= 8
    && passwordStrength.isAcceptable
    && activePasswordBreachCheck.status === 'checking';
  const submitDisabled = submitting || slugStatus === 'checking' || passwordCheckPending || (Boolean(captchaSiteKey) && !captchaReady);
  const signupHost = resolveBaseDomain(window.location.hostname) ?? 'bizarrecrm.com';

  return (
    <main className="min-h-screen bg-surface-50 font-sans text-surface-900 dark:bg-surface-950 dark:text-surface-100">
      <div className="mx-auto flex min-h-screen w-full max-w-6xl items-center px-4 py-10 sm:px-6 lg:px-8">
        <div className="grid w-full gap-8 lg:grid-cols-[minmax(0,1fr)_minmax(400px,460px)] lg:items-center">
          <section className="hidden lg:block">
            <Link to="/" className="inline-flex font-logo text-3xl text-pink-700 transition-colors hover:text-pink-800 dark:text-pink-300 dark:hover:text-pink-200">
              BIZARRECRM
            </Link>
            <h1 className="mt-6 max-w-xl font-display text-5xl font-semibold leading-tight text-cyan-800 dark:text-cyan-200">
              Create your repair shop workspace.
            </h1>
            <p className="mt-4 max-w-lg text-base leading-7 text-surface-600 dark:text-surface-300">
              Free to start. No credit card required. Your shop gets a dedicated URL after email verification.
            </p>

            <div className="mt-8 grid max-w-lg gap-4">
              <div className="flex items-start gap-3">
                <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-200 text-on-primary dark:bg-primary-500/20 dark:text-primary-300">
                  <Store className="h-5 w-5" aria-hidden="true" />
                </span>
                <div>
                  <p className="font-semibold text-surface-900 dark:text-surface-100">Dedicated tenant setup</p>
                  <p className="mt-1 text-sm leading-6 text-surface-600 dark:text-surface-400">
                    Your URL, owner account, and first-run setup stay scoped to your shop.
                  </p>
                </div>
              </div>
              <div className="flex items-start gap-3">
                <span className="mt-0.5 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-cyan-50 text-cyan-700 dark:bg-cyan-400/10 dark:text-cyan-300">
                  <ShieldCheck className="h-5 w-5" aria-hidden="true" />
                </span>
                <div>
                  <p className="font-semibold text-surface-900 dark:text-surface-100">Protected signup checks</p>
                  <p className="mt-1 text-sm leading-6 text-surface-600 dark:text-surface-400">
                    Slug availability, CAPTCHA, and password safety checks run before the shop is created.
                  </p>
                </div>
              </div>
            </div>
          </section>

          <div className="w-full">
            <div className="mb-6 text-center lg:hidden">
              <Link to="/" className="inline-flex font-logo text-3xl text-pink-700 transition-colors hover:text-pink-800 dark:text-pink-300 dark:hover:text-pink-200">
                BIZARRECRM
              </Link>
              <h1 className="mt-4 font-display text-4xl font-semibold text-cyan-800 dark:text-cyan-200">
                Create Your Shop
              </h1>
              <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">Free to start. No credit card required.</p>
            </div>

            <form
              onSubmit={handleSubmit}
              noValidate
              aria-busy={submitting}
              className="rounded-lg border border-surface-200 bg-white p-6 shadow-xl shadow-surface-900/10 dark:border-surface-700 dark:bg-surface-900 dark:shadow-black/30 sm:p-8"
            >
              <div className="mb-6 hidden text-center lg:block">
                <h2 className="font-display text-4xl font-semibold text-cyan-800 dark:text-cyan-200">
                  Create Your Shop
                </h2>
                <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
                  Free to start. No credit card required.
                </p>
              </div>

              <FormError message={apiError} variant="banner" className="mb-5" />

              <FieldGroup htmlFor="signup-shop-name" label="Shop Name" error={fieldErrors.shop_name} errorId="signup-shop-name-error">
                <input
                  id="signup-shop-name"
                  type="text"
                  value={shopName}
                  onChange={e => {
                    handleShopNameChange(e.target.value);
                    setFieldErrors(p => ({ ...p, shop_name: undefined }));
                  }}
                  placeholder="My Repair Shop"
                  maxLength={100}
                  autoComplete="organization"
                  autoFocus
                  aria-invalid={!!fieldErrors.shop_name}
                  aria-describedby={fieldErrors.shop_name ? 'signup-shop-name-error' : undefined}
                  className={inputClass(!!fieldErrors.shop_name)}
                />
              </FieldGroup>

              <FieldGroup htmlFor="signup-slug" label="Shop URL" error={fieldErrors.slug} errorId="signup-slug-error">
                <div className="flex min-w-0">
                  <input
                    id="signup-slug"
                    type="text"
                    value={slug}
                    onChange={e => {
                      setSlug(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ''));
                      setFieldErrors(p => ({ ...p, slug: undefined }));
                    }}
                    placeholder="your-shop"
                    maxLength={30}
                    autoCapitalize="none"
                    autoCorrect="off"
                    spellCheck={false}
                    aria-invalid={!!fieldErrors.slug}
                    aria-describedby={
                      fieldErrors.slug
                        ? 'signup-slug-error'
                        : slugStatus !== 'idle'
                          ? 'signup-slug-status'
                          : undefined
                    }
                    className={inputClass(!!fieldErrors.slug, 'min-w-0 rounded-r-none border-r-0')}
                  />
                  <span className={slugHostClass(!!fieldErrors.slug)}>
                    .{signupHost}
                  </span>
                </div>
                {slugStatus !== 'idle' && (
                  <div
                    id="signup-slug-status"
                    aria-live="polite"
                    className={cn('mt-1.5 flex items-center gap-1.5 text-xs font-medium', slugStatusClass(slugStatus))}
                  >
                    {slugStatus === 'checking' && <Loader2 className="h-3.5 w-3.5 animate-spin" aria-hidden="true" />}
                    {slugStatus === 'available' && <CheckCircle2 className="h-3.5 w-3.5" aria-hidden="true" />}
                    {(slugStatus === 'taken' || slugStatus === 'invalid') && <XCircle className="h-3.5 w-3.5" aria-hidden="true" />}
                    <span>{slugStatus === 'checking' ? 'Checking...' : slugMessage}</span>
                  </div>
                )}
              </FieldGroup>

              <FieldGroup htmlFor="signup-email" label="Email" error={fieldErrors.admin_email} errorId="signup-email-error">
                <input
                  id="signup-email"
                  type="email"
                  value={email}
                  onChange={e => { setEmail(e.target.value); setFieldErrors(p => ({ ...p, admin_email: undefined })); }}
                  placeholder="you@example.com"
                  maxLength={254}
                  autoComplete="email"
                  inputMode="email"
                  autoCapitalize="off"
                  autoCorrect="off"
                  spellCheck={false}
                  aria-invalid={!!fieldErrors.admin_email}
                  aria-describedby={fieldErrors.admin_email ? 'signup-email-error' : undefined}
                  className={inputClass(!!fieldErrors.admin_email)}
                />
              </FieldGroup>

              <FieldGroup htmlFor="signup-password" label="Password" error={fieldErrors.admin_password} errorId="signup-password-error">
                <div className="relative">
                  <input
                    id="signup-password"
                    type={showPassword ? 'text' : 'password'}
                    value={password}
                    onChange={e => { setPassword(e.target.value); setFieldErrors(p => ({ ...p, admin_password: undefined })); }}
                    placeholder="Min 8 characters"
                    maxLength={128}
                    autoComplete="new-password"
                    aria-invalid={!!fieldErrors.admin_password}
                    aria-describedby={passwordAriaDescribedBy}
                    className={inputClass(!!fieldErrors.admin_password, 'pr-12')}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    aria-label={showPassword ? 'Hide password' : 'Show password'}
                    aria-pressed={showPassword}
                    title={showPassword ? 'Hide password' : 'Show password'}
                    className="absolute inset-y-1 right-1 inline-flex w-10 items-center justify-center rounded-md text-surface-500 transition-colors hover:bg-surface-100 hover:text-surface-900 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-600 dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-100 dark:focus-visible:ring-cyan-400"
                  >
                    {showPassword ? <EyeOff className="h-4 w-4" aria-hidden="true" /> : <Eye className="h-4 w-4" aria-hidden="true" />}
                  </button>
                </div>
                {password && (
                  <PasswordSecurityFeedback
                    breachCheck={activePasswordBreachCheck}
                    strength={passwordStrength}
                  />
                )}
              </FieldGroup>

              <FieldGroup htmlFor="signup-confirm-password" label="Confirm Password" error={fieldErrors.confirm_password} errorId="signup-confirm-password-error">
                <input
                  id="signup-confirm-password"
                  type={showPassword ? 'text' : 'password'}
                  value={confirmPassword}
                  onChange={e => { setConfirmPassword(e.target.value); setFieldErrors(p => ({ ...p, confirm_password: undefined })); }}
                  placeholder="Repeat password"
                  maxLength={128}
                  autoComplete="new-password"
                  aria-invalid={!!fieldErrors.confirm_password}
                  aria-describedby={fieldErrors.confirm_password ? 'signup-confirm-password-error' : undefined}
                  className={inputClass(!!fieldErrors.confirm_password)}
                />
              </FieldGroup>

              {captchaSiteKey && (
                <FieldGroup label="Verification" error={fieldErrors.captcha || captchaError} errorId="signup-captcha-error">
                  <div ref={captchaContainerRef} className="min-h-[78px]" />
                  {!captchaReady && !captchaError && (
                    <div className="mt-1 text-xs text-surface-600 dark:text-surface-400">Loading verification...</div>
                  )}
                </FieldGroup>
              )}

              <Button
                type="submit"
                size="lg"
                fullWidth
                disabled={submitDisabled}
                leadingIcon={submitting ? <Loader2 className="h-4 w-4 animate-spin" aria-hidden="true" /> : undefined}
                className="mt-2 h-12 bg-surface-900 text-primary-100 hover:bg-surface-800 active:bg-surface-700 dark:bg-primary-500 dark:text-on-primary dark:hover:bg-primary-400 dark:active:bg-primary-600"
              >
                {submitting ? 'Creating Your Shop...' : 'Create My Shop'}
              </Button>
            </form>

            <div className="mt-5 text-center text-sm text-surface-600 dark:text-surface-400">
              Already have a shop?{' '}
              <Link to="/?login=true" className="font-semibold text-cyan-800 underline-offset-4 hover:underline dark:text-cyan-300">
                Log in
              </Link>
            </div>
          </div>
        </div>
      </div>
    </main>
  );
}

// ─── Helpers ──────────────────────────────────────────────────

function slugify(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 30);
}

function getProvisionedSuccessMessage(
  success: { slug: string; tenantUrl?: string },
  fallbackUrl: string,
): string {
  // Display the host portion of the actual server-provided URL so localhost
  // dev shows the real host instead of a production-shaped fallback.
  let host = '';
  try {
    host = new URL(success.tenantUrl ?? fallbackUrl).host;
  } catch {
    host = `${success.slug}.${resolveBaseDomain(window.location.hostname) ?? 'bizarrecrm.com'}`;
  }
  return `Your shop ${host} is live and you're signed in. Click below to start setting it up.`;
}

const INPUT_BASE =
  'w-full rounded-lg border bg-white px-3.5 py-3 text-[15px] text-surface-900 shadow-sm transition-colors placeholder:text-surface-400 ' +
  'focus:border-cyan-700 focus:outline-none focus:ring-2 focus:ring-cyan-700/20 ' +
  'dark:bg-surface-950 dark:text-surface-100 dark:placeholder:text-surface-500 dark:focus:border-cyan-400 dark:focus:ring-cyan-400/20';

function inputClass(hasError: boolean, className?: string): string {
  return cn(
    INPUT_BASE,
    hasError
      ? 'border-error-300 focus:border-error-500 focus:ring-error-500/20 dark:border-error-700 dark:focus:border-error-400 dark:focus:ring-error-400/20'
      : 'border-surface-300 dark:border-surface-700',
    className,
  );
}

function slugHostClass(hasError: boolean): string {
  return cn(
    'inline-flex max-w-[46%] shrink-0 items-center truncate rounded-r-lg border border-l-0 bg-surface-100 px-3 text-xs text-surface-500 dark:bg-surface-800 dark:text-surface-400 sm:text-sm',
    hasError ? 'border-error-300 dark:border-error-700' : 'border-surface-300 dark:border-surface-700',
  );
}

function PasswordSecurityFeedback({ strength, breachCheck }: { strength: PasswordStrengthAssessment; breachCheck: PasswordBreachCheck }) {
  const strengthTone = getStrengthTone(strength.score);
  const breachMessage = getBreachMessage(breachCheck);
  const activePips = Math.max(1, Math.min(4, strength.score));

  return (
    <div id="signup-password-security" className="mt-2" aria-live="polite">
      <div className="flex items-center gap-3">
        <div className="grid flex-1 grid-cols-4 gap-1" aria-hidden="true">
          {[0, 1, 2, 3].map(index => (
            <span
              key={index}
              className={cn(
                'h-1.5 rounded-full transition-colors',
                index < activePips ? strengthTone.bar : 'bg-surface-200 dark:bg-surface-700',
              )}
            />
          ))}
        </div>
        <span className={cn('min-w-20 text-right text-xs font-semibold', strengthTone.text)}>
          {strength.label}
        </span>
      </div>

      {strength.suggestions.length > 0 && (
        <p className="mt-1.5 text-xs leading-5 text-surface-500 dark:text-surface-400">
          {strength.suggestions[0]}
        </p>
      )}

      {strength.isAcceptable && breachMessage && (
        <p className={cn('mt-1.5 text-xs leading-5', breachTextClass(breachCheck.status))}>
          {breachMessage}
        </p>
      )}
    </div>
  );
}

function getStrengthTone(score: number): { bar: string; text: string } {
  if (score >= 4) return { bar: 'bg-success-700 dark:bg-success-400', text: 'text-success-700 dark:text-success-300' };
  if (score === 3) return { bar: 'bg-success-600 dark:bg-success-500', text: 'text-success-600 dark:text-success-300' };
  if (score === 2) return { bar: 'bg-warning-600 dark:bg-warning-400', text: 'text-warning-700 dark:text-warning-300' };
  return { bar: 'bg-error-600 dark:bg-error-400', text: 'text-error-600 dark:text-error-300' };
}

function breachTextClass(status: PasswordBreachCheck['status']): string {
  if (status === 'safe') return 'text-success-700 dark:text-success-300';
  if (status === 'breached' || status === 'error') return 'text-error-600 dark:text-error-300';
  return 'text-surface-500 dark:text-surface-400';
}

function slugStatusClass(status: 'idle' | 'checking' | 'available' | 'taken' | 'invalid'): string {
  if (status === 'available') return 'text-success-700 dark:text-success-300';
  if (status === 'checking') return 'text-surface-500 dark:text-surface-400';
  if (status === 'taken' || status === 'invalid') return 'text-error-600 dark:text-error-300';
  return 'text-surface-500 dark:text-surface-400';
}

function getBreachMessage(check: PasswordBreachCheck): string {
  switch (check.status) {
    case 'checking':
      return 'Checking breach data...';
    case 'safe':
      return 'No breach match found.';
    case 'breached':
      return `Seen in ${formatBreachCount(check.count)}.`;
    case 'error':
      return check.message;
    case 'idle':
    default:
      return 'Waiting to check breach data.';
  }
}

function formatBreachCount(count: number): string {
  const safeCount = Number.isFinite(count) ? Math.max(0, count) : 0;
  return `${safeCount.toLocaleString()} known ${safeCount === 1 ? 'breach' : 'breaches'}`;
}

function FieldGroup({ label, error, errorId, htmlFor, children }: { label: string; error?: string; errorId?: string; htmlFor?: string; children: ReactNode }) {
  return (
    <div className="mb-4">
      <label htmlFor={htmlFor} className="mb-1.5 block text-sm font-semibold text-surface-800 dark:text-surface-200">
        {label}
      </label>
      {children}
      <FormError id={errorId} message={error} />
    </div>
  );
}
