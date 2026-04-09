import { useRef, useEffect } from 'react';
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

// ── Live RPS Graph ────────────────────────────────────────────────
const GRAPH_POINTS = 60; // 60 data points = ~5 minutes at 5s polling

function LiveRpsGraph({ current, avg, peak, rpm, avgMs, p95Ms }: { current: number; avg: number; peak: number; rpm: number; avgMs: number; p95Ms: number }) {
  const historyRef = useRef<number[]>([]);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const maxRef = useRef(10);

  // Push new data point
  useEffect(() => {
    const h = historyRef.current;
    h.push(current);
    if (h.length > GRAPH_POINTS) h.shift();
    // Track max for scaling
    const localMax = Math.max(...h, 10);
    maxRef.current = localMax;
    drawGraph();
  }, [current]);

  const drawGraph = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const w = canvas.width;
    const h = canvas.height;
    const data = historyRef.current;
    const max = maxRef.current * 1.2; // 20% headroom
    const padding = { top: 10, bottom: 20, left: 0, right: 0 };
    const graphW = w - padding.left - padding.right;
    const graphH = h - padding.top - padding.bottom;

    ctx.clearRect(0, 0, w, h);

    if (data.length < 2) return;

    // Grid lines
    ctx.strokeStyle = '#27272a';
    ctx.lineWidth = 1;
    for (let i = 0; i <= 4; i++) {
      const y = padding.top + (graphH * i) / 4;
      ctx.beginPath();
      ctx.moveTo(padding.left, y);
      ctx.lineTo(w - padding.right, y);
      ctx.stroke();
    }

    // Fill gradient
    const gradient = ctx.createLinearGradient(0, padding.top, 0, h - padding.bottom);
    gradient.addColorStop(0, 'rgba(59, 130, 246, 0.3)');
    gradient.addColorStop(1, 'rgba(59, 130, 246, 0.02)');

    ctx.beginPath();
    ctx.moveTo(padding.left, h - padding.bottom);
    for (let i = 0; i < data.length; i++) {
      const x = padding.left + (i / (GRAPH_POINTS - 1)) * graphW;
      const y = padding.top + graphH - (data[i] / max) * graphH;
      if (i === 0) ctx.lineTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.lineTo(padding.left + ((data.length - 1) / (GRAPH_POINTS - 1)) * graphW, h - padding.bottom);
    ctx.closePath();
    ctx.fillStyle = gradient;
    ctx.fill();

    // Line
    ctx.beginPath();
    ctx.strokeStyle = '#3b82f6';
    ctx.lineWidth = 2;
    ctx.lineJoin = 'round';
    for (let i = 0; i < data.length; i++) {
      const x = padding.left + (i / (GRAPH_POINTS - 1)) * graphW;
      const y = padding.top + graphH - (data[i] / max) * graphH;
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Current value dot
    if (data.length > 0) {
      const lastX = padding.left + ((data.length - 1) / (GRAPH_POINTS - 1)) * graphW;
      const lastY = padding.top + graphH - (data[data.length - 1] / max) * graphH;
      ctx.beginPath();
      ctx.arc(lastX, lastY, 4, 0, Math.PI * 2);
      ctx.fillStyle = current > avg * 2 ? '#ef4444' : '#3b82f6';
      ctx.fill();
      ctx.strokeStyle = '#09090b';
      ctx.lineWidth = 2;
      ctx.stroke();
    }
  };

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
      <canvas
        ref={canvasRef}
        width={800}
        height={150}
        className="w-full h-[150px]"
      />
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
