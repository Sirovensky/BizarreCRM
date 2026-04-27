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
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';

export function BannerCertWarning() {
  const [pinningEnabled, setPinningEnabled] = useState<boolean | null>(null);
  const [reason, setReason] = useState<string | undefined>(undefined);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    getAPI().system.getCertPinningStatus().then((res) => {
      // DASH-ELEC-048: propagate 401 so auth expiry is detected here, not
      // only on the next health poll (up to 60 s later).
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setPinningEnabled(res.data.enabled);
        setReason(res.data.reason);
      }
    }).catch(() => {
      // If the IPC call fails we can't determine status — hide the banner.
      setPinningEnabled(true);
    });
  }, []);

  // Hide when pinning is enabled, status unknown (null), or user dismissed.
  if (pinningEnabled !== false || dismissed) return null;

  return (
    <div
      role="alert"
      className="flex items-start gap-3 px-4 py-3 bg-amber-950/40 border-b border-amber-800/60 text-amber-300"
    >
      <ShieldAlert className="w-4 h-4 mt-0.5 flex-shrink-0 text-amber-400" />
      <div className="flex-1 min-w-0">
        <span className="text-xs font-semibold text-amber-300">
          TLS cert pinning disabled —
        </span>{' '}
        <span className="text-xs text-amber-400">
          {reason ??
            'server.cert not found. Start the CRM server at least once to generate certs and enable fingerprint pinning.'}
        </span>
      </div>
      <button
        onClick={() => setDismissed(true)}
        className="flex-shrink-0 text-amber-500 hover:text-amber-300 transition-colors"
        aria-label="Dismiss"
      >
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
