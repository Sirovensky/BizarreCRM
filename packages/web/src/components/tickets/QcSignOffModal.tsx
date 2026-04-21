/**
 * QcSignOffModal — audit 44.10.
 *
 * Before a tech marks a ticket complete, the tenant may require a formal
 * sign-off: every checklist item ticked, a photo of the working device, and
 * the tech's signature.
 *
 * The server refuses sign-off unless every active checklist item is
 * explicitly passed=true and both images are attached. The UI pre-validates
 * so we don't round-trip a 400 for the obvious case.
 *
 * Signature capture: simple HTML canvas mouse/touch drawing. We export the
 * canvas as a PNG blob and upload it via multipart.
 */

import { useState, useEffect, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Camera, Eraser, Check, X, Loader2, CheckCircle2 } from 'lucide-react';
import toast from 'react-hot-toast';
import { benchApi } from '@/api/endpoints';

interface QcChecklistItem {
  id: number;
  name: string;
  sort_order: number;
  is_active: number;
  device_category: string | null;
}

interface QcSignOffModalProps {
  ticketId: number;
  ticketDeviceId?: number;
  deviceCategory?: string;
  onClose: () => void;
  onSigned?: () => void;
}

export function QcSignOffModal({
  ticketId,
  ticketDeviceId,
  deviceCategory,
  onClose,
  onSigned,
}: QcSignOffModalProps) {
  const qc = useQueryClient();

  const { data: checklistData, isLoading: checklistLoading } = useQuery({
    queryKey: ['qc-checklist', deviceCategory ?? 'all'],
    queryFn: () => benchApi.qc.checklist(deviceCategory),
  });
  const items: QcChecklistItem[] = checklistData?.data?.data ?? [];

  // Local "passed" map — each ticked item maps to true.
  const [passedMap, setPassedMap] = useState<Record<number, boolean>>({});
  useEffect(() => {
    // Start with every item unchecked so the tech has to physically think
    // through each one. "Select all" is intentionally absent.
    setPassedMap({});
  }, [items.length]);

  const [notes, setNotes] = useState('');
  const [workingPhotoFile, setWorkingPhotoFile] = useState<File | null>(null);
  const [workingPhotoPreview, setWorkingPhotoPreview] = useState<string | null>(null);
  const photoInputRef = useRef<HTMLInputElement>(null);

  // Signature canvas
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const drawingRef = useRef(false);
  const lastPointRef = useRef<{ x: number; y: number } | null>(null);
  const [signatureDrawn, setSignatureDrawn] = useState(false);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
  }, []);

  const getPoint = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    return {
      x: ((e.clientX - rect.left) / rect.width) * e.currentTarget.width,
      y: ((e.clientY - rect.top) / rect.height) * e.currentTarget.height,
    };
  };

  const onPointerDown = (e: React.PointerEvent<HTMLCanvasElement>) => {
    drawingRef.current = true;
    lastPointRef.current = getPoint(e);
    e.currentTarget.setPointerCapture(e.pointerId);
  };
  const onPointerMove = (e: React.PointerEvent<HTMLCanvasElement>) => {
    if (!drawingRef.current) return;
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    const pt = getPoint(e);
    if (lastPointRef.current) {
      ctx.beginPath();
      ctx.moveTo(lastPointRef.current.x, lastPointRef.current.y);
      ctx.lineTo(pt.x, pt.y);
      ctx.stroke();
    }
    lastPointRef.current = pt;
    setSignatureDrawn(true);
  };
  const onPointerUp = () => {
    drawingRef.current = false;
    lastPointRef.current = null;
  };
  const clearSignature = () => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, canvas.width, canvas.height);
    setSignatureDrawn(false);
  };

  const onPhotoChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    setWorkingPhotoFile(file);
    const url = URL.createObjectURL(file);
    setWorkingPhotoPreview(url);
  };

  const allPassed = items.length > 0 && items.every((i) => passedMap[i.id]);
  const canSubmit = allPassed && workingPhotoFile && signatureDrawn;

  const signMut = useMutation({
    mutationFn: async () => {
      if (!workingPhotoFile) throw new Error('Working photo required');
      const canvas = canvasRef.current;
      if (!canvas) throw new Error('Signature canvas not ready');
      const blob: Blob = await new Promise((resolve, reject) =>
        canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('Signature capture failed'))), 'image/png'),
      );

      const fd = new FormData();
      fd.append('ticket_id', String(ticketId));
      if (ticketDeviceId) fd.append('ticket_device_id', String(ticketDeviceId));
      fd.append(
        'checklist_results',
        JSON.stringify(
          items.map((i) => ({ item_id: i.id, passed: !!passedMap[i.id] })),
        ),
      );
      fd.append('notes', notes);
      fd.append('working_photo', workingPhotoFile);
      fd.append('tech_signature', new File([blob], 'signature.png', { type: 'image/png' }));

      return benchApi.qc.signOff(fd);
    },
    onSuccess: () => {
      toast.success('QC sign-off recorded');
      qc.invalidateQueries({ queryKey: ['qc-status', ticketId] });
      qc.invalidateQueries({ queryKey: ['ticket', ticketId] });
      onSigned?.();
      onClose();
    },
    onError: (err: unknown) => {
      const msg = err instanceof Error ? err.message : 'Sign-off failed';
      toast.error(msg);
    },
  });

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="presentation"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="qc-signoff-title"
        className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl bg-white p-6 shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-4 flex items-center justify-between">
          <h2
            id="qc-signoff-title"
            className="flex items-center gap-2 text-lg font-semibold text-surface-900 dark:text-surface-100"
          >
            <CheckCircle2 className="h-5 w-5 text-primary-500" />
            QC Sign-Off
          </h2>
          <button
            aria-label="Close"
            onClick={onClose}
            className="rounded p-1 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {checklistLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
          </div>
        ) : items.length === 0 ? (
          <p className="rounded-lg bg-yellow-50 p-3 text-sm text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-200">
            No QC checklist items are configured for this device category. Ask an admin to add some under Settings → Bench / QC.
          </p>
        ) : (
          <>
            <div className="mb-4">
              <p className="mb-2 text-xs font-semibold uppercase text-surface-500">
                Checklist — every item must be ticked
              </p>
              <ul className="space-y-2">
                {items.map((item) => (
                  <li
                    key={item.id}
                    className="flex items-start gap-3 rounded-lg border border-surface-200 p-2.5 dark:border-surface-700"
                  >
                    <input
                      type="checkbox"
                      checked={!!passedMap[item.id]}
                      onChange={(e) =>
                        setPassedMap((prev) => ({ ...prev, [item.id]: e.target.checked }))
                      }
                      className="mt-0.5 h-4 w-4 rounded border-surface-300 text-primary-600 focus:ring-primary-500"
                    />
                    <span className="flex-1 text-sm text-surface-700 dark:text-surface-300">
                      {item.name}
                    </span>
                  </li>
                ))}
              </ul>
            </div>

            <div className="mb-4">
              <p className="mb-2 text-xs font-semibold uppercase text-surface-500">
                Working device photo
              </p>
              <input
                ref={photoInputRef}
                type="file"
                accept="image/jpeg,image/png,image/webp"
                onChange={onPhotoChange}
                className="hidden"
              />
              {!workingPhotoPreview ? (
                <button
                  onClick={() => photoInputRef.current?.click()}
                  className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-surface-300 p-6 text-sm text-surface-500 hover:border-primary-500 hover:text-primary-600 dark:border-surface-600"
                >
                  <Camera className="h-5 w-5" />
                  Capture / upload photo
                </button>
              ) : (
                <div className="relative">
                  <img
                    src={workingPhotoPreview}
                    alt="Working device"
                    className="h-40 w-full rounded-lg object-cover"
                  />
                  <button
                    onClick={() => {
                      setWorkingPhotoFile(null);
                      setWorkingPhotoPreview(null);
                    }}
                    className="absolute right-2 top-2 rounded-full bg-black/60 p-1 text-white hover:bg-black/80"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>
              )}
            </div>

            <div className="mb-4">
              <p className="mb-2 text-xs font-semibold uppercase text-surface-500">Tech signature</p>
              <div className="overflow-hidden rounded-lg border border-surface-300 bg-white dark:border-surface-600">
                <canvas
                  ref={canvasRef}
                  width={600}
                  height={140}
                  onPointerDown={onPointerDown}
                  onPointerMove={onPointerMove}
                  onPointerUp={onPointerUp}
                  onPointerLeave={onPointerUp}
                  className="w-full touch-none"
                  style={{ height: 140, cursor: 'crosshair' }}
                />
              </div>
              <button
                onClick={clearSignature}
                className="mt-1 flex items-center gap-1 text-xs text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
              >
                <Eraser className="h-3 w-3" /> Clear signature
              </button>
            </div>

            <div className="mb-4">
              <label className="mb-1 block text-xs font-semibold uppercase text-surface-500">
                Notes (optional)
              </label>
              <textarea
                value={notes}
                onChange={(e) => setNotes(e.target.value)}
                rows={2}
                maxLength={1000}
                className="w-full rounded-lg border border-surface-200 bg-surface-50 p-2 text-sm dark:border-surface-700 dark:bg-surface-900 dark:text-surface-100"
                placeholder="Any observations the customer should know about..."
              />
            </div>

            <div className="flex justify-end gap-2">
              <button
                onClick={onClose}
                className="rounded-lg border border-surface-300 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                onClick={() => signMut.mutate()}
                disabled={!canSubmit || signMut.isPending}
                className="flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-semibold text-white hover:bg-primary-700 disabled:opacity-50"
              >
                {signMut.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : (
                  <Check className="h-4 w-4" />
                )}
                Sign off
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
