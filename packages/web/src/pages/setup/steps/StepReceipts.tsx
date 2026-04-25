import { Receipt } from 'lucide-react';
import type { SubStepProps } from '../wizardTypes';
import { SubStepHeader, SubStepFooter } from './StepBusinessHours';

/**
 * Sub-step — Receipt Layout.
 * Edits the header, footer, and title text shown on thermal and A4 receipts.
 * Live preview in the right column so users can see changes immediately.
 */
export function StepReceipts({ pending, onUpdate, onComplete, onCancel }: SubStepProps) {
  const header = pending.receipt_header || '';
  const footer = pending.receipt_footer || '';
  const title = pending.receipt_title || '';

  return (
    <div className="mx-auto max-w-3xl">
      <SubStepHeader
        title="Receipt Layout"
        subtitle="Customize the header and footer text on your receipts. Supports multi-line text."
        icon={<Receipt className="h-7 w-7 text-primary-600 dark:text-primary-400" />}
      />

      <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
        {/* Edit column */}
        <div className="space-y-4 rounded-2xl border border-surface-200 bg-white p-6 shadow-xl dark:border-surface-700 dark:bg-surface-800">
          <div>
            <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Receipt title (optional)
            </label>
            <input
              type="text"
              value={title}
              onChange={(e) => onUpdate({ receipt_title: e.target.value })}
              placeholder="Thank you for your business!"
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Header text
            </label>
            <textarea
              value={header}
              onChange={(e) => onUpdate({ receipt_header: e.target.value })}
              placeholder="Joe's Phone Repair&#10;123 Main Street&#10;City, State ZIP"
              rows={4}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-sm font-medium text-surface-700 dark:text-surface-300">
              Footer text
            </label>
            <textarea
              value={footer}
              onChange={(e) => onUpdate({ receipt_footer: e.target.value })}
              placeholder="Warranty: 90 days parts and labor&#10;Questions? Call us at (555) 123-4567"
              rows={4}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
        </div>

        {/* Preview column */}
        <div className="rounded-2xl border border-surface-200 bg-surface-50 p-6 shadow-inner dark:border-surface-700 dark:bg-surface-900/50">
          <p className="mb-3 text-xs font-semibold uppercase tracking-wide text-surface-500">Preview</p>
          <div className="rounded-lg border border-dashed border-surface-300 bg-white p-4 font-mono text-xs leading-relaxed text-surface-900 dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100">
            {header && <div className="whitespace-pre-line text-center font-bold">{header}</div>}
            {title && <div className="mt-2 text-center italic">{title}</div>}
            <div className="my-3 border-t border-dashed border-surface-300 dark:border-surface-600" />
            <div className="text-surface-400">-- receipt content goes here --</div>
            <div className="my-3 border-t border-dashed border-surface-300 dark:border-surface-600" />
            {footer && <div className="whitespace-pre-line text-center">{footer}</div>}
            {!header && !footer && !title && (
              <div className="text-center text-surface-400">Fill in the form to preview.</div>
            )}
          </div>
        </div>
      </div>

      <SubStepFooter onCancel={onCancel} onComplete={onComplete} completeLabel="Save receipt layout" />
    </div>
  );
}
