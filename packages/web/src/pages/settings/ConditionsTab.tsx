import { useState } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Plus, Trash2, Pencil, X, Check, Loader2, AlertCircle,
  GripVertical, ChevronUp, ChevronDown, ToggleLeft, ToggleRight,
  Smartphone, Tablet, Laptop, Monitor, Gamepad2, Tv, HelpCircle,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { confirm } from '@/stores/confirmStore';
import { cn } from '@/utils/cn';
import { formatApiError } from '@/utils/apiError';

// ─── Types ────────────────────────────────────────────────────────────────────

interface ConditionCheck {
  id: number;
  template_id: number;
  label: string;
  sort_order: number;
  is_active: number;
}

interface ConditionTemplate {
  id: number;
  category: string;
  name: string;
  is_default: number;
  created_at: string;
  checks: ConditionCheck[];
}

const CATEGORIES = [
  { key: 'phone', label: 'Phone', icon: Smartphone },
  { key: 'tablet', label: 'Tablet', icon: Tablet },
  { key: 'laptop', label: 'Laptop', icon: Laptop },
  { key: 'desktop', label: 'Desktop', icon: Monitor },
  { key: 'console', label: 'Console', icon: Gamepad2 },
  { key: 'tv', label: 'TV', icon: Tv },
  { key: 'other', label: 'Other', icon: HelpCircle },
] as const;

// ─── Main Component ───────────────────────────────────────────────────────────

export function ConditionsTab() {
  const [selectedCategory, setSelectedCategory] = useState('phone');

  return (
    <div className="space-y-6">
      {/* Pre/Post Condition Templates */}
      <div className="space-y-4">
        <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wide">Pre/Post Repair Conditions</h3>
        {/* Category Tabs */}
        <div className="flex gap-1 bg-surface-100 dark:bg-surface-800 rounded-lg p-1 overflow-x-auto">
          {CATEGORIES.map((cat) => {
            const Icon = cat.icon;
            return (
              <button
                key={cat.key}
                onClick={() => setSelectedCategory(cat.key)}
                className={cn(
                  'flex items-center gap-1.5 px-3 py-1.5 text-sm font-medium rounded-md transition-colors whitespace-nowrap',
                  selectedCategory === cat.key
                    ? 'bg-white dark:bg-surface-700 text-surface-900 dark:text-surface-100 shadow-sm'
                    : 'text-surface-500 hover:text-surface-700 dark:hover:text-surface-300'
                )}
              >
                <Icon className="h-4 w-4" />
                {cat.label}
              </button>
            );
          })}
        </div>

        {/* Template list for selected category */}
        <CategoryTemplates category={selectedCategory} />
      </div>

      {/* Repair Checklists */}
      <ChecklistTemplatesSection />
    </div>
  );
}

// ─── Category Templates ───────────────────────────────────────────────────────

function CategoryTemplates({ category }: { category: string }) {
  const queryClient = useQueryClient();
  const [newTemplateName, setNewTemplateName] = useState('');
  const [showNewTemplate, setShowNewTemplate] = useState(false);

  const { data: templates, isLoading, isError } = useQuery({
    queryKey: ['condition-templates', category],
    queryFn: async () => {
      const res = await settingsApi.getConditionTemplates(category);
      return res.data.data as ConditionTemplate[];
    },
  });

  const createMutation = useMutation({
    mutationFn: (name: string) => settingsApi.createConditionTemplate({ category, name }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
      setNewTemplateName('');
      setShowNewTemplate(false);
      toast.success('Template created');
    },
    onError: () => toast.error('Failed to create template'),
  });

  const deleteMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteConditionTemplate(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
      toast.success('Template deleted');
    },
    onError: (err: any) => toast.error(err?.response?.data?.message || 'Failed to delete template'),
  });

  if (isLoading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="h-6 w-6 animate-spin text-primary-500" />
        <span className="ml-2 text-surface-500">Loading...</span>
      </div>
    );
  }

  if (isError) {
    return (
      <div className="flex flex-col items-center justify-center py-12">
        <AlertCircle className="h-8 w-8 text-red-400 mb-2" />
        <p className="text-sm text-surface-500">Failed to load condition templates</p>
      </div>
    );
  }

  return (
    <div className="space-y-4">
      {templates?.map((template) => (
        <TemplateCard
          key={template.id}
          template={template}
          category={category}
          onDelete={template.is_default ? undefined : () => deleteMutation.mutate(template.id)}
        />
      ))}

      {/* Add new template */}
      {showNewTemplate ? (
        <div className="card p-4">
          <div className="flex items-center gap-2">
            <input
              type="text"
              value={newTemplateName}
              onChange={(e) => setNewTemplateName(e.target.value)}
              placeholder="Template name..."
              className="input flex-1"
              autoFocus
              onKeyDown={(e) => {
                if (e.key === 'Enter' && newTemplateName.trim()) createMutation.mutate(newTemplateName.trim());
                if (e.key === 'Escape') { setShowNewTemplate(false); setNewTemplateName(''); }
              }}
            />
            <button
              onClick={() => { if (newTemplateName.trim()) createMutation.mutate(newTemplateName.trim()); }}
              disabled={!newTemplateName.trim() || createMutation.isPending}
              className="btn btn-primary btn-sm"
            >
              <Check className="h-4 w-4" />
            </button>
            <button onClick={() => { setShowNewTemplate(false); setNewTemplateName(''); }} className="btn btn-ghost btn-sm">
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>
      ) : (
        <button
          onClick={() => setShowNewTemplate(true)}
          className="btn btn-ghost w-full justify-center gap-2 border border-dashed border-surface-300 dark:border-surface-600 py-3 text-surface-500 hover:text-surface-700 dark:hover:text-surface-300"
        >
          <Plus className="h-4 w-4" />
          Add Template
        </button>
      )}
    </div>
  );
}

// ─── Template Card ────────────────────────────────────────────────────────────

function TemplateCard({
  template,
  category,
  onDelete,
}: {
  template: ConditionTemplate;
  category: string;
  onDelete?: () => void;
}) {
  const queryClient = useQueryClient();
  const [newCheckLabel, setNewCheckLabel] = useState('');
  const [editingCheckId, setEditingCheckId] = useState<number | null>(null);
  const [editingLabel, setEditingLabel] = useState('');

  const addCheckMutation = useMutation({
    mutationFn: (label: string) => settingsApi.addConditionCheck({ template_id: template.id, label }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
      setNewCheckLabel('');
      toast.success('Check added');
    },
    onError: () => toast.error('Failed to add check'),
  });

  const updateCheckMutation = useMutation({
    mutationFn: ({ id, data }: { id: number; data: { label?: string; is_active?: number } }) =>
      settingsApi.updateConditionCheck(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
      setEditingCheckId(null);
    },
    onError: () => toast.error('Failed to update check'),
  });

  const deleteCheckMutation = useMutation({
    mutationFn: (id: number) => settingsApi.deleteConditionCheck(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
      toast.success('Check removed');
    },
    onError: () => toast.error('Failed to remove check'),
  });

  const reorderMutation = useMutation({
    mutationFn: (order: number[]) => settingsApi.reorderConditionChecks(template.id, order),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['condition-templates', category] });
    },
    onError: () => toast.error('Failed to reorder'),
  });

  function moveCheck(checkId: number, direction: 'up' | 'down') {
    const checks = [...template.checks].sort((a, b) => a.sort_order - b.sort_order);
    const idx = checks.findIndex((c) => c.id === checkId);
    if (idx < 0) return;
    const swapIdx = direction === 'up' ? idx - 1 : idx + 1;
    if (swapIdx < 0 || swapIdx >= checks.length) return;
    [checks[idx], checks[swapIdx]] = [checks[swapIdx], checks[idx]];
    reorderMutation.mutate(checks.map((c) => c.id));
  }

  const sortedChecks = [...template.checks].sort((a, b) => a.sort_order - b.sort_order);

  return (
    <div className="card">
      {/* Header */}
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">{template.name}</h3>
          {template.is_default ? (
            <span className="text-xs bg-primary-100 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400 px-2 py-0.5 rounded-full">
              Default
            </span>
          ) : null}
        </div>
        {onDelete && (
          <button aria-label="Delete" onClick={onDelete} className="btn btn-ghost btn-sm text-red-500 hover:text-red-700 hover:bg-red-50 dark:hover:bg-red-900/20">
            <Trash2 className="h-4 w-4" />
          </button>
        )}
      </div>

      {/* Checks list */}
      <div className="divide-y divide-surface-100 dark:divide-surface-800">
        {sortedChecks.map((check, idx) => (
          <div
            key={check.id}
            className={cn(
              'flex items-center gap-2 px-4 py-2.5 group',
              !check.is_active && 'opacity-50'
            )}
          >
            <GripVertical className="h-4 w-4 text-surface-300 dark:text-surface-600 flex-shrink-0" />

            {/* Up/Down buttons */}
            <div className="flex flex-col gap-0.5">
              <button
                onClick={() => moveCheck(check.id, 'up')}
                disabled={idx === 0}
                className="p-0.5 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                <ChevronUp className="h-3 w-3" />
              </button>
              <button
                onClick={() => moveCheck(check.id, 'down')}
                disabled={idx === sortedChecks.length - 1}
                className="p-0.5 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300 disabled:opacity-30 disabled:cursor-not-allowed"
              >
                <ChevronDown className="h-3 w-3" />
              </button>
            </div>

            {/* Label (editable) */}
            {editingCheckId === check.id ? (
              <div className="flex items-center gap-1 flex-1">
                <input
                  type="text"
                  value={editingLabel}
                  onChange={(e) => setEditingLabel(e.target.value)}
                  className="input input-sm flex-1"
                  autoFocus
                  onKeyDown={(e) => {
                    if (e.key === 'Enter' && editingLabel.trim()) {
                      updateCheckMutation.mutate({ id: check.id, data: { label: editingLabel.trim() } });
                    }
                    if (e.key === 'Escape') setEditingCheckId(null);
                  }}
                />
                <button
                  onClick={() => {
                    if (editingLabel.trim()) updateCheckMutation.mutate({ id: check.id, data: { label: editingLabel.trim() } });
                  }}
                  className="p-1 text-green-600 hover:text-green-700"
                >
                  <Check className="h-3.5 w-3.5" />
                </button>
                <button onClick={() => setEditingCheckId(null)} className="p-1 text-surface-400 hover:text-surface-600">
                  <X className="h-3.5 w-3.5" />
                </button>
              </div>
            ) : (
              <span className="flex-1 text-sm text-surface-700 dark:text-surface-300">{check.label}</span>
            )}

            {/* Actions */}
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
              <button
                onClick={() => {
                  setEditingCheckId(check.id);
                  setEditingLabel(check.label);
                }}
                className="p-1 text-surface-400 hover:text-primary-600"
                title="Edit label"
              >
                <Pencil className="h-3.5 w-3.5" />
              </button>
              <button
                onClick={() => updateCheckMutation.mutate({ id: check.id, data: { is_active: check.is_active ? 0 : 1 } })}
                className="p-1 text-surface-400 hover:text-amber-600"
                title={check.is_active ? 'Deactivate' : 'Activate'}
              >
                {check.is_active ? <ToggleRight className="h-4 w-4 text-green-500" /> : <ToggleLeft className="h-4 w-4" />}
              </button>
              <button
                onClick={() => deleteCheckMutation.mutate(check.id)}
                className="p-1 text-surface-400 hover:text-red-600"
                title="Remove check"
              >
                <X className="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
        ))}

        {sortedChecks.length === 0 && (
          <div className="px-4 py-6 text-center text-sm text-surface-400 dark:text-surface-500">
            No condition checks yet. Add one below.
          </div>
        )}
      </div>

      {/* Add new check */}
      <div className="p-3 border-t border-surface-100 dark:border-surface-800">
        <div className="flex items-center gap-2">
          <input
            type="text"
            value={newCheckLabel}
            onChange={(e) => setNewCheckLabel(e.target.value)}
            placeholder="Add a condition check..."
            className="input input-sm flex-1"
            onKeyDown={(e) => {
              if (e.key === 'Enter' && newCheckLabel.trim()) addCheckMutation.mutate(newCheckLabel.trim());
            }}
          />
          <button
            onClick={() => { if (newCheckLabel.trim()) addCheckMutation.mutate(newCheckLabel.trim()); }}
            disabled={!newCheckLabel.trim() || addCheckMutation.isPending}
            className="btn btn-primary btn-sm gap-1"
          >
            <Plus className="h-3.5 w-3.5" />
            Add
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Checklist Templates Section ─────────────────────────────────────────────

function ChecklistTemplatesSection() {
  const queryClient = useQueryClient();
  const [showAdd, setShowAdd] = useState(false);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [form, setForm] = useState({ name: '', device_type: '', items: '' });

  const { data } = useQuery({
    queryKey: ['settings', 'checklist-templates'],
    queryFn: async () => {
      const res = await settingsApi.getChecklistTemplates();
      return (res.data?.data?.templates || []) as any[];
    },
  });
  const templates = data || [];

  const createMut = useMutation({
    mutationFn: (d: any) => editingId
      ? settingsApi.updateChecklistTemplate(editingId, d)
      : settingsApi.createChecklistTemplate(d),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'checklist-templates'] });
      toast.success(editingId ? 'Updated' : 'Created');
      setShowAdd(false);
      setEditingId(null);
      setForm({ name: '', device_type: '', items: '' });
    },
    onError: () => toast.error('Failed'),
  });

  const deleteMut = useMutation({
    mutationFn: (id: number) => settingsApi.deleteChecklistTemplate(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'checklist-templates'] });
      toast.success('Deleted');
    },
  });

  const handleSubmit = () => {
    if (!form.name.trim()) return toast.error('Name required');
    const items = form.items.split('\n').map(s => s.trim()).filter(Boolean).map((label, i) => ({ label, sort_order: i, checked: false }));
    createMut.mutate({ name: form.name, device_type: form.device_type || null, items });
  };

  const handleEdit = (t: any) => {
    setEditingId(t.id);
    const items = typeof t.items === 'string' ? JSON.parse(t.items) : (t.items || []);
    setForm({ name: t.name, device_type: t.device_type || '', items: items.map((i: any) => i.label || i).join('\n') });
    setShowAdd(true);
  };

  return (
    <div>
      <div className="flex items-center justify-between mb-3">
        <h3 className="text-sm font-semibold text-surface-500 uppercase tracking-wide">Repair Checklists</h3>
        <button onClick={() => { setEditingId(null); setForm({ name: '', device_type: '', items: '' }); setShowAdd(!showAdd); }}
          className="inline-flex items-center gap-1 text-xs font-medium text-primary-600 hover:text-primary-700">
          <Plus className="h-3.5 w-3.5" /> New Template
        </button>
      </div>

      {showAdd && (
        <div className="card p-4 mb-3">
          <div className="grid grid-cols-1 sm:grid-cols-2 gap-3 mb-3">
            <input value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })}
              aria-label="Template name"
              placeholder="Template name (e.g. Screen Replacement)" className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100" />
            <select value={form.device_type} onChange={(e) => setForm({ ...form, device_type: e.target.value })}
              aria-label="Device type"
              className="px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100">
              <option value="">All Device Types</option>
              <option value="Phone">Phone</option>
              <option value="Tablet">Tablet</option>
              <option value="Laptop">Laptop</option>
              <option value="TV">TV</option>
              <option value="Game Console">Game Console</option>
              <option value="Desktop">Desktop</option>
            </select>
          </div>
          <textarea value={form.items} onChange={(e) => setForm({ ...form, items: e.target.value })}
            aria-label="Checklist items"
            rows={5} placeholder="One checklist item per line:&#10;1. Open device&#10;2. Remove battery&#10;3. Replace screen&#10;4. Test display&#10;5. Reassemble"
            className="w-full px-3 py-2 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 font-mono resize-none" />
          <div className="flex gap-2 mt-2">
            <button onClick={handleSubmit} className="px-3 py-1.5 text-sm bg-primary-600 text-white rounded-lg hover:bg-primary-700">
              {editingId ? 'Update' : 'Create'}
            </button>
            <button onClick={() => { setShowAdd(false); setEditingId(null); }} className="px-3 py-1.5 text-sm text-surface-500 hover:text-surface-700">Cancel</button>
          </div>
        </div>
      )}

      {templates.length === 0 ? (
        <p className="text-sm text-surface-400 py-4">No checklist templates yet. Create one to standardize repair workflows.</p>
      ) : (
        <div className="space-y-2">
          {templates.map((t: any) => {
            const items = typeof t.items === 'string' ? JSON.parse(t.items) : (t.items || []);
            return (
              <div key={t.id} className="card p-3 flex items-start gap-3">
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{t.name}</span>
                    {t.device_type && (
                      <span className="text-[10px] rounded-full bg-surface-100 dark:bg-surface-700 px-2 py-0.5 text-surface-500">{t.device_type}</span>
                    )}
                    <span className="text-[10px] text-surface-400">{items.length} steps</span>
                  </div>
                  <p className="text-xs text-surface-400 mt-0.5 truncate">
                    {items.slice(0, 3).map((i: any) => i.label || i).join(' → ')}
                    {items.length > 3 && ' → ...'}
                  </p>
                </div>
                <div className="flex gap-1 shrink-0">
                  <button aria-label="Edit" onClick={() => handleEdit(t)} className="p-1 text-surface-400 hover:text-amber-600"><Pencil className="h-3.5 w-3.5" /></button>
                  <button aria-label="Delete" onClick={async () => {
                    try { if (await confirm('Delete this template?', { danger: true })) deleteMut.mutate(t.id); }
                    catch (err) { toast.error(formatApiError(err)); }
                  }} className="p-1 text-surface-400 hover:text-red-600"><Trash2 className="h-3.5 w-3.5" /></button>
                </div>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
