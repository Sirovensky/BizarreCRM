import { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Zap, Loader2, ShieldCheck, Smartphone, Copy, Check, KeyRound, Eye, EyeOff, WifiOff, AlertTriangle, ShieldAlert, ServerCrash, Mail } from 'lucide-react';
import { authApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { formatApiError } from '@/utils/apiError';

type ErrorKind = 'network' | 'credentials' | 'rate-limit' | 'server';

// WEB-FA-014: Module-level (per-tab) cache of the most recent me() / setupStatus
// resolution so a remount of LoginPage within `STALE_MS` does not re-hit the
// server. Multi-tab dedup uses sessionStorage with the same TTL — the typical
// "open 3 tabs of the dashboard while logged out" pattern previously fired N
// /me + N /setup-status calls; with this guard the second/third tab read the
// cached envelope synchronously and skip the network hop.
const STALE_MS = 5_000;
const MEM_CACHE_KEY = 'bizarre:loginpage:bootstrap';
type LoginBootstrapCache = {
  ts: number;
  setupNeedsSetup: boolean | null;
  setupIsMultiTenant: boolean | null;
  meUser: unknown | null;
};
let memCache: LoginBootstrapCache | null = null;
function readBootstrapCache(): LoginBootstrapCache | null {
  const now = Date.now();
  if (memCache && now - memCache.ts < STALE_MS) return memCache;
  try {
    const raw = sessionStorage.getItem(MEM_CACHE_KEY);
    if (!raw) return null;
    const parsed = JSON.parse(raw) as LoginBootstrapCache;
    if (parsed && typeof parsed.ts === 'number' && now - parsed.ts < STALE_MS) {
      memCache = parsed;
      return parsed;
    }
  } catch {
    /* ignore */
  }
  return null;
}
function writeBootstrapCache(entry: LoginBootstrapCache): void {
  memCache = entry;
  try {
    sessionStorage.setItem(MEM_CACHE_KEY, JSON.stringify(entry));
  } catch {
    /* storage disabled — module-level mem cache still works */
  }
}

function LoginError({ message, kind }: { message: string; kind: ErrorKind }) {
  const config: Record<ErrorKind, { icon: React.ReactNode; bg: string; text: string; border: string }> = {
    network: {
      icon: <WifiOff className="h-4 w-4 shrink-0" />,
      bg: 'bg-orange-50 dark:bg-orange-950/30',
      text: 'text-orange-700 dark:text-orange-300',
      border: 'border-orange-200 dark:border-orange-800',
    },
    credentials: {
      icon: <ShieldAlert className="h-4 w-4 shrink-0" />,
      bg: 'bg-red-50 dark:bg-red-950/30',
      text: 'text-red-700 dark:text-red-300',
      border: 'border-red-200 dark:border-red-800',
    },
    'rate-limit': {
      icon: <AlertTriangle className="h-4 w-4 shrink-0" />,
      bg: 'bg-amber-50 dark:bg-amber-950/30',
      text: 'text-amber-700 dark:text-amber-300',
      border: 'border-amber-200 dark:border-amber-800',
    },
    server: {
      icon: <ServerCrash className="h-4 w-4 shrink-0" />,
      bg: 'bg-red-50 dark:bg-red-950/30',
      text: 'text-red-700 dark:text-red-300',
      border: 'border-red-200 dark:border-red-800',
    },
  };
  const c = config[kind];
  return (
    <div className={`flex items-center gap-2.5 rounded-lg border p-3 ${c.bg} ${c.text} ${c.border}`}>
      {c.icon}
      <p className="text-sm">{message}</p>
    </div>
  );
}

type Step = 'password' | 'setPassword' | 'setup' | 'verify' | 'firstTimeSetup';

export function LoginPage() {
  const navigate = useNavigate();
  const { isAuthenticated, completeLogin } = useAuthStore();

  const [step, setStep] = useState<Step>('password');
  const [setupUsername, setSetupUsername] = useState('');
  const [setupPassword, setSetupPassword] = useState('');
  const [setupEmail, setSetupEmail] = useState('');
  const [setupFirstName, setSetupFirstName] = useState('');
  const [setupLastName, setSetupLastName] = useState('');
  const [setupStoreName, setSetupStoreName] = useState('');
  const [setupToken, setSetupToken] = useState('');
  // True when the backend reported `isMultiTenant=false` and no users exist.
  // In that branch the first-run form is the real setup wizard: no setup
  // token is required, but first/last name and store name are collected.
  const [isSingleTenantSetup, setIsSingleTenantSetup] = useState(false);
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [challengeToken, setChallengeToken] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [qrUrl, setQrUrl] = useState('');
  const [manualSecret, setManualSecret] = useState('');
  const [error, setError] = useState('');
  const [errorKind, setErrorKind] = useState<ErrorKind>('server');
  const [loading, setLoading] = useState(false);
  const [copied, setCopied] = useState(false);
  const [trustDevice, setTrustDevice] = useState(false);
  const [autoChecking, setAutoChecking] = useState(true);
  const [showPassword, setShowPassword] = useState(false);
  const [showForgot, setShowForgot] = useState(false);
  const [forgotEmail, setForgotEmail] = useState('');
  const [forgotSent, setForgotSent] = useState(false);
  const [forgotLoading, setForgotLoading] = useState(false);
  const [needsSetupNoToken, setNeedsSetupNoToken] = useState(false);
  const [fieldErrors, setFieldErrors] = useState<{ username?: string; password?: string }>({});
  const codeRef = useRef<HTMLInputElement>(null);

  // Check for setup token in URL (/setup/:token). W11 fix: guard against
  // resolving state updates after unmount — if the user navigates away mid-
  // check, the stale promise would call setStep / setAutoChecking on an
  // unmounted component. `cancelled` flips in the cleanup and every branch
  // checks before calling a setter.
  // WEB-FA-001 fix: previously the catch silently dropped the error,
  // potentially leaving the user staring at an empty login card with no
  // way to recover. Now we surface a non-fatal banner with the parsed
  // error and log to the console for debugging.
  useEffect(() => {
    const match = window.location.pathname.match(/^\/setup\/([a-f0-9]{64})$/);
    if (!match) return;
    setSetupToken(match[1]);
    let cancelled = false;
    authApi.setupStatus()
      .then(res => {
        if (cancelled) return;
        if (res.data?.data?.needsSetup) {
          setStep('firstTimeSetup');
          setAutoChecking(false);
        } else {
          // Shop already set up — redirect to login
          window.history.replaceState(null, '', '/login');
          setAutoChecking(false);
        }
      })
      .catch((err: unknown) => {
        if (cancelled) return;
        // eslint-disable-next-line no-console
        console.error('[LoginPage] setupStatus failed (token path):', err);
        const e = err as { response?: { status?: number } } | undefined;
        if (!e?.response) {
          setErrorKind('network');
          setError('Cannot reach server to verify setup link. Check your connection and try again.');
        } else {
          setErrorKind('server');
          setError(formatApiError(err) || 'Failed to verify setup link.');
        }
        setAutoChecking(false);
      });
    return () => { cancelled = true; };
  }, []);

  // Combined auth check: if already authenticated redirect immediately,
  // otherwise try to restore session from a valid refresh token cookie.
  useEffect(() => {
    if (isAuthenticated) { navigate('/'); return; }
    if (step === 'firstTimeSetup') return; // Skip auth check during setup

    let cancelled = false;
    (async () => {
      // WEB-FA-014: Short-lived bootstrap cache (per-tab + sessionStorage)
      // skips the network round-trip when LoginPage remounts or a sibling
      // tab already resolved the same data within the STALE_MS window.
      const cached = readBootstrapCache();
      let setupData: { needsSetup?: boolean; isMultiTenant?: boolean } | null =
        cached
          ? { needsSetup: cached.setupNeedsSetup ?? undefined, isMultiTenant: cached.setupIsMultiTenant ?? undefined }
          : null;
      let cachedMeUser: unknown = cached?.meUser ?? null;

      // WEB-FA-001 fix: setupStatus() failures used to fall into the same
      // empty catch as me() failures. me() failing is the normal "no
      // session" path (silent), but setupStatus() failing means we don't
      // know whether to render the first-run wizard or the login form —
      // surface that to the user instead of leaving them stuck.
      if (!setupData) {
        try {
          // Also check if shop needs first-time setup
          const setupRes = await authApi.setupStatus();
          if (cancelled) return;
          setupData = setupRes.data?.data ?? null;
        } catch (err: unknown) {
          if (cancelled) return;
          // eslint-disable-next-line no-console
          console.error('[LoginPage] setupStatus failed:', err);
          const e = err as { response?: { status?: number } } | undefined;
          if (!e?.response) {
            setErrorKind('network');
            setError('Cannot reach server. Check your connection and try again.');
          } else {
            setErrorKind('server');
            setError(formatApiError(err) || 'Server error while checking setup status.');
          }
          // Fall through to render the login form so the user is not stuck.
          setAutoChecking(false);
          return;
        }
      }

      if (setupData?.needsSetup) {
        // Single-tenant mode: no token exists because there's no
        // provisioning flow. Render the full first-run wizard.
        if (setupData.isMultiTenant === false) {
          setIsSingleTenantSetup(true);
          setStep('firstTimeSetup');
          setAutoChecking(false);
          return;
        }
        // Multi-tenant mode, no token in URL — tell the user to ask an
        // admin for a setup link (the token path handles the rest).
        setNeedsSetupNoToken(true);
        setAutoChecking(false);
        return;
      }

      let meUser: unknown = cachedMeUser;
      if (!meUser) {
        try {
          const res = await authApi.me();
          if (cancelled) return;
          // @audit-fixed: server returns `{ success, data: req.user }` — the User
          // sits at `res.data.data`, not `res.data.data.user`. The old read kept
          // returning undefined and silently dropped every auto-login attempt.
          meUser = res.data?.data ?? null;
        } catch {
          // No valid session — proceed to login form (expected path, silent).
          meUser = null;
        }
        if (cancelled) return;
      }

      // Persist whatever we resolved (success or null) for sibling tabs.
      writeBootstrapCache({
        ts: Date.now(),
        setupNeedsSetup: setupData?.needsSetup ?? null,
        setupIsMultiTenant: setupData?.isMultiTenant ?? null,
        meUser: meUser ?? null,
      });

      if (meUser) {
        const token = localStorage.getItem('accessToken');
        if (token) {
          completeLogin(token, '', meUser as Parameters<typeof completeLogin>[2]);
          navigate('/');
          return;
        }
      }
      if (!cancelled) setAutoChecking(false);
    })();

    return () => { cancelled = true; };
  }, [isAuthenticated, navigate, completeLogin, step]);

  async function handlePassword(e: React.FormEvent) {
    e.preventDefault();
    const errors: { username?: string; password?: string } = {};
    if (!username.trim()) errors.username = 'Username or email is required';
    if (!password) errors.password = 'Password is required';
    setFieldErrors(errors);
    if (Object.keys(errors).length > 0) return;
    setError('');
    setLoading(true);
    try {
      const res = await authApi.login(username, password);
      const data = res.data.data;

      // Trusted device — server skipped 2FA and issued tokens directly.
      // Defensive null-check: a malformed/partial 2FA-skip response without
      // refreshToken or user must NOT be treated as a successful login.
      if (data.trustedDevice && data.accessToken) {
        if (!data.refreshToken || !data.user) {
          setErrorKind('server');
          setError('Login response was incomplete. Please try again.');
          return;
        }
        completeLogin(data.accessToken, data.refreshToken, data.user);
        return;
      }

      setChallengeToken(data.challengeToken!);
      if (data.requiresPasswordSetup) {
        setStep('setPassword');
      } else if (data.requires2faSetup) {
        const setupRes = await authApi.setup2fa(data.challengeToken!);
        const setupData = setupRes.data.data;
        if (setupData.challengeToken) setChallengeToken(setupData.challengeToken);
        setQrUrl(setupData.qr);
        setManualSecret(setupData.secret);
        setStep('setup');
      } else {
        setStep('verify');
      }
    } catch (err: unknown) {
      const e = err as { response?: { status?: number } } | undefined;
      if (!e?.response) {
        setErrorKind('network');
        setError('Cannot connect to server. Check your network connection.');
      } else if (e.response.status === 429) {
        setErrorKind('rate-limit');
        setError('Too many login attempts. Please try again later.');
      } else if (e.response.status === 401) {
        setErrorKind('credentials');
        setError('Invalid username or password.');
      } else {
        setErrorKind('server');
        setError(formatApiError(err));
      }
    } finally {
      setLoading(false);
      setTotpCode('');
    }
  }

  async function handleVerify(e: React.FormEvent) {
    e.preventDefault();
    if (totpCode.length !== 6) return;
    setError('');
    setLoading(true);
    try {
      const res = await authApi.verify2fa(challengeToken, totpCode, trustDevice);
      const data = res.data.data;
      completeLogin(data.accessToken, data.refreshToken, data.user);
      navigate('/');
    } catch (err: unknown) {
      const msg = formatApiError(err) || 'Invalid code';
      const e = err as { response?: { data?: { data?: { challengeToken?: string } } } } | undefined;
      const newToken = e?.response?.data?.data?.challengeToken;
      if (newToken) setChallengeToken(newToken);
      setError(msg);
      setTotpCode('');
      codeRef.current?.focus();
    } finally {
      setLoading(false);
    }
  }

  async function handleSetPassword(e: React.FormEvent) {
    e.preventDefault();
    if (newPassword.length < 8) { setError('Password must be at least 8 characters'); return; }
    if (newPassword !== confirmPassword) { setError('Passwords do not match'); return; }
    setError('');
    setLoading(true);
    try {
      const res = await authApi.setPassword(challengeToken, newPassword);
      const newToken = res.data.data.challengeToken;
      setChallengeToken(newToken);
      // Now proceed to 2FA setup
      const setupRes = await authApi.setup2fa(newToken);
      const setupData = setupRes.data.data;
      if (setupData.challengeToken) setChallengeToken(setupData.challengeToken);
      setQrUrl(setupData.qr);
      setManualSecret(setupData.secret);
      setStep('setup');
    } catch (err: unknown) {
      setError(formatApiError(err) || 'Failed to set password');
    } finally {
      setLoading(false);
    }
  }

  function copySecret() {
    navigator.clipboard.writeText(manualSecret);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }

  if (autoChecking) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 via-primary-50/30 to-surface-100 dark:from-surface-950 dark:via-surface-900 dark:to-surface-950">
        <Loader2 className="h-8 w-8 animate-spin text-primary-600" />
      </div>
    );
  }

  if (needsSetupNoToken) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 via-primary-50/30 to-surface-100 dark:from-surface-950 dark:via-surface-900 dark:to-surface-950">
        <div className="w-full max-w-md px-4">
          <div className="mb-8 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary-600 shadow-lg shadow-primary-600/30">
              <Zap className="h-8 w-8 text-white" />
            </div>
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Bizarre CRM</h1>
          </div>
          <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
            <div className="flex items-center gap-3 rounded-lg bg-amber-50 p-4 dark:bg-amber-950/30">
              <KeyRound className="h-5 w-5 shrink-0 text-amber-600" />
              <p className="text-sm text-amber-800 dark:text-amber-300">
                This shop hasn't been set up yet. Contact your administrator for a setup link.
              </p>
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="relative flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 via-primary-50/30 to-surface-100 dark:from-surface-950 dark:via-surface-900 dark:to-surface-950">
      <div className="w-full max-w-md px-4">
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary-600 shadow-lg shadow-primary-600/30">
            <Zap className="h-8 w-8 text-white" />
          </div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Bizarre CRM</h1>
          <p className="text-surface-500 dark:text-surface-400">
            {step === 'firstTimeSetup' && (isSingleTenantSetup
              ? 'Welcome — set up your shop and admin account'
              : 'Welcome! Create your admin account')}
            {step === 'password' && 'Sign in to your account'}
            {step === 'setPassword' && 'Create your password'}
            {step === 'setup' && 'Set up two-factor authentication'}
            {step === 'verify' && 'Enter your authenticator code'}
          </p>
        </div>

        <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          {step === 'firstTimeSetup' && (
            <form onSubmit={async (e) => {
              e.preventDefault();
              setError('');
              if (!setupUsername.trim() || setupUsername.trim().length < 3) {
                setError('Username must be at least 3 characters');
                return;
              }
              if (!setupPassword || setupPassword.length < 8) {
                setError('Password must be at least 8 characters');
                return;
              }
              if (isSingleTenantSetup) {
                if (!setupEmail.trim()) {
                  setError('Email is required');
                  return;
                }
                if (!setupFirstName.trim() || !setupLastName.trim()) {
                  setError('First and last name are required');
                  return;
                }
              }
              setLoading(true);
              try {
                await authApi.setup({
                  username: setupUsername.trim(),
                  password: setupPassword,
                  email: setupEmail.trim() || undefined,
                  first_name: isSingleTenantSetup ? setupFirstName.trim() : undefined,
                  last_name: isSingleTenantSetup ? setupLastName.trim() : undefined,
                  store_name: isSingleTenantSetup && setupStoreName.trim() ? setupStoreName.trim() : undefined,
                  setup_token: isSingleTenantSetup ? undefined : setupToken,
                });
                setStep('password');
                setUsername(setupUsername.trim());
                setPassword('');
                setError('');
                setIsSingleTenantSetup(false);
                // Wipe credentials from memory immediately — section 41 fix.
                setSetupPassword('');
                window.history.replaceState(null, '', '/login');
              } catch (err: unknown) {
                setError(formatApiError(err) || 'Setup failed');
              } finally {
                setLoading(false);
              }
            }} className="space-y-4" noValidate>
              {isSingleTenantSetup && (
                <>
                  <div>
                    <label htmlFor="setup-store-name" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Shop name</label>
                    <input
                      id="setup-store-name"
                      type="text"
                      value={setupStoreName}
                      onChange={(e) => setSetupStoreName(e.target.value)}
                      autoFocus
                      maxLength={200}
                      placeholder="Acme Phone Repair"
                      className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                    />
                    <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">Used on receipts and the dashboard header.</p>
                  </div>
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <label htmlFor="setup-first-name" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">First name</label>
                      <input
                        id="setup-first-name"
                        type="text"
                        value={setupFirstName}
                        onChange={(e) => setSetupFirstName(e.target.value)}
                        maxLength={100}
                        placeholder="John"
                        className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                      />
                    </div>
                    <div>
                      <label htmlFor="setup-last-name" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Last name</label>
                      <input
                        id="setup-last-name"
                        type="text"
                        value={setupLastName}
                        onChange={(e) => setSetupLastName(e.target.value)}
                        maxLength={100}
                        placeholder="Smith"
                        className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                      />
                    </div>
                  </div>
                </>
              )}
              <div>
                <label htmlFor="setup-username" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Username</label>
                <input
                  id="setup-username"
                  type="text"
                  value={setupUsername}
                  onChange={(e) => setSetupUsername(e.target.value)}
                  autoFocus={!isSingleTenantSetup}
                  autoComplete="username"
                  placeholder="Choose a username"
                  className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>
              <div>
                <label htmlFor="setup-email" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">
                  Email {isSingleTenantSetup ? '' : '(optional)'}
                </label>
                <input
                  id="setup-email"
                  type="email"
                  value={setupEmail}
                  onChange={(e) => setSetupEmail(e.target.value)}
                  placeholder="admin@yourshop.com"
                  autoComplete="email"
                  className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>
              <div>
                <label htmlFor="setup-password" className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Password</label>
                <input
                  id="setup-password"
                  type="password"
                  value={setupPassword}
                  onChange={(e) => setSetupPassword(e.target.value)}
                  autoComplete="new-password"
                  placeholder="Min 8 characters"
                  className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>
              {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}
              <button
                type="submit"
                disabled={loading}
                className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary-600 px-4 py-3 text-sm font-semibold text-white transition-colors hover:bg-primary-700 focus:ring-2 focus:ring-primary-500/50 disabled:opacity-50"
              >
                {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <KeyRound className="h-4 w-4" />}
                {isSingleTenantSetup ? 'Create shop & continue' : 'Create Account & Continue'}
              </button>
            </form>
          )}
          {step === 'password' && (
            <form onSubmit={handlePassword} className="space-y-4" noValidate>
              <div>
                <label htmlFor="login-username" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Username or email</label>
                <input id="login-username" type="text" value={username} onChange={(e) => { setUsername(e.target.value); setFieldErrors(prev => ({ ...prev, username: undefined })); }} autoFocus autoComplete="username"
                  placeholder="admin or admin@yourshop.com"
                  aria-invalid={!!fieldErrors.username}
                  aria-describedby={fieldErrors.username ? 'login-username-error' : undefined}
                  className={`w-full rounded-lg border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ${fieldErrors.username ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`} />
                {fieldErrors.username && <p id="login-username-error" className="mt-1 text-xs text-red-500">{fieldErrors.username}</p>}
              </div>
              <div>
                <label htmlFor="login-password" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Password</label>
                <div className="relative">
                  <input id="login-password" type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => { setPassword(e.target.value); setFieldErrors(prev => ({ ...prev, password: undefined })); }} autoComplete="current-password"
                    aria-invalid={!!fieldErrors.password}
                    aria-describedby={fieldErrors.password ? 'login-password-error' : undefined}
                    className={`w-full rounded-lg border bg-surface-50 px-4 py-3 pr-11 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ${fieldErrors.password ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`} />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} tabIndex={-1}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300">
                    {showPassword ? <EyeOff className="h-4.5 w-4.5" /> : <Eye className="h-4.5 w-4.5" />}
                  </button>
                </div>
                {fieldErrors.password && <p id="login-password-error" className="mt-1 text-xs text-red-500">{fieldErrors.password}</p>}
              </div>
              <div className="flex justify-end">
                <button type="button" onClick={() => setShowForgot(!showForgot)} className="text-xs text-primary-600 hover:text-primary-700 dark:text-primary-400 dark:hover:text-primary-300">
                  Forgot password?
                </button>
              </div>
              {showForgot && (
                <div className="rounded-lg bg-surface-100 p-3 dark:bg-surface-700">
                  {forgotSent ? (
                    <div className="flex items-center gap-2">
                      <Check className="h-4 w-4 text-green-500" />
                      <p className="text-xs text-surface-600 dark:text-surface-300">
                        If an account with that email exists, a reset link has been sent. Check your inbox.
                      </p>
                    </div>
                  ) : (
                    <div className="space-y-2">
                      <p className="text-xs text-surface-600 dark:text-surface-300">
                        Enter your email to receive a password reset link.
                      </p>
                      <div className="flex gap-2">
                        <label htmlFor="forgot-email" className="sr-only">Email for password reset</label>
                        <input
                          id="forgot-email"
                          type="email"
                          value={forgotEmail}
                          onChange={(e) => setForgotEmail(e.target.value)}
                          placeholder="your@email.com"
                          className="flex-1 rounded-lg border border-surface-300 bg-white px-3 py-1.5 text-xs text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                        />
                        <button
                          type="button"
                          disabled={forgotLoading || !forgotEmail.includes('@')}
                          onClick={async () => {
                            setForgotLoading(true);
                            try {
                              await authApi.forgotPassword(forgotEmail.trim());
                              setForgotSent(true);
                            } catch {
                              setForgotSent(true); // Don't reveal errors
                            } finally {
                              setForgotLoading(false);
                            }
                          }}
                          className="flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-white hover:bg-primary-700 disabled:opacity-50"
                        >
                          {forgotLoading ? <Loader2 className="h-3 w-3 animate-spin" /> : <Mail className="h-3 w-3" />}
                          Send
                        </button>
                      </div>
                    </div>
                  )}
                </div>
              )}
              {error && <LoginError message={error} kind={errorKind} />}
              <button type="submit" disabled={loading}
                className="w-full rounded-lg bg-primary-600 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50">
                {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Sign In'}
              </button>
            </form>
          )}

          {step === 'setPassword' && (
            <form onSubmit={handleSetPassword} className="space-y-4">
              <div className="flex items-center gap-3 rounded-lg bg-primary-50 p-3 dark:bg-primary-950/30">
                <KeyRound className="h-5 w-5 shrink-0 text-primary-600" />
                <p className="text-xs text-primary-800 dark:text-primary-300">
                  Welcome! Create a secure password for your account.
                </p>
              </div>
              <div>
                <label htmlFor="new-password" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">New Password</label>
                <input id="new-password" type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} autoFocus required minLength={8} autoComplete="new-password"
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              <div>
                <label htmlFor="confirm-password" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Confirm Password</label>
                <input id="confirm-password" type="password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} required minLength={8} autoComplete="new-password"
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              <p className="text-xs text-surface-400">Minimum 8 characters</p>
              {error && <p className="text-sm text-red-500">{error}</p>}
              <button type="submit" disabled={loading || newPassword.length < 8}
                className="w-full rounded-lg bg-primary-600 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50">
                {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Set Password & Continue'}
              </button>
            </form>
          )}

          {step === 'setup' && (
            <div className="space-y-5">
              <div className="flex items-center gap-3 rounded-lg bg-amber-50 p-3 dark:bg-amber-950/30">
                <Smartphone className="h-5 w-5 shrink-0 text-amber-600" />
                <p className="text-xs text-amber-800 dark:text-amber-300">
                  Scan this QR code with Google Authenticator, Authy, or any TOTP app.
                </p>
              </div>
              {qrUrl && (
                <div className="flex justify-center">
                  <img src={qrUrl} alt="TOTP QR Code" className="h-48 w-48 rounded-lg border border-surface-200 dark:border-surface-600" />
                </div>
              )}
              <div>
                <p className="mb-1 text-xs text-surface-500">Or enter this code manually:</p>
                <div className="flex items-center gap-2 rounded-lg bg-surface-100 p-2 dark:bg-surface-700">
                  <code className="flex-1 text-xs font-mono text-surface-800 dark:text-surface-200 break-all">{manualSecret}</code>
                  <button aria-label="Copy secret" onClick={copySecret} className="shrink-0 rounded p-1 text-surface-400 hover:text-surface-600">
                    {copied ? <Check className="h-4 w-4 text-green-500" /> : <Copy className="h-4 w-4" />}
                  </button>
                </div>
              </div>
              <form onSubmit={handleVerify} className="space-y-3">
                <label htmlFor="2fa-setup-code" className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Enter 6-digit code to verify</label>
                <input id="2fa-setup-code" ref={codeRef} type="text" inputMode="numeric" pattern="[0-9]*" maxLength={6} autoComplete="one-time-code"
                  value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, ''))}
                  placeholder="000000" autoFocus
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl font-mono tracking-[0.5em] text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
                {error && <p className="text-sm text-red-500">{error}</p>}
                <button type="submit" disabled={loading || totpCode.length !== 6}
                  className="w-full rounded-lg bg-green-600 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-green-700 disabled:opacity-50">
                  {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Verify & Complete Setup'}
                </button>
              </form>
            </div>
          )}

          {step === 'verify' && (
            <form onSubmit={handleVerify} className="space-y-5">
              <div className="flex items-center gap-3 rounded-lg bg-primary-50 p-3 dark:bg-primary-950/30">
                <ShieldCheck className="h-5 w-5 shrink-0 text-primary-600" />
                <p className="text-xs text-primary-800 dark:text-primary-300">
                  Open your authenticator app and enter the 6-digit code.
                </p>
              </div>
              <label htmlFor="2fa-verify-code" className="sr-only">6-digit authenticator code</label>
              <input id="2fa-verify-code" ref={codeRef} type="text" inputMode="numeric" pattern="[0-9]*" maxLength={6} autoComplete="one-time-code"
                value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, ''))}
                placeholder="000000" autoFocus
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl font-mono tracking-[0.5em] text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              {error && <p className="text-sm text-red-500">{error}</p>}
              <label htmlFor="trust-device" className="flex items-center gap-2 cursor-pointer">
                <input
                  id="trust-device"
                  type="checkbox"
                  checked={trustDevice}
                  onChange={(e) => setTrustDevice(e.target.checked)}
                  className="h-4 w-4 rounded border-surface-300 dark:border-surface-600 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-xs text-surface-500 dark:text-surface-400">Trust this device for 90 days</span>
              </label>
              <button type="submit" disabled={loading || totpCode.length !== 6}
                className="w-full rounded-lg bg-primary-600 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50">
                {loading ? <Loader2 className="mx-auto h-5 w-5 animate-spin" /> : 'Verify'}
              </button>
              <button type="button" onClick={() => { setStep('password'); setError(''); }}
                className="w-full text-xs text-surface-400 hover:text-surface-600">
                Back to login
              </button>
            </form>
          )}
        </div>
      </div>
    </div>
  );
}
