import { MapPin, Phone, Mail, Clock, DollarSign, ArrowRight, ArrowLeft } from 'lucide-react';
import type { StepProps } from '../wizardTypes';

const TIMEZONES = [
  'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
  'America/Phoenix', 'America/Anchorage', 'Pacific/Honolulu',
  'Europe/London', 'Europe/Berlin', 'Europe/Paris',
  'Asia/Tokyo', 'Asia/Shanghai', 'Asia/Kolkata',
  'Australia/Sydney',
];

const CURRENCIES = [
  { code: 'USD', label: 'USD ($)' },
  { code: 'EUR', label: 'EUR (\u20ac)' },
  { code: 'GBP', label: 'GBP (\u00a3)' },
  { code: 'CAD', label: 'CAD (C$)' },
  { code: 'AUD', label: 'AUD (A$)' },
  { code: 'NZD', label: 'NZD (NZ$)' },
];

/**
 * Step 2 — Store Info. All fields required before Next is enabled.
 * Timezone and currency have sensible defaults (America/Denver, USD) so
 * the minimum user interaction is just typing address/phone/email.
 */
export function StepStoreInfo({ pending, onUpdate, onNext, onBack }: StepProps) {
  const address = pending.store_address || '';
  const phone = pending.store_phone || '';
  const email = pending.store_email || '';
  const timezone = pending.store_timezone || 'America/Denver';
  const currency = pending.store_currency || 'USD';

  // Simple required-field validation. More thorough validation (phone format,
  // valid email) happens server-side if needed.
  const emailLooksValid = !email || /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
  const canAdvance =
    address.trim().length >= 3 &&
    phone.trim().length >= 3 &&
    email.trim().length >= 3 &&
    emailLooksValid;

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6">
        <h2 className="font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Store info
        </h2>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          These appear on receipts, invoices, and customer-facing pages.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div>
          <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
            <MapPin className="h-4 w-4 text-surface-400" />
            Address <span className="text-red-500">*</span>
          </label>
          <input
            type="text"
            value={address}
            onChange={(e) => onUpdate({ store_address: e.target.value })}
            placeholder="123 Main St, City, State ZIP"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Phone className="h-4 w-4 text-surface-400" />
              Phone <span className="text-red-500">*</span>
            </label>
            <input
              type="tel"
              value={phone}
              onChange={(e) => onUpdate({ store_phone: e.target.value })}
              placeholder="+1 (555) 123-4567"
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
          <div>
            <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Mail className="h-4 w-4 text-surface-400" />
              Email <span className="text-red-500">*</span>
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => onUpdate({ store_email: e.target.value })}
              placeholder="shop@example.com"
              className={`w-full rounded-lg border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:outline-none focus:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                !emailLooksValid
                  ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                  : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            {!emailLooksValid && (
              <p className="mt-1 text-xs text-red-500">Please enter a valid email address.</p>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Clock className="h-4 w-4 text-surface-400" />
              Timezone
            </label>
            <select
              value={timezone}
              onChange={(e) => onUpdate({ store_timezone: e.target.value })}
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
              onChange={(e) => onUpdate({ store_currency: e.target.value })}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            >
              {CURRENCIES.map((c) => (
                <option key={c.code} value={c.code}>{c.label}</option>
              ))}
            </select>
          </div>
        </div>

        <div className="flex items-center justify-between pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-1 text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <button
            type="button"
            onClick={onNext}
            disabled={!canAdvance}
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-white shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Next — Your Pro trial
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
