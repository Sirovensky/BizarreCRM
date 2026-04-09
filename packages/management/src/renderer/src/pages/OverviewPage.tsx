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

// ── Live RPS Graph (interactive with axes, hover tooltips, responsive) ────
const GRAPH_POINTS = 60; // 60 data points = ~5 minutes at 5s polling
const POLL_INTERVAL_SEC = 5; // matches useServerHealth polling

interface DataPoint {
  value: number;
  time: number; // Date.now() timestamp
}

function LiveRpsGraph({ current, avg, peak, rpm, avgMs, p95Ms }: { current: number; avg: number; peak: number; rpm: number; avgMs: number; p95Ms: number }) {
  const historyRef = useRef<DataPoint[]>([]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const maxRef = useRef(10);
  const [hoverIdx, setHoverIdx] = useState<number | null>(null);
  const [tooltipPos, setTooltipPos] = useState<{ x: number; y: number } | null>(null);

  // Push new data point
  useEffect(() => {
    const h = historyRef.current;
    h.push({ value: current, time: Date.now() });
    if (h.length > GRAPH_POINTS) h.shift();
    maxRef.current = Math.max(...h.map(p => p.value), 10);
    drawGraph(hoverIdx);
  }, [current]);

  // Responsive canvas sizing via ResizeObserver
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

  // Redraw on hover change
  useEffect(() => { drawGraph(hoverIdx); }, [hoverIdx]);

  const drawGraph = useCallback((activeIdx: number | null) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const w = canvas.width / dpr;
    const h = canvas.height / dpr;
    const data = historyRef.current;
    const max = maxRef.current * 1.2; // 20% headroom
    const pad = { top: 12, bottom: 28, left: 44, right: 12 };
    const gW = w - pad.left - pad.right;
    const gH = h - pad.top - pad.bottom;

    ctx.save();
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, w, h);

    // Helper: data index → canvas coords
    const toX = (i: number) => pad.left + (i / (GRAPH_POINTS - 1)) * gW;
    const toY = (v: number) => pad.top + gH - (v / max) * gH;

    // ── Y-axis labels + grid lines ──
    ctx.font = '10px Inter, system-ui, sans-serif';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    const ySteps = 4;
    for (let i = 0; i <= ySteps; i++) {
      const val = max - (max * i) / ySteps;
      const y = pad.top + (gH * i) / ySteps;
      // Grid line
      ctx.strokeStyle = '#1e1e22';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(pad.left, y);
      ctx.lineTo(w - pad.right, y);
      ctx.stroke();
      // Label
      ctx.fillStyle = '#71717a';
      ctx.fillText(val >= 1000 ? `${(val / 1000).toFixed(1)}k` : Math.round(val).toString(), pad.left - 6, y);
    }

    // ── X-axis labels ──
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    ctx.fillStyle = '#71717a';
    const xLabels = [
      { idx: 0, label: `${GRAPH_POINTS * POLL_INTERVAL_SEC}s ago` },
      { idx: Math.floor(GRAPH_POINTS / 2), label: `${Math.floor(GRAPH_POINTS / 2) * POLL_INTERVAL_SEC}s ago` },
      { idx: GRAPH_POINTS - 1, label: 'now' },
    ];
    for (const { idx, label } of xLabels) {
      ctx.fillText(label, toX(idx), h - pad.bottom + 8);
    }

    if (data.length < 2) { ctx.restore(); return; }

    // ── Area fill gradient ──
    const gradient = ctx.createLinearGradient(0, pad.top, 0, h - pad.bottom);
    gradient.addColorStop(0, 'rgba(59, 130, 246, 0.25)');
    gradient.addColorStop(1, 'rgba(59, 130, 246, 0.01)');

    const startIdx = GRAPH_POINTS - data.length;
    ctx.beginPath();
    ctx.moveTo(toX(startIdx), toY(0));
    for (let i = 0; i < data.length; i++) {
      ctx.lineTo(toX(startIdx + i), toY(data[i].value));
    }
    ctx.lineTo(toX(startIdx + data.length - 1), toY(0));
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // ── Data line ──
    ctx.beginPath();
    ctx.strokeStyle = '#3b82f6';
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    ctx.lineCap = 'round';
    for (let i = 0; i < data.length; i++) {
      const x = toX(startIdx + i);
      const y = toY(data[i].value);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // ── Current value dot (pulsing) ──
    if (data.length > 0) {
      const lastX = toX(startIdx + data.length - 1);
      const lastY = toY(data[data.length - 1].value);
      ctx.beginPath();
      ctx.arc(lastX, lastY, 4, 0, Math.PI * 2);
      ctx.fillStyle = current > avg * 2 ? '#ef4444' : '#3b82f6';
      ctx.fill();
      ctx.strokeStyle = '#09090b';
      ctx.lineWidth = 2;
      ctx.stroke();
    }

    // ── Hover crosshair + tooltip dot ──
    if (activeIdx !== null && activeIdx >= 0 && activeIdx < data.length) {
      const hx = toX(startIdx + activeIdx);
      const hy = toY(data[activeIdx].value);

      // Vertical dashed line
      ctx.setLineDash([4, 3]);
      ctx.strokeStyle = '#52525b';
      ctx.lineWidth = 1;
      ctx.beginPath();
      ctx.moveTo(hx, pad.top);
      ctx.lineTo(hx, h - pad.bottom);
      ctx.stroke();
      ctx.setLineDash([]);

      // Highlight dot
      ctx.beginPath();
      ctx.arc(hx, hy, 6, 0, Math.PI * 2);
      ctx.fillStyle = 'rgba(59, 130, 246, 0.3)';
      ctx.fill();
      ctx.beginPath();
      ctx.arc(hx, hy, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = '#60a5fa';
      ctx.fill();
      ctx.strokeStyle = '#09090b';
      ctx.lineWidth = 1.5;
      ctx.stroke();
    }

    ctx.restore();
  }, [current, avg]);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLCanvasElement>) => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const rect = canvas.getBoundingClientRect();
    const mx = e.clientX - rect.left;
    const data = historyRef.current;
    if (data.length < 2) return;

    const dpr = window.devicePixelRatio || 1;
    const w = canvas.width / dpr;
    const pad = { left: 44, right: 12 };
    const gW = w - pad.left - pad.right;
    const startIdx = GRAPH_POINTS - data.length;

    // Find nearest data index
    let closest = -1;
    let closestDist = Infinity;
    for (let i = 0; i < data.length; i++) {
      const x = pad.left + ((startIdx + i) / (GRAPH_POINTS - 1)) * gW;
      const dist = Math.abs(x - mx);
      if (dist < closestDist) { closestDist = dist; closest = i; }
    }

    if (closest >= 0 && closestDist < 20) {
      setHoverIdx(closest);
      setTooltipPos({ x: e.clientX - rect.left, y: e.clientY - rect.top });
    } else {
      setHoverIdx(null);
      setTooltipPos(null);
    }
  }, []);

  const handleMouseLeave = useCallback(() => {
    setHoverIdx(null);
    setTooltipPos(null);
  }, []);

  const hoveredPoint = hoverIdx !== null ? historyRef.current[hoverIdx] : null;
  const hoveredSecsAgo = hoveredPoint ? Math.round((Date.now() - hoveredPoint.time) / 1000) : 0;

  return (
    <div className="stat-card !p-4">
      <div className="flex items-center justify-between mb-3">
        <div className="flex items-center gap-2">
          <Activity className="w-4 h-4 text-accent-400" />
          <span className="text-sm font-semibold text-surface-200">Live Request Rate</span>
        </div>
        <div className="flex items-center gap-4 text-xs">
          <span className="text-surface-500">Now: <span className="font-bold text-surface-100">{formatNumber(current)}</span>/s</span>
          <span className="text-surface-500">Avg: <span className="font-medium text-surface-300">{formatDecimal(avg)}</span>/s</span>
          <span className="text-surface-500">Peak: <span className="font-medium text-amber-400">{formatNumber(peak)}</span>/s</span>
          <span className="text-surface-500">RPM: <span className="font-medium text-surface-300">{formatNumber(rpm)}</span></span>
          <span className="text-surface-500">Avg: <span className={cn('font-medium', avgMs > 100 ? 'text-amber-400' : 'text-surface-300')}>{avgMs.toFixed(1)}ms</span></span>
          <span className="text-surface-500">P95: <span className={cn('font-medium', p95Ms > 500 ? 'text-red-400' : 'text-surface-300')}>{p95Ms.toFixed(0)}ms</span></span>
        </div>
      </div>
      <div ref={containerRef} className="relative w-full h-[170px]">
        <canvas
          ref={canvasRef}
          className="w-full h-full cursor-crosshair"
          onMouseMove={handleMouseMove}
          onMouseLeave={handleMouseLeave}
        />
        {/* Floating tooltip */}
        {hoveredPoint && tooltipPos && (
          <div
            className="absolute pointer-events-none z-10 bg-surface-900 border border-surface-700 rounded-lg px-3 py-2 shadow-xl text-xs"
            style={{
              left: Math.min(tooltipPos.x + 12, (containerRef.current?.clientWidth ?? 300) - 140),
              top: Math.max(tooltipPos.y - 50, 0),
            }}
          >
            <div className="text-surface-400 mb-1">{hoveredSecsAgo === 0 ? 'Now' : `${hoveredSecsAgo}s ago`}</div>
            <div className="text-surface-100 font-bold text-sm">{formatNumber(hoveredPoint.value)} <span className="text-surface-500 font-normal">req/s</span></div>
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

      {/* Live RPS Graph */}
      <LiveRpsGraph
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
