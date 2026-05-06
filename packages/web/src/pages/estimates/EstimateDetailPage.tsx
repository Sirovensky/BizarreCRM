import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  ArrowLeft, Loader2, Printer, ArrowRightLeft, Send, Pencil, Save, X,
  CheckCircle, History, ChevronDown, ChevronUp, XCircle, Plus, Trash2,
  FileSignature, Link2,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { estimateApi } from '@/api/endpoints';
import type { EstimateSignature, EstimateSignPublicSummary } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';
import { formatCurrency, formatDate } from '@/utils/format';
import { Breadcrumb } from '@/components/shared/Breadcrumb';
import { CopyButton } from '@/components/shared/CopyButton';
import { SignatureCanvas } from '@/components/shared/SignatureCanvas';
import { useAuthStore } from '@/stores/authStore';
import { useEffect, useState } from 'react';

const STATUS_COLORS: Record<string, string> = {
  draft: '#6b7280',
  sent: '#3b82f6',
  approved: '#22c55e',
  signed: '#16a34a',
  rejected: '#ef4444',
  converted: '#8b5cf6',
};

const ESTIMATE_ACTION_BUTTON_CLASS =
  'inline-flex min-h-10 w-full items-center justify-center gap-2 whitespace-nowrap rounded-lg px-3 py-2 text-sm font-medium sm:w-auto sm:px-4';

// ENR-LE6 estimate version row — minimal shared shape (id + version + timestamp).
// Server returns more fields (snapshot blob, author, diff metadata) but the UI
// only renders the version number + created_at, so keep this narrow.
interface EstimateVersion {
  id: number;
  version_number: number;
  created_at: string;
}

interface EstimateSignSession {
  token: string;
  url: string;
  expiresAt: string;
}

function decodeUrlSegment(value: string): string {
  try {
    return decodeURIComponent(value);
  } catch {
    return value;
  }
}

function extractEstimateSignToken(url: string): string {
  try {
    const parsed = new URL(url, window.location.origin);
    const segment = parsed.pathname.split('/').filter(Boolean).pop() || '';
    return decodeUrlSegment(segment);
  } catch {
    const segment = url.split('?')[0]?.split('/').filter(Boolean).pop() || '';
    return decodeUrlSegment(segment);
  }
}

function SignatureRow({ signature }: { signature: EstimateSignature }) {
  return (
    <div className="rounded-lg border border-surface-200 p-3 text-sm dark:border-surface-700">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className="truncate font-medium text-surface-900 dark:text-surface-100">{signature.signer_name}</p>
          {signature.signer_email && (
            <p className="truncate text-xs text-surface-500 dark:text-surface-400">{signature.signer_email}</p>
          )}
        </div>
        <span className="shrink-0 text-xs text-surface-500 dark:text-surface-400">
          {formatDate(signature.signed_at)}
        </span>
      </div>
    </div>
  );
}

function EstimateSignDialog({
  session,
  fallbackEmail,
  onClose,
  onSigned,
}: {
  session: EstimateSignSession;
  fallbackEmail?: string | null;
  onClose: () => void;
  onSigned: () => void;
}) {
  const [signerName, setSignerName] = useState('');
  const [signerEmail, setSignerEmail] = useState(fallbackEmail || '');
  const [signatureDataUrl, setSignatureDataUrl] = useState('');

  const summaryQuery = useQuery({
    queryKey: ['estimate-sign-public-summary', session.token],
    queryFn: () => estimateApi.getSigningEstimate(session.token),
    retry: false,
  });
  const publicSummary: EstimateSignPublicSummary | undefined = summaryQuery.data?.data?.data;

  useEffect(() => {
    if (!signerName && publicSummary?.customer_name) {
      setSignerName(publicSummary.customer_name);
    }
  }, [publicSummary?.customer_name, signerName]);

  const submitMut = useMutation({
    mutationFn: () => estimateApi.submitSigningEstimate(session.token, {
      signer_name: signerName.trim(),
      signer_email: signerEmail.trim() || undefined,
      signature_data_url: signatureDataUrl,
    }),
    onSuccess: () => {
      toast.success('Estimate signed');
      onSigned();
    },
    onError: (err: any) => toast.error(formatApiError(err) || 'Failed to sign estimate'),
  });

  const handleSignatureSave = (dataUrl: string) => {
    if (
      dataUrl &&
      !dataUrl.startsWith('data:image/png;base64,') &&
      !dataUrl.startsWith('data:image/svg+xml;base64,')
    ) {
      setSignatureDataUrl('');
      toast.error('Signature is too large to save. Please clear it and try a simpler signature.');
      return;
    }
    setSignatureDataUrl(dataUrl);
  };

  const canSubmit =
    signerName.trim().length > 0 &&
    signatureDataUrl.length > 0 &&
    !summaryQuery.isLoading &&
    !summaryQuery.isError &&
    !submitMut.isPending;

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      role="presentation"
      onClick={() => {
        if (!submitMut.isPending) onClose();
      }}
    >
      <div
        role="dialog"
        aria-modal="true"
        aria-labelledby="estimate-sign-title"
        className="max-h-[90vh] w-full max-w-2xl overflow-y-auto rounded-xl border border-surface-200 bg-white p-6 shadow-2xl dark:border-surface-700 dark:bg-surface-900"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="mb-5 flex items-start justify-between gap-4">
          <div>
            <h2 id="estimate-sign-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
              Estimate signature
            </h2>
            <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
              Expires {formatDate(session.expiresAt)}
            </p>
          </div>
          <button
            type="button"
            aria-label="Close"
            onClick={onClose}
            disabled={submitMut.isPending}
            className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-600 disabled:opacity-50 dark:hover:bg-surface-800 dark:hover:text-surface-200"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="mb-5 rounded-lg border border-surface-200 bg-surface-50 p-3 dark:border-surface-700 dark:bg-surface-800/60">
          <div className="flex items-center gap-2 text-xs font-medium text-surface-500 dark:text-surface-400">
            <Link2 className="h-3.5 w-3.5" />
            <span className="truncate">{session.url}</span>
            <CopyButton text={session.url} />
          </div>
        </div>

        {summaryQuery.isLoading ? (
          <div className="flex justify-center py-10">
            <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
          </div>
        ) : summaryQuery.isError || !publicSummary ? (
          <div className="rounded-lg border border-red-200 bg-red-50 p-4 text-sm text-red-700 dark:border-red-900/50 dark:bg-red-950/30 dark:text-red-300">
            This signing link is no longer available.
          </div>
        ) : (
          <div className="space-y-5">
            <div className="grid gap-3 rounded-lg border border-surface-200 p-4 text-sm dark:border-surface-700 sm:grid-cols-3">
              <div>
                <p className="text-xs uppercase text-surface-500 dark:text-surface-400">Estimate</p>
                <p className="font-medium text-surface-900 dark:text-surface-100">{publicSummary.order_id}</p>
              </div>
              <div>
                <p className="text-xs uppercase text-surface-500 dark:text-surface-400">Customer</p>
                <p className="font-medium text-surface-900 dark:text-surface-100">{publicSummary.customer_name || 'Customer'}</p>
              </div>
              <div>
                <p className="text-xs uppercase text-surface-500 dark:text-surface-400">Total</p>
                <p className="font-medium text-surface-900 dark:text-surface-100">{formatCurrency(publicSummary.total || 0)}</p>
              </div>
            </div>

            <div className="grid gap-3 sm:grid-cols-2">
              <label className="block text-sm">
                <span className="mb-1 block font-medium text-surface-700 dark:text-surface-300">Signer name</span>
                <input
                  value={signerName}
                  onChange={(e) => setSignerName(e.target.value)}
                  className="input"
                  maxLength={200}
                />
              </label>
              <label className="block text-sm">
                <span className="mb-1 block font-medium text-surface-700 dark:text-surface-300">Signer email</span>
                <input
                  value={signerEmail}
                  onChange={(e) => setSignerEmail(e.target.value)}
                  className="input"
                  type="email"
                  maxLength={254}
                />
              </label>
            </div>

            <div>
              <p className="mb-2 text-sm font-medium text-surface-700 dark:text-surface-300">Signature</p>
              <SignatureCanvas onSave={handleSignatureSave} width={560} height={160} />
            </div>

            <div className="flex justify-end gap-2">
              <button
                type="button"
                onClick={onClose}
                disabled={submitMut.isPending}
                className="rounded-lg border border-surface-200 px-4 py-2 text-sm font-medium text-surface-700 hover:bg-surface-50 disabled:opacity-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800"
              >
                Cancel
              </button>
              <button
                type="button"
                onClick={() => submitMut.mutate()}
                disabled={!canSubmit}
                className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:cursor-not-allowed disabled:opacity-50"
              >
                {submitMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileSignature className="h-4 w-4" />}
                Save signature
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

export function EstimateDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const userRole = useAuthStore((s) => s.user?.role);
  const [editing, setEditing] = useState(false);
  const [notes, setNotes] = useState('');
  const [showVersions, setShowVersions] = useState(false);
  const [signSession, setSignSession] = useState<EstimateSignSession | null>(null);
  // WEB-W2-019: inline line-item editing state
  const [editingItems, setEditingItems] = useState(false);
  const [draftItems, setDraftItems] = useState<Array<{
    id?: number;
    description: string;
    quantity: number;
    unit_price: number;
    tax_amount: number;
  }>>([]);

  // Guard against a missing route param — `Number(undefined)` is NaN and
  // would otherwise fire the API call with a garbage id.
  const numericId = id ? Number(id) : NaN;
  const idIsValid = Number.isFinite(numericId);
  const { data, isLoading, isError } = useQuery({
    queryKey: ['estimate', id],
    queryFn: () => estimateApi.get(numericId),
    enabled: idIsValid,
  });

  const estimate = data?.data?.data;
  const canManageSigning = userRole === 'admin' || userRole === 'manager';

  // Version history query (ENR-LE6)
  const { data: versionsData, isLoading: versionsLoading } = useQuery({
    queryKey: ['estimate-versions', id],
    queryFn: () => estimateApi.versions(Number(id)),
    enabled: showVersions,
    staleTime: 60_000, // versions of completed/sent estimates rarely change minute-to-minute
  });
  const versions: EstimateVersion[] = versionsData?.data?.data || [];

  const { data: signaturesData, isLoading: signaturesLoading, isError: signaturesError } = useQuery({
    queryKey: ['estimate-signatures', numericId],
    queryFn: () => estimateApi.signatures(numericId),
    enabled: idIsValid && canManageSigning,
    staleTime: 60_000,
    retry: false,
  });
  const signatures: EstimateSignature[] = signaturesData?.data?.data || [];

  const sendMut = useMutation({
    mutationFn: () => estimateApi.send(Number(id)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      const data = res?.data?.data || {};
      if (data.sent === false) {
        toast.error(data.warning || 'No message was sent');
      } else {
        toast.success(data.message || 'Estimate sent to customer');
      }
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to send'),
  });

  const approveMut = useMutation({
    mutationFn: () => estimateApi.approve(Number(id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      toast.success('Estimate approved');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to approve'),
  });

  const convertMut = useMutation({
    mutationFn: () => estimateApi.convert(Number(id)),
    onSuccess: (res) => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      toast.success('Converted to ticket');
      const ticketId = res.data?.data?.ticket?.id;
      if (ticketId) navigate(`/tickets/${ticketId}`);
    },
    onError: () => toast.error('Failed to convert'),
  });

  const updateMut = useMutation({
    mutationFn: (d: any) => estimateApi.update(Number(id), d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      setEditing(false);
      toast.success('Estimate updated');
    },
    onError: () => toast.error('Failed to update'),
  });

  // WEB-W2-020: reject mutation
  const rejectMut = useMutation({
    mutationFn: () => estimateApi.reject(Number(id)),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      queryClient.invalidateQueries({ queryKey: ['estimates'] });
      toast.success('Estimate rejected');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to reject'),
  });

  const createSignUrlMut = useMutation({
    mutationFn: () => estimateApi.createSignUrl(Number(id)),
    onSuccess: (res) => {
      const payload = res.data?.data;
      const token = payload?.url ? extractEstimateSignToken(payload.url) : '';
      if (!payload?.url || !token) {
        toast.error('Signing link response was invalid');
        return;
      }
      setSignSession({ token, url: payload.url, expiresAt: payload.expires_at });
    },
    onError: (err: any) => toast.error(formatApiError(err) || 'Failed to create signing link'),
  });

  // WEB-W2-019: line-item save mutation — reuses the existing PUT /:id endpoint
  const lineItemsMut = useMutation({
    mutationFn: (items: typeof draftItems) =>
      estimateApi.update(Number(id), { line_items: items }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['estimate', id] });
      setEditingItems(false);
      toast.success('Line items saved');
    },
    onError: () => toast.error('Failed to save line items'),
  });

  const estimateBreadcrumbItems = [
    { label: 'Estimates', href: '/estimates' },
    { label: estimate?.order_id || (id ? `Estimate #${id}` : 'Estimate') },
  ];

  if (isLoading) {
    return (
      <div>
        <Breadcrumb items={estimateBreadcrumbItems} />
        <div className="flex items-center justify-center py-20" aria-busy="true" aria-label="Loading estimate">
          <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
        </div>
      </div>
    );
  }

  if (isError || !estimate) {
    return (
      <div>
        <Breadcrumb items={estimateBreadcrumbItems} />
        <div className="flex flex-col items-center justify-center py-20" role="alert">
          <p className="text-lg font-medium text-surface-600 dark:text-surface-400">Estimate not found</p>
          <Link to="/estimates" className="mt-4 text-sm text-primary-600 hover:underline">Back to estimates</Link>
        </div>
      </div>
    );
  }

  const color = STATUS_COLORS[estimate.status] || '#6b7280';
  const lineItems: any[] = estimate.line_items || [];
  const estimateContentLocked =
    estimate.status === 'approved' ||
    estimate.status === 'signed' ||
    estimate.status === 'converted' ||
    estimate.status === 'rejected';
  const isExpired =
    !estimateContentLocked &&
    !!estimate.valid_until &&
    new Date(estimate.valid_until) < new Date();
  // Mutually exclusive action buttons — without this gate a rapid click on
  // Convert mid-Send navigates away while the first mutation is still in
  // flight, leaving the server in an inconsistent state.
  const anyMutationPending =
    sendMut.isPending ||
    approveMut.isPending ||
    convertMut.isPending ||
    rejectMut.isPending ||
    createSignUrlMut.isPending;
  const canStartSigning =
    canManageSigning &&
    !estimateContentLocked;

  return (
    <div>
      <Breadcrumb items={estimateBreadcrumbItems} />
      {/* Header */}
      <div className="mb-6 flex flex-col gap-4 lg:flex-row lg:items-start lg:justify-between">
        <div className="flex min-w-0 items-start gap-3">
          <button onClick={() => navigate('/estimates')} className="shrink-0 rounded-lg p-2 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
            <ArrowLeft className="h-5 w-5" />
          </button>
          <div className="min-w-0">
            <div className="flex min-w-0 flex-wrap items-center gap-3">
              <h1 className="min-w-0 break-words text-2xl font-bold text-surface-900 dark:text-surface-100">
                Estimate {estimate.order_id}
              </h1>
              <span
                className="inline-flex shrink-0 items-center gap-1.5 rounded-full px-2.5 py-0.5 text-xs font-medium capitalize"
                style={{ backgroundColor: `${color}18`, color }}
              >
                <span className="h-1.5 w-1.5 rounded-full" style={{ backgroundColor: color }} />
                {estimate.status}
              </span>
            </div>
            <p className="text-sm text-surface-500">Created {formatDate(estimate.created_at)}</p>
          </div>
        </div>
        <div className="grid w-full grid-cols-[repeat(auto-fit,minmax(8.75rem,1fr))] gap-2 sm:flex sm:flex-wrap sm:items-center lg:w-auto lg:justify-end" data-estimate-actions="true">
          {canStartSigning && (
            <button
              onClick={() => createSignUrlMut.mutate()}
              disabled={anyMutationPending}
              className={cn(
                ESTIMATE_ACTION_BUTTON_CLASS,
                'border border-amber-300 text-amber-700 hover:bg-amber-50 dark:border-amber-700 dark:text-amber-300 dark:hover:bg-amber-950/30 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none',
              )}
            >
              {createSignUrlMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <FileSignature className="h-4 w-4" />}
              E-sign
            </button>
          )}
          {(estimate.status === 'draft' || estimate.status === 'sent') && (
            <button
              onClick={async () => {
                try {
                  const msg = estimate.status === 'sent' ? 'Resend this estimate to the customer?' : 'Send this estimate to the customer via SMS?';
                  if (await confirm(msg)) sendMut.mutate();
                } catch (err) { toast.error(formatApiError(err)); }
              }}
              disabled={anyMutationPending || isExpired}
              className={cn(
                ESTIMATE_ACTION_BUTTON_CLASS,
                'border border-primary-300 text-primary-700 hover:bg-primary-50 dark:border-primary-700 dark:text-primary-400 dark:hover:bg-primary-950/30 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none',
              )}
            >
              {sendMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              {estimate.status === 'sent' ? 'Resend' : 'Send'}
            </button>
          )}
          {(estimate.status === 'sent' || estimate.status === 'draft') && (
            <button
              onClick={async () => {
                try { if (await confirm('Mark this estimate as approved?')) approveMut.mutate(); }
                catch (err) { toast.error(formatApiError(err)); }
              }}
              disabled={anyMutationPending || isExpired}
              className={cn(
                ESTIMATE_ACTION_BUTTON_CLASS,
                'border border-emerald-300 text-emerald-700 hover:bg-emerald-50 dark:border-emerald-700 dark:text-emerald-400 dark:hover:bg-emerald-950/30 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none',
              )}
            >
              {approveMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <CheckCircle className="h-4 w-4" />}
              Approve
            </button>
          )}
          {estimate.status !== 'converted' && estimate.status !== 'rejected' && (
            <button
              onClick={async () => {
                try {
                  const isStale = estimate.status === 'draft' || estimate.status === 'expired';
                  const msg = isStale
                    ? `Convert this ${estimate.status} estimate to a ticket? Customer hasn't signed/approved this quote.`
                    : 'Convert this estimate to a ticket?';
                  if (await confirm(msg)) convertMut.mutate();
                }
                catch (err) { toast.error(formatApiError(err)); }
              }}
              disabled={anyMutationPending || isExpired}
              className={cn(
                ESTIMATE_ACTION_BUTTON_CLASS,
                'border border-green-300 text-green-700 hover:bg-green-50 dark:border-green-700 dark:text-green-400 dark:hover:bg-green-950/30 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none',
              )}
            >
              {convertMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <ArrowRightLeft className="h-4 w-4" />}
              Convert to Ticket
            </button>
          )}
          {/* WEB-W2-020: Reject button — available on any non-terminal status */}
          {!estimateContentLocked && (
            <button
              onClick={async () => {
                try {
                  if (await confirm('Mark this estimate as rejected? This cannot be undone.', { title: 'Reject estimate?', confirmLabel: 'Reject', danger: true }))
                    rejectMut.mutate();
                } catch (err) { toast.error(formatApiError(err)); }
              }}
              disabled={anyMutationPending}
              className={cn(
                ESTIMATE_ACTION_BUTTON_CLASS,
                'border border-red-300 text-red-700 hover:bg-red-50 dark:border-red-700 dark:text-red-400 dark:hover:bg-red-950/30 disabled:cursor-not-allowed disabled:opacity-50 disabled:pointer-events-none',
              )}
            >
              {rejectMut.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <XCircle className="h-4 w-4" />}
              Reject
            </button>
          )}
          <button
            onClick={() => window.print()}
            className={cn(
              ESTIMATE_ACTION_BUTTON_CLASS,
              'border border-surface-200 text-surface-700 hover:bg-surface-50 dark:border-surface-700 dark:text-surface-300 dark:hover:bg-surface-800',
            )}
          >
            <Printer className="h-4 w-4" />
            Print
          </button>
        </div>
      </div>

      {isExpired && (
        <div className="mb-6 flex flex-col gap-2 rounded-lg border border-amber-300 bg-amber-50 px-4 py-3 sm:flex-row sm:items-center sm:justify-between dark:border-amber-700 dark:bg-amber-950/30">
          <p className="text-sm font-medium text-amber-800 dark:text-amber-200">
            Estimate expired on {formatDate(estimate.valid_until)} — pricing may be stale. Re-quote to update.
          </p>
          <button
            type="button"
            onClick={() => navigate('/estimates/new')}
            className="shrink-0 rounded-lg border border-amber-400 px-3 py-1.5 text-xs font-semibold text-amber-800 hover:bg-amber-100 dark:border-amber-600 dark:text-amber-200 dark:hover:bg-amber-900/40"
          >
            Re-quote
          </button>
        </div>
      )}

      {estimateContentLocked && (estimate.status === 'approved' || estimate.status === 'signed') && (
        <div className="mb-6 rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 dark:border-surface-700 dark:bg-surface-800/60">
          <p className="text-sm font-medium text-surface-700 dark:text-surface-300">
            This estimate is locked because it was <span className="capitalize">{estimate.status}</span>. Create a revision instead.
          </p>
        </div>
      )}
      {estimateContentLocked && estimate.status === 'converted' && (
        <div className="mb-6 rounded-lg border border-surface-300 bg-surface-50 px-4 py-3 dark:border-surface-700 dark:bg-surface-800/60">
          <p className="text-sm font-medium text-surface-700 dark:text-surface-300">
            This estimate is locked because it was converted. Create a revision instead.
          </p>
        </div>
      )}

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Main content */}
        <div className="lg:col-span-2 space-y-6">
          {/* Customer info */}
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Customer</h3>
            {estimate.customer_first_name ? (
              <div>
                <p className="font-medium text-surface-900 dark:text-surface-100">
                  {estimate.customer_first_name} {estimate.customer_last_name}
                </p>
                {estimate.customer_email && <p className="text-sm text-surface-500">{estimate.customer_email}</p>}
                {(estimate.customer_phone || estimate.customer_mobile) && (
                  <p className="text-sm text-surface-500">{estimate.customer_mobile || estimate.customer_phone}</p>
                )}
                {estimate.address1 && (
                  <p className="text-sm text-surface-500 mt-1">
                    {estimate.address1}{estimate.city && `, ${estimate.city}`}{estimate.state && `, ${estimate.state}`} {estimate.postcode}
                  </p>
                )}
              </div>
            ) : (
              <p className="text-sm text-surface-400 italic">No customer linked</p>
            )}
          </div>

          {/* Line items */}
          <div className="card overflow-hidden">
            <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
              <h3 className="font-semibold text-surface-900 dark:text-surface-100">Line Items</h3>
              {/* WEB-W2-019: edit line items inline (only for non-terminal estimates) */}
              {!editingItems && !estimateContentLocked && (
                <button
                  onClick={() => {
                    setDraftItems(lineItems.map((li: any) => ({
                      id: li.id,
                      description: li.description || li.item_name || li.name || '',
                      quantity: Number(li.quantity) || 1,
                      unit_price: Number(li.unit_price ?? li.price ?? 0),
                      tax_amount: Number(li.tax_amount ?? 0),
                    })));
                    setEditingItems(true);
                  }}
                  className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1"
                >
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
              {editingItems && (
                <div className="flex items-center gap-2">
                  <button
                    onClick={() => lineItemsMut.mutate(draftItems)}
                    disabled={lineItemsMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none"
                  >
                    {lineItemsMut.isPending ? <Loader2 className="h-3 w-3 animate-spin" /> : <Save className="h-3 w-3" />}
                    Save
                  </button>
                  <button onClick={() => setEditingItems(false)} className="text-xs text-surface-500 hover:text-surface-700">Cancel</button>
                </div>
              )}
            </div>
            {editingItems ? (
              /* Editable line-items form */
              <div className="p-4 space-y-3">
                {draftItems.map((item, idx) => (
                  <div key={idx} className="grid grid-cols-[1fr_auto_auto_auto_auto] gap-2 items-start">
                    <input
                      value={item.description}
                      onChange={(e) => setDraftItems((prev) => prev.map((r, i) => i === idx ? { ...r, description: e.target.value } : r))}
                      placeholder="Description"
                      className="input text-sm"
                    />
                    <input
                      type="number" min="1" step="1"
                      value={item.quantity}
                      onChange={(e) => setDraftItems((prev) => prev.map((r, i) => i === idx ? { ...r, quantity: Number(e.target.value) || 1 } : r))}
                      placeholder="Qty"
                      className="input text-sm w-20 text-right"
                    />
                    <input
                      type="number" min="0" step="0.01"
                      value={item.unit_price}
                      onChange={(e) => setDraftItems((prev) => prev.map((r, i) => i === idx ? { ...r, unit_price: Number(e.target.value) || 0 } : r))}
                      placeholder="Price"
                      className="input text-sm w-28 text-right"
                    />
                    <input
                      type="number" min="0" step="0.01"
                      value={item.tax_amount}
                      onChange={(e) => setDraftItems((prev) => prev.map((r, i) => i === idx ? { ...r, tax_amount: Number(e.target.value) || 0 } : r))}
                      placeholder="Tax"
                      className="input text-sm w-24 text-right"
                    />
                    <button
                      onClick={() => setDraftItems((prev) => prev.filter((_, i) => i !== idx))}
                      className="p-1.5 text-red-400 hover:text-red-600 rounded"
                      title="Remove row"
                    >
                      <Trash2 className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
                <button
                  onClick={() => setDraftItems((prev) => [...prev, { description: '', quantity: 1, unit_price: 0, tax_amount: 0 }])}
                  className="inline-flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 font-medium mt-1"
                >
                  <Plus className="h-3 w-3" /> Add row
                </button>
              </div>
            ) : lineItems.length === 0 ? (
              <p className="p-4 text-sm text-surface-400">No line items</p>
            ) : (
              <div className="overflow-x-auto">
              <table className="w-full text-sm">
                <thead>
                  <tr className="border-b border-surface-100 dark:border-surface-800">
                    <th className="text-left px-4 py-3 font-medium text-surface-500">Item</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Qty</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Price</th>
                    <th className="text-right px-4 py-3 font-medium text-surface-500">Total</th>
                  </tr>
                </thead>
                <tbody>
                  {lineItems.map((li: any) => (
                    <tr key={li.id} className="border-b border-surface-50 dark:border-surface-800/50">
                      <td className="px-4 py-3">
                        <p className="font-medium text-surface-900 dark:text-surface-100">{li.item_name || li.description || li.name || 'Item'}</p>
                        {li.item_sku && <p className="text-xs text-surface-400">SKU: {li.item_sku}</p>}
                      </td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{li.quantity}</td>
                      <td className="px-4 py-3 text-right text-surface-600 dark:text-surface-400">{formatCurrency(li.unit_price ?? li.price ?? 0)}</td>
                      <td className="px-4 py-3 text-right font-medium text-surface-900 dark:text-surface-100">{formatCurrency(li.total ?? li.quantity * (li.unit_price ?? li.price ?? 0))}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
              </div>
            )}
          </div>

          {/* Notes */}
          <div className="card p-5">
            <div className="flex items-center justify-between mb-3">
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Notes</h3>
              {!editing && !estimateContentLocked && (
                <button onClick={() => { setEditing(true); setNotes(estimate.notes || ''); }}
                  className="text-xs text-primary-600 hover:text-primary-700 font-medium flex items-center gap-1">
                  <Pencil className="h-3 w-3" /> Edit
                </button>
              )}
            </div>
            {editing ? (
              <div className="space-y-2">
                <textarea
                  value={notes}
                  onChange={(e) => setNotes(e.target.value)}
                  rows={3}
                  className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-surface-50 dark:bg-surface-800 px-3 py-2 text-sm text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
                />
                <div className="flex gap-2">
                  <button onClick={() => updateMut.mutate({ notes })} disabled={updateMut.isPending}
                    className="inline-flex items-center gap-1 rounded-lg bg-primary-600 px-3 py-1.5 text-xs font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none">
                    <Save className="h-3 w-3" /> Save
                  </button>
                  <button onClick={() => setEditing(false)} className="text-xs text-surface-500 hover:text-surface-700">Cancel</button>
                </div>
              </div>
            ) : (
              <p className="text-sm text-surface-600 dark:text-surface-400 whitespace-pre-wrap">
                {estimate.notes || <span className="italic text-surface-400">No notes</span>}
              </p>
            )}
          </div>
        </div>

        {/* Sidebar summary */}
        <div className="space-y-6">
          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-4">Summary</h3>
            <div className="space-y-2 text-sm">
              <div className="flex justify-between">
                <span className="text-surface-500">Subtotal</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.subtotal)}</span>
              </div>
              {estimate.discount > 0 && (
                <div className="flex justify-between text-green-600">
                  <span>Discount</span>
                  <span>-{formatCurrency(estimate.discount)}</span>
                </div>
              )}
              <div className="flex justify-between">
                <span className="text-surface-500">Tax</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.total_tax)}</span>
              </div>
              <div className="flex justify-between pt-2 border-t border-surface-200 dark:border-surface-700 font-bold text-base">
                <span className="text-surface-900 dark:text-surface-100">Total</span>
                <span className="text-surface-900 dark:text-surface-100">{formatCurrency(estimate.total)}</span>
              </div>
            </div>
          </div>

          <div className="card p-5">
            <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider mb-3">Details</h3>
            <dl className="space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-surface-500">Created</dt>
                <dd className="text-surface-900 dark:text-surface-100">{formatDate(estimate.created_at)}</dd>
              </div>
              {estimate.valid_until && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Valid Until</dt>
                  <dd className={cn(
                    'text-surface-900 dark:text-surface-100',
                    estimate.valid_until && new Date(estimate.valid_until) < new Date() && 'text-red-500 dark:text-red-400',
                  )}>
                    {formatDate(estimate.valid_until)}
                    {estimate.valid_until && new Date(estimate.valid_until) < new Date() && ' (expired)'}
                  </dd>
                </div>
              )}
              {estimate.sent_at && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Sent</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{formatDate(estimate.sent_at)}</dd>
                </div>
              )}
              {estimate.approved_at && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Approved</dt>
                  <dd className="text-emerald-600 dark:text-emerald-400">{formatDate(estimate.approved_at)}</dd>
                </div>
              )}
              {estimate.created_by_first_name && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Created By</dt>
                  <dd className="text-surface-900 dark:text-surface-100">{estimate.created_by_first_name} {estimate.created_by_last_name}</dd>
                </div>
              )}
              {estimate.converted_ticket_id && (
                <div className="flex justify-between">
                  <dt className="text-surface-500">Ticket</dt>
                  <dd>
                    <Link to={`/tickets/${estimate.converted_ticket_id}`} className="text-primary-600 hover:underline">
                      View Ticket
                    </Link>
                  </dd>
                </div>
              )}
            </dl>
          </div>

          {canManageSigning && (
            <div className="card p-5">
              <div className="mb-3 flex items-center justify-between gap-3">
                <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Signatures</h3>
                {canStartSigning && (
                  <button
                    type="button"
                    onClick={() => createSignUrlMut.mutate()}
                    disabled={anyMutationPending}
                    className="inline-flex items-center gap-1.5 rounded-lg border border-amber-300 px-3 py-1.5 text-xs font-medium text-amber-700 hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-amber-700 dark:text-amber-300 dark:hover:bg-amber-950/30"
                  >
                    {createSignUrlMut.isPending ? <Loader2 className="h-3.5 w-3.5 animate-spin" /> : <FileSignature className="h-3.5 w-3.5" />}
                    Sign
                  </button>
                )}
              </div>
              {signaturesLoading ? (
                <div className="flex justify-center py-4">
                  <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
                </div>
              ) : signaturesError ? (
                <p className="text-xs text-red-500 dark:text-red-400">Signatures unavailable</p>
              ) : signatures.length === 0 ? (
                <p className="text-xs text-surface-400 dark:text-surface-500 italic">No signatures captured</p>
              ) : (
                <div className="space-y-2">
                  {signatures.map((signature) => (
                    <SignatureRow key={signature.id} signature={signature} />
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Version History (ENR-LE6) */}
          <div className="card p-5" data-version-history="true">
            <button
              onClick={() => setShowVersions((v) => !v)}
              className="flex w-full items-center justify-between"
            >
              <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wider">Version History</h3>
              {showVersions
                ? <ChevronUp className="h-4 w-4 text-surface-400" />
                : <ChevronDown className="h-4 w-4 text-surface-400" />
              }
            </button>
            {showVersions && (
              <div className="mt-3">
                {versionsLoading ? (
                  <div className="flex justify-center py-4">
                    <Loader2 className="h-5 w-5 animate-spin text-surface-400" />
                  </div>
                ) : versions.length === 0 ? (
                  <p className="text-xs text-surface-400 dark:text-surface-500 italic">No previous versions</p>
                ) : (
                  <div className="space-y-2 max-h-48 overflow-y-auto">
                    {versions.map((v) => (
                      <div
                        key={v.id}
                        className="flex items-center justify-between rounded-lg bg-surface-50 dark:bg-surface-800/50 px-3 py-2"
                      >
                        <div className="flex items-center gap-2">
                          <History className="h-3.5 w-3.5 text-surface-400" />
                          <span className="text-sm font-medium text-surface-700 dark:text-surface-300">
                            v{v.version_number}
                          </span>
                        </div>
                        <span className="text-xs text-surface-400">
                          {formatDate(v.created_at)}
                        </span>
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}
          </div>
        </div>
      </div>
      {signSession && (
        <EstimateSignDialog
          session={signSession}
          fallbackEmail={estimate.customer_email}
          onClose={() => setSignSession(null)}
          onSigned={() => {
            setSignSession(null);
            queryClient.invalidateQueries({ queryKey: ['estimate', id] });
            queryClient.invalidateQueries({ queryKey: ['estimate-signatures', numericId] });
            queryClient.invalidateQueries({ queryKey: ['estimates'] });
          }}
        />
      )}
    </div>
  );
}
