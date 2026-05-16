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
import { formatApiError } from '@/utils/apiError';
import { InventoryItemPicker } from '@/components/inventory/InventoryItemPicker';
import { formatDateTime } from '@/utils/format';
import {
  IMAGE_UPLOAD_ACCEPT,
  SMALL_IMAGE_UPLOAD_MAX_BYTES,
  validateImageFile,
} from '@/utils/imageUploadPolicy';

// Returns the given path only if it's safe to render as an `<a href>` target.
// Accepts relative paths starting with `/` (typical uploads location) and
// absolute http/https URLs. Anything else (e.g. `javascript:` / `data:`) is
// stripped out so a poisoned server value can't execute in the user's tab.
function safeHref(raw: string | null | undefined): string | null {
  if (!raw) return null;
  // Fixer-WW (WEB-FB-015): reject protocol-relative `//attacker/foo` first —
  // browsers treat those as absolute cross-origin even though they pass a
  // naive `startsWith('/')` allow-list.
  if (raw.startsWith('//')) return null;
  if (raw.startsWith('/')) return raw;
  try {
    const parsed = new URL(raw);
    if (parsed.protocol === 'http:' || parsed.protocol === 'https:') return parsed.href;
  } catch { /* fall through */ }
  return null;
}

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
  damaged: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
  stolen: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
  lost: 'bg-surface-200 text-surface-700 dark:bg-surface-700 dark:text-surface-300',
  expired: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300',
  other: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-300',
};

export function ShrinkagePage() {
  const queryClient = useQueryClient();
  const [showNew, setShowNew] = useState(false);
  const [itemId, setItemId] = useState<number | null>(null);
  const [quantity, setQuantity] = useState('');
  const [reason, setReason] = useState<ShrinkageRow['reason']>('damaged');
  const [notes, setNotes] = useState('');
  const [photoName, setPhotoName] = useState('');
  const photoRef = useRef<HTMLInputElement>(null);
  // WEB-UIUX-640: inline edit + delete state.
  const [editingId, setEditingId] = useState<number | null>(null);
  const [editForm, setEditForm] = useState<{
    quantity: string;
    reason: ShrinkageRow['reason'];
    notes: string;
  }>({ quantity: '', reason: 'damaged', notes: '' });

  const updateMutation = useMutation({
    mutationFn: async (vars: { id: number; quantity: number; reason: ShrinkageRow['reason']; notes: string }) => {
      const res = await api.patch(`/inventory-enrich/shrinkage/${vars.id}`, {
        quantity: vars.quantity,
        reason: vars.reason,
        notes: vars.notes || null,
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Shrinkage event updated');
      queryClient.invalidateQueries({ queryKey: ['shrinkage'] });
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
      setEditingId(null);
    },
    onError: (e: unknown) => toast.error(formatApiError(e)),
  });
  const deleteMutation = useMutation({
    mutationFn: async (id: number) => {
      const res = await api.delete(`/inventory-enrich/shrinkage/${id}`);
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Shrinkage event deleted; stock restored');
      queryClient.invalidateQueries({ queryKey: ['shrinkage'] });
      queryClient.invalidateQueries({ queryKey: ['inventory'] });
    },
    onError: (e: unknown) => toast.error(formatApiError(e)),
  });

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
      if (photoRef.current?.files?.[0]) {
        const photo = photoRef.current.files[0];
        const error = await validateImageFile(photo, {
          maxBytes: SMALL_IMAGE_UPLOAD_MAX_BYTES,
          label: `"${photo.name}"`,
        });
        if (error) throw new Error(error);
        fd.append('photo', photo);
      }
      if (!itemId) throw new Error('Inventory item is required');
      const res = await api.post(`/inventory-enrich/${itemId}/shrinkage`, fd, {
        headers: { 'Content-Type': 'multipart/form-data' },
      });
      return res.data.data;
    },
    onSuccess: () => {
      toast.success('Shrinkage recorded');
      queryClient.invalidateQueries({ queryKey: ['shrinkage'] });
      setShowNew(false);
      setItemId(null);
      setQuantity('');
      setReason('damaged');
      setNotes('');
      setPhotoName('');
      if (photoRef.current) photoRef.current.value = '';
    },
    // WEB-FL-024 (Fixer-C9 2026-04-25): consolidate hand-rolled
    // `e?.response?.data?.message` chain onto shared formatApiError, which
    // also surfaces ERR_* code + ref id and handles non-axios shapes safely.
    onError: (e: unknown) => toast.error(formatApiError(e)),
  });

  const total = rows.reduce((s, r) => s + r.quantity, 0);
  const clearPhoto = () => {
    setPhotoName('');
    if (photoRef.current) photoRef.current.value = '';
  };

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
        <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 space-y-3 dark:border-amber-900/60 dark:bg-amber-950/30">
          <h3 className="font-semibold text-amber-950 dark:text-amber-100">Record new shrinkage event</h3>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
            <InventoryItemPicker
              value={itemId}
              onChange={(item) => setItemId(item?.id ?? null)}
              label="Inventory item"
              placeholder="Search item..."
              required
            />
            <input
              value={quantity}
              onChange={(e) => setQuantity(e.target.value)}
              placeholder="Quantity lost"
              type="number"
              min="1"
              className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-amber-900/60 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            />
            <select
              value={reason}
              onChange={(e) => setReason(e.target.value as ShrinkageRow['reason'])}
              className="rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 dark:border-amber-900/60 dark:bg-surface-900 dark:text-surface-100"
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
            className="w-full rounded-md border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder:text-surface-400 dark:border-amber-900/60 dark:bg-surface-900 dark:text-surface-100 dark:placeholder:text-surface-500"
            rows={2}
          />
          <div className="flex flex-col gap-2 sm:flex-row sm:items-center">
            <label className="inline-flex h-10 w-fit cursor-pointer items-center gap-2 rounded-md border border-surface-300 bg-white px-3 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 focus-within:ring-2 focus-within:ring-primary-500 focus-within:ring-offset-2 dark:border-amber-900/60 dark:bg-surface-900 dark:text-surface-200 dark:hover:bg-surface-800 dark:focus-within:ring-offset-surface-950">
              <Camera className="h-4 w-4" />
              <span>Attach photo</span>
              <input
                ref={photoRef}
                type="file"
                accept={IMAGE_UPLOAD_ACCEPT}
                className="sr-only"
                aria-describedby="shrinkage-photo-feedback"
                onChange={(e) => setPhotoName(e.target.files?.[0]?.name ?? '')}
              />
            </label>
            <div id="shrinkage-photo-feedback" className="min-w-0 text-sm text-surface-600 dark:text-surface-300">
              {photoName ? (
                <span className="block max-w-xs truncate" title={photoName}>
                  {photoName}
                </span>
              ) : (
                <span className="text-surface-500">No photo selected</span>
              )}
            </div>
            {photoName && (
              <button
                type="button"
                onClick={clearPhoto}
                className="w-fit rounded-md border border-surface-300 px-3 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:border-amber-900/60 dark:text-surface-200 dark:hover:bg-surface-900"
              >
                Clear
              </button>
            )}
          </div>
          <div className="flex gap-2">
            <button
              onClick={() => recordMut.mutate()}
              disabled={!itemId || !quantity || recordMut.isPending}
              className="rounded-md bg-amber-600 px-4 py-2 text-sm font-semibold text-white disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {recordMut.isPending && <Loader2 className="inline h-4 w-4 animate-spin mr-1" />}
              Record
            </button>
            <button
              onClick={() => setShowNew(false)}
              className="rounded-md border border-surface-300 px-4 py-2 text-sm text-surface-700 hover:bg-surface-50 dark:border-amber-900/60 dark:text-surface-200 dark:hover:bg-surface-900"
            >
              Cancel
            </button>
          </div>
        </div>
      )}

      <div className="rounded-lg border border-surface-200 bg-white overflow-x-auto dark:border-surface-700 dark:bg-surface-800">
        <table className="w-full text-sm">
          <thead className="bg-surface-50 border-b border-surface-200 dark:border-surface-700 dark:bg-surface-900">
            <tr>
              <th className="text-left px-3 py-2">When</th>
              <th className="text-left px-3 py-2">Item</th>
              <th className="text-right px-3 py-2">Qty</th>
              <th className="text-left px-3 py-2">Reason</th>
              <th className="text-left px-3 py-2">Notes</th>
              <th className="text-center px-3 py-2">Photo</th>
              <th className="text-right px-3 py-2">Actions</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td colSpan={7} className="text-center py-8 text-surface-400">
                  No shrinkage recorded yet
                </td>
              </tr>
            )}
            {rows.map((r) => {
              const isEditing = editingId === r.id;
              return (
                <tr key={r.id} className="border-b border-surface-100 last:border-0 dark:border-surface-700">
                  <td className="px-3 py-2 text-xs text-surface-500">
                    {formatDateTime(r.reported_at)}
                  </td>
                  <td className="px-3 py-2">
                    <div className="font-medium">{r.name}</div>
                    <div className="text-xs text-surface-500">{r.sku}</div>
                  </td>
                  <td className="text-right px-3 py-2 font-semibold">
                    {isEditing ? (
                      <input
                        type="number"
                        min="1"
                        value={editForm.quantity}
                        onChange={(e) => setEditForm({ ...editForm, quantity: e.target.value })}
                        className="w-20 text-right rounded border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1 text-sm"
                      />
                    ) : (
                      r.quantity
                    )}
                  </td>
                  <td className="px-3 py-2">
                    {isEditing ? (
                      <select
                        value={editForm.reason}
                        onChange={(e) => setEditForm({ ...editForm, reason: e.target.value as ShrinkageRow['reason'] })}
                        className="rounded border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1 text-xs"
                      >
                        <option value="damaged">damaged</option>
                        <option value="stolen">stolen</option>
                        <option value="lost">lost</option>
                        <option value="expired">expired</option>
                        <option value="other">other</option>
                      </select>
                    ) : (
                      <span className={cn('px-2 py-0.5 rounded-full text-xs font-medium', REASON_COLORS[r.reason])}>
                        {r.reason}
                      </span>
                    )}
                  </td>
                  <td className="px-3 py-2 text-xs max-w-xs">
                    {isEditing ? (
                      <input
                        type="text"
                        value={editForm.notes}
                        onChange={(e) => setEditForm({ ...editForm, notes: e.target.value })}
                        className="w-full rounded border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1 text-xs"
                      />
                    ) : (
                      <span className="truncate inline-block max-w-xs">{r.notes || '—'}</span>
                    )}
                  </td>
                  <td className="text-center px-3 py-2">
                    {(() => {
                      const href = safeHref(r.photo_path);
                      return href ? (
                        <a href={href} target="_blank" rel="noopener noreferrer" className="text-primary-600 text-xs">
                          View
                        </a>
                      ) : (
                        '—'
                      );
                    })()}
                  </td>
                  <td className="text-right px-3 py-2 whitespace-nowrap">
                    {isEditing ? (
                      <div className="inline-flex gap-1">
                        <button
                          type="button"
                          disabled={updateMutation.isPending}
                          onClick={() => {
                            const q = parseInt(editForm.quantity, 10);
                            if (!Number.isFinite(q) || q < 1) { toast.error('Quantity must be a positive integer'); return; }
                            updateMutation.mutate({ id: r.id, quantity: q, reason: editForm.reason, notes: editForm.notes });
                          }}
                          className="px-2 py-1 text-xs font-medium rounded bg-primary-600 text-on-primary hover:bg-primary-700 disabled:opacity-50"
                        >
                          Save
                        </button>
                        <button
                          type="button"
                          onClick={() => setEditingId(null)}
                          className="px-2 py-1 text-xs font-medium rounded border border-surface-200 dark:border-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800"
                        >
                          Cancel
                        </button>
                      </div>
                    ) : (
                      <div className="inline-flex gap-2 text-xs">
                        <button
                          type="button"
                          onClick={() => {
                            setEditingId(r.id);
                            setEditForm({ quantity: String(r.quantity), reason: r.reason, notes: r.notes ?? '' });
                          }}
                          className="text-primary-600 hover:underline"
                        >
                          Edit
                        </button>
                        <button
                          type="button"
                          onClick={async () => {
                            if (!window.confirm(`Delete shrinkage event for ${r.name}? Stock of ${r.quantity} will be restored.`)) return;
                            deleteMutation.mutate(r.id);
                          }}
                          className="text-red-600 hover:underline"
                        >
                          Delete
                        </button>
                      </div>
                    )}
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>
    </div>
  );
}
