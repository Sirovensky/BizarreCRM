/**
 * ShortcutReferenceCard — Day-1 Onboarding (audit section 42, idea 14)
 *
 * A tiny popover triggered by the `?` button in the Header. Lists the top
 * keyboard shortcuts a new shop owner should know about so they don't have
 * to hunt through documentation. Renders as a modal-ish dropdown attached
 * to the body; the parent (Header) controls visibility via props.
 *
 * The shortcut list is static — it's what the app actually binds. If a new
 * shortcut is added globally, update SHORTCUTS below.
 */
import { useEffect, useRef } from 'react';
import { X, Keyboard } from 'lucide-react';

interface ShortcutEntry {
  keys: ReadonlyArray<string>;
  description: string;
}

// Keep in sync with the global keydown handlers in Header.tsx / App.tsx /
// POS pages. If a binding moves, update this list — it's the ONLY place we
// advertise shortcuts to the user so a stale entry is a real problem.
const SHORTCUTS: ReadonlyArray<{ section: string; items: ReadonlyArray<ShortcutEntry> }> = [
  {
    section: 'Global',
    items: [
      { keys: ['Ctrl', 'K'], description: 'Open command palette / search' },
      { keys: ['Esc'], description: 'Close modal or dialog' },
      { keys: ['?'], description: 'Show this reference card' },
    ],
  },
  {
    section: 'Quick jump (outside POS)',
    items: [
      { keys: ['F2'], description: 'Point of sale' },
      { keys: ['F3'], description: 'New customer' },
      { keys: ['F4'], description: 'Tickets list' },
    ],
  },
  {
    section: 'Point of Sale',
    items: [
      { keys: ['F1'], description: 'Repairs tab' },
      { keys: ['F2'], description: 'Products tab' },
      { keys: ['F3'], description: 'Misc tab' },
      { keys: ['F4'], description: 'Customer search' },
      { keys: ['Shift', 'F5'], description: 'Complete sale' },
      { keys: ['F6'], description: 'Returns' },
    ],
  },
  {
    section: 'Forms',
    items: [
      { keys: ['Ctrl', 'Enter'], description: 'Save and continue' },
      { keys: ['Ctrl', 'S'], description: 'Save without closing' },
    ],
  },
];

interface ShortcutReferenceCardProps {
  open: boolean;
  onClose: () => void;
}

export function ShortcutReferenceCard({ open, onClose }: ShortcutReferenceCardProps) {
  const panelRef = useRef<HTMLDivElement>(null);

  // Close on Escape and outside click.
  useEffect(() => {
    if (!open) return;
    const handleKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    const handleClick = (e: MouseEvent) => {
      if (panelRef.current && !panelRef.current.contains(e.target as Node)) {
        onClose();
      }
    };
    document.addEventListener('keydown', handleKey);
    document.addEventListener('mousedown', handleClick);
    return () => {
      document.removeEventListener('keydown', handleKey);
      document.removeEventListener('mousedown', handleClick);
    };
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div className="fixed inset-0 z-[60] flex items-start justify-center bg-black/20 p-4 pt-20 backdrop-blur-sm">
      <div
        ref={panelRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby="shortcut-card-title"
        className="w-full max-w-md overflow-hidden rounded-2xl border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-900"
      >
        <div className="flex items-center justify-between border-b border-surface-100 px-5 py-4 dark:border-surface-800">
          <div className="flex items-center gap-2">
            <Keyboard className="h-4.5 w-4.5 text-primary-500" />
            <h2 id="shortcut-card-title" className="text-sm font-semibold text-surface-900 dark:text-surface-100">
              Keyboard shortcuts
            </h2>
          </div>
          <button
            type="button"
            onClick={onClose}
            className="rounded-md p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-800 dark:hover:text-surface-200"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>
        <div className="max-h-[70vh] overflow-y-auto p-5">
          {SHORTCUTS.map((section) => (
            <div key={section.section} className="mb-4 last:mb-0">
              <h3 className="mb-2 text-[11px] font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500">
                {section.section}
              </h3>
              <ul className="space-y-1.5">
                {section.items.map((item) => (
                  <li
                    key={item.description}
                    className="flex items-center justify-between rounded-lg px-2 py-1.5 text-sm text-surface-700 dark:text-surface-300"
                  >
                    <span>{item.description}</span>
                    <span className="flex items-center gap-1">
                      {item.keys.map((k) => (
                        <kbd
                          key={k}
                          className="rounded border border-surface-300 bg-surface-50 px-1.5 py-0.5 text-[11px] font-semibold text-surface-700 shadow-sm dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200"
                        >
                          {k}
                        </kbd>
                      ))}
                    </span>
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
