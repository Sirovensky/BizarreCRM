/**
 * RefundReasonPicker — dropdown + optional note for partial refunds.
 * §52 idea 6. The parent wires the selected reason into its existing
 * call to the refunds endpoint (refunds.routes.ts is NOT edited by this
 * agent — the integration is purely frontend).
 *
 * NAMING NOTE (WEB-UIUX-429):
 * The file/component name uses the industry/backend term "Refund" because
 * it maps directly to the refunds endpoint and RefundReasonCode enum.
 * The UI surfaces this as "Credit Note" (accounting terminology preferred
 * by the product/UX team). This intentional mismatch keeps backend types
 * and UI copy decoupled; if UX ever standardises on one term, only the
 * REASONS labels (below) or the file name need updating — not both.
 */
import { useEffect, useState, type ClipboardEvent } from 'react';
import toast from 'react-hot-toast';

export type RefundReasonCode =
  | 'defective'
  | 'dissatisfaction'
  | 'wrong_item'
  | 'duplicate_charge'
  | 'price_adjustment'
  | 'cancelled_service'
  | 'exchange_return'
  | 'tax_adjustment'
  | 'shipping_issue'
  | 'loyalty_promo'
  | 'failed_repair'
  | 'lost_data'
  | 'extended_delay'
  | 'goodwill_gesture'
  | 'chargeback_prevention'
  | 'warranty_invocation'
  // WEB-UIUX-1290: retail-cluster codes added 2026-05-11 so staff stop
  // falling through to 'other' for the most-frequent real-world reasons.
  | 'cancelled_service'
  | 'exchange_no_refund'
  | 'tax_adjustment'
  | 'shipping_issue'
  | 'loyalty_promo_retroactive'
  | 'other';

// WEB-UIUX-1042: hint strings omit terminal periods to match the app-wide
// convention for dropdown labels (no trailing punctuation).
const REASONS: ReadonlyArray<{ code: RefundReasonCode; label: string; hint: string }> = [
  { code: 'defective',                 label: 'Defective product',         hint: 'Arrived broken or malfunctioned' },
  { code: 'dissatisfaction',           label: 'Customer dissatisfied',     hint: 'Changed mind, unhappy with result' },
  { code: 'wrong_item',                label: 'Wrong item',                hint: 'Received/ordered the wrong SKU' },
  { code: 'duplicate_charge',          label: 'Duplicate charge',          hint: 'Billed twice by mistake' },
  { code: 'price_adjustment',          label: 'Price adjustment',          hint: 'Retroactive discount / price match' },
  { code: 'failed_repair',             label: 'Failed repair',             hint: 'Service repair did not resolve the issue' },
  { code: 'lost_data',                 label: 'Lost data',                 hint: 'Customer data lost during service' },
  { code: 'extended_delay',            label: 'Extended delay',            hint: 'Service took significantly longer than quoted' },
  { code: 'goodwill_gesture',          label: 'Goodwill gesture',          hint: 'Discretionary credit to preserve customer relationship' },
  { code: 'chargeback_prevention',     label: 'Chargeback prevention',     hint: 'Pre-emptive refund to avoid a payment dispute' },
  { code: 'warranty_invocation',       label: 'Warranty invocation',       hint: 'Refund issued under product or service warranty' },
  // WEB-UIUX-1290: cluster of high-frequency retail reasons.
  { code: 'cancelled_service',         label: 'Cancelled service',         hint: 'Appointment / service cancelled before work started' },
  { code: 'exchange_no_refund',        label: 'Exchange (no refund)',      hint: 'Returned for swap, no money moved' },
  { code: 'tax_adjustment',            label: 'Tax adjustment',            hint: 'Sales-tax correction (rate, exemption, jurisdiction)' },
  { code: 'shipping_issue',            label: 'Shipping issue',            hint: 'Lost / damaged / never delivered' },
  { code: 'loyalty_promo_retroactive', label: 'Loyalty / promo retro',     hint: 'Discount honored after the sale (missed code, member tier)' },
  { code: 'other',                     label: 'Other',                     hint: 'Free-form reason in the note' },
];

const OTHER_NOTE_MIN = 5;
const NOTE_MAX = 500;
const NOTE_WARN_AT = 450;

interface RefundReasonPickerProps {
  value: RefundReasonCode | null;
  note: string;
  onChange: (reason: RefundReasonCode | null, note: string) => void;
  /** Called whenever the picker's validity state changes. False when "Other"
   *  is selected but the note is shorter than the required minimum. */
  onValidityChange?: (isValid: boolean) => void;
  required?: boolean;
  /** Override the picker's heading label. Defaults to "Refund reason" so
   *  existing refund flows are unaffected; credit-note contexts should pass
   *  "Reason for credit note" to match the modal title. */
  label?: string;
}

export function RefundReasonPicker({
  value,
  note,
  onChange,
  onValidityChange,
  required = true,
  label = 'Refund reason',
}: RefundReasonPickerProps) {
  const [localReason, setLocalReason] = useState<RefundReasonCode | null>(value);
  const [localNote, setLocalNote] = useState(note);
  /** Only show the inline error after the user has interacted with the note field. */
  const [noteTouched, setNoteTouched] = useState(false);

  const isOtherSelected = localReason === 'other';
  const noteIsShort = localNote.trim().length < OTHER_NOTE_MIN;
  const isValid = !isOtherSelected || !noteIsShort;

  useEffect(() => { setLocalReason(value); setLocalNote(note); }, [value, note]);

  useEffect(() => {
    onValidityChange?.(isValid);
  }, [isValid, onValidityChange]);

  const handleReasonChange = (code: RefundReasonCode) => {
    setLocalReason(code);
    // Reset touched state when switching reason so the error only appears
    // after the user actively edits (or blurs) the note for this new choice.
    if (code !== 'other') setNoteTouched(false);
    onChange(code, localNote);
  };

  const handleNoteChange = (next: string) => {
    setLocalNote(next);
    onChange(localReason, next);
  };

  const handleNotePaste = (e: ClipboardEvent<HTMLTextAreaElement>) => {
    const pasted = e.clipboardData.getData('text');
    const selectionLength = e.currentTarget.selectionEnd - e.currentTarget.selectionStart;
    if (localNote.length - selectionLength + pasted.length > NOTE_MAX) {
      toast.error(`Notes are limited to ${NOTE_MAX} characters; extra pasted text was trimmed.`);
    }
  };

  // WEB-FE-016 (Fixer-B5 2026-04-25): swap raw `text-gray-*`/`border-gray-*`
  // for surface-* tokens with `dark:` pairs so the refund picker is readable
  // in dark mode and stays aligned with the Zinc neutral ramp the rest of the
  // app uses (§project_brand_surface_ramp).
  return (
    <div className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
          {label} {required ? <span className="text-red-500">*</span> : null}
        </label>
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-2">
          {REASONS.map((r) => (
            <button
              type="button"
              key={r.code}
              onClick={() => handleReasonChange(r.code)}
              // WEB-UIUX-1303: `min-w-0` lets the flex/grid track shrink the
              // chip below its content's intrinsic width so long labels
              // ("Customer dissatisfied", "Loyalty / promo retro") wrap at
              // word boundaries instead of mid-word on narrow viewports.
              className={`min-h-[44px] min-w-0 rounded-md border px-3 py-2 text-left text-sm transition ${
                localReason === r.code
                  ? 'border-primary-500 bg-primary-50 text-primary-900 dark:bg-primary-900/30 dark:text-primary-200'
                  : 'border-surface-300 dark:border-surface-700 text-surface-900 dark:text-surface-100 hover:border-surface-400 dark:hover:border-surface-600'
              }`}
            >
              <div className="font-medium break-words">{r.label}</div>
              <div className="text-xs text-surface-500 dark:text-surface-400 break-words">{r.hint}</div>
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">
          Notes {isOtherSelected ? <span className="text-red-500">*</span> : '(optional)'}
        </label>
        {/* WEB-UIUX-1044: maxLength=500 matches the practical convention for the
            credit_note_note column (TEXT type, no DB-level cap). The server
            should enforce the same limit in a future hardening pass —
            track as a separate refunds-sprint TODO. */}
        <textarea
          value={localNote}
          onChange={(e) => handleNoteChange(e.target.value)}
          // WEB-UIUX-726: warn the operator when a paste is silently truncated.
          onPaste={(e) => {
            const pasted = e.clipboardData.getData('text');
            const projected = (localNote ?? '').length + pasted.length;
            if (projected > 500) {
              const dropped = projected - 500;
              toast(`Note was truncated — ${dropped} characters dropped (500 max).`, { icon: '⚠️' });
            }
            handleNotePaste(e);
          }}
          onBlur={() => isOtherSelected && setNoteTouched(true)}
          placeholder={isOtherSelected ? 'Please describe the reason…' : 'What happened? (optional)'}
          className={`w-full rounded-md border bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 ${
            isOtherSelected && noteTouched && noteIsShort
              ? 'border-red-500 dark:border-red-400'
              : 'border-surface-300 dark:border-surface-700'
          }`}
          rows={3}
          maxLength={NOTE_MAX}
          aria-describedby={isOtherSelected ? 'refund-note-hint' : undefined}
        />
        <div className={`mt-1 text-xs text-right ${
          localNote.length > NOTE_WARN_AT
            ? 'text-amber-600 dark:text-amber-400'
            : 'text-surface-500 dark:text-surface-400'
        }`}>
          {localNote.length}/{NOTE_MAX}
        </div>
        {isOtherSelected && noteTouched && noteIsShort && (
          <p id="refund-note-hint" className="mt-1 text-xs text-red-600 dark:text-red-400">
            Please describe the reason ({OTHER_NOTE_MIN}+ characters required).
          </p>
        )}
      </div>
    </div>
  );
}
