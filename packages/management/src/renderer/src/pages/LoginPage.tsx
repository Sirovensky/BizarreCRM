import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { Server, AlertCircle, Play, Loader2, Shield, KeyRound, X, UserPlus, Eye, EyeOff, FileText, RefreshCw } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { useAuthStore } from '@/stores/authStore';
import { PASSWORD_MIN_LENGTH } from '@/utils/constants';

type LoginStep = 'loading' | 'setup' | 'login' | '2fa-setup' | '2fa-verify' | 'set-password';

const LOG_FILE_ORDER = [
  'bizarre-crm.err.log',
  'bizarre-crm.out.log',
  'bizarre-crm.direct.err.log',
  'bizarre-crm.direct.out.log',
] as const;

export function LoginPage() {
  const navigate = useNavigate();
  const loginSuccess = useAuthStore((s) => s.loginSuccess);

  const [step, setStep] = useState<LoginStep>('loading');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [totpCode, setTotpCode] = useState('');
  const [challengeToken, setChallengeToken] = useState('');
  const [qrCode, setQrCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [serverOffline, setServerOffline] = useState(false);
  const [starting, setStarting] = useState(false);
  const [showLogs, setShowLogs] = useState(false);
  const [logsLoading, setLogsLoading] = useState(false);
  const [selectedLog, setSelectedLog] = useState<string>(LOG_FILE_ORDER[0]);
  const [logContent, setLogContent] = useState('');
  const [logError, setLogError] = useState('');
  // DASH-ELEC-164: SettingsPage already has show-password toggles; mirror the
  // pattern on the first-run set-password step so operators typing a 10+ char
  // password against an OS-level password manager can verify before submit.
  const [showNew, setShowNew] = useState(false);
  const [showConfirm, setShowConfirm] = useState(false);
  // FIXED-by-Fixer-A21 (DASH-ELEC-247): surface server-issued TOTP recovery
  // codes during first-run 2FA setup so a lost authenticator device doesn't
  // permanently lock out the sole super-admin. Backwards-compatible: if the
  // server response omits `recoveryCodes`, the UI block is hidden.
  const [recoveryCodes, setRecoveryCodes] = useState<string[]>([]);
  const [codesAck, setCodesAck] = useState(false);

  // Check setup status on mount
  useEffect(() => {
    checkSetupStatus();
  }, []);

  const checkSetupStatus = async (autoStart = true) => {
    try {
      const res = await getAPI().management.setupStatus();
      if (res.success && res.data) {
        setServerOffline(false);
        setStep(res.data.needsSetup ? 'setup' : 'login');
        return;
      } else if (res.offline && autoStart) {
        // Server not running — try to start it automatically
        setServerOffline(true);
        setError('Server not running — starting it now...');
        setStarting(true);
        try {
          await getAPI().service.start();
        } catch { /* may fail if no service installed — that's ok */ }
        // Wait and retry a few times
        for (let i = 0; i < 10; i++) {
          await new Promise(r => setTimeout(r, 3000));
          try {
            const retry = await getAPI().management.setupStatus();
            if (retry.success && retry.data) {
              setServerOffline(false);
              setError('');
              setStarting(false);
              setStep(retry.data.needsSetup ? 'setup' : 'login');
              return;
            }
          } catch { /* still starting */ }
        }
        setStarting(false);
        setError('Could not reach server. Start it manually, then reopen the dashboard.');
      } else if (res.offline) {
        setServerOffline(true);
      }
    } catch {
      setServerOffline(true);
    }
    setStep('login');
  };

  const handleSetup = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username.trim() || username.trim().length < 3) { setError('Username must be at least 3 characters'); return; }
    // FIXED-by-Fixer-A21 (DASH-ELEC-055): align first-run setup with set-password
    // policy (min 10 chars). Prevents inconsistent password strength between
    // setup and forced-change flows.
    if (!password || password.length < PASSWORD_MIN_LENGTH) { setError(`Password must be at least ${PASSWORD_MIN_LENGTH} characters`); return; }

    setLoading(true);
    setError('');

    try {
      const res = await getAPI().management.setup(username.trim(), password);
      if (res.success) {
        setStep('login');
        setPassword('');
        setError('');
      } else {
        setError(res.message ?? 'Setup failed');
      }
    } catch {
      setError('Setup failed — server not reachable');
    } finally {
      setLoading(false);
    }
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!username.trim() || !password) return;

    setLoading(true);
    setError('');
    setServerOffline(false);

    try {
      const api = getAPI();
      const res = await api.superAdmin.login(username.trim(), password);

      if (res.offline) {
        setServerOffline(true);
        setError('Server not reachable');
        return;
      }

      if (!res.success) {
        setError(res.message ?? 'Login failed');
        return;
      }

      // DASH-ELEC-267 (Fixer-C24 2026-04-25): bridge.ts now parameterises
      // login + setup2fa response shapes, so the cast is no longer needed.
      const data = res.data;

      if (data?.challengeToken) {
        setChallengeToken(data.challengeToken);

        if (data.requiresPasswordSetup) {
          setStep('set-password');
        } else if (data.requires2faSetup) {
          // Auto-trigger 2FA setup
          const setupRes = await api.superAdmin.setup2fa(data.challengeToken);
          if (setupRes.success && setupRes.data) {
            const setupData = setupRes.data;
            setQrCode(setupData.qr ?? '');
            if (setupData.challengeToken) setChallengeToken(setupData.challengeToken);
            // FIXED-by-Fixer-A21 (DASH-ELEC-247)
            if (Array.isArray(setupData.recoveryCodes)) setRecoveryCodes(setupData.recoveryCodes);
          }
          setStep('2fa-setup');
        } else if (data.totpEnabled) {
          setStep('2fa-verify');
        }
      }
    } catch (err) {
      setServerOffline(true);
      setError(err instanceof Error ? err.message : 'Server not reachable');
    } finally {
      setLoading(false);
    }
  };

  const handleSetPassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword.length < PASSWORD_MIN_LENGTH) {
      setError(`Password must be at least ${PASSWORD_MIN_LENGTH} characters`);
      return;
    }
    if (newPassword !== confirmPassword) {
      setError('Passwords do not match');
      return;
    }

    setLoading(true);
    setError('');

    try {
      const res = await getAPI().superAdmin.setPassword(challengeToken, newPassword);
      if (res.success) {
        // DASH-ELEC-267 (Fixer-C24 2026-04-25): bridge typings now carry these
        // optional fields directly — drop the cast.
        const data = res.data;
        if (data?.challengeToken) setChallengeToken(data.challengeToken);
        // Now set up 2FA
        const setupRes = await getAPI().superAdmin.setup2fa(data?.challengeToken ?? challengeToken);
        if (setupRes.success && setupRes.data) {
          const setupData = setupRes.data;
          setQrCode(setupData.qr ?? '');
          if (setupData.challengeToken) setChallengeToken(setupData.challengeToken);
          // FIXED-by-Fixer-A21 (DASH-ELEC-247)
          if (Array.isArray(setupData.recoveryCodes)) setRecoveryCodes(setupData.recoveryCodes);
        }
        setStep('2fa-setup');
      } else {
        setError(res.message ?? 'Failed to set password');
      }
    } catch {
      setError('Failed to set password');
    } finally {
      setLoading(false);
    }
  };

  const handleVerify2fa = async (e: React.FormEvent) => {
    e.preventDefault();
    if (totpCode.length !== 6) return;

    setLoading(true);
    setError('');

    try {
      const res = await getAPI().superAdmin.verify2fa(challengeToken, totpCode);
      if (res.success) {
        // @audit-fixed: previously the plaintext `password`, `newPassword`,
        // `confirmPassword`, `totpCode`, and `challengeToken` were left in
        // React state after a successful 2FA login — they sat in memory
        // until the user navigated to a new page or hard-refreshed, which
        // gave any injected script (or a curious user with DevTools open
        // in dev) easy access to the credentials. We now zero out every
        // sensitive field BEFORE the navigate() so the LoginPage component
        // unmounts with a clean slate.
        const trimmedUsername = username.trim();
        setPassword('');
        setNewPassword('');
        setConfirmPassword('');
        setTotpCode('');
        setChallengeToken('');
        setQrCode('');
        // FIXED-by-Fixer-A21 (DASH-ELEC-247): wipe recovery codes from React
        // state on success — if the operator failed to copy them, that's on
        // them; we won't keep secrets in memory after the dashboard is in.
        setRecoveryCodes([]);
        setCodesAck(false);
        loginSuccess('super-admin', trimmedUsername);
        navigate('/', { replace: true });
      } else {
        setError(res.message ?? 'Invalid code');
        setTotpCode('');
      }
    } catch {
      setError('Verification failed');
    } finally {
      setLoading(false);
    }
  };

  const handleStartServer = async () => {
    setStarting(true);
    setError('');
    try {
      // @audit-fixed: previously this only caught thrown errors. The
      // service.start() IPC handler returns { success: false, output }
      // (does NOT throw) when sc.exe / pm2 fails to start the server, so
      // any failure was reported as "Server starting...". Now we check
      // the response envelope and surface the failure message verbatim.
      const res = await getAPI().service.start() as
        { success?: boolean; output?: string; message?: string } | undefined;
      if (res && typeof res === 'object' && 'success' in res && res.success === false) {
        setError(res.message ?? res.output ?? 'Failed to start server');
        return;
      }
      setError('Server starting... try again in a few seconds.');
      setServerOffline(false);
      setTimeout(checkSetupStatus, 5000);
    } catch {
      setError('Failed to start server');
    } finally {
      setStarting(false);
    }
  };

  const refreshServerLogs = async (preferredName = selectedLog, showSpinner = true) => {
    if (showSpinner) setLogsLoading(true);
    setLogError('');
    try {
      const filesRes = await getAPI().admin.listLogs();
      if (!filesRes.success || !filesRes.data) {
        setLogError(filesRes.message ?? 'Could not list server logs');
        return;
      }

      const files = filesRes.data.files ?? [];
      const existing = files.filter((file) => file.exists);
      const preferredExists = existing.some((file) => file.name === preferredName);
      const chosen =
        preferredExists
          ? preferredName
          : LOG_FILE_ORDER.find((name) => existing.some((file) => file.name === name));

      if (!chosen) {
        setSelectedLog(LOG_FILE_ORDER[0]);
        setLogContent('No server log files found yet.');
        return;
      }

      setSelectedLog(chosen);
      const tailRes = await getAPI().admin.tailLog({ name: chosen, lines: 400 });
      if (!tailRes.success || !tailRes.data) {
        setLogError(tailRes.message ?? 'Could not read server logs');
        return;
      }
      setLogContent(tailRes.data.content || 'Log file is empty.');
    } catch {
      setLogError('Could not read server logs');
    } finally {
      if (showSpinner) setLogsLoading(false);
    }
  };

  const handleViewLogs = async () => {
    const next = !showLogs;
    setShowLogs(next);
    if (next) await refreshServerLogs(selectedLog);
  };

  useEffect(() => {
    if (!showLogs) return;
    const id = window.setInterval(() => {
      void refreshServerLogs(selectedLog, false);
    }, 2500);
    return () => window.clearInterval(id);
  }, [showLogs, selectedLog]);

  if (step === 'loading') {
    return (
      <div className="flex items-center justify-center min-h-screen bg-surface-950">
        <Loader2 className="w-6 h-6 text-accent-400 animate-spin" />
      </div>
    );
  }

  return (
    <div className="flex items-center justify-center min-h-screen bg-surface-950">
      <div className={`${showLogs ? 'w-[min(92vw,720px)]' : 'w-[400px]'} bg-surface-900 border border-surface-800 rounded-xl p-8 shadow-2xl`}>
        {/* Header */}
        <div className="flex items-center gap-3 mb-6">
          <div className="w-10 h-10 rounded-lg bg-accent-600/20 flex items-center justify-center">
            <Server className="w-5 h-5 text-accent-400" />
          </div>
          <div>
            <h1 className="text-lg font-bold text-surface-100">Server Dashboard</h1>
            <p className="text-xs text-surface-500">
              {step === 'setup' && 'Create your admin account to get started'}
              {step === 'login' && 'Super admin login (2FA required)'}
              {step === 'set-password' && 'Set your password (min 10 characters)'}
              {step === '2fa-setup' && 'Scan QR code with Google Authenticator'}
              {step === '2fa-verify' && 'Enter your 2FA code'}
            </p>
          </div>
        </div>

        {/* Error — DASH-ELEC-284: role="alert" so AT announces on mount/update */}
        {error && (
          <div className="mb-4">
            <div role="alert" className="flex items-start gap-2 p-3 rounded-lg bg-red-950/40 border border-red-900/50 text-red-400 text-xs">
              <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" aria-hidden="true" />
              <span>{error}</span>
            </div>
            {serverOffline && (
              <div className="mt-2 grid grid-cols-2 gap-2">
                <button
                  type="button"
                  onClick={handleStartServer}
                  disabled={starting}
                  className="flex items-center justify-center gap-2 px-4 py-2 bg-green-600/20 text-green-400 text-xs font-medium border border-green-800/50 rounded-lg hover:bg-green-600/30 disabled:opacity-50 transition-colors"
                >
                  {starting ? (
                    <><Loader2 className="w-3.5 h-3.5 animate-spin" /> Starting...</>
                  ) : (
                    <><Play className="w-3.5 h-3.5" /> Start Server</>
                  )}
                </button>
                <button
                  type="button"
                  onClick={handleViewLogs}
                  className="flex items-center justify-center gap-2 px-4 py-2 bg-surface-800 text-surface-200 text-xs font-medium border border-surface-700 rounded-lg hover:bg-surface-700 transition-colors"
                >
                  <FileText className="w-3.5 h-3.5" />
                  {showLogs ? 'Hide Logs' : 'See Logs'}
                </button>
              </div>
            )}
            {serverOffline && showLogs && (
              <div className="mt-3 rounded-lg border border-surface-700 bg-surface-950 overflow-hidden">
                <div className="flex items-center justify-between gap-2 px-3 py-2 border-b border-surface-800">
                  <div className="flex items-center gap-2 min-w-0 text-xs text-surface-300">
                    <FileText className="w-3.5 h-3.5 flex-shrink-0" />
                    <span className="truncate">{selectedLog}</span>
                  </div>
                  <button
                    type="button"
                    onClick={() => void refreshServerLogs(selectedLog)}
                    disabled={logsLoading}
                    className="flex items-center gap-1.5 px-2 py-1 text-[11px] text-surface-300 hover:text-surface-100 hover:bg-surface-800 rounded disabled:opacity-50"
                  >
                    {logsLoading ? <Loader2 className="w-3 h-3 animate-spin" /> : <RefreshCw className="w-3 h-3" />}
                    Refresh
                  </button>
                </div>
                {logError ? (
                  <div className="p-3 text-xs text-red-300">{logError}</div>
                ) : (
                  <pre className="h-56 overflow-auto p-3 text-[11px] leading-relaxed text-surface-300 whitespace-pre-wrap break-words font-mono">
                    {logsLoading && !logContent ? 'Loading logs...' : logContent}
                  </pre>
                )}
              </div>
            )}
          </div>
        )}

        {/* Step: First-run setup — create admin account */}
        {step === 'setup' && (
          <form onSubmit={handleSetup}>
            <div className="mb-4 p-3 rounded-lg bg-accent-950/40 border border-accent-800/30 text-accent-300 text-xs">
              Welcome! Create your super admin account to manage the server.
            </div>
            <div className="space-y-3 mb-5">
              <input
                type="text" value={username} onChange={(e) => setUsername(e.target.value)}
                placeholder="Choose a username (min 3 chars)" autoComplete="username" autoFocus
                maxLength={256}
                aria-label="Choose a username (minimum 3 characters)"
                className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
              />
              <input
                type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                placeholder="Choose a password (min 10 chars)"
                maxLength={1024}
                autoComplete="new-password"
                aria-label="Choose a password (minimum 10 characters)"
                className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
              />
            </div>
            <button
              type="submit" disabled={loading || username.trim().length < 3 || password.length < PASSWORD_MIN_LENGTH}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent-600 text-white text-sm font-semibold rounded-lg hover:bg-accent-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <UserPlus className="w-4 h-4" />
              {loading ? 'Creating account...' : 'Create Account & Continue'}
            </button>
          </form>
        )}

        {/* Step: Login */}
        {step === 'login' && (
          <form onSubmit={handleLogin}>
            <div className="space-y-3 mb-5">
              <input
                type="text" value={username} onChange={(e) => setUsername(e.target.value)}
                placeholder="Username" autoComplete="username" autoFocus
                maxLength={256}
                aria-label="Username"
                className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
              />
              <input
                type="password" value={password} onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                maxLength={1024}
                autoComplete="current-password"
                aria-label="Password"
                className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
              />
            </div>
            <button
              type="submit" disabled={loading || !username.trim() || !password}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent-600 text-white text-sm font-semibold rounded-lg hover:bg-accent-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <Shield className="w-4 h-4" />
              {loading ? 'Authenticating...' : 'Log In'}
            </button>
          </form>
        )}

        {/* Step: Set Password (first run) */}
        {step === 'set-password' && (
          <form onSubmit={handleSetPassword}>
            <div className="space-y-3 mb-5">
              <div className="relative">
                <input
                  type={showNew ? 'text' : 'password'} value={newPassword} onChange={(e) => setNewPassword(e.target.value)}
                  placeholder="New password (min 10 characters)" autoFocus
                  autoComplete="new-password"
                  aria-label="New password (minimum 10 characters)"
                  className="w-full px-3.5 py-2.5 pr-10 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
                />
                <button
                  type="button"
                  onClick={() => setShowNew((v) => !v)}
                  aria-label={showNew ? 'Hide password' : 'Show password'}
                  aria-pressed={showNew}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 text-surface-500 hover:text-surface-200"
                >
                  {showNew ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              <div className="relative">
                <input
                  type={showConfirm ? 'text' : 'password'} value={confirmPassword} onChange={(e) => setConfirmPassword(e.target.value)}
                  placeholder="Confirm password"
                  autoComplete="new-password"
                  aria-label="Confirm password"
                  className="w-full px-3.5 py-2.5 pr-10 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors"
                />
                <button
                  type="button"
                  onClick={() => setShowConfirm((v) => !v)}
                  aria-label={showConfirm ? 'Hide password' : 'Show password'}
                  aria-pressed={showConfirm}
                  className="absolute right-2 top-1/2 -translate-y-1/2 p-1.5 text-surface-500 hover:text-surface-200"
                >
                  {showConfirm ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
            </div>
            <button
              type="submit" disabled={loading || newPassword.length < PASSWORD_MIN_LENGTH || newPassword !== confirmPassword}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent-600 text-white text-sm font-semibold rounded-lg hover:bg-accent-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {loading ? 'Setting password...' : 'Set Password & Continue'}
            </button>
          </form>
        )}

        {/* Step: 2FA Setup */}
        {step === '2fa-setup' && (
          <form onSubmit={handleVerify2fa}>
            {/* DASH-ELEC-094: bg-white scoped to <img> only — outer card uses surface token */}
            {/* DASH-ELEC-061: validate qrCode is a data:image URI before rendering — a
                compromised server returning `javascript:` or `data:text/html` would
                otherwise execute in the renderer's origin via <img src=…>. */}
            {qrCode && qrCode.startsWith('data:image/') && (
              <div className="flex justify-center mb-4 p-4 bg-surface-800 rounded-lg">
                <img src={qrCode} alt="2FA QR Code" className="w-48 h-48 bg-white p-1 rounded" />
              </div>
            )}
            <p className="text-xs text-surface-400 mb-4 text-center">
              Scan the QR code with Google Authenticator, then enter the 6-digit code below.
            </p>
            {/* FIXED-by-Fixer-A21 (DASH-ELEC-247): one-time recovery codes for
                lost-device fallback. Renders only when server response carries
                `recoveryCodes`; otherwise this block stays hidden and the flow
                is unchanged. Operator must check the ack box before verify is
                enabled. */}
            {recoveryCodes.length > 0 && (
              <div className="mb-4 p-3 rounded-lg bg-amber-950/40 border border-amber-800/40">
                <div className="flex items-center gap-2 mb-2 text-amber-300 text-xs font-semibold">
                  <Shield className="w-3.5 h-3.5" />
                  Save these recovery codes — shown only once
                </div>
                <p className="text-[11px] text-amber-200/80 mb-2 leading-snug">
                  Store them in a password manager or print them. Each can be used
                  exactly once if you lose your authenticator device.
                </p>
                <div className="grid grid-cols-2 gap-1.5 mb-2 font-mono text-[11px] text-surface-100 bg-surface-950 rounded-md p-2 border border-surface-800">
                  {recoveryCodes.map((c) => (
                    <div key={c} className="select-all tracking-wider">{c}</div>
                  ))}
                </div>
                <div className="flex items-center justify-between gap-2">
                  <div className="flex items-center gap-3">
                    <button
                      type="button"
                      onClick={() => {
                        void navigator.clipboard?.writeText(recoveryCodes.join('\n'));
                      }}
                      className="text-[11px] text-amber-300 hover:text-amber-200 underline-offset-2 hover:underline"
                    >
                      Copy all
                    </button>
                    {/* FIXED-by-Fixer-A27 2026-04-25 (DASH-ELEC-247): Copy-all
                        alone fails when clipboard is denied (locked-down kiosks
                        often disable it) and leaves no offline artifact when the
                        super-admin can't reach a password manager. Download
                        emits a plain-text file the operator can drop on a USB
                        stick / print, satisfying the "print them" guidance in
                        the help line above. Filename includes ISO date so
                        multiple resets don't overwrite each other. Object URL
                        is revoked synchronously after the click to avoid
                        retaining the codes in the renderer's blob store. */}
                    <button
                      type="button"
                      onClick={() => {
                        const stamp = new Date().toISOString().slice(0, 10);
                        const blob = new Blob(
                          [
                            `BizarreCRM super-admin 2FA recovery codes\n`,
                            `Generated: ${new Date().toISOString()}\n`,
                            `Each code can be used exactly once if you lose your authenticator.\n`,
                            `Store this file securely — anyone with these codes can bypass 2FA.\n\n`,
                            recoveryCodes.join('\n'),
                            '\n',
                          ],
                          { type: 'text/plain;charset=utf-8' },
                        );
                        const url = URL.createObjectURL(blob);
                        const a = document.createElement('a');
                        a.href = url;
                        a.download = `bizarrecrm-recovery-codes-${stamp}.txt`;
                        document.body.appendChild(a);
                        a.click();
                        a.remove();
                        URL.revokeObjectURL(url);
                      }}
                      className="text-[11px] text-amber-300 hover:text-amber-200 underline-offset-2 hover:underline"
                    >
                      Download .txt
                    </button>
                  </div>
                  <label className="flex items-center gap-1.5 text-[11px] text-amber-200 cursor-pointer">
                    <input
                      type="checkbox"
                      checked={codesAck}
                      onChange={(e) => setCodesAck(e.target.checked)}
                      className="accent-amber-500"
                    />
                    I have saved them
                  </label>
                </div>
              </div>
            )}
            <input
              type="text" value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="6-digit code" autoFocus maxLength={6}
              autoComplete="one-time-code"
              aria-label="6-digit authenticator code"
              className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 text-center tracking-[0.3em] font-mono placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors mb-4"
            />
            <button
              type="submit"
              disabled={loading || totpCode.length !== 6 || (recoveryCodes.length > 0 && !codesAck)}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent-600 text-white text-sm font-semibold rounded-lg hover:bg-accent-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <KeyRound className="w-4 h-4" />
              {loading ? 'Verifying...' : 'Verify & Complete Setup'}
            </button>
          </form>
        )}

        {/* Step: 2FA Verify (returning user) */}
        {step === '2fa-verify' && (
          <form onSubmit={handleVerify2fa}>
            <p className="text-xs text-surface-400 mb-4 text-center">
              Enter the 6-digit code from your authenticator app.
            </p>
            <input
              type="text" value={totpCode} onChange={(e) => setTotpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
              placeholder="000000" autoFocus maxLength={6}
              autoComplete="one-time-code"
              aria-label="6-digit authenticator code"
              className="w-full px-3.5 py-2.5 bg-surface-950 border border-surface-700 rounded-lg text-sm text-surface-100 text-center tracking-[0.3em] font-mono placeholder:text-surface-400 focus:border-accent-500 focus:outline-none transition-colors mb-4"
            />
            <button
              type="submit" disabled={loading || totpCode.length !== 6}
              className="w-full flex items-center justify-center gap-2 px-4 py-2.5 bg-accent-600 text-white text-sm font-semibold rounded-lg hover:bg-accent-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              <KeyRound className="w-4 h-4" />
              {loading ? 'Verifying...' : 'Verify'}
            </button>
          </form>
        )}

        {/* Exit button — closes dashboard only, server keeps running */}
        <div className="mt-5 pt-4 border-t border-surface-800 flex justify-end">
          <button
            type="button"
            onClick={() => getAPI().system.closeDashboard()}
            className="flex items-center gap-1.5 px-3 py-1.5 text-xs text-surface-500 hover:text-surface-300 hover:bg-surface-800 rounded-md transition-colors"
            title="Close dashboard (server keeps running)"
          >
            <X className="w-3.5 h-3.5" />
            Exit Dashboard
          </button>
        </div>
      </div>
    </div>
  );
}
