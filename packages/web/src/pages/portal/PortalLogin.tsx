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
        setError('Too many attempts. Please wait a minute before trying again.');
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
    if (!phone.trim() || pin.length !== 4) {
      setError('Please enter your phone number and 4-digit PIN');
      return;
    }
    setLoading(true);
    try {
      const result = await api.portalLogin(phone.trim(), pin);
      onFullLogin(result.token, result.customer.first_name);
    } catch (err: unknown) {
      const status = (err as any)?.response?.status;
      if (!status) {
        setError('Unable to connect. Please check your internet connection.');
      } else if (status === 401) {
        setError('Invalid credentials. Please try again.');
      } else if (status === 429) {
        setError('Too many attempts. Please try again later.');
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  return (
    <div className={`flex flex-col items-center ${isWidget ? 'px-4 py-3' : 'min-h-screen bg-gray-50 px-4 py-8'}`}>
      {!isWidget && (
        <div className="mb-6 text-center">
          {storeLogo ? (
            <img src={storeLogo} alt={storeName} className="mx-auto mb-3 h-16 object-contain" />
          ) : (
            <div className="mx-auto mb-3 flex h-16 w-16 items-center justify-center rounded-full bg-primary-600 text-white text-2xl font-bold">
              {storeName.charAt(0)}
            </div>
          )}
          <h1 className="text-2xl font-bold text-gray-900">{storeName}</h1>
          <p className="mt-1 text-sm text-gray-500">Check your repair status or manage your account</p>
        </div>
      )}

      <div className={`w-full ${isWidget ? '' : 'max-w-md'}`}>
        <div className="rounded-xl bg-white shadow-sm border border-gray-200 overflow-hidden">
          {/* Tab bar */}
          <div className="flex border-b border-gray-200">
            <button
              onClick={() => { setTab('track'); setError(''); }}
              className={`flex-1 py-3 text-sm font-medium transition-colors ${
                tab === 'track'
                  ? 'text-primary-600 border-b-2 border-primary-600 bg-primary-50/50'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Track Repair
            </button>
            <button
              onClick={() => { setTab('signin'); setError(''); }}
              className={`flex-1 py-3 text-sm font-medium transition-colors ${
                tab === 'signin'
                  ? 'text-primary-600 border-b-2 border-primary-600 bg-primary-50/50'
                  : 'text-gray-500 hover:text-gray-700'
              }`}
            >
              Sign In
            </button>
          </div>

          <div className="p-5">
            {error && (
              <div className="mb-4 rounded-lg bg-red-50 border border-red-200 px-4 py-3 text-sm text-red-700">
                {error}
              </div>
            )}

            {tab === 'track' ? (
              <form onSubmit={handleQuickTrack} className="space-y-4">
                <div>
                  <label htmlFor="orderId" className="block text-sm font-medium text-gray-700 mb-1">
                    Ticket ID
                  </label>
                  <input
                    id="orderId"
                    type="text"
                    placeholder="e.g. T-1042 or 1042"
                    value={orderId}
                    onChange={e => setOrderId(e.target.value)}
                    className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="off"
                  />
                </div>
                <div>
                  <label htmlFor="phoneLast4" className="block text-sm font-medium text-gray-700 mb-1">
                    Last 4 digits of your phone
                  </label>
                  <input
                    id="phoneLast4"
                    type="tel"
                    placeholder="e.g. 1234"
                    maxLength={4}
                    value={phoneLast4}
                    onChange={e => setPhoneLast4(e.target.value.replace(/\D/g, '').slice(0, 4))}
                    className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="off"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50 transition-colors"
                >
                  {loading ? 'Looking up...' : 'Track My Repair'}
                </button>
              </form>
            ) : (
              <form onSubmit={handleSignIn} className="space-y-4">
                <div>
                  <label htmlFor="phone" className="block text-sm font-medium text-gray-700 mb-1">
                    Phone Number
                  </label>
                  <input
                    id="phone"
                    type="tel"
                    placeholder="(303) 555-1234"
                    value={phone}
                    onChange={e => setPhone(e.target.value)}
                    className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-sm text-gray-900 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="tel"
                  />
                </div>
                <div>
                  <label htmlFor="pin" className="block text-sm font-medium text-gray-700 mb-1">
                    4-Digit PIN
                  </label>
                  <input
                    id="pin"
                    type="password"
                    placeholder="****"
                    maxLength={4}
                    value={pin}
                    onChange={e => setPin(e.target.value.replace(/\D/g, '').slice(0, 4))}
                    className="w-full rounded-lg border border-gray-300 px-4 py-2.5 text-sm text-gray-900 tracking-widest focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
                    autoComplete="off"
                  />
                </div>
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-white hover:bg-primary-700 disabled:opacity-50 transition-colors"
                >
                  {loading ? 'Signing in...' : 'Sign In'}
                </button>
                <p className="text-center text-xs text-gray-400 mt-2">
                  Don't have an account?{' '}
                  <button type="button" onClick={onRegister} className="text-primary-600 hover:underline">
                    Create one
                  </button>
                </p>
              </form>
            )}
          </div>
        </div>

        {!isWidget && (
          <p className="mt-4 text-center text-xs text-gray-400">
            Your ticket ID is on your receipt or in the SMS we sent when your repair was checked in.
          </p>
        )}
      </div>
    </div>
  );
}
