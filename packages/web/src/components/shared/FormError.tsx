import { AlertCircle } from 'lucide-react';

/**
 * Shared form-error primitive — WEB-FQ-019 (Fixer-C10 2026-04-25).
 *
 * Three variants codify the audit's split between "field-level inline error"
 * (`field`), "form-submit banner" (`banner`), and "tiny helper text"
 * (`hint`). Adopted incrementally — existing per-page red-500 borders /
 * `<p class="text-sm text-red-600 mt-1">` lines remain valid; new code and
 * page-touch refactors should consume this primitive instead of inventing
 * another visual treatment. Field/hint variants intentionally avoid
 * `role="alert"` so a failed long form does not trigger one screen-reader
 * announcement per invalid field; use the banner variant for submit-level
 * announcements.
 */

interface FormErrorProps {
  /** The error message to render. If empty/falsy, returns null. */
  message?: string | null;
  /** Visual treatment. Default `field`. */
  variant?: 'field' | 'banner' | 'hint';
  /** Optional id for `aria-describedby` wiring on the associated input. */
  id?: string;
  /** Optional className passthrough for layout (margins). */
  className?: string;
}

export function FormError({
  message,
  variant = 'field',
  id,
  className = '',
}: FormErrorProps) {
  if (!message) return null;

  if (variant === 'banner') {
    return (
      <div
        id={id}
        role="alert"
        className={`flex items-start gap-2 rounded-md border border-error-200 bg-error-50 p-3 text-sm text-error-700 dark:border-error-900 dark:bg-error-950 dark:text-error-300 ${className}`}
      >
        <AlertCircle className="mt-0.5 h-4 w-4 flex-shrink-0" aria-hidden="true" />
        <span>{message}</span>
      </div>
    );
  }

  if (variant === 'hint') {
    return (
      <p
        id={id}
        className={`mt-1 text-xs text-error-600 dark:text-error-400 ${className}`}
      >
        {message}
      </p>
    );
  }

  // variant === 'field' (default)
  return (
    <p
      id={id}
      className={`mt-1 text-sm text-error-600 dark:text-error-400 ${className}`}
    >
      {message}
    </p>
  );
}
