import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, AlertCircle, Database } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';

// ─── Types ────────────────────────────────────────────────────────────────────

interface RetentionField {
  key: string;
  label: string;
  description: string;
}

// Matches the configKeys in retentionSweeper.ts PII_RULES + sweep-enabled flag
const RETENTION_FIELDS: RetentionField[] = [
  {
    key: 'retention_sms_months',
    label: 'SMS conversations retention (months)',
    description: 'SMS message records older than this will be deleted.',
  },
  {
    key: 'retention_calls_months',
    label: 'Call log retention (months)',
    description: 'Call log records older than this will be deleted.',
  },
  {
    key: 'retention_email_months',
    label: 'Email messages retention (months)',
    description: 'Email message records older than this will be deleted.',
  },
  {
    key: 'retention_ticket_notes_months',
    label: 'Ticket notes retention (months)',
    description: 'Ticket note content older than this will be scrubbed (the note row is kept but its content is blanked).',
  },
];

// ─── Number Input Row ─────────────────────────────────────────────────────────

interface NumberRowProps {
  id: string;
  label: string;
  description: string;
  value: string;
  onChange: (v: string) => void;
}

function NumberRow({ id, label, description, value, onChange }: NumberRowProps) {
  // WEB-FX-002 (Fixer-A17 2026-04-25): pair the input with a real <label htmlFor>
  // + aria-describedby so screen readers announce the field name and helper
  // copy together instead of an unlabeled spinner.
  const descId = `${id}-desc`;
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
      <div>
        <label htmlFor={id} className="text-sm font-medium text-surface-900 dark:text-surface-100 block cursor-pointer">{label}</label>
        <p id={descId} className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <div className="flex items-center gap-2 flex-shrink-0">
        <input
          id={id}
          type="number"
          min="0"
          max="120"
          step="1"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          aria-describedby={descId}
          className="w-24 px-3 py-1.5 text-sm text-right border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
        />
        <span className="text-sm text-surface-500 dark:text-surface-400 w-14">months</span>
      </div>
    </div>
  );
}

// ─── Component ────────────────────────────────────────────────────────────────

export function DataRetentionTab() {
  const queryClient = useQueryClient();
  const [config, setConfig] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
  });

  useEffect(() => {
    if (data) {
      setConfig(data);
      setDirty(false);
    }
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: (d: Record<string, string>) => settingsApi.updateConfig(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      setDirty(false);
      toast.success('Data retention settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function set(key: string, value: string): void {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  function val(key: string): string {
    // Default-OFF policy: missing keys default to '0' (no deletion).
    return config[key] ?? '0';
  }

  const sweepEnabled = config.retention_sweep_enabled === '1';

  function handleSave(): void {
    // Save retention keys + master switch only (avoid overwriting unrelated config)
    const patch: Record<string, string> = { retention_sweep_enabled: sweepEnabled ? '1' : '0' };
    for (const field of RETENTION_FIELDS) {
      patch[field.key] = val(field.key);
    }
    saveMutation.mutate(patch);
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
        <span className="ml-3 text-surface-500">Loading...</span>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
        <p className="text-sm text-surface-500">Failed to load settings</p>
      </div>
    );
  }

  return (
    <div className="card">
      {/* Header */}
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Database className="h-5 w-5 text-surface-400" />
          <h2 className="text-sm font-semibold text-surface-800 dark:text-surface-200">Data Retention</h2>
        </div>
        <button
          onClick={handleSave}
          disabled={saveMutation.isPending || !dirty}
          className="flex items-center gap-2 px-3 py-1.5 text-sm rounded-lg bg-primary-600 text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {saveMutation.isPending ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Save className="h-4 w-4" />
          )}
          Save
        </button>
      </div>

      {/* Master kill switch */}
      <div className="px-4 py-3 border-b border-surface-100 dark:border-surface-800">
        <label className="flex items-start gap-3 cursor-pointer">
          <input
            type="checkbox"
            checked={sweepEnabled}
            onChange={(e) => set('retention_sweep_enabled', e.target.checked ? '1' : '0')}
            className="mt-1 h-4 w-4 rounded border-surface-300 text-primary-500 focus:ring-primary-500"
          />
          <div className="flex-1">
            <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
              Enable automatic data retention deletion
            </p>
            <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">
              {sweepEnabled
                ? 'Nightly sweeper will delete data older than the per-category windows below.'
                : 'All data is kept indefinitely. No automatic deletion. Turn this on only if you need GDPR/CCPA compliance or have a storage cap.'}
            </p>
          </div>
        </label>
      </div>

      {/* Description */}
      <div className={`px-4 py-3 border-b border-surface-100 dark:border-surface-800 ${sweepEnabled ? 'bg-amber-50 dark:bg-amber-900/10' : 'bg-surface-50 dark:bg-surface-900/30'}`}>
        <p className={`text-sm ${sweepEnabled ? 'text-amber-800 dark:text-amber-300' : 'text-surface-500 dark:text-surface-400'}`}>
          {sweepEnabled
            ? <>Data older than these thresholds will have PII scrubbed by the nightly sweeper. Set to <strong>0</strong> to disable retention for a given category. Maximum is 120 months (10 years).</>
            : <>Per-category retention windows below have no effect while the master switch above is off. Default for fresh shops: <strong>0</strong> (keep forever).</>}
        </p>
      </div>

      {/* Fields */}
      <div className="px-4 divide-y divide-surface-100 dark:divide-surface-800">
        {RETENTION_FIELDS.map((field) => (
          <NumberRow
            key={field.key}
            id={`retention-${field.key}`}
            label={field.label}
            description={field.description}
            value={val(field.key)}
            onChange={(v) => set(field.key, v)}
          />
        ))}
      </div>
    </div>
  );
}
