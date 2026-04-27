/**
 * Automation rule detail page — WEB-S6-019.
 *
 * Reached at /automations/:id. Shows the rule's full condition/action
 * builder using the shared AutomationModal form components from
 * AutomationsTab. Admins can edit and save inline; non-admins see read-only
 * summary and are redirected back if they try to reach this URL directly.
 */
import { useState } from 'react';
import { useParams, useNavigate, Link } from 'react-router-dom';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { ArrowLeft, Loader2, AlertCircle, Zap, FlaskConical } from 'lucide-react';
import toast from 'react-hot-toast';
import { automationsApi, settingsApi } from '@/api/endpoints';
import { useAuthStore } from '@/stores/authStore';
import { formatDateTime } from '@/utils/format';
import {
  AutomationModal,
  type AutomationRule,
  type TicketStatus,
  type UserRecord,
  triggerLabel,
  actionLabel,
  triggerConfigSummary,
  actionConfigSummary,
} from './AutomationsTab';

export function AutomationDetailPage() {
  const { id } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const userRole = useAuthStore((s) => s.user?.role);
  const isAdmin = userRole === 'admin';
  const [showEdit, setShowEdit] = useState(false);

  const ruleId = id ? parseInt(id, 10) : NaN;

  const { data: ruleData, isLoading, isError } = useQuery({
    queryKey: ['automations', ruleId],
    enabled: !Number.isNaN(ruleId),
    queryFn: async () => {
      const res = await automationsApi.getOne(ruleId);
      return res.data.data as AutomationRule;
    },
  });

  const { data: statuses } = useQuery({
    queryKey: ['settings', 'statuses'],
    queryFn: async () => {
      const res = await settingsApi.getStatuses();
      return (res.data.data || []) as TicketStatus[];
    },
  });

  const { data: users } = useQuery({
    queryKey: ['settings', 'users'],
    queryFn: async () => {
      const res = await settingsApi.getUsers();
      return (res.data.data?.users || res.data.data || []) as UserRecord[];
    },
  });

  const updateMut = useMutation({
    mutationFn: (data: Parameters<typeof automationsApi.update>[1]) =>
      automationsApi.update(ruleId, data),
    onSuccess: () => {
      toast.success('Automation rule updated');
      queryClient.invalidateQueries({ queryKey: ['automations', ruleId] });
      queryClient.invalidateQueries({ queryKey: ['automations'] });
      setShowEdit(false);
    },
    onError: (err: unknown) => {
      const e = err as { response?: { data?: { message?: string } } } | undefined;
      toast.error(e?.response?.data?.message || 'Failed to update rule');
    },
  });

  const dryRunMut = useMutation({
    mutationFn: () => automationsApi.dryRun(ruleId),
    onSuccess: (res) => {
      const d = (res.data as any)?.data ?? {};
      if (d.trigger_would_fire) {
        toast.success(`Would fire — ${d.action_preview ?? d.action_type}`, { duration: 5000 });
      } else {
        toast(`Would NOT fire (trigger conditions not met)`, { icon: '🔍', duration: 5000 });
      }
    },
    onError: () => toast.error('Dry-run failed'),
  });

  const statusList = statuses ?? [];
  const userList = users ?? [];

  if (Number.isNaN(ruleId)) {
    return (
      <div className="p-6 max-w-3xl mx-auto">
        <p className="text-red-600 text-sm">Invalid automation ID.</p>
        <Link to="/settings/automations" className="text-primary-600 hover:underline text-sm mt-2 inline-block">
          Back to automations
        </Link>
      </div>
    );
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
      </div>
    );
  }

  if (isError || !ruleData) {
    return (
      <div className="p-6 max-w-3xl mx-auto flex flex-col items-center py-20">
        <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
        <p className="text-sm text-surface-500 mb-4">Automation rule not found.</p>
        <button
          className="text-primary-600 hover:underline text-sm"
          onClick={() => navigate(-1)}
        >
          Go back
        </button>
      </div>
    );
  }

  const rule = ruleData;

  return (
    <div className="p-6 max-w-3xl mx-auto">
      {/* Back nav */}
      <div className="mb-4">
        <Link
          to="/settings/automations"
          className="inline-flex items-center gap-1 text-sm text-surface-500 hover:text-surface-800 dark:hover:text-surface-200"
        >
          <ArrowLeft className="h-4 w-4" /> Back to Automations
        </Link>
      </div>

      {/* Header */}
      <header className="mb-6 flex items-start justify-between">
        <div>
          <div className="flex items-center gap-2">
            <Zap className="h-6 w-6 text-primary-500" />
            <h1 className="text-2xl font-bold text-surface-900 dark:text-surface-100">{rule.name}</h1>
            <span
              className={`text-xs font-semibold uppercase rounded px-2 py-0.5 ${
                rule.is_active
                  ? 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-400'
                  : 'bg-surface-200 dark:bg-surface-700 text-surface-500'
              }`}
            >
              {rule.is_active ? 'Active' : 'Disabled'}
            </span>
          </div>
          <p className="text-sm text-surface-500 mt-1">
            Created {formatDateTime(rule.created_at.replace(' ', 'T'))}
            {rule.updated_at !== rule.created_at && (
              <> · Updated {formatDateTime(rule.updated_at.replace(' ', 'T'))}</>
            )}
          </p>
        </div>
        {isAdmin && (
          <div className="flex gap-2">
            <button
              className="inline-flex items-center gap-1 px-3 py-1.5 rounded border text-sm text-surface-600 dark:text-surface-300 hover:bg-surface-50 dark:hover:bg-surface-800 disabled:opacity-40"
              disabled={dryRunMut.isPending}
              onClick={() => dryRunMut.mutate()}
            >
              {dryRunMut.isPending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <FlaskConical className="h-4 w-4" />
              )}
              Dry-run
            </button>
            <button
              className="px-3 py-1.5 bg-primary-600 text-primary-950 rounded text-sm hover:bg-primary-700"
              onClick={() => setShowEdit(true)}
            >
              Edit rule
            </button>
          </div>
        )}
      </header>

      {/* Rule details card */}
      <div className="bg-white dark:bg-surface-900 border dark:border-surface-700 rounded-xl shadow divide-y dark:divide-surface-700">
        <div className="p-5">
          <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Trigger (When)</h2>
          <p className="text-sm font-medium text-surface-800 dark:text-surface-200">
            {triggerLabel(rule.trigger_type)}
            {triggerConfigSummary(rule.trigger_type, rule.trigger_config, statusList)}
          </p>
        </div>
        <div className="p-5">
          <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Action (Then)</h2>
          <p className="text-sm font-medium text-surface-800 dark:text-surface-200">
            {actionLabel(rule.action_type)}
          </p>
          <p className="text-sm text-surface-500 mt-1">
            {actionConfigSummary(rule.action_type, rule.action_config, statusList, userList)}
          </p>
        </div>
        <div className="p-5">
          <h2 className="text-xs font-semibold text-surface-400 uppercase tracking-wider mb-3">Raw Config</h2>
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
            <div>
              <p className="text-xs text-surface-400 mb-1">Trigger config</p>
              <pre className="text-xs bg-surface-50 dark:bg-surface-800 rounded p-2 overflow-x-auto text-surface-700 dark:text-surface-300">
                {JSON.stringify(rule.trigger_config, null, 2)}
              </pre>
            </div>
            <div>
              <p className="text-xs text-surface-400 mb-1">Action config</p>
              <pre className="text-xs bg-surface-50 dark:bg-surface-800 rounded p-2 overflow-x-auto text-surface-700 dark:text-surface-300">
                {JSON.stringify(rule.action_config, null, 2)}
              </pre>
            </div>
          </div>
        </div>
      </div>

      {/* Edit modal */}
      {showEdit && isAdmin && (
        <AutomationModal
          rule={rule}
          statuses={statusList}
          users={userList}
          onClose={() => setShowEdit(false)}
          onSave={(data) => updateMut.mutate(data)}
          saving={updateMut.isPending}
        />
      )}
    </div>
  );
}
