import { useState } from 'react';
import * as api from './portalApi';

function mapRegisterError(err: unknown): string {
  const status = (err as { response?: { status?: number } })?.response?.status;
  if (status === 400) return 'Invalid information — please check your inputs';
  if (status === 401) return 'Registration failed — please try again';
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

  async function handleSendCode(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (phone.replace(/\D/g, '').length < 10) {
      setError('Please enter a valid phone number');
      return;
    }
    setLoading(true);
    try {
      await api.sendVerificationCode(phone.trim());
      setStep('code');
    } catch (err: unknown) {
      setError(mapRegisterError(err));
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
          <h2 className="text-xl font-bold text-surface-900 dark:text-surface-100 mb-1">Create Account</h2>
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
                  step === s ? 'bg-primary-600 text-primary-950' :
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
            <div className="mb-4 rounded-lg bg-red-50 dark:bg-red-900/20 border border-red-200 dark:border-red-800 px-4 py-3 text-sm text-red-700 dark:text-red-300">
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
                  placeholder="(303) 555-1234"
                  value={phone}
                  onChange={e => setPhone(e.target.value)}
                  className="w-full rounded-lg border border-surface-300 dark:border-surface-600 bg-white dark:bg-surface-900 px-4 py-2.5 text-sm text-surface-900 dark:text-surface-100 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                  autoComplete="tel"
                />
              </div>
              <button
                type="submit"
                disabled={loading}
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 transition-colors"
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
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 transition-colors"
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
                className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 transition-colors"
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
