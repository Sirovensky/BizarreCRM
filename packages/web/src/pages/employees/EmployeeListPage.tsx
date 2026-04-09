import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  UserCog, Clock, DollarSign, ChevronDown, ChevronRight, X, Hash,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { employeeApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { formatCurrency } from '@/utils/format';

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
}

interface EmployeeDetail extends Employee {
  clock_entries: ClockEntry[];
  commissions: Commission[];
  is_clocked_in: boolean;
  current_clock_entry: ClockEntry | null;
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
function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-US', {
    month: 'short', day: 'numeric',
  });
}

function formatTime(iso: string) {
  return new Date(iso).toLocaleTimeString('en-US', {
    hour: 'numeric', minute: '2-digit',
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

function getWeekRange() {
  const now = new Date();
  const dayOfWeek = now.getDay();
  const monday = new Date(now);
  monday.setDate(now.getDate() - ((dayOfWeek + 6) % 7));
  monday.setHours(0, 0, 0, 0);
  return {
    from_date: monday.toISOString(),
    to_date: new Date().toISOString(),
  };
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

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/50" onClick={onClose}>
      <div className="w-full max-w-sm rounded-xl bg-white shadow-2xl dark:bg-surface-800" onClick={(e) => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-surface-200 px-4 py-3 dark:border-surface-700">
          <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            {action === 'clock-in' ? 'Clock In' : 'Clock Out'} - {employee.first_name}
          </h3>
          <button onClick={onClose} className="rounded-lg p-1 hover:bg-surface-100 dark:hover:bg-surface-700">
            <X className="h-5 w-5 text-surface-500" />
          </button>
        </div>
        <div className="p-6">
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
                if (e.key === 'Enter' && pin.length >= 4) onSubmit(pin);
              }}
              placeholder="4-6 digit PIN"
              autoFocus
              className="w-full rounded-lg border border-surface-300 py-3 pl-9 pr-4 text-center text-2xl tracking-[0.5em] dark:border-surface-600 dark:bg-surface-700 dark:text-surface-100"
            />
          </div>
          {!employee.has_pin && (
            <p className="mt-2 text-xs text-amber-600 dark:text-amber-400">
              No PIN set for this employee. Any value will be accepted.
            </p>
          )}
        </div>
        <div className="flex justify-end gap-2 border-t border-surface-200 px-4 py-3 dark:border-surface-700">
          <button
            onClick={onClose}
            className="rounded-lg px-4 py-2 text-sm font-medium text-surface-600 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-700"
          >
            Cancel
          </button>
          <button
            onClick={() => onSubmit(pin)}
            disabled={pin.length < 4 || isPending}
            className={cn(
              'rounded-lg px-4 py-2 text-sm font-medium text-white disabled:opacity-50',
              action === 'clock-in'
                ? 'bg-green-600 hover:bg-green-700'
                : 'bg-red-600 hover:bg-red-700',
            )}
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

// ─── Expanded Row Detail ────────────────────────────────────────────
function EmployeeExpandedRow({ employeeId }: { employeeId: number }) {
  const weekRange = getWeekRange();
  const monthRange = getMonthRange();

  const { data: hoursData } = useQuery({
    queryKey: ['employee-hours', employeeId, weekRange.from_date],
    queryFn: () => employeeApi.hours(employeeId, weekRange),
  });

  const { data: commissionsData } = useQuery({
    queryKey: ['employee-commissions', employeeId, monthRange.from_date],
    queryFn: () => employeeApi.commissions(employeeId, monthRange),
  });

  const { data: detailData } = useQuery({
    queryKey: ['employee-detail', employeeId],
    queryFn: () => employeeApi.get(employeeId),
  });

  const hoursResult = (hoursData?.data as any)?.data;
  const commissionsResult = (commissionsData?.data as any)?.data;
  const detail = (detailData?.data as any)?.data as EmployeeDetail | undefined;

  const recentClock = detail?.clock_entries?.slice(0, 5) ?? [];
  const recentCommissions = detail?.commissions?.slice(0, 5) ?? [];

  return (
    <tr>
      <td colSpan={6} className="bg-surface-50/50 px-4 py-4 dark:bg-surface-800/50">
        <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
          {/* Recent Clock Entries */}
          <div>
            <h4 className="mb-2 flex items-center gap-2 text-sm font-semibold text-surface-700 dark:text-surface-300">
              <Clock className="h-4 w-4" />
              Recent Clock Entries
              {hoursResult && (
                <span className="ml-auto text-xs font-normal text-surface-500">
                  This week: {formatHours(hoursResult.total_hours ?? 0)}
                </span>
              )}
            </h4>
            {recentClock.length === 0 ? (
              <p className="text-sm text-surface-400">No clock entries found</p>
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
              {commissionsResult && (
                <span className="ml-auto text-xs font-normal text-surface-500">
                  This month: {formatCurrency(commissionsResult.total_amount ?? 0)}
                </span>
              )}
            </h4>
            {recentCommissions.length === 0 ? (
              <p className="text-sm text-surface-400">No commissions found</p>
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

  // Fetch employee list
  const { data: listData, isLoading } = useQuery({
    queryKey: ['employees'],
    queryFn: () => employeeApi.list(),
  });
  const employees: Employee[] = (listData?.data as any)?.data ?? [];

  // Fetch detail for each employee to get clock status
  const detailQueries = employees.map((emp) => ({
    queryKey: ['employee-detail', emp.id],
    queryFn: () => employeeApi.get(emp.id),
    enabled: true,
  }));
  // Use individual queries for status
  const employeeDetails = new Map<number, EmployeeDetail>();
  // We'll fetch details within the table rendering via separate queries

  // Clock in mutation
  const clockInMutation = useMutation({
    mutationFn: ({ id, pin }: { id: number; pin: string }) => employeeApi.clockIn(id, pin),
    onSuccess: () => {
      toast.success('Clocked in successfully');
      setPinModal(null);
      queryClient.invalidateQueries({ queryKey: ['employees'] });
      queryClient.invalidateQueries({ queryKey: ['employee-detail'] });
      queryClient.invalidateQueries({ queryKey: ['employee-hours'] });
    },
    onError: (err: any) => {
      toast.error(err.response?.data?.message || 'Failed to clock in');
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
      queryClient.invalidateQueries({ queryKey: ['employee-hours'] });
    },
    onError: (err: any) => {
      toast.error(err.response?.data?.message || 'Failed to clock out');
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
          className="inline-flex items-center gap-2 rounded-lg bg-primary-600 px-4 py-2 text-sm font-medium text-white shadow-sm transition-colors hover:bg-primary-700"
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
                    <p className="text-surface-500">No employees found</p>
                  </td>
                </tr>
              ) : (
                employees.map((emp) => (
                  <EmployeeRow
                    key={emp.id}
                    employee={emp}
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

// ─── Employee Row (with detail query) ───────────────────────────────
function EmployeeRow({ employee, isExpanded, onToggle, onClockAction }: {
  employee: Employee;
  isExpanded: boolean;
  onToggle: () => void;
  onClockAction: (action: 'clock-in' | 'clock-out') => void;
}) {
  const weekRange = getWeekRange();

  const { data: detailData } = useQuery({
    queryKey: ['employee-detail', employee.id],
    queryFn: () => employeeApi.get(employee.id),
    staleTime: 30000,
  });

  const { data: hoursData } = useQuery({
    queryKey: ['employee-hours', employee.id, weekRange.from_date],
    queryFn: () => employeeApi.hours(employee.id, weekRange),
    staleTime: 60000,
  });

  const detail = (detailData?.data as any)?.data as EmployeeDetail | undefined;
  const weeklyHours = (hoursData?.data as any)?.data?.total_hours ?? 0;
  const isClockedIn = detail?.is_clocked_in ?? false;

  const roleClass = ROLE_COLORS[employee.role] ?? 'bg-surface-100 text-surface-700 dark:bg-surface-700 dark:text-surface-300';

  return (
    <>
      <tr
        onClick={onToggle}
        className="cursor-pointer transition-colors hover:bg-surface-50 dark:hover:bg-surface-800/50"
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
          <button
            onClick={(e) => {
              e.stopPropagation();
              onClockAction(isClockedIn ? 'clock-out' : 'clock-in');
            }}
            className={cn(
              'rounded-lg px-3 py-1.5 text-xs font-medium text-white transition-colors',
              isClockedIn
                ? 'bg-red-600 hover:bg-red-700'
                : 'bg-green-600 hover:bg-green-700',
            )}
          >
            {isClockedIn ? 'Clock Out' : 'Clock In'}
          </button>
        </td>
      </tr>
      {isExpanded && <EmployeeExpandedRow employeeId={employee.id} />}
    </>
  );
}
