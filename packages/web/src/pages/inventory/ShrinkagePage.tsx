/**
 * Shrinkage tracking — explicit "stock disappeared" log with reason + photo.
 *
 * Cross-ref: criticalaudit.md §48 idea #10.
 */
import { useState, useRef } from 'react';
import { Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ChevronLeft, AlertTriangle, Plus, Loader2, Camera } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { cn } from '@/utils/cn';

interface ShrinkageRow {
  id: number;
  inventory_item_id: number;
  quantity: number;
  reason: 'damaged' | 'stolen' | 'lost' | 'expired' | 'other';
  photo_path: string | null;
  reported_at: string;
  notes: string | null;
  name: string;
  sku: string | null;
}

const REASON_COLORS = {
  damaged: 'bg-amber-100 text-amber-700',
  stolen: 'bg-red-100 text-red-700',
  lost: 'bg-surface-200 text-surface-700',
  expired: 'bg-purple-100 text-purple-700',
  other: 'bg-blue-100 text-blue-700',
};

export function ShrinkagePage() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [itemId, setItemId] = useState('');
  const [quantity, setQuantity] = useState('');
  const [reason, setReason] = useState<ShrinkageRow['reason']>('damaged');
  const [notes, setNotes] = useState('');
  const photoRef = useRef<HTMLInputElement>(null);

  const { data: shrinkageData } = useQuery({
    queryKey: ['shrinkage'],
    queryFn: async () => {
      const res = await api.get<{ success: boolean; data: ShrinkageRow[] }>(
        '/inventory-enrich/shrinkage',
      );
      return res.data.data;
    },
  });
  const rows: ShrinkageRow[] = shrinkageData || [];

  const recordMut = useMutation({
    mutationFn: async () => {
      const fd = new FormData();
      fd.append('quantity', quantity);
      fd.append('reason', reason);
      if (notes) fd.append('notes', notes);
      if (photoRef.current?.files?.[0]) fd.append('photo', photoRef.current.files[0]);
      const res = await api.post(`/inventory-enrich/${itemId}/shrinkage`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Shrinkage recorded');
      queryClient.invalidateQueries({ queryKey: ['shrinkage'] });
      setShowNew(false);
      setItemId('');
      setQuantity('');
      setReason('damaged');
      setNotes('');
      if (photoRef.current) photoRef.current.value = '';
    },
    onError: (e: any) => toast.error(e?.response?.data?.message || 'Failed to record'),
  });

  const total = rows.reduce((s, r) => s + r.quantity, 0);

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between">
        <div>
          <Link to="/inventory" className="text-sm text-primary-600 hover:underline inline-flex items-center gap-1">
            <ChevronLeft className="h-4 w-4" /> Back to Inventory
          </Link>
          <h1 className="text-2xl font-bold mt-2 flex items-center gap-2">
            <AlertTriangle className="h-6 w-6 text-amber-500" /> Shrinkage Log
          </h1>
          <p className="text-sm text-surface-500">
            Record damaged / stolen / lost / expired stock — {rows.length} events ({total} units)
          </p>
        </div>
        <button
          onClick={() => setShowNew(!showNew)}
          className="inline-flex items-center gap-2 rounded-lg bg-amber-600 px-4 py-2 text-sm font-semibold text-white hover:bg-amber-700"
        >
          <Plus className="h-4 w-4" /> Record Shrinkage
        </button>
      </div>

      {showNew && (
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 space-y-3">
          <h3 className="font-semibold">Record new shrinkage event</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <input
              value={itemId}
              onChange={(e) => setItemId(e.target.value)}
              placeholder="Inventory item ID"
              type="number"
              className="rounded-md border border-surface-300 px-3 py-2 text-sm"
            />
            <input
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              placeholder="Quantity lost"
              type="number"
              min="1"
              className="rounded-md border border-surface-300 px-3 py-2 text-sm"
            />
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as ShrinkageRow['reason'])}
              className="rounded-md border border-surface-300 px-3 py-2 text-sm"
            >
              <option value="damaged">Damaged</option>
              <option value="stolen">Stolen</option>
              <option value="lost">Lost</option>
              <option value="expired">Expired</option>
              <option value="other">Other</option>
            </select>
          </div>
          <textarea
            value={notes}
            onChange={(e) => setNotes(e.target.value)}
            placeholder="Notes (optional)"
            className="w-full rounded-md border border-surface-300 px-3 py-2 text-sm"
            rows={2}
          />
          <div className="flex items-center gap-2">
            <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
              <Camera className="h-4 w-4" />
              <span>Attach photo</span>
              <input ref={photoRef} type="file" accept="image/*" className="hidden" />
            </label>
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => recordMut.mutate()}
              disabled={!itemId || !quantity || recordMut.isPending}
              className="rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50"
            >
              {recordMut.isPending && <Loader2 className="inline h-4 w-4 animate-spin mr-1" />}
              Record
            </button>
            <button
              onClick={() => setShowNew(false)}
              className="rounded-md border border-surface-300 px-4 py-2 text-sm"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-hidden">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200">
            <tr>
              <th className="text-left px-3 py-2">When</th>
              <th className="text-left px-3 py-2">Item</th>
              <th className="text-right px-3 py-2">Qty</th>
              <th className="text-left px-3 py-2">Reason</th>
              <th className="text-left px-3 py-2">Notes</th>
              <th className="text-center px-3 py-2">Photo</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="text-center py-8 text-surface-400">
                  No shrinkage recorded yet
                </td>
              </tr>
            )}
            {rows.map((r) => (
              <tr key={r.id} className="border-b border-surface-100 last:border-0">
                <td className="px-3 py-2 text-xs text-surface-500">
                  {new Date(r.reported_at).toLocaleString()}
                </td>
                <td className="px-3 py-2">
                  <div className="font-medium">{r.name}</div>
                  <div className="text-xs text-surface-500">{r.sku}</div>
                </td>
                <td className="text-right px-3 py-2 font-semibold">{r.quantity}</td>
                <td className="px-3 py-2">
                  <span
                    className={cn(
                      'px-2 py-0.5 rounded-full text-xs font-medium',
                      REASON_COLORS[r.reason],
                    )}
                  >
                    {r.reason}
                  </span>
                </td>
                <td className="px-3 py-2 text-xs max-w-xs truncate">{r.notes || '—'}</td>
                <td className="text-center px-3 py-2">
                  {r.photo_path ? (
                    <a href={r.photo_path} target="_blank" rel="noreferrer" className="text-primary-600 text-xs">
                      View
                    </a>
                  ) : (
                    '—'
                  )}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}
