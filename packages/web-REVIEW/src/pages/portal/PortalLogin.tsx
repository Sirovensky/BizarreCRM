import { useState } from 'react';
import * as api from './portalApi';

interface PortalLoginProps {
  onQuickTrack: (token: string, ticket: api.TicketDetail) => void;
  onFullLogin: (token: string, customerName: string) => void;
  onRegister: () => void;
  storeName: string;
  storeLogo: string | null;
  isWidget?: boolean;
}

type Tab = 'track' | 'signin';

export function PortalLogin({ onQuickTrack, onFullLogin, onRegister, storeName, storeLogo, isWidget }: PortalLoginProps) {
  const [tab, setTab] = useState<Tab>('track');
  const [orderId, setOrderId] = useState('');
  const [phoneLast4, setPhoneLast4] = useState('');
  const [phone, setPhone] = useState('');
  const [pin, setPin] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // WEB-FC-024: read server's Retry-After (seconds) and surface a concrete countdown
  function retryAfterMessage(err: unknown, fallback: string): string {
    const headers = (err as any)?.response?.headers ?? {};
    const raw = headers['retry-after'] ?? headers['Retry-After'];
    const secs = raw ? parseInt(String(raw), 10) : NaN;
    if (Number.isFinite(secs) && secs > 0) {
      if (secs < 60) return `Too many attempts. Please try again in ${secs}s.`;
      const mins = Math.ceil(secs / 60);
      return `Too many attempts. Please try again in ${mins} minute${mins === 1 ? '' : 's'}.`;
    }
    return fallback;
  }

  async function handleQuickTrack(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!orderId.trim() || phoneLast4.length !== 4) {
      setError('Please enter your ticket ID and last 4 digits of your phone number');
      return;
    }
    setLoading(true);
    try {
      const result = await api.quickTrack(orderId.trim(), phoneLast4);
      onQuickTrack(result.token, result.ticket);
    } catch (err: unknown) {
      const status = (err as any)?.response?.status;
      if (!status) {
        setError('Unable to connect. Please check your internet connection.');
      } else if (status === 404) {
        setError('No matching repair found. Please check your details.');
      } else if (status === 429) {
        setError(retryAfterMessage(err, 'Too many attempts. Please wait a minute before trying again.'));
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  async function handleSignIn(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    // WEB-S4-020: strip non-digits before submit so backend receives a normalized phone
    const phoneDigits = phone.replace(/\D/g, '');
    if (!phoneDigits || pin.length !== 4) {
      setError('Please enter your phone number and 4-digit PIN');
      return;
    }
    setLoading(true);
    try {
      const result = await api.portalLogin(phoneDigits, pin);
      onFullLogin(result.token, result.customer.first_name);
    } catch (err: unknown) {
      const status = (err as any)?.response?.status;
      if (!status) {
        setError('Unable to connect. Please check your internet connection.');
      } else if (status === 401) {
        setError('Invalid credentials. Please try again.');
      } else if (status === 429) {
        setError(retryAfterMessage(err, 'Too many attempts. Please try again later.'));
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className={`flex flex-col items-center ${isWidget ? 'px-4 py-3' : 'min-h-screen bg-surface-50 dark:bg-surface-950 px-4 py-8'}`}>
      {!isWidget && (
        <div className="mb-6 text-center">
          {storeLogo ? (
            <img src={storeLogo} alt={storeName} className="mx-auto mb-3 h-16 object-contain" />
          ) : (
            <div className="mx-auto mb-3 flex h-16 w-16 items-center justify-center rounded-full bg-primary-600 text-primary-950 text-2xl font-bold">
              {storeName.charAt(0)}
            </div>
          )}
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">{storeName}</h1>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">Check your repair status or manage your account</p>
        </div>
      )}

      <div className={`w-full ${isWidget ? '' : 'max-w-md'}`}>
        <div className="rounded-xl bg-white dark:bg-surface-900 shadow-sm border border-surface-200 dark:border-surface-700 overflow-hidden">
          {/* Tab bar */}
          <div className="flex border-b border-surface-200 dark:border-surface-700">
            <button
              onClick={() => { setTab('track'); setError(''); }}
              className={`flex-1 py-3 text-sm font-medium transition-colors ${
                tab === 'track'
                  ? 'text-primary-600 dark:text-primary-400 border-b-2 border-primary-600 bg-primary-50/50 dark:bg-primary-900/20'
                  : 'text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-200'
              }`}
            >
              Track Repair
            </button>
            <button
              onClick={() => { setTab('signin'); setError(''); }}
              className={`flex-1 py-3 text-sm font-medium transition-colors ${
                tab === 'signin'
                  ? 'text-primary-600 dark:text-primary-400 border-b-2 border-primary-600 bg-primary-50/50 dark:bg-primary-900/20'
                  : 'text-surface-500 dark:text-surface-400 hover:text-surface-700 dark:hover:text-surface-200'
              }`}
            >
              Sign In
            </button>
          </div>

          <div className="p-5">
            {error && (
              <div id="portal-login-error" role="alert" className="mb-4 rounded-lg bg-red-50 dark:bg-red-900/30 border border-red-200 dark:border-red-700 px-4 py-3 text-sm text-red-700 dark:text-red-300">
                {error}
              </div>
            )}

            {tab === 'track' ? (
              <form onSubmit={handleQuickTrack} className="space-y-4">
                <div>
                  <label htmlFor="portal-order-id" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                    Ticket ID
                  </label>
                  <input
                    id="portal-order-id"
                    type="text"
                    placeholder="e.g. T-1042 or 1042"
                    value={orderId}
                    onChange={e => setOrderId(e.target.value)}
                    aria-invalid={!!error}
                    aria-describedby={error ? 'portal-login-error' : undefined}
                    className="w-full rounded-lg border border-surface-300 dark:border-surface-600 dark:bg-surface-800 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="off"
                  />
                </div>
                <div>
                  <label htmlFor="portal-phone-last4" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                    Last 4 digits of your phone
                  </label>
                  <input
                    id="portal-phone-last4"
                    type="tel"
                    placeholder="e.g. 1234"
                    maxLength={4}
                    value={phoneLast4}
                    onChange={e => setPhoneLast4(e.target.value.replace(/\D/g, '').slice(0, 4))}
                    aria-invalid={!!error}
                    aria-describedby={error ? 'portal-login-error' : undefined}
                    className="w-full rounded-lg border border-surface-300 dark:border-surface-600 dark:bg-surface-800 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="off"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
                >
                  {loading ? 'Looking up...' : 'Track My Repair'}
                </button>
              </form>
            ) : (
              <form onSubmit={handleSignIn} className="space-y-4">
                <div>
                  <label htmlFor="portal-phone" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                    Phone Number
                  </label>
                  <input
                    id="portal-phone"
                    type="tel"
                    placeholder="(303) 555-1234"
                    value={phone}
                    onChange={e => setPhone(e.target.value)}
                    aria-invalid={!!error}
                    aria-describedby={error ? 'portal-login-error' : undefined}
                    className="w-full rounded-lg border border-surface-300 dark:border-surface-600 dark:bg-surface-800 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="tel"
                  />
                </div>
                <div>
                  <label htmlFor="portal-pin" className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
                    4-Digit PIN
                  </label>
                  <input
                    id="portal-pin"
                    type="password"
                    inputMode="numeric"
                    pattern="[0-9]*"
                    placeholder="****"
                    maxLength={4}
                    value={pin}
                    onChange={e => setPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                    aria-invalid={!!error}
                    aria-describedby={error ? 'portal-login-error' : undefined}
                    className="w-full rounded-lg border border-surface-300 dark:border-surface-600 dark:bg-surface-800 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 tracking-widest focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    /* WEB-FK-008 (Fixer-A15 2026-04-25): tag PIN as
                       current-password so OS/browser password managers
                       can store + autofill it. With a 4-digit PIN, manual
                       entry is the worst case — every typed PIN is a
                       shoulder-surf chance. Letting 1Password/iCloud
                       Keychain fill it eliminates that vector and lets
                       users pick a unique 4-digit per-shop PIN instead
                       of reusing 1234/0000 across portals. */
                    autoComplete="current-password"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none transition-colors"
                >
                  {loading ? 'Signing in...' : 'Sign In'}
                </button>
                <p className="text-center text-xs text-surface-400 dark:text-surface-500 mt-2">
                  Don't have an account?{' '}
                  <button type="button" onClick={onRegister} className="text-primary-600 dark:text-primary-400 hover:underline">
                    Create one
                  </button>
                </p>
              </form>
            )}
          </div>
        </div>

        {!isWidget && (
          <p className="mt-4 text-center text-xs text-surface-400 dark:text-surface-500">
            Your ticket ID is on your receipt or in the SMS we sent when your repair was checked in.
          </p>
        )}
      </div>
    </div>
  );
}
