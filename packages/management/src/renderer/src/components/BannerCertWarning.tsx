/**
 * AUDIT-MGT-006: Banner shown at the top of every authenticated page when TLS
 * certificate fingerprint pinning is disabled (server.cert absent on first run).
 *
 * Without pinning, the connection to the local CRM server is still HTTPS but a
 * process that port-squats on 443 before the real server starts could present
 * its own cert and MITM API calls — including credential submission. This banner
 * makes the operator aware of the degraded security state so they can start the
 * CRM server at least once to generate certs before using the dashboard.
 */
import { ShieldAlert, X } from 'lucide-react';
import { useState, useEffect } from 'react';
import { getAPI, type CertPinningStatus } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';

// DASH-ELEC-248: persist dismissal to localStorage; re-show after 24h or on
// a fresh cold-start (page reload without a stored timestamp).
const LS_KEY = 'banner-cert-warning-dismissed-at';
const RESHOW_MS = 24 * 60 * 60 * 1000; // 24 hours

function isSuppressed(): boolean {
  try {
    const raw = localStorage.getItem(LS_KEY);
    if (!raw) return false;
    return Date.now() - Number(raw) < RESHOW_MS;
  } catch {
    return false;
  }
}

export function BannerCertWarning() {
  const [status, setStatus] = useState<CertPinningStatus | null>(null);
  const [dismissed, setDismissed] = useState(() => isSuppressed());

  useEffect(() => {
    getAPI().system.getCertPinningStatus().then((res) => {
      // DASH-ELEC-048: propagate 401 so auth expiry is detected here, not
      // only on the next health poll (up to 60 s later).
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setStatus(res.data);
      }
    }).catch(() => {
      // If the IPC call fails we can't determine status — hide the banner.
      setStatus({ enabled: true });
    });
  }, []);

  function handleDismiss() {
    try { localStorage.setItem(LS_KEY, String(Date.now())); } catch { /* ignore */ }
    setDismissed(true);
  }

  const expiryDays = status?.daysUntilExpiry;
  const hasExpiryWarning =
    status?.enabled === true &&
    typeof expiryDays === 'number' &&
    expiryDays <= 30;

  // Hide when pinning is enabled and cert is not near expiry, status unknown
  // (null), or user dismissed.
  if (dismissed || !status || (status.enabled !== false && !hasExpiryWarning)) return null;

  const severity = status.enabled === false || (typeof expiryDays === 'number' && expiryDays > 7)
    ? 'amber'
    : 'red';
  const tone = severity === 'red'
    ? {
        wrapper: 'bg-red-950/45 border-red-800/70 text-red-300',
        icon: 'text-red-400',
        title: 'text-red-300',
        body: 'text-red-400',
        button: 'text-red-500 hover:text-red-300',
      }
    : {
        wrapper: 'bg-amber-950/40 border-amber-800/60 text-amber-300',
        icon: 'text-amber-400',
        title: 'text-amber-300',
        body: 'text-amber-400',
        button: 'text-amber-500 hover:text-amber-300',
      };
  const validToText = status.validTo
    ? new Date(status.validTo).toLocaleString(undefined, {
        dateStyle: 'medium',
        timeStyle: 'short',
      })
    : null;
  const expiryDaysForMessage = typeof expiryDays === 'number' ? expiryDays : 0;
  const title = status.enabled === false
    ? 'TLS cert pinning disabled —'
    : expiryDaysForMessage <= 0
      ? 'TLS certificate expired —'
      : 'TLS certificate expires soon —';
  const message = status.enabled === false
    ? status.reason ??
      'server.cert not found. Start the CRM server at least once to generate certs and enable fingerprint pinning.'
    : expiryDaysForMessage <= 0
      ? `server.cert expired${validToText ? ` on ${validToText}` : ''}. Regenerate server certificates before relying on the dashboard.`
      : `server.cert expires${validToText ? ` on ${validToText}` : ''} (${expiryDaysForMessage} day${expiryDaysForMessage === 1 ? '' : 's'} left). Rotate certificates before expiry.`;

  return (
    <div
      role="alert"
      className={`flex items-start gap-3 px-4 py-3 border-b ${tone.wrapper}`}
    >
      <ShieldAlert className={`w-4 h-4 mt-0.5 flex-shrink-0 ${tone.icon}`} />
      <div className="flex-1 min-w-0">
        <span className={`text-xs font-semibold ${tone.title}`}>
          {title}
        </span>{' '}
        <span className={`text-xs ${tone.body}`}>
          {message}
        </span>
      </div>
      <button
        onClick={handleDismiss}
        className={`flex-shrink-0 transition-colors ${tone.button}`}
        aria-label="Dismiss"
      >
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
