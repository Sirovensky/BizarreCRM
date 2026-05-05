/**
 * DefectReporterButton — audit 44.14.
 *
 * One-click "Report defect" on a part that's installed on a ticket. Opens a
 * small modal for defect type + optional description + optional photo, then
 * submits and tells the tech how many defects have been logged for this part
 * in the last 30 days. If the threshold is crossed, a procurement
 * notification is fired (server side).
 */

import { useEffect, useRef, useState } from 'react';
import { useMutation } from '@tanstack/react-query';
import { AlertTriangle, X, Loader2, Camera } from 'lucide-react';
import toast from 'react-hot-toast';
import { benchApi } from '@/api/endpoints';

// WEB-FD-012 (Fixer-426B 2026-04-26): typed response for benchApi.defects.report.
interface DefectReportResponse {
  count_30d?: number;
  alert_triggered?: boolean;
  threshold?: number;
}

interface DefectReporterButtonProps {
  inventoryItemId: number;
  itemName: string;
  ticketId?: number;
  compact?: boolean;
}

const DEFECT_TYPES = [
  { value: 'doa', label: 'DOA (dead on arrival)' },
  { value: 'intermittent', label: 'Intermittent failure' },
  { value: 'cosmetic', label: 'Cosmetic defect' },
  { value: 'wrong_spec', label: 'Wrong spec / mismatch' },
];

export function DefectReporterButton({
  inventoryItemId,
  itemName,
  ticketId,
  compact = false,
}: DefectReporterButtonProps) {
  const [open, setOpen] = useState(false);
  const [defectType, setDefectType] = useState('doa');
  const [description, setDescription] = useState('');
  const [photoFile, setPhotoFile] = useState<File | null>(null);
  const [photoPreview, setPhotoPreview] = useState<string | null>(null);
  const photoRef = useRef<HTMLInputElement>(null);

  const reset = () => {
    setDefectType('doa');
    setDescription('');
    setPhotoFile(null);
    setPhotoPreview(null);
  };

  const reportMut = useMutation({
    mutationFn: () => {
      const fd = new FormData();
      fd.append('inventory_item_id', String(inventoryItemId));
      if (ticketId) fd.append('ticket_id', String(ticketId));
      fd.append('defect_type', defectType);
      if (description) fd.append('description', description);
      if (photoFile) fd.append('photo', photoFile);
      return benchApi.defects.report(fd);
    },
    onSuccess: (res: { data?: { data?: DefectReportResponse } }) => {
      const count = res?.data?.data?.count_30d ?? 0;
      const alert = res?.data?.data?.alert_triggered;
      const threshold = res?.data?.data?.threshold ?? 0;
      toast.success(
        alert
          ? `Defect logged. ${count} in last 30 days -> over threshold of ${threshold}, procurement notified.`
          : `Defect logged (${count} in last 30 days).`,
      );
      reset();
      setOpen(false);
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Failed to report defect';
      toast.error(msg);
    },
  });

  const onPhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setPhotoFile(file);
    setPhotoPreview(URL.createObjectURL(file));
  };

  // WEB-FX-003: Esc-to-close.
  useEffect(() => {
    if (!open) return;
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') setOpen(false); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [open]);

  return (
    <>
      <button
        onClick={() => setOpen(true)}
        title={`Report a defect on ${itemName}`}
        className={
          compact
            ? 'inline-flex items-center gap-1 text-xs text-red-600 hover:text-red-800 dark:text-red-400 dark:hover:text-red-300'
            : 'inline-flex items-center gap-1 rounded-lg border border-red-200 bg-red-50 px-2.5 py-1 text-xs font-medium text-red-700 hover:bg-red-100 dark:border-red-800 dark:bg-red-900/20 dark:text-red-300 dark:hover:bg-red-900/40'
        }
      >
        <AlertTriangle className="h-3.5 w-3.5" />
        {compact ? 'Defect' : 'Report defect'}
      </button>

      {open && (
        <div
          className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
          onClick={() => setOpen(false)}
        >
          <div
            role="dialog"
            aria-modal="true"
            aria-labelledby="defect-report-title"
            className="w-full max-w-md rounded-xl bg-white p-5 shadow-2xl dark:bg-surface-800"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="mb-3 flex items-center justify-between">
              <h3 id="defect-report-title" className="flex items-center gap-2 text-base font-semibold text-surface-900 dark:text-surface-100">
                <AlertTriangle className="h-4 w-4 text-red-500" />
                Report defect
              </h3>
              <button
                onClick={() => setOpen(false)}
                className="rounded p-1 text-surface-400 hover:text-surface-600"
              >
                <X className="h-4 w-4" />
              </button>
            </div>

            <p className="mb-3 text-sm text-surface-600 dark:text-surface-400">
              Part: <span className="font-medium">{itemName}</span>
            </p>

            <div className="mb-3">
              <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">
                Defect type
              </label>
              <select
                value={defectType}
                onChange={(e) => setDefectType(e.target.value)}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
              >
                {DEFECT_TYPES.map((t) => (
                  <option key={t.value} value={t.value}>
                    {t.label}
                  </option>
                ))}
              </select>
            </div>

            <div className="mb-3">
              <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">
                Description (optional)
              </label>
              <textarea
                value={description}
                onChange={(e) => setDescription(e.target.value)}
                rows={2}
                maxLength={2000}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                placeholder="What went wrong?"
              />
            </div>

            <div className="mb-4">
              <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">
                Photo (optional)
              </label>
              <input
                ref={photoRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={onPhotoChange}
                className="hidden"
              />
              {!photoPreview ? (
                <button
                  onClick={() => photoRef.current?.click()}
                  className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-surface-300 p-4 text-xs text-surface-500 hover:border-red-500 hover:text-red-600 dark:border-surface-600"
                >
                  <Camera className="h-4 w-4" />
                  Attach photo
                </button>
              ) : (
                <div className="relative">
                  <img
                    src={photoPreview}
                    alt="Defect"
                    className="h-28 w-full rounded-lg object-cover"
                  />
                  <button
                    onClick={() => {
                      setPhotoFile(null);
                      setPhotoPreview(null);
                    }}
                    className="absolute right-1 top-1 rounded-full bg-black/60 p-1 text-white hover:bg-black/80"
                  >
                    <X className="h-3 w-3" />
                  </button>
                </div>
              )}
            </div>

            <div className="flex justify-end gap-2">
              <button
                onClick={() => setOpen(false)}
                className="rounded-lg border border-surface-300 px-3 py-1.5 text-sm text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                onClick={() => reportMut.mutate()}
                disabled={reportMut.isPending}
                className="flex items-center gap-2 rounded-lg bg-red-600 px-3 py-1.5 text-sm font-semibold text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                {reportMut.isPending && <Loader2 className="h-3.5 w-3.5 animate-spin" />}
                Submit report
              </button>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
