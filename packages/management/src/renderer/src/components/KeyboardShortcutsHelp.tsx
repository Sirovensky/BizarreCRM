import { useCallback, useEffect, useRef, useState } from 'react';
import { Keyboard } from 'lucide-react';

interface Shortcut {
  keys: string[];
  desc: string;
  group: 'Navigation' | 'Actions' | 'Data' | 'Mouse';
}

/** True on macOS (both renderer and Electron renderer process).
 * DASH-ELEC-125: Prefer navigator.userAgentData?.platform (UACH, Chrome 90+)
 * to navigator.platform which is deprecated and returns "" in future Chromium.
 * Falls back to userAgent Macintosh string for older contexts.
 */
const IS_MAC = (() => {
  if (typeof navigator === 'undefined') return process.platform === 'darwin';
  const uaData = (navigator as Navigator & { userAgentData?: { platform?: string } }).userAgentData;
  if (uaData?.platform) return uaData.platform === 'macOS';
  return navigator.userAgent.includes('Macintosh');
})();

const SHORTCUTS: Shortcut[] = [
  { keys: IS_MAC ? ['⌘', 'K'] : ['Ctrl', 'K'], desc: 'Open command palette', group: 'Navigation' },
  { keys: ['/'], desc: 'Open command palette (from anywhere)', group: 'Navigation' },
  { keys: ['?'], desc: 'Show this help overlay', group: 'Navigation' },
  { keys: ['Esc'], desc: 'Close any open overlay', group: 'Navigation' },
  { keys: ['↑', '↓'], desc: 'Navigate command palette / tables', group: 'Navigation' },
  { keys: ['Enter'], desc: 'Run the focused command', group: 'Actions' },
  { keys: ['Tab'], desc: 'Move focus forward (standard)', group: 'Navigation' },
  // DASH-ELEC-123: Mouse-only actions moved to their own section so keyboard-only operators are not misled.
  { keys: ['Click'], desc: 'Expand row details (tenant / crash / alert)', group: 'Mouse' },
  { keys: ['Hover', 'Click'], desc: 'Click copy icon next to IPs, slugs, and secrets to copy', group: 'Mouse' },
];

/**
 * Global help overlay bound to the `?` key. Kept separate from the command
 * palette so operators who already memorised the shortcuts (which they
 * will, since the palette covers the main workflow) never accidentally
 * trip into a help dialog. `?` is US-keyboard-specific (Shift+/); other
 * layouts won't trigger it, which is the intended behaviour — the
 * command palette's `/` fallback still works everywhere.
 */
const TITLE_ID = 'keyboard-shortcuts-help-title';

export function KeyboardShortcutsHelp() {
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  const onGlobalKeyDown = useCallback((e: KeyboardEvent) => {
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
    window.addEventListener('keydown', onGlobalKeyDown);
    return () => window.removeEventListener('keydown', onGlobalKeyDown);
  }, [onGlobalKeyDown]);

  // Focus the dialog panel when it opens.
  useEffect(() => {
    if (open) {
      containerRef.current?.focus();
    }
  }, [open]);

  // Tab focus trap inside the dialog.
  const handleDialogKeyDown = useCallback((e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'Escape') {
      setOpen(false);
      return;
    }
    if (e.key === 'Tab') {
      const el = containerRef.current;
      if (!el) return;
      const focusable = Array.from(
        el.querySelectorAll<HTMLElement>(
          'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        )
      ).filter((n) => !n.hasAttribute('disabled'));
      if (focusable.length === 0) return;
      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last.focus();
        }
      } else {
        if (document.activeElement === last) {
          e.preventDefault();
          first.focus();
        }
      }
    }
  }, []);

  if (!open) return null;

  const groups = Array.from(new Set(SHORTCUTS.map((s) => s.group))) as Shortcut['group'][];

  return (
    <div
      className="fixed inset-0 z-50 flex items-start justify-center pt-[max(1rem,min(6rem,10vh))] bg-black/60 backdrop-blur-sm"
      onClick={() => setOpen(false)}
    >
      <div
        ref={containerRef}
        role="dialog"
        aria-modal="true"
        aria-labelledby={TITLE_ID}
        tabIndex={-1}
        className="w-[min(480px,calc(100vw-2rem))] bg-surface-900 border border-surface-700 rounded-xl shadow-2xl overflow-hidden outline-none"
        onClick={(e) => e.stopPropagation()}
        onKeyDown={handleDialogKeyDown}
      >
        <div className="flex items-center justify-between px-4 py-3 border-b border-surface-800">
          <div className="flex items-center gap-2">
            <Keyboard className="w-4 h-4 text-accent-400" aria-hidden="true" />
            <span id={TITLE_ID} className="text-sm font-semibold text-surface-200">Keyboard shortcuts</span>
          </div>
          <button
            onClick={() => setOpen(false)}
            aria-label="Close keyboard shortcuts"
            className="text-[10px] text-surface-500 font-mono border border-surface-700 rounded px-1.5 py-0.5 hover:bg-surface-800 hover:text-surface-300 transition-colors"
          >
            esc
          </button>
        </div>
        <div className="p-4 space-y-4 max-h-[60vh] overflow-y-auto">
          {groups.map((g) => (
            <div key={g}>
              <h3 className="text-[10px] font-semibold text-surface-500 uppercase tracking-wider mb-2">
                {g}
              </h3>
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
