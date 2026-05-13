/**
 * BenchQcTab — WEB-UIUX-1079
 *
 * Admin UI for the bench timer + QC + defect alert toggles. Backing
 * `store_config` keys were added with migration 088 but only mutable via
 * direct SQL until now; the first-run wizard promised an admin toggle that
 * didn't exist.
 *
 * Persisted keys (whitelisted in settings.routes.ts):
 *   - bench_timer_enabled         : 'true' | 'false'
 *   - qc_required                 : 'true' | 'false'
 *   - bench_labor_rate_cents      : integer cents (default 0)
 *   - defect_alert_threshold_30d  : integer count threshold (default 0)
 */
import { useEffect, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';

const KEYS = {
  benchTimerEnabled: 'bench_timer_enabled',
  qcRequired: 'qc_required',
  benchLaborRateCents: 'bench_labor_rate_cents',
  defectAlertThreshold30d: 'defect_alert_threshold_30d',
} as const;

export function BenchQcTab() {
  const queryClient = useQueryClient();
  const [config, setConfig] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);

  const { data, isLoading } = useQuery({
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
    mutationFn: (patch: Record<string, string>) => settingsApi.updateConfig(patch),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      setDirty(false);
      toast.success('Bench & QC settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function bool(key: string, fallback = 'false'): boolean {
    return (config[key] ?? fallback) === 'true';
  }

  function setBool(key: string, v: boolean) {
    setConfig((prev) => ({ ...prev, [key]: v ? 'true' : 'false' }));
    setDirty(true);
  }

  function num(key: string, fallback = '0'): string {
    return config[key] ?? fallback;
  }

  function setNum(key: string, value: string) {
    // Allow blank during edit; coerce to '0' on save.
    setConfig((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  function handleSave() {
    const patch: Record<string, string> = {
      [KEYS.benchTimerEnabled]: bool(KEYS.benchTimerEnabled) ? 'true' : 'false',
      [KEYS.qcRequired]: bool(KEYS.qcRequired) ? 'true' : 'false',
      [KEYS.benchLaborRateCents]: String(Math.max(0, parseInt(num(KEYS.benchLaborRateCents), 10) || 0)),
      [KEYS.defectAlertThreshold30d]: String(Math.max(0, parseInt(num(KEYS.defectAlertThreshold30d), 10) || 0)),
    };
    saveMutation.mutate(patch);
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-surface-900 dark:text-surface-100">Bench &amp; QC</h1>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          Controls for the bench timer, post-repair QC sign-off, and defect
          alerts. These toggles back the keys seeded in migration 088.
        </p>
      </div>

      <div className="rounded-xl border border-surface-200 bg-white shadow-sm dark:border-surface-700 dark:bg-surface-900">
        <ToggleRow
          id="bench_timer_enabled"
          label="Enable bench timer"
          description="Show the per-ticket repair-time timer to techs. When off the UI is hidden and no rows are written to ticket_time_entries."
          value={bool(KEYS.benchTimerEnabled)}
          onChange={(v) => setBool(KEYS.benchTimerEnabled, v)}
        />
        <ToggleRow
          id="qc_required"
          label="Require QC sign-off before close"
          description="When on, tickets cannot be marked complete (PATCH status='complete') without a passing qc_sign_offs row. Failed sign-offs reroute the ticket to a configured failure status."
          value={bool(KEYS.qcRequired)}
          onChange={(v) => setBool(KEYS.qcRequired, v)}
        />
        <NumberRow
          id="bench_labor_rate_cents"
          label="Bench labor rate (cents/hour)"
          description="Default labor rate used by the bench timer cost rollups. 0 disables labor cost projection."
          unit="¢/hr"
          value={num(KEYS.benchLaborRateCents)}
          onChange={(v) => setNum(KEYS.benchLaborRateCents, v)}
        />
        <NumberRow
          id="defect_alert_threshold_30d"
          label="Defect alert threshold (30-day count)"
          description="Triggers a defect alert when the same part SKU racks up this many defect reports within a rolling 30-day window. 0 disables alerts."
          unit="reports"
          value={num(KEYS.defectAlertThreshold30d)}
          onChange={(v) => setNum(KEYS.defectAlertThreshold30d, v)}
        />
      </div>

      <div className="flex justify-end">
        <button
          type="button"
          onClick={handleSave}
          disabled={!dirty || saveMutation.isPending}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save changes
        </button>
      </div>
    </div>
  );
}

function ToggleRow({
  id, label, description, value, onChange,
}: {
  id: string;
  label: string;
  description: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  const descId = `${id}-desc`;
  return (
    <div className="flex items-center justify-between gap-6 border-b border-surface-100 px-4 py-4 last:border-b-0 dark:border-surface-800">
      <div>
        <label htmlFor={id} className="block cursor-pointer text-sm font-medium text-surface-900 dark:text-surface-100">{label}</label>
        <p id={descId} className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">{description}</p>
      </div>
      <button
        id={id}
        type="button"
        role="switch"
        aria-checked={value}
        aria-describedby={descId}
        onClick={() => onChange(!value)}
        className={`relative inline-flex h-6 w-11 flex-shrink-0 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 ${
          value ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600'
        }`}
      >
        <span
          className={`inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${
            value ? 'translate-x-5' : 'translate-x-1'
          }`}
        />
      </button>
    </div>
  );
}

function NumberRow({
  id, label, description, unit, value, onChange,
}: {
  id: string;
  label: string;
  description: string;
  unit: string;
  value: string;
  onChange: (v: string) => void;
}) {
  const descId = `${id}-desc`;
  return (
    <div className="flex items-center justify-between gap-6 border-b border-surface-100 px-4 py-4 last:border-b-0 dark:border-surface-800">
      <div>
        <label htmlFor={id} className="block cursor-pointer text-sm font-medium text-surface-900 dark:text-surface-100">{label}</label>
        <p id={descId} className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">{description}</p>
      </div>
      <div className="flex flex-shrink-0 items-center gap-2">
        <input
          id={id}
          type="number"
          min="0"
          step="1"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          aria-describedby={descId}
          className="w-28 rounded-lg border border-surface-200 bg-white px-3 py-1.5 text-right text-sm text-surface-900 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
        />
        <span className="w-14 text-sm text-surface-500 dark:text-surface-400">{unit}</span>
      </div>
    </div>
  );
}
