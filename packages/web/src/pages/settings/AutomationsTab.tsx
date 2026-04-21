import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, Plus, Trash2, X, Save, Zap, AlertCircle, ChevronDown, ChevronUp, FlaskConical } from 'lucide-react';
import toast from 'react-hot-toast';
import { automationsApi, settingsApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';

// -- Types ------------------------------------------------------------------

interface AutomationRule {
  id: number;
  name: string;
  is_active: number;
  trigger_type: string;
  trigger_config: Record<string, unknown>;
  action_type: string;
  action_config: Record<string, unknown>;
  sort_order: number;
  created_at: string;
  updated_at: string;
}

interface TicketStatus {
  id: number;
  name: string;
  color: string;
}

interface UserRecord {
  id: number;
  username: string;
  first_name: string;
  last_name: string;
}

// -- Constants ---------------------------------------------------------------

const TRIGGER_TYPES = [
  { value: 'ticket_created', label: 'Ticket Created' },
  { value: 'ticket_status_changed', label: 'Ticket Status Changed' },
  { value: 'ticket_assigned', label: 'Ticket Assigned' },
  { value: 'customer_created', label: 'Customer Created' },
  { value: 'invoice_created', label: 'Invoice Created' },
] as const;

const ACTION_TYPES = [
  { value: 'send_sms', label: 'Send SMS' },
  { value: 'send_email', label: 'Send Email' },
  { value: 'change_status', label: 'Change Ticket Status' },
  { value: 'assign_to', label: 'Assign Ticket' },
  { value: 'add_note', label: 'Add Note to Ticket' },
  { value: 'create_notification', label: 'Create Notification' },
] as const;

const TEMPLATE_VARS = [
  { key: '{ticket_id}', desc: 'Ticket ID' },
  { key: '{customer_name}', desc: 'Customer full name' },
  { key: '{customer_phone}', desc: 'Customer phone' },
  { key: '{customer_email}', desc: 'Customer email' },
  { key: '{device_name}', desc: 'Device name' },
  { key: '{ticket_status}', desc: 'Ticket status' },
  { key: '{ticket_total}', desc: 'Ticket total' },
  { key: '{invoice_id}', desc: 'Invoice ID' },
  { key: '{invoice_total}', desc: 'Invoice total' },
];

function triggerLabel(type: string): string {
  return TRIGGER_TYPES.find((t) => t.value === type)?.label ?? type;
}

function actionLabel(type: string): string {
  return ACTION_TYPES.find((a) => a.value === type)?.label ?? type;
}

// -- Toggle Switch -----------------------------------------------------------

function ToggleSwitch({ checked, onChange, disabled }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      disabled={disabled}
      className={cn(
        'relative inline-flex h-5 w-9 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-primary-500 focus:ring-offset-1',
        checked ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600',
        disabled && 'opacity-50 cursor-not-allowed'
      )}
    >
      <span
        className="inline-block h-3.5 w-3.5 rounded-full bg-white transition-transform"
        style={{ transform: checked ? 'translateX(18px)' : 'translateX(2px)' }}
      />
    </button>
  );
}

// -- Trigger Config Form -----------------------------------------------------

function TriggerConfigForm({
  triggerType,
  config,
  onChange,
  statuses,
}: {
  triggerType: string;
  config: Record<string, unknown>;
  onChange: (c: Record<string, unknown>) => void;
  statuses: TicketStatus[];
}) {
  if (triggerType !== 'ticket_status_changed') return null;

  return (
    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
      <div>
        <label className="block text-xs font-medium text-surface-500 mb-1">From Status (optional)</label>
        <select
          value={String(config.from_status_id ?? '')}
          onChange={(e) => onChange({ ...config, from_status_id: e.target.value ? Number(e.target.value) : undefined })}
          className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
        >
          <option value="">Any status</option>
          {statuses.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
      </div>
      <div>
        <label className="block text-xs font-medium text-surface-500 mb-1">To Status (optional)</label>
        <select
          value={String(config.to_status_id ?? '')}
          onChange={(e) => onChange({ ...config, to_status_id: e.target.value ? Number(e.target.value) : undefined })}
          className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
        >
          <option value="">Any status</option>
          {statuses.map((s) => (
            <option key={s.id} value={s.id}>{s.name}</option>
          ))}
        </select>
      </div>
    </div>
  );
}

// -- Action Config Form ------------------------------------------------------

function ActionConfigForm({
  actionType,
  config,
  onChange,
  statuses,
  users,
}: {
  actionType: string;
  config: Record<string, unknown>;
  onChange: (c: Record<string, unknown>) => void;
  statuses: TicketStatus[];
  users: UserRecord[];
}) {
  switch (actionType) {
    case 'send_sms':
      return (
        <div className="space-y-3 mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">
              To (leave blank for customer phone)
            </label>
            <input
              type="text"
              value={String(config.to ?? '')}
              onChange={(e) => onChange({ ...config, to: e.target.value })}
              placeholder="{customer_phone}"
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">Message Template *</label>
            <textarea
              value={String(config.template ?? '')}
              onChange={(e) => onChange({ ...config, template: e.target.value })}
              rows={3}
              placeholder="Hi {customer_name}, your repair #{ticket_id} status has been updated to {ticket_status}."
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            />
          </div>
          <TemplateVarHints />
        </div>
      );

    case 'send_email':
      return (
        <div className="space-y-3 mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">Subject *</label>
            <input
              type="text"
              value={String(config.subject ?? '')}
              onChange={(e) => onChange({ ...config, subject: e.target.value })}
              placeholder="Repair #{ticket_id} Update"
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            />
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">Body (HTML) *</label>
            <textarea
              value={String(config.body ?? '')}
              onChange={(e) => onChange({ ...config, body: e.target.value })}
              rows={4}
              placeholder="<p>Hi {customer_name}, your repair is ready for pickup.</p>"
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 font-mono"
            />
          </div>
          <TemplateVarHints />
        </div>
      );

    case 'change_status':
      return (
        <div className="mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <label className="block text-xs font-medium text-surface-500 mb-1">New Status *</label>
          <select
            value={String(config.status_id ?? '')}
            onChange={(e) => onChange({ ...config, status_id: e.target.value ? Number(e.target.value) : undefined })}
            className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
          >
            <option value="">Select status...</option>
            {statuses.map((s) => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>
        </div>
      );

    case 'assign_to':
      return (
        <div className="mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <label className="block text-xs font-medium text-surface-500 mb-1">Assign To User *</label>
          <select
            value={String(config.user_id ?? '')}
            onChange={(e) => onChange({ ...config, user_id: e.target.value ? Number(e.target.value) : undefined })}
            className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
          >
            <option value="">Select user...</option>
            {users.map((u) => (
              <option key={u.id} value={u.id}>
                {u.first_name} {u.last_name} ({u.username})
              </option>
            ))}
          </select>
        </div>
      );

    case 'add_note':
      return (
        <div className="space-y-3 mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">Note Type</label>
            <select
              value={String(config.type ?? 'internal')}
              onChange={(e) => onChange({ ...config, type: e.target.value })}
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            >
              <option value="internal">Internal</option>
              <option value="diagnostic">Diagnostic</option>
            </select>
          </div>
          <div>
            <label className="block text-xs font-medium text-surface-500 mb-1">Note Content *</label>
            <textarea
              value={String(config.content ?? '')}
              onChange={(e) => onChange({ ...config, content: e.target.value })}
              rows={3}
              placeholder="Auto-note: Status changed to {ticket_status}"
              className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
            />
          </div>
          <TemplateVarHints />
        </div>
      );

    case 'create_notification':
      return (
        <div className="mt-3 p-3 bg-surface-50 dark:bg-surface-800/50 rounded-lg">
          <label className="block text-xs font-medium text-surface-500 mb-1">Notification Message *</label>
          <textarea
            value={String(config.message ?? '')}
            onChange={(e) => onChange({ ...config, message: e.target.value })}
            rows={2}
            placeholder="Ticket #{ticket_id} for {customer_name} needs attention"
            className="w-full px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100"
          />
          <TemplateVarHints />
        </div>
      );

    default:
      return null;
  }
}

// -- Template Variable Hints -------------------------------------------------

function TemplateVarHints() {
  return (
    <div>
      <p className="text-xs text-surface-400 mb-1.5">Available variables:</p>
      <div className="flex flex-wrap gap-1">
        {TEMPLATE_VARS.map((v) => (
          <span
            key={v.key}
            title={v.desc}
            className="inline-block rounded bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300 px-1.5 py-0.5 text-[10px] font-mono cursor-help"
          >
            {v.key}
          </span>
        ))}
      </div>
    </div>
  );
}

// -- Create/Edit Modal -------------------------------------------------------

function AutomationModal({
  rule,
  statuses,
  users,
  onClose,
  onSave,
  saving,
}: {
  rule: AutomationRule | null;
  statuses: TicketStatus[];
  users: UserRecord[];
  onClose: () => void;
  onSave: (data: {
    name: string;
    trigger_type: string;
    trigger_config: Record<string, unknown>;
    action_type: string;
    action_config: Record<string, unknown>;
  }) => void;
  saving: boolean;
}) {
  const [name, setName] = useState(rule?.name ?? '');
  const [triggerType, setTriggerType] = useState(rule?.trigger_type ?? 'ticket_status_changed');
  const [triggerConfig, setTriggerConfig] = useState<Record<string, unknown>>(rule?.trigger_config ?? {});
  const [actionType, setActionType] = useState(rule?.action_type ?? 'send_sms');
  const [actionConfig, setActionConfig] = useState<Record<string, unknown>>(rule?.action_config ?? {});

  function handleSave() {
    if (!name.trim()) {
      toast.error('Name is required');
      return;
    }
    // Strip empty values from configs
    const cleanTrigger = Object.fromEntries(
      Object.entries(triggerConfig).filter(([, v]) => v !== undefined && v !== '')
    );
    const cleanAction = Object.fromEntries(
      Object.entries(actionConfig).filter(([, v]) => v !== undefined && v !== '')
    );
    onSave({ name: name.trim(), trigger_type: triggerType, trigger_config: cleanTrigger, action_type: actionType, action_config: cleanAction });
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-surface-900 rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-surface-200 dark:border-surface-700">
          <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
            {rule ? 'Edit Automation Rule' : 'Create Automation Rule'}
          </h3>
          <button aria-label="Close" onClick={onClose} className="p-1.5 rounded-lg hover:bg-surface-100 dark:hover:bg-surface-800 text-surface-400">
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Body */}
        <div className="p-5 space-y-5">
          {/* Name */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">Rule Name *</label>
            <input
              type="text"
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="e.g. Notify customer on status change"
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500"
            />
          </div>

          {/* Trigger */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">When (Trigger)</label>
            <select
              value={triggerType}
              onChange={(e) => { setTriggerType(e.target.value); setTriggerConfig({}); }}
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {TRIGGER_TYPES.map((t) => (
                <option key={t.value} value={t.value}>{t.label}</option>
              ))}
            </select>
            <TriggerConfigForm
              triggerType={triggerType}
              config={triggerConfig}
              onChange={setTriggerConfig}
              statuses={statuses}
            />
          </div>

          {/* Action */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">Then (Action)</label>
            <select
              value={actionType}
              onChange={(e) => { setActionType(e.target.value); setActionConfig({}); }}
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {ACTION_TYPES.map((a) => (
                <option key={a.value} value={a.value}>{a.label}</option>
              ))}
            </select>
            <ActionConfigForm
              actionType={actionType}
              config={actionConfig}
              onChange={setActionConfig}
              statuses={statuses}
              users={users}
            />
          </div>
        </div>

        {/* Footer */}
        <div className="flex items-center justify-end gap-3 p-5 border-t border-surface-200 dark:border-surface-700">
          <button
            onClick={onClose}
            className="px-4 py-2 text-sm font-medium text-surface-700 dark:text-surface-300 bg-surface-100 dark:bg-surface-800 rounded-lg hover:bg-surface-200 dark:hover:bg-surface-700 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={saving || !name.trim()}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition-colors disabled:opacity-50"
          >
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            {rule ? 'Update Rule' : 'Create Rule'}
          </button>
        </div>
      </div>
    </div>
  );
}

// -- Action Config Summary ---------------------------------------------------

function actionConfigSummary(actionType: string, config: Record<string, unknown>, statuses: TicketStatus[], users: UserRecord[]): string {
  switch (actionType) {
    case 'send_sms':
      return config.template ? `"${String(config.template).slice(0, 60)}${String(config.template).length > 60 ? '...' : ''}"` : 'No template';
    case 'send_email':
      return config.subject ? `Subject: ${String(config.subject)}` : 'No subject';
    case 'change_status': {
      const st = statuses.find((s) => s.id === Number(config.status_id));
      return st ? `Change to "${st.name}"` : 'No status selected';
    }
    case 'assign_to': {
      const u = users.find((u) => u.id === Number(config.user_id));
      return u ? `Assign to ${u.first_name} ${u.last_name}` : 'No user selected';
    }
    case 'add_note':
      return config.content ? `${String(config.type ?? 'internal')} note` : 'No content';
    case 'create_notification':
      return config.message ? `"${String(config.message).slice(0, 60)}..."` : 'No message';
    default:
      return '';
  }
}

function triggerConfigSummary(triggerType: string, config: Record<string, unknown>, statuses: TicketStatus[]): string {
  if (triggerType !== 'ticket_status_changed') return '';
  const parts: string[] = [];
  if (config.from_status_id) {
    const s = statuses.find((s) => s.id === Number(config.from_status_id));
    if (s) parts.push(`from "${s.name}"`);
  }
  if (config.to_status_id) {
    const s = statuses.find((s) => s.id === Number(config.to_status_id));
    if (s) parts.push(`to "${s.name}"`);
  }
  return parts.length > 0 ? ` (${parts.join(' ')})` : ' (any status)';
}

// -- Main Component ----------------------------------------------------------

export function AutomationsTab() {
  const queryClient = useQueryClient();
  const [showModal, setShowModal] = useState(false);
  const [editingRule, setEditingRule] = useState<AutomationRule | null>(null);
  const [expandedId, setExpandedId] = useState<number | null>(null);

  // Fetch automations
  const { data: automations, isLoading, isError } = useQuery({
    queryKey: ['automations'],
    queryFn: async () => {
      const res = await automationsApi.list();
      return res.data.data as AutomationRule[];
    },
  });

  // Fetch statuses for dropdowns
  const { data: statuses } = useQuery({
    queryKey: ['settings', 'statuses'],
    queryFn: async () => {
      const res = await settingsApi.getStatuses();
      // Server: res.json({ success: true, data: statuses }) — array directly.
      return (res.data.data || []) as TicketStatus[];
    },
  });

  // Fetch users for dropdowns
  const { data: users } = useQuery({
    queryKey: ['settings', 'users'],
    queryFn: async () => {
      const res = await settingsApi.getUsers();
      return (res.data.data?.users || res.data.data || []) as UserRecord[];
    },
  });

  const createMut = useMutation({
    mutationFn: (data: Parameters<typeof automationsApi.create>[0]) => automationsApi.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['automations'] });
      toast.success('Automation rule created');
      setShowModal(false);
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to create rule'),
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: Parameters<typeof automationsApi.update>[1] }) => automationsApi.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['automations'] });
      toast.success('Automation rule updated');
      setShowModal(false);
      setEditingRule(null);
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to update rule'),
  });

  const toggleMut = useMutation({
    mutationFn: (id: number) => automationsApi.toggle(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['automations'] });
    },
    onError: () => toast.error('Failed to toggle rule'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => automationsApi.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['automations'] });
      toast.success('Automation rule deleted');
    },
    onError: () => toast.error('Failed to delete rule'),
  });

  const dryRunMut = useMutation({
    mutationFn: (id: number) => automationsApi.dryRun(id),
    onSuccess: (res) => {
      const d = (res.data as any)?.data ?? {};
      if (d.trigger_would_fire) {
        toast.success(
          `Would fire — ${d.action_preview ?? d.action_type}`,
          { duration: 5000 },
        );
      } else {
        toast(`Would NOT fire (trigger conditions not met)`, {
          icon: '🔍',
          duration: 5000,
        });
      }
    },
    onError: () => toast.error('Dry-run failed'),
  });

  async function handleDelete(rule: AutomationRule) {
    const ok = await confirm(
      `Are you sure you want to delete "${rule.name}"? This action cannot be undone.`,
      { title: 'Delete Automation Rule', confirmLabel: 'Delete', danger: true },
    );
    if (ok) deleteMut.mutate(rule.id);
  }

  function handleSave(data: {
    name: string;
    trigger_type: string;
    trigger_config: Record<string, unknown>;
    action_type: string;
    action_config: Record<string, unknown>;
  }) {
    if (editingRule) {
      updateMut.mutate({ id: editingRule.id, data });
    } else {
      createMut.mutate(data);
    }
  }

  const statusList = statuses ?? [];
  const userList = users ?? [];
  const rules = automations ?? [];

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
        <span className="ml-3 text-surface-500">Loading automations...</span>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
        <p className="text-sm text-surface-500">Failed to load automation rules</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">Automation Rules</h3>
          <p className="text-xs text-surface-500 mt-0.5">
            Create rules that automatically perform actions when events occur.
          </p>
        </div>
        <button
          onClick={() => { setEditingRule(null); setShowModal(true); }}
          className="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors"
        >
          <Plus className="h-4 w-4" /> New Rule
        </button>
      </div>

      {/* Rules list */}
      {rules.length === 0 ? (
        <div className="card">
          <div className="flex flex-col items-center justify-center py-16">
            <Zap className="h-12 w-12 text-surface-300 dark:text-surface-600 mb-4" />
            <p className="text-sm font-medium text-surface-500 dark:text-surface-400">No automation rules yet</p>
            <p className="text-xs text-surface-400 dark:text-surface-500 mt-1 max-w-sm text-center">
              Create rules to automatically send SMS, change statuses, or assign tickets when events happen.
            </p>
            <button
              onClick={() => { setEditingRule(null); setShowModal(true); }}
              className="mt-4 inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium bg-primary-600 text-white rounded-lg hover:bg-primary-700 transition-colors"
            >
              <Plus className="h-4 w-4" /> Create First Rule
            </button>
          </div>
        </div>
      ) : (
        <div className="space-y-2">
          {rules.map((rule) => {
            const isExpanded = expandedId === rule.id;
            return (
              <div key={rule.id} className="card">
                {/* Rule summary row */}
                <div
                  className="flex items-center gap-3 px-4 py-3 cursor-pointer hover:bg-surface-50 dark:hover:bg-surface-800/30"
                  onClick={() => setExpandedId(isExpanded ? null : rule.id)}
                >
                  {/* Toggle */}
                  <div onClick={(e) => e.stopPropagation()}>
                    <ToggleSwitch
                      checked={!!rule.is_active}
                      onChange={() => toggleMut.mutate(rule.id)}
                      disabled={toggleMut.isPending}
                    />
                  </div>

                  {/* Info */}
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className={cn(
                        'font-medium text-sm',
                        rule.is_active ? 'text-surface-900 dark:text-surface-100' : 'text-surface-400'
                      )}>
                        {rule.name}
                      </span>
                      {!rule.is_active && (
                        <span className="text-[10px] uppercase font-semibold bg-surface-200 dark:bg-surface-700 text-surface-500 rounded px-1.5 py-0.5">
                          Disabled
                        </span>
                      )}
                    </div>
                    <p className="text-xs text-surface-500 mt-0.5">
                      <span className="font-medium">{triggerLabel(rule.trigger_type)}</span>
                      {triggerConfigSummary(rule.trigger_type, rule.trigger_config, statusList)}
                      <span className="mx-1 text-surface-400">-&gt;</span>
                      <span className="font-medium">{actionLabel(rule.action_type)}</span>
                    </p>
                  </div>

                  {/* Actions */}
                  <div className="flex items-center gap-1" onClick={(e) => e.stopPropagation()}>
                    <button
                      onClick={() => { setEditingRule(rule); setShowModal(true); }}
                      className="p-1.5 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400 hover:text-primary-500"
                      title="Edit rule"
                    >
                      <Zap className="h-4 w-4" />
                    </button>
                    <button
                      onClick={() => handleDelete(rule)}
                      className="p-1.5 rounded hover:bg-surface-100 dark:hover:bg-surface-700 text-surface-400 hover:text-red-500"
                      title="Delete rule"
                    >
                      <Trash2 className="h-4 w-4" />
                    </button>
                  </div>

                  {/* Expand chevron */}
                  {isExpanded ? (
                    <ChevronUp className="h-4 w-4 text-surface-400 shrink-0" />
                  ) : (
                    <ChevronDown className="h-4 w-4 text-surface-400 shrink-0" />
                  )}
                </div>

                {/* Expanded details */}
                {isExpanded && (
                  <div className="px-4 py-3 border-t border-surface-100 dark:border-surface-800 bg-surface-50 dark:bg-surface-800/20 text-xs space-y-2">
                    <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
                      <div>
                        <span className="text-surface-400 font-medium uppercase tracking-wider text-[10px]">Trigger</span>
                        <p className="text-surface-700 dark:text-surface-300 mt-0.5">
                          {triggerLabel(rule.trigger_type)}
                          {triggerConfigSummary(rule.trigger_type, rule.trigger_config, statusList)}
                        </p>
                      </div>
                      <div>
                        <span className="text-surface-400 font-medium uppercase tracking-wider text-[10px]">Action</span>
                        <p className="text-surface-700 dark:text-surface-300 mt-0.5">
                          {actionLabel(rule.action_type)}
                          {' - '}
                          {actionConfigSummary(rule.action_type, rule.action_config, statusList, userList)}
                        </p>
                      </div>
                    </div>
                    <div className="flex items-center justify-between pt-1">
                      <div className="text-surface-400">
                        Created: {new Date(rule.created_at.replace(' ', 'T')).toLocaleString()}
                        {rule.updated_at !== rule.created_at && (
                          <> | Updated: {new Date(rule.updated_at.replace(' ', 'T')).toLocaleString()}</>
                        )}
                      </div>
                      <button
                        onClick={(e) => { e.stopPropagation(); dryRunMut.mutate(rule.id); }}
                        disabled={dryRunMut.isPending && dryRunMut.variables === rule.id}
                        className="inline-flex items-center gap-1 px-2 py-1 rounded bg-surface-100 dark:bg-surface-700 text-surface-600 dark:text-surface-300 hover:bg-surface-200 dark:hover:bg-surface-600 disabled:opacity-40 text-[10px] font-medium"
                        title="Dry-run — check if this rule would fire (no side effects)"
                      >
                        <FlaskConical className="h-3 w-3" /> Dry-run
                      </button>
                    </div>
                  </div>
                )}
              </div>
            );
          })}
        </div>
      )}

      {/* Create/Edit Modal */}
      {showModal && (
        <AutomationModal
          rule={editingRule}
          statuses={statusList}
          users={userList}
          onClose={() => { setShowModal(false); setEditingRule(null); }}
          onSave={handleSave}
          saving={createMut.isPending || updateMut.isPending}
        />
      )}
    </div>
  );
}
