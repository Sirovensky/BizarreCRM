/**
 * RefundReasonPicker — dropdown + optional note for partial refunds.
 * §52 idea 6. The parent wires the selected reason into its existing
 * call to the refunds endpoint (refunds.routes.ts is NOT edited by this
 * agent — the integration is purely frontend).
 */
import { useState } from 'react';

export type RefundReasonCode =
  | 'defective'
  | 'dissatisfaction'
  | 'wrong_item'
  | 'duplicate_charge'
  | 'price_adjustment'
  | 'other';

const REASONS: ReadonlyArray<{ code: RefundReasonCode; label: string; hint: string }> = [
  { code: 'defective',        label: 'Defective product',   hint: 'Arrived broken or malfunctioned.' },
  { code: 'dissatisfaction',  label: 'Customer dissatisfied', hint: 'Changed mind, unhappy with result.' },
  { code: 'wrong_item',       label: 'Wrong item',          hint: 'Received/ordered the wrong SKU.' },
  { code: 'duplicate_charge', label: 'Duplicate charge',    hint: 'Billed twice by mistake.' },
  { code: 'price_adjustment', label: 'Price adjustment',    hint: 'Retroactive discount / price match.' },
  { code: 'other',            label: 'Other',               hint: 'Free-form reason in the note.' },
];

interface RefundReasonPickerProps {
  value: RefundReasonCode | null;
  note: string;
  onChange: (reason: RefundReasonCode, note: string) => void;
  required?: boolean;
}

export function RefundReasonPicker({
  value,
  note,
  onChange,
  required = true,
}: RefundReasonPickerProps) {
  const [localReason, setLocalReason] = useState<RefundReasonCode | null>(value);
  const [localNote, setLocalNote] = useState(note);

  const handleReasonChange = (code: RefundReasonCode) => {
    setLocalReason(code);
    onChange(code, localNote);
  };

  const handleNoteChange = (next: string) => {
    setLocalNote(next);
    if (localReason) onChange(localReason, next);
  };

  return (
    <div className="space-y-3">
      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Refund reason {required ? <span className="text-red-500">*</span> : null}
        </label>
        <div className="grid grid-cols-2 gap-2">
          {REASONS.map((r) => (
            <button
              type="button"
              key={r.code}
              onClick={() => handleReasonChange(r.code)}
              className={`rounded-md border px-3 py-2 text-left text-sm transition ${
                localReason === r.code
                  ? 'border-primary-500 bg-primary-50 text-primary-900'
                  : 'border-gray-300 hover:border-gray-400'
              }`}
            >
              <div className="font-medium">{r.label}</div>
              <div className="text-xs text-gray-500">{r.hint}</div>
            </button>
          ))}
        </div>
      </div>

      <div>
        <label className="block text-sm font-medium text-gray-700 mb-1">
          Notes (optional)
        </label>
        <textarea
          value={localNote}
          onChange={(e) => handleNoteChange(e.target.value)}
          placeholder="Free-form context to help with reporting…"
          className="w-full rounded-md border border-gray-300 px-3 py-2 text-sm focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
          rows={3}
          maxLength={500}
        />
      </div>
    </div>
  );
}
