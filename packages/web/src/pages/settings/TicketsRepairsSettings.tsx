import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { ComingSoonBadge } from './components/ComingSoonBadge';

type SubTab = 'tickets' | 'repairs';

// ─── Toggle Row ──────────────────────────────────────────────────────────────

function ToggleRow({ label, description, value, onChange }: {
  label: string;
  description: string;
  value: boolean;
  onChange: (v: boolean) => void;
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800">
      <div>
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <button
        onClick={() => onChange(!value)}
        className={cn(
          'relative inline-flex h-6 w-11 rounded-full transition-colors flex-shrink-0',
          value ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600'
        )}
      >
        <span className={cn(
          'inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform mt-0.5',
          value ? 'translate-x-5 ml-0.5' : 'translate-x-0.5'
        )} />
      </button>
    </div>
  );
}

// ─── Select Row ──────────────────────────────────────────────────────────────

function SelectRow({ label, description, value, options, onChange, comingSoon = false }: {
  label: string;
  description: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (v: string) => void;
  comingSoon?: boolean;
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800">
      <div>
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
          {comingSoon && <ComingSoonBadge status="coming_soon" compact />}
        </div>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        disabled={comingSoon}
        className="px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
    </div>
  );
}

// ─── Number + Select Row ─────────────────────────────────────────────────────

function NumberSelectRow({ label, description, numValue, selectValue, selectOptions, onNumChange, onSelectChange }: {
  label: string;
  description: string;
  numValue: string;
  selectValue: string;
  selectOptions: { value: string; label: string }[];
  onNumChange: (v: string) => void;
  onSelectChange: (v: string) => void;
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800">
      <div>
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <div className="flex items-center gap-2">
        <input
          type="number"
          min="0"
          value={numValue}
          onChange={(e) => onNumChange(e.target.value)}
          className="w-20 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
        />
        <select
          value={selectValue}
          onChange={(e) => onSelectChange(e.target.value)}
          className="px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
        >
          {selectOptions.map((o) => (
            <option key={o.value} value={o.value}>{o.label}</option>
          ))}
        </select>
      </div>
    </div>
  );
}

// ─── Section Header ──────────────────────────────────────────────────────────

function SectionHeader({ title }: { title: string }) {
  return (
    <h4 className="text-sm font-semibold text-primary-600 dark:text-primary-400 uppercase tracking-wide mt-6 mb-2">{title}</h4>
  );
}

// ─── Input Row ──────────────────────────────────────────────────────────────

function InputRow({ label, description, value, onChange }: {
  label: string;
  description: string;
  value: string;
  onChange: (v: string) => void;
}) {
  return (
    <div className="py-4 border-b border-surface-100 dark:border-surface-800">
      <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
      <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5 mb-2">{description}</p>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        rows={2}
        className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-none"
      />
    </div>
  );
}

// ─── Main Component ──────────────────────────────────────────────────────────

export function TicketsRepairsSettings() {
  const queryClient = useQueryClient();
  const [config, setConfig] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);
  const [subTab, setSubTab] = useState<SubTab>('tickets');

  const { data, isLoading, isError } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
  });

  useEffect(() => {
    if (data) {
      setConfig(data);
      setDirty(false);
    }
  }, [data]);

  const saveMutation = useMutation({
    mutationFn: (d: Record<string, string>) => settingsApi.updateConfig(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      setDirty(false);
      toast.success('Settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function set(key: string, value: string) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
  }

  function toggle(key: string) {
    set(key, config[key] === '1' ? '0' : '1');
  }

  function bool(key: string): boolean {
    return config[key] === '1';
  }

  function val(key: string, fallback = ''): string {
    return config[key] ?? fallback;
  }

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-20">
        <Loader2 className="h-8 w-8 animate-spin text-primary-500" />
        <span className="ml-3 text-surface-500">Loading...</span>
      </div>
    );
  }
  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center py-20">
        <AlertCircle className="h-10 w-10 text-red-400 mb-3" />
        <p className="text-sm text-surface-500">Failed to load settings</p>
      </div>
    );
  }

  return (
    <div className="card">
      {/* Header */}
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <button
            onClick={() => setSubTab('tickets')}
            className={cn(
              'px-3 py-1.5 text-sm font-medium rounded-md transition-colors',
              subTab === 'tickets'
                ? 'bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
            )}
          >
            Tickets
          </button>
          <button
            onClick={() => setSubTab('repairs')}
            className={cn(
              'px-3 py-1.5 text-sm font-medium rounded-md transition-colors',
              subTab === 'repairs'
                ? 'bg-primary-100 dark:bg-primary-900/30 text-primary-700 dark:text-primary-300'
                : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
            )}
          >
            Repairs
          </button>
        </div>
        <button
          onClick={() => saveMutation.mutate(config)}
          disabled={!dirty || saveMutation.isPending}
          className={cn(
            'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
            dirty
              ? 'bg-primary-600 text-primary-950 hover:bg-primary-700'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-400 cursor-not-allowed'
          )}
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      {/* Content */}
      <div className="p-6">
        {subTab === 'tickets' && (
          <>
            <SectionHeader title="Interface & Display" />
            <ToggleRow
              label="Display inventory section"
              description="Display inventory section in ticket interface"
              value={bool('ticket_show_inventory')}
              onChange={() => toggle('ticket_show_inventory')}
            />
            <ToggleRow
              label="Display closed/cancelled tickets"
              description="Display closed and cancelled tickets on listing"
              value={bool('ticket_show_closed')}
              onChange={() => toggle('ticket_show_closed')}
            />
            <ToggleRow
              label="Display empty tickets"
              description="Display empty tickets on Manage Tickets"
              value={bool('ticket_show_empty')}
              onChange={() => toggle('ticket_show_empty')}
            />
            <ToggleRow
              label="Display parts column"
              description="Display parts field on Manage Tickets"
              value={bool('ticket_show_parts_column')}
              onChange={() => toggle('ticket_show_parts_column')}
            />

            <SectionHeader title="Rules & Permissions" />
            <ToggleRow
              label="Allow editing closed tickets"
              description="Allow employees to update closed tickets"
              value={bool('ticket_allow_edit_closed')}
              onChange={() => toggle('ticket_allow_edit_closed')}
            />
            <ToggleRow
              label="Allow ticket deletion after invoice"
              description="Allow ticket deletion after invoice has been created"
              value={bool('ticket_allow_delete_after_invoice')}
              onChange={() => toggle('ticket_allow_delete_after_invoice')}
            />
            <ToggleRow
              label="Allow ticket editing after invoice"
              description="Allow ticket editing after invoice has been created"
              value={bool('ticket_allow_edit_after_invoice')}
              onChange={() => toggle('ticket_allow_edit_after_invoice')}
            />
            <ToggleRow
              label="Auto-close ticket on invoice"
              description="Auto-close ticket after invoice creation"
              value={bool('ticket_auto_close_on_invoice')}
              onChange={() => toggle('ticket_auto_close_on_invoice')}
            />
            <ToggleRow
              label="All employees view all tickets"
              description="Allow all employees to view all tickets"
              value={bool('ticket_all_employees_view_all')}
              onChange={() => toggle('ticket_all_employees_view_all')}
            />
            <ToggleRow
              label="Require repair stopwatch"
              description="Require use of repair time stopwatch"
              value={bool('ticket_require_stopwatch')}
              onChange={() => toggle('ticket_require_stopwatch')}
            />
            <SelectRow
              label="Auto-start timer on status"
              description="Automatically start repair timer when ticket enters this status"
              value={val('ticket_timer_auto_start_status', '')}
              options={[
                { value: '', label: 'Disabled' },
                { value: 'in_progress', label: 'In Progress' },
              ]}
              onChange={(v) => set('ticket_timer_auto_start_status', v)}
            />
            <SelectRow
              label="Auto-stop timer on status"
              description="Automatically stop repair timer when ticket enters this status"
              value={val('ticket_timer_auto_stop_status', '')}
              options={[
                { value: '', label: 'Disabled' },
                { value: 'closed', label: 'Closed' },
                { value: 'waiting_on_customer', label: 'Waiting on Customer' },
                { value: 'waiting_for_parts', label: 'Waiting for Parts' },
              ]}
              onChange={(v) => set('ticket_timer_auto_stop_status', v)}
            />
            <ToggleRow
              label="Auto-update status on reply"
              description="Auto-update status when customer replies"
              value={bool('ticket_auto_status_on_reply')}
              onChange={() => toggle('ticket_auto_status_on_reply')}
            />
            <ToggleRow
              label="Auto-remove passcode on close"
              description="Auto-remove passcode when ticket is closed"
              value={bool('ticket_auto_remove_passcode')}
              onChange={() => toggle('ticket_auto_remove_passcode')}
            />
            <ToggleRow
              label="Copy notes to warranty ticket"
              description="Copy original ticket notes when creating a warranty repair"
              value={bool('ticket_copy_warranty_notes')}
              onChange={() => toggle('ticket_copy_warranty_notes')}
            />
            <SelectRow
              label="Default Assignment"
              description="How new tickets are assigned by default"
              value={val('ticket_default_assignment', 'default')}
              options={[
                { value: 'default', label: 'Default (Creator)' },
                { value: 'unassigned', label: 'Unassigned' },
                { value: 'pin_based', label: 'Based on PIN' },
              ]}
              onChange={(v) => set('ticket_default_assignment', v)}
            />

            <SectionHeader title="Defaults" />
            <SelectRow
              label="Default View"
              description="Default ticket listing view"
              value={val('ticket_default_view', 'listing')}
              options={[
                { value: 'listing', label: 'Listing' },
                { value: 'calendar', label: 'Calendar' },
              ]}
              onChange={(v) => set('ticket_default_view', v)}
            />
            <SelectRow
              label="Default Date Filter"
              description="Default date filter on ticket listing"
              value={val('ticket_default_filter', 'all')}
              options={[
                { value: 'all', label: 'All' },
                { value: 'today', label: 'Today' },
                { value: '7days', label: '7 Days' },
                { value: '14days', label: '14 Days' },
                { value: '30days', label: '30 Days' },
              ]}
              onChange={(v) => set('ticket_default_filter', v)}
            />
            <SelectRow
              label="Default Date Sort"
              description="Default date sorting column"
              value={val('ticket_default_date_sort', 'created')}
              options={[
                { value: 'created', label: 'Created Date' },
                { value: 'due', label: 'Due Date' },
              ]}
              onChange={(v) => set('ticket_default_date_sort', v)}
              comingSoon
            />
            <SelectRow
              label="Default Pagination"
              description="Number of tickets per page"
              value={val('ticket_default_pagination', '25')}
              options={[
                { value: '25', label: '25' },
                { value: '50', label: '50' },
                { value: '100', label: '100' },
              ]}
              onChange={(v) => set('ticket_default_pagination', v)}
            />
            <SelectRow
              label="Default Sort Order"
              description="Default sort order on ticket listing"
              value={val('ticket_default_sort_order', 'due_date')}
              options={[
                { value: 'due_date', label: 'By Due Date' },
                { value: 'created_date', label: 'By Created Date' },
                { value: 'ticket_number', label: 'By Ticket Number' },
              ]}
              onChange={(v) => set('ticket_default_sort_order', v)}
              comingSoon
            />
            <SelectRow
              label="Status after estimate creation"
              description="Automatically set ticket to this status after an estimate is created"
              value={val('ticket_status_after_estimate', '')}
              options={[
                { value: '', label: 'No change' },
                { value: 'waiting_on_customer', label: 'Waiting on Customer' },
                { value: 'on_hold', label: 'On Hold' },
              ]}
              onChange={(v) => set('ticket_status_after_estimate', v)}
            />

            <SectionHeader title="Label Templates" />
            <SelectRow
              label="Ticket Label Template"
              description="Template used for printing ticket labels"
              value={val('ticket_label_template', 'default')}
              options={[
                { value: 'default', label: 'Default' },
                { value: 'professional', label: 'Professional' },
                { value: 'compact', label: 'Compact' },
                { value: 'barcode', label: 'Barcode Only' },
              ]}
              onChange={(v) => set('ticket_label_template', v)}
            />

            <SectionHeader title="Customer Feedback" />
            <ToggleRow
              label="Enable feedback requests"
              description="Send feedback/review request to customer after ticket is closed"
              value={bool('feedback_enabled')}
              onChange={() => toggle('feedback_enabled')}
            />
            <ToggleRow
              label="Auto-send feedback SMS"
              description="Automatically send an SMS asking for feedback when a ticket is closed"
              value={bool('feedback_auto_sms')}
              onChange={() => toggle('feedback_auto_sms')}
            />
            <InputRow
              label="Feedback SMS template"
              description="Message sent to customer. Use {customer_name}, {ticket_id}, {device_name}"
              value={val('feedback_sms_template', 'Hi {customer_name}, how was your repair experience for {device_name}? Reply 1-5 (1=poor, 5=excellent). Thank you!')}
              onChange={(v) => set('feedback_sms_template', v)}
            />
            <SelectRow
              label="Feedback delay"
              description="How long after ticket close to send the feedback request"
              value={val('feedback_delay_hours', '24')}
              options={[
                { value: '0', label: 'Immediately' },
                { value: '1', label: '1 hour' },
                { value: '24', label: '24 hours' },
                { value: '48', label: '48 hours' },
                { value: '72', label: '72 hours' },
              ]}
              onChange={(v) => set('feedback_delay_hours', v)}
            />
          </>
        )}

        {subTab === 'repairs' && (
          <>
            <SectionHeader title="Workflow" />
            <ToggleRow
              label="Require pre-repair condition check"
              description="Require pre-repair device condition check before starting"
              value={bool('repair_require_pre_condition')}
              onChange={() => toggle('repair_require_pre_condition')}
            />
            <ToggleRow
              label="Require post-repair condition check"
              description="Require post-repair device condition check before closing"
              value={bool('repair_require_post_condition')}
              onChange={() => toggle('repair_require_post_condition')}
            />
            <ToggleRow
              label="Require part entry"
              description="Require part entry before marking repair complete"
              value={bool('repair_require_parts')}
              onChange={() => toggle('repair_require_parts')}
            />
            <ToggleRow
              label="Require customer information"
              description="Require customer information on every repair ticket"
              value={bool('repair_require_customer')}
              onChange={() => toggle('repair_require_customer')}
            />
            <ToggleRow
              label="Require diagnostic notes"
              description="Require diagnostic notes before status change"
              value={bool('repair_require_diagnostic')}
              onChange={() => toggle('repair_require_diagnostic')}
            />
            <ToggleRow
              label="Require device IMEI/Serial"
              description="Require device IMEI or serial number entry"
              value={bool('repair_require_imei')}
              onChange={() => toggle('repair_require_imei')}
            />
            <ToggleRow
              label="Itemize line items"
              description="Itemize each repair as separate line item"
              value={bool('repair_itemize_line_items')}
              onChange={() => toggle('repair_itemize_line_items')}
            />
            <ToggleRow
              label="Price includes parts"
              description="Calculate service price as sum of parts + labor"
              value={bool('repair_price_includes_parts')}
              onChange={() => toggle('repair_price_includes_parts')}
            />

            <SectionHeader title="Defaults" />
            <NumberSelectRow
              label="Default Warranty"
              description="Default warranty period for repairs"
              numValue={val('repair_default_warranty_value', '90')}
              selectValue={val('repair_default_warranty_unit', 'days')}
              selectOptions={[
                { value: 'days', label: 'Days' },
                { value: 'months', label: 'Months' },
                { value: 'years', label: 'Years' },
              ]}
              onNumChange={(v) => set('repair_default_warranty_value', v)}
              onSelectChange={(v) => set('repair_default_warranty_unit', v)}
            />
            <SelectRow
              label="Default Input Criteria"
              description="Default identifier type for devices"
              value={val('repair_default_input_criteria', 'imei')}
              options={[
                { value: 'imei', label: 'IMEI' },
                { value: 'serial', label: 'Serial' },
              ]}
              onChange={(v) => set('repair_default_input_criteria', v)}
            />
            <NumberSelectRow
              label="Default Due Date"
              description="Default due date offset for new tickets"
              numValue={val('repair_default_due_value', '3')}
              selectValue={val('repair_default_due_unit', 'days')}
              selectOptions={[
                { value: 'minutes', label: 'Minutes' },
                { value: 'hours', label: 'Hours' },
                { value: 'days', label: 'Days' },
              ]}
              onNumChange={(v) => set('repair_default_due_value', v)}
              onSelectChange={(v) => set('repair_default_due_unit', v)}
            />
          </>
        )}
      </div>
    </div>
  );
}
