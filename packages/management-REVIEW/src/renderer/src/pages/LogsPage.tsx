import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import { ScrollText, RefreshCw, Pause, Play, Filter, Trash2, Copy, ArrowDownToLine } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';
import { formatBytes, formatDateTime } from '@/utils/format';
import toast from 'react-hot-toast';
import { formatApiError } from '@/utils/apiError';

interface LogFileMeta {
  name: string;
  size: number;
  mtime: string | null;
  exists: boolean;
  error?: string;
}

const REFRESH_INTERVAL_MS = 2000;
const TAIL_LINES_OPTIONS = [100, 200, 500, 1000, 2000];

const SEVERITY_HIGHLIGHT: Array<{ pattern: RegExp; cls: string }> = [
  { pattern: /\b(FATAL|ERROR|❌|✖)\b/i, cls: 'text-red-300' },
  { pattern: /\b(WARN|WARNING|⚠️)\b/i, cls: 'text-amber-300' },
  { pattern: /\b(INFO|✓|✔|OK)\b/i, cls: 'text-emerald-300/70' },
  { pattern: /\b(DEBUG|TRACE)\b/i, cls: 'text-surface-400 opacity-70' },
];

function colorize(line: string): string {
  for (const { pattern, cls } of SEVERITY_HIGHLIGHT) {
    if (pattern.test(line)) return cls;
  }
  return 'text-surface-300';
}

/**
 * Split a line into plain + highlighted segments wherever the filter
 * substring matches (case-insensitive). Returns the original line as a
 * single text node when the filter is empty so there's no DOM cost.
 */
function renderWithHighlight(line: string, filter: string, regex: RegExp | null): React.ReactNode {
  // DASH-ELEC-216: regex mode segments via RegExp.exec instead of substring
  // indexOf so highlight spans align with actual match windows.
  if (regex) {
    const nodes: React.ReactNode[] = [];
    const re = new RegExp(regex.source, regex.flags.includes('g') ? regex.flags : `${regex.flags}g`);
    let pos = 0;
    let m: RegExpExecArray | null;
    while ((m = re.exec(line)) !== null) {
      if (m.index > pos) nodes.push(line.slice(pos, m.index));
      nodes.push(
        <mark key={m.index} className="bg-amber-500/30 text-amber-100 rounded px-0.5">
          {m[0]}
        </mark>
      );
      pos = m.index + m[0].length;
      // Guard against zero-width matches that would otherwise infinite-loop.
      if (m[0].length === 0) re.lastIndex++;
    }
    if (pos < line.length) nodes.push(line.slice(pos));
    return nodes.length === 0 ? line : nodes;
  }
  const q = filter.trim();
  if (!q) return line || '\u00A0';
  const needle = q.toLowerCase();
  const hay = line.toLowerCase();
  const nodes: React.ReactNode[] = [];
  let cursor = 0;
  while (cursor < line.length) {
    const hit = hay.indexOf(needle, cursor);
    if (hit === -1) {
      nodes.push(line.slice(cursor));
      break;
    }
    if (hit > cursor) nodes.push(line.slice(cursor, hit));
    nodes.push(
      <mark key={hit} className="bg-amber-500/30 text-amber-100 rounded px-0.5">
        {line.slice(hit, hit + needle.length)}
      </mark>
    );
    cursor = hit + needle.length;
  }
  return nodes.length === 0 ? (line || '\u00A0') : nodes;
}

export function LogsPage() {
  const [files, setFiles] = useState<LogFileMeta[]>([]);
  const [selected, setSelected] = useState<string>('bizarre-crm.err.log');
  const [tailLines, setTailLines] = useState(500);
  const [filter, setFilter] = useState('');
  // DASH-ELEC-216: regex toggle. Falls back gracefully to substring on
  // invalid pattern so a half-typed `(` doesn't throw and blank the view.
  const [regexMode, setRegexMode] = useState(false);
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [content, setContent] = useState('');
  const [meta, setMeta] = useState<{ size: number; mtime: string | null; truncated: boolean } | null>(null);
  const [loading, setLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const refreshFileList = useCallback(async () => {
    try {
      const res = await getAPI().admin.listLogs();
      // DASH-ELEC-281: detect 401 and trigger global auto-logout instead of
      // silently leaving the file dropdown empty when the JWT has expired.
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setFiles(res.data.files);
      } else if (res.message) {
        toast.error(formatApiError(res));
      }
    } catch (err) {
      console.warn('[LogsPage] listLogs failed', err);
    }
  }, []);

  const loadTail = useCallback(async () => {
    setLoading(true);
    try {
      const res = await getAPI().admin.tailLog({ name: selected, lines: tailLines });
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setContent(res.data.content);
        setMeta({ size: res.data.size, mtime: res.data.mtime, truncated: res.data.truncated });
      } else if (res.message) {
        // Don't toast on every poll failure — just clear content.
        setContent('');
      }
    } catch (err) {
      console.warn('[LogsPage] tailLog failed', err);
    } finally {
      setLoading(false);
    }
  }, [selected, tailLines]);

  useEffect(() => { refreshFileList(); }, [refreshFileList]);
  useEffect(() => { loadTail(); }, [loadTail]);

  // Auto-refresh + auto-scroll
  useEffect(() => {
    if (!autoRefresh) return;
    const id = setInterval(loadTail, REFRESH_INTERVAL_MS);
    return () => clearInterval(id);
  }, [autoRefresh, loadTail]);

  // DASH-ELEC-127: auto-scroll only when the operator is already pinned to the
  // bottom. If they've scrolled up to investigate an earlier line, the 2-second
  // poll must NOT yank them back. The 50px slack absorbs sub-pixel rounding +
  // a row-height of fresh paint.
  const userScrolledRef = useRef(false);
  const onScrollContainer = useCallback(() => {
    const el = scrollRef.current;
    if (!el) return;
    userScrolledRef.current = el.scrollTop < el.scrollHeight - el.clientHeight - 50;
  }, []);
  useEffect(() => {
    if (autoRefresh && scrollRef.current && !userScrolledRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [content, autoRefresh]);

  // DASH-ELEC-038: derive the raw line array once so filteredLines and
  // errorCodeCounts both consume the same memoised split instead of each
  // calling content.split('\n') independently on every 2-second poll tick.
  // DASH-ELEC-215: strip ANSI escape sequences (e.g. ^[[32m) emitted by
  // coloured server output so they don't render as literal garbage.
  // eslint-disable-next-line no-control-regex
  const allLines = useMemo(() => content.replace(/\x1b\[[0-9;]*m/g, '').split('\n'), [content]);

  // DASH-ELEC-216: compile filter into a RegExp when regexMode is on. Bad
  // patterns (mid-typing) fall back to null so the substring path runs and
  // the view never blanks out from a SyntaxError.
  const compiledRegex = useMemo<RegExp | null>(() => {
    if (!regexMode) return null;
    const q = filter.trim();
    if (!q) return null;
    try {
      return new RegExp(q, 'i');
    } catch {
      return null;
    }
  }, [regexMode, filter]);

  const filteredLines = useMemo(() => {
    if (compiledRegex) {
      return allLines.filter((l) => compiledRegex.test(l));
    }
    if (!filter.trim()) return allLines;
    const needle = filter.toLowerCase();
    return allLines.filter((l) => l.toLowerCase().includes(needle));
  }, [allLines, filter, compiledRegex]);

  // Extract ERR_* codes that appear in the current tail so operators can
  // spot patterns at a glance ("everything is ERR_ORIGIN_MISSING right now")
  // and one-click filter to just those lines. Only scans what's loaded.
  const errorCodeCounts = useMemo(() => {
    const counts = new Map<string, number>();
    // Match ERR_<UPPER_WITH_UNDERSCORES> — mirrors the server's errorCodes registry shape.
    // Bounded to 4..40 chars to avoid matching tail-end junk like `ERR_` with no suffix.
    const re = /\bERR_[A-Z][A-Z0-9_]{3,40}\b/g;
    for (const line of allLines) {
      const matches = line.match(re);
      if (!matches) continue;
      for (const code of matches) {
        counts.set(code, (counts.get(code) ?? 0) + 1);
      }
    }
    return [...counts.entries()].sort((a, b) => b[1] - a[1]);
  }, [allLines]);

  const selectedFile = files.find((f) => f.name === selected);

  return (
    <div className="space-y-4 animate-fade-in flex flex-col h-full">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <ScrollText className="w-5 h-5 text-accent-400" />
          Server Logs
        </h1>
        <div className="flex items-center gap-2">
          {autoRefresh && (
            <span
              aria-live="polite"
              aria-label="Live log tail active"
              className="flex items-center gap-1 px-2 py-0.5 rounded text-[10px] font-semibold tracking-widest text-emerald-400 border border-emerald-900/60 bg-emerald-950/30"
            >
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" aria-hidden="true" />
              LIVE
            </span>
          )}
          <button
            onClick={() => setAutoRefresh((v) => !v)}
            aria-pressed={autoRefresh}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded border transition-colors ${
              autoRefresh
                ? 'bg-emerald-950/40 border-emerald-900/60 text-emerald-300 hover:bg-emerald-950/60'
                : 'bg-surface-900 border-surface-700 text-surface-400 hover:text-surface-200'
            }`}
          >
            {autoRefresh ? <Pause className="w-3.5 h-3.5" aria-hidden="true" /> : <Play className="w-3.5 h-3.5" aria-hidden="true" />}
            {autoRefresh ? 'Pause tail' : 'Resume tail'}
          </button>
          <button
            onClick={async () => {
              const text = filteredLines.join('\n');
              if (!text.trim()) { toast('Nothing to copy'); return; }
              try {
                await navigator.clipboard.writeText(text);
                toast.success(`Copied ${filteredLines.length} lines`);
              } catch (err) {
                toast.error(err instanceof Error ? err.message : 'Copy failed');
              }
            }}
            className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800"
            title="Copy visible lines to clipboard"
          >
            <Copy className="w-4 h-4" />
          </button>
          <button
            onClick={() => {
              if (scrollRef.current) {
                scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
                // DASH-ELEC-127: explicit "scroll to bottom" re-pins, so
                // subsequent auto-scroll ticks resume.
                userScrolledRef.current = false;
              }
            }}
            className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800"
            title="Scroll to bottom"
          >
            <ArrowDownToLine className="w-4 h-4" />
          </button>
          <button
            onClick={loadTail}
            disabled={loading}
            className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800 disabled:opacity-50"
            title="Refresh now"
          >
            <RefreshCw className={`w-4 h-4 ${loading ? 'animate-spin' : ''}`} />
          </button>
        </div>
      </div>

      <div className="flex items-center gap-2 flex-wrap text-xs">
        <select
          value={selected}
          onChange={(e) => setSelected(e.target.value)}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 font-mono"
        >
          {files.map((f) => (
            <option key={f.name} value={f.name}>
              {f.name}{f.exists ? ` (${formatBytes(f.size)})` : ' (missing)'}
            </option>
          ))}
        </select>
        <select
          value={tailLines}
          onChange={(e) => setTailLines(parseInt(e.target.value, 10))}
          className="px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200"
        >
          {TAIL_LINES_OPTIONS.map((n) => <option key={n} value={n}>last {n} lines</option>)}
        </select>
        <div className="flex items-center gap-1 flex-1 min-w-[180px]">
          <Filter className="w-3.5 h-3.5 text-surface-500" />
          <input
            type="text"
            value={filter}
            onChange={(e) => setFilter(e.target.value)}
            placeholder={regexMode ? 'Filter (regex, case-insensitive)' : 'Filter (substring match, case-insensitive)'}
            className={`flex-1 px-2 py-1 bg-surface-950 border rounded text-surface-200 placeholder:text-surface-600 font-mono ${
              regexMode && filter.trim() && !compiledRegex
                ? 'border-red-700/70'
                : 'border-surface-700'
            }`}
          />
          {/* DASH-ELEC-216: regex mode toggle. Aria-pressed announces the
              current mode; invalid regex highlights the input border red but
              keeps the substring fallback active so the tail still renders. */}
          <button
            onClick={() => setRegexMode((v) => !v)}
            aria-pressed={regexMode}
            title={regexMode ? 'Regex mode (click to disable)' : 'Substring mode (click to enable regex)'}
            className={`px-1.5 py-0.5 text-[10px] font-mono rounded border transition-colors ${
              regexMode
                ? 'bg-accent-950/40 border-accent-800 text-accent-300'
                : 'bg-surface-900 border-surface-700 text-surface-500 hover:text-surface-300'
            }`}
          >
            .*
          </button>
          {filter && (
            <button
              onClick={() => setFilter('')}
              className="p-1 text-surface-500 hover:text-surface-300"
              title="Clear filter"
            >
              <Trash2 className="w-3 h-3" />
            </button>
          )}
        </div>
        {selectedFile?.mtime && (
          <span className="text-surface-500" title={new Date(selectedFile.mtime).toISOString()}>
            modified {formatDateTime(selectedFile.mtime)}
          </span>
        )}
      </div>

      {meta?.truncated && (
        <div className="px-3 py-2 rounded border border-amber-900/50 bg-amber-950/30 text-xs text-amber-300">
          Output truncated at 4 MiB. Lower the line count or grep with the filter to narrow.
        </div>
      )}

      {/* Error-code chip bar — surfaces ERR_* occurrences in the current tail
          so operators see at a glance which failure mode dominates. Each chip
          is a one-click filter shortcut. */}
      {errorCodeCounts.length > 0 && (
        <div className="flex items-center gap-1.5 flex-wrap text-[11px]">
          <span className="text-surface-500">error codes:</span>
          {errorCodeCounts.slice(0, 12).map(([code, count]) => (
            <button
              key={code}
              onClick={() => setFilter(filter === code ? '' : code)}
              className={`inline-flex items-center gap-1 px-1.5 py-0.5 rounded border transition-colors ${
                filter === code
                  ? 'border-accent-600 bg-accent-950/40 text-accent-300'
                  : 'border-surface-700 text-surface-400 hover:text-surface-200 hover:border-surface-600'
              }`}
              title={`Filter tail to ${code}`}
            >
              <span className="font-mono">{count}</span>
              <span className="font-mono text-[10px]">{code}</span>
            </button>
          ))}
          {errorCodeCounts.length > 12 && (
            <span className="text-surface-600">+{errorCodeCounts.length - 12} more</span>
          )}
        </div>
      )}

      <div
        ref={scrollRef}
        onScroll={onScrollContainer}
        className="flex-1 min-h-[400px] overflow-auto bg-surface-950 border border-surface-800 rounded p-3 font-mono text-[11px] leading-relaxed"
      >
        {!selectedFile?.exists ? (
          <div className="text-surface-500 text-center py-8">
            Log file not found at <code className="font-mono">{selected}</code>. Server may not have started yet.
          </div>
        ) : filteredLines.length === 0 || (filteredLines.length === 1 && !filteredLines[0]) ? (
          <div className="text-surface-500 text-center py-8">
            {filter ? 'No lines match the filter.' : 'Log is empty.'}
          </div>
        ) : (
          filteredLines.map((line, i) => (
            // DASH-ELEC-039: content-derived key so React can reuse DOM nodes
            // that haven't changed on the 2-second tail refresh rather than
            // diffing the entire list by position.
            <div key={`${i}-${line.slice(0, 20)}`} className={`whitespace-pre-wrap break-all ${colorize(line)}`}>
              {renderWithHighlight(line, filter, compiledRegex)}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
