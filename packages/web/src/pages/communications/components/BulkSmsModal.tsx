import { useEffect, useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { X, AlertTriangle, Users, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { smsApi } from '@/api/endpoints';
import { SmsTemplateListResponse } from '@/api/types';
import { cn } from '@/utils/cn';

/**
 * Bulk SMS modal — audit §51.3.
 *
 * Two-step confirmation:
 *   1. User picks segment + template, modal shows preview count and fetches
 *      a server-issued confirmation token.
 *   2. User clicks "Send to N recipients" — token is submitted with the
 *      request so a single click cannot dispatch without seeing the count.
 *
 * Admin-only: backend enforces req.user.role === 'admin'. Non-admins see a
 * 403 and a friendly error.
 */

interface BulkSmsModalProps {
  open: boolean;
  onClose: () => void;
}

type Segment = 'open_tickets' | 'all_customers' | 'recent_purchases';

// WEB-UIUX-1115: Append opt-in scope to every segment hint so admins know counts are filtered
const SEGMENTS: { value: Segment; label: string; hint: string }[] = [
  { value: 'open_tickets', label: 'Open tickets', hint: 'Customers with tickets in progress (opted-in for marketing only)' },
  { value: 'recent_purchases', label: 'Recent purchases', hint: 'Customers who bought in last 30 days (opted-in for marketing only)' },
  { value: 'all_customers', label: 'All customers', hint: 'Every customer with a mobile number (opted-in for marketing only)' },
];

interface SmsTemplate {
  id: number;
  name: string;
  content: string;
}

interface PreviewResponse {
  preview_count: number;
  confirmation_token: string;
  confirmed: false;
}

// WEB-UIUX-1111: Updated to match server response shape from inbox.routes.ts:693-703
interface ConfirmResponse {
  attempted: number;
  sent: number;
  failed: number;
  segment: string;
  template: string;
  confirmed: true;
}

export function BulkSmsModal({ open, onClose }: BulkSmsModalProps) {
  // WEB-UIUX-1121: Default to recent_purchases — most common bulk send use-case
  const [segment, setSegment] = useState<Segment>('recent_purchases');
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  // WEB-UIUX-1122: TCPA quiet-hours warning state
  const [quietHoursWarning, setQuietHoursWarning] = useState<string | null>(null);
  // WEB-UIUX-1124: Countdown timer for confirmation expiry
  const [previewedAt, setPreviewedAt] = useState<number | null>(null);
  const [countdown, setCountdown] = useState<number>(300); // 5 minutes in seconds

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
    enabled: open,
  });
  const tplPayload = tplData?.data as SmsTemplateListResponse | undefined;
  const templates: SmsTemplate[] = tplPayload?.data?.templates ?? [];

  const previewMut = useMutation({
    mutationFn: async () => {
      if (!templateId) throw new Error('Pick a template');
      const res = await api.post<{ success: boolean; data: PreviewResponse }>(
        '/inbox/bulk-send',
        { segment, template_id: templateId },
      );
      return res.data.data;
    },
    onSuccess: (p) => {
      setPreview(p);
      // WEB-UIUX-1124: Record when preview was received so countdown can track expiry
      setPreviewedAt(Date.now());
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Failed to preview'),
  });

  const sendMut = useMutation({
    mutationFn: async () => {
      if (!preview || !templateId) throw new Error('No preview');
      const res = await api.post<{ success: boolean; data: ConfirmResponse }>(
        '/inbox/bulk-send',
        {
          segment,
          template_id: templateId,
          confirmation_token: preview.confirmation_token,
        },
      );
      return res.data.data;
    },
    onSuccess: (r) => {
      // WEB-UIUX-1111: Use actual server fields; keep modal open when failures occurred
      toast.success(
        `Sent ${r.sent} of ${r.attempted}${r.failed > 0 ? ` (${r.failed} failed — see retry queue)` : ''}`,
      );
      setPreview(null);
      setPreviewedAt(null);
      setTemplateId(null);
      if (r.failed === 0) {
        onClose();
      }
      // If failed > 0 modal stays open so admin sees the count before dismissing
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Bulk send failed'),
  });

  // WEB-UIUX-1122: Check TCPA quiet hours (8am–9pm) on open and whenever modal is shown
  useEffect(() => {
    if (!open) return;
    const checkQuietHours = () => {
      const now = new Date();
      const h = now.getHours();
      if (h < 8 || h >= 21) {
        const hh = String(h).padStart(2, '0');
        const mm = String(now.getMinutes()).padStart(2, '0');
        setQuietHoursWarning(`${hh}:${mm}`);
      } else {
        setQuietHoursWarning(null);
      }
    };
    checkQuietHours();
    const interval = setInterval(checkQuietHours, 60_000);
    return () => clearInterval(interval);
  }, [open]);

  // WEB-UIUX-1124: Live countdown for confirmation token (5 min = 300 s)
  useEffect(() => {
    if (!previewedAt) return;
    setCountdown(300);
    const interval = setInterval(() => {
      const elapsed = Math.floor((Date.now() - previewedAt) / 1000);
      const remaining = Math.max(0, 300 - elapsed);
      setCountdown(remaining);
      if (remaining === 0) clearInterval(interval);
    }, 1000);
    return () => clearInterval(interval);
  }, [previewedAt]);

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      // Gate Esc while in preview — closing would silently discard the
      // 5-min confirmation_token and force the user to re-preview.
      if (e.key === 'Escape' && !preview) onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose, preview]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="bulk-sms-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={preview ? undefined : onClose}
    >
      <div
        className="w-full max-w-md rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 id="bulk-sms-title" className="flex items-center gap-2 text-lg font-semibold text-surface-900 dark:text-surface-100">
            <Users className="h-5 w-5 text-primary-500" />
            Bulk SMS
          </h3>
          <button
            onClick={onClose}
            aria-label="Close"
            className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700"
          >
            <X className="h-5 w-5 text-surface-500" />
          </button>
        </div>

        <div className="space-y-3 p-4">
          {/* WEB-UIUX-1115: Consent-scope banner so admins know counts are opt-in filtered */}
          <p className="text-xs text-surface-500">Recipient counts include only customers who opted in to marketing SMS.</p>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300">
              Segment
            </label>
            <div role="radiogroup" aria-label="Recipient segment" className="space-y-1">
              {SEGMENTS.map((s) => (
                <button
                  key={s.value}
                  type="button"
                  role="radio"
                  aria-checked={segment === s.value}
                  tabIndex={segment === s.value ? 0 : -1}
                  onClick={() => {
                    setSegment(s.value);
                    setPreview(null);
                    setPreviewedAt(null);
                  }}
                  className={cn(
                    'block w-full rounded-lg border p-2 text-left text-sm transition-colors',
                    segment === s.value
                      ? 'border-primary-400 bg-primary-50 dark:border-primary-600 dark:bg-primary-900/20'
                      : 'border-surface-200 hover:border-surface-300 dark:border-surface-600',
                  )}
                >
                  <div className="font-medium text-surface-900 dark:text-surface-100">
                    {s.label}
                  </div>
                  <div className="text-[11px] text-surface-500">{s.hint}</div>
                </button>
              ))}
            </div>
          </div>

          <div>
            <label className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300">
              Template
            </label>
            <select
              value={templateId ?? ''}
              onChange={(e) => {
                setTemplateId(Number(e.target.value) || null);
                setPreview(null);
                setPreviewedAt(null);
              }}
              className="w-full rounded-lg border border-surface-300 bg-white px-2 py-1.5 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            >
              <option value="">Pick a template…</option>
              {templates.map((t) => (
                <option key={t.id} value={t.id}>
                  {t.name}
                </option>
              ))}
            </select>
          </div>

          {/* WEB-UIUX-1122: TCPA quiet-hours informational banner — does not block send */}
          {quietHoursWarning && (
            <div className="flex items-start gap-2 rounded-lg border border-amber-400 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-600 dark:bg-amber-900/20 dark:text-amber-200">
              <AlertTriangle className="h-4 w-4 flex-shrink-0 text-amber-600 dark:text-amber-400" />
              <span>
                Local time {quietHoursWarning} — TCPA quiet hours typically 21:00–08:00. Many US states restrict sending outside that window.
              </span>
            </div>
          )}

          {preview && (
            <div className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-200">
              <AlertTriangle className="h-4 w-4 flex-shrink-0" />
              {/* WEB-UIUX-1124: Live countdown replaces static "5 minutes" copy */}
              <span>
                This will send to <strong>{preview.preview_count}</strong> recipients.
                {countdown > 0 ? (
                  <> Confirmation expires in <strong>{String(Math.floor(countdown / 60)).padStart(2, '0')}:{String(countdown % 60).padStart(2, '0')}</strong>.</>
                ) : (
                  <> <strong className="text-red-700 dark:text-red-400">Confirmation expired.</strong> Please re-preview.</>
                )}
              </span>
            </div>
          )}
        </div>

        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          <button
            onClick={onClose}
            className="rounded-lg px-3 py-1.5 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
          {!preview ? (
            <button
              onClick={() => previewMut.mutate()}
              disabled={!templateId || previewMut.isPending}
              className="rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
            >
              {previewMut.isPending ? 'Previewing…' : 'Preview'}
            </button>
          ) : (
            <>
              <button
                onClick={() => { setPreview(null); previewMut.mutate(); }}
                disabled={!templateId || previewMut.isPending}
                className="text-sm text-primary-600 hover:text-primary-800 dark:text-primary-400 dark:hover:text-primary-200 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {previewMut.isPending ? 'Refreshing…' : 'Re-Preview'}
              </button>
              <button
                onClick={() => sendMut.mutate()}
                disabled={sendMut.isPending || preview.preview_count === 0 || countdown === 0}
                title={countdown === 0 ? 'Confirmation expired — please re-preview' : undefined}
                className="inline-flex items-center gap-1 rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
              >
                <Send className="h-3.5 w-3.5" />
                {sendMut.isPending ? 'Sending…' : `Send to ${preview.preview_count}`}
              </button>
            </>
          )}
        </div>
      </div>
    </div>
  );
}
