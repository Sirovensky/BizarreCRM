import { useEffect, useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { X, AlertTriangle, Users, Send } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { smsApi } from '@/api/endpoints';
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

const SEGMENTS: { value: Segment; label: string; hint: string }[] = [
  { value: 'open_tickets', label: 'Open tickets', hint: 'Customers with tickets in progress' },
  { value: 'recent_purchases', label: 'Recent purchases', hint: 'Customers who bought in last 30 days' },
  { value: 'all_customers', label: 'All customers', hint: 'Every customer with a mobile number' },
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

interface ConfirmResponse {
  enqueued: number;
  segment: string;
  confirmed: true;
}

export function BulkSmsModal({ open, onClose }: BulkSmsModalProps) {
  const [segment, setSegment] = useState<Segment>('open_tickets');
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
    enabled: open,
  });
  const templates: SmsTemplate[] = (tplData?.data as any)?.data?.templates ?? [];

  const previewMut = useMutation({
    mutationFn: async () => {
      if (!templateId) throw new Error('Pick a template');
      const res = await api.post<{ success: boolean; data: PreviewResponse }>(
        '/inbox/bulk-send',
        { segment, template_id: templateId },
      );
      return res.data.data;
    },
    onSuccess: (p) => setPreview(p),
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
      toast.success(`Enqueued ${r.enqueued} messages`);
      setPreview(null);
      setTemplateId(null);
      onClose();
    },
    onError: (e: any) => toast.error(e?.response?.data?.error || 'Bulk send failed'),
  });

  useEffect(() => {
    if (!open) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  if (!open) return null;

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="bulk-sms-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
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
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300">
              Segment
            </label>
            <div className="space-y-1">
              {SEGMENTS.map((s) => (
                <button
                  key={s.value}
                  type="button"
                  onClick={() => {
                    setSegment(s.value);
                    setPreview(null);
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

          {preview && (
            <div className="flex items-start gap-2 rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900 dark:border-amber-700 dark:bg-amber-900/20 dark:text-amber-200">
              <AlertTriangle className="h-4 w-4 flex-shrink-0" />
              <span>
                This will send to <strong>{preview.preview_count}</strong> recipients.
                Confirmation expires in 5 minutes.
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
              className="rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50"
            >
              {previewMut.isPending ? 'Previewing…' : 'Preview'}
            </button>
          ) : (
            <button
              onClick={() => sendMut.mutate()}
              disabled={sendMut.isPending || preview.preview_count === 0}
              className="inline-flex items-center gap-1 rounded-lg bg-red-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-red-700 disabled:opacity-50"
            >
              <Send className="h-3.5 w-3.5" />
              {sendMut.isPending ? 'Sending…' : `Send to ${preview.preview_count}`}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
