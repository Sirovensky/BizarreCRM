import { useState } from 'react';
import { useNavigate, Navigate } from 'react-router-dom';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { Store, MapPin, Phone, Mail, Clock, DollarSign, ArrowRight, Loader2, CheckCircle2, Smartphone, Download } from 'lucide-react';
import { settingsApi } from '@/api/endpoints';

const TIMEZONES = [
  'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
  'America/Phoenix', 'America/Anchorage', 'Pacific/Honolulu',
  'Europe/London', 'Europe/Berlin', 'Europe/Paris',
  'Asia/Tokyo', 'Asia/Shanghai', 'Asia/Kolkata',
  'Australia/Sydney',
];

export function SetupPage() {
  const navigate = useNavigate();
  const queryClient = useQueryClient();

  // If setup already completed, redirect to dashboard
  const { data: setupData, isLoading: checkingSetup } = useQuery({
    queryKey: ['setup-status'],
    queryFn: () => settingsApi.getSetupStatus(),
    staleTime: 10_000,
  });
  const alreadyCompleted = (setupData as any)?.data?.data?.setup_completed === true;
  if (alreadyCompleted) return <Navigate to="/" replace />;
  if (checkingSetup) return null;

  const [setupDone, setSetupDone] = useState(false);
  const [storeName, setStoreName] = useState('');
  const [address, setAddress] = useState('');
  const [phone, setPhone] = useState('');
  const [email, setEmail] = useState('');
  const [timezone, setTimezone] = useState('America/Denver');
  const [currency, setCurrency] = useState('USD');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!storeName.trim()) {
      setError('Store name is required');
      return;
    }
    setSaving(true);
    setError('');
    try {
      await settingsApi.completeSetup({
        store_name: storeName.trim(),
        address: address.trim() || undefined,
        phone: phone.trim() || undefined,
        email: email.trim() || undefined,
        timezone,
        currency,
      });
      await queryClient.refetchQueries({ queryKey: ['setup-status'] });
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      setSetupDone(true);
    } catch (err: any) {
      setError(err?.response?.data?.message || 'Failed to save. Please try again.');
    } finally {
      setSaving(false);
    }
  };

  // After setup: show mobile app download prompt
  if (setupDone) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 to-surface-100 p-4 dark:from-surface-950 dark:to-surface-900">
        <div className="w-full max-w-lg">
          <div className="mb-8 text-center">
            <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-green-100 dark:bg-green-500/10">
              <CheckCircle2 className="h-8 w-8 text-green-600 dark:text-green-400" />
            </div>
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">
              Shop is ready!
            </h1>
            <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
              Your repair shop has been set up. One more thing...
            </p>
          </div>

          <div className="rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
            <div className="flex items-start gap-4 mb-6">
              <div className="flex h-12 w-12 flex-shrink-0 items-center justify-center rounded-xl bg-primary-100 dark:bg-primary-500/10">
                <Smartphone className="h-6 w-6 text-primary-600 dark:text-primary-400" />
              </div>
              <div>
                <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-50">Get the Mobile App</h2>
                <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
                  Manage tickets, check inventory, and send SMS right from your phone. Works on any Android device.
                </p>
              </div>
            </div>

            <a
              href="/downloads/BizarreCRM.apk"
              download
              className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary-600 px-6 py-3 text-sm font-semibold text-white shadow-lg hover:bg-primary-700 transition-colors"
            >
              <Download className="h-4 w-4" />
              Download Android App (.apk)
            </a>

            <p className="mt-3 text-center text-xs text-surface-400 dark:text-surface-500">
              You may need to allow "Install from unknown sources" in your phone's settings.
            </p>

            <button
              onClick={() => navigate('/', { replace: true })}
              className="mt-6 flex w-full items-center justify-center gap-2 rounded-xl border border-surface-200 bg-surface-50 px-6 py-3 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:bg-surface-700 transition-colors"
            >
              Skip for now — Go to Dashboard
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gradient-to-br from-surface-50 to-surface-100 p-4 dark:from-surface-950 dark:to-surface-900">
      <div className="w-full max-w-lg">
        {/* Header */}
        <div className="mb-8 text-center">
          <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
            <Store className="h-8 w-8 text-primary-600 dark:text-primary-400" />
          </div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">
            Set up your shop
          </h1>
          <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
            Tell us about your repair shop. You can change these later in Settings.
          </p>
        </div>

        {/* Form */}
        <form onSubmit={handleSubmit} className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          {/* Store Name — required */}
          <div>
            <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Store className="h-4 w-4 text-surface-400" />
              Store Name <span className="text-red-500">*</span>
            </label>
            <input
              type="text"
              value={storeName}
              onChange={(e) => setStoreName(e.target.value)}
              placeholder="Joe's Phone Repair"
              autoFocus
              required
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>

          {/* Address */}
          <div>
            <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <MapPin className="h-4 w-4 text-surface-400" />
              Address
            </label>
            <input
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder="123 Main St, City, State ZIP"
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>

          {/* Phone + Email row */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
                <Phone className="h-4 w-4 text-surface-400" />
                Phone
              </label>
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="+1 (555) 123-4567"
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>
            <div>
              <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
                <Mail className="h-4 w-4 text-surface-400" />
                Email
              </label>
              <input
                type="email"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="shop@example.com"
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              />
            </div>
          </div>

          {/* Timezone + Currency */}
          <div className="grid grid-cols-2 gap-4">
            <div>
              <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
                <Clock className="h-4 w-4 text-surface-400" />
                Timezone
              </label>
              <select
                value={timezone}
                onChange={(e) => setTimezone(e.target.value)}
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              >
                {TIMEZONES.map((tz) => (
                  <option key={tz} value={tz}>{tz.replace('_', ' ')}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
                <DollarSign className="h-4 w-4 text-surface-400" />
                Currency
              </label>
              <select
                value={currency}
                onChange={(e) => setCurrency(e.target.value)}
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
              >
                <option value="USD">USD ($)</option>
                <option value="EUR">EUR (&euro;)</option>
                <option value="GBP">GBP (&pound;)</option>
                <option value="CAD">CAD (C$)</option>
                <option value="AUD">AUD (A$)</option>
              </select>
            </div>
          </div>

          {error && (
            <p className="text-sm text-red-500">{error}</p>
          )}

          <button
            type="submit"
            disabled={saving || !storeName.trim()}
            className="flex w-full items-center justify-center gap-2 rounded-lg bg-primary-600 py-3.5 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:opacity-50"
          >
            {saving ? (
              <Loader2 className="h-5 w-5 animate-spin" />
            ) : (
              <>
                <CheckCircle2 className="h-5 w-5" />
                Complete Setup
                <ArrowRight className="h-4 w-4" />
              </>
            )}
          </button>

          <p className="text-center text-xs text-surface-400">
            You can update all of these in Settings anytime.
          </p>
        </form>
      </div>
    </div>
  );
}
