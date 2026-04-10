import { Loader2, AlertCircle, Package } from 'lucide-react';

export function SummaryCard({ label, value, icon: Icon, color, bg }: {
  label: string; value: string; icon: React.ComponentType<{ className?: string }>; color: string; bg: string;
}) {
  return (
    <div className="card flex items-center gap-4 p-5">
      <div className={`flex items-center justify-center h-12 w-12 rounded-xl ${bg}`}>
        <Icon className={`h-6 w-6 ${color}`} />
      </div>
      <div>
        <p className="text-sm text-surface-500 dark:text-surface-400">{label}</p>
        <p className="text-2xl font-bold text-surface-900 dark:text-surface-100">{value}</p>
      </div>
    </div>
  );
}

export function LoadingState() {
  return (
    <div className="flex items-center justify-center py-20">
      <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
      <span className="ml-3 text-surface-500">Loading report data...</span>
    </div>
  );
}

export function ErrorState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-20">
      <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
      <p className="text-sm text-surface-500">{message}</p>
    </div>
  );
}

export function EmptyState({ message }: { message: string }) {
  return (
    <div className="flex flex-col items-center justify-center py-16">
      <Package className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-3" />
      <p className="text-sm text-surface-400 dark:text-surface-500">{message}</p>
    </div>
  );
}
