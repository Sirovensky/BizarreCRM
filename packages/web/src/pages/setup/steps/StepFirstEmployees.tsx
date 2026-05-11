/**
 * StepFirstEmployees — Setup wizard Step 15.
 *
 * Lets the owner invite 1-3 staff members up front so they're not alone in the
 * tickets list on day one. The step renders an editable list of rows (name +
 * email + role) plus a "+ Add another employee" button. On "Send invites" each
 * non-empty, valid row is POSTed individually to the setup invite endpoint with
 * `send_invite: true`; per-row status badges reflect account creation and email
 * delivery. After all rows finish (success or failure), the wizard advances via
 * `onNext()`. "Skip this step" advances without sending.
 *
 * Mockup: `mockups/web-setup-wizard.html` `<section id="screen-15">`.
 */
import { useId, useState } from 'react';
import type { JSX } from 'react';
import {
  Plus,
  Trash2,
  Shield,
  Wrench,
  Calculator,
  CheckCircle2,
  XCircle,
  Loader2,
} from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { settingsApi } from '@/api/endpoints';
import { validateEmail } from '@/services/validationService';

type EmployeeRole = 'admin' | 'tech' | 'cashier';
type RowStatus = 'idle' | 'sending' | 'sent' | 'created' | 'failed';

interface EmployeeInvite {
  id: string;
  name: string;
  email: string;
  role: EmployeeRole;
  /** Self-host PIN for clock-in/out + register access. Optional 4-digit string.
   *  Mockup explicitly includes this field per mockups/web-setup-wizard.html
   *  #screen-15. SaaS shops can ignore — backend drops the value if PIN-auth
   *  isn't enabled for the tenant. */
  pin?: string;
}

interface RowError {
  name?: string;
  email?: string;
  pin?: string;
}

const OBVIOUS_EMPLOYEE_PINS = new Set([
  '0000',
  '1111',
  '2222',
  '3333',
  '4444',
  '5555',
  '6666',
  '7777',
  '8888',
  '9999',
  '1234',
  '4321',
  '0123',
  '3210',
  '9876',
  '2580',
  '0852',
  '1212',
  '1122',
  '1313',
  '6969',
  '2000',
  '2024',
  '2025',
  '2026',
]);

/** Generate a stable client-only id used as the React key for each row. */
function makeRowId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return `row-${Math.random().toString(36).slice(2)}-${Date.now().toString(36)}`;
}

function emptyRow(): EmployeeInvite {
  return { id: makeRowId(), name: '', email: '', role: 'tech', pin: '' };
}

/** A row is "empty" if both name and email are blank — treated as skipped. */
function isEmptyRow(row: EmployeeInvite): boolean {
  return row.name.trim() === '' && row.email.trim() === '';
}

function isSequentialPin(pin: string): boolean {
  return '0123456789'.includes(pin) || '9876543210'.includes(pin);
}

function isWeakEmployeePin(pin: string): boolean {
  return (
    OBVIOUS_EMPLOYEE_PINS.has(pin) ||
    isSequentialPin(pin) ||
    pin.slice(0, 2) === pin.slice(2)
  );
}

/**
 * Validate one row. Returns null if the row is fully valid OR fully empty
 * (empty rows are skipped, not errored). Otherwise returns per-field errors.
 */
function validateRow(row: EmployeeInvite): RowError | null {
  if (isEmptyRow(row)) return null;
  const errors: RowError = {};
  const name = row.name.trim();
  if (name.length < 2) errors.name = 'Name must be at least 2 characters.';
  const emailErr = validateEmail(row.email.trim());
  if (emailErr) errors.email = emailErr;
  const pin = row.pin?.trim() ?? '';
  if (pin && !/^\d{4}$/.test(pin)) {
    errors.pin = 'Enter exactly 4 digits, or leave PIN blank.';
  } else if (pin && isWeakEmployeePin(pin)) {
    errors.pin = 'Choose a less obvious PIN; avoid repeats, sequences, and default values.';
  }
  return Object.keys(errors).length > 0 ? errors : null;
}

const ROLE_OPTIONS: ReadonlyArray<{
  value: EmployeeRole;
  label: string;
  Icon: typeof Shield;
}> = [
  { value: 'admin', label: 'Admin', Icon: Shield },
  { value: 'tech', label: 'Technician', Icon: Wrench },
  { value: 'cashier', label: 'Cashier', Icon: Calculator },
];

export function StepFirstEmployees({
  pending: _pending,
  onUpdate: _onUpdate,
  onNext,
  onBack,
  onSkip,
}: StepProps): JSX.Element {
  void _pending;
  void _onUpdate;
  const fieldIdPrefix = useId();
  const [rows, setRows] = useState<EmployeeInvite[]>(() => [emptyRow()]);
  const [statuses, setStatuses] = useState<Record<string, RowStatus>>({});
  const [messages, setMessages] = useState<Record<string, string>>({});
  const [errors, setErrors] = useState<Record<string, RowError>>({});
  const [submitting, setSubmitting] = useState(false);
  const [retryDisabled, setRetryDisabled] = useState<Record<string, boolean>>({});

  const updateRow = (id: string, patch: Partial<EmployeeInvite>) => {
    setRows((prev) =>
      prev.map((r) => (r.id === id ? { ...r, ...patch } : r)),
    );
    // Clear inline error for the row on edit so the user can re-validate.
    setErrors((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    setMessages((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
  };

  const addRow = () => {
    setRows((prev) => [...prev, emptyRow()]);
  };

  const removeRow = (id: string) => {
    setRows((prev) => (prev.length <= 1 ? prev : prev.filter((r) => r.id !== id)));
    setStatuses((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    setErrors((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
    setMessages((prev) => {
      if (!prev[id]) return prev;
      const next = { ...prev };
      delete next[id];
      return next;
    });
  };

  const sendOne = async (row: EmployeeInvite): Promise<boolean> => {
    setStatuses((prev) => ({ ...prev, [row.id]: 'sending' }));
    setMessages((prev) => {
      if (!prev[row.id]) return prev;
      const next = { ...prev };
      delete next[row.id];
      return next;
    });
    try {
      const res = await settingsApi.setupInvite({
        name: row.name.trim(),
        email: row.email.trim(),
        role: row.role,
        send_invite: true,
        // PIN is optional. 4-digit numeric used by self-host shops for
        // clock-in/out + register access. Empty string is sent as undefined so
        // backend doesn't try to hash an empty PIN.
        pin: row.pin && row.pin.length === 4 ? row.pin : undefined,
      });
      const deliveryStatus = res.data?.data?.delivery?.status;
      if (deliveryStatus === 'sent') {
        setStatuses((prev) => ({ ...prev, [row.id]: 'sent' }));
        setMessages((prev) => ({ ...prev, [row.id]: 'Email invite delivered.' }));
      } else if (deliveryStatus === 'not_configured') {
        setStatuses((prev) => ({ ...prev, [row.id]: 'created' }));
        setMessages((prev) => ({ ...prev, [row.id]: 'Account created; SMTP is not configured yet.' }));
      } else if (deliveryStatus === 'failed') {
        setStatuses((prev) => ({ ...prev, [row.id]: 'created' }));
        setMessages((prev) => ({ ...prev, [row.id]: 'Account created; invite email failed to send.' }));
      } else {
        setStatuses((prev) => ({ ...prev, [row.id]: 'created' }));
        setMessages((prev) => ({ ...prev, [row.id]: 'Account created.' }));
      }
      return true;
    } catch (err) {
      const message =
        (err as { response?: { data?: { message?: string } }; message?: string })?.response?.data?.message ||
        (err as { message?: string })?.message ||
        'Invite failed.';
      setStatuses((prev) => ({ ...prev, [row.id]: 'failed' }));
      setMessages((prev) => ({ ...prev, [row.id]: message }));
      return false;
    }
  };

  const handleSendInvites = async () => {
    if (submitting) return;

    // 1. Validate every row. Empty rows are skipped silently.
    const nextErrors: Record<string, RowError> = {};
    for (const row of rows) {
      const err = validateRow(row);
      if (err) nextErrors[row.id] = err;
    }
    setErrors(nextErrors);
    if (Object.keys(nextErrors).length > 0) return;

    // 2. Collect rows to actually send.
    const toSend = rows.filter((r) => !isEmptyRow(r));
    if (toSend.length === 0) return;

    // WEB-UIUX-857: explicit confirm before invite emails fire. Invites
    // create real accounts and trigger real outbound email; mistyped
    // addresses become orphaned accounts with no recall path. A single
    // confirm with the recipient list lets the operator catch typos
    // before the irreversible step.
    const recipientList = toSend
      .map((r) => `• ${r.name.trim()} <${r.email.trim()}> · ${r.role}`)
      .join('\n');
    const ok = window.confirm(
      `Send invite emails now to:\n\n${recipientList}\n\nAccounts are created immediately and the invite email goes out. Typos cannot be undone from the wizard.`,
    );
    if (!ok) return;

    // 3. Fire requests. Continue past per-row failures so the user sees the
    //    full picture; the retry link in the failed badge re-tries that row.
    setSubmitting(true);
    await Promise.all(toSend.map((row) => sendOne(row)));
    setSubmitting(false);

    // 4. Advance regardless of per-row failures — the user can review and
    //    retry from the Settings → Team page after the wizard finishes.
    onNext();
  };

  const handleRetry = (id: string) => {
    if (retryDisabled[id]) return;
    const row = rows.find((r) => r.id === id);
    if (!row) return;
    setRetryDisabled((prev) => ({ ...prev, [id]: true }));
    setTimeout(() => {
      setRetryDisabled((prev) => {
        const next = { ...prev };
        delete next[id];
        return next;
      });
    }, 1000);
    void sendOne(row);
  };

  const handleSkip = () => {
    (onSkip ?? onNext)();
  };

  const hasInviteReady = rows.some((row) => !isEmptyRow(row));
  const canSendInvites =
    hasInviteReady &&
    rows.every((row) => isEmptyRow(row) || validateRow(row) === null);

  return (
    <div className="mx-auto max-w-3xl">
      <div className="mb-6 flex justify-center">
</div>

      <div className="mx-auto max-w-3xl rounded-2xl border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800">
        <h1 className="font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          Add your team
        </h1>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          Invite 1-3 staff now or skip — without team accounts you'll be alone
          on the tickets list. Invitees get an email link to set their own
          password.
        </p>
        <p className="mt-3 rounded-lg border border-amber-200 bg-amber-50 px-3 py-2 text-xs text-amber-900 dark:border-amber-400/30 dark:bg-amber-500/10 dark:text-amber-100">
          Employee PINs are optional, but they unlock clock-in and register
          actions when PIN access is enabled. Use a unique 4-digit PIN for each
          employee and avoid shared, repeated, sequential, birthday, or default
          values like 1234 or 0000.
        </p>

        <div className="mt-6 space-y-1">
          {rows.map((row, index) => {
            const isLast = index === rows.length - 1;
            const status: RowStatus = statuses[row.id] ?? 'idle';
            const rowError = errors[row.id];
            const nameId = `${fieldIdPrefix}-name-${row.id}`;
            const emailId = `${fieldIdPrefix}-email-${row.id}`;
            const roleId = `${fieldIdPrefix}-role-${row.id}`;
            const pinId = `${fieldIdPrefix}-pin-${row.id}`;
            const pinHelpId = `${fieldIdPrefix}-pin-help-${row.id}`;
            const pinErrorId = `${fieldIdPrefix}-pin-error-${row.id}`;
            const pinValue = row.pin?.trim() ?? '';
            const livePinError =
              !rowError?.pin && pinValue
                ? !/^\d{4}$/.test(pinValue)
                  ? 'Enter exactly 4 digits, or leave PIN blank.'
                  : isWeakEmployeePin(pinValue)
                    ? 'Choose a less obvious PIN; avoid repeats, sequences, and default values.'
                    : undefined
                : undefined;
            const pinError = rowError?.pin ?? livePinError;
            const RoleIcon =
              ROLE_OPTIONS.find((opt) => opt.value === row.role)?.Icon ?? Wrench;
            const message = messages[row.id];

            return (
              <div
                key={row.id}
                className={
                  'flex flex-wrap items-end gap-3 py-3' +
                  (isLast
                    ? ''
                    : ' border-b border-surface-100 dark:border-surface-800')
                }
              >
                {/* Name */}
                <div className="min-w-[180px] flex-1">
                  <label
                    htmlFor={nameId}
                    className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400"
                  >
                    Name
                  </label>
                  <input
                    id={nameId}
                    type="text"
                    value={row.name}
                    onChange={(e) => updateRow(row.id, { name: e.target.value })}
                    placeholder="Sarah Kim"
                    aria-invalid={Boolean(rowError?.name)}
                    className={
                      'w-full rounded-lg border bg-surface-50 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ' +
                      (rowError?.name
                        ? 'border-red-400 dark:border-red-500'
                        : 'border-surface-300 dark:border-surface-600')
                    }
                  />
                  {rowError?.name ? (
                    <p className="mt-1 text-xs text-red-600 dark:text-red-400">
                      {rowError.name}
                    </p>
                  ) : null}
                </div>

                {/* Email */}
                <div className="min-w-[200px] flex-1">
                  <label
                    htmlFor={emailId}
                    className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400"
                  >
                    Email
                  </label>
                  <input
                    id={emailId}
                    type="email"
                    value={row.email}
                    onChange={(e) => updateRow(row.id, { email: e.target.value })}
                    placeholder="sarah@shop.com"
                    aria-invalid={Boolean(rowError?.email)}
                    className={
                      'w-full rounded-lg border bg-surface-50 px-3 py-2 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ' +
                      (rowError?.email
                        ? 'border-red-400 dark:border-red-500'
                        : 'border-surface-300 dark:border-surface-600')
                    }
                  />
                  {rowError?.email ? (
                    <p className="mt-1 text-xs text-red-600 dark:text-red-400">
                      {rowError.email}
                    </p>
                  ) : null}
                </div>

                {/* Role */}
                <div className="min-w-[160px]">
                  <label
                    htmlFor={roleId}
                    className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400"
                  >
                    Role
                  </label>
                  <div className="relative">
                    <span className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-surface-500 dark:text-surface-400">
                      <RoleIcon className="h-4 w-4" />
                    </span>
                    <select
                      id={roleId}
                      value={row.role}
                      onChange={(e) =>
                        updateRow(row.id, {
                          role: e.target.value as EmployeeRole,
                        })
                      }
                      className="w-full appearance-none rounded-lg border border-surface-300 bg-surface-50 py-2 pl-8 pr-7 text-sm text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                    >
                      {ROLE_OPTIONS.map((opt) => (
                        <option key={opt.value} value={opt.value}>
                          {opt.label}
                        </option>
                      ))}
                    </select>
                  </div>
                </div>

                {/* PIN — clock-in/register access. 4-digit numeric, optional. */}
                <div className="w-40">
                  <label
                    htmlFor={pinId}
                    className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400"
                  >
                    PIN <span className="text-surface-400">(opt.)</span>
                  </label>
                  <input
                    id={pinId}
                    type="text"
                    inputMode="numeric"
                    pattern="\d{4}"
                    maxLength={4}
                    placeholder="4827"
                    value={row.pin ?? ''}
                    aria-invalid={Boolean(pinError)}
                    aria-describedby={`${pinHelpId}${pinError ? ` ${pinErrorId}` : ''}`}
                    onChange={(e) =>
                      updateRow(row.id, {
                        pin: e.target.value.replace(/\D/g, '').slice(0, 4),
                      })
                    }
                    className={
                      'w-full rounded-lg border bg-surface-50 px-2 py-2 text-center font-mono text-sm tracking-widest text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:bg-surface-700 dark:text-surface-100 ' +
                      (pinError
                        ? 'border-red-400 dark:border-red-500'
                        : 'border-surface-300 dark:border-surface-600')
                    }
                  />
                  <p
                    id={pinHelpId}
                    className="mt-1 text-xs leading-snug text-surface-500 dark:text-surface-400"
                  >
                    Unique 4 digits.
                  </p>
                  {pinError ? (
                    <p
                      id={pinErrorId}
                      className="mt-1 text-xs text-red-600 dark:text-red-400"
                    >
                      {pinError}
                    </p>
                  ) : null}
                </div>

                {/* Status badge */}
                <div className="flex min-h-[38px] items-center pb-1 text-xs">
                  {status === 'sending' ? (
                    <span className="inline-flex items-center gap-1.5 text-surface-600 dark:text-surface-300">
                      <Loader2 className="h-3.5 w-3.5 animate-spin" />
                      Sending…
                    </span>
                  ) : status === 'sent' ? (
                    <span className="inline-flex items-center gap-1.5 font-medium text-green-700 dark:text-green-400">
                      <CheckCircle2 className="h-4 w-4" />
                      Invite sent
                    </span>
                  ) : status === 'created' ? (
                    <span className="inline-flex items-center gap-1.5 font-medium text-amber-700 dark:text-amber-300">
                      <CheckCircle2 className="h-4 w-4" />
                      Account created
                    </span>
                  ) : status === 'failed' ? (
                    <span className="inline-flex items-center gap-1.5 text-red-600 dark:text-red-400">
                      <XCircle className="h-4 w-4" />
                      Failed —{' '}
                      <button
                        type="button"
                        onClick={() => handleRetry(row.id)}
                        disabled={statuses[row.id] === 'sending' || retryDisabled[row.id]}
                        className="btn btn-xs font-medium underline hover:no-underline disabled:cursor-not-allowed disabled:opacity-50"
                      >
                        retry
                      </button>
                    </span>
                  ) : null}
                </div>

                {message ? (
                  <p className="basis-full text-xs text-surface-500 dark:text-surface-400">
                    {message}
                  </p>
                ) : null}

                {/* Remove */}
                {rows.length > 1 ? (
                  <button
                    type="button"
                    onClick={() => removeRow(row.id)}
                    aria-label={`Remove employee row ${index + 1}`}
                    className="btn-icon btn-sm mb-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-500/10 dark:hover:text-red-400"
                  >
                    <Trash2 className="h-4 w-4" />
                  </button>
                ) : null}
              </div>
            );
          })}
        </div>

        <button
          type="button"
          onClick={addRow}
          className="btn btn-sm mt-3 inline-flex items-center gap-1.5 text-sm font-medium text-primary-700 hover:underline dark:text-primary-400"
        >
          <Plus className="h-4 w-4" />
          Add another employee
        </button>

        {/* Footer */}
        <div className="mt-8 flex items-center justify-between gap-3">
          <button
            type="button"
            onClick={onBack}
            disabled={submitting}
            className="btn btn-lg rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              disabled={submitting}
              className="btn btn-lg rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip this step
            </button>
            <button
              type="button"
              onClick={handleSendInvites}
              disabled={submitting || !canSendInvites}
              className="btn btn-lg inline-flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
            >
              {submitting ? (
                <>
                  <Loader2 className="h-4 w-4 animate-spin" />
                  Sending…
                </>
              ) : (
                'Send invites'
              )}
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}

export default StepFirstEmployees;
