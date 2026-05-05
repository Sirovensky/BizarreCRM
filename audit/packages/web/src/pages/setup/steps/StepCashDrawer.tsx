import { useEffect, useState } from 'react';
import type { JSX } from 'react';
import { Printer, Wifi, XCircle, PlayCircle, ArrowLeft, ArrowRight } from 'lucide-react';
import toast from 'react-hot-toast';
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
 * The "Pop drawer (test)" button is a placeholder — actual hardware kick is
 * wired up later by the cash-drawer service. For now it just emits a toast
 * so the owner sees the button works.
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

  // Push every change back to the wizard's pending bundle so the shell's
  // bulk PUT /settings/config picks it up at the end. We clear the address
  // when the driver isn't `network` to avoid persisting stale state.
  useEffect(() => {
    onUpdate({
      cash_drawer_driver: driver,
      cash_drawer_address: driver === 'network' ? address : undefined,
    });
    // onUpdate is provided by the shell — its identity may change per render,
    // so we intentionally exclude it from deps to keep this a value-driven sync.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driver, address]);

  const handleTestPop = () => {
    toast('Test pop will be wired with the cash-drawer service later.', {
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
                      ? 'flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-primary-500 text-primary-950'
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
                        className="mt-1 block w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm text-surface-900 placeholder-surface-400 shadow-sm focus:border-primary-500 focus:outline-none focus:ring-2 focus:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-100 dark:placeholder-surface-500"
                      />
                      <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
                        LAN address of the drawer's network controller.
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
              className="inline-flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-4 py-2.5 text-sm font-semibold text-surface-700 shadow-sm transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
            >
              <PlayCircle className="h-4 w-4" />
              Pop drawer (test)
            </button>
            <p className="mt-1 text-[11px] text-surface-500 dark:text-surface-400">
              Stub for now — wires up to the cash-drawer service in a later step.
            </p>
          </div>
        ) : null}

        <div className="flex items-center justify-between gap-3 pt-2">
          <button
            type="button"
            onClick={onBack}
            className="flex items-center gap-2 rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            <ArrowLeft className="h-4 w-4" />
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
              <ArrowRight className="h-4 w-4" />
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepCashDrawer;
