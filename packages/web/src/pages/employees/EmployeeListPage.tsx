import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  UserCog, Clock, DollarSign, ChevronDown, ChevronRight, X, Hash, Pencil, Check, Search, Eye, EyeOff,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import { employeeApi, locationApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';
import { formatCurrency, formatTime } from '@/utils/format';
import { useAuthStore } from '@/stores/authStore';
import { useHasRole } from '@/hooks/useHasRole';

// ─── Types ──────────────────────────────────────────────────────────
interface Employee {
  id: number;
  username: string;
  email: string;
  first_name: string;
  last_name: string;
  role: string;
  avatar_url?: string;
  is_active: number;
  has_pin: number;
  permissions?: string;
  created_at: string;
  updated_at: string;
  // WEB-S6-033: list endpoint now includes these fields so no per-row fetch needed
  is_clocked_in?: number | boolean;
  active_clock_in_at?: string | null;
  weekly_hours?: number;
}

interface EmployeeDetail extends Employee {
  clock_entries?: ClockEntry[];
  commissions?: Commission[];
  is_clocked_in?: boolean;
  current_clock_entry?: ClockEntry | null;
  pay_rate?: number | null;
}

interface ClockEntry {
  id: number;
  user_id: number;
  clock_in: string;
  clock_out: string | null;
  total_hours: number | null;
  notes?: string;
}

interface Commission {
  id: number;
  user_id: number;
  amount: number;
  ticket_id?: number;
  invoice_id?: number;
  ticket_order_id?: string;
  invoice_order_id?: string;
  description?: string;
  created_at: string;
}

// ─── Helpers ────────────────────────────────────────────────────────
// @audit-fixed (WEB-FM-008 / Fixer-B22 2026-04-25): dropped the hardcoded
// `'en-US'` locale on these three helpers. The shared `utils/format.ts`
// helpers all derive the active locale from `initCurrencyFromSettings`
// (defaults to navigator.language) so `formatShortDateTime` already
// formats clock-in entries in the visitor's locale. Recent-commission
// rows still need a *short* date (month+day, no year) which the shared
// helper doesn't expose, so we keep tiny local helpers but read the
// browser locale at format-time instead of pinning to en-US.
const _employeeLocale = typeof navigator !== 'undefined' ? navigator.language || 'en-US' : 'en-US';

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString(_employeeLocale, {
    month: 'short', day: 'numeric',
  });
}

function formatDateTime(iso: string) {
  return `${formatDate(iso)} ${formatTime(iso)}`;
}

function formatHours(hours: number) {
  const h = Math.floor(hours);
  const m = Math.round((hours - h) * 60);
  return m > 0 ? `${h}h ${m}m` : `${h}h`;
}

function getMonthRange() {
  const now = new Date();
  const firstOfMonth = new Date(now.getFullYear(), now.getMonth(), 1);
  return {
    from_date: firstOfMonth.toISOString(),
    to_date: new Date().toISOString(),
  };
}

const ROLE_COLORS: Record<string, string> = {
  admin: 'bg-purple-100 text-purple-700 dark:bg-purple-900/30 dark:text-purple-400',
  technician: 'bg-blue-100 text-blue-700 dark:bg-blue-900/30 dark:text-blue-400',
  manager: 'bg-amber-100 text-amber-700 dark:bg-amber-900/30 dark:text-amber-400',
  cashier: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400',
};

// ─── PIN Entry Modal ────────────────────────────────────────────────
// WEB-UIUX-1262: parse server rate-limit error to extract lockedUntil + attemptsRemaining
function parseRateLimitError(err: unknown): { lockedUntil?: Date; attemptsRemaining?: number; message?: string } {
  try {
    const resp = (err as any)?.response?.data;
    const lockedUntilStr = resp?.lockedUntil ?? resp?.locked_until;
    const attemptsRemaining = resp?.attemptsRemaining ?? resp?.attempts_remaining;
    const message: string | undefined = resp?.message ?? resp?.error;
    const lockedUntil = lockedUntilStr ? new Date(lockedUntilStr) : undefined;
    // Also try "Try again in N min" pattern from message string
    if (!lockedUntil && message) {
      const match = message.match(/try again in (\d+)\s*min/i);
      if (match) {
        const mins = parseInt(match[1], 10);
        return { lockedUntil: new Date(Date.now() + mins * 60 * 1000), attemptsRemaining, message };
      }
    }
    return { lockedUntil, attemptsRemaining, message };
  } catch {
    return {};
  }
}

function PinModal({ employee, action, onClose, onSubmit, isPending, lockedUntilProp, attemptsRemainingProp }: {
  employee: Employee;
  action: 'clock-in' | 'clock-out';
  onClose: () => void;
  // WEB-UIUX-1252: locationId is the operator's selected punch location;
  // null when there is one active location (server falls back to user's
  // home_location_id / global default).
  // WEB-UIUX-1261: notes is the optional clock-out memo (clock-in ignores it).
  onSubmit: (pin: string, locationId: number | null, notes: string | null) => void;
  isPending: boolean;
  // WEB-UIUX-1262: parent passes lockout info parsed from server rate-limit error
  lockedUntilProp?: Date | null;
  attemptsRemainingProp?: number | null;
}) {
  const [pin, setPin] = useState('');
  // WEB-UIUX-1257: need current user role to show the right no-PIN guidance
  const { user: currentUser } = useAuthStore();
  // WEB-UIUX-1252: pull active locations so multi-location stores can pick
  // the punch site. Single-location tenants skip the picker entirely. Cache
  // for 5 min — locations rarely change inside a shift.
  const { data: locationsData } = useQuery({
    queryKey: ['locations', 'active'],
    queryFn: () => locationApi.list(true).then((r) => r.data.data ?? []),
    staleTime: 5 * 60_000,
    enabled: !!employee.has_pin,
  });
  const locations = locationsData ?? [];
  const showLocationPicker = locations.length > 1;
  const defaultLocationId = (
    locations.find((l) => l.is_default)?.id
    ?? locations[0]?.id
    ?? null
  );
  const [locationId, setLocationId] = useState<number | null>(defaultLocationId);
  useEffect(() => {
    // Re-default once locations resolve.
    if (locationId == null && defaultLocationId != null) setLocationId(defaultLocationId);
  }, [defaultLocationId, locationId]);
  // WEB-UIUX-1261: optional clock-out memo. Hidden on clock-in to keep the
  // common-case PIN entry uncluttered; server-side, clock-in route doesn't
  // accept this field anyway.
  const [notes, setNotes] = useState('');
  // WEB-UIUX-902: canonical role gate via useHasRole.
  const isAdmin = useHasRole('admin');
  // WEB-UIUX-1262: rate-limit lockout countdown state (seeded from parent prop)
  const [lockedUntil, setLockedUntil] = useState<Date | null>(lockedUntilProp ?? null);
  const [attemptsRemaining, setAttemptsRemaining] = useState<number | null>(attemptsRemainingProp ?? null);
  const [countdown, setCountdown] = useState('');

  // Sync prop changes (new error from parent) into local state
  useEffect(() => { if (lockedUntilProp) setLockedUntil(lockedUntilProp); }, [lockedUntilProp]);
  useEffect(() => { if (attemptsRemainingProp != null) setAttemptsRemaining(attemptsRemainingProp); }, [attemptsRemainingProp]);

  // WEB-UIUX-1262: live mm:ss countdown timer when locked out
  useEffect(() => {
    if (!lockedUntil) { setCountdown(''); return; }
    const tick = () => {
      const diff = lockedUntil.getTime() - Date.now();
      if (diff <= 0) { setLockedUntil(null); setCountdown(''); return; }
      const totalSec = Math.ceil(diff / 1000);
      const mm = String(Math.floor(totalSec / 60)).padStart(2, '0');
      const ss = String(totalSec % 60).padStart(2, '0');
      setCountdown(`${mm}:${ss}`);
    };
    tick();
    const id = setInterval(tick, 500);
    return () => clearInterval(id);
  }, [lockedUntil]);

  // WEB-UIUX-1266: show/hide PIN toggle
  const [showPin, setShowPin] = useState(false);

  // WEB-FG-012 fix: kiosk-cashiers were losing in-progress PINs when their hand
  // grazed the dim outside the inner card — backdrop-click closed the modal
  // mid-typing. Close on Escape only; the explicit Cancel/Close button and the
  // header X icon already cover the dismiss path. Also adds a11y-correct
  // role + aria-modal + aria-labelledby (modal previously had no semantic
  // dialog role, screen readers announced it as plain-text content).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    document.addEventListener('keydown', onKey);
    return () => document.removeEventListener('keydown', onKey);
  }, [onClose]);

  return (
    <div
      role="dialog"
      aria-modal="true"
      aria-labelledby="pin-modal-title"
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
    >
      <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-800">
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          {/* WEB-UIUX-1257: show "PIN Required" title when employee has no PIN to avoid dead-end confusion */}
          <h3 id="pin-modal-title" className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            {!employee.has_pin
              ? 'PIN Required'
              : `${action === 'clock-in' ? 'Clock In' : 'Clock Out'} — ${[employee.first_name, employee.last_name].filter(Boolean).join(' ')}`}
          </h3>
          <button type="button" aria-label="Close" onClick={onClose} className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5 text-surface-500" />
          </button>
        </div>
        <div className="p-6">
          {/* WEB-FG-004 fix: when the employee has no PIN configured, the
              modal previously accepted ANY value — meaning a walk-up bystander
              on an unattended kiosk could clock in/out a pin-less employee
              and falsify timesheets/commissions. We now hard-block the form:
              the input is disabled, Submit is disabled, and the operator is
              told to set a PIN in Edit Employee first. The server is the
              source of truth; this client gate just removes the trivial
              walk-up attack. */}
          {/* WEB-UIUX-1257: role-aware no-PIN guidance so the user is never left in a dead-end loop.
              Admins get a direct link to the user settings page; non-admins are told to ask. */}
          {!employee.has_pin ? (
            <div className="rounded-lg border border-amber-300 bg-amber-50 p-4 text-sm text-amber-800 dark:border-amber-700 dark:bg-amber-900/30 dark:text-amber-200">
              <p className="font-semibold">PIN required to clock in/out.</p>
              {isAdmin ? (
                <p className="mt-1">
                  {employee.first_name} {employee.last_name} has no PIN set.{' '}
                  <Link
                    to={`/settings/users?employee=${employee.id}`}
                    className="font-semibold underline hover:no-underline"
                    onClick={onClose}
                  >
                    Set PIN now →
                  </Link>
                </p>
              ) : (
                <p className="mt-1">Ask an admin to set your PIN before recording time.</p>
              )}
            </div>
          ) : (
            <>
              <label htmlFor="pin-modal-input" className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">
                Enter PIN
              </label>
              <div className="relative">
                <Hash className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                {/* WEB-UIUX-1266: type toggles between password and text via Eye/EyeOff icon */}
                {/* WEB-UIUX-1271: aria-describedby points at the visible hint
                    below so SR users hear the 4-6 digit length constraint. */}
                <input
                  id="pin-modal-input"
                  type={showPin ? 'text' : 'password'}
                  inputMode="numeric"
                  maxLength={6}
                  value={pin}
                  onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
                  onKeyDown={(e) => {
                    // WEB-UIUX-1253: PIN is 4–6 digits; do NOT auto-submit at length 4 because
                    // the employee may still be typing a 5- or 6-digit PIN. Submit only on
                    // Enter when PIN is at max length (6); the explicit Submit button covers all lengths.
                    if (e.key === 'Enter' && pin.length === 6) {
                      onSubmit(pin, locationId, action === 'clock-out' ? (notes.trim() || null) : null);
                    }
                  }}
                  placeholder="4-6 digit PIN"
                  autoFocus
                  disabled={!!lockedUntil}
                  aria-describedby="pin-modal-hint"
                  className="w-full rounded-lg border border-surface-300 py-3 pl-9 pr-10 text-center text-2xl tracking-[0.5em] dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100 disabled:opacity-50"
                />
                {/* WEB-UIUX-1266: show/hide toggle button */}
                <button
                  type="button"
                  aria-label={showPin ? 'Hide PIN' : 'Show PIN'}
                  onClick={() => setShowPin((v) => !v)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
                >
                  {showPin ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
                </button>
              </div>
              {/* WEB-UIUX-1271: visible-on-screen hint paired with aria-describedby
                  so the length constraint is announced to SR users. */}
              <p id="pin-modal-hint" className="mt-1 text-xs text-surface-500 dark:text-surface-400">
                4–6 digit PIN (digits only)
              </p>
              {/* WEB-UIUX-1261: optional clock-out memo. Hidden on clock-in
                  to keep the common-case PIN entry uncluttered; the server
                  clock-in route ignores `notes` anyway. */}
              {action === 'clock-out' && (
                <div className="mt-3">
                  <label
                    htmlFor="pin-modal-notes"
                    className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300"
                  >
                    Shift note (optional)
                  </label>
                  <textarea
                    id="pin-modal-notes"
                    value={notes}
                    onChange={(e) => setNotes(e.target.value.slice(0, 1000))}
                    disabled={!!lockedUntil}
                    rows={2}
                    maxLength={1000}
                    placeholder="e.g. covered for sick teammate, client meeting ran late"
                    className="w-full resize-none rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm focus-visible:border-primary-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-600 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                  />
                  <p className="mt-0.5 text-right text-[10px] text-surface-400">
                    {notes.length}/1000
                  </p>
                </div>
              )}
              {/* WEB-UIUX-1252: multi-location punch picker. Single-location
                  stores never see this row; server falls back to the user's
                  home_location_id when locationId is null. */}
              {showLocationPicker && (
                <div className="mt-3">
                  <label
                    htmlFor="pin-modal-location"
                    className="mb-1 block text-xs font-medium text-surface-700 dark:text-surface-300"
                  >
                    Punch location
                  </label>
                  <select
                    id="pin-modal-location"
                    value={locationId ?? ''}
                    onChange={(e) => {
                      const next = e.target.value;
                      setLocationId(next ? Number(next) : null);
                    }}
                    disabled={!!lockedUntil}
                    className="w-full rounded-lg border border-surface-300 bg-white px-3 py-2 text-sm focus-visible:border-primary-600 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-600 dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                  >
                    {locations.map((l) => (
                      <option key={l.id} value={l.id}>
                        {l.name}
                        {l.is_default ? ' (default)' : ''}
                      </option>
                    ))}
                  </select>
                </div>
              )}
              {/* WEB-UIUX-1262: rate-limit lockout feedback — live countdown + attempts remaining */}
              {lockedUntil && countdown && (
                <div className="mt-2 rounded-lg border border-red-300 bg-red-50 px-3 py-2 text-sm text-red-700 dark:border-red-700 dark:bg-red-900/30 dark:text-red-300">
                  Too many incorrect attempts. Try again in{' '}
                  <span className="font-mono font-semibold">{countdown}</span>.
                  {attemptsRemaining !== null && (
                    <span className="ml-1 text-xs opacity-75">(attempts remaining: {attemptsRemaining}/5)</span>
                  )}
                </div>
              )}
              {!lockedUntil && attemptsRemaining !== null && (
                <p className="mt-1 text-xs text-surface-500 dark:text-surface-400">
                  Attempts remaining: {attemptsRemaining}/5
                </p>
              )}
            </>
          )}
        </div>
        {/* WEB-UIUX-1274: header X already closes. Footer secondary slot:
            when no PIN + admin → "Set PIN" link; otherwise no Cancel button. */}
        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          {!employee.has_pin && isAdmin ? (
            <Link
              to={`/settings/users?employee=${employee.id}`}
              onClick={onClose}
              className="rounded-lg px-4 py-2 text-sm font-medium text-primary-600 hover:bg-surface-100 dark:text-primary-400 dark:hover:bg-surface-700"
            >
              Set PIN
            </Link>
          ) : null}
          <button type="button"
            onClick={() => onSubmit(pin, locationId, action === 'clock-out' ? (notes.trim() || null) : null)}
            disabled={!employee.has_pin || pin.length < 4 || isPending || !!lockedUntil}
            className={cn(
              'rounded-lg px-4 py-2 text-sm font-medium text-white disabled:opacity-50 disabled:cursor-not-allowed disabled:pointer-events-none',
              action === 'clock-in'
                ? 'bg-green-600 hover:bg-green-700'
                : 'bg-red-600 hover:bg-red-700',
            )}
            title={!employee.has_pin ? 'Set a PIN before clocking in/out' : undefined}
          >
            {isPending ? (
              <span className="flex items-center gap-2">
                <div className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                Processing...
              </span>
            ) : (
              action === 'clock-in' ? 'Clock In' : 'Clock Out'
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Pay Rate inline editor (WEB-S6-014) ─────────────────────────
function PayRateEditor({ employeeId, currentRate }: { employeeId: number; currentRate: number | null }) {
  const queryClient = useQueryClient();
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState('');

  const mutation = useMutation({
    mutationFn: (rate: number | null) => employeeApi.updatePayRate(employeeId, rate),
    onSuccess: () => {
      toast.success('Pay rate updated');
      setEditing(false);
      queryClient.invalidateQueries({ queryKey: ['employee-detail', employeeId] });
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
    },
  });

  function startEdit() {
    setDraft(currentRate != null ? String(currentRate) : '');
    setEditing(true);
  }

  function commit() {
    const trimmed = draft.trim();
    const rate = trimmed === '' ? null : parseFloat(trimmed);
    if (trimmed !== '' && (isNaN(rate!) || rate! < 0 || rate! > 9999.99)) {
      toast.error('Pay rate must be a number between 0 and 9999.99');
      return;
    }
    // WEB-UIUX-1265: $0 or sub-$1 pay rates are almost certainly typos.
    // Confirm before banking a value that silently zeros out future
    // commissions/hours math for this employee.
    if (rate !== null && rate < 1) {
      const label = rate === 0 ? '$0.00/hr (no pay)' : `$${rate.toFixed(2)}/hr`;
      // eslint-disable-next-line no-alert
      const ok = window.confirm(`Set pay rate to ${label}? This will be used for all future timesheet + commission math.`);
      if (!ok) return;
    }
    mutation.mutate(rate);
  }

  if (editing) {
    return (
      <div className="flex items-center gap-2">
        <span className="text-sm text-surface-500">$/hr</span>
        <input
          type="number"
          min="0"
          max="9999.99"
          step="0.01"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') commit();
            if (e.key === 'Escape') setEditing(false);
          }}
          autoFocus
          placeholder="e.g. 18.50"
          className="w-24 rounded-lg border border-surface-300 px-2 py-1 text-sm dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
        />
        <button
          type="button"
          onClick={commit}
          disabled={mutation.isPending}
          aria-label="Save pay rate"
          className="rounded-lg p-1 text-green-600 hover:bg-green-50 dark:text-green-400 dark:hover:bg-green-950/30"
        >
          <Check className="h-4 w-4" />
        </button>
        <button
          type="button"
          onClick={() => setEditing(false)}
          aria-label="Cancel"
          className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-700"
        >
          <X className="h-4 w-4" />
        </button>
      </div>
    );
  }

  return (
    <div className="flex items-center gap-2">
      <span className="text-sm font-medium text-surface-800 dark:text-surface-200">
        {currentRate != null ? `${formatCurrency(currentRate)}/hr` : <span className="italic text-surface-400">Not set</span>}
      </span>
      <button
        type="button"
        onClick={startEdit}
        aria-label="Edit pay rate"
        className="rounded-lg p-1 text-surface-400 hover:bg-surface-100 hover:text-surface-700 dark:hover:bg-surface-700 dark:hover:text-surface-200"
      >
        <Pencil className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

// ─── Expanded Row Detail ────────────────────────────────────────────
function EmployeeExpandedRow({
  employee,
  detail,
  isDetailLoading,
}: {
  employee: Employee;
  detail: EmployeeDetail | undefined;
  isDetailLoading: boolean;
}) {
  const monthRange = getMonthRange();

  const detailCommissions = detail?.commissions ?? [];
  const recentClock = detail?.clock_entries?.slice(0, 5) ?? [];
  const recentCommissions = detailCommissions.slice(0, 5);
  const weeklyHours = Number(employee.weekly_hours ?? 0);
  const monthStart = new Date(monthRange.from_date).getTime();
  const recentMonthCommissionTotal = detailCommissions
    .filter((commission) => new Date(commission.created_at).getTime() >= monthStart)
    .reduce((total, commission) => total + Number(commission.amount ?? 0), 0);

  return (
    <tr>
      <td colSpan={6} className="bg-surface-50/50 px-4 py-4 dark:bg-surface-800/50">
        {/* WEB-S6-014: Pay Rate row */}
        <div className="mb-4 flex items-center gap-4 rounded-lg border border-surface-200 bg-white px-4 py-3 shadow-sm dark:border-surface-700 dark:bg-surface-700">
          <DollarSign className="h-4 w-4 shrink-0 text-surface-400" />
          <span className="text-sm font-medium text-surface-700 dark:text-surface-300">Hourly Pay Rate</span>
          <div className="ml-auto">
            <PayRateEditor
              employeeId={employee.id}
              currentRate={detail?.pay_rate ?? null}
            />
          </div>
        </div>

        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          {/* Recent Clock Entries */}
          <div>
            <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold text-surface-700 dark:text-surface-300">
              <Clock className="h-4 w-4" />
              Recent Clock Entries
              <span className="ml-auto text-xs font-normal text-surface-500">
                This week: {formatHours(weeklyHours)}
              </span>
            </h4>
            {isDetailLoading && !detail ? (
              <p className="text-sm text-surface-400">Loading clock entries...</p>
            ) : recentClock.length === 0 ? (
              // WEB-UIUX-1269: spatial reference depends on viewport; just
              // point to the action label.
              <p className="text-sm text-surface-400">No clock entries yet. Use the Clock In button on this row to log a shift.</p>
            ) : (
              <div className="space-y-1">
                {recentClock.map((entry) => (
                  <div
                    key={entry.id}
                    className="flex items-center justify-between rounded-lg bg-white px-3 py-2 text-sm shadow-sm dark:bg-surface-700"
                  >
                    <span className="text-surface-600 dark:text-surface-300">
                      {formatDateTime(entry.clock_in)}
                    </span>
                    <span className="text-surface-500">
                      {entry.clock_out ? (
                        <>to {formatTime(entry.clock_out)} ({formatHours(entry.total_hours ?? 0)})</>
                      ) : (
                        <span className="text-green-600 dark:text-green-400">Active</span>
                      )}
                    </span>
                  </div>
                ))}
                {/* WEB-UIUX-1268: view-all link below the capped list */}
                <div className="pt-1 text-right">
                  <Link
                    to="/team/payroll"
                    className="text-xs text-primary-600 hover:underline dark:text-primary-400"
                  >
                    View all →
                  </Link>
                </div>
              </div>
            )}
          </div>

          {/* Recent Commissions */}
          <div>
            <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold text-surface-700 dark:text-surface-300">
              <DollarSign className="h-4 w-4" />
              Recent Commissions
              {recentMonthCommissionTotal > 0 && (
                <span className="ml-auto text-xs font-normal text-surface-500">
                  Recent this month: {formatCurrency(recentMonthCommissionTotal)}
                </span>
              )}
            </h4>
            {isDetailLoading && !detail ? (
              <p className="text-sm text-surface-400">Loading commissions...</p>
            ) : recentCommissions.length === 0 ? (
              <p className="text-sm text-surface-400">No commissions recorded yet. Commissions are tracked per ticket or invoice.</p>
            ) : (
              <div className="space-y-1">
                {recentCommissions.map((c) => (
                  <div
                    key={c.id}
                    className="flex items-center justify-between rounded-lg bg-white px-3 py-2 text-sm shadow-sm dark:bg-surface-700"
                  >
                    <span className="text-surface-600 dark:text-surface-300">
                      {c.ticket_order_id && `T-${c.ticket_order_id}`}
                      {c.invoice_order_id && `INV-${c.invoice_order_id}`}
                      {!c.ticket_order_id && !c.invoice_order_id && (c.description || 'Commission')}
                    </span>
                    <div className="flex items-center gap-3">
                      <span className="text-xs text-surface-400">{formatDate(c.created_at)}</span>
                      <span className="font-medium text-green-600 dark:text-green-400">
                        {formatCurrency(c.amount)}
                      </span>
                    </div>
                  </div>
                ))}
                {/* WEB-UIUX-1268: view-all link below the capped commissions list */}
                <div className="pt-1 text-right">
                  <Link
                    to="/team/payroll"
                    className="text-xs text-primary-600 hover:underline dark:text-primary-400"
                  >
                    View all →
                  </Link>
                </div>
              </div>
            )}
          </div>
        </div>
      </td>
    </tr>
  );
}

// ─── Skeleton Row ───────────────────────────────────────────────────
function SkeletonRow() {
  return (
    <tr className="animate-pulse">
      <td className="px-4 py-3"><div className="h-4 w-4 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-32 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-5 w-20 rounded-full bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-16 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-4 w-12 rounded bg-surface-200 dark:bg-surface-700" /></td>
      <td className="px-4 py-3"><div className="h-8 w-24 rounded bg-surface-200 dark:bg-surface-700" /></td>
    </tr>
  );
}

// ─── Main Component ─────────────────────────────────────────────────
export function EmployeeListPage() {
  const queryClient = useQueryClient();
  const [expandedId, setExpandedId] = useState<number | null>(null);
  const [pinModal, setPinModal] = useState<{ employee: Employee; action: 'clock-in' | 'clock-out' } | null>(null);
  // WEB-UIUX-1259: client-side search filter (name + email substring)
  const [searchQuery, setSearchQuery] = useState('');
  const { user: currentUser } = useAuthStore();
  // WEB-UIUX-902: canonical role gate via useHasRole.
  const isAdmin = useHasRole('admin');
  // WEB-UIUX-1262: rate-limit lockout state parsed from server error response
  const [pinLockedUntil, setPinLockedUntil] = useState<Date | null>(null);
  const [pinAttemptsRemaining, setPinAttemptsRemaining] = useState<number | null>(null);

  // Fetch employee list
  // WEB-UIUX-1260: refetchInterval keeps kiosks in sync with clock-in/out from other devices within 30s
  const { data: listData, isLoading } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
    refetchInterval: 30_000,
  });
  const employees: Employee[] = (listData?.data as any)?.data ?? [];

  // WEB-UIUX-1259: filter employees client-side by name or email substring
  const filteredEmployees = searchQuery.trim()
    ? employees.filter((emp) => {
        const q = searchQuery.trim().toLowerCase();
        const fullName = `${emp.first_name} ${emp.last_name}`.toLowerCase();
        return fullName.includes(q) || emp.email.toLowerCase().includes(q);
      })
    : employees;

  // WEB-S6-033: is_clocked_in + weekly_hours are now included in the list
  // response — no per-row detail queries needed.

  // Clock in mutation
  const clockInMutation = useMutation({
    // WEB-UIUX-1252: thread the selected location_id through; server falls
    // back to home_location_id when undefined.
    mutationFn: ({ id, pin, locationId }: { id: number; pin: string; locationId: number | null }) =>
      employeeApi.clockIn(id, pin, locationId ?? undefined),
    onSuccess: (response) => {
      toast.success('Clocked in successfully');
      // WEB-UIUX-1255: server sends auto_closed_entry when a stale open shift was
      // silently closed before the new clock-in. Warn the employee so they know to
      // contact a manager to correct the previous shift's logged hours.
      const responseData = (response?.data as any)?.data ?? (response?.data as any);
      if (responseData?.auto_closed_entry) {
        toast('Previous shift auto-closed after 16h — contact a manager to correct logged hours.', {
          icon: '⚠️',
          style: { background: '#fffbeb', color: '#92400e', border: '1px solid #f59e0b' },
          duration: 8000,
        });
      }
      setPinModal(null);
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      queryClient.invalidateQueries({ queryKey: ['employee-detail'] });
    },
    onError: (err: unknown) => {
      // WEB-UIUX-1262: parse rate-limit lockout from server error
      const { lockedUntil, attemptsRemaining, message } = parseRateLimitError(err);
      if (lockedUntil) {
        setPinLockedUntil(lockedUntil);
        if (attemptsRemaining != null) setPinAttemptsRemaining(attemptsRemaining);
      } else {
        toast.error(message ?? formatApiError(err));
      }
    },
  });

  // Clock out mutation
  const clockOutMutation = useMutation({
    mutationFn: ({ id, pin, locationId, notes }: { id: number; pin: string; locationId: number | null; notes: string | null }) =>
      employeeApi.clockOut(id, pin, locationId ?? undefined, notes ?? undefined),
    onSuccess: (res: any) => {
      // WEB-UIUX-1256: surface total hours banked + (when available)
      // clock-in time so the worker has explicit confirmation of what
      // was logged. Server returns total_hours on the response payload
      // (employees.routes.ts:457,473).
      const data = res?.data?.data ?? res?.data ?? {};
      const totalHours = Number(data.total_hours ?? 0);
      const clockInAt = data.clock_in ?? data.clock_in_at ?? null;
      let msg = 'Clocked out successfully';
      if (totalHours > 0) {
        const h = Math.floor(totalHours);
        const m = Math.round((totalHours - h) * 60);
        msg = `Clocked out — ${h}h ${m}m logged${clockInAt ? ` since ${new Date(clockInAt).toLocaleTimeString()}` : ''}`;
      }
      toast.success(msg);
      setPinModal(null);
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      queryClient.invalidateQueries({ queryKey: ['employee-detail'] });
    },
    onError: (err: unknown) => {
      // WEB-UIUX-1262: parse rate-limit lockout from server error
      const { lockedUntil, attemptsRemaining, message } = parseRateLimitError(err);
      if (lockedUntil) {
        setPinLockedUntil(lockedUntil);
        if (attemptsRemaining != null) setPinAttemptsRemaining(attemptsRemaining);
      } else {
        toast.error(message ?? formatApiError(err));
      }
    },
  });

  const handlePinSubmit = (pin: string, locationId: number | null, notes: string | null) => {
    if (!pinModal) return;
    if (pinModal.action === 'clock-in') {
      clockInMutation.mutate({ id: pinModal.employee.id, pin, locationId });
    } else {
      clockOutMutation.mutate({ id: pinModal.employee.id, pin, locationId, notes });
    }
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Employees</h1>
          {/* WEB-UIUX-1263: subtitle covers every staff role, not just techs. */}
          <p className="text-surface-500 dark:text-surface-400">Employees, time clock, and payroll roster</p>
        </div>
        {/* WEB-UIUX-1258: label promises action; it's actually navigation to
            the user-management settings tab. Make the destination explicit. */}
        <a
          href="/settings/users"
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
          title="Open Settings → Users to create or invite a new employee"
          aria-label="Add a new employee — opens Settings > Users"
        >
          <UserCog className="h-4 w-4" />
          Add Employee (in Settings)
        </a>
      </div>

      {/* Helpful hint when only 1 employee */}
      {!isLoading && employees.length === 1 && (
        <div className="mb-4 rounded-lg border border-blue-200 bg-blue-50 px-4 py-3 text-sm text-blue-700 dark:border-blue-800 dark:bg-blue-950/30 dark:text-blue-300">
          You only have one employee. Add more team members in <a href="/settings/users" className="font-medium underline">Settings &rarr; Users</a> to track hours and commissions for your staff.
        </div>
      )}

      {/* WEB-UIUX-1259: search bar — filters by name and email, client-side */}
      <div className="mb-4">
        <div className="relative max-w-xs">
          <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400 pointer-events-none" />
          <input
            type="search"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="Search by name or email…"
            className="w-full rounded-lg border border-surface-300 py-2 pl-9 pr-4 text-sm dark:border-surface-600 dark:bg-surface-800 dark:text-surface-100 dark:placeholder-surface-500"
          />
        </div>
      </div>

      {/* Table */}
      <div className="card overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-sm">
            <thead>
              <tr className="border-b border-surface-200 bg-surface-50 dark:border-surface-700 dark:bg-surface-800">
                <th className="w-8 px-4 py-3" />
                <th className="px-4 py-3 font-medium text-surface-600 dark:text-surface-400">Name</th>
                <th className="px-4 py-3 font-medium text-surface-600 dark:text-surface-400">Role</th>
                <th className="px-4 py-3 font-medium text-surface-600 dark:text-surface-400">Status</th>
                <th className="px-4 py-3 font-medium text-surface-600 dark:text-surface-400">Hours This Week</th>
                <th className="px-4 py-3 font-medium text-surface-600 dark:text-surface-400">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-surface-100 dark:divide-surface-700">
              {isLoading ? (
                Array.from({ length: 4 }).map((_, i) => <SkeletonRow key={i} />)
              ) : employees.length === 0 ? (
                <tr>
                  <td colSpan={6} className="px-4 py-12 text-center">
                    <UserCog className="mx-auto mb-3 h-12 w-12 text-surface-300 dark:text-surface-600" />
                    <p className="text-sm font-medium text-surface-500 dark:text-surface-400">No employees found</p>
                    <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">Add employees to manage time tracking and commissions.</p>
                  </td>
                </tr>
              ) : filteredEmployees.length === 0 && searchQuery.trim() ? (
                <tr>
                  <td colSpan={6} className="px-4 py-8 text-center text-sm text-surface-500 dark:text-surface-400">
                    No employees match <span className="font-medium">"{searchQuery}"</span>
                  </td>
                </tr>
              ) : (
                filteredEmployees.map((emp) => (
                  <EmployeeRow
                    key={emp.id}
                    employee={emp}
                    currentUser={currentUser}
                    isExpanded={expandedId === emp.id}
                    onToggle={() => setExpandedId(expandedId === emp.id ? null : emp.id)}
                    onClockAction={(action) => { setPinLockedUntil(null); setPinAttemptsRemaining(null); setPinModal({ employee: emp, action }); }}
                  />
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>

      {/* PIN Modal */}
      {pinModal && (
        <PinModal
          employee={pinModal.employee}
          action={pinModal.action}
          onClose={() => { setPinModal(null); setPinLockedUntil(null); setPinAttemptsRemaining(null); }}
          onSubmit={handlePinSubmit}
          isPending={clockInMutation.isPending || clockOutMutation.isPending}
          lockedUntilProp={pinLockedUntil}
          attemptsRemainingProp={pinAttemptsRemaining}
        />
      )}
    </div>
  );
}

// WEB-UIUX-1254: tiny live-elapsed display rendered under the on-shift pill.
// Re-ticks every 30s so the row doesn't thrash on second boundaries while the
// rest of the list re-renders.
function ActiveShiftElapsed({ clockInAt }: { clockInAt: string }) {
  const [, setNow] = useState(Date.now());
  useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 30_000);
    return () => clearInterval(t);
  }, []);
  const startMs = new Date(clockInAt).getTime();
  if (!Number.isFinite(startMs)) return null;
  const elapsedMin = Math.max(0, Math.floor((Date.now() - startMs) / 60_000));
  const h = Math.floor(elapsedMin / 60);
  const m = elapsedMin % 60;
  return (
    <span
      className="ml-2 text-[11px] font-mono tabular-nums text-surface-500 dark:text-surface-400"
      title={`Clocked in at ${new Date(clockInAt).toLocaleTimeString()}`}
    >
      {h > 0 ? `${h}h ${m}m` : `${m}m`}
    </span>
  );
}

// ─── Employee Row ────────────────────────────────────────────────────
// WEB-S6-033 / WEB-UIUX-184: clock status + weekly hours are served by the
// list endpoint, and the expanded panel reuses one detail payload for pay rate,
// recent clock history, and recent commissions.
function EmployeeRow({ employee, currentUser, isExpanded, onToggle, onClockAction }: {
  employee: Employee;
  currentUser: { id: number; role: string } | null | undefined;
  isExpanded: boolean;
  onToggle: () => void;
  onClockAction: (action: 'clock-in' | 'clock-out') => void;
}) {
  // WEB-UIUX-902: canonical role gate via useHasRole.
  const isAdmin = useHasRole('admin');
  // WEB-S6-033: use list-level fields; only fetch detail when expanded.
  const isClockedIn = !!(employee.is_clocked_in);
  const weeklyHours = Number(employee.weekly_hours ?? 0);

  // Detail query fires only when the row is expanded (single call per user).
  const { data: detailData, isLoading: isDetailLoading } = useQuery({
    queryKey: ['employee-detail', employee.id],
    queryFn: () => employeeApi.get(employee.id),
    enabled: isExpanded,
    staleTime: 30000,
  });
  const detail = (detailData?.data as { data?: EmployeeDetail } | undefined)?.data;

  const roleClass = ROLE_COLORS[employee.role] ?? 'bg-surface-100 text-surface-700 dark:bg-surface-700 dark:text-surface-300';

  return (
    <>
      <tr
        onClick={onToggle}
        tabIndex={0}
        aria-expanded={isExpanded}
        onKeyDown={(e) => {
          if (e.key === 'Enter' || e.key === ' ') {
            e.preventDefault();
            onToggle();
          }
        }}
        className="cursor-pointer transition-colors hover:bg-surface-50 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-primary-500 dark:hover:bg-surface-800/50"
      >
        <td className="px-4 py-3">
          {isExpanded
            ? <ChevronDown className="h-4 w-4 text-surface-400" />
            : <ChevronRight className="h-4 w-4 text-surface-400" />}
        </td>
        <td className="px-4 py-3">
          <div className="flex items-center gap-3">
            <div className="flex h-8 w-8 items-center justify-center rounded-full bg-primary-100 text-xs font-semibold text-primary-700 dark:bg-primary-900/30 dark:text-primary-400">
              {employee.first_name?.[0]}{employee.last_name?.[0]}
            </div>
            <div>
              <div className="font-medium text-surface-900 dark:text-surface-100">
                {employee.first_name} {employee.last_name}
              </div>
              <div className="text-xs text-surface-500">{employee.email}</div>
            </div>
          </div>
        </td>
        <td className="px-4 py-3">
          <span className={cn('inline-flex rounded-full px-2.5 py-0.5 text-xs font-medium capitalize', roleClass)}>
            {employee.role}
          </span>
        </td>
        {/* WEB-UIUX-1272: pill badge replaces tiny dot for better kiosk legibility */}
        {/* WEB-UIUX-1254: live elapsed timer under the pill so a worker sees
            "On shift · 4h 12m" at a glance. */}
        <td className="px-4 py-3">
          <span className={cn(
            'inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold',
            isClockedIn
              ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
              : 'bg-surface-100 text-surface-500 dark:bg-surface-700 dark:text-surface-400',
          )}>
            {isClockedIn ? 'On shift' : 'Off'}
          </span>
          {isClockedIn && employee.active_clock_in_at && (
            <ActiveShiftElapsed clockInAt={employee.active_clock_in_at} />
          )}
        </td>
        <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
          {formatHours(weeklyHours)}
        </td>
        <td className="px-4 py-3">
          {/* WEB-UIUX-1251: server only lets admins clock OTHER employees. Non-admin users
              may only clock themselves in/out. Disable the button and show a tooltip when
              the current user is not an admin and this row is a different employee. */}
          {(() => {
            const canClock = isAdmin || currentUser?.id === employee.id;
            return (
              <span title={canClock ? undefined : 'Only admins can clock other employees'}>
                <button
                  type="button"
                  disabled={!canClock}
                  onClick={(e) => {
                    e.stopPropagation();
                    onClockAction(isClockedIn ? 'clock-out' : 'clock-in');
                  }}
                  className={cn(
                    'rounded-lg px-3 py-1.5 text-xs font-medium text-white transition-colors disabled:opacity-50 disabled:cursor-not-allowed',
                    isClockedIn
                      ? 'bg-red-600 hover:bg-red-700'
                      : 'bg-green-600 hover:bg-green-700',
                  )}
                >
                  {isClockedIn ? 'Clock Out' : 'Clock In'}
                </button>
              </span>
            );
          })()}
        </td>
      </tr>
      {isExpanded && (
        <EmployeeExpandedRow
          employee={employee}
          detail={detail}
          isDetailLoading={isDetailLoading}
        />
      )}
    </>
  );
}
