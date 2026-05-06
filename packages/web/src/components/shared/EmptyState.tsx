import { Package, type LucideIcon } from 'lucide-react';
import { Button } from './Button';

interface EmptyStateProps {
  icon?: LucideIcon;
  title: string;
  description?: string;
  actionLabel?: string;
  onAction?: () => void;
}

export function EmptyState({
  icon: Icon = Package,
  title,
  description,
  actionLabel,
  onAction,
}: EmptyStateProps) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <Icon className="mb-4 h-16 w-16 text-surface-300 dark:text-surface-600" />
      <h2 className="text-lg font-medium text-surface-600 dark:text-surface-400">
        {title}
      </h2>
      {description && (
        <p className="mt-1 text-sm text-surface-400 dark:text-surface-500">
          {description}
        </p>
      )}
      {actionLabel && onAction && (
        <Button
          onClick={onAction}
          size="md"
          className="mt-4"
        >
          {actionLabel}
        </Button>
      )}
    </div>
  );
}
