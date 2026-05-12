import { useEffect, useState } from 'react';
import { useQuery, useMutation } from '@tanstack/react-query';
import { X, AlertTriangle, Users, Send, Minus } from 'lucide-react';
import toast from 'react-hot-toast';
import { api } from '@/api/client';
import { smsApi } from '@/api/endpoints';
import { SmsTemplateListResponse } from '@/api/types';
import { cn } from '@/utils/cn';
// WEB-UIUX-1521: Focus trap for modal accessibility
import { useFocusTrap } from '@/hooks/useFocusTrap';

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
  // WEB-UIUX-1113: server ships up to 5 masked sample phones so the operator
  // can sanity-check WHO before confirming a marketing blast.
  sample_phones?: Array<{ masked: string }>;
  sample_size?: number;
  // WEB-UIUX-1517: hourly bulk-send quota counter so admin knows how many
  // sends remain in the current window before hitting the 429.
  quota?: {
    used: number;
    max: number;
    window_ms: number;
    reset_at: string | null;
  };
  // WEB-UIUX-1510: provider state echoed at preview time. `real=false`
  // means simulated/unconfigured — UI gates Send + renders an inline
  // "configure provider" banner instead of letting admin build a full
  // campaign that then fails at confirm step.
  provider?: {
    real: boolean;
    name: string | null;
  };
}

// WEB-UIUX-1111: Updated to match server response shape from inbox.routes.ts:693-703
// WEB-UIUX-1117: server now returns a job id + initial counts (sent=0, failed=0)
// and the dispatch happens async on the server. Client polls /jobs/:id for
// progress and can hit /jobs/:id/abort.
interface ConfirmResponse {
  attempted: number;
  sent: number;
  failed: number;
  segment: string;
  template: string | { id: number; name: string };
  confirmed: true;
  job_id: number | null;
  status?: 'running' | 'completed' | 'aborted' | 'failed';
}

interface JobProgress {
  id: number;
  total: number;
  sent: number;
  failed: number;
  status: 'pending' | 'running' | 'completed' | 'aborted' | 'failed';
  abort_requested: number;
  last_error: string | null;
}

export function BulkSmsModal({ open, onClose }: BulkSmsModalProps) {
  // WEB-UIUX-1521: Always-active focus trap — modal only renders when open
  const dialogRef = useFocusTrap(true);
  // WEB-UIUX-1121: Default to recent_purchases — most common bulk send use-case
  const [segment, setSegment] = useState<Segment>('recent_purchases');
  const [templateId, setTemplateId] = useState<number | null>(null);
  const [preview, setPreview] = useState<PreviewResponse | null>(null);
  // WEB-UIUX-1122: TCPA quiet-hours warning state
  const [quietHoursWarning, setQuietHoursWarning] = useState<string | null>(null);
  // WEB-UIUX-1124: Countdown timer for confirmation expiry
  const [previewedAt, setPreviewedAt] = useState<number | null>(null);
  const [countdown, setCountdown] = useState<number>(300); // 5 minutes in seconds
  // WEB-UIUX-1513: typed-confirm gate when preview_count >= 100.
  const [typedConfirm, setTypedConfirm] = useState('');
  // WEB-UIUX-1117: track the running job for poll + abort.
  const [jobId, setJobId] = useState<number | null>(null);
  const [jobProgress, setJobProgress] = useState<JobProgress | null>(null);
  const [aborting, setAborting] = useState(false);
  // WEB-UIUX-869: minimized-to-chip state so the cashier can answer inbound
  // SMS during the 5-min token window. The modal pops back open via the
  // chip's Reopen button or by clicking the chip body. Auto-reset to
  // !minimized when the preview is cleared (e.g. after Send) so the
  // chip doesn't linger.
  const [minimized, setMinimized] = useState(false);
  useEffect(() => {
    if (!preview) setMinimized(false);
  }, [preview]);
  useEffect(() => {
    if (!open) setMinimized(false);
  }, [open]);
  // Reset typed confirm whenever the preview resets so a stale count
  // can't unlock Send after segment/template change.
  useEffect(() => { setTypedConfirm(''); }, [preview?.preview_count]);

  const { data: tplData } = useQuery({
    queryKey: ['sms-templates'],
    queryFn: () => smsApi.templates(),
    enabled: open,
  });
  const tplPayload = tplData?.data as SmsTemplateListResponse | undefined;
  const templates: SmsTemplate[] = tplPayload?.data?.templates ?? [];

  // WEB-UIUX-1512: pre-fetch per-segment counts so segment buttons can
  // label their reach before the admin commits to one. Server endpoint
  // is admin-only + cheap (3 COUNT(DISTINCT) queries); 60s staleTime
  // keeps the chip honest without spamming refresh.
  const { data: segmentCountsData } = useQuery({
    queryKey: ['bulk-sms-segment-counts'],
    queryFn: async () => {
      const res = await api.get<{
        success: boolean;
        data: { open_tickets: number; all_customers: number; recent_purchases: number };
      }>('/inbox/bulk-send-segment-counts');
      return res.data.data;
    },
    enabled: open,
    staleTime: 60_000,
  });
  const segmentCounts = segmentCountsData ?? null;

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
      // WEB-UIUX-1117: kick off poll on the returned job. Server dispatched
      // the send loop async; the modal switches into "progress" view and
      // polls /jobs/:id every 2s. Empty audiences come back with job_id=null.
      if (r.job_id) {
        setJobId(r.job_id);
        setJobProgress({
          id: r.job_id,
          total: r.attempted,
          sent: r.sent,
          failed: r.failed,
          status: 'running',
          abort_requested: 0,
          last_error: null,
        });
        toast.success(`Bulk send started — dispatching to ${r.attempted} recipient${r.attempted === 1 ? '' : 's'}.`);
        setPreview(null);
        setPreviewedAt(null);
      } else {
        toast.success(`No recipients matched segment ${r.segment}.`);
        setPreview(null);
        setPreviewedAt(null);
        setTemplateId(null);
        onClose();
      }
    },
    onError: (e: any) => {
      // WEB-UIUX-1120: surface server rate-limit hint with a precise wait
      // window instead of the opaque "Bulk send failed" toast. Server reply
      // shape is `Rate limit exceeded — try again in {N}s` from guardInboxRate.
      const raw = String(e?.response?.data?.error ?? e?.response?.data?.message ?? '');
      const status = e?.response?.status;
      const m = /try again in (\d+)s/i.exec(raw);
      if (status === 429 && m) {
        const seconds = parseInt(m[1], 10);
        const mins = Math.floor(seconds / 60);
        const human = mins >= 1 ? `${mins} min` : `${seconds}s`;
        toast.error(`Bulk send rate-limited — next bulk available in ${human}.`, { duration: 8000 });
        return;
      }
      // WEB-UIUX-1511: segment-drift 409 ("Segment changed since preview").
      // Clear the stale preview + auto-issue a fresh preview so the admin
      // sees the new count and can re-confirm. Avoid the infinite-loop
      // where Send → 409 → toast → Send → 409 trapped the previous flow.
      if (status === 409 && /segment changed/i.test(raw)) {
        toast.error('Audience changed since preview — refreshing recipient count.', { duration: 6000 });
        setPreview(null);
        setPreviewedAt(null);
        if (templateId) previewMut.mutate();
        return;
      }
      toast.error(raw || 'Bulk send failed');
    },
  });

  // WEB-UIUX-1117: poll the active job every 2s; stop when terminal.
  useEffect(() => {
    if (!jobId) return;
    let stopped = false;
    let timer: ReturnType<typeof setTimeout> | null = null;
    async function tick() {
      if (stopped) return;
      try {
        const res = await api.get<{ success: boolean; data: JobProgress }>(`/inbox/bulk-send/jobs/${jobId}`);
        if (stopped) return;
        const job = res.data?.data;
        if (job) {
          setJobProgress(job);
          if (job.status === 'completed' || job.status === 'aborted' || job.status === 'failed') {
            stopped = true;
            const verb = job.status === 'completed' ? 'completed' : job.status === 'aborted' ? 'aborted' : 'failed';
            toast.success(`Bulk send ${verb}: ${job.sent} sent, ${job.failed} failed${job.status === 'aborted' ? ` of ${job.total}` : ''}.`);
            return;
          }
        }
      } catch (err) {
        // Transient error — keep polling.
        // eslint-disable-next-line no-console
        console.warn('[BulkSmsModal] poll failed', err);
      }
      if (!stopped) timer = setTimeout(tick, 2000);
    }
    void tick();
    return () => {
      stopped = true;
      if (timer) clearTimeout(timer);
    };
  }, [jobId]);

  async function handleAbort() {
    if (!jobId || aborting) return;
    setAborting(true);
    try {
      await api.post<{ success: boolean }>(`/inbox/bulk-send/jobs/${jobId}/abort`);
      toast('Abort requested — finishing in-flight send.');
    } catch (e) {
      const msg = (e as { response?: { data?: { message?: string } } })?.response?.data?.message
        ?? 'Could not abort job.';
      toast.error(msg);
    } finally {
      setAborting(false);
    }
  }

  function clearJob() {
    setJobId(null);
    setJobProgress(null);
    setTemplateId(null);
    onClose();
  }

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

  // WEB-UIUX-869: minimized chip. When a preview is active and the user
  // minimizes, render a non-blocking fixed chip in the lower right with
  // recipient count + countdown + Reopen button. The CommunicationPage
  // behind it is fully interactive so the operator can answer inbound
  // SMS during the 5-min token window without losing the token.
  if (minimized && preview) {
    const mins = Math.floor(countdown / 60);
    const secs = countdown % 60;
    return (
      <div
        role="region"
        aria-label="Bulk SMS in progress (minimized)"
        className="fixed bottom-4 right-4 z-50 flex items-center gap-3 rounded-lg border border-amber-300 bg-amber-50 px-3 py-2 shadow-lg dark:border-amber-700 dark:bg-amber-900/40"
      >
        <Users className="h-4 w-4 text-amber-700 dark:text-amber-300" aria-hidden="true" />
        <div className="flex flex-col text-xs">
          <span className="font-medium text-amber-900 dark:text-amber-100">
            Bulk SMS · {preview.preview_count} recipients
          </span>
          <span className="text-amber-700 dark:text-amber-300 tabular-nums">
            {countdown > 0
              ? `Token expires in ${String(mins).padStart(2, '0')}:${String(secs).padStart(2, '0')}`
              : 'Confirmation expired — reopen to re-preview'}
          </span>
        </div>
        <button
          type="button"
          onClick={() => setMinimized(false)}
          className="rounded-md bg-amber-600 px-2 py-1 text-xs font-semibold text-white hover:bg-amber-700"
        >
          Reopen
        </button>
        <button
          type="button"
          aria-label="Cancel bulk SMS"
          onClick={() => {
            setMinimized(false);
            setPreview(null);
            setPreviewedAt(null);
            onClose();
          }}
          className="rounded p-1 text-amber-700 hover:bg-amber-100 dark:text-amber-300 dark:hover:bg-amber-900"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="bulk-sms-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={preview ? undefined : onClose}
    >
      {/* WEB-UIUX-1521: dialogRef wires the focus trap to this container */}
      <div
        ref={dialogRef}
        className="w-full max-w-md rounded-xl bg-white shadow-2xl dark:bg-surface-800"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 id="bulk-sms-title" className="flex items-center gap-2 text-lg font-semibold text-surface-900 dark:text-surface-100">
            <Users className="h-5 w-5 text-primary-500" />
            Bulk SMS
          </h3>
          <div className="flex items-center gap-1">
            {/* WEB-UIUX-869: Minimize collapses to a chip so the cashier
                can answer inbound SMS without burning the 5-min preview
                token. Visible only once a preview exists. */}
            {preview && (
              <button
                onClick={() => setMinimized(true)}
                aria-label="Minimize"
                title="Minimize — keep the preview token alive while answering inbound SMS"
                className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700"
              >
                <Minus className="h-5 w-5 text-surface-500" />
              </button>
            )}
            <button
              onClick={onClose}
              aria-label="Close"
              className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700"
            >
              <X className="h-5 w-5 text-surface-500" />
            </button>
          </div>
        </div>

        <div className="space-y-3 p-4">
          {/* WEB-UIUX-1117: in-flight job view — replaces the form once the
              server returns a job_id. Polls every 2s, surfaces a progress
              bar + Abort. */}
          {jobProgress ? (
            <div className="space-y-3">
              <div>
                <p className="text-sm font-medium">
                  Sending bulk SMS — {jobProgress.sent} sent
                  {jobProgress.failed > 0 ? `, ${jobProgress.failed} failed` : ''} of {jobProgress.total}
                </p>
                <div className="mt-2 h-2 w-full overflow-hidden rounded-full bg-surface-200 dark:bg-surface-700">
                  <div
                    className={`h-full transition-all ${jobProgress.status === 'aborted' ? 'bg-amber-500' : jobProgress.status === 'failed' ? 'bg-red-500' : 'bg-primary-500'}`}
                    style={{ width: `${jobProgress.total > 0 ? Math.min(100, ((jobProgress.sent + jobProgress.failed) / jobProgress.total) * 100) : 0}%` }}
                  />
                </div>
                <p className="mt-1 text-xs text-surface-500">
                  Status: <b>{jobProgress.status}</b>
                  {jobProgress.abort_requested && jobProgress.status === 'running' ? ' (abort requested — finishing in-flight send)' : ''}
                </p>
              </div>
              {jobProgress.last_error && (
                <div role="alert" className="rounded-md border border-red-200 bg-red-50 p-2 text-xs text-red-700 dark:border-red-500/30 dark:bg-red-500/10 dark:text-red-300">
                  {jobProgress.last_error}
                </div>
              )}
              <div className="flex justify-end gap-2">
                {jobProgress.status === 'running' && !jobProgress.abort_requested && (
                  <button
                    type="button"
                    onClick={handleAbort}
                    disabled={aborting}
                    className="rounded-md border border-amber-300 bg-amber-50 px-3 py-1.5 text-sm font-medium text-amber-800 hover:bg-amber-100 disabled:opacity-60 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300"
                  >
                    {aborting ? 'Requesting abort…' : 'Abort send'}
                  </button>
                )}
                {(jobProgress.status === 'completed' || jobProgress.status === 'aborted' || jobProgress.status === 'failed') && (
                  <button
                    type="button"
                    onClick={clearJob}
                    className="rounded-md bg-primary-600 px-3 py-1.5 text-sm font-medium text-white hover:bg-primary-700"
                  >
                    Close
                  </button>
                )}
              </div>
            </div>
          ) : <>
          {/* WEB-UIUX-1115: Consent-scope banner so admins know counts are opt-in filtered */}
          <p className="text-xs text-surface-500">Recipient counts include only customers who opted in to marketing SMS.</p>
          <div>
            <label className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300">
              Segment
            </label>
            <div role="radiogroup" aria-label="Recipient segment" className="space-y-1">
              {SEGMENTS.map((s, i) => (
                <button
                  key={s.value}
                  type="button"
                  role="radio"
                  aria-checked={segment === s.value}
                  tabIndex={segment === s.value ? 0 : -1}
                  // WEB-UIUX-1521: autoFocus on first button so keyboard users land inside the trap immediately
                  autoFocus={i === 0}
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
                  <div className="flex items-center justify-between gap-2">
                    <div className="font-medium text-surface-900 dark:text-surface-100">
                      {s.label}
                    </div>
                    {/* WEB-UIUX-1512: per-segment count chip so admin sees
                        audience size before committing to a segment. Hidden
                        while the counts query is in flight (renders the
                        previous selection's label cleanly during initial
                        modal open). */}
                    {segmentCounts && (
                      <span className="rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-semibold tabular-nums text-surface-600 dark:bg-surface-700 dark:text-surface-300">
                        {segmentCounts[s.value].toLocaleString()}
                      </span>
                    )}
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
            {/* WEB-UIUX-1112: render the resolved template body + segment math
                so the admin sees the exact text + cost before blasting. */}
            {(() => {
              if (!templateId) return null;
              const tpl = templates.find((t) => t.id === templateId);
              if (!tpl) return null;
              const body = tpl.content || '';
              const chars = body.length;
              // GSM-7 single-segment = 160 chars; multi-segment = 153 each.
              // Unicode (emoji) would be 70/67 but we under-count here — server
              // is the source of truth on cost; this is a guidance heuristic.
              const segments = chars === 0 ? 0 : chars <= 160 ? 1 : Math.ceil(chars / 153);
              return (
                <div className="mt-2 rounded-lg border border-surface-200 bg-surface-50 p-2 text-xs dark:border-surface-700 dark:bg-surface-900/40">
                  <div className="mb-1 flex items-center justify-between gap-2 text-[11px] uppercase tracking-wide text-surface-500">
                    <span>Body preview</span>
                    <span>{chars} chars · {segments} segment{segments === 1 ? '' : 's'}/recipient</span>
                  </div>
                  <pre className="whitespace-pre-wrap break-words font-sans text-sm text-surface-800 dark:text-surface-200">{body || <span className="italic text-surface-400">No body set on this template.</span>}</pre>
                </div>
              );
            })()}
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
              {/*
                * WEB-UIUX-1124: Live countdown replaces static "5 minutes" copy.
                * WEB-UIUX-1523: Static "Confirmation expires in 5 minutes" was inaccurate;
                *   the live MM:SS timer below is already truthful — no copy change needed.
                *   (Re-preview prompt on expiry also satisfies the "wait longer" guidance.)
                */}
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
          {/* WEB-UIUX-1113: masked sample recipients so operator sanity-checks WHO. */}
          {preview && preview.sample_phones && preview.sample_phones.length > 0 && (
            <div className="rounded-lg border border-surface-200 bg-surface-50 p-2 text-xs dark:border-surface-700 dark:bg-surface-800/50">
              <p className="font-medium text-surface-700 dark:text-surface-300 mb-1">
                Sample recipients (first {preview.sample_phones.length} of {preview.preview_count})
              </p>
              <ul className="space-y-0.5 font-mono text-surface-600 dark:text-surface-400">
                {preview.sample_phones.map((p, i) => (
                  <li key={i}>· {p.masked}</li>
                ))}
              </ul>
            </div>
          )}
          {/* WEB-UIUX-1517: surface remaining hourly quota so the admin sees
              why a 4th send returns 429 instead of being surprised by it. */}
          {preview && preview.quota && (
            <BulkSendQuotaLine quota={preview.quota} />
          )}
          {/* WEB-UIUX-1510: surface provider configuration BEFORE Send. When
              real=false, simulated/no-op provider is configured, so the blast
              would either go nowhere or queue in retry. Banner makes the
              cause visible while still letting admin sanity-check audience
              size; Send is gated below. */}
          {preview && preview.provider && !preview.provider.real && (
            <div
              role="alert"
              className="rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs text-amber-800 dark:border-amber-500/30 dark:bg-amber-500/10 dark:text-amber-300"
            >
              <p className="font-medium">SMS provider not configured</p>
              <p className="mt-0.5">
                Current provider ({preview.provider.name ?? 'simulated'}) does
                not actually deliver SMS. Configure a real provider in
                Settings → SMS before sending; Send is disabled until then.
              </p>
            </div>
          )}
          </>}
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
              {/* WEB-UIUX-1513: typed-confirm above threshold so single-
                  click doesn't blast 12k recipients. Type the recipient
                  count to enable the Send button. */}
              {preview.preview_count >= 100 ? (
                <div className="flex items-center gap-2">
                  <input
                    type="text"
                    inputMode="numeric"
                    placeholder={`Type ${preview.preview_count}`}
                    value={typedConfirm}
                    onChange={(e) => setTypedConfirm(e.target.value.replace(/[^0-9]/g, ''))}
                    aria-label={`Type ${preview.preview_count} to confirm`}
                    className="w-32 rounded border border-surface-300 bg-white px-2 py-1 text-xs dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100"
                  />
                  <button
                    onClick={() => sendMut.mutate()}
                    disabled={
                      sendMut.isPending
                      || preview.preview_count === 0
                      || countdown === 0
                      || typedConfirm !== String(preview.preview_count)
                      || preview.provider?.real === false
                    }
                    title={
                      preview.provider?.real === false
                        ? 'Configure a real SMS provider in Settings → SMS before sending'
                        : countdown === 0
                          ? 'Confirmation expired — please re-preview'
                          : typedConfirm !== String(preview.preview_count)
                            ? `Type ${preview.preview_count} to confirm`
                            : undefined
                    }
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                  >
                    <Send className="h-3.5 w-3.5" />
                    {sendMut.isPending ? 'Sending…' : `Send to ${preview.preview_count}`}
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => sendMut.mutate()}
                  disabled={sendMut.isPending || preview.preview_count === 0 || countdown === 0 || preview.provider?.real === false}
                  title={
                    preview.provider?.real === false
                      ? 'Configure a real SMS provider in Settings → SMS before sending'
                      : countdown === 0 ? 'Confirmation expired — please re-preview' : undefined
                  }
                  // WEB-UIUX-1116: drop red (destructive) — sending an opted-in
                  // marketing reminder is additive, not destructive. Primary
                  // tone matches Stripe/Klaviyo confident-send buttons; the
                  // explicit "Send to N" label already carries blast-radius.
                  className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                >
                  <Send className="h-3.5 w-3.5" />
                  {sendMut.isPending ? 'Sending…' : `Send to ${preview.preview_count}`}
                </button>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

/**
 * WEB-UIUX-1517: live hourly quota line. Server reports the absolute
 * reset_at; the component ticks once per second so the countdown stays
 * truthful without the parent re-rendering on every tick.
 */
function BulkSendQuotaLine({ quota }: { quota: NonNullable<PreviewResponse['quota']> }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    if (!quota.reset_at) return;
    const t = window.setInterval(() => setNow(Date.now()), 1000);
    return () => window.clearInterval(t);
  }, [quota.reset_at]);

  const remaining = Math.max(0, quota.max - quota.used);
  const resetMs = quota.reset_at ? new Date(quota.reset_at).getTime() : null;
  const secondsToReset = resetMs ? Math.max(0, Math.floor((resetMs - now) / 1000)) : null;
  const mm = secondsToReset != null ? String(Math.floor(secondsToReset / 60)).padStart(2, '0') : null;
  const ss = secondsToReset != null ? String(secondsToReset % 60).padStart(2, '0') : null;
  const exhausted = remaining === 0;

  return (
    <div
      className={
        exhausted
          ? 'rounded-lg border border-amber-300 bg-amber-50 p-2 text-xs dark:border-amber-500/30 dark:bg-amber-500/10'
          : 'rounded-lg border border-surface-200 bg-surface-50 p-2 text-xs dark:border-surface-700 dark:bg-surface-800/50'
      }
    >
      <p
        className={
          exhausted
            ? 'font-medium text-amber-800 dark:text-amber-300'
            : 'font-medium text-surface-700 dark:text-surface-300'
        }
      >
        Bulk sends this hour: {quota.used} of {quota.max} used
        {secondsToReset != null && secondsToReset > 0 && (
          <> · resets in {mm}:{ss}</>
        )}
        {exhausted && (
          <> — wait for the window to reset before sending.</>
        )}
      </p>
    </div>
  );
}
