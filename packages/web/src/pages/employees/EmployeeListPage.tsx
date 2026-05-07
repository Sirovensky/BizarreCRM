import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  UserCog, Clock, DollarSign, ChevronDown, ChevronRight, X, Hash, Pencil, Check, Search,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { Link } from 'react-router-dom';
import { employeeApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';
import { formatCurrency, formatTime } from '@/utils/format';
import { useAuthStore } from '@/stores/authStore';

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
function PinModal({ employee, action, onClose, onSubmit, isPending }: {
  employee: Employee;
  action: 'clock-in' | 'clock-out';
  onClose: () => void;
  onSubmit: (pin: string) => void;
  isPending: boolean;
}) {
  const [pin, setPin] = useState('');
  // WEB-UIUX-1257: need current user role to show the right no-PIN guidance
  const { user: currentUser } = useAuthStore();

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
              : `${action === 'clock-in' ? 'Clock In' : 'Clock Out'} — ${employee.first_name}`}
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
              {currentUser?.role === 'admin' ? (
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
              <label className="mb-2 block text-sm font-medium text-surface-700 dark:text-surface-300">
                Enter PIN
              </label>
              <div className="relative">
                <Hash className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-surface-400" />
                <input
                  type="password"
                  inputMode="numeric"
                  maxLength={6}
                  value={pin}
                  onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
                  onKeyDown={(e) => {
                    // WEB-UIUX-1253: PIN is 4–6 digits; do NOT auto-submit at length 4 because
                    // the employee may still be typing a 5- or 6-digit PIN. Submit only on
                    // Enter when PIN is at max length (6); the explicit Submit button covers all lengths.
                    if (e.key === 'Enter' && pin.length === 6) onSubmit(pin);
                  }}
                  placeholder="4-6 digit PIN"
                  autoFocus
                  className="w-full rounded-lg border border-surface-300 py-3 pl-9 pr-4 text-center text-2xl tracking-[0.5em] dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
                />
              </div>
            </>
          )}
        </div>
        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          <button type="button"
            onClick={onClose}
            className="rounded-lg px-4 py-2 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            {employee.has_pin ? 'Cancel' : 'Close'}
          </button>
          <button type="button"
            onClick={() => onSubmit(pin)}
            disabled={!employee.has_pin || pin.length < 4 || isPending}
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
              <p className="text-sm text-surface-400">No clock entries yet. Use the clock in/out buttons above.</p>
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

  // Fetch employee list
  const { data: listData, isLoading } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
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
    mutationFn: ({ id, pin }: { id: number; pin: string }) => employeeApi.clockIn(id, pin),
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
      toast.error(formatApiError(err));
    },
  });

  // Clock out mutation
  const clockOutMutation = useMutation({
    mutationFn: ({ id, pin }: { id: number; pin: string }) => employeeApi.clockOut(id, pin),
    onSuccess: () => {
      toast.success('Clocked out successfully');
      setPinModal(null);
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      queryClient.invalidateQueries({ queryKey: ['employee-detail'] });
    },
    onError: (err: unknown) => {
      toast.error(formatApiError(err));
    },
  });

  const handlePinSubmit = (pin: string) => {
    if (!pinModal) return;
    if (pinModal.action === 'clock-in') {
      clockInMutation.mutate({ id: pinModal.employee.id, pin });
    } else {
      clockOutMutation.mutate({ id: pinModal.employee.id, pin });
    }
  };

  return (
    <div>
      {/* Header */}
      <div className="mb-6 flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">Employees</h1>
          <p className="text-surface-500 dark:text-surface-400">Manage technicians and staff</p>
        </div>
        <a
          href="/settings/users"
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-primary-950 shadow-sm transition-colors hover:bg-primary-700"
        >
          <UserCog className="h-4 w-4" />
          Add Employee
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
                    onClockAction={(action) => setPinModal({ employee: emp, action })}
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
          onClose={() => setPinModal(null)}
          onSubmit={handlePinSubmit}
          isPending={clockInMutation.isPending || clockOutMutation.isPending}
        />
      )}
    </div>
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
        <td className="px-4 py-3">
          <div className="flex items-center gap-2">
            <span className={cn(
              'h-2.5 w-2.5 rounded-full',
              isClockedIn ? 'bg-green-500' : 'bg-surface-300 dark:bg-surface-600',
            )} />
            <span className={cn(
              'text-sm',
              isClockedIn
                ? 'font-medium text-green-700 dark:text-green-400'
                : 'text-surface-500 dark:text-surface-400',
            )}>
              {isClockedIn ? 'Clocked In' : 'Clocked Out'}
            </span>
          </div>
        </td>
        <td className="px-4 py-3 text-surface-700 dark:text-surface-300">
          {formatHours(weeklyHours)}
        </td>
        <td className="px-4 py-3">
          {/* WEB-UIUX-1251: server only lets admins clock OTHER employees. Non-admin users
              may only clock themselves in/out. Disable the button and show a tooltip when
              the current user is not an admin and this row is a different employee. */}
          {(() => {
            const canClock = currentUser?.role === 'admin' || currentUser?.id === employee.id;
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
                    'rounded-lg px-3 py-1.5 text-xs font-medium text-white transition-colors disabled:opacity-40 disabled:cursor-not-allowed',
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
