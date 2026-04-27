import { Store, Sun, Moon, Monitor, ArrowRight } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { useUiStore } from '@/stores/uiStore';

type ThemeOption = 'light' | 'dark' | 'system';

const THEME_OPTIONS: Array<{ id: ThemeOption; label: string; description: string; Icon: typeof Sun }> = [
  { id: 'light', label: 'Light', description: 'Bright and clean', Icon: Sun },
  { id: 'dark', label: 'Dark', description: 'Easier on the eyes', Icon: Moon },
  { id: 'system', label: 'System', description: 'Follows your OS setting', Icon: Monitor },
];

/**
 * Step 1 — Welcome.
 * Collects store_name (pre-filled from signup) and theme preference.
 * Theme changes are applied immediately via useUiStore so the rest of the
 * wizard reflects the choice. This gives the user a visceral preview of what
 * their dashboard will feel like.
 */
export function StepWelcome({ pending, onUpdate, onNext }: StepProps) {
  const { theme, setTheme } = useUiStore();
  const storeName = pending.store_name || '';

  const handleThemeChange = (newTheme: ThemeOption) => {
    setTheme(newTheme); // applies to <html> immediately
    onUpdate({ theme: newTheme });
  };

  const canAdvance = storeName.trim().length >= 2;

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Store className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Welcome to BizarreCRM
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Let's set up your shop. This takes about 2 minutes.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {/* Store name (editable, pre-filled from signup) */}
        <div>
          <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Store name <span className="text-red-500">*</span>
          </label>
          <input
            type="text"
            value={storeName}
            onChange={(e) => onUpdate({ store_name: e.target.value })}
            placeholder="Joe's Phone Repair"
            autoFocus
            maxLength={100}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
          />
          <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
            This appears on receipts, invoices, and the customer portal.
          </p>
        </div>

        {/* Theme picker */}
        <div>
          <label className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">
            Choose your theme
          </label>
          <div className="grid grid-cols-3 gap-3">
            {THEME_OPTIONS.map(({ id, label, description, Icon }) => {
              const selected = theme === id;
              return (
                <button
                  key={id}
                  type="button"
                  onClick={() => handleThemeChange(id)}
                  className={`flex flex-col items-center gap-2 rounded-xl border-2 p-4 transition-all ${
                    selected
                      ? 'border-primary-500 bg-primary-50 ring-2 ring-primary-500/20 dark:border-primary-400 dark:bg-primary-500/10'
                      : 'border-surface-200 bg-white hover:border-surface-300 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:hover:border-surface-600 dark:hover:bg-surface-700'
                  }`}
                >
                  <Icon className={`h-6 w-6 ${selected ? 'text-primary-600 dark:text-primary-400' : 'text-surface-500'}`} />
                  <div className={`text-sm font-semibold ${selected ? 'text-primary-700 dark:text-primary-300' : 'text-surface-700 dark:text-surface-300'}`}>
                    {label}
                  </div>
                  <div className="text-center text-xs text-surface-500 dark:text-surface-400">
                    {description}
                  </div>
                </button>
              );
            })}
          </div>
          <p className="mt-2 text-xs text-surface-500 dark:text-surface-400">
            You can change this anytime in Settings &rarr; Store.
          </p>
        </div>

        <div className="flex justify-end">
          <button
            type="button"
            onClick={onNext}
            disabled={!canAdvance}
            className="flex items-center gap-2 rounded-lg bg-primary-600 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
          >
            Next — Store info
            <ArrowRight className="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  );
}
