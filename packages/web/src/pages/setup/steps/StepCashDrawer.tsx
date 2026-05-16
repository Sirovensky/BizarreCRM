import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import { Printer, Wifi, XCircle, PlayCircle, ArrowLeft, ArrowRight } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import type { StepProps } from '../wizardTypes';

/**
 * Step 20 — Cash drawer.
 *
 * Mirrors `#screen-20` in `mockups/web-setup-wizard.html`. The shop owner
 * picks how their cash drawer pops on a sale:
 *
 *   1. `kicked_by_printer` — receipt printer fires the kick code (most common
 *      for thermal POS printers; no extra config beyond the printer step).
 *   2. `network` — standalone IP-addressable drawer; reveals an address
 *      field for the LAN IP (or `host:port`).
 *   3. `none` — manual cash handling, no drawer integration.
 *
 * The "Pop drawer (test)" button calls the backend drawer test endpoint.
 * For printer-kicked drawers it reuses the receipt-printer connection
 * collected in the previous setup step.
 *
 * Persists `cash_drawer_driver` and (when applicable) `cash_drawer_address`
 * via `onUpdate`. The shell's bulk PUT /settings/config flushes them at the
 * end of the wizard.
 */

type CashDrawerDriver = 'kicked_by_printer' | 'network' | 'none';

interface DriverOption {
  id: CashDrawerDriver;
  label: string;
  description: string;
  Icon: typeof Printer;
}

const DRIVER_OPTIONS: ReadonlyArray<DriverOption> = [
  {
    id: 'kicked_by_printer',
    label: 'Kicked by receipt printer',
    description:
      'Receipt printer fires the kick pulse on a cash sale. Most common — no extra wiring.',
    Icon: Printer,
  },
  {
    id: 'network',
    label: 'Network IP drawer',
    description:
      'Standalone drawer on your LAN. Enter its IP address (or host:port).',
    Icon: Wifi,
  },
  {
    id: 'none',
    label: 'None / manual cash handling',
    description: 'No drawer integration. Cashier opens manually.',
    Icon: XCircle,
  },
];

interface NetworkAddressValidation {
  valid: boolean;
  message: string;
}

const IPV4_PART_PATTERN = /^\d{1,3}$/;
const HOSTNAME_LABEL_PATTERN = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/i;

const isValidIpv4Address = (host: string): boolean => {
  const parts = host.split('.');
  return (
    parts.length === 4 &&
    parts.every((part) => {
      if (!IPV4_PART_PATTERN.test(part)) {
        return false;
      }
      const octet = Number(part);
      return octet >= 0 && octet <= 255;
    })
  );
};

const isValidIpv6Address = (host: string): boolean => {
  try {
    return new URL(`http://[${host}]`).hostname === `[${host.toLowerCase()}]`;
  } catch {
    return false;
  }
};

const isValidHostname = (host: string): boolean => {
  if (host.length > 253 || host.includes('..')) {
    return false;
  }
  const normalized = host.endsWith('.') ? host.slice(0, -1) : host;
  return normalized
    .split('.')
    .every((label) => label.length > 0 && HOSTNAME_LABEL_PATTERN.test(label));
};

const isValidPort = (port: string): boolean => {
  if (!/^\d+$/.test(port)) {
    return false;
  }
  const portNumber = Number(port);
  return portNumber >= 1 && portNumber <= 65535;
};

const parseNetworkAddress = (value: string): { host: string; port?: string; bracketed: boolean } | null => {
  const trimmed = value.trim();
  if (trimmed.length === 0 || /\s/.test(trimmed) || /^[a-z][a-z0-9+.-]*:\/\//i.test(trimmed)) {
    return null;
  }

  if (trimmed.startsWith('[')) {
    const closeBracketIndex = trimmed.indexOf(']');
    if (closeBracketIndex <= 1) {
      return null;
    }
    const host = trimmed.slice(1, closeBracketIndex);
    const suffix = trimmed.slice(closeBracketIndex + 1);
    if (suffix.length === 0) {
      return { host, bracketed: true };
    }
    if (!suffix.startsWith(':') || suffix.length === 1) {
      return null;
    }
    return { host, port: suffix.slice(1), bracketed: true };
  }

  const colonCount = (trimmed.match(/:/g) ?? []).length;
  if (colonCount === 0) {
    return { host: trimmed, bracketed: false };
  }
  if (colonCount === 1) {
    const [host, port] = trimmed.split(':');
    if (!host || !port) {
      return null;
    }
    return { host, port, bracketed: false };
  }
  return { host: trimmed, bracketed: false };
};

const validateNetworkAddress = (value: string): NetworkAddressValidation => {
  const parsed = parseNetworkAddress(value);
  if (!parsed) {
    return {
      valid: false,
      message: 'Enter an IP address or hostname, optionally followed by a numeric port.',
    };
  }

  const hostIsValid = parsed.bracketed
    ? isValidIpv6Address(parsed.host)
    : isValidIpv4Address(parsed.host) ||
      isValidIpv6Address(parsed.host) ||
      (!/^[\d.]+$/.test(parsed.host) && isValidHostname(parsed.host));
  if (!hostIsValid) {
    return {
      valid: false,
      message: 'Enter a valid drawer IP address or hostname.',
    };
  }

  if (parsed.port !== undefined && !isValidPort(parsed.port)) {
    return {
      valid: false,
      message: 'Port must be a number from 1 to 65535.',
    };
  }

  return { valid: true, message: '' };
};

export function StepCashDrawer({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const initialDriver = (pending.cash_drawer_driver as CashDrawerDriver | undefined) ?? 'kicked_by_printer';
  const [driver, setDriver] = useState<CashDrawerDriver>(initialDriver);
  const [address, setAddress] = useState<string>(pending.cash_drawer_address ?? '');
  const [testing, setTesting] = useState(false);
  const addressValidation = validateNetworkAddress(address);
  const shouldShowAddressError = driver === 'network' && address.trim().length > 0 && !addressValidation.valid;
  const canContinue = driver !== 'network' || addressValidation.valid;

  // Push every change back to the wizard's pending bundle so the shell's
  // bulk PUT /settings/config picks it up at the end. We clear the address
  // when the driver isn't `network` to avoid persisting stale state.
  useEffect(() => {
    onUpdate({
      cash_drawer_driver: driver,
      cash_drawer_address: driver === 'network' && addressValidation.valid ? address.trim() : undefined,
    });
    // onUpdate is provided by the shell — its identity may change per render,
    // so we intentionally exclude it from deps to keep this a value-driven sync.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driver, address, addressValidation.valid]);

  const handleTestPop = async () => {
    if (driver === 'network' && !addressValidation.valid) {
      toast.error(addressValidation.message);
      return;
    }

    setTesting(true);
    try {
      await settingsApi.testCashDrawer({
        driver,
        address: driver === 'network' ? address.trim() : undefined,
        printer: {
          connection: pending.receipt_printer_connection,
          address: pending.receipt_printer_address,
        },
      });
      toast.success('Cash drawer kick command sent');
    } catch (err: unknown) {
      const message =
        (err as { response?: { data?: { message?: string } }; message?: string })?.response?.data?.message ||
        (err as { message?: string })?.message ||
        'Could not send the drawer kick command.';
      toast.error(message);
    } finally {
      setTesting(false);
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
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Cash drawer
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          How should the till pop on cash sales? You can change this later in Settings.
        </p>
      </div>

      <div className="space-y-6 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        <div className="space-y-3">
          {DRIVER_OPTIONS.map(({ id, label, description, Icon }) => {
            const isSelected = driver === id;
            return (
              <button
                key={id}
                type="button"
                onClick={() => setDriver(id)}
                className={
                  isSelected
                    ? 'flex w-full items-start gap-4 border-2 rounded-xl p-5 text-left transition-colors border-primary-500 bg-primary-50 dark:border-primary-400 dark:bg-primary-900/20'
                    : 'flex w-full items-start gap-4 border-2 rounded-xl p-5 text-left transition-colors border-surface-200 dark:border-surface-700 hover:border-surface-300 dark:hover:border-surface-600'
                }
                aria-pressed={isSelected}
              >
                <div
                  className={
                    isSelected
                      ? 'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-on-primary'
                      : 'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                  }
                >
                  <Icon className="h-5 w-5" />
                </div>
                <div className="flex-1">
                  <div
                    className={
                      isSelected
                        ? 'text-sm font-semibold text-primary-700 dark:text-primary-200'
                        : 'text-sm font-semibold text-surface-900 dark:text-surface-100'
                    }
                  >
                    {label}
                  </div>
                  <p
                    className={
                      isSelected
                        ? 'mt-0.5 text-xs text-primary-700/80 dark:text-primary-200/80'
                        : 'mt-0.5 text-xs text-surface-500 dark:text-surface-400'
                    }
                  >
                    {description}
                  </p>

                  {id === 'network' && isSelected ? (
                    <div className="mt-3">
                      <label
                        htmlFor="cash-drawer-address"
                        className="block text-xs font-medium text-surface-700 dark:text-surface-300"
                      >
                        Drawer IP address
                      </label>
                      <input
                        id="cash-drawer-address"
                        type="text"
                        value={address}
                        onChange={(e) => setAddress(e.target.value)}
                        onClick={(e) => e.stopPropagation()}
                        placeholder="192.168.1.50  or  192.168.1.50:8000"
                        aria-invalid={shouldShowAddressError}
                        aria-describedby="cash-drawer-address-help"
                        className={
                          shouldShowAddressError
                            ? 'mt-1 block w-full rounded-lg border border-error-500 bg-white px-3 py-2 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-error-500 focus:outline-none focus:ring-2 focus:ring-error-500/20 dark:border-error-400 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500'
                            : 'mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500'
                        }
                      />
                      <p
                        id="cash-drawer-address-help"
                        className={
                          shouldShowAddressError
                            ? 'mt-1 text-[11px] text-error-600 dark:text-error-400'
                            : 'mt-1 text-[11px] text-surface-500 dark:text-surface-400'
                        }
                      >
                        {shouldShowAddressError
                          ? addressValidation.message
                          : "LAN address of the drawer's network controller."}
                      </p>
                    </div>
                  ) : null}
                </div>
              </button>
            );
          })}
        </div>

        {driver !== 'none' ? (
          <div>
            <button
              type="button"
              onClick={handleTestPop}
              disabled={testing}
              className="btn btn-md inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              <PlayCircle className={`h-4 w-4 ${testing ? 'animate-pulse' : ''}`} />
              {testing ? 'Sending...' : 'Pop drawer (test)'}
            </button>
            <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
              Sends the ESC/POS drawer pulse through the selected route.
            </p>
          </div>
        ) : null}

        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="btn btn-lg flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="btn btn-lg rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip this step
            </button>
            <button
            type="button"
            onClick={onNext}
              disabled={!canContinue}
              className="btn btn-lg flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-on-primary shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-50"
            >
              Continue
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepCashDrawer;
