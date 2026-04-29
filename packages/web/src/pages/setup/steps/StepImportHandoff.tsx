import { Database, Clock, Sparkles, ArrowRight, ArrowLeft } from 'lucide-react';
import type { StepProps } from '../wizardTypes';

const OPTIONS = [
  {
    id: 'will_import' as const,
    icon: Database,
    title: 'Yes, import data',
    desc: 'From RepairDesk, RepairShopr, or CSV — we\'ll deep-link you to the import tool the moment the wizard finishes.',
  },
  {
    id: 'later' as const,
    icon: Clock,
    title: "I'll do it later",
    desc: 'Settings → Data & Import is always available.',
  },
  {
    id: 'fresh' as const,
    icon: Sparkles,
    title: 'Fresh start',
    desc: 'No legacy data to import.',
  },
];

/**
 * StepImportHandoff — records the user's intent without leaving the wizard.
 *
 * Earlier behavior opened a new tab to /settings?tab=data-import which (since
 * the wizard gate redirects unfinished tenants back to /setup) just spawned
 * a duplicate wizard in the second tab. That was confusing and broken.
 *
 * Now: clicking a card sets `pending.setup_imported_legacy_data` and the
 * Continue button advances to the next wizard step. The "will_import"
 * choice is consumed by StepDone (or the post-wizard dashboard) which
 * deep-links to /settings?tab=data&section=import once the user is fully
 * through the wizard.
 */
export function StepImportHandoff({ pending, onUpdate, onNext, onBack }: StepProps) {
  const selected = pending.setup_imported_legacy_data;

  const handlePick = (id: typeof OPTIONS[number]['id']) => {
    onUpdate({ setup_imported_legacy_data: id });
  };

  return (
    <div className="mx-auto flex max-w-3xl flex-col">
      <h2 className="text-3xl font-semibold tracking-tight text-surface-900 dark:text-surface-50">
        Existing data?
      </h2>
      <p className="mt-2 text-base text-surface-600 dark:text-surface-400">
        Bring customers, tickets, and inventory from your old system. Pick a path now — you can always change it later.
      </p>

      <div className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-3">
        {OPTIONS.map((opt) => {
          const Icon = opt.icon;
          const isSel = selected === opt.id;
          return (
            <button
              key={opt.id}
              type="button"
              onClick={() => handlePick(opt.id)}
              className={[
                'text-left rounded-2xl border-2 p-6 min-h-32 transition-all',
                'hover:shadow-lg motion-reduce:transition-none focus-visible:outline-none',
                'focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2',
                isSel
                  ? 'border-primary-500 bg-primary-50 dark:bg-primary-900/30 ring-2 ring-primary-500/20'
                  : 'border-surface-200 dark:border-surface-700 hover:border-primary-400',
              ].join(' ')}
            >
              <Icon className={`h-8 w-8 ${isSel ? 'text-primary-700 dark:text-primary-300' : 'text-primary-600 dark:text-primary-400'}`} />
              <h3 className="mt-3 text-xl font-medium text-surface-900 dark:text-surface-50">
                {opt.title}
              </h3>
              <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
                {opt.desc}
              </p>
            </button>
          );
        })}
      </div>

      {selected === 'will_import' && (
        <div className="mt-6 rounded-xl border border-primary-300 bg-primary-50 p-4 text-sm text-primary-900 dark:border-primary-500/30 dark:bg-primary-900/20 dark:text-primary-200">
          We'll open the import tool automatically after you finish the wizard. Keep going — your choice is saved.
        </div>
      )}

      <div className="mt-8 flex items-center justify-between">
        <button
          type="button"
          onClick={onBack}
          className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
        >
          <ArrowLeft className="h-4 w-4" />
          Back
        </button>
        <button
          type="button"
          onClick={onNext}
          disabled={!selected}
          className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none"
        >
          Continue
          <ArrowRight className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}
