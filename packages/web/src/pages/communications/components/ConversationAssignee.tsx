import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { UserCheck, UserPlus, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

/**
 * Conversation assignee dropdown — audit §51.1.
 *
 * Shows a small pill ("Unassigned" / "Mike") that opens a popover to pick
 * any active user. Uses PATCH /inbox/conversation/:phone/assign.
 */

interface ConversationAssigneeProps {
  phone: string;
  className?: string;
}

interface UserRow {
  id: number;
  first_name: string | null;
  last_name: string | null;
  username: string;
}

interface AssignmentRow {
  phone: string;
  assigned_user_id: number | null;
  assigned_at: string;
}

async function fetchAssignment(phone: string): Promise<AssignmentRow | null> {
  const res = await api.get<{ success: boolean; data: AssignmentRow[] }>(
    '/inbox/conversations',
  );
  const rows = res.data.data || [];
  return rows.find((r) => r.phone === phone) ?? null;
}

async function fetchUsers(): Promise<UserRow[]> {
  const res = await api.get<{ success: boolean; data: UserRow[] }>('/settings/users');
  return (res.data as any).data ?? [];
}

function userLabel(u: UserRow | undefined): string {
  if (!u) return 'Unknown';
  const name = [u.first_name, u.last_name].filter(Boolean).join(' ').trim();
  return name || u.username;
}

export function ConversationAssignee({ phone, className }: ConversationAssigneeProps) {
  const qc = useQueryClient();
  const [open, setOpen] = useState(false);

  const { data: assignment } = useQuery({
    queryKey: ['inbox-assignment', phone],
    queryFn: () => fetchAssignment(phone),
    enabled: !!phone,
  });

  const { data: users } = useQuery({
    queryKey: ['inbox-users-for-assign'],
    queryFn: fetchUsers,
    enabled: open,
  });

  const assignMut = useMutation({
    mutationFn: (userId: number | null) =>
      api.patch(`/inbox/conversation/${encodeURIComponent(phone)}/assign`, { user_id: userId }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['inbox-assignment', phone] });
      qc.invalidateQueries({ queryKey: ['inbox-conversations'] });
      setOpen(false);
      toast.success('Conversation assigned');
    },
    onError: () => toast.error('Failed to assign'),
  });

  const assignedUser = users?.find((u) => u.id === assignment?.assigned_user_id);
  const label = assignment?.assigned_user_id ? userLabel(assignedUser) : 'Unassigned';
  const isAssigned = assignment?.assigned_user_id != null;

  return (
    <div className={cn('relative inline-block', className)}>
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        className={cn(
          'inline-flex items-center gap-1 rounded-full border px-2 py-0.5 text-[11px] font-medium',
          isAssigned
            ? 'border-primary-300 bg-primary-50 text-primary-700 dark:border-primary-700 dark:bg-primary-900/30 dark:text-primary-300'
            : 'border-surface-300 bg-surface-50 text-surface-600 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-400',
        )}
      >
        {isAssigned ? <UserCheck className="h-3 w-3" /> : <UserPlus className="h-3 w-3" />}
        {label}
      </button>
      {open && (
        <>
          <div className="fixed inset-0 z-30" onClick={() => setOpen(false)} />
          <div className="absolute right-0 z-40 mt-1 w-52 rounded-lg border border-surface-200 bg-white shadow-lg dark:border-surface-700 dark:bg-surface-800">
            <div className="flex items-center justify-between border-b border-surface-100 px-3 py-1.5 text-xs font-medium text-surface-500 dark:border-surface-700">
              Assign to
              <button
                onClick={() => setOpen(false)}
                className="rounded p-0.5 hover:bg-surface-100 dark:hover:bg-surface-700"
              >
                <X className="h-3 w-3" />
              </button>
            </div>
            <button
              onClick={() => assignMut.mutate(null)}
              disabled={assignMut.isPending}
              className="block w-full px-3 py-1.5 text-left text-xs text-surface-600 hover:bg-surface-50 dark:text-surface-400 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              Unassigned
            </button>
            {(users ?? []).map((u) => (
              <button
                key={u.id}
                onClick={() => assignMut.mutate(u.id)}
                disabled={assignMut.isPending}
                className={cn(
                  'block w-full px-3 py-1.5 text-left text-xs hover:bg-surface-50 dark:hover:bg-surface-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
                  assignment?.assigned_user_id === u.id
                    ? 'font-medium text-primary-600 dark:text-primary-400'
                    : 'text-surface-700 dark:text-surface-300',
                )}
              >
                {userLabel(u)}
              </button>
            ))}
            {(!users || users.length === 0) && (
              <div className="px-3 py-2 text-xs text-surface-400">Loading users…</div>
            )}
          </div>
        </>
      )}
    </div>
  );
}
