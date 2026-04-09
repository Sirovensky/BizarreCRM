import {
  Cpu,
  HardDrive,
  Clock,
  Zap,
  Database,
  Wifi,
  AlertTriangle,
} from 'lucide-react';
import { cn } from '@/utils/cn';
import { useServerStore } from '@/stores/serverStore';
import { formatUptime, formatDecimal } from '@/utils/format';

interface StatCardProps {
  label: string;
  value: string;
  unit?: string;
  icon: React.ElementType;
  iconColor?: string;
}

function StatCard({ label, value, unit, icon: Icon, iconColor = 'text-accent-400' }: StatCardProps) {
  return (
    <div className="stat-card">
      <div className="flex items-center justify-between mb-3">
        <span className="text-[11px] font-medium text-surface-500 uppercase tracking-wider">
          {label}
        </span>
        <Icon className={cn('w-4 h-4', iconColor)} />
      </div>
      <div className="flex items-baseline gap-1">
        <span className="text-2xl font-bold text-surface-100">{value}</span>
        {unit && <span className="text-xs text-surface-500">{unit}</span>}
      </div>
    </div>
  );
}

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
          value={stats?.requestsPerSecond !== undefined ? formatDecimal(stats.requestsPerSecond) : '--'}
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
