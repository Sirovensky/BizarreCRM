/**
 * InstallmentPlanWizard — "Split $500 into 4 weekly payments" UX.
 * §52 idea 2. Schedule is computed client-side and previewed; the server
 * owns the final INSERT wrapped in a transaction.
 *
 * Acceptance safety note: BlockChyp (§52 idea 2) requires an explicit
 * customer acceptance token before any auto-debit can fire. This wizard
 * captures a typed signature line which becomes the `acceptance_token`
 * and `acceptance_signed_at` on the plan row. No auto-charges happen
 * unless both fields are set.
 */
import { useMemo, useState } from 'react';

interface InstallmentPreview {
  index: number;
  due_date: string;
  amount_cents: number;
}

interface InstallmentPlanWizardProps {
  customerId: number;
  invoiceId?: number | null;
  totalCents: number;
  onSubmit: (payload: {
    customer_id: number;
    invoice_id: number | null;
    total_cents: number;
    installment_count: number;
    frequency_days: number;
    acceptance_token: string;
    acceptance_signed_at: string;
    schedule: InstallmentPreview[];
  }) => void;
  onCancel: () => void;
}

export function InstallmentPlanWizard({
  customerId,
  invoiceId = null,
  totalCents,
  onSubmit,
  onCancel,
}: InstallmentPlanWizardProps) {
  const [installmentCount, setInstallmentCount] = useState(4);
  const [frequencyDays, setFrequencyDays] = useState(7);
  const [startDate, setStartDate] = useState<string>(() =>
    new Date().toISOString().slice(0, 10),
  );
  const [acceptanceText, setAcceptanceText] = useState('');

  const schedule = useMemo<InstallmentPreview[]>(() => {
    if (!installmentCount || installmentCount < 1) return [];
    const perCent = Math.floor(totalCents / installmentCount);
    const remainder = totalCents - perCent * installmentCount;
    const rows: InstallmentPreview[] = [];
    const start = new Date(`${startDate}T00:00:00`);
    for (let i = 0; i < installmentCount; i++) {
      const d = new Date(start);
      d.setDate(d.getDate() + i * frequencyDays);
      rows.push({
        index: i + 1,
        due_date: d.toISOString().slice(0, 10),
        amount_cents: i === installmentCount - 1 ? perCent + remainder : perCent,
      });
    }
    return rows;
  }, [installmentCount, frequencyDays, startDate, totalCents]);

  const acceptanceReady = acceptanceText.trim().length >= 3;

  const handleSubmit = () => {
    if (!acceptanceReady) return;
    onSubmit({
      customer_id: customerId,
      invoice_id: invoiceId,
      total_cents: totalCents,
      installment_count: installmentCount,
      frequency_days: frequencyDays,
      acceptance_token: acceptanceText.trim(),
      acceptance_signed_at: new Date().toISOString(),
      schedule,
    });
  };

  return (
    <div className="space-y-4 rounded-lg border border-gray-200 bg-white p-5 shadow-sm">
      <h2 className="text-lg font-semibold text-gray-900">
        Payment plan — ${(totalCents / 100).toFixed(2)}
      </h2>

      <div className="grid grid-cols-3 gap-4">
        <label className="block">
          <span className="text-sm font-medium text-gray-700"># of payments</span>
          <input
            type="number"
            min={2}
            max={24}
            value={installmentCount}
            onChange={(e) =>
              setInstallmentCount(Math.max(2, Math.min(24, parseInt(e.target.value, 10) || 2)))
            }
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
          />
        </label>
        <label className="block">
          <span className="text-sm font-medium text-gray-700">Frequency (days)</span>
          <select
            value={frequencyDays}
            onChange={(e) => setFrequencyDays(parseInt(e.target.value, 10))}
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
          >
            <option value={7}>Weekly (7 days)</option>
            <option value={14}>Bi-weekly (14 days)</option>
            <option value={30}>Monthly (30 days)</option>
          </select>
        </label>
        <label className="block">
          <span className="text-sm font-medium text-gray-700">First due date</span>
          <input
            type="date"
            value={startDate}
            onChange={(e) => setStartDate(e.target.value)}
            className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
          />
        </label>
      </div>

      <div className="rounded-md border border-gray-200">
        <table className="w-full text-sm">
          <thead className="bg-gray-50 text-gray-600">
            <tr>
              <th className="px-3 py-2 text-left">#</th>
              <th className="px-3 py-2 text-left">Due date</th>
              <th className="px-3 py-2 text-right">Amount</th>
            </tr>
          </thead>
          <tbody>
            {schedule.map((row) => (
              <tr key={row.index} className="border-t border-gray-100">
                <td className="px-3 py-2">{row.index}</td>
                <td className="px-3 py-2">{row.due_date}</td>
                <td className="px-3 py-2 text-right font-medium">
                  ${(row.amount_cents / 100).toFixed(2)}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="rounded-md border border-amber-200 bg-amber-50 p-3 text-sm text-amber-900">
        <p className="font-medium">Customer acceptance required</p>
        <p className="mt-1">
          By typing their name below the customer authorizes auto-debit of each installment
          from the card on file. This is the acceptance token stored with the plan — no
          charges will run without it.
        </p>
        <input
          type="text"
          value={acceptanceText}
          onChange={(e) => setAcceptanceText(e.target.value)}
          placeholder="Customer's full legal name"
          className="mt-2 w-full rounded-md border border-amber-300 bg-white px-3 py-2 text-sm"
        />
      </div>

      <div className="flex justify-end gap-2">
        <button
          type="button"
          className="rounded-md border border-gray-300 px-4 py-2 text-sm hover:bg-gray-50"
          onClick={onCancel}
        >
          Cancel
        </button>
        <button
          type="button"
          disabled={!acceptanceReady}
          className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
          onClick={handleSubmit}
        >
          Create plan
        </button>
      </div>
    </div>
  );
}
