import { useState, useEffect, useRef, useCallback, useMemo } from 'react';
import { useNavigate } from 'react-router-dom';
import { useUiStore } from '@/stores/uiStore';
import { searchApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import {
  Search,
  Ticket,
  Users,
  Package,
  FileText,
  Loader2,
  Clock,
  X,
  CornerDownLeft,
  ArrowUp,
  ArrowDown,
} from 'lucide-react';

interface SearchResult {
  id: number;
  display: string;
  type: string;
  subtitle?: string;
}

interface GroupedResults {
  tickets: SearchResult[];
  customers: SearchResult[];
  inventory: SearchResult[];
  invoices: SearchResult[];
}

const RECENT_SEARCHES_KEY = 'crm_recent_searches';
const MAX_RECENT = 10;
const MIN_QUERY_LENGTH = 2;
const TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

interface RecentSearchEntry {
  query: string;
  storedAt: number;
}

function getRecentSearches(): string[] {
  try {
    const stored = sessionStorage.getItem(RECENT_SEARCHES_KEY);
    if (!stored) return [];
    const parsed: unknown = JSON.parse(stored);
    if (!Array.isArray(parsed)) throw new Error('not array');
    const now = Date.now();
    return (parsed as RecentSearchEntry[])
      .filter((e) => now - e.storedAt < TTL_MS)
      .map((e) => e.query);
  } catch (err) {
    console.warn('CommandPalette: corrupted search history, clearing', err);
    sessionStorage.removeItem(RECENT_SEARCHES_KEY);
    return [];
  }
}

function saveRecentSearch(query: string) {
  if (query.length < MIN_QUERY_LENGTH) return;
  try {
    const stored = sessionStorage.getItem(RECENT_SEARCHES_KEY);
    let existing: RecentSearchEntry[] = [];
    if (stored) {
      try {
        const parsed: unknown = JSON.parse(stored);
        if (!Array.isArray(parsed)) throw new Error('not array');
        existing = parsed as RecentSearchEntry[];
      } catch (err) {
        console.warn('CommandPalette: corrupted search history on save, clearing', err);
        sessionStorage.removeItem(RECENT_SEARCHES_KEY);
      }
    }
    const now = Date.now();
    const filtered = existing
      .filter((e) => e.query !== query && now - e.storedAt < TTL_MS);
    filtered.unshift({ query, storedAt: now });
    sessionStorage.setItem(
      RECENT_SEARCHES_KEY,
      JSON.stringify(filtered.slice(0, MAX_RECENT)),
    );
  } catch (err) {
    // sessionStorage unavailable — skip silently
    console.warn('[CommandPalette] persisting recent searches failed', err);
  }
}

const typeConfig: Record<string, { icon: React.ReactNode; label: string; path: (id: number) => string; color: string }> = {
  ticket: {
    icon: <Ticket className="h-4 w-4" />,
    label: 'Tickets',
    path: (id) => `/tickets/${id}`,
    color: 'text-blue-500 bg-blue-50 dark:bg-blue-500/10',
  },
  customer: {
    icon: <Users className="h-4 w-4" />,
    label: 'Customers',
    path: (id) => `/customers/${id}`,
    color: 'text-emerald-500 bg-emerald-50 dark:bg-emerald-500/10',
  },
  inventory: {
    icon: <Package className="h-4 w-4" />,
    label: 'Inventory',
    path: (id) => `/inventory/${id}`,
    color: 'text-amber-500 bg-amber-50 dark:bg-amber-500/10',
  },
  invoice: {
    icon: <FileText className="h-4 w-4" />,
    label: 'Invoices',
    path: (id) => `/invoices/${id}`,
    color: 'text-purple-500 bg-purple-50 dark:bg-purple-500/10',
  },
};

export function CommandPalette() {
  const navigate = useNavigate();
  const { commandPaletteOpen, setCommandPaletteOpen } = useUiStore();
  const inputRef = useRef<HTMLInputElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  // SCAN-1117: monotonically increasing request id so a slow prior search
  // response can't overwrite a newer one if the user types faster than the
  // network round-trip.
  const reqSeq = useRef(0);

  const [query, setQuery] = useState('');
  const [results, setResults] = useState<GroupedResults | null>(null);
  const [loading, setLoading] = useState(false);
  const [searchError, setSearchError] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState(0);
  // WEB-FD-008 fix: previously this was a one-shot lazy initializer
  // (`useState(getRecentSearches)`) so a search saved during the same session
  // never appeared under "Recent" until a full page reload. Re-read from
  // sessionStorage every time the palette opens so the user sees their just-
  // executed search the next time they hit Cmd-K.
  const [recentSearches, setRecentSearches] = useState<string[]>(getRecentSearches);
  useEffect(() => {
    if (commandPaletteOpen) setRecentSearches(getRecentSearches());
  }, [commandPaletteOpen]);

  // Flatten results into a single ordered list for keyboard navigation (memoized)
  const flatResults = useMemo<SearchResult[]>(() =>
    results
      ? [
          ...results.tickets,
          ...results.customers,
          ...results.inventory,
          ...results.invoices,
        ]
      : [],
    [results],
  );

  const totalCount = flatResults.length;

  // Close handler
  const close = useCallback(() => {
    setCommandPaletteOpen(false);
    setQuery('');
    setResults(null);
    setSelectedIndex(0);
  }, [setCommandPaletteOpen]);

  // Focus input on open — return a cleanup so the timer doesn't fire after
  // an unmount (W10 fix). A stale callback trying to focus a detached input
  // is harmless but still creates a memory retention path.
  useEffect(() => {
    if (!commandPaletteOpen) return;
    const timer = setTimeout(() => inputRef.current?.focus(), 50);
    return () => clearTimeout(timer);
  }, [commandPaletteOpen]);

  // Debounced search
  useEffect(() => {
    if (query.trim().length < MIN_QUERY_LENGTH) {
      setResults(null);
      setSelectedIndex(0);
      return;
    }

    const timer = setTimeout(async () => {
      // SCAN-1117: capture the request id BEFORE awaiting so late responses
      // from a stale query can be discarded when they resolve.
      const myReqId = ++reqSeq.current;
      setLoading(true);
      setSearchError(false);
      try {
        const res = await searchApi.global(query.trim());
        if (myReqId !== reqSeq.current) return; // stale — a newer search is in flight
        const data = res.data.data as GroupedResults;
        setResults(data);
        setSelectedIndex(0);
      } catch (err) {
        if (myReqId !== reqSeq.current) return;
        // Surface the failure as an explicit error state so the palette shows
        // "Search unavailable" instead of a misleading "No results found".
        console.error('[CommandPalette] search failed', err);
        setResults({ tickets: [], customers: [], inventory: [], invoices: [] });
        setSearchError(true);
      } finally {
        if (myReqId === reqSeq.current) setLoading(false);
      }
    }, 300);

    return () => clearTimeout(timer);
  }, [query]);

  // Navigate to result
  const navigateTo = useCallback(
    (result: SearchResult) => {
      const config = typeConfig[result.type];
      if (config) {
        saveRecentSearch(query.trim());
        navigate(config.path(result.id));
        close();
      }
    },
    [navigate, close, query]
  );

  // Keyboard navigation
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === 'ArrowDown') {
        e.preventDefault();
        setSelectedIndex((i) => (totalCount > 0 ? (i + 1) % totalCount : 0));
      } else if (e.key === 'ArrowUp') {
        e.preventDefault();
        setSelectedIndex((i) => (totalCount > 0 ? (i - 1 + totalCount) % totalCount : 0));
      } else if (e.key === 'Enter' && flatResults[selectedIndex]) {
        e.preventDefault();
        navigateTo(flatResults[selectedIndex]);
      } else if (e.key === 'Escape') {
        e.preventDefault();
        close();
      }
    },
    [totalCount, flatResults, selectedIndex, navigateTo, close]
  );

  // Scroll selected item into view
  useEffect(() => {
    if (!listRef.current) return;
    const selected = listRef.current.querySelector('[data-selected="true"]');
    if (selected) {
      selected.scrollIntoView({ block: 'nearest' });
    }
  }, [selectedIndex]);

  // Use recent search as query
  const useRecent = (term: string) => {
    setQuery(term);
    inputRef.current?.focus();
  };

  if (!commandPaletteOpen) return null;

  // Render result groups
  const renderGroup = (type: string, items: SearchResult[], startIndex: number) => {
    if (items.length === 0) return { element: null, nextIndex: startIndex };
    const config = typeConfig[type];
    return {
      element: (
        <div key={type}>
          <div className="flex items-center gap-2 px-4 py-2 text-xs font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500">
            <span className={cn('flex h-5 w-5 items-center justify-center rounded', config.color)}>
              {config.icon}
            </span>
            {config.label}
            <span className="text-surface-300 dark:text-surface-600">({items.length})</span>
          </div>
          {items.map((item, i) => {
            const globalIdx = startIndex + i;
            const isSelected = globalIdx === selectedIndex;
            return (
              <button
                key={`${type}-${item.id}`}
                data-selected={isSelected}
                onClick={() => navigateTo(item)}
                onMouseEnter={() => setSelectedIndex(globalIdx)}
                className={cn(
                  'flex w-full items-center gap-3 px-4 py-2.5 text-left transition-colors',
                  isSelected
                    ? 'bg-brand-50 text-brand-700 dark:bg-brand-500/10 dark:text-brand-300'
                    : 'text-surface-700 hover:bg-surface-50 dark:text-surface-200 dark:hover:bg-surface-800'
                )}
              >
                <span className={cn('flex h-8 w-8 shrink-0 items-center justify-center rounded-lg', config.color)}>
                  {config.icon}
                </span>
                <div className="min-w-0 flex-1">
                  <p className="truncate text-sm font-medium">{item.display}</p>
                  {item.subtitle && (
                    <p className="truncate text-xs text-surface-400 dark:text-surface-500">
                      {item.subtitle}
                    </p>
                  )}
                </div>
                {isSelected && (
                  <CornerDownLeft className="h-3.5 w-3.5 shrink-0 text-surface-300 dark:text-surface-600" />
                )}
              </button>
            );
          })}
        </div>
      ),
      nextIndex: startIndex + items.length,
    };
  };

  let idx = 0;
  const groups: React.ReactNode[] = [];
  if (results) {
    for (const [type, items] of [
      ['ticket', results.tickets],
      ['customer', results.customers],
      ['inventory', results.inventory],
      ['invoice', results.invoices],
    ] as [string, SearchResult[]][]) {
      const { element, nextIndex } = renderGroup(type, items, idx);
      if (element) groups.push(element);
      idx = nextIndex;
    }
  }

  const hasResults = totalCount > 0;
  const hasQuery = query.trim().length >= MIN_QUERY_LENGTH;
  const showNoResults = hasQuery && !loading && results && !hasResults;
  const showRecent = query.trim().length === 0 && recentSearches.length > 0;

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 z-[100] bg-black/50 backdrop-blur-sm"
        onClick={close}
      />

      {/* Modal */}
      <div className="fixed inset-0 z-[101] flex items-start justify-center px-4 pt-[15vh]">
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="command-palette-title"
          className="w-full max-w-xl overflow-hidden rounded-2xl border border-surface-200 bg-white shadow-2xl dark:border-surface-700 dark:bg-surface-900"
          onClick={(e) => e.stopPropagation()}
        >
          <h2 id="command-palette-title" className="sr-only">Command palette</h2>
          {/* Search Input */}
          <div className="flex items-center gap-3 border-b border-surface-100 px-4 dark:border-surface-800">
            {loading ? (
              <Loader2 className="h-5 w-5 shrink-0 animate-spin text-brand-500" />
            ) : (
              <Search className="h-5 w-5 shrink-0 text-surface-400 dark:text-surface-500" />
            )}
            <input
              ref={inputRef}
              type="text"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              onKeyDown={handleKeyDown}
              placeholder="Search tickets, customers, inventory, invoices..."
              className="h-14 flex-1 bg-transparent text-base text-surface-800 outline-none placeholder:text-surface-400 dark:text-surface-100 dark:placeholder:text-surface-500"
            />
            {query && (
              <button
                aria-label="Clear search"
                onClick={() => { setQuery(''); inputRef.current?.focus(); }}
                className="flex h-6 w-6 items-center justify-center rounded-md text-surface-400 transition-colors hover:bg-surface-100 hover:text-surface-600 dark:hover:bg-surface-800 dark:hover:text-surface-300"
              >
                <X className="h-4 w-4" />
              </button>
            )}
            <kbd className="hidden rounded-md border border-surface-200 bg-surface-50 px-1.5 py-0.5 text-[11px] font-medium text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500 sm:inline-block">
              ESC
            </kbd>
          </div>

          {/* Results area */}
          <div
            ref={listRef}
            className="max-h-[60vh] overflow-y-auto overscroll-contain"
          >
            {/* Recent searches */}
            {showRecent && (
              <div className="py-2">
                <div className="px-4 py-2 text-xs font-semibold uppercase tracking-wider text-surface-400 dark:text-surface-500">
                  Recent Searches
                </div>
                {recentSearches.map((term) => (
                  <button
                    key={term}
                    onClick={() => useRecent(term)}
                    className="flex w-full items-center gap-3 px-4 py-2 text-left text-sm text-surface-600 transition-colors hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-800"
                  >
                    <Clock className="h-4 w-4 shrink-0 text-surface-300 dark:text-surface-600" />
                    <span className="truncate">{term}</span>
                  </button>
                ))}
              </div>
            )}

            {/* Grouped results */}
            {groups.length > 0 && <div className="py-1">{groups}</div>}

            {/* No results — distinguishes backend failure from empty set */}
            {showNoResults && (
              <div className="flex flex-col items-center gap-2 py-12 text-center">
                <Search aria-hidden="true" className="h-10 w-10 text-surface-200 dark:text-surface-700" />
                <p className="text-sm font-medium text-surface-500 dark:text-surface-400">
                  {searchError ? 'Search unavailable' : 'No results found'}
                </p>
                <p className="text-xs text-surface-400 dark:text-surface-500">
                  {searchError ? 'The search service is not responding. Please try again in a moment.' : 'Try a different search term'}
                </p>
              </div>
            )}

            {/* Empty initial state (no recent) */}
            {!hasQuery && recentSearches.length === 0 && (
              <div className="flex flex-col items-center gap-2 py-12 text-center">
                <Search className="h-10 w-10 text-surface-200 dark:text-surface-700" />
                <p className="text-sm text-surface-400 dark:text-surface-500">
                  Start typing to search across everything
                </p>
              </div>
            )}
          </div>

          {/* Footer with keyboard hints */}
          <div className="flex items-center gap-4 border-t border-surface-100 px-4 py-2.5 text-xs text-surface-400 dark:border-surface-800 dark:text-surface-500">
            <span className="flex items-center gap-1">
              <ArrowUp className="h-3 w-3" />
              <ArrowDown className="h-3 w-3" />
              navigate
            </span>
            <span className="flex items-center gap-1">
              <CornerDownLeft className="h-3 w-3" />
              open
            </span>
            <span className="flex items-center gap-1">
              <kbd className="rounded border border-surface-200 bg-surface-50 px-1 text-[10px] dark:border-surface-700 dark:bg-surface-800">
                ESC
              </kbd>
              close
            </span>
          </div>
        </div>
      </div>
    </>
  );
}
