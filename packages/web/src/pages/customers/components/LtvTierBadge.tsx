import { useQuery } from '@tanstack/react-query';
import { Award, Crown, Medal } from 'lucide-react';
import { crmApi } from '@/api/endpoints';
import { formatCents } from '@/utils/format';
import { cn } from '@/utils/cn';

/**
 * LtvTierBadge — displays a customer's lifetime-value tier + formatted total.
 * Tiers (cents):
 *   bronze   <   50_000  ($500)
 *   silver   <  250_000  ($2500)
 *   gold     <  750_000  ($7500)
 *   platinum >= 750_000
 */

interface LtvTierBadgeProps {
  customerId: number;
  className?: string;
  showValue?: boolean;
}

type Tier = 'bronze' | 'silver' | 'gold' | 'platinum';

interface LtvResponse {
  success: boolean;
  data: {
    tier: Tier;
    lifetime_value_cents: number;
  };
}

const TIER_META: Record<Tier, {
  label: string;
  classes: string;
  icon: typeof Award;
}> = {
  bronze: {
    label: 'Bronze',
    classes:
      'bg-amber-50 text-amber-800 border-amber-200 dark:bg-amber-900/20 dark:text-amber-300 dark:border-amber-800',
    icon: Medal,
  },
  silver: {
    label: 'Silver',
    classes:
      'bg-slate-100 text-slate-700 border-slate-300 dark:bg-slate-700/30 dark:text-slate-200 dark:border-slate-600',
    icon: Medal,
  },
  gold: {
    label: 'Gold',
    classes:
      'bg-yellow-100 text-yellow-800 border-yellow-300 dark:bg-yellow-900/20 dark:text-yellow-300 dark:border-yellow-800',
    icon: Award,
  },
  platinum: {
    label: 'Platinum',
    classes:
      'bg-indigo-100 text-indigo-700 border-indigo-300 dark:bg-indigo-900/20 dark:text-indigo-300 dark:border-indigo-800',
    icon: Crown,
  },
};

export function LtvTierBadge({ customerId, className, showValue = true }: LtvTierBadgeProps) {
  const { data, isLoading } = useQuery<LtvResponse>({
    queryKey: ['crm', 'ltv-tier', customerId],
    queryFn: async () => {
      const res = await crmApi.ltvTier(customerId);
      return res.data as LtvResponse;
    },
    enabled: !!customerId,
    staleTime: 60_000,
  });

  if (isLoading || !data?.data) {
    return (
      <div className={cn(
        'inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full text-xs border bg-surface-100 text-surface-400 border-surface-200 dark:bg-surface-800 dark:border-surface-700',
        className,
      )}>
        <Medal className="h-3 w-3 animate-pulse" />
        <span>Loading...</span>
      </div>
    );
  }

  const tier = data.data.tier;
  const meta = TIER_META[tier] ?? TIER_META.bronze;
  const Icon = meta.icon;
  const cents = data.data.lifetime_value_cents ?? 0;

  return (
    <div
      className={cn(
        'inline-flex items-center gap-2 px-3 py-1 rounded-full border text-xs font-medium',
        meta.classes,
        className,
      )}
      title={`Lifetime value: ${formatCents(cents)}`}
    >
      <Icon className="h-3.5 w-3.5" />
      <span>{meta.label}</span>
      {showValue && (
        <span className="font-mono tabular-nums opacity-75">
          {formatCents(cents)}
        </span>
      )}
    </div>
  );
}
