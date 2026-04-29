import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import { Printer, Usb, Wifi, Bluetooth, XCircle, Play } from 'lucide-react';
import toast from 'react-hot-toast';
import type { StepProps } from '../wizardTypes';

/**
 * Step 19 — Receipt printer.
 *
 * Mirrors `#screen-19` in `docs/setup-wizard-preview.html` and follows the
 * same small-card pattern used by `StepCashDrawer`. Three sections in a
 * single card:
 *
 *   1. Driver picker (radio) — escpos / star / brother_ql / none.
 *   2. Connection (radio, hidden when driver === 'none') — usb / network /
 *      bluetooth.
 *   3. Address (text input, hidden when driver === 'none') — single field
 *      whose label and placeholder change based on connection type.
 *
 * "Print test receipt" button is visible only when driver !== 'none'. For
 * now it just emits a toast — actual ESC/POS service hookup lands later.
 *
 * Persists `receipt_printer_driver`, `receipt_printer_connection`, and
 * `receipt_printer_address` via `onUpdate`. The shell flushes everything
 * to `store_config` via the bulk PUT /settings/config at the end of the
 * wizard (or on Skip).
 */

type ReceiptPrinterDriver = 'escpos' | 'star' | 'brother_ql' | 'none';
type ReceiptPrinterConnection = 'usb' | 'network' | 'bluetooth';

interface DriverOption {
  id: ReceiptPrinterDriver;
  label: string;
  description: string;
  Icon: typeof Printer;
}

interface ConnectionOption {
  id: ReceiptPrinterConnection;
  label: string;
  description: string;
  Icon: typeof Printer;
}

const DRIVER_OPTIONS: ReadonlyArray<DriverOption> = [
  {
    id: 'escpos',
    label: 'ESC/POS (most common)',
    description: 'Generic Epson, Citizen, Bixolon, Xprinter — the default for thermal POS.',
    Icon: Printer,
  },
  {
    id: 'star',
    label: 'Star Micronics',
    description: 'TSP100/TSP650/TSP143 series. Star uses its own command set.',
    Icon: Printer,
  },
  {
    id: 'brother_ql',
    label: 'Brother QL',
    description: 'Brother QL label printers (QL-820NWB, QL-1110NWB, etc.).',
    Icon: Printer,
  },
  {
    id: 'none',
    label: 'None / no thermal printer',
    description: 'Skip hardware printing. Receipts can still email + PDF.',
    Icon: XCircle,
  },
];

const CONNECTION_OPTIONS: ReadonlyArray<ConnectionOption> = [
  {
    id: 'usb',
    label: 'USB',
    description: 'Wired direct to this machine.',
    Icon: Usb,
  },
  {
    id: 'network',
    label: 'Network IP',
    description: 'Printer on your LAN.',
    Icon: Wifi,
  },
  {
    id: 'bluetooth',
    label: 'Bluetooth (advanced)',
    description: 'Paired BT printer.',
    Icon: Bluetooth,
  },
];

interface AddressFieldCopy {
  label: string;
  placeholder: string;
  hint: string;
}

const ADDRESS_COPY: Record<ReceiptPrinterConnection, AddressFieldCopy> = {
  usb: {
    label: 'Device path',
    placeholder: '/dev/usb/lp0   or   COM3',
    hint: 'Linux device node (e.g. /dev/usb/lp0) or Windows COM port (e.g. COM3).',
  },
  network: {
    label: 'IP address',
    placeholder: '192.168.1.50  or  192.168.1.50:9100',
    hint: 'LAN address of the printer. Most network thermals use port 9100.',
  },
  bluetooth: {
    label: 'Bluetooth MAC address',
    placeholder: '00:11:22:33:44:55',
    hint: 'Device MAC address from your OS Bluetooth pairing list.',
  },
};

export function StepReceiptPrinter({
  pending,
  onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  const initialDriver = (pending.receipt_printer_driver as ReceiptPrinterDriver | undefined) ?? 'escpos';
  const initialConnection =
    (pending.receipt_printer_connection as ReceiptPrinterConnection | undefined) ?? 'usb';

  const [driver, setDriver] = useState<ReceiptPrinterDriver>(initialDriver);
  const [connection, setConnection] = useState<ReceiptPrinterConnection>(initialConnection);
  const [address, setAddress] = useState<string>(pending.receipt_printer_address ?? '');

  // Push every change back into the wizard's pending bundle. When the driver
  // is 'none' we explicitly clear connection + address so we don't persist
  // stale values from an earlier selection.
  useEffect(() => {
    if (driver === 'none') {
      onUpdate({
        receipt_printer_driver: 'none',
        receipt_printer_connection: undefined,
        receipt_printer_address: undefined,
      });
      return;
    }
    onUpdate({
      receipt_printer_driver: driver,
      receipt_printer_connection: connection,
      receipt_printer_address: address || undefined,
    });
    // onUpdate identity may change per render — treat as a value-driven sync.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driver, connection, address]);

  const handleTestPrint = () => {
    toast('Test print will be wired with ESC/POS service once driver lands.', {
      icon: 'i',
    });
  };

  const handleSkip = () => {
    if (onSkip) {
      onSkip();
    } else {
      onNext();
    }
  };

  const showConnectionAndAddress = driver !== 'none';
  const addressCopy = ADDRESS_COPY[connection];

  return (
    <div className="mx-auto max-w-2xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mb-6 text-center">
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Receipt printer
        </h1>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          Thermal 80mm USB or network. Skip if you don't have one yet — receipts can still email.
        </p>
      </div>

      <div className="space-y-8 rounded-2xl border border-surface-200 bg-white p-8 shadow-xl dark:border-surface-700 dark:bg-surface-800">
        {/* ─── 1. Driver picker (2x2 grid) ──────────────────────────────── */}
        <div>
          <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
            Driver
          </h2>
          <div className="grid grid-cols-1 gap-3 sm:grid-cols-2">
            {DRIVER_OPTIONS.map(({ id, label, description, Icon }) => {
              const isSelected = driver === id;
              return (
                <button
                  key={id}
                  type="button"
                  onClick={() => setDriver(id)}
                  className={
                    isSelected
                      ? 'flex items-start gap-3 rounded-xl border-2 border-primary-500 bg-primary-50 p-4 text-left transition-colors dark:border-primary-400 dark:bg-primary-900/20'
                      : 'flex items-start gap-3 rounded-xl border-2 border-surface-200 p-4 text-left transition-colors hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600'
                  }
                  aria-pressed={isSelected}
                >
                  <div
                    className={
                      isSelected
                        ? 'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950'
                        : 'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                    }
                  >
                    <Icon className="h-4 w-4" />
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
                  </div>
                </button>
              );
            })}
          </div>
        </div>

        {/* ─── 2. Connection (3-col) — hidden when driver === 'none' ────── */}
        {showConnectionAndAddress ? (
          <div>
            <h2 className="mb-3 text-sm font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400">
              Connection
            </h2>
            <div className="grid grid-cols-1 gap-3 sm:grid-cols-3">
              {CONNECTION_OPTIONS.map(({ id, label, description, Icon }) => {
                const isSelected = connection === id;
                return (
                  <button
                    key={id}
                    type="button"
                    onClick={() => setConnection(id)}
                    className={
                      isSelected
                        ? 'flex flex-col items-start gap-2 rounded-xl border-2 border-primary-500 bg-primary-50 p-4 text-left transition-colors dark:border-primary-400 dark:bg-primary-900/20'
                        : 'flex flex-col items-start gap-2 rounded-xl border-2 border-surface-200 p-4 text-left transition-colors hover:border-surface-300 dark:border-surface-700 dark:hover:border-surface-600'
                    }
                    aria-pressed={isSelected}
                  >
                    <div
                      className={
                        isSelected
                          ? 'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950'
                          : 'flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400'
                      }
                    >
                      <Icon className="h-4 w-4" />
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
                    </div>
                  </button>
                );
              })}
            </div>
          </div>
        ) : null}

        {/* ─── 3. Address — single field, label flips per connection ────── */}
        {showConnectionAndAddress ? (
          <div>
            <label
              htmlFor="receipt-printer-address"
              className="block text-sm font-semibold uppercase tracking-wide text-surface-500 dark:text-surface-400"
            >
              {addressCopy.label}
            </label>
            <input
              id="receipt-printer-address"
              type="text"
              value={address}
              onChange={(e) => setAddress(e.target.value)}
              placeholder={addressCopy.placeholder}
              className="mt-2 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2.5 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
            />
            <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
              {addressCopy.hint}
            </p>
          </div>
        ) : null}

        {/* ─── Test print (visible only when a driver is selected) ──────── */}
        {showConnectionAndAddress ? (
          <div>
            <button
              type="button"
              onClick={handleTestPrint}
              className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              <Play className="h-4 w-4" />
              Print test receipt
            </button>
            <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
              Stub for now — wires up to the ESC/POS service in a later step.
            </p>
          </div>
        ) : null}

        {/* ─── Footer nav ───────────────────────────────────────────────── */}
        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
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

export default StepReceiptPrinter;
