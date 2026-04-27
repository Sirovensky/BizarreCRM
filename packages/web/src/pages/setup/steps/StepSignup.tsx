/**
 * StepSignup — Step 1 of the SaaS setup wizard.
 *
 * Mockup: docs/setup-wizard-preview.html § <section id="screen-saas-1">
 *
 * Collects:
 *   - name (single field, split first+last on first space)
 *   - email (validateEmail)
 *   - password (min 10, strength indicator)
 *   - shop URL slug (validateShopSlug + live availability check)
 *
 * On submit calls POST /api/v1/signup. In dev mode the server returns
 * `accessToken` + `user`; we persist via authStore.completeLogin so the
 * authenticated client is ready to flow into Step 2 (verifyEmail). In
 * production no token is returned (verification gate) and we still hand
 * off to the verifyEmail phase via onNext().
 *
 * The captured email is forwarded via onUpdate({ signup_email }) so
 * Step 6 (Store info) can pre-fill the shop email field without re-asking.
 */
import { useEffect, useRef, useState } from 'react';
import type { JSX } from 'react';
import { Eye, EyeOff, Loader2, Check, X } from 'lucide-react';
import { validateEmail, validateShopSlug } from '@/services/validationService';
import { signupApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';
import type { StepProps } from '../wizardTypes';

type SlugStatus = 'idle' | 'invalid' | 'checking' | 'available' | 'taken';

interface PasswordStrength {
  score: 0 | 1 | 2 | 3;
  label: 'Too short' | 'Weak' | 'Fair' | 'Strong';
  colorClass: string;
}

function gradePassword(pw: string): PasswordStrength {
  if (pw.length < 10) {
    return { score: 0, label: 'Too short', colorClass: 'bg-red-500' };
  }
  let signals = 0;
  if (/[a-z]/.test(pw)) signals++;
  if (/[A-Z]/.test(pw)) signals++;
  if (/\d/.test(pw)) signals++;
  if (/[^A-Za-z0-9]/.test(pw)) signals++;
  if (pw.length >= 14) signals++;
  if (signals >= 4) return { score: 3, label: 'Strong', colorClass: 'bg-green-500' };
  if (signals >= 3) return { score: 2, label: 'Fair', colorClass: 'bg-amber-500' };
  return { score: 1, label: 'Weak', colorClass: 'bg-orange-500' };
}

/** Capitalise hyphen-separated slug into a display name fallback. */
function slugToShopName(slug: string): string {
  return slug
    .split('-')
    .filter(Boolean)
    .map((s) => s.charAt(0).toUpperCase() + s.slice(1))
    .join(' ')
    .trim();
}

export function StepSignup({ onUpdate, onNext }: StepProps): JSX.Element {
  const completeLogin = useAuthStore((s) => s.completeLogin);

  const [name, setName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [slug, setSlug] = useState('');

  const [slugStatus, setSlugStatus] = useState<SlugStatus>('idle');
  const [slugMessage, setSlugMessage] = useState('');

  const [submitting, setSubmitting] = useState(false);
  const [apiError, setApiError] = useState('');
  const [touched, setTouched] = useState({
    name: false,
    email: false,
    password: false,
    slug: false,
  });

  // Debounced slug availability check.
  // Race-guard: drop responses that arrive after the user typed further.
  const slugTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const latestSlugRef = useRef<string>('');

  useEffect(() => {
    if (slugTimerRef.current) clearTimeout(slugTimerRef.current);
    latestSlugRef.current = slug;

    if (!slug) {
      setSlugStatus('idle');
      setSlugMessage('');
      return;
    }

    const localErr = validateShopSlug(slug);
    if (localErr) {
      setSlugStatus('invalid');
      setSlugMessage(localErr);
      return;
    }

    setSlugStatus('checking');
    setSlugMessage('');

    slugTimerRef.current = setTimeout(async () => {
      try {
        const res = await signupApi.checkSlug(slug);
        if (latestSlugRef.current !== slug) return;
        const { available, reason } = res.data.data;
        setSlugStatus(available ? 'available' : 'taken');
        setSlugMessage(available ? 'Available' : reason || 'Already taken');
      } catch {
        if (latestSlugRef.current !== slug) return;
        setSlugStatus('idle');
        setSlugMessage('Could not check availability');
      }
    }, 400);

    return () => {
      if (slugTimerRef.current) clearTimeout(slugTimerRef.current);
    };
  }, [slug]);

  const strength = gradePassword(password);
  const nameErr = name.trim().length < 2 ? 'Enter your name' : null;
  const emailErr = email.length > 0 ? validateEmail(email) : 'Email is required';
  const passwordErr = password.length < 10 ? 'Password must be at least 10 characters' : null;
  const slugErr = slugStatus === 'invalid' || slugStatus === 'taken' ? slugMessage || 'Invalid slug' : null;

  const formValid =
    !nameErr &&
    !emailErr &&
    !passwordErr &&
    slugStatus === 'available';

  const handleSubmit = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    setApiError('');
    setTouched({ name: true, email: true, password: true, slug: true });
    if (!formValid || submitting) return;

    const trimmedName = name.trim();
    const firstSpace = trimmedName.indexOf(' ');
    const firstName = firstSpace === -1 ? trimmedName : trimmedName.slice(0, firstSpace);
    const lastName = firstSpace === -1 ? '' : trimmedName.slice(firstSpace + 1).trim();

    const cleanEmail = email.trim().toLowerCase();
    const cleanSlug = slug.trim().toLowerCase();
    // Derive shop name from email's local part if non-trivial, else fall back
    // to a capitalised slug. The owner edits the canonical name in Step 4.
    const emailLocal = cleanEmail.split('@')[0];
    const derivedShopName =
      emailLocal && emailLocal.length >= 3
        ? emailLocal.charAt(0).toUpperCase() + emailLocal.slice(1)
        : slugToShopName(cleanSlug) || cleanSlug;

    setSubmitting(true);
    try {
      const res = await signupApi.createShop({
        slug: cleanSlug,
        shop_name: derivedShopName,
        admin_email: cleanEmail,
        admin_password: password,
        admin_first_name: firstName,
        admin_last_name: lastName,
        // Dev mode accepts any non-empty token; prod has its own captcha
        // surface on the public /signup page. The wizard runs after auth
        // gating, so we send a dev sentinel and rely on server config.
        captcha_token: import.meta.env.DEV ? 'dev-captcha-token' : '',
      });

      // Persist captured email for Step 6 pre-fill.
      onUpdate({ signup_email: cleanEmail });

      // Dev mode: server returned tokens — drop them into authStore so the
      // next request is authenticated. Production returns no token (the
      // user must click the email link), so we just advance.
      const data = res.data.data as {
        accessToken?: string;
        user?: { id: number; email: string; role: string; first_name?: string; last_name?: string };
      };
      if (data.accessToken && data.user) {
        // refreshToken is set as an httpOnly cookie by the server; pass empty.
        completeLogin(data.accessToken, '', data.user as Parameters<typeof completeLogin>[2]);
      }

      onNext();
    } catch (err: unknown) {
      const apiErr = err as { response?: { data?: { message?: string; error?: string } } } | undefined;
      const msg =
        apiErr?.response?.data?.message ||
        apiErr?.response?.data?.error ||
        (err instanceof Error ? err.message : '') ||
        'Could not create your shop. Please try again.';
      setApiError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  // Strength bar segments — three pips that fill as score climbs.
  const pipClass = (idx: number): string => {
    if (strength.score === 0) return 'bg-surface-200 dark:bg-surface-700';
    if (idx < strength.score) return strength.colorClass;
    return 'bg-surface-200 dark:bg-surface-700';
  };

  return (
    <div className="space-y-6">
      <div className="flex justify-center">
        <WizardBreadcrumb currentLabel="Step 1 · Signup" nextLabel="Step 2 · Verify email" />
      </div>

      <form
        onSubmit={handleSubmit}
        className="bg-white dark:bg-surface-800 rounded-2xl border border-surface-200 dark:border-surface-700 p-8 max-w-xl mx-auto shadow-lg"
        noValidate
      >
        <h2 className="font-display text-3xl font-bold text-surface-900 dark:text-surface-100">
          Start your free trial
        </h2>
        <p className="text-surface-600 dark:text-surface-400 mt-1 mb-6">
          14 days of Pro. No credit card.
        </p>

        {/* Name */}
        <div className="mb-4">
          <label htmlFor="signup-name" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
            Your name <span className="text-red-500">*</span>
          </label>
          <input
            id="signup-name"
            type="text"
            autoComplete="name"
            value={name}
            onChange={(e) => setName(e.target.value)}
            onBlur={() => setTouched((t) => ({ ...t, name: true }))}
            disabled={submitting}
            className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-3 py-2.5 text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/30 disabled:opacity-60"
            placeholder="Joe Smith"
          />
          {touched.name && nameErr && (
            <p className="text-xs text-red-600 dark:text-red-400 mt-1">{nameErr}</p>
          )}
        </div>

        {/* Email */}
        <div className="mb-4">
          <label htmlFor="signup-email" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
            Email <span className="text-red-500">*</span>
          </label>
          <input
            id="signup-email"
            type="email"
            autoComplete="email"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            onBlur={() => setTouched((t) => ({ ...t, email: true }))}
            disabled={submitting}
            className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-3 py-2.5 text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/30 disabled:opacity-60"
            placeholder="joe@joesphonerepair.com"
          />
          {touched.email && emailErr && (
            <p className="text-xs text-red-600 dark:text-red-400 mt-1">{emailErr}</p>
          )}
        </div>

        {/* Password */}
        <div className="mb-4">
          <label htmlFor="signup-password" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
            Password <span className="text-red-500">*</span>
          </label>
          <div className="relative">
            <input
              id="signup-password"
              type={showPassword ? 'text' : 'password'}
              autoComplete="new-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              onBlur={() => setTouched((t) => ({ ...t, password: true }))}
              disabled={submitting}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-3 py-2.5 pr-10 text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/30 disabled:opacity-60"
              placeholder="At least 10 characters"
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="absolute inset-y-0 right-2 flex items-center text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
              tabIndex={-1}
              aria-label={showPassword ? 'Hide password' : 'Show password'}
            >
              {showPassword ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>
          {/* Strength indicator (mirrors Step 2 self-host pattern) */}
          <div className="mt-2 flex gap-1">
            <span className={`h-1 flex-1 rounded-full ${pipClass(0)}`} />
            <span className={`h-1 flex-1 rounded-full ${pipClass(1)}`} />
            <span className={`h-1 flex-1 rounded-full ${pipClass(2)}`} />
          </div>
          <p className="text-xs text-surface-500 dark:text-surface-400 mt-1">
            Min 10 characters · strength:{' '}
            <span
              className={
                strength.score === 3
                  ? 'text-green-600 font-medium'
                  : strength.score === 2
                    ? 'text-amber-600 font-medium'
                    : strength.score === 1
                      ? 'text-orange-600 font-medium'
                      : 'text-red-600 font-medium'
              }
            >
              {strength.label}
            </span>
          </p>
          {touched.password && passwordErr && (
            <p className="text-xs text-red-600 dark:text-red-400 mt-1">{passwordErr}</p>
          )}
        </div>

        {/* Slug */}
        <div className="mb-6">
          <label htmlFor="signup-slug" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
            Choose your shop URL <span className="text-red-500">*</span>
          </label>
          <div className="flex items-center gap-2">
            <div className="relative flex-1">
              <input
                id="signup-slug"
                type="text"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                value={slug}
                onChange={(e) => setSlug(e.target.value.toLowerCase())}
                onBlur={() => setTouched((t) => ({ ...t, slug: true }))}
                disabled={submitting}
                className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-3 py-2.5 pr-9 text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/30 disabled:opacity-60"
                placeholder="joes-phone-repair"
              />
              <span className="absolute inset-y-0 right-2 flex items-center" aria-hidden="true">
                {slugStatus === 'checking' && <Loader2 className="h-4 w-4 text-surface-400 animate-spin" />}
                {slugStatus === 'available' && <Check className="h-4 w-4 text-green-600" />}
                {(slugStatus === 'taken' || slugStatus === 'invalid') && <X className="h-4 w-4 text-red-600" />}
              </span>
            </div>
            <span className="text-surface-500 text-sm select-none">.bizarrecrm.com</span>
          </div>
          {slug && slugMessage && (
            <p
              className={`text-xs mt-1 ${
                slugStatus === 'available'
                  ? 'text-green-600 dark:text-green-400'
                  : slugStatus === 'checking'
                    ? 'text-surface-500'
                    : 'text-red-600 dark:text-red-400'
              }`}
            >
              {slugMessage}
            </p>
          )}
          {touched.slug && !slug && (
            <p className="text-xs text-red-600 dark:text-red-400 mt-1">Pick a shop URL</p>
          )}
        </div>

        {apiError && (
          <div
            role="alert"
            className="mb-4 rounded-lg border border-red-200 dark:border-red-800 bg-red-50 dark:bg-red-900/20 px-3 py-2 text-sm text-red-700 dark:text-red-300"
          >
            {apiError}
          </div>
        )}

        <button
          type="submit"
          disabled={submitting || !formValid}
          className="bg-primary-500 hover:bg-primary-600 text-primary-950 font-semibold py-3 rounded-lg w-full inline-flex items-center justify-center gap-2 transition disabled:cursor-not-allowed disabled:opacity-50"
        >
          {submitting && <Loader2 className="h-4 w-4 animate-spin" />}
          {submitting ? 'Creating your shop…' : 'Create my shop'}
        </button>
      </form>
    </div>
  );
}

export default StepSignup;
