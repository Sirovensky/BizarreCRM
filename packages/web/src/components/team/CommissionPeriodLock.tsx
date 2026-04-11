/**
 * Commission period lock — criticalaudit.md §53 idea #7.
 *
 * Compact card that lists payroll periods with a Lock button. Once locked,
 * the row shows a lock icon and the locked-by user. The server-side check
 * (isCommissionLocked) refuses any subsequent commission edits in the locked
 * range — so this UI is a one-way switch on purpose.
 *
 * Drop-in for the payroll page or settings; also re-used by GoalsPage in a
 * follow-up if needed.
 */
import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Lock, LockOpen, Plus, Loader2, Download } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';

interface PayrollPeriod {
  id: number;
  name: string;
  start_date: string;
  end_date: string;
  locked_at: string | null;
  locked_by_user_id: number | null;
  notes: string | null;
}

export function CommissionPeriodLock() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [newName, setNewName] = useState('');
  const [newStart, setNewStart] = useState('');
  const [newEnd, setNewEnd] = useState('');

  const { data } = useQuery({
    queryKey: ['team', 'payroll', 'periods'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: PayrollPeriod[] }>(
        '/team/payroll/periods',
      );
      return res.data.data;
    },
  });
  const periods: PayrollPeriod[] = data || [];

  const createMut = useMutation({
    mutationFn: async () => {
      await api.post('/team/payroll/periods', {
        name: newName,
        start_date: newStart,
        end_date: newEnd,
      });
    },
    onSuccess: () => {
      toast.success('Period created');
      queryClient.invalidateQueries({ queryKey: ['team', 'payroll', 'periods'] });
      setShowNew(false);
      setNewName('');
      setNewStart('');
      setNewEnd('');
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to create period'),
  });

  const lockMut = useMutation({
    mutationFn: async (id: number) => {
      await api.post(`/team/payroll/lock/${id}`);
    },
    onSuccess: () => {
      toast.success('Period locked');
      queryClient.invalidateQueries({ queryKey: ['team', 'payroll', 'periods'] });
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Lock failed'),
  });

  function downloadCsv(periodId: number) {
    // Open in a new tab — the server returns text/csv with Content-Disposition.
    const url = `/api/v1/team/payroll/export.csv?period=${periodId}`;
    window.open(url, '_blank');
  }

  return (
    <div className="bg-white rounded-lg shadow border p-4">
      <div className="flex items-center justify-between mb-3">
        <h2 className="text-sm font-bold text-gray-800">Payroll periods</h2>
        <button
          className="px-2 py-1 bg-gray-100 hover:bg-gray-200 rounded text-xs inline-flex items-center"
          onClick={() => setShowNew(true)}
        >
          <Plus className="w-3 h-3 mr-1" /> New period
        </button>
      </div>
      {periods.length === 0 && (
        <p className="text-xs text-gray-500 py-4 text-center">No payroll periods yet.</p>
      )}
      <div className="space-y-2">
        {periods.map((p) => (
          <div
            key={p.id}
            className={`border rounded p-2 text-xs ${p.locked_at ? 'bg-gray-50' : ''}`}
          >
            <div className="flex items-center justify-between">
              <div>
                <div className="font-semibold text-gray-800">{p.name}</div>
                <div className="text-gray-500">{p.start_date} → {p.end_date}</div>
              </div>
              <div className="flex items-center gap-2">
                <button
                  className="p-1 text-gray-600 hover:text-blue-600"
                  title="Download CSV"
                  onClick={() => downloadCsv(p.id)}
                >
                  <Download className="w-4 h-4" />
                </button>
                {p.locked_at ? (
                  <span className="inline-flex items-center text-gray-500" title="Locked">
                    <Lock className="w-4 h-4" />
                  </span>
                ) : (
                  <button
                    className="px-2 py-1 bg-amber-600 text-white rounded text-xs inline-flex items-center hover:bg-amber-700"
                    disabled={lockMut.isPending}
                    onClick={() => lockMut.mutate(p.id)}
                  >
                    {lockMut.isPending ? (
                      <Loader2 className="w-3 h-3 animate-spin mr-1" />
                    ) : (
                      <LockOpen className="w-3 h-3 mr-1" />
                    )}
                    Lock
                  </button>
                )}
              </div>
            </div>
          </div>
        ))}
      </div>

      {showNew && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-white rounded-lg shadow-xl max-w-md w-full p-5">
            <h2 className="text-lg font-bold mb-4">New payroll period</h2>
            <div className="space-y-3">
              <label className="block">
                <span className="text-xs font-semibold text-gray-600">Name</span>
                <input
                  type="text"
                  className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder="e.g. 2026-W14"
                />
              </label>
              <div className="grid grid-cols-2 gap-2">
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">Start</span>
                  <input
                    type="date"
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newStart}
                    onChange={(e) => setNewStart(e.target.value)}
                  />
                </label>
                <label className="block">
                  <span className="text-xs font-semibold text-gray-600">End</span>
                  <input
                    type="date"
                    className="mt-1 w-full border rounded px-2 py-1.5 text-sm"
                    value={newEnd}
                    onChange={(e) => setNewEnd(e.target.value)}
                  />
                </label>
              </div>
            </div>
            <div className="flex gap-2 mt-5">
              <button
                className="flex-1 px-3 py-2 border rounded text-sm hover:bg-gray-50"
                onClick={() => setShowNew(false)}
              >
                Cancel
              </button>
              <button
                className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700 inline-flex items-center justify-center"
                disabled={!newName || !newStart || !newEnd || createMut.isPending}
                onClick={() => createMut.mutate()}
              >
                {createMut.isPending && <Loader2 className="w-4 h-4 animate-spin mr-1" />}
                Save
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
