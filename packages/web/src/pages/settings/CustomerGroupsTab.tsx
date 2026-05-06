import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertCircle, Check, Loader2, Pencil, Plus, Trash2, X } from 'lucide-react';
import toast from 'react-hot-toast';

import { settingsApi } from '@/api/endpoints';
import { SkeletonCard } from '@/components/shared/Skeleton';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';

interface CustomerGroupRecord {
  id: number;
  name: string;
  discount_pct: number;
  discount_type: string;
  auto_apply: number;
  description: string | null;
}

function LoadingState() {
  return (
    <div role="status" aria-label="Loading settings" aria-busy="true" className="space-y-3 py-6">
      <SkeletonCard />
      <SkeletonCard />
    </div>
  );
}

function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
      <p className="text-sm text-surface-500">{message}</p>
    </div>
  );
}

function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-12">
      <p className="text-sm text-surface-400 dark:text-surface-500">{message}</p>
    </div>
  );
}

export function CustomerGroupsTab() {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<Partial<CustomerGroupRecord>>({});
  const [showAdd, setShowAdd] = useState(false);
  const [addForm, setAddForm] = useState({ name: '', discount_pct: 0, discount_type: 'percentage', auto_apply: 1, description: '' });

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'customer-groups'],
    queryFn: async () => {
      const res = await settingsApi.getCustomerGroups();
      return (res.data.data || []) as CustomerGroupRecord[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (d: any) => settingsApi.createCustomerGroup(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      setShowAdd(false);
      setAddForm({ name: '', discount_pct: 0, discount_type: 'percentage', auto_apply: 1, description: '' });
      toast.success('Customer group created');
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: any }) => settingsApi.updateCustomerGroup(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      setEditing(null);
      toast.success('Customer group updated');
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteCustomerGroup(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'customer-groups'] });
      toast.success('Customer group deleted');
    },
    onError: (err: unknown) => toast.error(formatApiError(err)),
  });

  function startEdit(group: CustomerGroupRecord) {
    setEditing(group.id);
    setEditForm({
      name: group.name,
      discount_pct: group.discount_pct,
      discount_type: group.discount_type,
      auto_apply: group.auto_apply,
      description: group.description,
    });
  }

  if (isLoading) return <LoadingState />;
  if (isError) return <ErrorState message="Failed to load customer groups" />;

  const groups = data || [];

  return (
    <div className="space-y-4">
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <div>
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Customer Groups</h3>
            <p className="text-xs text-surface-400 mt-0.5">Define discount tiers that auto-apply when selecting a group member</p>
          </div>
          <button
            onClick={() => setShowAdd(!showAdd)}
            className="btn btn-primary btn-md bg-blue-600 text-white hover:bg-blue-700"
          >
            <Plus className="h-4 w-4" /> Add Group
          </button>
        </div>

        {showAdd && (
          <div className="p-4 border-b border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/30">
            <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-3">
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Group Name</label>
                <input
                  type="text"
                  value={addForm.name}
                  onChange={(e) => setAddForm({ ...addForm, name: e.target.value })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus:ring-2 focus:ring-blue-500 w-full"
                  placeholder="e.g. VIP, Wholesale, Employee"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Discount</label>
                <div className="flex gap-2">
                  <input
                    type="number"
                    min="0"
                    step="0.01"
                    value={addForm.discount_pct || ''}
                    onChange={(e) => setAddForm({ ...addForm, discount_pct: parseFloat(e.target.value) || 0 })}
                    className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-24 focus-visible:outline-none focus:ring-2 focus:ring-blue-500"
                    placeholder="0"
                  />
                  <select
                    value={addForm.discount_type}
                    onChange={(e) => setAddForm({ ...addForm, discount_type: e.target.value })}
                    className="px-2 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="percentage">%</option>
                    <option value="fixed">$ Fixed</option>
                  </select>
                </div>
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-500 mb-1">Description</label>
                <input
                  type="text"
                  value={addForm.description}
                  onChange={(e) => setAddForm({ ...addForm, description: e.target.value })}
                  className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus:ring-2 focus:ring-blue-500 w-full"
                  placeholder="Optional description"
                />
              </div>
            </div>
            <div className="flex items-center gap-4 mt-3">
              <label className="flex items-center gap-1.5 text-sm text-surface-600 dark:text-surface-400">
                <input type="checkbox" checked={!!addForm.auto_apply} onChange={(e) => setAddForm({ ...addForm, auto_apply: e.target.checked ? 1 : 0 })} className="rounded" />
                Auto-apply on checkout
              </label>
              <button
                onClick={() => {
                  if (!addForm.name.trim()) return toast.error('Group name is required');
                  createMutation.mutate(addForm);
                }}
                disabled={createMutation.isPending}
                className="btn btn-primary btn-sm bg-blue-600 text-white hover:bg-blue-700"
              >
                {createMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Check className="h-4 w-4" />}
                Create
              </button>
              <button onClick={() => setShowAdd(false)} className="btn btn-ghost btn-sm text-surface-400 hover:text-surface-600">Cancel</button>
            </div>
          </div>
        )}

        {groups.length === 0 ? (
          <EmptyState message="No customer groups defined yet" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800 text-left text-xs font-medium text-surface-500 uppercase tracking-wider">
                  <th className="px-4 py-3">Name</th>
                  <th className="px-4 py-3">Discount</th>
                  <th className="px-4 py-3">Auto-Apply</th>
                  <th className="px-4 py-3">Description</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-surface-100 dark:divide-surface-800">
                {groups.map((group) => (
                  <tr key={group.id} className="hover:bg-surface-50 dark:hover:bg-surface-800/50 transition-colors">
                    {editing === group.id ? (
                      <>
                        <td className="px-4 py-2">
                          <input
                            type="text"
                            value={editForm.name || ''}
                            onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-32 focus-visible:outline-none focus:ring-1 focus:ring-blue-500"
                          />
                        </td>
                        <td className="px-4 py-2">
                          <div className="flex items-center gap-1">
                            <input
                              type="number"
                              min="0"
                              step="0.01"
                              value={editForm.discount_pct || ''}
                              onChange={(e) => setEditForm({ ...editForm, discount_pct: parseFloat(e.target.value) || 0 })}
                              className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-20 focus-visible:outline-none focus:ring-1 focus:ring-blue-500"
                            />
                            <select
                              value={editForm.discount_type || 'percentage'}
                              onChange={(e) => setEditForm({ ...editForm, discount_type: e.target.value })}
                              className="px-1 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus:ring-1 focus:ring-blue-500"
                            >
                              <option value="percentage">%</option>
                              <option value="fixed">$</option>
                            </select>
                          </div>
                        </td>
                        <td className="px-4 py-2">
                          <input
                            type="checkbox"
                            checked={!!editForm.auto_apply}
                            onChange={(e) => setEditForm({ ...editForm, auto_apply: e.target.checked ? 1 : 0 })}
                            className="rounded"
                          />
                        </td>
                        <td className="px-4 py-2">
                          <input
                            type="text"
                            value={editForm.description || ''}
                            onChange={(e) => setEditForm({ ...editForm, description: e.target.value })}
                            className="px-2 py-1 text-sm border border-surface-200 dark:border-surface-700 rounded bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 w-full focus-visible:outline-none focus:ring-1 focus:ring-blue-500"
                          />
                        </td>
                        <td className="px-4 py-2 text-right">
                          <div className="flex items-center justify-end gap-1">
                            <button
                              onClick={() => updateMutation.mutate({ id: group.id, data: editForm })}
                              disabled={updateMutation.isPending}
                              className="btn-icon btn-xs text-green-600 hover:bg-green-50 dark:hover:bg-green-900/20"
                            >
                              <Check className="h-4 w-4" />
                            </button>
                            <button onClick={() => setEditing(null)} className="btn-icon btn-xs text-surface-400 hover:text-surface-600">
                              <X className="h-4 w-4" />
                            </button>
                          </div>
                        </td>
                      </>
                    ) : (
                      <>
                        <td className="px-4 py-3">
                          <span className="font-medium text-surface-900 dark:text-surface-100">{group.name}</span>
                        </td>
                        <td className="px-4 py-3">
                          {group.discount_pct > 0 ? (
                            <span className="inline-flex items-center rounded-full bg-green-100 px-2 py-0.5 text-xs font-semibold text-green-700 dark:bg-green-900/30 dark:text-green-400">
                              {group.discount_type === 'fixed' ? `$${group.discount_pct}` : `${group.discount_pct}%`} off
                            </span>
                          ) : (
                            <span className="text-surface-400 text-xs">None</span>
                          )}
                        </td>
                        <td className="px-4 py-3">
                          <span className={cn(
                            'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                            group.auto_apply
                              ? 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400'
                              : 'bg-surface-100 text-surface-400 dark:bg-surface-800 dark:text-surface-500'
                          )}>
                            {group.auto_apply ? 'Yes' : 'No'}
                          </span>
                        </td>
                        <td className="px-4 py-3 text-surface-500 dark:text-surface-400 text-xs">
                          {group.description || '-'}
                        </td>
                        <td className="px-4 py-3 text-right">
                          <div className="flex items-center justify-end gap-1">
                            <button aria-label="Edit" onClick={() => startEdit(group)} className="btn-icon btn-xs text-surface-400 hover:text-blue-600 hover:bg-blue-50 dark:hover:bg-blue-900/20">
                              <Pencil className="h-3.5 w-3.5" />
                            </button>
                            <button aria-label="Delete" onClick={async () => { if (await confirm(`Delete group "${group.name}"?`, { danger: true })) deleteMutation.mutate(group.id); }} className="btn-icon btn-xs text-surface-400 hover:text-red-600 hover:bg-red-50 dark:hover:bg-red-900/20">
                              <Trash2 className="h-3.5 w-3.5" />
                            </button>
                          </div>
                        </td>
                      </>
                    )}
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  );
}
