/**
 * BalanceBadge — small pill shown next to a customer's name in lists.
 * Shows their outstanding balance colored by severity. §52 idea 13.
 *
 * The parent component is responsible for providing the cents value —
 * this component is purely presentational so it can be dropped into any
 * customer list / card without forcing a query rewrite.
 */
import { formatCents } from '@/utils/format';

interface BalanceBadgeProps {
  cents: number | null | undefined;
  size?: 'sm' | 'md';
}

export function BalanceBadge({ cents, size = 'sm' }: BalanceBadgeProps) {
  if (cents == null || cents === 0) return null;

  // Severity thresholds are in integer cents to keep the comparison
  // exact — no "49.99 rounds to 50 but should be warning, not overdue"
  // ambiguity. $50 and $10 as the two cut-offs.
  const absCents = Math.abs(cents);
  const isCredit = cents < 0; // FD-009: negative = customer is in credit, not debt
  const isOverdue = !isCredit && absCents >= 5000;
  const isWarning = !isCredit && absCents >= 1000 && absCents < 5000;

  const colorClass = isCredit
    ? 'bg-emerald-100 text-emerald-800 border-emerald-300'
    : isOverdue
      ? 'bg-red-100 text-red-800 border-red-300'
      : isWarning
        ? 'bg-amber-100 text-amber-800 border-amber-300'
        : 'bg-gray-100 text-gray-700 border-gray-300';

  const sizeClass = size === 'md' ? 'px-2 py-1 text-sm' : 'px-1.5 py-0.5 text-xs';
  // FD-009: format with the absolute value so the sign is conveyed by the
  // suffix ("credit" vs "due") rather than a leading minus that owners read
  // inconsistently. Title attribute spells out the direction explicitly for
  // screen readers + tooltip hover.
  const formattedAbs = formatCents(absCents);
  const suffix = isCredit ? 'credit' : 'due';

  return (
    <span
      className={`inline-flex items-center rounded-full border font-medium ${colorClass} ${sizeClass}`}
      title={isCredit ? `Account credit: ${formattedAbs}` : `Outstanding balance: ${formattedAbs}`}
    >
      {formattedAbs} {suffix}
    </span>
  );
}
