import { Database, Clock, Sparkles, ArrowUpRight } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';

const OPTIONS = [
  {
    id: 'will_import' as const,
    icon: Database,
    title: 'Yes, import data',
    desc: 'From RepairDesk, RepairShopr, or CSV',
    cta: 'Open import wizard',
  },
  {
    id: 'later' as const,
    icon: Clock,
    title: "I'll do it later",
    desc: 'Settings → Data & Import is always available',
    cta: undefined,
  },
  {
    id: 'fresh' as const,
    icon: Sparkles,
    title: 'Fresh start',
    desc: 'No legacy data to import',
    cta: undefined,
  },
];

export function StepImportHandoff({ pending, onUpdate, onNext }: StepProps) {
  const selected = pending.setup_imported_legacy_data;

  const handlePick = (id: typeof OPTIONS[number]['id']) => {
    onUpdate({ setup_imported_legacy_data: id });
    if (id === 'will_import') {
      window.open('/settings?tab=data-import', '_blank', 'noopener');
    }
    // Small delay so the user sees the selection state before advancing
    setTimeout(() => onNext(), 200);
  };

  return (
    <div className="flex flex-col">
      <WizardBreadcrumb prevLabel="Step 6 · Store info" currentLabel="Step 7 · Import" nextLabel="Step 8 · Repair pricing" />
      <h2 className="mt-6 text-3xl font-semibold tracking-tight text-surface-900 dark:text-surface-50">
        Existing data?
      </h2>
      <p className="mt-2 text-base text-surface-600 dark:text-surface-400">
        Bring customers, tickets, and inventory from your old system.
      </p>

      <div className="mt-8 grid grid-cols-1 gap-4 md:grid-cols-3">
        {OPTIONS.map((opt) => {
          const Icon = opt.icon;
          const isSel = selected === opt.id;
          return (
            <button
              key={opt.id}
              onClick={() => handlePick(opt.id)}
              className={[
                'text-left rounded-2xl border-2 p-6 min-h-32 transition-all',
                'hover:shadow-lg motion-reduce:transition-none focus-visible:outline-none',
                'focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2',
                isSel
                  ? 'border-primary-600 bg-primary-50 dark:bg-primary-900/30'
                  : 'border-surface-200 dark:border-surface-700 hover:border-primary-400',
              ].join(' ')}
            >
              <Icon className="h-8 w-8 text-primary-600 dark:text-primary-400" />
              <h3 className="mt-3 text-xl font-medium text-surface-900 dark:text-surface-50">
                {opt.title}
              </h3>
              <p className="mt-1 text-sm text-surface-600 dark:text-surface-400">
                {opt.desc}
              </p>
              {opt.cta && (
                <span className="mt-3 inline-flex items-center gap-1 text-sm font-medium text-primary-700 dark:text-primary-400">
                  {opt.cta}
                  <ArrowUpRight className="h-4 w-4" />
                </span>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}
