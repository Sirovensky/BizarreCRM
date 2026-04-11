/**
 * BalanceBadge — small pill shown next to a customer's name in lists.
 * Shows their outstanding balance colored by severity. §52 idea 13.
 *
 * The parent component is responsible for providing the cents value —
 * this component is purely presentational so it can be dropped into any
 * customer list / card without forcing a query rewrite.
 */
interface BalanceBadgeProps {
  cents: number | null | undefined;
  size?: 'sm' | 'md';
}

export function BalanceBadge({ cents, size = 'sm' }: BalanceBadgeProps) {
  if (cents == null || cents === 0) return null;

  const dollars = cents / 100;
  const isOverdue = dollars >= 50;
  const isWarning = dollars >= 10 && dollars < 50;

  const colorClass = isOverdue
    ? 'bg-red-100 text-red-800 border-red-300'
    : isWarning
      ? 'bg-amber-100 text-amber-800 border-amber-300'
      : 'bg-gray-100 text-gray-700 border-gray-300';

  const sizeClass = size === 'md' ? 'px-2 py-1 text-sm' : 'px-1.5 py-0.5 text-xs';

  return (
    <span
      className={`inline-flex items-center rounded-full border font-medium ${colorClass} ${sizeClass}`}
      title={`Outstanding balance: $${dollars.toFixed(2)}`}
    >
      ${dollars.toFixed(2)} due
    </span>
  );
}
