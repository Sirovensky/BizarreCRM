import { useState, useEffect, useRef, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { signupApi } from '../../api/endpoints';
import { redactEmails } from '../../utils/apiError';

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

export function SignupPage() {
  const [slug, setSlug] = useState('');
  const [shopName, setShopName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

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
  // WIZARD-EMAIL-1: track dev-skip state on the signup success screen so the
  // owner can short-circuit email verification while SMTP is still un-wired.
  const [devSkipState, setDevSkipState] = useState<'idle' | 'submitting' | 'failed'>('idle');
  const [devSkipError, setDevSkipError] = useState('');
  const captchaSiteKey = (import.meta.env.VITE_HCAPTCHA_SITE_KEY || '').trim();
  const [captchaToken, setCaptchaToken] = useState('');
  const [captchaReady, setCaptchaReady] = useState(!captchaSiteKey);
  const [captchaError, setCaptchaError] = useState('');

  const slugTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const captchaContainerRef = useRef<HTMLDivElement | null>(null);
  const captchaWidgetIdRef = useRef<string | number | null>(null);

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

  const validate = (): boolean => {
    const errors: FieldErrors = {};
    if (!slug || slug.length < 3) errors.slug = 'Shop URL is required (min 3 characters)';
    if (slugStatus === 'taken') errors.slug = 'This name is already taken';
    if (slugStatus === 'invalid') errors.slug = 'Invalid format';
    if (!shopName.trim() || shopName.trim().length < 2) errors.shop_name = 'Shop name is required';
    if (!email.trim() || !/\S+@\S+\.\S+/.test(email)) errors.admin_email = 'Valid email is required';
    if (!password || password.length < 8) errors.admin_password = 'Password must be at least 8 characters';
    if (password !== confirmPassword) errors.confirm_password = 'Passwords do not match';
    if (captchaSiteKey && !captchaToken) errors.captcha = 'Please complete the verification check';
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
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
    return (
      <div style={{ minHeight: '100vh', background: '#FBF3DB', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Roboto', sans-serif" }}>
        <div style={{ textAlign: 'center', maxWidth: 440, padding: 32 }}>
          <div style={{ fontSize: 48, marginBottom: 16 }}>{success.provisioned ? '✅' : '✉️'}</div>
          <h2 style={{ fontFamily: "'Inter', system-ui, sans-serif", fontSize: 36, color: '#0891B2', letterSpacing: 2, marginBottom: 8 }}>
            {success.provisioned ? 'Shop ready!' : 'Check Your Email'}
          </h2>
          <p style={{ color: '#555', fontSize: 16, marginBottom: 24, lineHeight: 1.5 }}>
            {success.provisioned
              ? (() => {
                  // Display the host portion of the actual server-provided URL
                  // so localhost dev shows "vizcompare.localhost" not the
                  // hardcoded ".bizarrecrm.com" production string.
                  let host = '';
                  try {
                    host = new URL(success.tenantUrl ?? fallbackUrl).host;
                  } catch {
                    host = `${success.slug}.${resolveBaseDomain(window.location.hostname) ?? 'bizarrecrm.com'}`;
                  }
                  return `Your shop ${host} is live and you're signed in. Click below to start setting it up.`;
                })()
              : (success.message || `We've sent a confirmation link to help finish creating your shop at ${success.slug}.`)}
          </p>

          {success.provisioned && (
            <a
              href={fallbackUrl}
              style={{
                display: 'inline-block',
                background: '#0891B2',
                color: '#fff',
                padding: '12px 28px',
                borderRadius: 8,
                fontSize: 16,
                fontWeight: 600,
                textDecoration: 'none',
                marginBottom: 16,
              }}
            >
              Open your shop &rarr;
            </a>
          )}

          <div style={{ marginTop: success.provisioned ? 8 : 24, fontSize: 14, color: '#666' }}>
            <Link to="/" style={{ color: '#0E7490', fontWeight: 600, textDecoration: 'none' }}>Return to home</Link>
          </div>

          {/* WIZARD-EMAIL-1 (TEMPORARY — must be removed before SaaS launch).
              Outbound email isn't wired yet, so without this button a dev test
              cannot complete the signup flow end-to-end. The matching backend
              route /api/v1/signup/verify/dev-skip is gated behind
              NODE_ENV !== 'production' AND WIZARD_DEV_SKIP_EMAIL=1. */}
          {/* Dev-skip button only useful when the shop is NOT yet provisioned
              (production-style email-pending path). When the server already
              auto-provisioned in dev mode, success.provisioned is true and
              the "Open your shop" CTA above is the right next step. */}
          {import.meta.env.DEV && !success.provisioned && (
            <div style={{ marginTop: 32, padding: 16, background: '#FEF3C7', border: '1px solid #FBBF24', borderRadius: 8, textAlign: 'left' }}>
              <p style={{ fontSize: 12, fontWeight: 600, color: '#92400E', marginBottom: 8, textTransform: 'uppercase', letterSpacing: '0.5px' }}>Dev only</p>
              <p style={{ fontSize: 13, color: '#78350F', marginBottom: 12 }}>
                SMTP isn't wired yet. Use this to provision the tenant immediately and bypass the email-link step.
              </p>
              <button
                type="button"
                onClick={async () => {
                  if (devSkipState === 'submitting') return;
                  setDevSkipState('submitting');
                  setDevSkipError('');
                  try {
                    const r = await fetch('/api/v1/signup/verify/dev-skip', {
                      method: 'POST',
                      headers: { 'Content-Type': 'application/json', Accept: 'application/json' },
                      credentials: 'include',
                      body: JSON.stringify({ slug: success.slug, adminEmail: success.adminEmail }),
                    });
                    const body = await r.json().catch(() => ({}));
                    if (!r.ok) {
                      setDevSkipState('failed');
                      if (r.status === 404) {
                        setDevSkipError('Dev-skip not enabled on the server. Set NODE_ENV != production AND WIZARD_DEV_SKIP_EMAIL=1, then restart.');
                      } else {
                        setDevSkipError(body?.message || `Dev-skip failed (HTTP ${r.status}).`);
                      }
                      return;
                    }
                    // Success — backend has provisioned the tenant and set
                    // refresh-token + csrf cookies. Redirect to the subdomain
                    // login (or directly into the wizard if accessToken came
                    // back). The full URL is guaranteed safe since slug is our
                    // own input.
                    const url = body?.data?.url || getTenantUrl(success.slug, '/login?verified=1');
                    window.location.href = url;
                  } catch (e: unknown) {
                    setDevSkipState('failed');
                    setDevSkipError(e instanceof Error ? e.message : 'Network error.');
                  }
                }}
                disabled={devSkipState === 'submitting'}
                style={{
                  background: devSkipState === 'submitting' ? '#FBBF24' : '#F59E0B',
                  color: '#451A03',
                  border: 'none',
                  borderRadius: 6,
                  padding: '8px 14px',
                  fontSize: 13,
                  fontWeight: 600,
                  cursor: devSkipState === 'submitting' ? 'wait' : 'pointer',
                }}
              >
                {devSkipState === 'submitting' ? 'Skipping…' : 'Skip email check (dev only)'}
              </button>
              {devSkipError && (
                <p style={{ marginTop: 10, fontSize: 12, color: '#991B1B' }}>{devSkipError}</p>
              )}
            </div>
          )}
        </div>
      </div>
    );
  }

  const submitDisabled = submitting || slugStatus === 'checking' || (Boolean(captchaSiteKey) && !captchaReady);

  return (
    <div style={{ minHeight: '100vh', background: '#FBF3DB', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '40px 16px', fontFamily: "'Jost', 'Roboto', sans-serif" }}>
      {/* WEB-FA-024: dropped per-page <style>@import — Bebas Neue is loaded
          once globally via index.html <link rel="stylesheet">. The inline
          @import duplicated the network round-trip on every signup mount
          AND blocked first paint while the @import resolved. League Spartan
          + Roboto refs further down fall back to Jost / system stack which
          aligns with the project_brand_fonts (Jost) canonical body face. */}
      <div style={{ width: '100%', maxWidth: 460 }}>
        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <Link to="/" style={{ textDecoration: 'none', display: 'inline-block' }}>
            <span style={{ fontFamily: "'Inter', system-ui, sans-serif", fontSize: 32, color: '#bc398f', letterSpacing: 3, cursor: 'pointer' }}>BIZARRECRM</span>
          </Link>
          <h1 style={{ fontFamily: "'Inter', system-ui, sans-serif", fontSize: 40, color: '#0891B2', letterSpacing: 2, marginTop: 8, marginBottom: 4 }}>
            Create Your Shop
          </h1>
          <p style={{ color: '#666', fontSize: 15 }}>Free to start. No credit card required.</p>
        </div>

        {/* Form card */}
        <form onSubmit={handleSubmit} noValidate style={{ background: '#fff', borderRadius: 12, padding: 32, boxShadow: '0 4px 24px rgba(0,0,0,.08)' }}>
          {apiError && (
            <div role="alert" aria-live="assertive" style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 8, padding: '10px 14px', marginBottom: 20, color: '#dc2626', fontSize: 14 }}>
              {apiError}
            </div>
          )}

          {/* Shop Name */}
          <FieldGroup htmlFor="signup-shop-name" label="Shop Name" error={fieldErrors.shop_name} errorId="signup-shop-name-error">
            <input
              id="signup-shop-name"
              type="text"
              value={shopName}
              onChange={e => handleShopNameChange(e.target.value)}
              placeholder="My Repair Shop"
              maxLength={100}
              autoFocus
              aria-invalid={!!fieldErrors.shop_name}
              aria-describedby={fieldErrors.shop_name ? 'signup-shop-name-error' : undefined}
              style={inputStyle(!!fieldErrors.shop_name)}
            />
          </FieldGroup>

          {/* Slug */}
          <FieldGroup htmlFor="signup-slug" label="Shop URL" error={fieldErrors.slug} errorId="signup-slug-error">
            <div style={{ display: 'flex' }}>
              <input
                id="signup-slug"
                type="text"
                value={slug}
                onChange={e => setSlug(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ''))}
                placeholder="your-shop"
                maxLength={30}
                aria-invalid={!!fieldErrors.slug}
                aria-describedby={
                  fieldErrors.slug
                    ? 'signup-slug-error'
                    : slugStatus !== 'idle'
                      ? 'signup-slug-status'
                      : undefined
                }
                style={{ ...inputStyle(!!fieldErrors.slug), borderRadius: '8px 0 0 8px', borderRight: 'none' }}
              />
              <span style={{
                display: 'flex', alignItems: 'center', padding: '0 12px',
                background: '#f5f5f5', border: `2px solid ${fieldErrors.slug ? '#fca5a5' : '#ddd'}`,
                borderLeft: 'none', borderRadius: '0 8px 8px 0', color: '#999', fontSize: 13, whiteSpace: 'nowrap',
              }}>.{resolveBaseDomain(window.location.hostname) ?? 'bizarrecrm.com'}</span>
            </div>
            {slugStatus !== 'idle' && (
              <div id="signup-slug-status" style={{ marginTop: 4, fontSize: 13, color: slugStatus === 'available' ? '#16a34a' : slugStatus === 'checking' ? '#999' : '#dc2626' }}>
                {slugStatus === 'checking' ? 'Checking...' : slugMessage}
              </div>
            )}
          </FieldGroup>

          {/* Email */}
          <FieldGroup htmlFor="signup-email" label="Email" error={fieldErrors.admin_email} errorId="signup-email-error">
            <input
              id="signup-email"
              type="email"
              value={email}
              onChange={e => { setEmail(e.target.value); setFieldErrors(p => ({ ...p, admin_email: undefined })); }}
              placeholder="you@example.com"
              maxLength={254}
              aria-invalid={!!fieldErrors.admin_email}
              aria-describedby={fieldErrors.admin_email ? 'signup-email-error' : undefined}
              style={inputStyle(!!fieldErrors.admin_email)}
            />
          </FieldGroup>

          {/* Password */}
          <FieldGroup htmlFor="signup-password" label="Password" error={fieldErrors.admin_password} errorId="signup-password-error">
            <div style={{ position: 'relative' }}>
              <input
                id="signup-password"
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={e => { setPassword(e.target.value); setFieldErrors(p => ({ ...p, admin_password: undefined })); }}
                placeholder="Min 8 characters"
                maxLength={128}
                aria-invalid={!!fieldErrors.admin_password}
                aria-describedby={fieldErrors.admin_password ? 'signup-password-error' : undefined}
                style={{ ...inputStyle(!!fieldErrors.admin_password), paddingRight: 44 }}
              />
              <button type="button" onClick={() => setShowPassword(!showPassword)}
                aria-label={showPassword ? 'Hide password' : 'Show password'}
                aria-pressed={showPassword}
                style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 13, fontFamily: "'Roboto', sans-serif" }}>
                {showPassword ? 'Hide' : 'Show'}
              </button>
            </div>
          </FieldGroup>

          {/* Confirm Password */}
          <FieldGroup htmlFor="signup-confirm-password" label="Confirm Password" error={fieldErrors.confirm_password} errorId="signup-confirm-password-error">
            <input
              id="signup-confirm-password"
              type={showPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={e => { setConfirmPassword(e.target.value); setFieldErrors(p => ({ ...p, confirm_password: undefined })); }}
              placeholder="Repeat password"
              maxLength={128}
              aria-invalid={!!fieldErrors.confirm_password}
              aria-describedby={fieldErrors.confirm_password ? 'signup-confirm-password-error' : undefined}
              style={inputStyle(!!fieldErrors.confirm_password)}
            />
          </FieldGroup>


          {captchaSiteKey && (
            <FieldGroup label="Verification" error={fieldErrors.captcha || captchaError} errorId="signup-captcha-error">
              <div ref={captchaContainerRef} style={{ minHeight: 78 }} />
              {!captchaReady && !captchaError && (
                <div style={{ marginTop: 4, fontSize: 13, color: '#666' }}>Loading verification...</div>
              )}
            </FieldGroup>
          )}

          {/* Submit */}
          <button
            type="submit"
            disabled={submitDisabled}
            style={{
              width: '100%', padding: '14px 0', marginTop: 8,
              background: submitDisabled ? '#999' : '#0E7490', color: '#fff', border: 'none', borderRadius: 8,
              fontFamily: "'League Spartan', sans-serif", fontWeight: 600, fontSize: 16,
              cursor: submitDisabled ? 'not-allowed' : 'pointer', transition: 'background .2s',
            }}
          >
            {submitting ? 'Creating Your Shop...' : 'Create My Shop'}
          </button>
        </form>

        {/* Footer links */}
        <div style={{ textAlign: 'center', marginTop: 20, fontSize: 14, color: '#666' }}>
          Already have a shop?{' '}
          <Link to="/?login=true" style={{ color: '#0E7490', fontWeight: 600, textDecoration: 'none' }}>Log in</Link>
        </div>
      </div>
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────

function slugify(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 30);
}

function inputStyle(hasError: boolean): React.CSSProperties {
  return {
    width: '100%', padding: '11px 14px', fontSize: 15, color: '#1a1a1a',
    border: `2px solid ${hasError ? '#fca5a5' : '#ddd'}`, borderRadius: 8,
    outline: 'none', fontFamily: "'Roboto', sans-serif",
    transition: 'border-color .2s', boxSizing: 'border-box',
  };
}

function FieldGroup({ label, error, errorId, htmlFor, children }: { label: string; error?: string; errorId?: string; htmlFor?: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <label htmlFor={htmlFor} style={{ display: 'block', marginBottom: 6, fontSize: 14, fontWeight: 600, fontFamily: "'League Spartan', sans-serif", color: '#333' }}>
        {label}
      </label>
      {children}
      {error && <div id={errorId} role="alert" aria-live="polite" style={{ marginTop: 4, fontSize: 13, color: '#dc2626' }}>{error}</div>}
    </div>
  );
}
