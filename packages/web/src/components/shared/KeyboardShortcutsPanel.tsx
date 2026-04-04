import { useEffect, useCallback } from 'react';

interface ShortcutItem {
  keys: string[];
  description: string;
}

interface ShortcutGroup {
  title: string;
  shortcuts: ShortcutItem[];
}

const SHORTCUT_GROUPS: ShortcutGroup[] = [
  {
    title: 'Navigation',
    shortcuts: [
      { keys: ['F2'], description: 'POS / Check-In' },
      { keys: ['F3'], description: 'New Customer' },
      { keys: ['F4'], description: 'Tickets' },
    ],
  },
  {
    title: 'Actions',
    shortcuts: [
      { keys: ['F5'], description: 'Open Search' },
      { keys: ['Ctrl', 'K'], description: 'Open Search' },
    ],
  },
  {
    title: 'Views',
    shortcuts: [
      { keys: ['?'], description: 'Keyboard shortcuts' },
      { keys: ['Esc'], description: 'Close modal / dialog' },
    ],
  },
];

function KeyBadge({ label }: { label: string }) {
  return (
    <kbd className="inline-flex items-center justify-center min-w-[28px] px-2 py-1 text-xs font-semibold rounded-md border border-surface-300 bg-surface-100 text-surface-700 shadow-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-200">
      {label}
    </kbd>
  );
}

interface KeyboardShortcutsPanelProps {
  open: boolean;
  onClose: () => void;
}

export function KeyboardShortcutsPanel({ open, onClose }: KeyboardShortcutsPanelProps) {
  const handleKeyDown = useCallback(
    (e: KeyboardEvent) => {
      if (e.key === 'Escape' || e.key === '?') {
        e.preventDefault();
        onClose();
      }
    },
    [onClose]
  );

  useEffect(() => {
    if (!open) return;
    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [open, handleKeyDown]);

  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-[100] flex items-center justify-center bg-black/50 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-5 flex items-center justify-between">
          <h2 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            Keyboard Shortcuts
          </h2>
          <button
            onClick={onClose}
            className="rounded-md p-1 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
          >
            <span className="sr-only">Close</span>
            <svg className="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
              <path strokeLinecap="round" strokeLinejoin="round" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div className="space-y-5">
          {SHORTCUT_GROUPS.map((group) => (
            <div key={group.title}>
              <h3 className="mb-2 text-xs font-medium uppercase tracking-wider text-surface-500 dark:text-surface-400">
                {group.title}
              </h3>
              <div className="space-y-2">
                {group.shortcuts.map((shortcut, i) => (
                  <div
                    key={i}
                    className="flex items-center justify-between rounded-lg px-3 py-2 hover:bg-surface-50 dark:hover:bg-surface-700/50"
                  >
                    <span className="text-sm text-surface-700 dark:text-surface-300">
                      {shortcut.description}
                    </span>
                    <div className="flex items-center gap-1">
                      {shortcut.keys.map((key, j) => (
                        <span key={j} className="flex items-center gap-1">
                          {j > 0 && (
                            <span className="text-xs text-surface-400">+</span>
                          )}
                          <KeyBadge label={key} />
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        <p className="mt-5 text-center text-xs text-surface-400 dark:text-surface-500">
          Press <KeyBadge label="?" /> or <KeyBadge label="Esc" /> to close
        </p>
      </div>
    </div>
  );
}
