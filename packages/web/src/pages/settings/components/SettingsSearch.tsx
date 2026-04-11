/**
 * SettingsSearch — global search across all settings metadata. When the user
 * types "passcode" we filter SETTINGS_METADATA and show live matches. Clicking
 * a match jumps to the relevant tab and highlights the setting with a
 * temporary ring animation.
 *
 * This replaces the weaker tab-only filter in SettingsPage.tsx with a
 * setting-level one that reads from our honest metadata source.
 */

import { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import { Search, X, Clock, CheckCircle2, AlertCircle } from 'lucide-react';
import { cn } from '@/utils/cn';
import { searchSettings, type SettingDef } from '../settingsMetadata';

export interface SettingsSearchProps {
  /** Called when the user picks a result. Navigate to the tab and highlight the setting. */
  onNavigate: (tab: string, settingKey: string) => void;
  /** Optional initial value (e.g. from URL hash) */
  initialValue?: string;
  /** Max number of results to show in the dropdown */
  maxResults?: number;
}

/**
 * Highlight a matching setting in the DOM by pulsing a ring around its
 * data-setting-key element. The target element should set
 * `data-setting-key="<key>"` somewhere in the settings tab DOM.
 */
export function highlightSetting(key: string): void {
  const el = document.querySelector<HTMLElement>(`[data-setting-key="${CSS.escape(key)}"]`);
  if (!el) return;
  el.scrollIntoView({ behavior: 'smooth', block: 'center' });
  // Flash a highlight ring for ~2 seconds
  el.classList.add('ring-2', 'ring-primary-500', 'ring-offset-2', 'rounded-lg');
  window.setTimeout(() => {
    el.classList.remove('ring-2', 'ring-primary-500', 'ring-offset-2', 'rounded-lg');
  }, 2000);
}

export function SettingsSearch({ onNavigate, initialValue = '', maxResults = 12 }: SettingsSearchProps) {
  const [query, setQuery] = useState(initialValue);
  const [open, setOpen] = useState(false);
  const [activeIndex, setActiveIndex] = useState(0);
  const wrapperRef = useRef<HTMLDivElement>(null);

  const results = useMemo(() => {
    if (!query.trim()) return [];
    return searchSettings(query).slice(0, maxResults);
  }, [query, maxResults]);

  // Close on click outside
  useEffect(() => {
    function handleClick(e: MouseEvent) {
      if (wrapperRef.current && !wrapperRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClick);
    return () => document.removeEventListener('mousedown', handleClick);
  }, []);

  // Reset active index when results change
  useEffect(() => {
    setActiveIndex(0);
  }, [results]);

  const pick = useCallback(
    (result: SettingDef) => {
      onNavigate(result.tab, result.key);
      // Defer highlight until after the tab switches
      window.setTimeout(() => highlightSetting(result.key), 150);
      setOpen(false);
      setQuery('');
    },
    [onNavigate]
  );

  function handleKey(e: React.KeyboardEvent<HTMLInputElement>) {
    if (!open) return;
    if (e.key === 'ArrowDown') {
      e.preventDefault();
      setActiveIndex((i) => Math.min(i + 1, results.length - 1));
    } else if (e.key === 'ArrowUp') {
      e.preventDefault();
      setActiveIndex((i) => Math.max(i - 1, 0));
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (results[activeIndex]) pick(results[activeIndex]);
    } else if (e.key === 'Escape') {
      setOpen(false);
    }
  }

  return (
    <div ref={wrapperRef} className="relative w-full sm:w-72">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
        <input
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          onKeyDown={handleKey}
          placeholder="Search settings..."
          className="w-full rounded-lg border border-surface-200 bg-white py-1.5 pl-9 pr-8 text-sm placeholder:text-surface-400 focus:border-primary-500 focus:outline-none focus:ring-1 focus:ring-primary-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100"
        />
        {query && (
          <button
            type="button"
            onClick={() => {
              setQuery('');
              setOpen(false);
            }}
            className="absolute right-2 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600"
            aria-label="Clear search"
          >
            <X className="h-3.5 w-3.5" />
          </button>
        )}
      </div>

      {open && query.trim() && (
        <div className="absolute left-0 right-0 top-full z-40 mt-1 max-h-96 overflow-y-auto rounded-lg border border-surface-200 bg-white shadow-xl dark:border-surface-700 dark:bg-surface-900">
          {results.length === 0 ? (
            <p className="px-4 py-6 text-center text-sm text-surface-400">
              No settings match "{query}"
            </p>
          ) : (
            <ul className="divide-y divide-surface-100 dark:divide-surface-800">
              {results.map((r, i) => (
                <li key={`${r.tab}-${r.key}`}>
                  <button
                    type="button"
                    onClick={() => pick(r)}
                    onMouseEnter={() => setActiveIndex(i)}
                    className={cn(
                      'flex w-full flex-col gap-0.5 px-3 py-2 text-left transition-colors',
                      i === activeIndex
                        ? 'bg-primary-50 dark:bg-primary-500/10'
                        : 'hover:bg-surface-50 dark:hover:bg-surface-800'
                    )}
                  >
                    <div className="flex items-center justify-between gap-2">
                      <span className="truncate text-sm font-medium text-surface-900 dark:text-surface-100">
                        {r.label}
                      </span>
                      <StatusPill status={r.status} />
                    </div>
                    <div className="flex items-center gap-2 text-xs text-surface-500">
                      <span className="rounded bg-surface-100 px-1.5 py-0.5 font-mono text-[10px] dark:bg-surface-800">
                        {r.tab}
                      </span>
                      <span className="truncate">{r.tooltip}</span>
                    </div>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      )}
    </div>
  );
}

function StatusPill({ status }: { status: SettingDef['status'] }) {
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
