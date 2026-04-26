import { useState, useEffect, useRef } from 'react';
import { Download, CheckCircle2, Loader2, AlertTriangle, XCircle } from 'lucide-react';
import type { SubStepProps } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';
import { rdImportApi, rsImportApi, mraImportApi } from '@/api/endpoints';

type ImportSource = 'repairdesk' | 'repairshopr' | 'myrepairapp';
type ImportPhase = 'select-source' | 'enter-creds' | 'select-entities' | 'running' | 'done';

const SOURCE_DETAILS: Record<ImportSource, {
  label: string;
  description: string;
  entities: Array<{ id: string; label: string }>;
}> = {
  repairdesk: {
    label: 'RepairDesk',
    description: 'Full migration including customers, tickets, invoices, inventory, and SMS history.',
    entities: [
      { id: 'customers', label: 'Customers' },
      { id: 'tickets', label: 'Tickets (repairs)' },
      { id: 'invoices', label: 'Invoices & payments' },
      { id: 'inventory', label: 'Inventory / parts' },
      { id: 'sms', label: 'SMS history' },
    ],
  },
  repairshopr: {
    label: 'RepairShopr',
    description: 'Customers, tickets, invoices, and inventory from RepairShopr.',
    entities: [
      { id: 'customers', label: 'Customers' },
      { id: 'tickets', label: 'Tickets (repairs)' },
      { id: 'invoices', label: 'Invoices & payments' },
      { id: 'inventory', label: 'Inventory / parts' },
    ],
  },
  myrepairapp: {
    label: 'MyRepairApp',
    description: 'Customers, tickets, invoices, and inventory from MyRepairApp.',
    entities: [
      { id: 'customers', label: 'Customers' },
      { id: 'tickets', label: 'Tickets (repairs)' },
      { id: 'invoices', label: 'Invoices & payments' },
      { id: 'inventory', label: 'Inventory' },
    ],
  },
};

/**
 * Sub-step — Import Existing Data.
 *
 * Multi-stage internal state machine:
 *   select-source -> enter-creds -> select-entities -> running -> done
 *
 * Uses the existing rdImportApi / rsImportApi / mraImportApi clients which
 * already exist in the codebase (unchanged). Progress is polled every 3s
 * during the 'running' phase. User can "Continue in background" to leave the
 * sub-step while the import keeps running — the hub card will then show an
 * "Importing..." state until the next visit to Settings -> Data & Import.
 */
export function StepImport({ onComplete, onCancel }: SubStepProps) {
  const [phase, setPhase] = useState<ImportPhase>('select-source');
  const [source, setSource] = useState<ImportSource | null>(null);
  const [apiKey, setApiKey] = useState('');
  const [subdomain, setSubdomain] = useState(''); // only for RepairShopr
  const [testStatus, setTestStatus] = useState<'idle' | 'testing' | 'ok' | 'fail'>('idle');
  const [testMessage, setTestMessage] = useState('');
  const [selectedEntities, setSelectedEntities] = useState<Set<string>>(new Set(['customers']));
  const [runSummary, setRunSummary] = useState<{ imported: number; skipped: number; errors: number; total: number; active: boolean } | null>(null);
  const [error, setError] = useState('');
  const pollRef = useRef<ReturnType<typeof setInterval> | null>(null);

  // Cleanup poll on unmount
  useEffect(() => {
    return () => {
      if (pollRef.current) clearInterval(pollRef.current);
    };
  }, []);

  const resetSource = () => {
    setSource(null);
    setApiKey('');
    setSubdomain('');
    setTestStatus('idle');
    setTestMessage('');
    setSelectedEntities(new Set(['customers']));
    setPhase('select-source');
  };

  const handleTestConnection = async () => {
    if (!source) return;
    setTestStatus('testing');
    setTestMessage('');
    try {
      let res: any;
      if (source === 'repairdesk') {
        res = await rdImportApi.testConnection(apiKey);
      } else if (source === 'repairshopr') {
        res = await rsImportApi.testConnection({ api_key: apiKey, subdomain });
      } else {
        res = await mraImportApi.testConnection({ api_key: apiKey });
      }
      const ok = res?.data?.data?.ok !== false;
      setTestStatus(ok ? 'ok' : 'fail');
      setTestMessage(res?.data?.data?.message || (ok ? 'Connection successful!' : 'Connection failed.'));
    } catch (err: any) {
      setTestStatus('fail');
      setTestMessage(err?.response?.data?.message || err?.message || 'Connection failed.');
    }
  };

  const toggleEntity = (id: string) => {
    setSelectedEntities((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  };

  const startImport = async () => {
    if (!source) return;
    setError('');
    try {
      const entities = Array.from(selectedEntities);
      if (source === 'repairdesk') {
        await rdImportApi.start({ api_key: apiKey, entities });
      } else if (source === 'repairshopr') {
        await rsImportApi.start({ api_key: apiKey, subdomain, entities });
      } else {
        await mraImportApi.start({ api_key: apiKey, entities });
      }
      setPhase('running');
      // Capture the source at schedule time — without this, a later state
      // change would let the interval callback call the wrong status endpoint.
      const pollSource = source;
      let consecutiveFailures = 0;
      const MAX_CONSECUTIVE_FAILURES = 5;
      // WEB-FO-017: clear any stacked poller from a prior `startImport()`
      // before re-arming. The button is disabled during `phase === 'running'`,
      // but a rapid double-click can race the API call (the second `startImport`
      // begins before the first one's `setPhase('running')` has rendered) and
      // overwrite `pollRef.current` without stopping the previous interval.
      if (pollRef.current) {
        clearInterval(pollRef.current);
        pollRef.current = null;
      }
      pollRef.current = setInterval(async () => {
        try {
          let statusRes: any;
          if (pollSource === 'repairdesk') statusRes = await rdImportApi.status();
          else if (pollSource === 'repairshopr') statusRes = await rsImportApi.status();
          else statusRes = await mraImportApi.status();
          const overall = statusRes?.data?.data?.overall;
          const active = statusRes?.data?.data?.is_active;
          if (overall) {
            setRunSummary({
              imported: overall.imported || 0,
              skipped: overall.skipped || 0,
              errors: overall.errors || 0,
              total: overall.total_records || 0,
              active: !!active,
            });
            if (!active) {
              if (pollRef.current) clearInterval(pollRef.current);
              setPhase('done');
            }
          }
          consecutiveFailures = 0;
        } catch (pollErr) {
          // Count transient failures — bail after 5 in a row so the poller
          // doesn't spin forever on a permanent backend outage.
          consecutiveFailures += 1;
          if (consecutiveFailures >= MAX_CONSECUTIVE_FAILURES) {
            if (pollRef.current) clearInterval(pollRef.current);
            console.error('[setup/import] polling aborted after repeated failures', pollErr);
            setError('Lost connection to the import service. Please refresh to check status.');
          }
        }
      }, 3000);
    } catch (err: unknown) {
      const e = err as { response?: { data?: { message?: string } } } | undefined;
      setError(e?.response?.data?.message || 'Failed to start import.');
    }
  };

  // ── Render per phase ─────────────────────────────────────────────
  if (phase === 'select-source') {
    return (
      <div className="mx-auto max-w-2xl">
        <SubStepHeader
          title="Import Existing Data"
          subtitle="Migrate your existing shop's data from another CRM. This keeps your history intact."
          icon={<Download className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
        />
        <div className="space-y-3">
          {(Object.keys(SOURCE_DETAILS) as ImportSource[]).map((s) => {
            const details = SOURCE_DETAILS[s];
            return (
              <button
                key={s}
                type="button"
                onClick={() => { setSource(s); setPhase('enter-creds'); }}
                className="w-full rounded-xl border-2 border-surface-200 bg-white p-5 text-left transition-all hover:border-primary-400 hover:shadow-md dark:border-surface-700 dark:bg-surface-800 dark:hover:border-primary-500/60"
              >
                <div className="font-['League_Spartan'] text-lg font-bold tracking-wide text-surface-900 dark:text-surface-50">
                  {details.label}
                </div>
                <div className="mt-1 text-sm text-surface-500 dark:text-surface-400">
                  {details.description}
                </div>
              </button>
            );
          })}
          <button
            type="button"
            onClick={onCancel}
            className="w-full rounded-xl border border-dashed border-surface-300 bg-surface-50 p-5 text-center text-sm font-medium text-surface-500 hover:border-surface-400 hover:bg-surface-100 dark:border-surface-600 dark:bg-surface-800/50 dark:text-surface-400 dark:hover:border-surface-500 dark:hover:bg-surface-700"
          >
            I don't have data to import &mdash; back to hub
          </button>
        </div>
      </div>
    );
  }

  if (phase === 'enter-creds' && source) {
    const details = SOURCE_DETAILS[source];
    const canTest = source === 'repairshopr' ? !!apiKey && !!subdomain : !!apiKey;
    return (
      <div className="mx-auto max-w-xl">
        <SubStepHeader
          title={`${details.label} Credentials`}
          subtitle="Paste your API key to start the import."
          icon={<Download className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
        />
        <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div>
            <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
              API key
            </label>
            <input
              type="password"
              value={apiKey}
              onChange={(e) => { setApiKey(e.target.value); setTestStatus('idle'); }}
              placeholder="Paste your API key"
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 font-mono text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>

          {source === 'repairshopr' && (
            <div>
              <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
                Subdomain
              </label>
              <div className="flex items-center">
                <input
                  type="text"
                  value={subdomain}
                  onChange={(e) => { setSubdomain(e.target.value.trim()); setTestStatus('idle'); }}
                  placeholder="yourshop"
                  className="flex-1 rounded-l-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
                <span className="rounded-r-lg border border-l-0 border-surface-300 bg-surface-100 px-3 py-3 text-sm text-surface-500 dark:border-surface-600 dark:bg-surface-700">
                  .repairshopr.com
                </span>
              </div>
            </div>
          )}

          <button
            type="button"
            onClick={handleTestConnection}
            disabled={!canTest || testStatus === 'testing'}
            className="flex items-center gap-2 rounded-lg border border-surface-300 bg-white px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:opacity-50 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            {testStatus === 'testing' && <Loader2 className="h-4 w-4 animate-spin" />}
            {testStatus === 'ok' && <CheckCircle2 className="h-4 w-4 text-green-500" />}
            {testStatus === 'fail' && <XCircle className="h-4 w-4 text-red-500" />}
            Test connection
          </button>

          {testMessage && (
            <p className={`text-sm ${testStatus === 'ok' ? 'text-green-600 dark:text-green-400' : 'text-red-500'}`}>
              {testMessage}
            </p>
          )}

          <p className="text-xs text-surface-500 dark:text-surface-400">
            Your API key is kept in memory only for the duration of the import and discarded when
            it finishes. It is never written to disk. If you need to re-run the import later,
            you'll paste it again.
          </p>
        </div>

        <div className="mt-6 flex items-center justify-between">
          <button type="button" onClick={resetSource} className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100">
            &larr; Change source
          </button>
          <button
            type="button"
            onClick={() => setPhase('select-entities')}
            disabled={testStatus !== 'ok'}
            className="rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm hover:bg-primary-700 disabled:opacity-50"
          >
            Next &rarr; What to import
          </button>
        </div>
      </div>
    );
  }

  if (phase === 'select-entities' && source) {
    const details = SOURCE_DETAILS[source];
    return (
      <div className="mx-auto max-w-xl">
        <SubStepHeader
          title="What to import"
          subtitle={`Pick what you want to bring over from ${details.label}.`}
          icon={<Download className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
        />
        <div className="space-y-2 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          {details.entities.map((e) => {
            const checked = selectedEntities.has(e.id);
            return (
              <label key={e.id} className="flex cursor-pointer items-center gap-3 rounded-lg border border-surface-200 p-3 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-700/50">
                <input
                  type="checkbox"
                  checked={checked}
                  onChange={() => toggleEntity(e.id)}
                  className="h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                />
                <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{e.label}</span>
              </label>
            );
          })}
        </div>
        {error && <p role="alert" aria-live="polite" className="mt-3 text-sm text-red-500">{error}</p>}
        <div className="mt-6 flex items-center justify-between">
          <button type="button" onClick={() => setPhase('enter-creds')} className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100">
            &larr; Back
          </button>
          <button
            type="button"
            onClick={startImport}
            disabled={selectedEntities.size === 0}
            className="rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm hover:bg-primary-700 disabled:opacity-50"
          >
            Start import
          </button>
        </div>
      </div>
    );
  }

  if (phase === 'running') {
    return (
      <div className="mx-auto max-w-xl">
        <SubStepHeader
          title="Importing..."
          subtitle="This runs in the background. You can leave this screen and check progress later."
          icon={<Loader2 className="h-7 w-7 animate-spin text-primary-600 dark:text-primary-400" />}
        />
        <div className="rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          {runSummary ? (
            <div className="space-y-2 text-sm">
              <div className="flex justify-between"><span>Imported</span><strong>{runSummary.imported}</strong></div>
              <div className="flex justify-between"><span>Skipped (duplicates)</span><strong>{runSummary.skipped}</strong></div>
              <div className="flex justify-between"><span>Errors</span><strong>{runSummary.errors}</strong></div>
              <div className="flex justify-between border-t border-surface-200 pt-2 dark:border-surface-700"><span>Total records</span><strong>{runSummary.total}</strong></div>
            </div>
          ) : (
            <p className="text-sm text-surface-500">Waiting for import to start...</p>
          )}
        </div>
        <div className="mt-6 flex items-center justify-center">
          <button
            type="button"
            onClick={() => { if (pollRef.current) clearInterval(pollRef.current); onComplete(); }}
            className="rounded-lg border border-surface-300 px-6 py-3 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Continue in background
          </button>
        </div>
      </div>
    );
  }

  if (phase === 'done') {
    return (
      <div className="mx-auto max-w-xl">
        <SubStepHeader
          title="Import complete"
          subtitle="Your data is now in BizarreCRM."
          icon={<CheckCircle2 className="h-7 w-7 text-green-600 dark:text-green-400" />}
        />
        {runSummary && (
          <div className="rounded-2xl border border-green-200 bg-green-50 p-6 text-sm dark:border-green-500/30 dark:bg-green-500/10">
            <div className="flex justify-between"><span>Imported</span><strong>{runSummary.imported}</strong></div>
            <div className="flex justify-between"><span>Skipped</span><strong>{runSummary.skipped}</strong></div>
            <div className="flex justify-between"><span>Errors</span><strong>{runSummary.errors}</strong></div>
            {runSummary.errors > 0 && (
              <p className="mt-3 flex items-center gap-2 text-xs text-amber-700 dark:text-amber-400">
                <AlertTriangle className="h-3.5 w-3.5" />
                Some records didn't import. Review them later in Settings &rarr; Data &amp; Import.
              </p>
            )}
          </div>
        )}
        <SubStepFooter onCancel={onCancel} onComplete={onComplete} completeLabel="Finish" />
      </div>
    );
  }

  return null;
}
