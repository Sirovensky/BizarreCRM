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
  { pattern: /\b(DEBUG|TRACE)\b/i, cls: 'text-surface-500' },
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
function renderWithHighlight(line: string, filter: string): React.ReactNode {
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
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [content, setContent] = useState('');
  const [meta, setMeta] = useState<{ size: number; mtime: string | null; truncated: boolean } | null>(null);
  const [loading, setLoading] = useState(false);
  const scrollRef = useRef<HTMLDivElement>(null);

  const refreshFileList = useCallback(async () => {
    try {
      const res = await getAPI().admin.listLogs();
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

  // Auto-scroll to bottom on new content while in tail mode
  useEffect(() => {
    if (autoRefresh && scrollRef.current) {
      scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
    }
  }, [content, autoRefresh]);

  const filteredLines = useMemo(() => {
    if (!filter.trim()) return content.split('\n');
    const needle = filter.toLowerCase();
    return content.split('\n').filter((l) => l.toLowerCase().includes(needle));
  }, [content, filter]);

  // Extract ERR_* codes that appear in the current tail so operators can
  // spot patterns at a glance ("everything is ERR_ORIGIN_MISSING right now")
  // and one-click filter to just those lines. Only scans what's loaded.
  const errorCodeCounts = useMemo(() => {
    const counts = new Map<string, number>();
    // Match ERR_<UPPER_WITH_UNDERSCORES> — mirrors the server's errorCodes registry shape.
    // Bounded to 4..40 chars to avoid matching tail-end junk like `ERR_` with no suffix.
    const re = /\bERR_[A-Z][A-Z0-9_]{3,40}\b/g;
    for (const line of content.split('\n')) {
      const matches = line.match(re);
      if (!matches) continue;
      for (const code of matches) {
        counts.set(code, (counts.get(code) ?? 0) + 1);
      }
    }
    return [...counts.entries()].sort((a, b) => b[1] - a[1]);
  }, [content]);

  const selectedFile = files.find((f) => f.name === selected);

  return (
    <div className="space-y-4 animate-fade-in flex flex-col h-full">
      <div className="flex items-center justify-between gap-3 flex-wrap">
        <h1 className="text-lg font-bold text-surface-100 flex items-center gap-2">
          <ScrollText className="w-5 h-5 text-accent-400" />
          Server Logs
        </h1>
        <div className="flex items-center gap-2">
          <button
            onClick={() => setAutoRefresh((v) => !v)}
            className={`flex items-center gap-1.5 px-3 py-1.5 text-xs font-medium rounded border transition-colors ${
              autoRefresh
                ? 'bg-emerald-950/40 border-emerald-900/60 text-emerald-300 hover:bg-emerald-950/60'
                : 'bg-surface-900 border-surface-700 text-surface-400 hover:text-surface-200'
            }`}
          >
            {autoRefresh ? <Pause className="w-3.5 h-3.5" /> : <Play className="w-3.5 h-3.5" />}
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
                toast.error(err instanceof Error ? err.message : 'Clipboard write failed');
              }
            }}
            className="p-2 rounded text-surface-400 hover:text-surface-200 hover:bg-surface-800"
            title="Copy visible lines to clipboard"
          >
            <Copy className="w-4 h-4" />
          </button>
          <button
            onClick={() => { if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight; }}
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
            placeholder="Filter (substring match, case-insensitive)"
            className="flex-1 px-2 py-1 bg-surface-950 border border-surface-700 rounded text-surface-200 placeholder:text-surface-600"
          />
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
          <span className="text-surface-500">
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
            <div key={i} className={`whitespace-pre-wrap break-all ${colorize(line)}`}>
              {renderWithHighlight(line, filter)}
            </div>
          ))
        )}
      </div>
    </div>
  );
}
