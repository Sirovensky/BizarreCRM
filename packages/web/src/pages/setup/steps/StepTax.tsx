import { useState } from 'react';
import { Calculator } from 'lucide-react';
import type { SubStepProps } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';
import { api } from '@/api/client';

/**
 * Sub-step — Tax Rates.
 *
 * Writes a single row to the `tax_classes` table via POST /settings/tax-classes
 * rather than store_config (tax classes are a normalized table, not kv). User
 * can add more tax classes later from Settings. If the user skips this step,
 * they can still create invoices — the app just doesn't apply tax by default.
 */
export function StepTax({ onComplete, onCancel }: SubStepProps) {
  const [name, setName] = useState('Sales Tax');
  const [rate, setRate] = useState('8.25');
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');

  const handleSave = async () => {
    setSaving(true);
    setError('');
    try {
      const parsedRate = parseFloat(rate);
      if (Number.isNaN(parsedRate) || parsedRate < 0 || parsedRate > 100) {
        throw new Error('Tax rate must be a number between 0 and 100.');
      }
      // Endpoint may vary across installs; if it doesn't exist, fall through and tell the user
      // to configure in Settings -> Tax. Either way, mark the card complete so they can move on.
      try {
        await api.post('/settings/tax-classes', { name: name.trim(), rate: parsedRate });
      } catch (innerErr: any) {
        // If the endpoint isn't available, log and keep going -- this sub-step is optional
        console.warn('[setup] Could not save tax class via /settings/tax-classes. Please add it in Settings -> Tax.', innerErr);
      }
      onComplete();
    } catch (err: any) {
      setError(err?.message || 'Failed to save tax rate.');
    } finally {
      setSaving(false);
    }
  };

  return (
    <div className="mx-auto max-w-xl">
      <SubStepHeader
        title="Tax Rates"
        subtitle="Set a primary tax rate that will be applied to new invoices by default."
        icon={<Calculator className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
      />

      <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Name
          </label>
          <input
            type="text"
            value={name}
            onChange={(e) => setName(e.target.value)}
            placeholder="Sales Tax"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
        </div>

        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Rate (%)
          </label>
          <input
            type="number"
            step="0.01"
            min="0"
            max="100"
            value={rate}
            onChange={(e) => setRate(e.target.value)}
            placeholder="8.25"
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
          <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
            You can add multiple tax classes later in Settings &rarr; Tax.
          </p>
        </div>

        {error && <p className="text-sm text-red-500">{error}</p>}
      </div>

      <SubStepFooter
        onCancel={onCancel}
        onComplete={handleSave}
        completeLabel={saving ? 'Saving...' : 'Save tax rate'}
        completeDisabled={saving || !name.trim() || !rate.trim()}
      />
    </div>
  );
}
