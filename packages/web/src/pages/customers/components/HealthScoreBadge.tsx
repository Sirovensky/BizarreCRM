import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Activity, RefreshCw, TrendingUp, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { crmApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

/**
 * HealthScoreBadge — shows a 0-100 customer health score and tier.
 * Reads data via GET /crm/customers/:id/health-score.
 *
 * Tiers:
 *   champion   (80-100) — emerald
 *   healthy    (50- 79) — sky
 *   at_risk    (<50)    — amber
 *
 * If the score is null (customer has never been scored) the badge renders
 * a "Score" action button that calls POST /recalculate so the owner can
 * seed it on first view.
 */

interface HealthScoreBadgeProps {
  customerId: number;
  /** Compact mode strips padding + description, used in list rows */
  compact?: boolean;
  className?: string;
}

type Tier = 'champion' | 'healthy' | 'at_risk' | null;

interface HealthScoreResponse {
  success: boolean;
  data: {
    score: number | null;
    tier: Tier;
    last_interaction_at: string | null;
    lifetime_value_cents: number;
  };
}

const TIER_META: Record<Exclude<Tier, null>, {
  label: string;
  classes: string;
  icon: typeof Activity;
}> = {
  champion: {
    label: 'Champion',
    classes:
      'bg-emerald-100 text-emerald-700 border-emerald-200 dark:bg-emerald-900/30 dark:text-emerald-300 dark:border-emerald-800',
    icon: TrendingUp,
  },
  healthy: {
    label: 'Healthy',
    classes:
      'bg-sky-100 text-sky-700 border-sky-200 dark:bg-sky-900/30 dark:text-sky-300 dark:border-sky-800',
    icon: Activity,
  },
  at_risk: {
    label: 'At Risk',
    classes:
      'bg-amber-100 text-amber-700 border-amber-200 dark:bg-amber-900/30 dark:text-amber-300 dark:border-amber-800',
    icon: AlertCircle,
  },
};

export function HealthScoreBadge({ customerId, compact = false, className }: HealthScoreBadgeProps) {
  const queryClient = useQueryClient();

  const { data, isLoading } = useQuery<HealthScoreResponse>({
    queryKey: ['crm', 'health-score', customerId],
    queryFn: async () => {
      const res = await crmApi.healthScore(customerId);
      return res.data as HealthScoreResponse;
    },
    enabled: !!customerId,
    staleTime: 60_000,
  });

  const recalculate = useMutation({
    mutationFn: async () => {
      const res = await crmApi.recalculateHealth(customerId);
      return res.data;
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['crm', 'health-score', customerId] });
      queryClient.invalidateQueries({ queryKey: ['crm', 'ltv-tier', customerId] });
      toast.success('Health score refreshed');
    },
    onError: () => {
      toast.error('Failed to refresh health score');
    },
  });

  if (isLoading) {
    return (
      <div className={cn(
        'inline-flex items-center gap-1.5 px-2 py-1 rounded-full text-xs border bg-surface-100 text-surface-400 border-surface-200 dark:bg-surface-800 dark:border-surface-700',
        className,
      )}>
        <Activity className="h-3 w-3 animate-pulse" />
        <span>Loading...</span>
      </div>
    );
  }

  const score = data?.data?.score ?? null;
  const tier = data?.data?.tier ?? null;

  if (score === null || tier === null) {
    return (
      <button
        type="button"
        onClick={() => recalculate.mutate()}
        disabled={recalculate.isPending}
        className={cn(
          'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs font-medium border transition-colors',
          'bg-surface-50 text-surface-600 border-surface-200 hover:bg-surface-100',
          'dark:bg-surface-800 dark:text-surface-300 dark:border-surface-700 dark:hover:bg-surface-700',
          className,
        )}
      >
        <RefreshCw className={cn('h-3 w-3', recalculate.isPending && 'animate-spin')} />
        Score customer
      </button>
    );
  }

  const meta = TIER_META[tier];
  const Icon = meta.icon;

  return (
    <div
      className={cn(
        'inline-flex items-center gap-2 rounded-full border font-medium',
        compact ? 'px-2 py-0.5 text-[11px]' : 'px-3 py-1 text-xs',
        meta.classes,
        className,
      )}
      title={`Health score ${score}/100 — ${meta.label}`}
    >
      <Icon className={compact ? 'h-3 w-3' : 'h-3.5 w-3.5'} />
      <span>{meta.label}</span>
      <span className={cn('font-mono tabular-nums', compact ? '' : 'ml-0.5')}>
        {score}
      </span>
      {!compact && (
        <button
          type="button"
          onClick={(e) => {
            e.stopPropagation();
            recalculate.mutate();
          }}
          disabled={recalculate.isPending}
          className="ml-1 p-0.5 rounded-full hover:bg-black/10 dark:hover:bg-white/10 transition-colors"
          aria-label="Refresh health score"
        >
          <RefreshCw className={cn('h-3 w-3', recalculate.isPending && 'animate-spin')} />
        </button>
      )}
    </div>
  );
}
