/**
 * Custom roles + permission matrix — criticalaudit.md §53 idea #12.
 *
 * Replaces the "coming soon" placeholder. Lists every role on the left, every
 * permission key on the right; toggling a checkbox PUTs to /roles/:id/permissions
 * with a single update payload (no batch save needed).
 *
 * Built-in roles (admin/manager/technician/cashier) are read-only on the
 * `name` field but their permission matrix is editable. The 'admin.full' bit
 * on the admin role is server-side guarded so you can't lock yourself out.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Shield, Loader2, Plus, Save } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface Role {
  id: number;
  name: string;
  description: string | null;
  is_active: number;
}

interface MatrixEntry {
  key: string;
  allowed: boolean;
}

interface RoleMatrixResponse {
  role: Role;
  matrix: MatrixEntry[];
}

const BUILTIN = ['admin', 'manager', 'technician', 'cashier'];

export function RolesMatrixPage() {
  const queryClient = useQueryClient();
  const [selectedRoleId, setSelectedRoleId] = useState<number | null>(null);
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newDescription, setNewDescription] = useState('');

  const { data: rolesData } = useQuery({
    queryKey: ['roles'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: Role[] }>('/roles');
      const list = res.data.data;
      if (list.length && selectedRoleId === null) setSelectedRoleId(list[0].id);
      return list;
    },
  });
  const roles: Role[] = rolesData || [];

  const { data: matrixData, isLoading: matrixLoading } = useQuery({
    queryKey: ['roles', selectedRoleId, 'permissions'],
    enabled: !!selectedRoleId,
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: RoleMatrixResponse }>(
        `/roles/${selectedRoleId}/permissions`,
      );
      return res.data.data;
    },
  });

  const updateMut = useMutation({
    mutationFn: async ({ key, allowed }: { key: string; allowed: boolean }) => {
      await api.put(`/roles/${selectedRoleId}/permissions`, {
        updates: [{ key, allowed }],
      });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['roles', selectedRoleId, 'permissions'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Update failed'),
  });

  const createMut = useMutation({
    mutationFn: async () => {
      const res = await api.post('/roles', { name: newName, description: newDescription || null });
      return res.data.data;
    },
    onSuccess: (created: Role) => {
      toast.success('Role created');
      queryClient.invalidateQueries({ queryKey: ['roles'] });
      setShowNew(false);
      setNewName('');
      setNewDescription('');
      if (created?.id) setSelectedRoleId(created.id);
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to create role'),
  });

  const matrix = matrixData?.matrix || [];

  // Group permission keys by their prefix (before the first dot) for readability.
  const grouped: Record<string, MatrixEntry[]> = {};
  for (const m of matrix) {
    const group = m.key.split('.')[0];
    if (!grouped[group]) grouped[group] = [];
    grouped[group].push(m);
  }

  return (
    <div className="p-6 max-w-6xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-800 inline-flex items-center">
            <Shield className="w-6 h-6 mr-2 text-purple-500" /> Roles & Permissions
          </h1>
          <p className="text-sm text-gray-500">Toggle which features each role can access.</p>
        </div>
        <button
          className="px-3 py-1.5 bg-purple-600 text-white rounded text-sm hover:bg-purple-700 inline-flex items-center"
          onClick={() => setShowNew(true)}
        >
          <Plus className="w-4 h-4 mr-1" /> New role
        </button>
      </header>

      <div className="grid grid-cols-1 lg:grid-cols-[240px_1fr] gap-4">
        <aside className="bg-white rounded-lg shadow border p-2">
          {roles.map((r) => (
            <button
              key={r.id}
              className={`w-full text-left px-3 py-2 rounded text-sm ${
                selectedRoleId === r.id ? 'bg-purple-100 text-purple-800 font-semibold' : 'hover:bg-gray-50'
              }`}
              onClick={() => setSelectedRoleId(r.id)}
            >
              <div className="capitalize">{r.name}</div>
              {r.description && (
                <div className="text-xs text-gray-500 line-clamp-1">{r.description}</div>
              )}
              {BUILTIN.includes(r.name) && (
                <span className="text-xs text-gray-400">built-in</span>
              )}
            </button>
          ))}
        </aside>

        <section className="bg-white rounded-lg shadow border p-4">
          {!selectedRoleId && <p className="text-gray-500">Pick a role to edit.</p>}
          {matrixLoading && (
            <div className="flex items-center justify-center py-12 text-gray-500">
              <Loader2 className="w-5 h-5 animate-spin mr-2" /> Loading...
            </div>
          )}
          {!matrixLoading && matrix.length > 0 && (
            <div className="space-y-5">
              {Object.entries(grouped).map(([group, entries]) => (
                <div key={group}>
                  <h3 className="text-xs font-bold uppercase text-gray-500 mb-2 border-b pb-1">{group}</h3>
                  <div className="grid grid-cols-1 sm:grid-cols-2 gap-y-1">
                    {entries.map((m) => (
                      <label
                        key={m.key}
                        className="flex items-center text-sm py-1 cursor-pointer hover:bg-gray-50 px-2 rounded"
                      >
                        <input
                          type="checkbox"
                          className="mr-2 h-4 w-4"
                          checked={m.allowed}
                          disabled={updateMut.isPending}
                          onChange={(e) =>
                            updateMut.mutate({ key: m.key, allowed: e.target.checked })
                          }
                        />
                        <span className="font-mono text-xs">{m.key}</span>
                      </label>
                    ))}
                  </div>
                </div>
              ))}
            </div>
          )}
        </section>
      </div>

      {showNew && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5">
            <h2 className="text-lg font-bold mb-4">New role</h2>
            <label className="block mb-3">
              <span className="text-xs font-semibold text-gray-600">Name</span>
              <input
                type="text"
                className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                value={newName}
                onChange={(e) => setNewName(e.target.value.toLowerCase().replace(/\s+/g, '_'))}
                placeholder="e.g. parts_clerk"
              />
            </label>
            <label className="block mb-3">
              <span className="text-xs font-semibold text-gray-600">Description (optional)</span>
              <input
                type="text"
                className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                value={newDescription}
                onChange={(e) => setNewDescription(e.target.value)}
              />
            </label>
            <div className="flex gap-2">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-purple-600 text-white rounded text-sm hover:bg-purple-700 inline-flex items-center justify-center"
                disabled={!newName || createMut.isPending}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending ? <Loader2 className="w-4 h-4 animate-spin mr-1" /> : <Save className="w-4 h-4 mr-1" />}
                Create
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
