import { useRef, useEffect, useState, useCallback } from 'react';
import {
  Cpu,
  HardDrive,
  Clock,
  Zap,
  Database,
  Wifi,
  AlertTriangle,
  TrendingUp,
  Activity,
} from 'lucide-react';
import { cn } from '@/utils/cn';
import { useServerStore } from '@/stores/serverStore';
import { formatUptime, formatDecimal, formatNumber } from '@/utils/format';
import { getAPI } from '@/api/bridge';
import type { MetricsDataPoint } from '@/api/bridge';

interface StatCardProps {
  label: string;
  value: string;
  unit?: string;
  icon: React.ElementType;
  iconColor?: string;
  sublabel?: string;
}

function StatCard({ label, value, unit, icon: Icon, iconColor = 'text-accent-400', sublabel }: StatCardProps) {
  return (
    <div className="stat-card">
      <div className="flex items-center justify-between mb-3">
        <div>
          <span className="text-[11px] font-medium text-surface-500 uppercase tracking-wider">
            {label}
          </span>
          {sublabel && <span className="text-[9px] text-surface-600 ml-1">({sublabel})</span>}
        </div>
        <Icon className={cn('w-4 h-4', iconColor)} />
      </div>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-bold text-surface-100">{value}</span>
        {unit && <span className="text-xs text-surface-500">{unit}</span>}
      </div>
    </div>
  );
}

// ── Request Rate Graph (live + historical with time range selector) ────

const LIVE_POINTS = 60;
const LIVE_POLL_SEC = 5;
const TIME_RANGES = ['Live', '1h', '6h', '1d', '1w', '1m', '6m'] as const;
type TimeRange = (typeof TIME_RANGES)[number];

interface DataPoint { value: number; time: number; }

function formatTimeLabel(ts: string | number, range: TimeRange): string {
  const d = typeof ts === 'number' ? new Date(ts) : new Date(ts.includes(' ') ? ts.replace(' ', 'T') + 'Z' : ts);
  if (range === 'Live') return '';
  if (range === '1h' || range === '6h') return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (range === '1d') return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  if (range === '1w') return d.toLocaleDateString([], { weekday: 'short', hour: '2-digit' });
  return d.toLocaleDateString([], { month: 'short', day: 'numeric' });
}

function formatHoverTime(ts: string | number, range: TimeRange): string {
  const d = typeof ts === 'number' ? new Date(ts) : new Date(ts.includes(' ') ? ts.replace(' ', 'T') + 'Z' : ts);
  if (range === 'Live') {
    const ago = Math.round((Date.now() - d.getTime()) / 1000);
    return ago === 0 ? 'Now' : `${ago}s ago`;
  }
  if (range === '1h' || range === '6h' || range === '1d') return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  return d.toLocaleDateString([], { month: 'short', day: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function RequestRateGraph({ current, avg, peak, rpm, avgMs, p95Ms }: { current: number; avg: number; peak: number; rpm: number; avgMs: number; p95Ms: number }) {
  const [range, setRange] = useState<TimeRange>('Live');
  const [histData, setHistData] = useState<MetricsDataPoint[] | null>(null);
  const [loading, setLoading] = useState(false);

  // Live data tracking
  const liveRef = useRef<DataPoint[]>([]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const [tooltipPos, setTooltipPos] = useState<{ x: number; y: number } | null>(null);

  // Push live data point
  useEffect(() => {
    const h = liveRef.current;
    h.push({ value: current, time: Date.now() });
    if (h.length > LIVE_POINTS) h.shift();
    if (range === 'Live') drawGraph(hoverIdx);
  }, [current]);

  // Fetch historical data when range changes
  useEffect(() => {
    if (range === 'Live') { setHistData(null); drawGraph(hoverIdx); return; }
    let cancelled = false;
    setLoading(true);
    getAPI().management.getStatsHistory(range).then(res => {
      if (cancelled) return;
      setHistData(res.data ?? []);
      setLoading(false);
    }).catch(() => { if (!cancelled) { setHistData([]); setLoading(false); } });
    return () => { cancelled = true; };
  }, [range]);

  // Redraw when data or hover changes
  useEffect(() => { drawGraph(hoverIdx); }, [hoverIdx, histData, range]);

  // Responsive sizing
  useEffect(() => {
    const container = containerRef.current;
    const canvas = canvasRef.current;
    if (!container || !canvas) return;
    const obs = new ResizeObserver(([entry]) => {
      const dpr = window.devicePixelRatio || 1;
      const { width, height } = entry.contentRect;
      canvas.width = Math.round(width * dpr);
      canvas.height = Math.round(height * dpr);
      canvas.style.width = `${width}px`;
      canvas.style.height = `${height}px`;
      const ctx = canvas.getContext('2d');
      if (ctx) ctx.scale(dpr, dpr);
      drawGraph(hoverIdx);
    });
    obs.observe(container);
    return () => obs.disconnect();
  }, []);

  const drawGraph = useCallback((activeIdx: number | null) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const w = canvas.width / dpr;
    const h = canvas.height / dpr;
    const pad = { top: 12, bottom: 28, left: 44, right: 12 };
    const gW = w - pad.left - pad.right;
    const gH = h - pad.top - pad.bottom;

    // Resolve data source
    let points: { value: number; label: string }[];
    if (range === 'Live') {
      points = liveRef.current.map(p => ({ value: p.value, label: '' }));
    } else if (histData && histData.length > 0) {
      points = histData.map(p => ({ value: p.rps_avg, label: p.timestamp }));
    } else {
      points = [];
    }

    const maxPoints = range === 'Live' ? LIVE_POINTS : points.length;
    const max = (points.length > 0 ? Math.max(...points.map(p => p.value), 1) : 10) * 1.2;

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    const toX = (i: number) => pad.left + (maxPoints > 1 ? (i / (maxPoints - 1)) * gW : gW / 2);
    const toY = (v: number) => pad.top + gH - (v / max) * gH;

    // Y-axis labels + grid
    ctx.font = '10px Inter, system-ui, sans-serif';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let i = 0; i <= 4; i++) {
      const val = max - (max * i) / 4;
      const y = pad.top + (gH * i) / 4;
      ctx.strokeStyle = '#1e1e22';
      ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(pad.left, y); ctx.lineTo(w - pad.right, y); ctx.stroke();
      ctx.fillStyle = '#71717a';
      ctx.fillText(val >= 1000 ? `${(val / 1000).toFixed(1)}k` : Math.round(val).toString(), pad.left - 6, y);
    }

    // X-axis labels
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillStyle = '#52525b';
    if (range === 'Live') {
      const labels = [
        { idx: 0, text: `${LIVE_POINTS * LIVE_POLL_SEC}s ago` },
        { idx: Math.floor(LIVE_POINTS / 2), text: `${Math.floor(LIVE_POINTS / 2) * LIVE_POLL_SEC}s ago` },
        { idx: LIVE_POINTS - 1, text: 'now' },
      ];
      for (const { idx, text } of labels) ctx.fillText(text, toX(idx), h - pad.bottom + 8);
    } else if (points.length > 2) {
      const step = Math.max(1, Math.floor(points.length / 5));
      for (let i = 0; i < points.length; i += step) {
        ctx.fillText(formatTimeLabel(points[i].label, range), toX(i), h - pad.bottom + 8);
      }
      // Always label last point
      if (points.length - 1 > step) {
        ctx.fillText(formatTimeLabel(points[points.length - 1].label, range), toX(points.length - 1), h - pad.bottom + 8);
      }
    }

    if (points.length === 0) {
      ctx.fillStyle = '#52525b';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.font = '12px Inter, system-ui, sans-serif';
      ctx.fillText(loading ? 'Loading...' : 'No data for this range yet', w / 2, h / 2);
      ctx.restore();
      return;
    }

    // Single data point — draw as a dot on the right edge
    if (points.length === 1) {
      const x = toX(maxPoints - 1);
      const y = toY(points[0].value);
      ctx.beginPath(); ctx.arc(x, y, 5, 0, Math.PI * 2);
      ctx.fillStyle = '#3b82f6'; ctx.fill();
      ctx.strokeStyle = '#09090b'; ctx.lineWidth = 2; ctx.stroke();
      // Label
      ctx.fillStyle = '#a1a1aa'; ctx.textAlign = 'right'; ctx.textBaseline = 'bottom';
      ctx.font = '11px Inter, system-ui, sans-serif';
      ctx.fillText(`${formatDecimal(points[0].value)} req/s`, x - 10, y - 8);
      ctx.restore();
      return;
    }

    // Data offset for live mode (right-align sparse data)
    const startIdx = range === 'Live' ? LIVE_POINTS - points.length : 0;

    // Area fill
    const gradient = ctx.createLinearGradient(0, pad.top, 0, h - pad.bottom);
    gradient.addColorStop(0, 'rgba(59, 130, 246, 0.25)');
    gradient.addColorStop(1, 'rgba(59, 130, 246, 0.01)');
    ctx.beginPath();
    ctx.moveTo(toX(startIdx), toY(0));
    for (let i = 0; i < points.length; i++) ctx.lineTo(toX(startIdx + i), toY(points[i].value));
    ctx.lineTo(toX(startIdx + points.length - 1), toY(0));
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // Line
    ctx.beginPath();
    ctx.strokeStyle = '#3b82f6';
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let i = 0; i < points.length; i++) {
      const x = toX(startIdx + i), y = toY(points[i].value);
      if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Current dot (live only)
    if (range === 'Live' && points.length > 0) {
      const lx = toX(startIdx + points.length - 1), ly = toY(points[points.length - 1].value);
      ctx.beginPath(); ctx.arc(lx, ly, 4, 0, Math.PI * 2);
      ctx.fillStyle = current > avg * 2 ? '#ef4444' : '#3b82f6';
      ctx.fill(); ctx.strokeStyle = '#09090b'; ctx.lineWidth = 2; ctx.stroke();
    }

    // Hover crosshair
    if (activeIdx !== null && activeIdx >= 0 && activeIdx < points.length) {
      const hx = toX(startIdx + activeIdx), hy = toY(points[activeIdx].value);
      ctx.setLineDash([4, 3]); ctx.strokeStyle = '#52525b'; ctx.lineWidth = 1;
      ctx.beginPath(); ctx.moveTo(hx, pad.top); ctx.lineTo(hx, h - pad.bottom); ctx.stroke();
      ctx.setLineDash([]);
      ctx.beginPath(); ctx.arc(hx, hy, 6, 0, Math.PI * 2); ctx.fillStyle = 'rgba(59, 130, 246, 0.3)'; ctx.fill();
      ctx.beginPath(); ctx.arc(hx, hy, 3.5, 0, Math.PI * 2); ctx.fillStyle = '#60a5fa'; ctx.fill();
      ctx.strokeStyle = '#09090b'; ctx.lineWidth = 1.5; ctx.stroke();
    }

    ctx.restore();
  }, [current, avg, range, histData, loading]);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;

    const points = range === 'Live' ? liveRef.current : (histData ?? []);
    if (points.length < 1) return;

    const dpr = window.devicePixelRatio || 1;
    const w = canvas.width / dpr;
    const pad = { left: 44, right: 12 };
    const gW = w - pad.left - pad.right;
    const maxPts = range === 'Live' ? LIVE_POINTS : points.length;
    const startIdx = range === 'Live' ? LIVE_POINTS - points.length : 0;

    let closest = -1, closestDist = Infinity;
    for (let i = 0; i < points.length; i++) {
      const x = pad.left + ((startIdx + i) / (maxPts - 1)) * gW;
      const dist = Math.abs(x - mx);
      if (dist < closestDist) { closestDist = dist; closest = i; }
    }
    if (closest >= 0 && closestDist < 20) {
      setHoverIdx(closest);
      setTooltipPos({ x: e.clientX - rect.left, y: e.clientY - rect.top });
    } else {
      setHoverIdx(null); setTooltipPos(null);
    }
  }, [range, histData]);

  const handleMouseLeave = useCallback(() => { setHoverIdx(null); setTooltipPos(null); }, []);

  // Resolve hovered point for tooltip
  const hoveredValue = hoverIdx !== null
    ? range === 'Live'
      ? liveRef.current[hoverIdx]?.value ?? 0
      : (histData?.[hoverIdx]?.rps_avg ?? 0)
    : 0;
  const hoveredTime = hoverIdx !== null
    ? range === 'Live'
      ? liveRef.current[hoverIdx]?.time ?? 0
      : (histData?.[hoverIdx]?.timestamp ?? '')
    : '';
  const hoveredP95 = hoverIdx !== null && range !== 'Live' ? histData?.[hoverIdx]?.p95_response_ms : undefined;

  return (
    <div className="stat-card !p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <Activity className="w-4 h-4 text-accent-400" />
          <span className="text-sm font-semibold text-surface-200">Request Rate</span>
        </div>
        <div className="flex items-center gap-4 text-xs">
          {range === 'Live' && (
            <>
              <span className="text-surface-500">Now: <span className="font-bold text-surface-100">{formatNumber(current)}</span>/s</span>
              <span className="text-surface-500">Avg: <span className="font-medium text-surface-300">{formatDecimal(avg)}</span>/s</span>
              <span className="text-surface-500">Peak: <span className="font-medium text-amber-400">{formatNumber(peak)}</span>/s</span>
              <span className="text-surface-500">RPM: <span className="font-medium text-surface-300">{formatNumber(rpm)}</span></span>
              <span className="text-surface-500">Avg: <span className={cn('font-medium', avgMs > 100 ? 'text-amber-400' : 'text-surface-300')}>{avgMs.toFixed(1)}ms</span></span>
              <span className="text-surface-500">P95: <span className={cn('font-medium', p95Ms > 500 ? 'text-red-400' : 'text-surface-300')}>{p95Ms.toFixed(0)}ms</span></span>
            </>
          )}
          {range !== 'Live' && histData && histData.length > 0 && (
            <span className="text-surface-500">{histData.length} data points</span>
          )}
        </div>
      </div>

      {/* Time range selector */}
      <div className="flex items-center gap-1 mb-2">
        {TIME_RANGES.map(r => (
          <button
            key={r}
            onClick={() => { setRange(r); setHoverIdx(null); setTooltipPos(null); }}
            className={cn(
              'px-2.5 py-1 text-[11px] font-medium rounded-md transition-colors',
              range === r
                ? 'bg-accent-600 text-white'
                : 'bg-surface-800 text-surface-400 hover:bg-surface-700 hover:text-surface-200'
            )}
          >
            {r}
          </button>
        ))}
      </div>

      <div ref={containerRef} className="relative w-full h-[170px]">
        <canvas
          ref={canvasRef}
          className="w-full h-full cursor-crosshair"
          onMouseMove={handleMouseMove}
          onMouseLeave={handleMouseLeave}
        />
        {hoverIdx !== null && tooltipPos && hoveredTime && (
          <div
            className="absolute pointer-events-none z-10 bg-surface-900 border border-surface-700 rounded-lg px-3 py-2 shadow-xl text-xs"
            style={{
              left: Math.min(tooltipPos.x + 12, (containerRef.current?.clientWidth ?? 300) - 160),
              top: Math.max(tooltipPos.y - 60, 0),
            }}
          >
            <div className="text-surface-400 mb-1">{formatHoverTime(hoveredTime, range)}</div>
            <div className="text-surface-100 font-bold text-sm">{formatDecimal(hoveredValue)} <span className="text-surface-500 font-normal">req/s</span></div>
            {hoveredP95 !== undefined && (
              <div className="text-surface-400 mt-0.5">P95: <span className="text-surface-300">{hoveredP95.toFixed(1)}ms</span></div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}

// ── Main Page ─────────────────────────────────────────────────────

export function OverviewPage() {
  const stats = useServerStore((s) => s.stats);
  const isOnline = useServerStore((s) => s.isOnline);
  const lastError = useServerStore((s) => s.lastError);

  return (
    <div className="space-y-6 animate-fade-in">
      <h1 className="text-lg font-bold text-surface-100">Overview</h1>

      {/* Offline banner */}
      {!isOnline && (
        <div className="flex items-center gap-3 p-4 rounded-lg bg-red-950/30 border border-red-900/50">
          <AlertTriangle className="w-5 h-5 text-red-400 flex-shrink-0" />
          <div>
            <p className="text-sm font-medium text-red-300">Server Offline</p>
            <p className="text-xs text-red-400/70">{lastError ?? 'Unable to reach the CRM server'}</p>
          </div>
        </div>
      )}

      {/* Stats grid */}
      <div className="grid grid-cols-3 gap-3">
        <StatCard
          label="Memory (RSS)"
          value={stats?.memory ? formatDecimal(stats.memory.rss) : '--'}
          unit="MB"
          icon={Cpu}
          iconColor="text-purple-400"
        />
        <StatCard
          label="Uptime"
          value={stats?.uptime !== undefined ? formatUptime(stats.uptime) : '--'}
          icon={Clock}
          iconColor="text-green-400"
        />
        <StatCard
          label="Requests/sec"
          sublabel="60s avg"
          value={stats?.requestsPerSecondAvg !== undefined ? formatDecimal(stats.requestsPerSecondAvg) : '--'}
          icon={Zap}
          iconColor="text-amber-400"
        />
        <StatCard
          label="Database"
          value={stats?.dbSizeMB !== undefined ? formatDecimal(stats.dbSizeMB) : '--'}
          unit="MB"
          icon={Database}
          iconColor="text-accent-400"
        />
        <StatCard
          label="Uploads"
          value={stats?.uploadsSizeMB !== undefined ? formatDecimal(stats.uploadsSizeMB) : '--'}
          unit="MB"
          icon={HardDrive}
          iconColor="text-cyan-400"
        />
        <StatCard
          label="Connections"
          value={stats?.activeConnections !== undefined ? String(stats.activeConnections) : '--'}
          icon={Wifi}
          iconColor="text-emerald-400"
        />
      </div>

      {/* Request Rate Graph (live + historical) */}
      <RequestRateGraph
        current={stats?.requestsPerSecond ?? 0}
        avg={stats?.requestsPerSecondAvg ?? 0}
        peak={stats?.requestsPerSecondPeak ?? 0}
        rpm={stats?.requestsPerMinute ?? 0}
        avgMs={stats?.avgResponseMs ?? 0}
        p95Ms={stats?.p95ResponseMs ?? 0}
      />

      {/* System info */}
      {stats && (
        <div className="flex flex-wrap gap-x-6 gap-y-1 text-xs text-surface-500">
          <span>Node {stats.nodeVersion}</span>
          <span>{stats.platform}</span>
          <span>{stats.hostname}</span>
          {stats.multiTenant && (
            <span className="text-accent-400 font-medium">Multi-tenant</span>
          )}
        </div>
      )}
    </div>
  );
}
