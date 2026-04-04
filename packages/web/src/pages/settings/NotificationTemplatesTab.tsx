import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Loader2, AlertCircle, X, Save, Mail, MessageSquare, Info } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

// ─── Types ───────────────────────────────────────────────────────────────────

interface NotificationTemplate {
  id: number;
  event_key: string;
  event_label: string;
  category: string;
  subject: string;
  email_body: string;
  sms_body: string;
  send_email_auto: number;
  send_sms_auto: number;
  is_active: number;
}

const TEMPLATE_VARIABLES = [
  { key: '{customer_name}', desc: 'Customer full name' },
  { key: '{ticket_id}', desc: 'Ticket ID (e.g. T-0042)' },
  { key: '{device_name}', desc: 'Device being repaired' },
  { key: '{store_name}', desc: 'Store name' },
  { key: '{store_phone}', desc: 'Store phone number' },
];

// ─── Edit Modal ──────────────────────────────────────────────────────────────

function EditTemplateModal({
  template,
  onClose,
  onSave,
  saving,
}: {
  template: NotificationTemplate;
  onClose: () => void;
  onSave: (data: Partial<NotificationTemplate>) => void;
  saving: boolean;
}) {
  const [subject, setSubject] = useState(template.subject);
  const [emailBody, setEmailBody] = useState(template.email_body);
  const [smsBody, setSmsBody] = useState(template.sms_body);

  function handleSave() {
    onSave({ subject, email_body: emailBody, sms_body: smsBody });
  }

  return (
    <div className="fixed inset-0 bg-black/50 z-50 flex items-center justify-center p-4">
      <div className="bg-white dark:bg-surface-900 rounded-xl shadow-2xl w-full max-w-2xl max-h-[90vh] overflow-y-auto">
        {/* Header */}
        <div className="flex items-center justify-between p-5 border-b border-surface-200 dark:border-surface-700">
          <div>
            <h3 className="text-lg font-semibold text-surface-900 dark:text-surface-100">
              Edit Template
            </h3>
            <p className="text-sm text-surface-500 mt-0.5">{template.event_label}</p>
          </div>
          <button onClick={onClose} className="p-1.5 rounded-lg hover:bg-surface-100 dark:hover:bg-surface-800 text-surface-400">
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Body */}
        <div className="p-5 space-y-5">
          {/* Variable chips */}
          <div>
            <p className="text-xs font-medium text-surface-500 mb-2 uppercase tracking-wider">Available Variables</p>
            <div className="flex flex-wrap gap-1.5">
              {TEMPLATE_VARIABLES.map((v) => (
                <span
                  key={v.key}
                  title={v.desc}
                  className="inline-flex items-center gap-1 rounded-md bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300 px-2 py-1 text-xs font-mono cursor-help"
                >
                  {v.key}
                  <Info className="h-3 w-3 text-blue-400" />
                </span>
              ))}
            </div>
          </div>

          {/* Subject */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">
              <Mail className="h-3.5 w-3.5 inline mr-1" />
              Email Subject
            </label>
            <input
              type="text"
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              placeholder="Email subject line..."
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          {/* Email Body */}
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">
              Email Body
            </label>
            <textarea
              value={emailBody}
              onChange={(e) => setEmailBody(e.target.value)}
              placeholder="Email body content (supports HTML)..."
              rows={5}
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500 font-mono"
            />
          </div>

          {/* SMS Body */}
          <div>
            <div className="flex items-center justify-between mb-1.5">
              <label className="text-sm font-medium text-surface-700 dark:text-surface-300">
                <MessageSquare className="h-3.5 w-3.5 inline mr-1" />
                SMS Body
              </label>
              <span className={cn(
                'text-xs font-mono',
                smsBody.length > 160 ? 'text-red-500' : 'text-surface-400'
              )}>
                {smsBody.length}/160
              </span>
            </div>
            <textarea
              value={smsBody}
              onChange={(e) => setSmsBody(e.target.value)}
              placeholder="SMS message content..."
              rows={3}
              className="w-full rounded-lg border border-surface-200 bg-white px-3 py-2 text-sm text-surface-900 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
            {smsBody.length > 160 && (
              <p className="text-xs text-amber-600 mt-1">
                Message exceeds 160 characters and may be split into multiple SMS segments.
              </p>
            )}
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
            disabled={saving}
            className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-lg hover:bg-blue-700 transition-colors disabled:opacity-50"
          >
            {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
            Save Template
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Toggle Switch ───────────────────────────────────────────────────────────

function ToggleSwitch({ checked, onChange, disabled }: { checked: boolean; onChange: (v: boolean) => void; disabled?: boolean }) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={checked}
      onClick={() => onChange(!checked)}
      disabled={disabled}
      className={cn(
        'relative inline-flex h-5 w-9 items-center rounded-full transition-colors focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-1',
        checked ? 'bg-blue-600' : 'bg-surface-300 dark:bg-surface-600',
        disabled && 'opacity-50 cursor-not-allowed'
      )}
    >
      <span
        className={cn(
          'inline-block h-3.5 w-3.5 rounded-full bg-white transition-transform',
          checked ? 'translate-x-4.5' : 'translate-x-0.5'
        )}
        style={{ transform: checked ? 'translateX(18px)' : 'translateX(2px)' }}
      />
    </button>
  );
}

// ─── Main Component ──────────────────────────────────────────────────────────

export function NotificationTemplatesTab() {
  const queryClient = useQueryClient();
  const [subTab, setSubTab] = useState<'customer' | 'internal'>('customer');
  const [editTemplate, setEditTemplate] = useState<NotificationTemplate | null>(null);

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'notification-templates'],
    queryFn: async () => {
      const res = await settingsApi.getNotificationTemplates();
      return (res.data.data?.templates || res.data.data || []) as NotificationTemplate[];
    },
  });

  const updateMut = useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<NotificationTemplate> }) =>
      settingsApi.updateNotificationTemplate(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'notification-templates'] });
      toast.success('Template updated');
      setEditTemplate(null);
    },
    onError: () => toast.error('Failed to update template'),
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
        <span className="ml-3 text-surface-500">Loading templates...</span>
      </div>
    );
  }

  if (isError || !data) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
        <p className="text-sm text-surface-500">Failed to load notification templates</p>
      </div>
    );
  }

  const filtered = data.filter((t) => subTab === 'customer' ? t.category === 'customer' : t.category === 'internal');

  function handleToggle(template: NotificationTemplate, field: 'send_email_auto' | 'send_sms_auto', value: boolean) {
    updateMut.mutate({ id: template.id, data: { [field]: value ? 1 : 0 } });
  }

  return (
    <div>
      {/* Sub-tabs */}
      <div className="flex gap-1 bg-surface-100 dark:bg-surface-800 rounded-lg p-1 mb-6 w-fit">
        {([
          { key: 'customer' as const, label: 'Customers' },
          { key: 'internal' as const, label: 'In-House' },
        ]).map((tab) => (
          <button
            key={tab.key}
            onClick={() => setSubTab(tab.key)}
            className={cn(
              'px-4 py-2 text-sm font-medium rounded-md transition-colors',
              subTab === tab.key
                ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
            )}
          >
            {tab.label}
          </button>
        ))}
      </div>

      {/* Template Table */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">
            {subTab === 'customer' ? 'Customer Notifications' : 'In-House Notifications'}
          </h3>
          <p className="text-xs text-surface-500 mt-1">
            Configure automatic email and SMS notifications for each event.
          </p>
        </div>

        {filtered.length === 0 ? (
          <div className="flex flex-col items-center justify-center py-12">
            <p className="text-sm text-surface-400">No templates in this category</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-surface-100 dark:border-surface-800">
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Event</th>
                  <th className="text-center px-4 py-3 font-medium text-surface-500 w-24">
                    <div className="flex items-center justify-center gap-1">
                      <Mail className="h-3.5 w-3.5" /> Email
                    </div>
                  </th>
                  <th className="text-center px-4 py-3 font-medium text-surface-500 w-24">
                    <div className="flex items-center justify-center gap-1">
                      <MessageSquare className="h-3.5 w-3.5" /> SMS
                    </div>
                  </th>
                  <th className="text-center px-4 py-3 font-medium text-surface-500 w-24">
                    <div className="flex items-center justify-center gap-1 text-xs">Canned</div>
                  </th>
                  <th className="text-left px-4 py-3 font-medium text-surface-500">Subject</th>
                  <th className="text-right px-4 py-3 font-medium text-surface-500 w-24">Action</th>
                </tr>
              </thead>
              <tbody>
                {filtered.map((t) => (
                  <tr key={t.id} className="border-b border-surface-50 dark:border-surface-800/50 hover:bg-surface-50 dark:hover:bg-surface-800/30">
                    <td className="px-4 py-3">
                      <p className="font-medium text-surface-900 dark:text-surface-100">{t.event_label}</p>
                      <p className="text-xs text-surface-400 font-mono">{t.event_key}</p>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex justify-center">
                        <ToggleSwitch
                          checked={!!t.send_email_auto}
                          onChange={(v) => handleToggle(t, 'send_email_auto', v)}
                          disabled={updateMut.isPending}
                        />
                      </div>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex justify-center">
                        <ToggleSwitch
                          checked={!!t.send_sms_auto}
                          onChange={(v) => handleToggle(t, 'send_sms_auto', v)}
                          disabled={updateMut.isPending}
                        />
                      </div>
                    </td>
                    <td className="px-4 py-3 text-center">
                      <div className="flex justify-center">
                        <ToggleSwitch
                          checked={!!(t as any).show_in_canned}
                          onChange={(v) => handleToggle(t, 'show_in_canned' as any, v)}
                          disabled={updateMut.isPending}
                        />
                      </div>
                    </td>
                    <td className="px-4 py-3 text-surface-600 dark:text-surface-400 max-w-[250px] truncate">
                      {t.subject || <span className="text-surface-400 italic">No subject</span>}
                    </td>
                    <td className="px-4 py-3 text-right">
                      <button
                        onClick={() => setEditTemplate(t)}
                        className="text-xs text-primary-600 hover:text-primary-700 font-medium"
                      >
                        Edit
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Edit Modal */}
      {editTemplate && (
        <EditTemplateModal
          template={editTemplate}
          onClose={() => setEditTemplate(null)}
          onSave={(data) => updateMut.mutate({ id: editTemplate.id, data })}
          saving={updateMut.isPending}
        />
      )}
    </div>
  );
}
