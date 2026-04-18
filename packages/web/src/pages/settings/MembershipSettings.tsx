import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Save, Loader2, Plus, Trash2, Pencil, X, Check, Crown, AlertCircle,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi, membershipApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { confirm } from '@/stores/confirmStore';

// ─── Types ────────────────────────────────────────────────────────

interface MembershipTier {
  id: number;
  name: string;
  slug: string;
  monthly_price: number;
  discount_pct: number;
  discount_applies_to: 'labor' | 'all' | 'parts';
  benefits: string[];
  color: string;
  sort_order: number;
  is_active: number;
}

interface TierFormState {
  name: string;
  monthly_price: string;
  discount_pct: string;
  discount_applies_to: 'labor' | 'all' | 'parts';
  benefits: string[];
  color: string;
}

const EMPTY_FORM: TierFormState = {
  name: '',
  monthly_price: '',
  discount_pct: '',
  discount_applies_to: 'labor',
  benefits: [],
  color: '#3b82f6',
};

const APPLIES_TO_OPTIONS: { value: 'labor' | 'all' | 'parts'; label: string }[] = [
  { value: 'labor', label: 'Labor only' },
  { value: 'all', label: 'All (labor + parts)' },
  { value: 'parts', label: 'Parts only' },
];

const PRESET_COLORS = [
  '#3b82f6', '#60a5fa', '#a78bfa', '#8b5cf6',
  '#f59e0b', '#f97316', '#ef4444', '#10b981',
  '#14b8a6', '#ec4899', '#6366f1', '#78716c',
];

// ─── Toggle Component ─────────────────────────────────────────────

function Toggle({ checked, onChange, label, description }: {
  checked: boolean; onChange: (v: boolean) => void; label: string; description?: string;
}) {
  return (
    <label className="flex items-start gap-3 cursor-pointer">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={cn(
          'relative mt-0.5 inline-flex h-6 w-11 shrink-0 items-center rounded-full transition-colors',
          checked ? 'bg-primary-600' : 'bg-surface-300 dark:bg-surface-600',
        )}
      >
        <span className={cn(
          'inline-block h-4 w-4 rounded-full bg-white transition-transform shadow-sm',
          checked ? 'translate-x-6' : 'translate-x-1',
        )} />
      </button>
      <div>
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        {description && <p className="text-xs text-surface-400 mt-0.5">{description}</p>}
      </div>
    </label>
  );
}

// ─── Tier Card ──────────────────────────────────────────────────

function TierCard({ tier, onEdit, onDelete }: {
  tier: MembershipTier;
  onEdit: () => void;
  onDelete: () => void;
}) {
  return (
    <div className="rounded-xl border-2 overflow-hidden" style={{ borderColor: tier.color }}>
      <div className="px-5 py-4" style={{ backgroundColor: tier.color + '15' }}>
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Crown className="h-5 w-5" style={{ color: tier.color }} />
            <h4 className="text-lg font-bold text-surface-900 dark:text-surface-100">{tier.name}</h4>
          </div>
          <div className="flex items-center gap-1">
            <button
              aria-label="Edit"
              onClick={onEdit}
              className="rounded-lg p-1.5 text-surface-400 hover:text-surface-700 hover:bg-white/60 dark:hover:text-surface-200 dark:hover:bg-surface-800/60 transition-colors"
            >
              <Pencil className="h-4 w-4" />
            </button>
            <button
              aria-label="Delete"
              onClick={onDelete}
              className="rounded-lg p-1.5 text-surface-400 hover:text-red-600 hover:bg-white/60 dark:hover:text-red-400 dark:hover:bg-surface-800/60 transition-colors"
            >
              <Trash2 className="h-4 w-4" />
            </button>
          </div>
        </div>
        <div className="mt-2 flex items-baseline gap-1">
          <span className="text-3xl font-extrabold text-surface-900 dark:text-surface-100">
            ${tier.monthly_price.toFixed(2)}
          </span>
          <span className="text-sm text-surface-500">/month</span>
        </div>
        <div className="mt-1">
          <span
            className="inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold text-white"
            style={{ backgroundColor: tier.color }}
          >
            {tier.discount_pct}% off {tier.discount_applies_to}
          </span>
        </div>
      </div>
      {tier.benefits.length > 0 && (
        <div className="px-5 py-4 bg-white dark:bg-surface-900">
          <ul className="space-y-2">
            {tier.benefits.map((b, i) => (
              <li key={i} className="flex items-start gap-2 text-sm text-surface-700 dark:text-surface-300">
                <Check className="h-4 w-4 mt-0.5 shrink-0" style={{ color: tier.color }} />
                {b}
              </li>
            ))}
          </ul>
        </div>
      )}
    </div>
  );
}

// ─── Tier Form ──────────────────────────────────────────────────

function TierForm({ initial, onSave, onCancel, saving }: {
  initial: TierFormState;
  onSave: (data: TierFormState) => void;
  onCancel: () => void;
  saving: boolean;
}) {
  const [form, setForm] = useState<TierFormState>(initial);
  const [newBenefit, setNewBenefit] = useState('');

  function handleChange<K extends keyof TierFormState>(key: K, value: TierFormState[K]) {
    setForm((prev) => ({ ...prev, [key]: value }));
  }

  function addBenefit() {
    if (!newBenefit.trim()) return;
    handleChange('benefits', [...form.benefits, newBenefit.trim()]);
    setNewBenefit('');
  }

  function removeBenefit(idx: number) {
    handleChange('benefits', form.benefits.filter((_, i) => i !== idx));
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    if (!form.name.trim()) { toast.error('Tier name is required'); return; }
    if (!form.monthly_price || parseFloat(form.monthly_price) <= 0) { toast.error('Price must be greater than 0'); return; }
    onSave(form);
  }

  return (
    <form onSubmit={handleSubmit} className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">
          {initial.name ? 'Edit Tier' : 'New Membership Tier'}
        </h3>
        <button aria-label="Close" type="button" onClick={onCancel} className="rounded-lg p-1.5 text-surface-400 hover:bg-surface-100 dark:hover:bg-surface-800">
          <X className="h-4 w-4" />
        </button>
      </div>

      <div className="p-5 space-y-4">
        {/* Name & Price */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Name</label>
            <input
              value={form.name}
              onChange={(e) => handleChange('name', e.target.value)}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
              placeholder="e.g. VIP"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Monthly Price ($)</label>
            <input
              type="number"
              step="0.01"
              min="0"
              value={form.monthly_price}
              onChange={(e) => handleChange('monthly_price', e.target.value)}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
              placeholder="29.99"
            />
          </div>
        </div>

        {/* Discount & Applies To */}
        <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Discount %</label>
            <input
              type="number"
              step="1"
              min="0"
              max="100"
              value={form.discount_pct}
              onChange={(e) => handleChange('discount_pct', e.target.value)}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
              placeholder="10"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Applies To</label>
            <select
              value={form.discount_applies_to}
              onChange={(e) => handleChange('discount_applies_to', e.target.value as 'labor' | 'all' | 'parts')}
              className="w-full rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
            >
              {APPLIES_TO_OPTIONS.map((o) => (
                <option key={o.value} value={o.value}>{o.label}</option>
              ))}
            </select>
          </div>
        </div>

        {/* Color Picker */}
        <div>
          <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">Tier Color</label>
          <div className="flex flex-wrap items-center gap-2">
            {PRESET_COLORS.map((c) => (
              <button
                key={c}
                type="button"
                onClick={() => handleChange('color', c)}
                className={cn(
                  'h-7 w-7 rounded-full border-2 transition-all',
                  form.color === c ? 'border-surface-900 dark:border-white scale-110' : 'border-transparent hover:scale-105',
                )}
                style={{ backgroundColor: c }}
              />
            ))}
            <input
              type="color"
              value={form.color}
              onChange={(e) => handleChange('color', e.target.value)}
              className="h-7 w-7 rounded-full cursor-pointer border border-surface-200 dark:border-surface-700"
            />
          </div>
        </div>

        {/* Benefits */}
        <div>
          <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1.5">Benefits</label>
          <div className="flex gap-2 mb-2">
            <input
              value={newBenefit}
              onChange={(e) => setNewBenefit(e.target.value)}
              onKeyDown={(e) => { if (e.key === 'Enter') { e.preventDefault(); addBenefit(); } }}
              className="flex-1 rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-primary-500"
              placeholder="Add a benefit..."
            />
            <button
              aria-label="Add benefit"
              type="button"
              onClick={addBenefit}
              disabled={!newBenefit.trim()}
              className="px-3 py-2 text-sm bg-primary-600 text-white rounded-lg hover:bg-primary-700 disabled:opacity-50 transition-colors"
            >
              <Plus className="h-4 w-4" />
            </button>
          </div>
          {form.benefits.length > 0 && (
            <div className="space-y-1.5">
              {form.benefits.map((b, i) => (
                <div key={i} className="flex items-center gap-2 rounded-lg bg-surface-50 dark:bg-surface-800 px-3 py-2 text-sm">
                  <Check className="h-4 w-4 text-green-500 shrink-0" />
                  <span className="flex-1 text-surface-700 dark:text-surface-300">{b}</span>
                  <button
                    aria-label="Remove benefit"
                    type="button"
                    onClick={() => removeBenefit(i)}
                    className="text-surface-400 hover:text-red-500 transition-colors"
                  >
                    <X className="h-3.5 w-3.5" />
                  </button>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>

      {/* Footer */}
      <div className="p-4 border-t border-surface-100 dark:border-surface-800 flex items-center justify-end gap-2">
        <button
          type="button"
          onClick={onCancel}
          className="px-4 py-2 text-sm font-medium text-surface-600 dark:text-surface-300 border border-surface-200 dark:border-surface-700 rounded-lg hover:bg-surface-50 dark:hover:bg-surface-800 transition-colors"
        >
          Cancel
        </button>
        <button
          type="submit"
          disabled={saving}
          className="inline-flex items-center gap-2 px-4 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 disabled:opacity-50 transition-colors"
        >
          {saving ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          {initial.name ? 'Update Tier' : 'Create Tier'}
        </button>
      </div>
    </form>
  );
}

// ─── Main Component ──────────────────────────────────────────────

export function MembershipSettings() {
  const queryClient = useQueryClient();
  const [showForm, setShowForm] = useState(false);
  const [editingTier, setEditingTier] = useState<MembershipTier | null>(null);

  // Fetch membership_enabled config
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => {
      const res = await settingsApi.getConfig();
      return res.data.data as Record<string, string>;
    },
  });

  const membershipEnabled = configData?.['membership_enabled'] === 'true';

  const toggleMutation = useMutation({
    mutationFn: (enabled: boolean) =>
      settingsApi.updateConfig({ membership_enabled: enabled ? 'true' : 'false' }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      toast.success('Membership settings updated');
    },
    onError: () => toast.error('Failed to update setting'),
  });

  // Fetch tiers
  const { data: tiersData, isLoading } = useQuery({
    queryKey: ['membership', 'tiers'],
    queryFn: async () => {
      const res = await membershipApi.getTiers();
      return res.data.data as MembershipTier[];
    },
  });
  const tiers = tiersData || [];

  // Create tier
  const createMutation = useMutation({
    mutationFn: (data: TierFormState) =>
      membershipApi.createTier({
        name: data.name,
        monthly_price: parseFloat(data.monthly_price),
        discount_pct: parseFloat(data.discount_pct) || 0,
        discount_applies_to: data.discount_applies_to,
        benefits: data.benefits,
        color: data.color,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'tiers'] });
      setShowForm(false);
      toast.success('Tier created');
    },
    onError: () => toast.error('Failed to create tier'),
  });

  // Update tier
  const updateMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: TierFormState }) =>
      membershipApi.updateTier(id, {
        name: data.name,
        monthly_price: parseFloat(data.monthly_price),
        discount_pct: parseFloat(data.discount_pct) || 0,
        discount_applies_to: data.discount_applies_to,
        benefits: data.benefits,
        color: data.color,
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'tiers'] });
      setEditingTier(null);
      setShowForm(false);
      toast.success('Tier updated');
    },
    onError: () => toast.error('Failed to update tier'),
  });

  // Delete tier
  const deleteMutation = useMutation({
    mutationFn: (id: number) => membershipApi.deleteTier(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['membership', 'tiers'] });
      toast.success('Tier deactivated');
    },
    onError: () => toast.error('Failed to deactivate tier'),
  });

  function handleEdit(tier: MembershipTier) {
    setEditingTier(tier);
    setShowForm(true);
  }

  async function handleDelete(tier: MembershipTier) {
    const ok = await confirm(
      `Deactivate "${tier.name}"? Existing subscribers will keep their membership until cancellation.`,
      { title: 'Deactivate Tier', confirmLabel: 'Deactivate', danger: true },
    );
    if (ok) deleteMutation.mutate(tier.id);
  }

  function handleSave(data: TierFormState) {
    if (editingTier) {
      updateMutation.mutate({ id: editingTier.id, data });
    } else {
      createMutation.mutate(data);
    }
  }

  const formInitial: TierFormState = editingTier
    ? {
        name: editingTier.name,
        monthly_price: editingTier.monthly_price.toString(),
        discount_pct: editingTier.discount_pct.toString(),
        discount_applies_to: editingTier.discount_applies_to,
        benefits: editingTier.benefits,
        color: editingTier.color,
      }
    : EMPTY_FORM;

  return (
    <div className="space-y-6">
      {/* Enable toggle */}
      <div className="card">
        <div className="p-5">
          <Toggle
            checked={membershipEnabled}
            onChange={(v) => toggleMutation.mutate(v)}
            label="Enable Membership System"
            description="Allow customers to subscribe to membership tiers for recurring discounts and perks."
          />
        </div>
      </div>

      {/* Tier management */}
      <div className="card">
        <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
          <div>
            <h3 className="font-semibold text-surface-900 dark:text-surface-100">Membership Tiers</h3>
            <p className="text-xs text-surface-400 mt-0.5">Define the plans customers can subscribe to.</p>
          </div>
          {!showForm && (
            <button
              onClick={() => { setEditingTier(null); setShowForm(true); }}
              className="inline-flex items-center gap-2 px-3 py-2 text-sm font-medium text-white bg-primary-600 rounded-lg hover:bg-primary-700 transition-colors"
            >
              <Plus className="h-4 w-4" />
              Add Tier
            </button>
          )}
        </div>

        {isLoading && (
          <div className="flex items-center justify-center py-12">
            <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
          </div>
        )}

        {!isLoading && tiers.length === 0 && !showForm && (
          <div className="flex flex-col items-center justify-center py-12 px-4">
            <Crown className="h-10 w-10 text-surface-300 dark:text-surface-600 mb-3" />
            <p className="text-sm text-surface-500 dark:text-surface-400 mb-1">No membership tiers yet</p>
            <p className="text-xs text-surface-400">Create your first tier to get started.</p>
          </div>
        )}

        {!isLoading && tiers.length > 0 && (
          <div className="p-5 grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {tiers.map((tier) => (
              <TierCard
                key={tier.id}
                tier={tier}
                onEdit={() => handleEdit(tier)}
                onDelete={() => handleDelete(tier)}
              />
            ))}
          </div>
        )}
      </div>

      {/* Form */}
      {showForm && (
        <TierForm
          initial={formInitial}
          onSave={handleSave}
          onCancel={() => { setShowForm(false); setEditingTier(null); }}
          saving={createMutation.isPending || updateMutation.isPending}
        />
      )}

      {/* Active Subscribers */}
      <ActiveSubscribers />
    </div>
  );
}

// ─── Active Subscribers ──────────────────────────────────────────

function ActiveSubscribers() {
  const { data, isLoading } = useQuery({
    queryKey: ['membership', 'subscriptions'],
    queryFn: async () => {
      const res = await membershipApi.getSubscriptions();
      return res.data.data as Array<{
        id: number; customer_id: number; tier_name: string; monthly_price: number;
        color: string; first_name: string; last_name: string; status: string;
        current_period_end: string; phone: string; email: string;
      }>;
    },
  });
  const subs = data || [];

  if (isLoading) return null;
  if (subs.length === 0) return null;

  return (
    <div className="card">
      <div className="p-4 border-b border-surface-100 dark:border-surface-800">
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Active Subscribers</h3>
        <p className="text-xs text-surface-400 mt-0.5">{subs.length} active membership{subs.length !== 1 ? 's' : ''}</p>
      </div>
      <div className="divide-y divide-surface-100 dark:divide-surface-800">
        {subs.map((sub) => (
          <div key={sub.id} className="px-4 py-3 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <div
                className="h-2.5 w-2.5 rounded-full shrink-0"
                style={{ backgroundColor: sub.color }}
              />
              <div>
                <p className="text-sm font-medium text-surface-900 dark:text-surface-100">
                  {sub.first_name} {sub.last_name}
                </p>
                <p className="text-xs text-surface-400">
                  {sub.tier_name} - ${sub.monthly_price.toFixed(2)}/mo
                </p>
              </div>
            </div>
            <div className="text-right">
              <span className={cn(
                'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-medium',
                sub.status === 'active' ? 'bg-green-100 text-green-700 dark:bg-green-500/20 dark:text-green-400' :
                sub.status === 'paused' ? 'bg-amber-100 text-amber-700 dark:bg-amber-500/20 dark:text-amber-400' :
                'bg-red-100 text-red-700 dark:bg-red-500/20 dark:text-red-400'
              )}>
                {sub.status}
              </span>
              {sub.current_period_end && (
                <p className="text-xs text-surface-400 mt-0.5">
                  Renews {new Date(sub.current_period_end).toLocaleDateString()}
                </p>
              )}
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}
