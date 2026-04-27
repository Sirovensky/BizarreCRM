import { CommissionPeriodLock } from '@/components/team/CommissionPeriodLock';

export function PayrollPage() {
  return (
    <div className="p-6 max-w-3xl mx-auto space-y-6">
      <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-50">Payroll</h1>
      <CommissionPeriodLock />
    </div>
  );
}
