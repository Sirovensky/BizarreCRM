/**
 * QcSignOffModal — audit 44.10.
 *
 * Before a tech marks a ticket complete, the tenant may require a formal
 * sign-off: every checklist item marked as passed, a photo of the working
 * device, and the tech's signature.
 *
 * The server refuses sign-off unless every active checklist item is explicitly
 * passed=true and both images are attached. Failed QC is not a sign-off row;
 * it is persisted through the ticket workflow by adding an internal note and
 * rerouting the ticket to an existing active status.
 *
 * Signature capture: simple HTML canvas mouse/touch drawing. We export the
 * canvas as a PNG blob and upload it via multipart.
 */

import { useState, useCallback, useEffect, useMemo, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Camera, Eraser, Check, X, Loader2, CheckCircle2, AlertTriangle, History } from 'lucide-react';
import toast from 'react-hot-toast';
import { benchApi, settingsApi, ticketApi } from '@/api/endpoints';
import { formatApiError } from '@/utils/apiError';
import {
  IMAGE_UPLOAD_ACCEPT,
  SMALL_IMAGE_UPLOAD_MAX_BYTES,
  validateImageFile,
} from '@/utils/imageUploadPolicy';

interface QcChecklistItem {
  id: number;
  name: string;
  sort_order: number;
  is_active: number;
  device_category: string | null;
}

type ChecklistOutcome = 'pass' | 'fail';

interface QcSignOffStatus {
  qc_required: boolean;
  signed: boolean;
  sign_off: {
    signed_at?: string;
    notes?: string | null;
    checklist_results?: Array<{ item_id: number; passed: boolean }>;
  } | null;
}

interface TicketStatusOption {
  id: number;
  name: string;
  sort_order?: number;
  is_closed?: boolean | number | string | null;
  is_cancelled?: boolean | number | string | null;
}

interface QcSignOffModalProps {
  ticketId: number;
  ticketDeviceId?: number;
  deviceCategory?: string;
  onClose: () => void;
  onSigned?: () => void;
}

function flagEnabled(value: unknown): boolean {
  return value === true || value === 1 || value === '1';
}

function normalizeStatusName(name: string): string {
  return name.trim().toLowerCase();
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

  const { data: statusData, isLoading: statusesLoading } = useQuery({
    queryKey: ['ticket-statuses'],
    queryFn: () => settingsApi.getStatuses(),
  });
  const statuses: TicketStatusOption[] = statusData?.data?.data ?? [];

  const activeStatuses = useMemo(
    () =>
      statuses
        .filter((status) => !flagEnabled(status.is_closed) && !flagEnabled(status.is_cancelled))
        .sort((a, b) => (a.sort_order ?? 0) - (b.sort_order ?? 0)),
    [statuses],
  );

  const defaultFailureStatus = useMemo(() => {
    const exactQcFailed = activeStatuses.find(
      (status) => normalizeStatusName(status.name) === 'repaired - qc failed',
    );
    if (exactQcFailed) return exactQcFailed;

    const anyQcFailed = activeStatuses.find((status) => {
      const name = normalizeStatusName(status.name);
      return name.includes('qc') && name.includes('fail');
    });
    if (anyQcFailed) return anyQcFailed;

    return (
      activeStatuses.find((status) => normalizeStatusName(status.name) === 'in progress') ??
      activeStatuses[0] ??
      null
    );
  }, [activeStatuses]);

  const [rerouteStatusId, setRerouteStatusId] = useState<number | ''>('');
  useEffect(() => {
    if (!defaultFailureStatus) return;
    setRerouteStatusId((current) => current || defaultFailureStatus.id);
  }, [defaultFailureStatus]);

  const rerouteStatus = activeStatuses.find((status) => status.id === Number(rerouteStatusId));

  // Fetch prior passing sign-off so reopening the modal doesn't imply failure history
  // that the current pass-only sign-off API cannot actually provide.
  const { data: priorStatusData } = useQuery({
    queryKey: ['qc-status', ticketId],
    queryFn: () => benchApi.qc.status(ticketId),
    // Don't retry aggressively — a 404 just means no prior attempt.
    retry: false,
  });
  const priorStatus: QcSignOffStatus | null = priorStatusData?.data?.data ?? null;
  const priorSignOff = priorStatus?.signed ? priorStatus.sign_off : null;

  // WEB-UIUX-1094: Reset key is derived from item ids (not just count) so the map resets
  // when the admin edits the checklist mid-session and ids change, not merely when count changes.
  const itemKey = JSON.stringify(items.map((item) => item.id));
  const [outcomeMap, setOutcomeMap] = useState<Record<number, ChecklistOutcome>>({});
  useEffect(() => {
    // Start with every item unreviewed so the tech has to physically think
    // through each one. "Select all" is intentionally absent.
    setOutcomeMap({});
  }, [itemKey]);
  const hasFailedOutcome = Object.values(outcomeMap).includes('fail');

  const [notes, setNotes] = useState('');
  const [failReason, setFailReason] = useState('');
  const [workingPhotoFile, setWorkingPhotoFile] = useState<File | null>(null);
  const [workingPhotoPreview, setWorkingPhotoPreview] = useState<string | null>(null);
  const workingPhotoPreviewRef = useRef<string | null>(null);
  const photoInputRef = useRef<HTMLInputElement>(null);

  // Revoke the current working-photo blob URL and clear the ref.
  const revokeWorkingPreview = useCallback(() => {
    if (workingPhotoPreviewRef.current) {
      URL.revokeObjectURL(workingPhotoPreviewRef.current);
      workingPhotoPreviewRef.current = null;
    }
  }, []);

  // Clean up on unmount.
  useEffect(() => revokeWorkingPreview, [revokeWorkingPreview]);

  const clearWorkingPhoto = useCallback(() => {
    setWorkingPhotoFile(null);
    revokeWorkingPreview();
    setWorkingPhotoPreview(null);
  }, [revokeWorkingPreview]);

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
    const dpr = window.devicePixelRatio || 1;
    // Scale internal resolution for retina/HiDPI screens.
    canvas.width = 600 * dpr;
    canvas.height = 140 * dpr;
    ctx.scale(dpr, dpr);
    ctx.fillStyle = '#ffffff';
    ctx.fillRect(0, 0, 600, 140);
    ctx.strokeStyle = '#0f172a';
    ctx.lineWidth = 2;
    ctx.lineCap = 'round';
    ctx.lineJoin = 'round';
    setSignatureDrawn(false);
  }, [hasFailedOutcome]);

  const getPoint = (e: React.PointerEvent<HTMLCanvasElement>) => {
    const rect = e.currentTarget.getBoundingClientRect();
    // Return logical (CSS-pixel) coordinates; ctx.scale(dpr, dpr) handles the
    // mapping to physical pixels automatically.
    return {
      x: (e.clientX - rect.left) * (rect.width  > 0 ? 600 / rect.width  : 1),
      y: (e.clientY - rect.top)  * (rect.height > 0 ? 140 / rect.height : 1),
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
    // Use logical dimensions (600×140) — ctx.scale(dpr,dpr) is already in effect.
    ctx.fillRect(0, 0, 600, 140);
    setSignatureDrawn(false);
  };

  const onPhotoChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    // WEB-UIUX-1099: Guard oversized photos before hitting the server.
    if (file.size > 10 * 1024 * 1024) {
      toast.error('Photo too large (max 10MB). Try a smaller image.');
      e.target.value = '';
      return;
    }
    const error = await validateImageFile(file, {
      maxBytes: SMALL_IMAGE_UPLOAD_MAX_BYTES,
      label: `"${file.name}"`,
    });
    if (error) {
      toast.error(error);
      e.target.value = '';
      return;
    }
    setWorkingPhotoFile(file);
    revokeWorkingPreview();
    const url = URL.createObjectURL(file);
    workingPhotoPreviewRef.current = url;
    setWorkingPhotoPreview(url);
  };

  const reviewedCount = items.filter((item) => outcomeMap[item.id]).length;
  const allReviewed = items.length > 0 && reviewedCount === items.length;
  const failedItems = items.filter((item) => outcomeMap[item.id] === 'fail');
  const hasFailures = failedItems.length > 0;
  const allPassed = allReviewed && !hasFailures;
  const canRecordFailure =
    hasFailures &&
    allReviewed &&
    failReason.trim().length > 0 &&
    !!rerouteStatus &&
    !statusesLoading;
  const canSignOff = !!workingPhotoFile && signatureDrawn && allPassed;
  const canSubmit = hasFailures ? canRecordFailure : canSignOff;

  // WEB-UIUX-1087: Guard backdrop click and Esc against silent checklist/photo/signature loss.
  // safeClose fires a confirm dialog when any progress exists (covers WEB-UIUX-1104 implicitly).
  // Guard close when the tech has started filling in the form.
  const hasChanges =
    signatureDrawn ||
    workingPhotoFile !== null ||
    Object.keys(outcomeMap).length > 0 ||
    notes.trim().length > 0 ||
    failReason.trim().length > 0;

  const safeClose = () => {
    if (
      hasChanges &&
      !window.confirm(
        'You have unsaved QC progress (signature, photo, or checklist). Close anyway?',
      )
    ) {
      return;
    }
    clearWorkingPhoto();
    onClose();
  };

  const submitMut = useMutation({
    mutationFn: async () => {
      if (hasFailures) {
        if (!allReviewed) throw new Error('Review every checklist item before recording QC failure');
        if (!rerouteStatus) throw new Error('Choose a ticket status for the QC failure reroute');
        const failedNames = failedItems.map((item) => item.name);
        const noteContent = [
          'QC failed.',
          '',
          'Failed checklist items:',
          ...failedNames.map((name) => `- ${name}`),
          '',
          `Reason: ${failReason.trim()}`,
          notes.trim() ? `\nAdditional notes:\n${notes.trim()}` : '',
        ]
          .filter(Boolean)
          .join('\n');

        let noteSaved = false;
        try {
          await ticketApi.addNote(ticketId, {
            type: 'internal',
            content: noteContent,
            is_flagged: true,
            ticket_device_id: ticketDeviceId,
          });
          noteSaved = true;
          await ticketApi.changeStatus(ticketId, rerouteStatus.id);
        } catch (err) {
          if (noteSaved) {
            throw new Error(`QC failure note was saved, but reroute failed: ${formatApiError(err)}`);
          }
          throw err;
        }

        return { outcome: 'fail' as const, rerouteStatusName: rerouteStatus.name };
      }

      if (!allPassed) throw new Error('Every checklist item must pass before sign-off');
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
        JSON.stringify(items.map((i) => ({ item_id: i.id, passed: outcomeMap[i.id] === 'pass' }))),
      );
      fd.append('notes', notes.trim());
      fd.append('working_photo', workingPhotoFile);
      fd.append('tech_signature', new File([blob], 'signature.png', { type: 'image/png' }));

      await benchApi.qc.signOff(fd);
      return { outcome: 'pass' as const };
    },
    onSuccess: (result) => {
      toast.success(
        result.outcome === 'fail'
          ? `QC failure recorded; ticket rerouted to ${result.rerouteStatusName}`
          : 'QC sign-off recorded',
      );
      // WEB-UIUX-1097: invalidate 'qc-status' becomes live once WEB-UIUX-1081 lands and a
      // useQuery(['qc-status', …]) is registered in the tickets list / board view.
      qc.invalidateQueries({ queryKey: ['qc-status', ticketId] });
      qc.invalidateQueries({ queryKey: ['ticket', ticketId] });
      qc.invalidateQueries({ queryKey: ['ticket-history', ticketId] });
      qc.invalidateQueries({ queryKey: ['tickets'] });
      qc.invalidateQueries({ queryKey: ['tickets', 'kanban'] });
      if (result.outcome === 'pass') onSigned?.();
      clearWorkingPhoto();
      onClose();
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
    },
  });

  useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') safeClose(); };
    document.addEventListener('keydown', handler);
    return () => document.removeEventListener('keydown', handler);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [hasChanges, onClose]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 p-4"
      role="presentation"
      onClick={safeClose}
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
            onClick={safeClose}
            className="rounded p-1 text-surface-400 hover:text-surface-600 dark:hover:text-surface-200"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {priorSignOff && (
          <div className="mb-4 flex gap-3 rounded-lg border border-green-300 bg-green-50 p-3 text-sm text-green-800 dark:border-green-700 dark:bg-green-900/20 dark:text-green-200">
            <History className="mt-0.5 h-4 w-4 shrink-0" />
            <div className="min-w-0">
              <p className="font-semibold">
                Existing QC sign-off recorded
                {priorSignOff.signed_at
                  ? ` on ${new Date(priorSignOff.signed_at).toLocaleDateString()}`
                  : ''}
              </p>
              {priorSignOff.notes && (
                <p className="mt-1 text-xs opacity-80">{priorSignOff.notes}</p>
              )}
            </div>
          </div>
        )}

        {checklistLoading ? (
          <div className="flex justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
          </div>
        ) : items.length === 0 ? (
          <div className="rounded-lg bg-yellow-50 p-3 text-sm text-yellow-800 dark:bg-yellow-900/20 dark:text-yellow-200">
            <p>
              No QC checklist items are configured for this device category. Ask an admin to add some under Settings → Bench / QC.
            </p>
            {/* WEB-UIUX-1103: Recovery affordance — point to the migration that seeds defaults. */}
            <p className="mt-1.5 text-xs opacity-75">
              (Migration 088 seeds 9 default items — restore via DB if all were deleted)
            </p>
          </div>
        ) : (
          <>
            <div className="mb-4">
              <p className="mb-2 text-xs font-semibold uppercase text-surface-500">
                Checklist — mark each item pass or fail
              </p>
              <ul className="space-y-2">
                {items.map((item) => (
                  <li
                    key={item.id}
                    className="flex flex-col gap-2 rounded-lg border border-surface-200 p-2.5 sm:flex-row sm:items-center sm:justify-between dark:border-surface-700"
                  >
                    <span className="min-w-0 flex-1 text-sm text-surface-700 dark:text-surface-300">
                      {item.name}
                    </span>
                    <div className="grid w-full grid-cols-2 gap-1 sm:w-44">
                      <button
                        type="button"
                        aria-pressed={outcomeMap[item.id] === 'pass'}
                        onClick={() =>
                          setOutcomeMap((prev) => ({ ...prev, [item.id]: 'pass' }))
                        }
                        className={`rounded-md border px-2 py-1.5 text-xs font-semibold transition-colors ${
                          outcomeMap[item.id] === 'pass'
                            ? 'border-green-500 bg-green-100 text-green-800 dark:border-green-700 dark:bg-green-900/40 dark:text-green-200'
                            : 'border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700'
                        }`}
                      >
                        Pass
                      </button>
                      <button
                        type="button"
                        aria-pressed={outcomeMap[item.id] === 'fail'}
                        onClick={() =>
                          setOutcomeMap((prev) => ({ ...prev, [item.id]: 'fail' }))
                        }
                        className={`rounded-md border px-2 py-1.5 text-xs font-semibold transition-colors ${
                          outcomeMap[item.id] === 'fail'
                            ? 'border-red-500 bg-red-100 text-red-800 dark:border-red-700 dark:bg-red-900/40 dark:text-red-200'
                            : 'border-surface-200 text-surface-600 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-700'
                        }`}
                      >
                        Fail
                      </button>
                    </div>
                  </li>
                ))}
              </ul>
              {!allReviewed && (
                <p className="mt-2 text-xs text-surface-500 dark:text-surface-400">
                  Review {items.length - reviewedCount} more checklist item
                  {items.length - reviewedCount === 1 ? '' : 's'} before submitting.
                </p>
              )}
            </div>

            {hasFailures && (
              <div className="mb-4 rounded-lg border border-red-300 bg-red-50 p-3 dark:border-red-700 dark:bg-red-900/20">
                <label className="mb-1 flex items-center gap-1.5 text-xs font-semibold uppercase text-red-700 dark:text-red-400">
                  <AlertTriangle className="h-3.5 w-3.5" />
                  QC failure and reroute
                </label>
                <textarea
                  value={failReason}
                  onChange={(e) => setFailReason(e.target.value)}
                  rows={3}
                  maxLength={1000}
                  className="w-full rounded-lg border border-red-300 bg-white p-2 text-sm text-surface-900 focus:outline-none focus:ring-2 focus:ring-red-400 dark:border-red-700 dark:bg-surface-900 dark:text-surface-100"
                  placeholder="Describe which items failed and why…"
                />
                <p className="mt-1 text-xs text-red-600 dark:text-red-400">
                  Failed: {failedItems.map((i) => i.name).join(', ')}.
                </p>
                <label className="mt-3 block text-xs font-semibold uppercase text-red-700 dark:text-red-400">
                  Reroute ticket to
                </label>
                <select
                  value={rerouteStatusId}
                  onChange={(e) => setRerouteStatusId(Number(e.target.value))}
                  disabled={statusesLoading || activeStatuses.length === 0}
                  className="mt-1 w-full rounded-lg border border-red-300 bg-white p-2 text-sm text-surface-900 focus:outline-none focus:ring-2 focus:ring-red-400 disabled:cursor-not-allowed disabled:opacity-60 dark:border-red-700 dark:bg-surface-900 dark:text-surface-100"
                >
                  {activeStatuses.map((status) => (
                    <option key={status.id} value={status.id}>
                      {status.name}
                    </option>
                  ))}
                </select>
                {activeStatuses.length === 0 && !statusesLoading && (
                  <p className="mt-2 text-xs text-red-700 dark:text-red-300">
                    No active ticket status is available for reroute, so QC failure cannot be submitted.
                  </p>
                )}
                <p className="mt-2 text-xs text-red-700 dark:text-red-300">
                  This records an internal ticket note and changes the ticket status; it does not create a passing QC sign-off.
                </p>
              </div>
            )}

            {!hasFailures && (
              <>
                <div className="mb-4">
                  <p className="mb-2 text-xs font-semibold uppercase text-surface-500">
                    Photo of working device
                  </p>
                  {/* WEB-UIUX-1090: Include HEIC/HEIF so iPhone Safari users are not blocked.
                      NOTE: server ALLOWED_MIMES may need a parallel update to accept
                      image/heic and image/heif — track separately. */}
                  {/* WEB-UIUX-1110: Removed image/webp from accept — webp cannot be captured
                      from iOS Safari camera; jpeg/png/heic/heif cover all real-device cases. */}
                  <input
                    ref={photoInputRef}
                    type="file"
                    accept="image/jpeg,image/png,image/heic,image/heif"
                    onChange={onPhotoChange}
                    className="hidden"
                  />
                  {!workingPhotoPreview ? (
                    <button
                      type="button"
                      onClick={() => photoInputRef.current?.click()}
                      className="flex w-full items-center justify-center gap-2 rounded-lg border-2 border-dashed border-surface-300 p-6 text-sm text-surface-500 hover:border-primary-500 hover:text-primary-600 dark:border-surface-600"
                    >
                      <Camera className="h-5 w-5" />
                      {/* WEB-UIUX-1108: "Capture / upload photo" slash was awkward; changed to "Add photo". */}
                      Add photo
                    </button>
                  ) : (
                    <div className="relative">
                      <img
                        src={workingPhotoPreview}
                        alt="Working device"
                        className="h-40 w-full rounded-lg object-cover"
                      />
                      <button
                        type="button"
                        onClick={clearWorkingPhoto}
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
                      onPointerDown={onPointerDown}
                      onPointerMove={onPointerMove}
                      onPointerUp={onPointerUp}
                      onPointerLeave={onPointerUp}
                      className="h-[140px] w-full touch-none"
                      style={{ cursor: 'crosshair' }}
                    />
                  </div>
                  <button
                    type="button"
                    onClick={clearSignature}
                    className="mt-1 flex items-center gap-1 text-xs text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
                  >
                    <Eraser className="h-3 w-3" /> Clear signature
                  </button>
                </div>
              </>
            )}

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
                placeholder="Internal QC notes (not shown to the customer)…"
              />
              {/* WEB-UIUX-1106: Character counter so tech sees remaining chars before truncation. */}
              <div className="text-xs text-surface-400 text-right mt-1">{notes.length} / 1000</div>
            </div>

            <div className="flex justify-end gap-2">
              {/* WEB-UIUX-1101: Cancel is ghost/text-only so it doesn't compete visually with the primary CTA. */}
              <button
                onClick={safeClose}
                className="px-4 py-2 text-sm font-medium text-surface-500 hover:text-surface-700 dark:text-surface-400 dark:hover:text-surface-200"
              >
                Cancel
              </button>
              <button
                onClick={() => submitMut.mutate()}
                disabled={!canSubmit || submitMut.isPending}
                className={`flex items-center gap-2 rounded-lg px-4 py-2 text-sm font-semibold disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none ${
                  hasFailures
                    ? 'bg-red-600 text-white hover:bg-red-700'
                    : 'bg-primary-600 text-primary-950 hover:bg-primary-700'
                }`}
              >
                {submitMut.isPending ? (
                  <Loader2 className="h-4 w-4 animate-spin" />
                ) : hasFailures ? (
                  <AlertTriangle className="h-4 w-4" />
                ) : (
                  <Check className="h-4 w-4" />
                )}
                {hasFailures ? 'Record failure' : 'Sign off'}
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  );
}
