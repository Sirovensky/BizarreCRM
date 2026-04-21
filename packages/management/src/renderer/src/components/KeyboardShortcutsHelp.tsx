import { useCallback, useEffect, useState } from 'react';
import { Keyboard } from 'lucide-react';

interface Shortcut {
  keys: string[];
  desc: string;
  group: 'Navigation' | 'Actions' | 'Data';
}

const SHORTCUTS: Shortcut[] = [
  { keys: ['Ctrl', 'K'], desc: 'Open command palette', group: 'Navigation' },
  { keys: ['/'], desc: 'Open command palette (from anywhere)', group: 'Navigation' },
  { keys: ['?'], desc: 'Show this help overlay', group: 'Navigation' },
  { keys: ['Esc'], desc: 'Close any open overlay', group: 'Navigation' },
  { keys: ['↑', '↓'], desc: 'Navigate command palette / tables', group: 'Navigation' },
  { keys: ['Enter'], desc: 'Run the focused command', group: 'Actions' },
  { keys: ['Tab'], desc: 'Move focus forward (standard)', group: 'Navigation' },
  { keys: ['Click'], desc: 'Click tenant / crash / alert row to expand details', group: 'Data' },
  { keys: ['Hover + Click'], desc: 'Click the copy icon next to IPs, slugs, and secrets to copy', group: 'Data' },
];

/**
 * Global help overlay bound to the `?` key. Kept separate from the command
 * palette so operators who already memorised the shortcuts (which they
 * will, since the palette covers the main workflow) never accidentally
 * trip into a help dialog. `?` is US-keyboard-specific (Shift+/); other
 * layouts won't trigger it, which is the intended behaviour — the
 * command palette's `/` fallback still works everywhere.
 */
export function KeyboardShortcutsHelp() {
  const [open, setOpen] = useState(false);

  const onKeyDown = useCallback((e: KeyboardEvent) => {
    if (open && e.key === 'Escape') {
      setOpen(false);
      return;
    }
    // `?` with no modifiers, not inside an input.
    if (e.key === '?' && !e.ctrlKey && !e.metaKey && !e.altKey) {
      const tag = (e.target as HTMLElement | null)?.tagName;
      if (tag !== 'INPUT' && tag !== 'TEXTAREA' && tag !== 'SELECT') {
        e.preventDefault();
        setOpen((v) => !v);
      }
    }
  }, [open]);

  useEffect(() => {
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [onKeyDown]);

  if (!open) return null;

  const groups = Array.from(new Set(SHORTCUTS.map((s) => s.group))) as Shortcut['group'][];

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-24 bg-black/60 backdrop-blur-sm"
      onClick={() => setOpen(false)}
    >
      <div
        className="w-[min(480px,calc(100vw-2rem))] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl overflow-hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between px-4 py-3 border-b border-surface-800">
          <div className="flex items-center gap-2">
            <Keyboard className="w-4 h-4 text-accent-400" />
            <span className="text-sm font-semibold text-surface-200">Keyboard shortcuts</span>
          </div>
          <span className="text-[10px] text-surface-500 font-mono border border-surface-700 rounded px-1.5 py-0.5">
            esc
          </span>
        </div>
        <div className="p-4 space-y-4 max-h-[60vh] overflow-y-auto">
          {groups.map((g) => (
            <div key={g}>
              <div className="text-[10px] font-semibold text-surface-500 uppercase tracking-wider mb-2">
                {g}
              </div>
              <div className="space-y-1.5">
                {SHORTCUTS.filter((s) => s.group === g).map((s) => (
                  <div key={s.desc} className="flex items-center justify-between gap-3">
                    <span className="text-xs text-surface-300 flex-1">{s.desc}</span>
                    <div className="flex items-center gap-1 flex-shrink-0">
                      {s.keys.map((k, i) => (
                        <span
                          key={i}
                          className="text-[10px] font-mono text-surface-400 bg-surface-950 border border-surface-700 rounded px-1.5 py-0.5 min-w-[18px] text-center"
                        >
                          {k}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
