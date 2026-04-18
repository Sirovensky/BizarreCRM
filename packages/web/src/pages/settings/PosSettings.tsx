import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, AlertCircle } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

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

// ─── Section Header ──────────────────────────────────────────────────────────

function SectionHeader({ title }: { title: string }) {
  return (
    <h4 className="text-sm font-semibold text-primary-600 dark:text-primary-400 uppercase tracking-wide mt-6 mb-2">{title}</h4>
  );
}

// ─── Main Component ──────────────────────────────────────────────────────────

export function PosSettings() {
  const queryClient = useQueryClient();
  const [config, setConfig] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);

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
      toast.success('POS settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function toggle(key: string) {
    setConfig((prev) => ({ ...prev, [key]: prev[key] === '1' ? '0' : '1' }));
    setDirty(true);
  }

  function bool(key: string): boolean {
    return config[key] === '1';
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
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Point of Sale Configuration</h3>
        <button
          onClick={() => saveMutation.mutate(config)}
          disabled={!dirty || saveMutation.isPending}
          className={cn(
            'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
            dirty
              ? 'bg-primary-600 text-white hover:bg-primary-700'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-400 cursor-not-allowed'
          )}
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      <div className="p-6">
        <SectionHeader title="Display Options" />
        <ToggleRow
          label="Display products tab"
          description="Show products tab in POS interface"
          value={bool('pos_show_products')}
          onChange={() => toggle('pos_show_products')}
        />
        <ToggleRow
          label="Display repairs tab"
          description="Show repairs tab in POS interface"
          value={bool('pos_show_repairs')}
          onChange={() => toggle('pos_show_repairs')}
        />
        <ToggleRow
          label="Display miscellaneous tab"
          description="Show miscellaneous tab in POS interface"
          value={bool('pos_show_miscellaneous')}
          onChange={() => toggle('pos_show_miscellaneous')}
        />
        <ToggleRow
          label="Display product bundles tab"
          description="Show product bundles tab in POS interface"
          value={bool('pos_show_bundles')}
          onChange={() => toggle('pos_show_bundles')}
        />
        <ToggleRow
          label="Display out-of-stock items"
          description="Show items that are currently out of stock"
          value={bool('pos_show_out_of_stock')}
          onChange={() => toggle('pos_show_out_of_stock')}
        />
        <ToggleRow
          label="Display invoice notes"
          description="Display invoice notes at checkout"
          value={bool('pos_show_invoice_notes')}
          onChange={() => toggle('pos_show_invoice_notes')}
        />
        <ToggleRow
          label="Display outstanding balance alert"
          description="Show alert when customer has an outstanding balance"
          value={bool('pos_show_outstanding_alert')}
          onChange={() => toggle('pos_show_outstanding_alert')}
        />
        <ToggleRow
          label="Display manufacturer/device images"
          description="Display images of manufacturers and devices"
          value={bool('pos_show_images')}
          onChange={() => toggle('pos_show_images')}
        />
        <ToggleRow
          label="Display discount reason"
          description="Display reason for discount field"
          value={bool('pos_show_discount_reason')}
          onChange={() => toggle('pos_show_discount_reason')}
        />
        <ToggleRow
          label="Display cost price"
          description="Display cost price on POS screen"
          value={bool('pos_show_cost_price')}
          onChange={() => toggle('pos_show_cost_price')}
        />

        <SectionHeader title="Quick Check-In" />
        <div className="py-4 border-b border-surface-100 dark:border-surface-800">
          <p className="text-sm font-medium text-surface-900 dark:text-surface-100 mb-1">Default device category</p>
          <p className="text-xs text-surface-500 dark:text-surface-400 mb-2">Pre-select this category when starting a new check-in</p>
          <select
            value={config['checkin_default_category'] || ''}
            onChange={(e) => { setConfig(prev => ({ ...prev, checkin_default_category: e.target.value })); setDirty(true); }}
            className="w-48 text-sm rounded-md border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 px-2 py-1.5"
          >
            <option value="">None (user picks)</option>
            <option value="phone">Phone</option>
            <option value="tablet">Tablet</option>
            <option value="laptop">Laptop</option>
            <option value="console">Console</option>
            <option value="tv">TV</option>
            <option value="desktop">Desktop</option>
            <option value="other">Other</option>
          </select>
        </div>
        <ToggleRow
          label="Auto-print label after check-in"
          description="Automatically open the print label dialog after creating a ticket from check-in"
          value={bool('checkin_auto_print_label')}
          onChange={() => toggle('checkin_auto_print_label')}
        />
        <ToggleRow
          label="Require customer before check-in"
          description="Customer must be selected or created before a repair ticket can be started"
          value={bool('repair_require_customer')}
          onChange={() => toggle('repair_require_customer')}
        />

        <SectionHeader title="Security & Requirements" />
        <ToggleRow
          label="Require PIN to complete sale"
          description="Require employee PIN verification to complete a sale"
          value={bool('pos_require_pin_sale')}
          onChange={() => toggle('pos_require_pin_sale')}
        />
        <ToggleRow
          label="Require PIN to create ticket"
          description="Require employee PIN verification to create a ticket"
          value={bool('pos_require_pin_ticket')}
          onChange={() => toggle('pos_require_pin_ticket')}
        />
        <ToggleRow
          label="Require referral source"
          description='Require "How did you hear about us?" on checkout'
          value={bool('pos_require_referral')}
          onChange={() => toggle('pos_require_referral')}
        />
      </div>
    </div>
  );
}
