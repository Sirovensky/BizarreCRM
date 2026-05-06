import type { ReactNode } from 'react';

/**
 * Canonical form-field wrapper — WEB-UIUX-216 (a11y: aria-describedby linkage).
 *
 * Renders a <label> + optional error message and automatically assigns the
 * error element a stable id (`<htmlFor>-error`) so callers can wire
 * `aria-describedby` without constructing the id manually.
 *
 * Two children patterns are supported:
 *
 *   1. Render-prop (preferred for inputs with error state):
 *        <FormField htmlFor="email" label="Email" error={errors.email}>
 *          {({ errorId }) => (
 *            <input
 *              id="email"
 *              aria-describedby={errorId}
 *              aria-invalid={!!errors.email}
 *            />
 *          )}
 *        </FormField>
 *
 *   2. Plain children (when no aria-describedby wiring is needed):
 *        <FormField label="Type">
 *          <select>...</select>
 *        </FormField>
 *
 * The error element carries role="alert" + aria-live="polite" so screen
 * readers announce it when it appears, but only once (not one per field like
 * a banner). For submit-level announcements use <FormError variant="banner">.
 *
 * Adopted incrementally — existing per-page local FormField definitions and
 * direct aria-describedby wiring remain valid; new code and refactors should
 * use this component.
 */

export interface FormFieldContext {
  /** Stable id for the error element, or undefined when no htmlFor is set. */
  errorId: string | undefined;
}

interface FormFieldProps {
  /** Text for the <label> element. */
  label: string;
  /** The `id` of the associated control. Used for label[for] + error-id derivation. */
  htmlFor?: string;
  /** If true, renders a red asterisk after the label (decorative, aria-hidden). */
  required?: boolean;
  /** Error message. When truthy, renders the error element and exposes errorId. */
  error?: string | null;
  /** Optional helper/hint text shown below the control (not in error state). */
  hint?: string;
  /** Optional className applied to the outermost wrapper div. */
  className?: string;
  /**
   * Children — either a ReactNode or a render-prop function receiving
   * `{ errorId }` so the inner control can set aria-describedby.
   */
  children: ReactNode | ((ctx: FormFieldContext) => ReactNode);
}

export function FormField({
  label,
  htmlFor,
  required,
  error,
  hint,
  className = '',
  children,
}: FormFieldProps) {
  // Derive a stable error-element id from the control id so callers never
  // have to construct it manually.
  const errorId: string | undefined = htmlFor && error ? `${htmlFor}-error` : undefined;
  // Also expose a hint id when a hint is present, combined with errorId when
  // both exist so aria-describedby can reference both.
  const hintId: string | undefined = htmlFor && hint ? `${htmlFor}-hint` : undefined;

  const ctx: FormFieldContext = { errorId };

  return (
    <div className={className}>
      <label
        htmlFor={htmlFor}
        className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1"
      >
        {label}
        {required && (
          <span className="text-red-500 ml-0.5" aria-hidden="true">
            *
          </span>
        )}
      </label>

      {typeof children === 'function' ? children(ctx) : children}

      {hint && !error && (
        <p
          id={hintId}
          className="mt-1 text-xs text-surface-500 dark:text-surface-400"
        >
          {hint}
        </p>
      )}

      {error && (
        <p
          id={errorId}
          role="alert"
          aria-live="polite"
          className="mt-1 text-xs text-red-500 dark:text-red-400"
        >
          {error}
        </p>
      )}
    </div>
  );
}
