/**
 * AUDIT-MGT-018: Banner shown at the top of every authenticated page when
 * UPDATE_SKIP_TAG_VERIFY=true is active in the server environment.
 *
 * When the bypass is set, the signed-tag gate in `management:perform-update`
 * is skipped, meaning an update can be installed from an unsigned git tag.
 * This removes the supply-chain integrity check (SEC-H95) that prevents a
 * tampered release from being installed. The banner makes the degraded
 * security state visible to the operator on every page, not just the Updates
 * page.
 */
import { ShieldAlert, X } from 'lucide-react';
import { useState, useEffect } from 'react';
import { getAPI } from '@/api/bridge';
import { handleApiResponse } from '@/utils/handleApiResponse';

export function BannerTagVerifyWarning() {
  const [bypass, setBypass] = useState<boolean | null>(null);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    getAPI().system.getTagVerifyStatus().then((res) => {
      // DASH-ELEC-048: propagate 401 so auth expiry is detected here, not
      // only on the next health poll (up to 60 s later).
      if (handleApiResponse(res)) return;
      if (res.success && res.data) {
        setBypass(res.data.bypass);
      }
    }).catch(() => {
      // If the IPC call fails we cannot determine status — hide the banner.
      setBypass(false);
    });
  }, []);

  // Hide when bypass is not active, status unknown, or user dismissed.
  if (bypass !== true || dismissed) return null;

  return (
    <div
      role="alert"
      className="flex items-start gap-3 px-4 py-3 bg-red-950/40 border-b border-red-800/60 text-red-300"
    >
      <ShieldAlert className="w-4 h-4 mt-0.5 flex-shrink-0 text-red-400" />
      <div className="flex-1 min-w-0">
        <span className="text-xs font-semibold text-red-300">
          UPDATE_SKIP_TAG_VERIFY is active —
        </span>{' '}
        <span className="text-xs text-red-400">
          Signed-tag verification is bypassed. Updates can be installed from
          unsigned git tags, removing the SEC-H95 supply-chain integrity check.
          Unset UPDATE_SKIP_TAG_VERIFY and restart the dashboard to re-enable
          the gate.
        </span>
      </div>
      <button
        onClick={() => setDismissed(true)}
        className="flex-shrink-0 text-red-500 hover:text-red-300 transition-colors"
        aria-label="Dismiss warning"
      >
        <X className="w-4 h-4" />
      </button>
    </div>
  );
}
