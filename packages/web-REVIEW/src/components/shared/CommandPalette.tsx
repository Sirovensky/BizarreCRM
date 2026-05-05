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
  Compass,
} from 'lucide-react';

interface SearchResult {
  id: number;
  display: string;
  type: string;
  subtitle?: string;
  /** Static page-jump entries store their target route here (id 0). */
  pagePath?: string;
}

interface GroupedResults {
  tickets: SearchResult[];
  customers: SearchResult[];
  inventory: SearchResult[];
  invoices: SearchResult[];
  pages: SearchResult[];
}

// WEB-FL-007 (Fixer-B12 2026-04-25): static page-jump targets so Cmd+K
// can navigate to routes that don't have a backend search surface (and
// to surfaces missing from Sidebar — see WEB-FL-006). Filtered locally
// by case-insensitive substring match on `display` + alias keywords.
interface PageJumpEntry {
  display: string;
  path: string;
  subtitle?: string;
  /** Extra match terms (route fragments, common synonyms). */
  aliases?: string[];
}

const PAGE_JUMPS: PageJumpEntry[] = [
  { display: 'Dashboard', path: '/dashboard' },
  { display: 'POS', path: '/pos', aliases: ['point of sale', 'register', 'checkout'] },
  { display: 'Tickets', path: '/tickets', aliases: ['repairs'] },
  { display: 'Customers', path: '/customers', aliases: ['clients'] },
  { display: 'Inventory', path: '/inventory', aliases: ['parts', 'stock'] },
  { display: 'Invoices', path: '/invoices' },
  { display: 'Estimates', path: '/estimates', aliases: ['quotes'] },
  { display: 'Expenses', path: '/expenses' },
  { display: 'Purchase Orders', path: '/purchase-orders', aliases: ['po'] },
  { display: 'Communications', path: '/communications', aliases: ['sms', 'messages', 'chat'] },
  { display: 'Leads', path: '/leads' },
  { display: 'Pipeline', path: '/pipeline' },
  { display: 'Calendar', path: '/calendar', aliases: ['appointments', 'schedule'] },
  { display: 'Marketing', path: '/marketing' },
  { display: 'Campaigns', path: '/campaigns' },
  { display: 'Automations', path: '/automations', aliases: ['workflows'] },
  { display: 'Reviews', path: '/reviews', aliases: ['nps', 'reputation'] },
  { display: 'Voice Calls', path: '/voice', aliases: ['phone', 'recordings'] },
  { display: 'Cash Register', path: '/cash-register', aliases: ['drawer', 'till'] },
  { display: 'Catalog', path: '/catalog', aliases: ['products'] },
  { display: 'Loaners', path: '/loaners', aliases: ['loaner devices'] },
  { display: 'Subscriptions', path: '/subscriptions', aliases: ['memberships', 'recurring'] },
  { display: 'Gift Cards', path: '/gift-cards' },
  { display: 'Referrals', path: '/referrals' },
  { display: 'Team', path: '/team' },
  { display: 'Performance Reviews', path: '/team/reviews', aliases: ['employee reviews'] },
  { display: 'Goals', path: '/team/goals' },
  { display: 'Billing', path: '/billing', aliases: ['subscription', 'plan'] },
  { display: 'Reports', path: '/reports', aliases: ['analytics'] },
  { display: 'Settings', path: '/settings', aliases: ['preferences', 'configuration'] },
];

function matchPageJumps(query: string): SearchResult[] {
  const q = query.trim().toLowerCase();
  if (q.length < MIN_QUERY_LENGTH) return [];
  const hits: SearchResult[] = [];
  for (const p of PAGE_JUMPS) {
    const hay = [p.display, p.path, ...(p.aliases ?? [])].join(' ').toLowerCase();
    if (hay.includes(q)) {
      hits.push({
        id: 0,
        display: p.display,
        type: 'page',
        subtitle: p.subtitle ?? p.path,
        pagePath: p.path,
      });
    }
    if (hits.length >= 6) break;
  }
  return hits;
}

const RECENT_SEARCHES_KEY = 'crm_recent_searches';
const MAX_RECENT = 10;
const MIN_QUERY_LENGTH = 2;
const TTL_MS = 24 * 60 * 60 * 1000; // 24 hours

// @audit-fixed (WEB-FJ-016 / Fixer-B11 2026-04-25): wipe stored queries on
// logout. Recent searches typically contain customer names, phone fragments,
// and ticket numbers — leaving them in sessionStorage after logout means the
// next staff member opening Cmd-K on the same tab session sees the previous
// operator's investigation trail. The `bizarre-crm:auth-cleared` event is
// dispatched by the auth store on logout / force-logout / switch-user.
if (typeof window !== 'undefined') {
  window.addEventListener('bizarre-crm:auth-cleared', () => {
    try { sessionStorage.removeItem(RECENT_SEARCHES_KEY); } catch { /* best-effort */ }
  });
}

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
  page: {
    icon: <Compass className="h-4 w-4" />,
    label: 'Pages',
    // Static page-jump rows carry their route on the result via `pagePath`;
    // navigateTo prefers that. This fallback is unreachable but keeps the
    // typeConfig contract uniform.
    path: () => '/',
    color: 'text-rose-500 bg-rose-50 dark:bg-rose-500/10',
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
          ...results.pages,
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

  // Focus input on open — requestAnimationFrame fires after the browser paints
  // so the focus ring appears at the end of the open animation, not mid-transition.
  useEffect(() => {
    if (!commandPaletteOpen) return;
    let raf = 0;
    raf = requestAnimationFrame(() => inputRef.current?.focus());
    return () => cancelAnimationFrame(raf);
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
      // WEB-FL-007 (Fixer-B12): page-jump matches are local + synchronous,
      // so they appear even if the backend search fails or is unavailable.
      const pages = matchPageJumps(query);
      try {
        const res = await searchApi.global(query.trim());
        if (myReqId !== reqSeq.current) return; // stale — a newer search is in flight
        const data = res.data.data as Omit<GroupedResults, 'pages'>;
        setResults({ ...data, pages });
        setSelectedIndex(0);
      } catch (err) {
        if (myReqId !== reqSeq.current) return;
        // Surface the failure as an explicit error state so the palette shows
        // "Search unavailable" instead of a misleading "No results found".
        console.error('[CommandPalette] search failed', err);
        setResults({ tickets: [], customers: [], inventory: [], invoices: [], pages });
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
      // WEB-FL-007: page-jump rows carry their target as `pagePath`
      // because their numeric id is a placeholder (0).
      if (result.type === 'page' && result.pagePath) {
        saveRecentSearch(query.trim());
        navigate(result.pagePath);
        close();
        return;
      }
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
                key={`${type}-${item.pagePath ?? item.id}`}
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
      ['page', results.pages],
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
        data-state="open"
        className="fixed inset-0 z-[100] bg-black/50 backdrop-blur-sm animate-in fade-in-0 duration-200 motion-reduce:animate-none"
        onClick={close}
      />

      {/* Modal */}
      <div className="fixed inset-0 z-[101] flex items-start justify-center px-4 pt-[15vh]">
        <div
          role="dialog"
          aria-modal="true"
          aria-labelledby="command-palette-title"
          data-state="open"
          className="w-full max-w-xl overflow-hidden rounded-2xl border border-surface-200 bg-white shadow-2xl dark:border-surface-700 dark:bg-surface-900 animate-in fade-in-0 zoom-in-95 duration-200 motion-reduce:animate-none"
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
              placeholder="Search pages, tickets, customers, inventory, invoices..."
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
