import { useState } from 'react';
import { CheckCircle2, Printer, ExternalLink, PlusCircle, Tag, FileText, MessageSquare, Mail, AlertTriangle } from 'lucide-react';
import { useNavigate } from 'react-router-dom';
import toast from 'react-hot-toast';
import { useUnifiedPosStore } from './store';
import { useQuery } from '@tanstack/react-query';
import { serverInfoApi, smsApi, notificationApi, ticketApi, settingsApi } from '@/api/endpoints';
// FA-L4: QrReceiptCode on the POS success screen lets the customer scan the
// receipt URL from the counter. It's a secondary channel — email/SMS remain
// the primary delivery — but works offline for walk-up customers.
import { QrReceiptCode } from '@/components/billing/QrReceiptCode';

// ─── SuccessScreen ──────────────────────────────────────────────────

export function SuccessScreen() {
  const navigate = useNavigate();
  const { showSuccess, resetAll } = useUnifiedPosStore();
  const [smsSending, setSmsSending] = useState(false);
  const [emailSending, setEmailSending] = useState(false);

  // Derive IDs early (before hooks) so they can be passed to enabled checks.
  // These are safe to compute unconditionally because they only read showSuccess.
  const _data = showSuccess;
  const _ticket = _data?.ticket;
  const _devices = _ticket?.devices ?? _data?.devices ?? [];
  const _firstDevice = _devices[0];
  const _ticketId: number | null = _ticket?.id ?? _data?.ticket_id ?? null;
  const _firstDeviceId: number | null = _firstDevice?.id ?? null;

  // Fetch store config for SMS receipt branding — must be above early return (hook rules).
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
    staleTime: 5 * 60 * 1000,
  });
  const storeConfig = configData ?? {};

  // Fetch server info for QR code URL — must be above early return (hook rules).
  const { data: serverInfo } = useQuery({
    queryKey: ['server-info'],
    queryFn: () => serverInfoApi.get(),
    staleTime: 60_000,
    enabled: !!showSuccess,
  });
  const serverUrl = serverInfo?.data?.data?.server_url ?? '';

  // AUDIT-WEB-002: fetch a scoped, short-lived (30-min) photo-upload token.
  // The QR URL embeds this token instead of the full staff bearer JWT so a
  // customer's phone cannot quietly retain a long-lived staff credential.
  // Token has aud='photo-upload' to prevent cross-endpoint reuse.
  const {
    data: scopedToken,
    isError: photoTokenError,
  } = useQuery({
    queryKey: ['photo-upload-token', _ticketId, _firstDeviceId],
    queryFn: async () => {
      const res = await ticketApi.getPhotoUploadToken(_ticketId!, _firstDeviceId!);
      return res.data.data.token;
    },
    enabled: !!(showSuccess && _ticketId && _firstDeviceId),
    staleTime: 25 * 60 * 1000, // 25 min — token itself expires at 30 min
    retry: false,
  });

  if (!showSuccess) return null;

  const data = showSuccess;
  const ticket = data.ticket;
  const invoice = data.invoice;
  const ticketId: number | null = ticket?.id ?? data.ticket_id ?? null;
  const orderId: string | null = ticket?.order_id ?? data.order_id ?? null;
  const mode: string = data.mode ?? 'checkout';
  const isTicketOnly = mode === 'create_ticket';
  const invoiceId: number | null = invoice?.id ?? data.invoice_id ?? null;
  const invoiceOrderId: string | null = invoice?.order_id ?? null;
  const total: number = invoice?.total ?? data.total ?? 0;
  const change: number = data.change ?? 0;

  // Customer name from multiple sources
  const customerName: string = ticket?.c_first_name
    ? `${ticket.c_first_name} ${ticket.c_last_name || ''}`.trim()
    : ticket?.customer?.first_name
      ? `${ticket.customer.first_name} ${ticket.customer.last_name || ''}`.trim()
      : invoice?.first_name
        ? `${invoice.first_name} ${invoice.last_name || ''}`.trim()
        : (data.customer_name ?? '');

  // Customer phone and email for receipt delivery
  const customerPhone: string | null = invoice?.customer_phone || ticket?.customer?.phone || data.customer_phone || null;
  const customerEmail: string | null = invoice?.customer_email || ticket?.customer?.email || data.customer_email || null;

  const handleSendSms = async () => {
    if (!customerPhone || !invoiceId) return;
    setSmsSending(true);
    try {
      const shopName = storeConfig['store_name'] || 'our shop';
      const smsFooter = storeConfig['receipt_thermal_footer'] || storeConfig['receipt_footer'] || '';
      const msg = `Receipt for Invoice #${invoiceOrderId || invoiceId}: Total $${total.toFixed(2)}. Paid: $${total.toFixed(2)}. Thank you for choosing ${shopName}!${smsFooter ? ` ${smsFooter}` : ''}`;
      await smsApi.send({ to: customerPhone, message: msg, entity_type: 'invoice', entity_id: invoiceId });
      toast.success('Receipt sent via SMS');
    } catch {
      toast.error('Failed to send SMS receipt');
    } finally {
      setSmsSending(false);
    }
  };

  const handleSendEmail = async () => {
    if (!invoiceId) return;
    setEmailSending(true);
    try {
      await notificationApi.sendReceipt({ invoice_id: invoiceId, email: customerEmail || undefined });
      toast.success('Receipt sent via email');
    } catch (err: unknown) {
      const msg = err && typeof err === 'object' && 'response' in err
        ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
        : undefined;
      toast.error(msg || 'Failed to send email receipt');
    } finally {
      setEmailSending(false);
    }
  };

  // Get first device info for summary
  const devices = ticket?.devices ?? data.devices ?? [];
  const firstDevice = devices[0];
  const deviceSummary = firstDevice
    ? `${firstDevice.device_name || firstDevice.device_type || 'Device'}${firstDevice.service_name ? ` - ${firstDevice.service_name}` : ''}`
    : null;
  const deviceCount = devices.length;

  // Get first device ID for QR code
  const firstDeviceId = firstDevice?.id ?? null;

  const handlePrintLabel = () => {
    if (ticketId) {
      const id = ticketId;
      resetAll();
      navigate(`/print/ticket/${id}?size=label`);
    }
  };

  const handlePrintReceipt = () => {
    if (ticketId) {
      const id = ticketId;
      resetAll();
      navigate(`/print/ticket/${id}?size=receipt80&type=receipt`);
    }
  };

  const handleViewTicket = () => {
    if (ticketId) {
      const id = ticketId;
      resetAll();
      navigate(`/tickets/${id}`);
    }
  };

  const handleViewInvoice = () => {
    if (invoiceId) {
      resetAll();
      setTimeout(() => navigate(`/invoices/${invoiceId}`), 0);
    }
  };

  const handleNewAction = () => {
    resetAll();
  };

  // AUDIT-WEB-002: build QR URL only when a scoped token is available.
  // Never fall back to the full staff bearer JWT.
  const qrUrl = serverUrl && ticketId && firstDeviceId && scopedToken
    ? `${serverUrl}/photo-capture/${ticketId}/${firstDeviceId}?t=${scopedToken}`
    : null;

  // ─── Ticket Created Success ────────────────────────────────────────
  if (isTicketOnly) {
    return (
      <div className="flex h-full flex-col items-center justify-center gap-5 p-8">
        {/* Green check */}
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-green-100 dark:bg-green-500/10">
          <CheckCircle2 className="h-12 w-12 text-green-600 dark:text-green-400" strokeWidth={1.5} />
        </div>

        <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">Ticket Created!</h1>

        {/* Ticket details */}
        <div className="space-y-1.5 text-center">
          {orderId && (
            <button
              onClick={handleViewTicket}
              className="text-xl font-bold text-teal-600 hover:text-teal-700 hover:underline dark:text-teal-400 dark:hover:text-teal-300"
            >
              {orderId}
            </button>
          )}
          {customerName && (
            <p className="text-sm font-medium text-surface-700 dark:text-surface-300">
              {customerName}
            </p>
          )}
          {deviceSummary && (
            <p className="text-sm text-surface-500 dark:text-surface-400">
              {deviceSummary}
              {deviceCount > 1 && ` (+${deviceCount - 1} more)`}
            </p>
          )}
          {invoiceOrderId && (
            <p className="text-xs text-surface-400 dark:text-surface-500">
              Invoice {invoiceOrderId}
            </p>
          )}
        </div>

        {/* Photo capture: QR code
            AUDIT-WEB-002: uses a scoped 30-min token, not the staff bearer JWT.
            Shows "QR unavailable" if the token mint call fails. */}
        {firstDeviceId && ticketId && (
          <div className="w-full max-w-sm rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-500/20 dark:bg-amber-500/5">
            <p className="mb-3 text-center text-sm font-semibold text-amber-800 dark:text-amber-300">
              Take Device Photos
            </p>
            {photoTokenError ? (
              <p className="text-center text-xs text-amber-700 dark:text-amber-400">
                QR unavailable — could not generate a secure upload link.
              </p>
            ) : qrUrl ? (
              <div className="flex items-start justify-center gap-4">
                {/* QR code */}
                <div className="text-center">
                  <div className="mx-auto mb-1.5 flex h-28 w-28 items-center justify-center rounded-lg bg-white p-1.5">
                    <img
                      src={`/api/v1/qr?data=${encodeURIComponent(qrUrl)}`}
                      alt="Scan to take photos"
                      className="h-24 w-24"
                    />
                  </div>
                  <p className="text-[10px] text-amber-700 dark:text-amber-400">
                    Scan QR with any phone
                  </p>
                </div>
                {/* FA-L1: "Push to Phone" control removed — it was a permanently
                    disabled placeholder. Planned rewire: push the photo-capture
                    session to whichever Android device is signed into the same
                    tenant/user, with the QR code as a fallback for walk-up
                    customers. Hidden until the server-side push dispatch lands. */}
              </div>
            ) : (
              <p className="text-center text-xs text-amber-600 dark:text-amber-400">
                Generating secure link…
              </p>
            )}
          </div>
        )}

        {/* Action buttons */}
        <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
          <button
            onClick={handlePrintLabel}
            className="flex items-center gap-2 rounded-lg border border-surface-300 px-5 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Tag className="h-4 w-4" />
            Print Label
          </button>
          <button
            onClick={handlePrintReceipt}
            className="flex items-center gap-2 rounded-lg border border-surface-300 px-5 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Printer className="h-4 w-4" />
            Print Receipt
          </button>
          <button
            onClick={handleViewTicket}
            className="flex items-center gap-2 rounded-lg border border-teal-300 px-5 py-2.5 text-sm font-medium text-teal-700 hover:bg-teal-50 dark:border-teal-500/30 dark:text-teal-400 dark:hover:bg-teal-500/10"
          >
            <ExternalLink className="h-4 w-4" />
            View Ticket
          </button>
          <button
            onClick={handleNewAction}
            className="flex items-center gap-2 rounded-lg bg-teal-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-teal-700"
          >
            <PlusCircle className="h-4 w-4" />
            New Check-in
          </button>
        </div>
      </div>
    );
  }

  // ─── Payment Received Success ──────────────────────────────────────
  // WEB-FH-008: when the card terminal declined / errored AFTER invoice
  // creation, render a RED warning state instead of the green checkmark.
  // The cashier MUST notice they need to retry the charge before handing
  // the receipt to the customer.
  const cardDeclined = !!data.card_declined;
  return (
    <div className="flex h-full flex-col items-center justify-center gap-5 p-8">
      {cardDeclined ? (
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-red-100 dark:bg-red-500/10">
          <AlertTriangle className="h-12 w-12 text-red-600 dark:text-red-400" strokeWidth={1.5} />
        </div>
      ) : (
        <div className="flex h-20 w-20 items-center justify-center rounded-full bg-green-100 dark:bg-green-500/10">
          <CheckCircle2 className="h-12 w-12 text-green-600 dark:text-green-400" strokeWidth={1.5} />
        </div>
      )}

      <h1 className={`text-2xl font-bold ${cardDeclined ? 'text-red-700 dark:text-red-400' : 'text-surface-900 dark:text-surface-50'}`}>
        {cardDeclined ? 'Card Declined — Retry Payment' : 'Payment Received!'}
      </h1>

      {cardDeclined && (
        <div className="w-full max-w-md rounded-lg border-2 border-red-300 bg-red-50 p-4 text-center dark:border-red-500/40 dark:bg-red-500/10">
          <p className="text-sm font-semibold text-red-800 dark:text-red-300">
            Invoice was created but the card terminal did not authorize.
          </p>
          {data.card_decline_message && (
            <p className="mt-1 text-xs text-red-700 dark:text-red-400">
              {data.card_decline_message}
            </p>
          )}
          <p className="mt-2 text-xs text-red-700 dark:text-red-400">
            Do <strong>not</strong> release the goods. Click "View Invoice" below to retry the charge or take an alternate tender.
          </p>
        </div>
      )}

      <div className="space-y-1.5 text-center">
        {total > 0 && (
          <p className={`text-3xl font-bold ${cardDeclined ? 'text-red-700 dark:text-red-400' : 'text-surface-900 dark:text-surface-100'}`}>
            ${total.toFixed(2)}
          </p>
        )}
        {change > 0 && !cardDeclined && (
          <p className="text-lg font-medium text-green-600 dark:text-green-400">
            Change: ${change.toFixed(2)}
          </p>
        )}
        {customerName && (
          <p className="text-sm font-medium text-surface-700 dark:text-surface-300">
            {customerName}
          </p>
        )}
        {orderId && (
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Ticket {orderId}
          </p>
        )}
        {invoiceOrderId && (
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Invoice {invoiceOrderId}
          </p>
        )}
      </div>

      {/* Receipt delivery — WEB-FH-008: suppress in declined state so the
          cashier can't accidentally SMS/email a "paid" receipt. */}
      {!cardDeclined && invoiceId && (customerPhone || customerEmail) && (
        <div className="flex flex-wrap items-center justify-center gap-3">
          {customerPhone && (
            <button
              onClick={handleSendSms}
              disabled={smsSending}
              className="flex items-center gap-2 rounded-lg border border-green-300 px-4 py-2 text-sm font-medium text-green-700 hover:bg-green-50 disabled:opacity-50 dark:border-green-500/30 dark:text-green-400 dark:hover:bg-green-500/10"
            >
              <MessageSquare className="h-4 w-4" />
              {smsSending ? 'Sending...' : 'Send Receipt via SMS'}
            </button>
          )}
          {customerEmail && (
            <button
              onClick={handleSendEmail}
              disabled={emailSending}
              className="flex items-center gap-2 rounded-lg border border-blue-300 px-4 py-2 text-sm font-medium text-blue-700 hover:bg-blue-50 disabled:opacity-50 dark:border-blue-500/30 dark:text-blue-400 dark:hover:bg-blue-500/10"
            >
              <Mail className="h-4 w-4" />
              {emailSending ? 'Sending...' : 'Email Receipt'}
            </button>
          )}
        </div>
      )}

      {/* FA-L4 — scannable receipt QR. Points the customer at the
          invoice detail page so they can pull up a copy on their phone
          without needing an SMS/email.
          WEB-FH-008: suppress on card-declined so the customer doesn't
          walk away with a QR pointing at an unpaid invoice. */}
      {!cardDeclined && invoiceId && serverUrl && (
        <div className="flex flex-col items-center gap-1 pt-2">
          <QrReceiptCode
            value={`${serverUrl}/invoices/${invoiceId}`}
            size={112}
            label="Scan for receipt"
          />
        </div>
      )}

      {/* Action buttons */}
      <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
        {/* WEB-FH-008: Print Receipt is hidden when the card declined to
            prevent the cashier from handing a misleading receipt to a
            customer whose payment never actually authorized. */}
        {!cardDeclined && (
          <button
            onClick={handlePrintReceipt}
            className="flex items-center gap-2 rounded-lg border border-surface-300 px-5 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <Printer className="h-4 w-4" />
            Print Receipt
          </button>
        )}
        {invoiceId && (
          <button
            onClick={handleViewInvoice}
            className="flex items-center gap-2 rounded-lg border border-surface-300 px-5 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <FileText className="h-4 w-4" />
            View Invoice
          </button>
        )}
        {ticketId && (
          <button
            onClick={handleViewTicket}
            className="flex items-center gap-2 rounded-lg border border-surface-300 px-5 py-2.5 text-sm font-medium text-surface-700 hover:bg-surface-50 dark:border-surface-600 dark:text-surface-300 dark:hover:bg-surface-800"
          >
            <ExternalLink className="h-4 w-4" />
            View Ticket
          </button>
        )}
        <button
          onClick={handleNewAction}
          className="flex items-center gap-2 rounded-lg bg-teal-600 px-5 py-2.5 text-sm font-semibold text-white hover:bg-teal-700"
        >
          <PlusCircle className="h-4 w-4" />
          New Sale
        </button>
      </div>
    </div>
  );
}
