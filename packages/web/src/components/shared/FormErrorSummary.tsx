import { AlertCircle } from 'lucide-react';

/**
 * Form-level error summary for long forms — WEB-UIUX-218.
 *
 * Renders a `role="alert"` region at the top of the form that lists every
 * validation error and links to the field that triggered it. Screen readers
 * announce the region as soon as it mounts (or its content changes).
 *
 * Usage
 * -----
 * ```tsx
 * // From a Record<string, string> errors map (CustomerCreatePage pattern):
 * <FormErrorSummary errors={errors} fieldIds={{ first_name: 'field-first-name' }} />
 *
 * // From a flat array of {fieldId, label, message} tuples:
 * <FormErrorSummary errors={[{ fieldId: 'field-email', label: 'Email', message: 'Required' }]} />
 * ```
 *
 * Incremental adoption: pages can pass their existing `errors` Record plus
 * an optional `fieldIds` map (field-key → DOM id). If no `fieldIds` entry
 * exists for a key the item renders without a link.
 *
 * Returns null when the error list is empty, so callers may render
 * unconditionally.
 */

export interface FormErrorEntry {
  /** DOM id of the errored input — used as the href anchor. */
  fieldId?: string;
  /** Human-readable field label shown in the list. */
  label: string;
  /** The validation message for this field. */
  message: string;
}

interface FormErrorSummaryBaseProps {
  /** Optional id for the summary container (e.g. for aria-describedby). */
  id?: string;
  /** Optional className passthrough for top-level margin/spacing. */
  className?: string;
  /** Heading text. Defaults to "Please fix the following errors:". */
  heading?: string;
}

interface FormErrorSummaryArrayProps extends FormErrorSummaryBaseProps {
  /** Pass a pre-built list of error entries. */
  errors: FormErrorEntry[];
  fieldIds?: never;
}

interface FormErrorSummaryRecordProps extends FormErrorSummaryBaseProps {
  /**
   * Pass the page's existing `errors` Record<string, string> directly.
   * Keys become labels (title-cased, underscores replaced with spaces).
   */
  errors: Record<string, string>;
  /**
   * Optional map from Record key → DOM input id.
   * When provided an anchor link is rendered for that field.
   */
  fieldIds?: Record<string, string>;
}

type FormErrorSummaryProps = FormErrorSummaryArrayProps | FormErrorSummaryRecordProps;

function toLabel(key: string): string {
  return key
    .replace(/^custom_\d+_?/, '') // strip custom field prefixes
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (c) => c.toUpperCase());
}

function isArray(e: FormErrorEntry[] | Record<string, string>): e is FormErrorEntry[] {
  return Array.isArray(e);
}

export function FormErrorSummary({
  errors,
  fieldIds,
  id,
  className = '',
  heading = 'Please fix the following errors:',
}: FormErrorSummaryProps) {
  const entries: FormErrorEntry[] = isArray(errors)
    ? errors
    : Object.entries(errors)
        .filter(([, msg]) => Boolean(msg))
        .map(([key, msg]) => ({
          fieldId: (fieldIds as Record<string, string> | undefined)?.[key],
          label: toLabel(key),
          message: msg,
        }));

  if (entries.length === 0) return null;

  return (
    <div
      id={id}
      role="alert"
      aria-live="assertive"
      className={`rounded-md border border-error-200 bg-error-50 p-4 dark:border-error-900 dark:bg-error-950 ${className}`}
    >
      <div className="flex gap-3">
        <AlertCircle
          className="mt-0.5 h-5 w-5 flex-shrink-0 text-error-600 dark:text-error-400"
          aria-hidden="true"
        />
        <div>
          <p className="text-sm font-medium text-error-800 dark:text-error-200">{heading}</p>
          <ul className="mt-2 list-disc space-y-1 pl-5 text-sm text-error-700 dark:text-error-300">
            {entries.map((entry, i) => (
              <li key={entry.fieldId ?? i}>
                {entry.fieldId ? (
                  <a
                    href={`#${entry.fieldId}`}
                    className="underline hover:no-underline focus:outline-none focus-visible:ring-2 focus-visible:ring-error-500"
                    onClick={(e) => {
                      e.preventDefault();
                      document.getElementById(entry.fieldId!)?.focus();
                    }}
                  >
                    {entry.label}
                  </a>
                ) : (
                  <span>{entry.label}</span>
                )}{' '}
                — {entry.message}
              </li>
            ))}
          </ul>
        </div>
      </div>
    </div>
  );
}
