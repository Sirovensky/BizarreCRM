import { useNavigate } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { Button } from './Button';

interface BackButtonProps {
  /** Override default navigate(-1) behavior */
  to?: string;
  /** Optional label (defaults to "Back") */
  label?: string;
}

export function BackButton({ to, label = 'Back' }: BackButtonProps) {
  const navigate = useNavigate();

  return (
    <Button
      type="button"
      onClick={() => (to ? navigate(to) : navigate(-1))}
      variant="ghost"
      size="sm"
      leadingIcon={<ArrowLeft aria-hidden="true" className="h-4 w-4" />}
      className="gap-1.5 px-2 text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
    >
      {label}
    </Button>
  );
}
