import { forwardRef } from 'react';
import type { ButtonHTMLAttributes, ReactNode } from 'react';
import { cn } from '@/utils/cn';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';
export type ButtonSize = 'xs' | 'sm' | 'md' | 'lg' | 'xl';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Optional leading icon, rendered before children. */
  leadingIcon?: ReactNode;
  /** Optional trailing icon, rendered after children. */
  trailingIcon?: ReactNode;
  /** Square sizing for icon-only controls while still using the same height scale. */
  iconOnly?: boolean;
  /** When true, the button stretches to its container width. */
  fullWidth?: boolean;
}

const BASE =
  'inline-flex shrink-0 items-center justify-center gap-2 whitespace-nowrap rounded-lg font-medium transition-colors ' +
  'disabled:opacity-50 disabled:cursor-not-allowed ' +
  'focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary-500 ' +
  'dark:focus-visible:ring-offset-surface-900';

const VARIANTS: Record<ButtonVariant, string> = {
  primary:
    'bg-primary-600 text-on-primary shadow-sm hover:bg-primary-700 active:bg-primary-800',
  secondary:
    'border border-surface-300 bg-white text-surface-700 hover:bg-surface-50 ' +
    'dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700',
  ghost:
    'text-surface-600 hover:bg-surface-100 hover:text-surface-900 ' +
    'dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-100',
  danger:
    'bg-red-600 text-white shadow-sm hover:bg-red-700 active:bg-red-800',
};

const SIZE_CLASSES: Record<ButtonSize, { regular: string; icon: string }> = {
  xs: { regular: 'h-7 px-2 text-xs', icon: 'h-7 w-7 p-0' },
  sm: { regular: 'h-9 px-3 text-sm', icon: 'h-9 w-9 p-0' },
  md: { regular: 'h-10 px-4 text-sm', icon: 'h-10 w-10 p-0' },
  lg: { regular: 'h-12 px-4 text-base', icon: 'h-12 w-12 p-0' },
  xl: { regular: 'h-14 px-5 text-base', icon: 'h-14 w-14 p-0' },
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'primary',
    size = 'md',
    leadingIcon,
    trailingIcon,
    iconOnly,
    fullWidth,
    className,
    type = 'button',
    children,
    ...rest
  },
  ref,
) {
  const composed = cn(
    BASE,
    VARIANTS[variant],
    iconOnly ? SIZE_CLASSES[size].icon : SIZE_CLASSES[size].regular,
    fullWidth && 'w-full',
    className,
  );

  return (
    <button ref={ref} type={type} className={composed} {...rest}>
      {leadingIcon}
      {children}
      {trailingIcon}
    </button>
  );
});
