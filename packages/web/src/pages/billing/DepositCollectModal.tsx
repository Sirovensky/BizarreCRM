/**
 * DepositCollectModal — §52 idea 8.
 * Small modal invoked from repair drop-off screens. Writes to
 * /api/v1/deposits so the final invoice can subtract the amount via
 * apply-to-invoice.
 *
 * Consumer wiring example:
 *
 *   const [open, setOpen] = useState(false);
 *   <button onClick={() => setOpen(true)}>Collect deposit</button>
 *   {open && (
 *     <DepositCollectModal
 *       customerId={customer.id}
 *       ticketId={ticket.id}
 *       onClose={() => setOpen(false)}
 *       onSuccess={() => { setOpen(false); refetchTicket(); }}
 *     />
 *   )}
 */
import { useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface DepositCollectModalProps {
  customerId: number;
  ticketId?: number | null;
  onClose: () => void;
  onSuccess?: (depositId: number) => void;
}

export function DepositCollectModal({
  customerId,
  ticketId = null,
  onClose,
  onSuccess,
}: DepositCollectModalProps) {
  const [amount, setAmount] = useState('');
  const [notes, setNotes] = useState('');

  const mutation = useMutation({
    mutationFn: async () => {
      const parsed = parseFloat(amount);
      if (!isFinite(parsed) || parsed <= 0) throw new Error('Enter a positive amount');
      const res = await api.post('/deposits', {
        customer_id: customerId,
        ticket_id: ticketId,
        amount: parsed,
        notes: notes || null,
      });
      return res.data.data as { id: number; amount_cents: number };
    },
    onSuccess: (data) => {
      toast.success(`Deposit of $${(data.amount_cents / 100).toFixed(2)} collected`);
      onSuccess?.(data.id);
    },
    onError: (err: unknown) => {
      toast.error(err instanceof Error ? err.message : 'Failed to collect deposit');
    },
  });

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4">
      <div className="w-full max-w-md rounded-lg bg-white p-6 shadow-xl">
        <h2 className="text-lg font-semibold text-gray-900">Collect Deposit</h2>
        <p className="mt-1 text-sm text-gray-500">
          Amount collected now will be subtracted from the final invoice when the repair is
          finalized.
        </p>

        <div className="mt-4 space-y-3">
          <label className="block">
            <span className="text-sm font-medium text-gray-700">Amount (USD)</span>
            <input
              type="number"
              step="0.01"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
              placeholder="100.00"
            />
          </label>
          <label className="block">
            <span className="text-sm font-medium text-gray-700">Notes (optional)</span>
            <textarea
              rows={3}
              value={notes}
              onChange={(e) => setNotes(e.target.value)}
              className="mt-1 w-full rounded-md border border-gray-300 px-3 py-2 text-sm"
              maxLength={500}
              placeholder="e.g. parts order deposit"
            />
          </label>
        </div>

        <div className="mt-5 flex justify-end gap-2">
          <button
            onClick={onClose}
            className="rounded-md border border-gray-300 px-4 py-2 text-sm hover:bg-gray-50"
          >
            Cancel
          </button>
          <button
            onClick={() => mutation.mutate()}
            disabled={mutation.isPending}
            className="rounded-md bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
          >
            {mutation.isPending ? 'Collecting…' : 'Collect deposit'}
          </button>
        </div>
      </div>
    </div>
  );
}
