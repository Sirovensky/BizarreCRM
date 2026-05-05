/**
 * SettingsGlobalSearch — a modal command-palette opened with Ctrl/Cmd+K while
 * anywhere inside /settings. It augments the inline SettingsSearch dropdown
 * for users who prefer keyboard-driven navigation (and works well on phones
 * where dropdowns fight the virtual keyboard for vertical space).
 *
 * Why a separate component?
 *   - The inline SettingsSearch sits in the header and is great for mouse
 *     users browsing tabs. The palette is modal, full-height on mobile, and
 *     cheap to open from any scroll position.
 *   - Both components read from the SAME static index (settingsSearchIndex.ts)
 *     so results are identical — they just render differently.
 *
 * The palette is mounted once at the SettingsPage level and listens for a
 * global Ctrl/Cmd+K shortcut. Results navigate via the onNavigate prop and
 * trigger the shared highlight helper after the tab switch commits.
 */

import {
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
  type KeyboardEvent,
} from 'react';
import { Search, X, Clock, AlertCircle, CheckCircle2, CornerDownLeft } from 'lucide-react';
import { cn } from '@/utils/cn';
import {
  getSettingsIndexSize,
  queryIndex,
  type SettingsIndexEntry,
} from '../settingsSearchIndex';
import { highlightSetting } from './SettingsSearch';

export interface SettingsGlobalSearchProps {
  /** Called when the user picks a result. Navigates to the tab by ID. */
  onNavigate: (tab: string, settingKey: string) => void;
  /** Max number of results rendered in the palette. */
  maxResults?: number;
  /** Keyboard shortcut character (default: "k"). */
  shortcutKey?: string;
}

export function SettingsGlobalSearch({
  onNavigate,
  maxResults = 25,
  shortcutKey = 'k',
}: SettingsGlobalSearchProps) {
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState('');
  const [activeIndex, setActiveIndex] = useState(0);
  const inputRef = useRef<HTMLInputElement>(null);

  // Global shortcut: Ctrl/Cmd+K opens the palette.
  useEffect(() => {
    function handleGlobalKey(e: globalThis.KeyboardEvent) {
      const normalized = e.key?.toLowerCase?.();
      if ((e.metaKey || e.ctrlKey) && normalized === shortcutKey) {
        e.preventDefault();
        setOpen(true);
      }
      if (normalized === 'escape') setOpen(false);
    }
    window.addEventListener('keydown', handleGlobalKey);
    return () => window.removeEventListener('keydown', handleGlobalKey);
  }, [shortcutKey]);

  // Autofocus the input when the modal opens.
  useEffect(() => {
    if (open) {
      const id = window.setTimeout(() => inputRef.current?.focus(), 20);
      return () => window.clearTimeout(id);
    }
    // Reset query on close for a clean next-open.
    setQuery('');
    setActiveIndex(0);
    return undefined;
  }, [open]);

  const results = useMemo(
    () => queryIndex(query, maxResults),
    [query, maxResults]
  );

  // Clamp the active index whenever the result set shrinks/grows.
  useEffect(() => {
    if (results.length === 0) {
      setActiveIndex(0);
      return;
    }
    if (activeIndex >= results.length) setActiveIndex(results.length - 1);
  }, [results, activeIndex]);

  const pick = useCallback(
    (entry: SettingsIndexEntry) => {
      onNavigate(entry.tab, entry.key);
      window.setTimeout(() => highlightSetting(entry.key), 150);
      setOpen(false);
    },
    [onNavigate]
  );

  function handleKey(e: KeyboardEvent<HTMLInputElement>) {
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActiveIndex((i) => Math.min(i + 1, Math.max(0, results.length - 1)));
      return;
    }
    if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActiveIndex((i) => Math.max(i - 1, 0));
      return;
    }
    if (e.key === 'Enter') {
      e.preventDefault();
      const hit = results[activeIndex];
      if (hit) pick(hit);
      return;
    }
    if (e.key === 'Escape') setOpen(false);
  }

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="settings-palette-title"
      className="fixed inset-0 z-[80] flex items-start justify-center bg-black/50 p-4 sm:pt-[8vh]"
      onClick={() => setOpen(false)}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[80vh] w-full max-w-xl flex-col overflow-hidden rounded-xl bg-white shadow-2xl dark:bg-surface-900 dark:ring-1 dark:ring-surface-700"
      >
        <header className="flex items-center gap-2 border-b border-surface-100 px-3 py-2 dark:border-surface-800">
          <Search className="h-4 w-4 text-surface-400" />
          <input
            ref={inputRef}
            type="text"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            onKeyDown={handleKey}
            placeholder="Search settings (try: tax, receipt, SMS, passcode)"
            className="flex-1 bg-transparent py-1.5 text-sm text-surface-900 placeholder:text-surface-400 focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-primary-400 dark:text-surface-100"
            aria-label="Search settings"
          />
          <button
            type="button"
            onClick={() => setOpen(false)}
            className="rounded p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800"
            aria-label="Close search"
          >
            <X className="h-4 w-4" />
          </button>
        </header>

        <h2 id="settings-palette-title" className="sr-only">
          Search settings
        </h2>

        <ResultsList
          query={query}
          results={results}
          activeIndex={activeIndex}
          onHover={setActiveIndex}
          onPick={pick}
        />

        <footer className="flex items-center justify-between border-t border-surface-100 bg-surface-50 px-3 py-2 text-[11px] text-surface-500 dark:border-surface-800 dark:bg-surface-800/60">
          <span>{getSettingsIndexSize()} settings indexed</span>
          <span className="hidden items-center gap-1 sm:inline-flex">
            <kbd className="rounded bg-white px-1 py-0.5 font-mono text-[10px] text-surface-600 shadow-sm dark:bg-surface-900 dark:text-surface-300">
              Enter
            </kbd>
            <CornerDownLeft className="h-3 w-3" />
            to open
          </span>
        </footer>
      </div>
    </div>
  );
}

interface ResultsListProps {
  query: string;
  results: SettingsIndexEntry[];
  activeIndex: number;
  onHover: (i: number) => void;
  onPick: (entry: SettingsIndexEntry) => void;
}

function ResultsList({ query, results, activeIndex, onHover, onPick }: ResultsListProps) {
  if (!query.trim()) {
    return (
      <div className="px-4 py-6 text-center text-xs text-surface-400">
        Start typing to find a setting across every tab.
      </div>
    );
  }
  if (results.length === 0) {
    return (
      <div className="px-4 py-6 text-center text-xs text-surface-400">
        No settings match "{query}".
      </div>
    );
  }
  return (
    <ul className="flex-1 overflow-y-auto py-1">
      {results.map((entry, i) => (
        <li key={`${entry.tab}-${entry.key}`}>
          <button
            type="button"
            onClick={() => onPick(entry)}
            onMouseEnter={() => onHover(i)}
            className={cn(
              'flex w-full flex-col gap-0.5 px-4 py-2 text-left transition-colors',
              i === activeIndex
                ? 'bg-primary-50 dark:bg-primary-500/10'
                : 'hover:bg-surface-50 dark:hover:bg-surface-800/70'
            )}
          >
            <div className="flex items-center justify-between gap-2">
              <span className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
                {entry.label}
              </span>
              <StatusPill status={entry.status} />
            </div>
            <div className="flex items-center gap-2 text-[11px] text-surface-500">
              <span className="rounded bg-surface-100 px-1.5 py-0.5 font-mono text-[10px] dark:bg-surface-800">
                {entry.tab}
              </span>
              <span className="truncate">{entry.description}</span>
            </div>
          </button>
        </li>
      ))}
    </ul>
  );
}

function StatusPill({ status }: { status: SettingsIndexEntry['status'] }) {
  if (status === 'live') {
    return (
      <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-green-100 px-1.5 py-0.5 text-[10px] font-semibold text-green-700 dark:bg-green-500/20 dark:text-green-300">
        <CheckCircle2 className="h-2.5 w-2.5" />
        Live
      </span>
    );
  }
  if (status === 'beta') {
    return (
      <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-amber-100 px-1.5 py-0.5 text-[10px] font-semibold text-amber-700 dark:bg-amber-500/20 dark:text-amber-300">
        <AlertCircle className="h-2.5 w-2.5" />
        Beta
      </span>
    );
  }
  return (
    <span className="inline-flex shrink-0 items-center gap-0.5 rounded-full bg-surface-100 px-1.5 py-0.5 text-[10px] font-semibold text-surface-600 dark:bg-surface-800 dark:text-surface-300">
      <Clock className="h-2.5 w-2.5" />
      Soon
    </span>
  );
}
