import { useState, useRef, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Zap, Loader2, ShieldCheck, Smartphone, Copy, Check, KeyRound, Eye, EyeOff, WifiOff, AlertTriangle, ShieldAlert, ServerCrash, Mail } from 'lucide-react';
import { authApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';

type ErrorKind = 'network' | 'credentials' | 'rate-limit' | 'server';

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
  const [setupToken, setSetupToken] = useState('');
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

  // Check for setup token in URL (/setup/:token)
  useEffect(() => {
    const match = window.location.pathname.match(/^\/setup\/([a-f0-9]{64})$/);
    if (match) {
      setSetupToken(match[1]);
      // Check if shop actually needs setup
      authApi.setupStatus().then(res => {
        if (res.data?.data?.needsSetup) {
          setStep('firstTimeSetup');
          setAutoChecking(false);
        } else {
          // Shop already set up — redirect to login
          window.history.replaceState(null, '', '/login');
          setAutoChecking(false);
        }
      }).catch(() => setAutoChecking(false));
      return;
    }
  }, []);

  // Combined auth check: if already authenticated redirect immediately,
  // otherwise try to restore session from a valid refresh token cookie.
  useEffect(() => {
    if (isAuthenticated) { navigate('/'); return; }
    if (step === 'firstTimeSetup') return; // Skip auth check during setup

    let cancelled = false;
    (async () => {
      try {
        // Also check if shop needs first-time setup
        const setupRes = await authApi.setupStatus();
        if (cancelled) return;
        if (setupRes.data?.data?.needsSetup) {
          // No users — without a setup token, show a message instead of login form
          setNeedsSetupNoToken(true);
          setAutoChecking(false);
          return;
        }

        const res = await authApi.me();
        if (cancelled) return;
        const user = res.data?.data?.user;
        if (user) {
          const token = localStorage.getItem('accessToken');
          if (token) {
            completeLogin(token, '', user);
            navigate('/');
            return;
          }
        }
      } catch {
        // No valid session -- stay on login page
        // No valid session — proceed to login form
      } finally {
        if (!cancelled) setAutoChecking(false);
      }
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

      // Trusted device — server skipped 2FA and issued tokens directly
      if (data.trustedDevice && data.accessToken) {
        completeLogin(data.accessToken, data.refreshToken!, data.user!);
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
    } catch (err: any) {
      if (!err?.response) {
        setErrorKind('network');
        setError('Cannot connect to server. Check your network connection.');
      } else if (err.response.status === 429) {
        setErrorKind('rate-limit');
        setError('Too many login attempts. Please try again later.');
      } else if (err.response.status === 401) {
        setErrorKind('credentials');
        setError('Invalid username or password.');
      } else {
        setErrorKind('server');
        setError(err.response.data?.message || 'Login failed. Please try again.');
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
    } catch (err: any) {
      const msg = err?.response?.data?.message || 'Invalid code';
      const newToken = err?.response?.data?.data?.challengeToken;
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
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Failed to set password');
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
            {step === 'firstTimeSetup' && 'Welcome! Create your admin account'}
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
              if (!setupUsername.trim() || setupUsername.length < 3) { setError('Username must be at least 3 characters'); return; }
              if (!setupPassword || setupPassword.length < 8) { setError('Password must be at least 8 characters'); return; }
              setLoading(true);
              try {
                await authApi.setup({ username: setupUsername.trim(), password: setupPassword, email: setupEmail || undefined, setup_token: setupToken });
                setStep('password');
                setUsername(setupUsername.trim());
                setPassword('');
                setError('');
                window.history.replaceState(null, '', '/login');
              } catch (err: any) {
                setError(err?.response?.data?.message || 'Setup failed');
              } finally { setLoading(false); }
            }} className="space-y-4" noValidate>
              <div>
                <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Username</label>
                <input type="text" value={setupUsername} onChange={(e) => setSetupUsername(e.target.value)} autoFocus
                  placeholder="Choose a username" className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Email (optional)</label>
                <input type="email" value={setupEmail} onChange={(e) => setSetupEmail(e.target.value)}
                  placeholder="admin@yourshop.com" className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              <div>
                <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Password</label>
                <input type="password" value={setupPassword} onChange={(e) => setSetupPassword(e.target.value)}
                  placeholder="Min 8 characters" className="w-full rounded-xl border border-surface-300 bg-white px-4 py-3 text-sm outline-none transition-colors focus:border-primary-500 focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              {error && <p className="text-sm text-red-600 dark:text-red-400">{error}</p>}
              <button type="submit" disabled={loading}
                className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary-600 px-4 py-3 text-sm font-semibold text-white transition-colors hover:bg-primary-700 focus:ring-2 focus:ring-primary-500/50 disabled:opacity-50">
                {loading ? <Loader2 className="h-4 w-4 animate-spin" /> : <KeyRound className="h-4 w-4" />}
                Create Account & Continue
              </button>
            </form>
          )}
          {step === 'password' && (
            <form onSubmit={handlePassword} className="space-y-4" noValidate>
              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Username or email</label>
                <input type="text" value={username} onChange={(e) => { setUsername(e.target.value); setFieldErrors(prev => ({ ...prev, username: undefined })); }} autoFocus autoComplete="username"
                  placeholder="admin or admin@yourshop.com"
                  className={`w-full rounded-lg border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ${fieldErrors.username ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`} />
                {fieldErrors.username && <p className="mt-1 text-xs text-red-500">{fieldErrors.username}</p>}
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Password</label>
                <div className="relative">
                  <input type={showPassword ? 'text' : 'password'} value={password} onChange={(e) => { setPassword(e.target.value); setFieldErrors(prev => ({ ...prev, password: undefined })); }} autoComplete="current-password"
                    className={`w-full rounded-lg border bg-surface-50 px-4 py-3 pr-11 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ${fieldErrors.password ? 'border-red-400 dark:border-red-500' : 'border-surface-300 dark:border-surface-600'}`} />
                  <button type="button" onClick={() => setShowPassword(!showPassword)} tabIndex={-1}
                    className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300">
                    {showPassword ? <EyeOff className="h-4.5 w-4.5" /> : <Eye className="h-4.5 w-4.5" />}
                  </button>
                </div>
                {fieldErrors.password && <p className="mt-1 text-xs text-red-500">{fieldErrors.password}</p>}
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
                        <input
                          type="email"
                          value={forgotEmail}
                          onChange={(e) => setForgotEmail(e.target.value)}
                          placeholder="your@email.com"
                          className="flex-1 rounded-lg border border-surface-300 bg-white px-3 py-1.5 text-xs text-surface-900 focus:border-primary-500 focus:outline-none dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
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
              <div className="flex items-center gap-3 rounded-lg bg-blue-50 p-3 dark:bg-blue-950/30">
                <KeyRound className="h-5 w-5 shrink-0 text-blue-600" />
                <p className="text-xs text-blue-800 dark:text-blue-300">
                  Welcome! Create a secure password for your account.
                </p>
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">New Password</label>
                <input type="password" value={newPassword} onChange={(e) => setNewPassword(e.target.value)} autoFocus required minLength={8}
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              </div>
              <div>
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Confirm Password</label>
                <input type="password" value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)} required minLength={8}
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
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
                <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">Enter 6-digit code to verify</label>
                <input ref={codeRef} type="text" inputMode="numeric" pattern="[0-9]*" maxLength={6}
                  value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, ''))}
                  placeholder="000000" autoFocus
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl font-mono tracking-[0.5em] text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
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
              <input ref={codeRef} type="text" inputMode="numeric" pattern="[0-9]*" maxLength={6}
                value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, ''))}
                placeholder="000000" autoFocus
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-center text-2xl font-mono tracking-[0.5em] text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100" />
              {error && <p className="text-sm text-red-500">{error}</p>}
              <label className="flex items-center gap-2 cursor-pointer">
                <input
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
