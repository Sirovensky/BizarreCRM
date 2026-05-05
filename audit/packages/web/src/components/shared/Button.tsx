/**
 * WEB-FQ-003 (Fixer-A14 2026-04-25): seed of the canonical <Button> component.
 *
 * Background: 950+ raw `<button>` tags across the app each hand-roll
 * `inline-flex items-center gap-1.5 px-3 py-1.5/py-2 rounded-md/rounded-lg
 * shadow-sm/none transition-colors` — three different "primary" CTAs can
 * appear in a single viewport (see CustomerListPage:577 / 634 / 669).
 *
 * This file is the *seed*: it defines the canonical variants so future
 * call-site migrations all converge on one source of truth. New code
 * should reach for <Button> rather than re-rolling the class strings.
 *
 * Existing call sites are intentionally NOT migrated in this commit —
 * that's a sweeping refactor tracked under WEB-FQ-003 itself. The seed
 * unblocks the migration without any behavioural change today.
 *
 * Variants chosen from the most common patterns observed in the codebase:
 *   - primary  : `bg-primary-600 text-primary-950 hover:bg-primary-700`
 *   - secondary: `border border-surface-300 bg-white text-surface-700`
 *   - ghost    : `text-surface-600 hover:bg-surface-100`
 *   - danger   : `bg-red-600 text-white hover:bg-red-700`
 *
 * Sizes:
 *   - sm: `px-3 py-1.5 text-xs`
 *   - md: `px-4 py-2 text-sm`   (default)
 *   - lg: `px-5 py-2.5 text-sm`
 *
 * Disabled-opacity is normalized to `disabled:opacity-50` per
 * WEB-FQ-007 (50/60/40 inconsistency).
 */
import { forwardRef } from 'react';
import type { ButtonHTMLAttributes, ReactNode } from 'react';

export type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger';
export type ButtonSize = 'sm' | 'md' | 'lg';

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  /** Optional leading icon, rendered before children. */
  leadingIcon?: ReactNode;
  /** Optional trailing icon, rendered after children. */
  trailingIcon?: ReactNode;
  /** When true, the button stretches to its container width. */
  fullWidth?: boolean;
}

const BASE =
  'inline-flex items-center justify-center gap-1.5 rounded-lg font-medium transition-[colors,box-shadow,transform] ' +
  'disabled:opacity-50 disabled:cursor-not-allowed ' +
  'focus:outline-none focus-visible:ring-2 focus-visible:ring-offset-2 focus-visible:ring-primary-500 ' +
  'dark:focus-visible:ring-offset-surface-900';

const VARIANTS: Record<ButtonVariant, string> = {
  primary:
    'bg-primary-600 text-primary-950 shadow-sm hover:bg-primary-700 active:bg-primary-800',
  secondary:
    'border border-surface-300 bg-white text-surface-700 hover:bg-surface-50 ' +
    'dark:border-surface-600 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700',
  ghost:
    'text-surface-600 hover:bg-surface-100 hover:text-surface-900 ' +
    'dark:text-surface-400 dark:hover:bg-surface-800 dark:hover:text-surface-100',
  danger:
    'bg-red-600 text-white shadow-sm hover:bg-red-700 active:bg-red-800',
};

const SIZES: Record<ButtonSize, string> = {
  sm: 'px-3 py-1.5 text-xs',
  md: 'px-4 py-2 text-sm',
  lg: 'px-5 py-2.5 text-sm',
};

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(function Button(
  {
    variant = 'primary',
    size = 'md',
    leadingIcon,
    trailingIcon,
    fullWidth,
    className,
    type = 'button',
    children,
    ...rest
  },
  ref,
) {
  const composed = [
    BASE,
    VARIANTS[variant],
    SIZES[size],
    fullWidth ? 'w-full' : '',
    className ?? '',
  ]
    .filter(Boolean)
    .join(' ');

  return (
    <button ref={ref} type={type} className={composed} {...rest}>
      {leadingIcon}
      {children}
      {trailingIcon}
    </button>
  );
});
