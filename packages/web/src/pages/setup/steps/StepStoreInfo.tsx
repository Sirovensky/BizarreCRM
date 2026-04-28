import { MapPin, Phone, Mail, Clock, DollarSign, ArrowRight, ArrowLeft } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { formatStorePhoneAsYouType } from '@/utils/phoneFormat';
import {
  validateStoreAddress,
  validatePhoneInternational,
  validateEmail,
  validateTimezone,
  validateCurrency,
  ALLOWED_TIMEZONES,
} from '@/services/validationService';

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

  // Errors are computed on every render so the UI reflects the latest value instantly.
  // A field only shows an error once it has been touched (non-empty) — empty fields
  // are caught by canAdvance, not shown as errors while the user hasn't typed yet.
  const errors = {
    address: address.length > 0 ? validateStoreAddress(address) : null,
    phone:   phone.length > 0   ? validatePhoneInternational(phone) : null,
    email:   email.length > 0   ? validateEmail(email) : null,
    timezone: validateTimezone(timezone),
    currency: validateCurrency(currency),
  };

  const canAdvance =
    !errors.address &&
    !errors.phone &&
    !errors.email &&
    !errors.timezone &&
    !errors.currency &&
    address.trim().length >= 10 &&
    phone.replace(/\D/g, '').length >= 10 &&
    email.trim().length >= 3;

  return (
    <div className="mx-auto max-w-2xl animate-in fade-in-0 slide-in-from-bottom-4 duration-300 motion-reduce:animate-none">
<div className="mb-6 mt-6">
        <h2 className="text-3xl font-semibold tracking-tight text-surface-900 dark:text-surface-50">
          Store info
        </h2>
        <p className="mt-1 text-base text-surface-600 dark:text-surface-400">
          These appear on receipts, invoices, and customer-facing pages.
        </p>
      </div>

      <div className="space-y-5 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl transition-all hover:shadow-lg dark:border-surface-700 dark:bg-surface-800">
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
            aria-invalid={!!errors.address}
            aria-describedby={errors.address ? 'setup-store-address-error' : undefined}
            className={`w-full rounded-xl border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
              errors.address
                ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
            }`}
          />
          {errors.address && (
            <p id="setup-store-address-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{errors.address}</p>
          )}
        </div>

        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          <div>
            <label htmlFor="setup-store-phone" className="mb-1.5 flex items-center gap-2 text-sm font-medium text-surface-700 dark:text-surface-300">
              <Phone className="h-4 w-4 text-surface-400" />
              Phone <span className="text-red-500">*</span>
            </label>
            <input
              id="setup-store-phone"
              type="tel"
              value={phone}
              onChange={(e) => onUpdate({ store_phone: formatStorePhoneAsYouType(e.target.value) })}
              placeholder="+1 (555)-123-4567"
              inputMode="tel"
              autoComplete="tel"
              aria-invalid={!!errors.phone}
              aria-describedby={errors.phone ? 'setup-store-phone-error' : undefined}
              className={`w-full rounded-xl border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                errors.phone
                  ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                  : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            {errors.phone && (
              <p id="setup-store-phone-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{errors.phone}</p>
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
              aria-invalid={!!errors.email}
              aria-describedby={errors.email ? 'setup-store-email-error' : undefined}
              className={`w-full rounded-xl border bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 dark:bg-surface-700 dark:text-surface-100 ${
                errors.email
                  ? 'border-red-400 focus:border-red-500 focus:ring-red-500/20 dark:border-red-500/60'
                  : 'border-surface-300 focus:border-primary-500 focus:ring-primary-500/20 dark:border-surface-600'
              }`}
            />
            {errors.email && (
              <p id="setup-store-email-error" role="alert" aria-live="polite" className="mt-1 text-xs text-red-500">{errors.email}</p>
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
              className="w-full rounded-xl border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            >
              {ALLOWED_TIMEZONES.map((tz) => (
                <option key={tz} value={tz}>{tz.replace(/_/g, ' ')}</option>
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
              className="w-full rounded-xl border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
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
            className="flex h-12 items-center gap-1 rounded-full px-4 text-sm font-medium text-surface-600 transition-colors hover:bg-surface-100 hover:text-surface-900 dark:text-surface-400 dark:hover:bg-surface-700 dark:hover:text-surface-100"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <button
            type="button"
            onClick={onNext}
            disabled={!canAdvance}
            className="flex h-12 items-center gap-2 rounded-full bg-primary-600 px-6 font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Next — Extras
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
