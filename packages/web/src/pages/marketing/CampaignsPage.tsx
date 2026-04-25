import { useEffect, useRef, useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Megaphone,
  Plus,
  Play,
  Eye,
  BarChart3,
  Mail,
  MessageSquare,
  Trash2,
  Pause,
  CircleCheck,
  CircleSlash,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { campaignsApi, crmApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { ConfirmDialog } from '@/components/shared/ConfirmDialog';
import { formatDateTime } from '@/utils/format';

/**
 * CampaignsPage — marketing automation dashboard.
 *
 * Lists all marketing_campaigns rows with status pill, type, channel, and
 * lifetime sent/reply/convert counts. Supports:
 *   - Create campaign modal (name/type/channel/segment/template)
 *   - Preview (dry-run) showing recipient count + sample rendered body
 *   - Run now (dispatches to eligible segment members immediately)
 *   - Toggle status draft → active → paused → archived
 *   - Delete
 *
 * Respects TCPA — server filters to sms_opt_in/email_opt_in. Frontend just
 * shows counts and reflects the server-side totals.
 */

interface Campaign {
  id: number;
  name: string;
  type: string;
  channel: 'sms' | 'email' | 'both';
  segment_id: number | null;
  template_subject: string | null;
  template_body: string;
  trigger_rule_json: string | null;
  status: 'draft' | 'active' | 'paused' | 'archived';
  sent_count: number;
  replied_count: number;
  converted_count: number;
  created_at: string;
  last_run_at: string | null;
}

interface Segment {
  id: number;
  name: string;
  member_count: number;
}

const TYPES: ReadonlyArray<{ value: string; label: string }> = [
  { value: 'birthday', label: 'Birthday' },
  { value: 'winback', label: 'Win-back' },
  { value: 'review_request', label: 'Review request' },
  { value: 'churn_warning', label: 'Churn warning' },
  { value: 'service_subscription', label: 'Subscription' },
  { value: 'custom', label: 'Custom' },
];

// WEB-FK-007 / FIXED-by-Fixer-A9 2026-04-25 — TCPA/CAN-SPAM client-side guard.
// SMS bodies must contain a recognizable opt-out phrase; email bodies must
// reference the {{unsubscribe_url}} merge token so the dispatcher can render
// a real link. Mirrors what the server should also enforce (defense in depth)
// but stops the most common operator mistake — a clean-looking promo with
// zero opt-out path — at draft time, before a Run-now click sends thousands.
function templateBodyIsCompliant(body: string, channel: 'sms' | 'email' | 'both'): boolean {
  if (!body.trim()) return false;
  const needsSms = channel === 'sms' || channel === 'both';
  const needsEmail = channel === 'email' || channel === 'both';
  if (needsSms && !/(reply\s+stop|text\s+stop|stop\s+to\s+(opt\s*out|unsubscribe))/i.test(body)) {
    return false;
  }
  if (needsEmail && !body.includes('{{unsubscribe_url}}')) {
    return false;
  }
  return true;
}

const STATUS_STYLES: Record<Campaign['status'], string> = {
  draft: 'bg-surface-100 text-surface-600 dark:bg-surface-800 dark:text-surface-300',
  active: 'bg-emerald-100 text-emerald-700 dark:bg-emerald-900/30 dark:text-emerald-300',
  paused: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-300',
  archived: 'bg-surface-200 text-surface-500 dark:bg-surface-800 dark:text-surface-500',
};

export function CampaignsPage() {
  const queryClient = useQueryClient();
  const [showCreate, setShowCreate] = useState(false);
  const [previewData, setPreviewData] = useState<{ campaign: Campaign; total: number; sample: Array<{ rendered_body: string }> } | null>(null);
  // Confirm dialogs for destructive actions — Run-now dispatches the segment
  // immediately to potentially thousands of recipients, and Delete is final.
  const [runConfirm, setRunConfirm] = useState<{ campaign: Campaign; total: number | null } | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<Campaign | null>(null);
  // WEB-FK-017 (Fixer-TTT 2026-04-25): keep a handle on the in-flight Run-now
  // recipient-count preview so cancelling the confirm dialog (or clicking
  // Run-now on a different campaign) aborts the previous request instead of
  // letting it finish and overwrite state. Server-side preview can spin up
  // significant DB work on a 2000-customer segment; aborting prevents waste
  // and the late-arriving-A-overwrites-B race.
  const runPreviewAbortRef = useRef<AbortController | null>(null);

  const { data: campaignsRes, isLoading } = useQuery<{ data?: Campaign[] }>({
    queryKey: ['campaigns'],
    queryFn: async () => {
      const res = await campaignsApi.list();
      return res.data as { data?: Campaign[] };
    },
    staleTime: 30_000,
  });

  const { data: segmentsRes } = useQuery<{ data?: Segment[] }>({
    queryKey: ['crm', 'segments'],
    queryFn: async () => {
      const res = await crmApi.listSegments();
      return res.data as { data?: Segment[] };
    },
    staleTime: 30_000,
  });

  const campaigns: Campaign[] = campaignsRes?.data ?? [];
  const segments: Segment[] = segmentsRes?.data ?? [];

  const runNow = useMutation({
    mutationFn: async (id: number) => {
      const res = await campaignsApi.runNow(id);
      return res.data;
    },
    onSuccess: (data) => {
      const d: any = (data as any)?.data ?? {};
      toast.success(`Dispatched: ${d.sent ?? 0} sent, ${d.failed ?? 0} failed`);
      queryClient.invalidateQueries({ queryKey: ['campaigns'] });
    },
    onError: () => toast.error('Failed to dispatch campaign'),
  });

  const deleteCampaign = useMutation({
    mutationFn: async (id: number) => {
      await campaignsApi.delete(id);
    },
    onSuccess: () => {
      toast.success('Campaign deleted');
      queryClient.invalidateQueries({ queryKey: ['campaigns'] });
    },
    onError: () => toast.error('Failed to delete'),
  });

  const updateStatus = useMutation({
    mutationFn: async ({ id, status }: { id: number; status: Campaign['status'] }) => {
      await campaignsApi.update(id, { status });
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['campaigns'] });
    },
    // WEB-FF-005 (Fixer-UU 2026-04-25): pause/resume failures used to be silent
    // — operator saw a stale list with no feedback. Surface server rejection
    // (rate-limit, segment deleted, validation error) via toast.
    onError: (err: any) => {
      // WEB-FC-019 (Fixer-KKK 2026-04-25): server returns descriptive errors
      // under .message (per shared httpError helper); .error was a legacy field
      // that no longer ships, so toasts always fell back to the generic string.
      toast.error(err?.response?.data?.message ?? err?.response?.data?.error ?? 'Failed to update campaign status');
    },
  });

  const preview = useMutation({
    mutationFn: async (campaign: Campaign) => {
      const res = await campaignsApi.preview(campaign.id);
      return { campaign, data: res.data };
    },
    onSuccess: ({ campaign, data }) => {
      const d: any = (data as any)?.data ?? {};
      setPreviewData({
        campaign,
        total: d.total_recipients ?? 0,
        sample: d.preview ?? [],
      });
    },
    onError: () => toast.error('Failed to preview'),
  });

  return (
    <div className="max-w-6xl mx-auto">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-3">
            <Megaphone className="h-6 w-6 text-primary-600 dark:text-primary-400" />
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">
              Marketing Campaigns
            </h1>
          </div>
          <p className="text-sm text-surface-500 mt-1">
            Birthday, win-back, review requests, churn warnings, and more — all TCPA-compliant.
          </p>
        </div>
        <button
          onClick={() => setShowCreate(true)}
          className="inline-flex items-center gap-2 px-4 py-2 bg-primary-600 hover:bg-primary-700 text-white rounded-lg font-medium shadow-sm"
        >
          <Plus className="h-4 w-4" /> New campaign
        </button>
      </header>

      {isLoading ? (
        <div className="text-center py-12 text-surface-500">Loading campaigns...</div>
      ) : campaigns.length === 0 ? (
        <div className="text-center py-16 text-surface-500 bg-white dark:bg-surface-900 rounded-xl border border-dashed border-surface-300 dark:border-surface-700">
          <Megaphone className="mx-auto h-10 w-10 mb-3 opacity-40" />
          <p>No campaigns yet. Create one to get started.</p>
        </div>
      ) : (
        <div className="space-y-3">
          {campaigns.map((campaign) => {
            const segment = segments.find((s) => s.id === campaign.segment_id);
            return (
              <div
                key={campaign.id}
                className="bg-white dark:bg-surface-900 rounded-xl border border-surface-200 dark:border-surface-700 p-4"
              >
                <div className="flex items-start justify-between gap-4">
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2 mb-1">
                      <h3 className="font-semibold text-surface-900 dark:text-surface-100 truncate">
                        {campaign.name}
                      </h3>
                      <span className={cn(
                        'inline-flex items-center px-2 py-0.5 rounded-full text-[10px] uppercase tracking-wide font-medium',
                        STATUS_STYLES[campaign.status],
                      )}>
                        {campaign.status}
                      </span>
                      <span className="inline-flex items-center gap-1 text-[11px] text-surface-500">
                        {campaign.channel === 'email' ? <Mail className="h-3 w-3" /> : <MessageSquare className="h-3 w-3" />}
                        {campaign.channel}
                      </span>
                    </div>
                    <p className="text-xs text-surface-500 dark:text-surface-400">
                      {TYPES.find((t) => t.value === campaign.type)?.label ?? campaign.type}
                      {segment && <span> · segment: <strong>{segment.name}</strong> ({segment.member_count})</span>}
                    </p>
                    <p className="text-xs text-surface-600 dark:text-surface-400 mt-2 line-clamp-2">
                      {campaign.template_body}
                    </p>
                    <div className="flex items-center gap-4 mt-2 text-[11px] text-surface-500">
                      <span><strong>{campaign.sent_count}</strong> sent</span>
                      <span><strong>{campaign.replied_count}</strong> replied</span>
                      <span><strong>{campaign.converted_count}</strong> converted</span>
                      {campaign.last_run_at && (
                        <span>last run {formatDateTime(campaign.last_run_at)}</span>
                      )}
                    </div>
                  </div>
                  <div className="flex flex-col gap-2 flex-shrink-0">
                    <button
                      onClick={() => preview.mutate(campaign)}
                      disabled={preview.isPending}
                      className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg border border-surface-200 hover:bg-surface-50 dark:border-surface-700 dark:hover:bg-surface-800"
                    >
                      <Eye className="h-3 w-3" /> Preview
                    </button>
                    <button
                      onClick={async () => {
                        // Open confirm dialog with a recipient-count preview so the
                        // operator sees how many people will be messaged before firing.
                        setRunConfirm({ campaign, total: null });
                        // WEB-FK-017: abort any prior in-flight preview before starting a new one.
                        runPreviewAbortRef.current?.abort();
                        const ac = new AbortController();
                        runPreviewAbortRef.current = ac;
                        try {
                          const res = await campaignsApi.preview(campaign.id, { signal: ac.signal });
                          if (ac.signal.aborted) return;
                          const total = (res.data as any)?.data?.total_recipients ?? 0;
                          // Only update if user hasn't already cancelled.
                          setRunConfirm((curr) => (curr && curr.campaign.id === campaign.id ? { campaign, total } : curr));
                        } catch (err: any) {
                          if (ac.signal.aborted || err?.name === 'CanceledError' || err?.name === 'AbortError') return;
                          setRunConfirm((curr) => (curr && curr.campaign.id === campaign.id ? { campaign, total: 0 } : curr));
                        }
                      }}
                      disabled={runNow.isPending || campaign.status === 'archived'}
                      className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg bg-primary-600 hover:bg-primary-700 text-white disabled:opacity-40"
                    >
                      <Play className="h-3 w-3" /> Run now
                    </button>
                    {campaign.status === 'draft' || campaign.status === 'paused' ? (
                      <button
                        onClick={() => updateStatus.mutate({ id: campaign.id, status: 'active' })}
                        disabled={updateStatus.isPending && updateStatus.variables?.id === campaign.id}
                        className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg text-emerald-700 hover:bg-emerald-50 dark:text-emerald-300 dark:hover:bg-emerald-900/20 disabled:opacity-50"
                      >
                        <CircleCheck className="h-3 w-3" /> Activate
                      </button>
                    ) : campaign.status === 'active' ? (
                      <button
                        onClick={() => updateStatus.mutate({ id: campaign.id, status: 'paused' })}
                        disabled={updateStatus.isPending && updateStatus.variables?.id === campaign.id}
                        className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg text-amber-700 hover:bg-amber-50 dark:text-amber-300 dark:hover:bg-amber-900/20 disabled:opacity-50"
                      >
                        <Pause className="h-3 w-3" /> Pause
                      </button>
                    ) : (
                      <button
                        onClick={() => updateStatus.mutate({ id: campaign.id, status: 'draft' })}
                        disabled={updateStatus.isPending && updateStatus.variables?.id === campaign.id}
                        className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg text-surface-600 hover:bg-surface-50 dark:text-surface-300 dark:hover:bg-surface-800 disabled:opacity-50"
                      >
                        <CircleSlash className="h-3 w-3" /> Restore
                      </button>
                    )}
                    <button
                      onClick={() => setDeleteConfirm(campaign)}
                      disabled={deleteCampaign.isPending && deleteCampaign.variables === campaign.id}
                      className="inline-flex items-center gap-1 px-3 py-1.5 text-xs rounded-lg text-red-600 hover:bg-red-50 dark:text-red-400 dark:hover:bg-red-900/20 disabled:opacity-50"
                    >
                      <Trash2 className="h-3 w-3" /> Delete
                    </button>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      )}

      {showCreate && (
        <CreateCampaignModal
          segments={segments}
          onClose={() => setShowCreate(false)}
          onCreated={() => {
            setShowCreate(false);
            queryClient.invalidateQueries({ queryKey: ['campaigns'] });
          }}
        />
      )}

      {previewData && (
        <PreviewModal
          data={previewData}
          onClose={() => setPreviewData(null)}
        />
      )}

      <ConfirmDialog
        open={!!runConfirm}
        title="Dispatch campaign now?"
        message={
          runConfirm
            ? runConfirm.total === null
              ? `Counting eligible recipients for "${runConfirm.campaign.name}"…`
              : `This will immediately send "${runConfirm.campaign.name}" via ${runConfirm.campaign.channel.toUpperCase()} to ${runConfirm.total} eligible recipient${runConfirm.total === 1 ? '' : 's'} (after opt-in filtering). This cannot be undone.`
            : ''
        }
        confirmLabel="Dispatch now"
        cancelLabel="Cancel"
        danger
        onConfirm={() => {
          if (runConfirm) runNow.mutate(runConfirm.campaign.id);
          runPreviewAbortRef.current?.abort();
          setRunConfirm(null);
        }}
        onCancel={() => {
          // WEB-FK-017: abort the preview round-trip on cancel so we don't
          // pay for a potentially-expensive recipient-count the user no longer needs.
          runPreviewAbortRef.current?.abort();
          setRunConfirm(null);
        }}
      />

      <ConfirmDialog
        open={!!deleteConfirm}
        title="Delete campaign?"
        message={
          deleteConfirm
            ? `Permanently delete "${deleteConfirm.name}"? This cannot be undone.`
            : ''
        }
        confirmLabel="Delete"
        cancelLabel="Cancel"
        danger
        onConfirm={() => {
          if (deleteConfirm) deleteCampaign.mutate(deleteConfirm.id);
          setDeleteConfirm(null);
        }}
        onCancel={() => setDeleteConfirm(null)}
      />
    </div>
  );
}

interface CreateProps {
  segments: Segment[];
  onClose: () => void;
  onCreated: () => void;
}

function CreateCampaignModal({ segments, onClose, onCreated }: CreateProps) {
  const [form, setForm] = useState({
    name: '',
    type: 'custom',
    channel: 'sms' as 'sms' | 'email' | 'both',
    segment_id: '' as string,
    template_subject: '',
    template_body: '',
  });

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  const create = useMutation({
    mutationFn: async () => {
      const payload: any = {
        name: form.name,
        type: form.type,
        channel: form.channel,
        template_body: form.template_body,
      };
      if (form.template_subject.trim()) payload.template_subject = form.template_subject.trim();
      if (form.segment_id) payload.segment_id = Number(form.segment_id);
      const res = await campaignsApi.create(payload);
      return res.data;
    },
    onSuccess: () => {
      toast.success('Campaign created');
      onCreated();
    },
    onError: (err: any) => {
      // WEB-FC-019 (Fixer-KKK 2026-04-25): prefer .message; .error kept as fallback.
      toast.error(err?.response?.data?.message ?? err?.response?.data?.error ?? 'Failed to create campaign');
    },
  });

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="new-campaign-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-xl max-w-lg w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <h2 id="new-campaign-title" className="text-lg font-bold text-surface-900 dark:text-surface-100">New campaign</h2>

        <div>
          <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Name</label>
          <input
            value={form.name}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
            placeholder="e.g. Summer screen protector promo"
            className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
          />
        </div>

        <div className="grid grid-cols-2 gap-3">
          <div>
            <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Type</label>
            <select
              value={form.type}
              onChange={(e) => setForm({ ...form, type: e.target.value })}
              className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
            >
              {TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Channel</label>
            <select
              value={form.channel}
              onChange={(e) => setForm({ ...form, channel: e.target.value as 'sms' | 'email' | 'both' })}
              className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
            >
              <option value="sms">SMS</option>
              <option value="email">Email</option>
              <option value="both">Both</option>
            </select>
          </div>
        </div>

        <div>
          <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Segment (optional)</label>
          <select
            value={form.segment_id}
            onChange={(e) => setForm({ ...form, segment_id: e.target.value })}
            className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
          >
            <option value="">(All eligible customers)</option>
            {segments.map((s) => (
              <option key={s.id} value={String(s.id)}>
                {s.name} ({s.member_count})
              </option>
            ))}
          </select>
        </div>

        {(form.channel === 'email' || form.channel === 'both') && (
          <div>
            <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Email subject</label>
            <input
              value={form.template_subject}
              onChange={(e) => setForm({ ...form, template_subject: e.target.value })}
              className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm"
            />
          </div>
        )}

        <div>
          <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">
            Template body — use {'{{first_name}}'} for merge tags
          </label>
          <textarea
            value={form.template_body}
            onChange={(e) => setForm({ ...form, template_body: e.target.value })}
            rows={4}
            placeholder={
              form.channel === 'email'
                ? 'Hi {{first_name}}, we miss you! Come visit for 15% off.\n\nUnsubscribe: {{unsubscribe_url}}'
                : 'Hi {{first_name}}, 15% off this week. Reply STOP to opt out.'
            }
            className="w-full px-3 py-2 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-sm font-mono"
          />
          {/* WEB-FK-007 / FIXED-by-Fixer-A9 2026-04-25 — block save when the
              template lacks the channel-specific opt-out path. Server still
              validates, but a missing footer should never even *attempt* a
              send: TCPA fines run $500–$1500/text and CAN-SPAM is $51,744/email,
              so we fail fast in-modal with explicit helper text rather than
              hoping operators read the placeholder. */}
          {(() => {
            const body = form.template_body;
            if (!body.trim()) return null;
            const errors: string[] = [];
            const needsSms = form.channel === 'sms' || form.channel === 'both';
            const needsEmail = form.channel === 'email' || form.channel === 'both';
            if (needsSms && !/(reply\s+stop|text\s+stop|stop\s+to\s+(opt\s*out|unsubscribe))/i.test(body)) {
              errors.push('SMS templates must include "Reply STOP" (TCPA opt-out instructions).');
            }
            if (needsEmail && !body.includes('{{unsubscribe_url}}')) {
              errors.push('Email templates must include the {{unsubscribe_url}} merge token (CAN-SPAM).');
            }
            if (errors.length === 0) return null;
            return (
              <ul className="mt-2 text-xs text-amber-700 dark:text-amber-300 list-disc pl-5 space-y-0.5">
                {errors.map((err) => <li key={err}>{err}</li>)}
              </ul>
            );
          })()}
          <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
            Required tokens: {form.channel === 'sms' ? '"Reply STOP"' : form.channel === 'email' ? '{{unsubscribe_url}}' : '"Reply STOP" (SMS) and {{unsubscribe_url}} (email)'}.
          </p>
        </div>

        <div className="flex justify-end gap-2 pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg border border-surface-200 dark:border-surface-700 hover:bg-surface-50 dark:hover:bg-surface-800"
          >
            Cancel
          </button>
          <button
            onClick={() => create.mutate()}
            disabled={create.isPending || !form.name.trim() || !templateBodyIsCompliant(form.template_body, form.channel)}
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 hover:bg-primary-700 text-white font-medium disabled:opacity-50"
          >
            Create
          </button>
        </div>
      </div>
    </div>
  );
}

interface PreviewProps {
  data: { campaign: Campaign; total: number; sample: Array<{ rendered_body: string }> };
  onClose: () => void;
}

function PreviewModal({ data, onClose }: PreviewProps) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose(); };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4"
      role="dialog"
      aria-modal="true"
      aria-labelledby="campaign-preview-title"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <div className="bg-white dark:bg-surface-900 rounded-xl max-w-lg w-full p-6 space-y-4" onClick={(e) => e.stopPropagation()}>
        <div>
          <h2 id="campaign-preview-title" className="text-lg font-bold text-surface-900 dark:text-surface-100 flex items-center gap-2">
            <BarChart3 className="h-5 w-5" /> Preview: {data.campaign.name}
          </h2>
          <p className="text-xs text-surface-500 mt-1">
            {data.total} eligible recipient{data.total === 1 ? '' : 's'} in the segment, after opt-in filtering.
          </p>
        </div>

        <div className="space-y-3">
          {data.sample.map((row, idx) => (
            <div key={idx} className="p-3 rounded-lg bg-surface-50 dark:bg-surface-800 text-sm font-mono whitespace-pre-wrap text-surface-700 dark:text-surface-200">
              {row.rendered_body}
            </div>
          ))}
          {data.sample.length === 0 && (
            <div className="text-center py-6 text-sm text-surface-500">
              No eligible recipients to preview.
            </div>
          )}
        </div>

        <div className="flex justify-end pt-2">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm rounded-lg bg-primary-600 text-white"
          >
            Close
          </button>
        </div>
      </div>
    </div>
  );
}
