import { MapPin, Phone, Mail, Clock, DollarSign, ArrowRight, ArrowLeft } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { formatStorePhoneAsYouType, stripPhone } from '@/utils/phoneFormat';

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
  // Require a full 10-digit US number (or a clearly-international entry the
  // formatter leaves unchanged). stripPhone gives us raw digits for length check.
  const phoneDigits = stripPhone(phone);
  const phoneLooksValid = phoneDigits.length === 0 || phoneDigits.length >= 10;
  const canAdvance =
    address.trim().length >= 3 &&
    phoneDigits.length >= 10 &&
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
          <label htmlFor="setup-store-address" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
            <MapPin className="h-4 w-4 text-surface-400" />
            Address <span className="text-red-500">*</span>
          </label>
          <input
            id="setup-store-address"
            type="text"
            value={address}
            onChange={(e) => onUpdate({ store_address: e.target.value })}
            placeholder="123 Main St, City, State ZIP"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="setup-store-phone" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Phone className="h-4 w-4 text-surface-400" />
              Phone <span className="text-red-500">*</span>
            </label>
            {/* WEB-S4-014: only strip+reformat on blur to avoid double-formatting while
                the user edits an already-formatted number. On change we store raw digits
                (via stripPhone) so the cursor stays stable; on blur we apply the display
                format so the field always shows the pretty version when unfocused. */}
            <input
              id="setup-store-phone"
              type="tel"
              value={phone}
              onChange={(e) => onUpdate({ store_phone: stripPhone(e.target.value) })}
              onBlur={(e) => onUpdate({ store_phone: formatStorePhoneAsYouType(e.target.value) })}
              placeholder="+1 (555)-123-4567"
              inputMode="tel"
              autoComplete="tel"
              aria-invalid={!phoneLooksValid}
              aria-describedby={!phoneLooksValid ? 'setup-store-phone-error' : undefined}
              className={`w-full rounded-lg border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                !phoneLooksValid
                  ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                  : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            {!phoneLooksValid && (
              <p id="setup-store-phone-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">Please enter a valid 10-digit phone number.</p>
            )}
          </div>
          <div>
            <label htmlFor="setup-store-email" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Mail className="h-4 w-4 text-surface-400" />
              Email <span className="text-red-500">*</span>
            </label>
            <input
              id="setup-store-email"
              type="email"
              value={email}
              onChange={(e) => onUpdate({ store_email: e.target.value })}
              placeholder="shop@example.com"
              aria-invalid={!emailLooksValid}
              aria-describedby={!emailLooksValid ? 'setup-store-email-error' : undefined}
              className={`w-full rounded-lg border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                !emailLooksValid
                  ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                  : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            {!emailLooksValid && (
              <p id="setup-store-email-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">Please enter a valid email address.</p>
            )}
          </div>
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="setup-store-timezone" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Clock className="h-4 w-4 text-surface-400" />
              Timezone
            </label>
            <select
              id="setup-store-timezone"
              value={timezone}
              onChange={(e) => onUpdate({ store_timezone: e.target.value })}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            >
              {TIMEZONES.map((tz) => (
                <option key={tz} value={tz}>{tz.replace('_', ' ')}</option>
              ))}
            </select>
          </div>
          <div>
            <label htmlFor="setup-store-currency" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <DollarSign className="h-4 w-4 text-surface-400" />
              Currency
            </label>
            <select
              id="setup-store-currency"
              value={currency}
              onChange={(e) => onUpdate({ store_currency: e.target.value })}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
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
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Next — Your Pro trial
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
