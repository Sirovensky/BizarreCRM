import { cn } from '@/utils/cn';

type StatusBadgeStatus =
  | 'online'
  | 'running'
  | 'offline'
  | 'stopped'
  | 'starting'
  | 'stopping'
  | 'unknown'
  | 'not_installed';

interface StatusBadgeProps {
  status: StatusBadgeStatus;
  size?: 'sm' | 'md';
}

const STATUS_CONFIG: Record<string, { label: string; dotClass: string; textClass: string }> = {
  online: { label: 'Online', dotClass: 'bg-green-500', textClass: 'text-green-400' },
  running: { label: 'Running', dotClass: 'bg-green-500', textClass: 'text-green-400' },
  offline: { label: 'Offline', dotClass: 'bg-red-500', textClass: 'text-red-400' },
  stopped: { label: 'Stopped', dotClass: 'bg-red-500', textClass: 'text-red-400' },
  starting: { label: 'Starting', dotClass: 'bg-amber-500', textClass: 'text-amber-400' },
  stopping: { label: 'Stopping', dotClass: 'bg-amber-500', textClass: 'text-amber-400' },
  not_installed: { label: 'Not Installed', dotClass: 'bg-surface-500', textClass: 'text-surface-400' },
  unknown: { label: 'Unknown', dotClass: 'bg-surface-500', textClass: 'text-surface-400' },
};

export function StatusBadge({ status, size = 'sm' }: StatusBadgeProps) {
  const config = STATUS_CONFIG[status] ?? STATUS_CONFIG.unknown;
  const isOnline = status === 'online' || status === 'running' as string;

  return (
    <span className={cn('inline-flex items-center gap-1.5', size === 'md' ? 'text-sm' : 'text-xs')}>
      <span className="relative flex">
        <span className={cn(
          'rounded-full',
          size === 'md' ? 'h-2.5 w-2.5' : 'h-2 w-2',
          config.dotClass
        )} />
        {isOnline && (
          <span className={cn(
            'absolute inset-0 rounded-full animate-ping opacity-75',
            config.dotClass
          )} />
        )}
      </span>
      <span className={cn('font-medium', config.textClass)}>
        {config.label}
      </span>
    </span>
  );
}
