/**
 * StepFirstEmployees — Setup wizard Step 15.
 *
 * Lets the owner invite 1-3 staff members up front so they're not alone in the
 * tickets list on day one. The step renders an editable list of rows (name +
 * email + role) plus a "+ Add another employee" button. On "Send invites" each
 * non-empty, valid row is POSTed individually to `/api/v1/users` with
 * `send_invite: true`; per-row status badges (sending / sent / failed) reflect
 * the call outcome. After all rows finish (success or failure), the wizard
 * advances via `onNext()`. "Skip" calls `onSkip ?? onNext` without sending.
 *
 * The endpoint isn't wrapped in `@/api/endpoints` yet, so we use plain `fetch`
 * with `credentials: 'include'` so the auth cookie tags along.
 *
 * Mockup: `docs/setup-wizard-preview.html` `<section id="screen-15">`.
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
import { validateEmail } from '@/services/validationService';

type EmployeeRole = 'admin' | 'tech' | 'cashier';
type RowStatus = 'idle' | 'sending' | 'sent' | 'failed';

interface EmployeeInvite {
  id: string;
  name: string;
  email: string;
  role: EmployeeRole;
  /** Self-host PIN for clock-in/out + register access. Optional 4-digit string.
   *  Mockup explicitly includes this field per docs/setup-wizard-preview.html
   *  #screen-15. SaaS shops can ignore — backend drops the value if PIN-auth
   *  isn't enabled for the tenant. */
  pin?: string;
}

interface RowError {
  name?: string;
  email?: string;
  pin?: string;
}

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
  return Object.keys(errors).length > 0 ? errors : null;
}

/** Split a full-name string into first / last on the first space. */
function splitName(full: string): { first_name: string; last_name: string } {
  const trimmed = full.trim();
  const idx = trimmed.indexOf(' ');
  if (idx === -1) return { first_name: trimmed, last_name: '' };
  return {
    first_name: trimmed.slice(0, idx),
    last_name: trimmed.slice(idx + 1).trim(),
  };
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
  const [errors, setErrors] = useState<Record<string, RowError>>({});
  const [submitting, setSubmitting] = useState(false);

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
  };

  const sendOne = async (row: EmployeeInvite): Promise<boolean> => {
    setStatuses((prev) => ({ ...prev, [row.id]: 'sending' }));
    try {
      const { first_name, last_name } = splitName(row.name);
      const res = await fetch('/api/v1/users', {
        method: 'POST',
        credentials: 'include',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          first_name,
          last_name,
          email: row.email.trim(),
          role: row.role,
          send_invite: true,
          // PIN is optional. 4-digit numeric used by self-host shops for
          // clock-in/out + register access. Server is expected to ignore the
          // field for SaaS tenants where PIN-auth isn't enabled. Empty string
          // is sent as undefined so backend doesn't try to hash an empty PIN.
          pin: row.pin && row.pin.length === 4 ? row.pin : undefined,
        }),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      setStatuses((prev) => ({ ...prev, [row.id]: 'sent' }));
      return true;
    } catch {
      setStatuses((prev) => ({ ...prev, [row.id]: 'failed' }));
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
    if (toSend.length === 0) {
      // Nothing to invite — behave like Skip.
      (onSkip ?? onNext)();
      return;
    }

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
    const row = rows.find((r) => r.id === id);
    if (!row) return;
    void sendOne(row);
  };

  const handleSkip = () => {
    (onSkip ?? onNext)();
  };

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

        <div className="mt-6 space-y-1">
          {rows.map((row, index) => {
            const isLast = index === rows.length - 1;
            const status: RowStatus = statuses[row.id] ?? 'idle';
            const rowError = errors[row.id];
            const nameId = `${fieldIdPrefix}-name-${row.id}`;
            const emailId = `${fieldIdPrefix}-email-${row.id}`;
            const roleId = `${fieldIdPrefix}-role-${row.id}`;
            const RoleIcon =
              ROLE_OPTIONS.find((opt) => opt.value === row.role)?.Icon ?? Wrench;

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
                <div className="w-24">
                  <label
                    htmlFor={`${row.id}-pin`}
                    className="mb-1 block text-xs font-medium text-surface-600 dark:text-surface-400"
                  >
                    PIN <span className="text-surface-400">(opt.)</span>
                  </label>
                  <input
                    id={`${row.id}-pin`}
                    type="text"
                    inputMode="numeric"
                    pattern="\d{4}"
                    maxLength={4}
                    placeholder="0000"
                    value={row.pin ?? ''}
                    onChange={(e) =>
                      updateRow(row.id, {
                        pin: e.target.value.replace(/\D/g, '').slice(0, 4),
                      })
                    }
                    className="w-full rounded-lg border border-surface-300 bg-surface-50 px-2 py-2 text-center font-mono text-sm tracking-widest text-surface-900 focus-visible:border-primary-500 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500/20 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                  />
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
                  ) : status === 'failed' ? (
                    <span className="inline-flex items-center gap-1.5 text-red-600 dark:text-red-400">
                      <XCircle className="h-4 w-4" />
                      Failed —{' '}
                      <button
                        type="button"
                        onClick={() => handleRetry(row.id)}
                        className="font-medium underline hover:no-underline"
                      >
                        retry
                      </button>
                    </span>
                  ) : null}
                </div>

                {/* Remove */}
                {rows.length > 1 ? (
                  <button
                    type="button"
                    onClick={() => removeRow(row.id)}
                    aria-label={`Remove employee row ${index + 1}`}
                    className="mb-1 flex h-9 w-9 shrink-0 items-center justify-center rounded-lg text-surface-400 hover:bg-red-50 hover:text-red-600 dark:hover:bg-red-500/10 dark:hover:text-red-400"
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
          className="mt-3 inline-flex items-center gap-1.5 text-sm font-medium text-primary-700 hover:underline dark:text-primary-400"
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
            className="rounded-lg border border-surface-200 bg-white px-5 py-3 text-sm font-semibold text-surface-700 transition-colors hover:bg-surface-50 disabled:cursor-not-allowed disabled:opacity-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-200 dark:hover:bg-surface-700"
          >
            Back
          </button>
          <div className="flex items-center gap-2">
            <button
              type="button"
              onClick={handleSkip}
              disabled={submitting}
              className="rounded-lg px-4 py-3 text-sm font-medium text-surface-500 hover:bg-surface-100 disabled:cursor-not-allowed disabled:opacity-50 dark:text-surface-400 dark:hover:bg-surface-700"
            >
              Skip — solo operator
            </button>
            <button
              type="button"
              onClick={handleSendInvites}
              disabled={submitting}
              className="inline-flex items-center gap-2 rounded-lg bg-primary-500 px-6 py-3 text-sm font-semibold text-primary-950 shadow-sm transition-colors hover:bg-primary-400 disabled:cursor-not-allowed disabled:opacity-60"
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
