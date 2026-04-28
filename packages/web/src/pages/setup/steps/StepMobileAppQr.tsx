import { useEffect, useState, type JSX } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { Copy, Smartphone, Wifi, Loader2 } from 'lucide-react';
import { toast } from 'react-hot-toast';
import type { StepProps } from '../wizardTypes';

/**
 * Step 24 — Mobile app QR (LAN pairing).
 *
 * Behavior:
 *  - Fetches `GET /api/v1/info` to get `{ lan_ip, port, server_url }`.
 *    Per CLAUDE.md item #4 the server returns the LAN URL we want techs'
 *    phones to point at (must be LAN IP, not localhost). Defensive: handles
 *    both raw `{ lan_ip, ... }` and the project's standard `{ success,
 *    data: { ... } }` envelope.
 *  - Renders a large QR encoding the `server_url` and a Copy-URL button.
 *  - Purely informational — no PendingWrites updates. Continue just calls
 *    `onNext()`. Skip is also allowed (owner can hand out QR later from
 *    Settings).
 */
interface InfoResponse {
  lan_ip?: string;
  port?: number | string;
  server_url?: string;
}

function unwrapInfo(json: unknown): InfoResponse {
  if (!json || typeof json !== 'object') return {};
  const obj = json as Record<string, unknown>;
  // Standard envelope: { success, data: { ... } }
  if ('success' in obj && 'data' in obj && obj.data && typeof obj.data === 'object') {
    return obj.data as InfoResponse;
  }
  // Raw shape
  return obj as InfoResponse;
}

export function StepMobileAppQr({ onNext, onBack, onSkip }: StepProps): JSX.Element {
  const [serverUrl, setServerUrl] = useState<string>('');
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string>('');

  useEffect(() => {
    let cancelled = false;
    (async () => {
      setLoading(true);
      setError('');
      try {
        const res = await fetch('/api/v1/info');
        const json = await res.json();
        if (cancelled) return;
        const info = unwrapInfo(json);
        // Prefer explicit server_url; fall back to building from lan_ip + port.
        let url = info.server_url ?? '';
        if (!url && info.lan_ip) {
          const port = info.port ?? 443;
          // Omit :443 since it's the default https port.
          url = String(port) === '443'
            ? `https://${info.lan_ip}`
            : `https://${info.lan_ip}:${port}`;
        }
        if (!url) {
          throw new Error('Server did not return a LAN URL');
        }
        setServerUrl(url);
      } catch (err: unknown) {
        if (cancelled) return;
        const msg =
          (err as { message?: string })?.message ||
          'Could not detect the shop LAN URL. Pair phones manually from Settings later.';
        setError(msg);
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  const handleCopy = async () => {
    if (!serverUrl) return;
    try {
      await navigator.clipboard.writeText(serverUrl);
      toast.success('URL copied to clipboard');
    } catch {
      toast.error('Could not copy — select and copy manually');
    }
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <div className="mx-auto mb-3 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-100 dark:bg-primary-500/10">
          <Smartphone className="h-7 w-7 text-primary-600 dark:text-primary-400" />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Pair your staff phones
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Scan to point the BizarreCRM staff app at this shop.
        </p>
      </div>

      <div className="mx-auto max-w-3xl rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="grid grid-cols-1 gap-8 md:grid-cols-[240px_1fr]">
          {/* Left: QR */}
          <div>
            <div className="flex aspect-square w-full items-center justify-center rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-600">
              {loading ? (
                <Loader2 className="h-8 w-8 animate-spin text-surface-400" />
              ) : serverUrl ? (
                <QRCodeSVG
                  value={serverUrl}
                  size={200}
                  bgColor="#ffffff"
                  fgColor="#000000"
                  level="M"
                  marginSize={1}
                  className="h-full w-full"
                />
              ) : (
                <Smartphone className="h-12 w-12 text-surface-300 dark:text-surface-500" />
              )}
            </div>
            <p className="mt-2 text-center text-xs text-surface-500 dark:text-surface-400">
              Scan with the BizarreCRM staff app
            </p>
          </div>

          {/* Right: instructions */}
          <div>
            <h2 className="font-['League_Spartan'] text-xl font-bold text-surface-900 dark:text-surface-50">
              Three quick steps
            </h2>
            <ol className="mt-3 space-y-2 text-sm text-surface-700 dark:text-surface-300">
              <li className="flex gap-2">
                <span className="font-semibold text-primary-700 dark:text-primary-400">1.</span>
                <span>Install BizarreCRM staff app from the Play Store / App Store.</span>
              </li>
              <li className="flex gap-2">
                <span className="font-semibold text-primary-700 dark:text-primary-400">2.</span>
                <span>
                  Open the app and tap <strong>"Pair with shop"</strong>.
                </span>
              </li>
              <li className="flex gap-2">
                <span className="font-semibold text-primary-700 dark:text-primary-400">3.</span>
                <span>Scan this QR code.</span>
              </li>
            </ol>

            {/* Copyable URL */}
            <label className="mt-5 mb-1.5 block text-xs font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
              Shop URL
            </label>
            <div className="flex items-center gap-2">
              <code className="flex-1 select-all break-all rounded bg-surface-100 p-2 font-mono text-sm text-surface-900 dark:bg-surface-700 dark:text-surface-100">
                {loading ? 'Detecting…' : serverUrl || '—'}
              </code>
              <button
                type="button"
                onClick={handleCopy}
                disabled={!serverUrl}
                className="inline-flex items-center gap-1 rounded-md border border-surface-300 px-2 py-1.5 text-xs font-medium text-surface-700 hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-600 dark:text-surface-200 dark:hover:bg-surface-700"
                aria-label="Copy URL"
              >
                <Copy className="h-3.5 w-3.5" />
                Copy
              </button>
            </div>

            {error ? (
              <p className="mt-3 text-xs text-amber-700 dark:text-amber-400">{error}</p>
            ) : null}

            <div className="mt-5 flex items-start gap-2 rounded-xl bg-surface-50 p-3 text-xs text-surface-600 dark:bg-surface-900/40 dark:text-surface-400">
              <Wifi className="mt-0.5 h-4 w-4 flex-shrink-0 text-surface-500 dark:text-surface-400" />
              <p>
                If your phones are not on the shop Wi-Fi, use Tailscale or share LAN access first.
                Public Wi-Fi pairing is not supported.
              </p>
            </div>
          </div>
        </div>

        <div className="mt-8 flex flex-col items-start justify-between gap-3 border-t border-surface-200 pt-5 sm:flex-row sm:items-center dark:border-surface-700">
          <button
            type="button"
            onClick={onBack}
            className="text-sm font-medium text-surface-600 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
          >
            ← Back
          </button>
          <div className="flex items-center gap-3">
            <button
              type="button"
              onClick={handleSkip}
              className="text-sm font-medium text-surface-500 hover:text-surface-800 hover:underline dark:text-surface-400 dark:hover:text-surface-200"
            >
              Skip
            </button>
            <button
              type="button"
              onClick={onNext}
              className="flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400"
            >
              Continue
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepMobileAppQr;
