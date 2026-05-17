/**
 * WEB-UIUX-1080: admin CRUD for QC sign-off checklist items.
 *
 * QcSignOffModal empty-state copy points operators here ("Ask an admin to
 * add some under Settings → Bench / QC."). Before this page existed, that
 * pointer dead-ended. Now admin can add/edit/delete checklist items + flip
 * is_active without touching the DB.
 */
import { useEffect, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ClipboardCheck, Plus, Loader2, AlertTriangle, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { benchApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';

interface ChecklistItem {
  id: number;
  name: string;
  sort_order: number;
  is_active: number;
  device_category: string | null;
}

interface ChecklistResponse {
  success: boolean;
  data: ChecklistItem[];
}

export function QcChecklistPage() {
  const queryClient = useQueryClient();
  const [showAddModal, setShowAddModal] = useState(false);
  const [editing, setEditing] = useState<ChecklistItem | null>(null);

  const { data, isLoading, isError, refetch } = useQuery({
    queryKey: ['bench', 'qc-checklist'],
    queryFn: async () => {
      const res = await benchApi.qc.checklist();
      return (res.data as ChecklistResponse).data;
    },
  });

  const createMut = useMutation({
    mutationFn: (vars: { name: string; sort_order: number; device_category: string | null }) =>
      benchApi.qc.createChecklistItem(vars),
    onSuccess: () => {
      toast.success('Checklist item added');
      queryClient.invalidateQueries({ queryKey: ['bench', 'qc-checklist'] });
      setShowAddModal(false);
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not add item'),
  });

  const updateMut = useMutation({
    mutationFn: (vars: { id: number; data: Record<string, unknown> }) =>
      benchApi.qc.updateChecklistItem(vars.id, vars.data),
    onSuccess: () => {
      toast.success('Checklist item updated');
      queryClient.invalidateQueries({ queryKey: ['bench', 'qc-checklist'] });
      setEditing(null);
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not update item'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => benchApi.qc.deleteChecklistItem(id),
    onSuccess: () => {
      toast.success('Checklist item removed');
      queryClient.invalidateQueries({ queryKey: ['bench', 'qc-checklist'] });
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Could not delete item'),
  });

  return (
    <div className="p-6">
      <div className="mb-6 flex items-center justify-between gap-4">
        <div>
          <h1 className="flex items-center gap-2 text-2xl font-bold text-surface-900 dark:text-surface-100">
            <ClipboardCheck className="h-6 w-6 text-primary-500" /> QC sign-off checklist
          </h1>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
            Items techs tick off before signing a repair. Inactive items stay on historical sign-offs but don't appear on new ones.
          </p>
        </div>
        <button
          type="button"
          onClick={() => setShowAddModal(true)}
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-on-primary hover:bg-primary-700"
        >
          <Plus className="h-4 w-4" /> Add item
        </button>
      </div>

      {isLoading && (
        <div className="flex items-center gap-2 text-sm text-surface-500 dark:text-surface-400">
          <Loader2 className="h-4 w-4 animate-spin" /> Loading checklist…
        </div>
      )}
      {isError && (
        <div className="flex items-center gap-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300">
          <AlertTriangle className="h-4 w-4" />
          Failed to load checklist.
          <button onClick={() => refetch()} className="ml-2 underline">Retry</button>
        </div>
      )}

      {!isLoading && !isError && (data?.length ?? 0) === 0 && (
        <div className="rounded-xl border border-surface-200 bg-white p-8 text-center text-sm text-surface-400 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-500">
          No checklist items yet — click "Add item" to seed the first.
        </div>
      )}

      {(data?.length ?? 0) > 0 && (
        <div className="overflow-hidden rounded-xl border border-surface-200 bg-white dark:border-surface-700 dark:bg-surface-800">
          <table className="min-w-full text-sm">
            <thead className="border-b border-surface-200 bg-surface-50 text-xs uppercase tracking-wide text-surface-500 dark:border-surface-700 dark:bg-surface-900/40 dark:text-surface-400">
              <tr>
                <th className="px-4 py-2 text-left">Sort</th>
                <th className="px-4 py-2 text-left">Name</th>
                <th className="px-4 py-2 text-left">Device category</th>
                <th className="px-4 py-2 text-left">Active</th>
                <th className="px-4 py-2 text-right">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
              {(data ?? [])
                .slice()
                .sort((a, b) => a.sort_order - b.sort_order || a.id - b.id)
                .map((item) => (
                  <tr key={item.id} className="hover:bg-surface-50 dark:hover:bg-surface-700/40">
                    <td className="px-4 py-2 font-mono">{item.sort_order}</td>
                    <td className="px-4 py-2 text-surface-900 dark:text-surface-100">{item.name}</td>
                    <td className="px-4 py-2 text-surface-500 dark:text-surface-400">{item.device_category ?? <span className="italic">all</span>}</td>
                    <td className="px-4 py-2">
                      <button
                        type="button"
                        onClick={() => updateMut.mutate({ id: item.id, data: { is_active: item.is_active ? false : true } })}
                        className={`rounded-full px-2 py-0.5 text-xs font-medium ${item.is_active
                          ? 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300'
                          : 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400'}`}
                      >
                        {item.is_active ? 'Active' : 'Inactive'}
                      </button>
                    </td>
                    <td className="px-4 py-2 text-right">
                      <button
                        type="button"
                        onClick={() => setEditing(item)}
                        className="mr-2 rounded-md border border-surface-200 px-2 py-1 text-xs font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700"
                      >
                        Edit
                      </button>
                      <button
                        type="button"
                        onClick={async () => {
                          const ok = await confirm(
                            `Delete "${item.name}"? Historical sign-offs keep the row reference.`,
                            { title: 'Delete checklist item', confirmLabel: 'Delete', danger: true },
                          );
                          if (ok) deleteMut.mutate(item.id);
                        }}
                        className="rounded-md border border-red-200 px-2 py-1 text-xs font-medium text-red-700 hover:bg-red-50 dark:border-red-800 dark:text-red-300 dark:hover:bg-red-900/20"
                      >
                        Delete
                      </button>
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      )}

      {showAddModal && (
        <ChecklistItemModal
          onClose={() => setShowAddModal(false)}
          onSubmit={(vals) => createMut.mutate(vals)}
          pending={createMut.isPending}
          initial={null}
        />
      )}
      {editing && (
        <ChecklistItemModal
          onClose={() => setEditing(null)}
          onSubmit={(vals) =>
            updateMut.mutate({
              id: editing.id,
              data: {
                name: vals.name,
                sort_order: vals.sort_order,
                device_category: vals.device_category,
              },
            })
          }
          pending={updateMut.isPending}
          initial={editing}
        />
      )}
    </div>
  );
}

interface ChecklistItemModalProps {
  onClose: () => void;
  onSubmit: (vals: { name: string; sort_order: number; device_category: string | null }) => void;
  pending: boolean;
  initial: ChecklistItem | null;
}

function ChecklistItemModal({ onClose, onSubmit, pending, initial }: ChecklistItemModalProps) {
  const [name, setName] = useState(initial?.name ?? '');
  const [sortOrder, setSortOrder] = useState(String(initial?.sort_order ?? 0));
  const [category, setCategory] = useState(initial?.device_category ?? '');

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 backdrop-blur-sm p-4"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-2xl shadow-2xl w-full max-w-md p-6 space-y-4">
        <div className="flex items-center justify-between">
          <h2 className="text-lg font-bold text-surface-900 dark:text-surface-100">
            {initial ? 'Edit checklist item' : 'Add checklist item'}
          </h2>
          <button aria-label="Close" onClick={onClose} className="rounded p-1 text-surface-400 hover:text-surface-600">
            <X className="h-4 w-4" />
          </button>
        </div>
        <div>
          <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Name</label>
          <input value={name} onChange={(e) => setName(e.target.value)} className="input w-full" placeholder="e.g. Buttons (power / volume / home) work" autoFocus />
        </div>
        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Sort order</label>
            <input type="number" min="0" value={sortOrder} onChange={(e) => setSortOrder(e.target.value)} className="input w-full" />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Device category</label>
            <input value={category} onChange={(e) => setCategory(e.target.value)} className="input w-full" placeholder="(blank = all)" />
          </div>
        </div>
        <div className="flex gap-3">
          <button onClick={onClose} className="flex-1 rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800">
            Cancel
          </button>
          <button
            onClick={() => {
              const trimmedName = name.trim();
              if (!trimmedName) {
                toast.error('Name required');
                return;
              }
              const order = Math.max(0, parseInt(sortOrder, 10) || 0);
              onSubmit({
                name: trimmedName,
                sort_order: order,
                device_category: category.trim() || null,
              });
            }}
            disabled={pending}
            className="flex-1 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-on-primary hover:bg-primary-700 disabled:opacity-50"
          >
            {pending ? 'Saving…' : initial ? 'Save changes' : 'Add item'}
          </button>
        </div>
      </div>
    </div>
  );
}
