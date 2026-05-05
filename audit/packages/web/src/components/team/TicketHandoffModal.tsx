/**
 * Ticket handoff modal — criticalaudit.md §53 idea #4.
 *
 * Lets the current assignee transfer a ticket to another tech with a REQUIRED
 * reason. The server logs the handoff in `ticket_handoffs` and reassigns the
 * `tickets.assigned_to` column atomically.
 *
 * Designed to be dropped into TicketDetailPage by the tickets agent in a
 * follow-up — they own that file, we don't touch it. Importable from here.
 */
import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, ArrowRightLeft } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface Employee {
  id: number;
  first_name: string;
  last_name: string;
}

interface TicketHandoffModalProps {
  ticketId: number;
  currentAssigneeId: number | null;
  onClose: () => void;
  onHandedOff?: () => void;
}

export function TicketHandoffModal({
  ticketId,
  currentAssigneeId,
  onClose,
  onHandedOff,
}: TicketHandoffModalProps) {
  const queryClient = useQueryClient();
  const [toUserId, setToUserId] = useState<number | ''>('');
  const [reason, setReason] = useState('');
  const [context, setContext] = useState('');

  const { data: employeesData } = useQuery({
    queryKey: ['employees', 'simple'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Employee[] }>('/employees');
      return res.data.data;
    },
  });
  const employees: Employee[] = (employeesData || []).filter((e) => e.id !== currentAssigneeId);

  const handoffMut = useMutation({
    mutationFn: async () => {
      await api.post(`/team/handoff/${ticketId}`, {
        to_user_id: Number(toUserId),
        reason: reason.trim(),
        context: context.trim() || null,
      });
    },
    onSuccess: () => {
      toast.success('Ticket handed off');
      queryClient.invalidateQueries({ queryKey: ['ticket', ticketId] });
      queryClient.invalidateQueries({ queryKey: ['team', 'my-queue'] });
      onHandedOff?.();
      onClose();
    },
    onError: (e: unknown) => {
      const msg =
        e && typeof e === 'object' && 'response' in e
          ? (e as { response?: { data?: { error?: string } } }).response?.data?.error
          : null;
      toast.error(msg || 'Handoff failed');
    },
  });

  const canSubmit = !!toUserId && reason.trim().length > 0 && !handoffMut.isPending;

  // WEB-FX-003: Esc-to-close.
  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  return (
    <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4" onClick={onClose}>
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="ticket-handoff-title"
        className="bg-white rounded-lg shadow-xl max-w-md w-full p-5"
        onClick={(e) => e.stopPropagation()}
      >
        <h2 id="ticket-handoff-title" className="text-lg font-bold mb-1 inline-flex items-center">
          <ArrowRightLeft className="w-5 h-5 mr-2 text-primary-500" /> Hand off ticket
        </h2>
        <p className="text-xs text-surface-500 dark:text-surface-400 mb-4">
          The new assignee will see this in their queue. The reason is logged for audit.
        </p>
        <div className="space-y-3">
          <label className="block">
            <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Hand off to</span>
            <select
              className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
              value={toUserId}
              onChange={(e) => setToUserId(e.target.value ? Number(e.target.value) : '')}
            >
              <option value="">— pick employee —</option>
              {employees.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.first_name} {e.last_name}
                </option>
              ))}
            </select>
          </label>
          <label className="block">
            <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Reason (required)</span>
            <input
              type="text"
              className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
              value={reason}
              onChange={(e) => setReason(e.target.value)}
              placeholder="e.g. Going on lunch break"
            />
          </label>
          <label className="block">
            <span className="text-xs font-semibold text-surface-600 dark:text-surface-300">Context (optional)</span>
            <textarea
              className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
              rows={3}
              value={context}
              onChange={(e) => setContext(e.target.value)}
              placeholder="Notes the next tech needs to know..."
            />
          </label>
        </div>
        <div className="flex gap-2 mt-5">
          <button
            className="flex-1 px-3 py-2 border rounded text-sm hover:bg-surface-50 dark:hover:bg-surface-800"
            onClick={onClose}
            disabled={handoffMut.isPending}
          >
            Cancel
          </button>
          <button
            className="flex-1 px-3 py-2 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700 inline-flex items-center justify-center disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            disabled={!canSubmit}
            onClick={() => handoffMut.mutate()}
          >
            {handoffMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
            Hand off
          </button>
        </div>
      </div>
    </div>
  );
}
