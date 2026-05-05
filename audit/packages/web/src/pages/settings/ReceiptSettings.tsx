import { useState, useEffect, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, AlertCircle, Upload, X, FileText } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';
import { ReceiptLivePreview } from './components/ReceiptLivePreview';
import { ComingSoonBadge } from './components/ComingSoonBadge';

// ─── Field Rows ──────────────────────────────────────────────────────────────

function TextRow({ label, description, value, onChange, placeholder }: {
  label: string;
  description: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
      <div className="flex-shrink-0">
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <input
        type="text"
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder || label}
        className="w-80 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
      />
    </div>
  );
}

function TextareaRow({ label, description, value, onChange, placeholder }: {
  label: string;
  description: string;
  value: string;
  onChange: (v: string) => void;
  placeholder?: string;
}) {
  return (
    <div className="flex items-start justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
      <div className="flex-shrink-0 pt-1.5">
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <textarea
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder || label}
        rows={3}
        className="w-80 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-y"
      />
    </div>
  );
}

// ─── Logo Upload Row ─────────────────────────────────────────────────────────

function LogoUploadRow({ label, description, value, onChange }: {
  label: string;
  description: string;
  value: string;
  onChange: (v: string) => void;
}) {
  const inputRef = useRef<HTMLInputElement>(null);

  function handleFile(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;
    if (file.size > 500_000) {
      toast.error('Logo must be under 500KB');
      return;
    }
    const reader = new FileReader();
    reader.onload = () => {
      onChange(reader.result as string);
    };
    reader.readAsDataURL(file);
  }

  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
      <div className="flex-shrink-0">
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <div className="flex items-center gap-3">
        {value ? (
          <div className="relative">
            <img src={value} alt="Logo" className="h-12 w-auto max-w-[160px] rounded border border-surface-200 dark:border-surface-700 object-contain" />
            <button
              onClick={() => onChange('')}
              className="absolute -right-1.5 -top-1.5 rounded-full bg-red-500 p-0.5 text-white hover:bg-red-600"
            >
              <X className="h-3 w-3" />
            </button>
          </div>
        ) : (
          <button
            onClick={() => inputRef.current?.click()}
            className="inline-flex items-center gap-2 rounded-lg border border-dashed border-surface-300 px-4 py-2 text-sm text-surface-500 transition-colors hover:border-primary-400 hover:text-primary-600 dark:border-surface-600 dark:hover:border-primary-500"
          >
            <Upload className="h-4 w-4" />
            Upload Logo
          </button>
        )}
        <input ref={inputRef} type="file" accept="image/*" className="hidden" onChange={handleFile} />
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

// ─── Main Component ──────────────────────────────────────────────────────────

// ─── Toggle Row ─────────────────────────────────────────────────────────────

function ToggleRow({ label, desc, configKey, val, set, comingSoon = false }: { label: string; desc: string; configKey: string; val: (k: string, fb?: string) => string; set: (k: string, v: string) => void; comingSoon?: boolean }) {
  const isOn = val(configKey, '1') === '1';
  return (
    <div className="flex items-center justify-between py-3 border-b border-surface-100 dark:border-surface-800 last:border-0">
      <div>
        <div className="flex items-center gap-2">
          <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
          {comingSoon && <ComingSoonBadge status="coming_soon" compact />}
        </div>
        <p className="text-xs text-surface-500 dark:text-surface-400">{desc}</p>
      </div>
      <button role="switch" aria-checked={isOn} disabled={comingSoon} onClick={() => !comingSoon && set(configKey, isOn ? '0' : '1')} className={cn('relative inline-flex h-6 w-11 shrink-0 rounded-full border-2 border-transparent transition-colors', isOn ? 'bg-teal-500' : 'bg-surface-300 dark:bg-surface-600', comingSoon && 'opacity-50 cursor-not-allowed')}>
        <span className={cn('pointer-events-none inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform', isOn ? 'translate-x-5' : 'translate-x-0')} />
      </button>
    </div>
  );
}

// ─── Receipt Templates Editor ────────────────────────────────────────────────

interface ReceiptTemplate {
  id: number;
  name: string;
  type: string;
  header_text: string | null;
  footer_text: string | null;
  show_warranty_info: number;
  show_trade_in_info: number;
  is_default: number;
}

function ReceiptTemplatesEditor() {
  const queryClient = useQueryClient();
  const [drafts, setDrafts] = useState<Record<number, { header_text: string; footer_text: string }>>({});

  const { data, isLoading } = useQuery({
    queryKey: ['receipt-templates'],
    queryFn: async () => {
      const res = await settingsApi.getReceiptTemplates();
      return res.data.data as ReceiptTemplate[];
    },
  });

  const saveMutation = useMutation({
    mutationFn: ({ id, header_text, footer_text }: { id: number; header_text: string; footer_text: string }) =>
      settingsApi.updateReceiptTemplate(id, { header_text, footer_text }),
    onSuccess: (_res, vars) => {
      queryClient.invalidateQueries({ queryKey: ['receipt-templates'] });
      setDrafts((prev) => {
        const next = { ...prev };
        delete next[vars.id];
        return next;
      });
      toast.success('Template saved');
    },
    onError: () => toast.error('Failed to save template'),
  });

  if (isLoading) return <div className="py-4 flex items-center gap-2 text-surface-400"><Loader2 className="h-4 w-4 animate-spin" /> Loading templates…</div>;
  if (!data?.length) return <p className="text-sm text-surface-400 py-2">No templates found.</p>;

  return (
    <div className="space-y-4">
      {data.map((tpl) => {
        const draft = drafts[tpl.id];
        const header = draft?.header_text ?? (tpl.header_text || '');
        const footer = draft?.footer_text ?? (tpl.footer_text || '');
        const isDirty = !!draft;

        function update(field: 'header_text' | 'footer_text', value: string) {
          setDrafts((prev) => ({
            ...prev,
            [tpl.id]: {
              header_text: field === 'header_text' ? value : (prev[tpl.id]?.header_text ?? (tpl.header_text || '')),
              footer_text: field === 'footer_text' ? value : (prev[tpl.id]?.footer_text ?? (tpl.footer_text || '')),
            },
          }));
        }

        return (
          <div key={tpl.id} className="rounded-lg border border-surface-200 dark:border-surface-700 p-4">
            <div className="flex items-center gap-2 mb-3">
              <FileText className="h-4 w-4 text-primary-500" />
              <p className="text-sm font-semibold text-surface-900 dark:text-surface-100">{tpl.name}</p>
              <span className="ml-auto text-xs text-surface-400 bg-surface-100 dark:bg-surface-800 px-2 py-0.5 rounded-full">{tpl.type}</span>
            </div>
            <div className="space-y-3">
              <div>
                <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Header text</label>
                <textarea
                  rows={2}
                  value={header}
                  onChange={(e) => update('header_text', e.target.value)}
                  placeholder="Printed above line items on this receipt type"
                  className="w-full px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-y"
                />
              </div>
              <div>
                <label className="block text-xs font-medium text-surface-600 dark:text-surface-400 mb-1">Footer text</label>
                <textarea
                  rows={2}
                  value={footer}
                  onChange={(e) => update('footer_text', e.target.value)}
                  placeholder="Printed at the bottom of this receipt type"
                  className="w-full px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 resize-y"
                />
              </div>
              <div className="flex justify-end">
                <button
                  onClick={() => saveMutation.mutate({ id: tpl.id, header_text: header, footer_text: footer })}
                  disabled={!isDirty || saveMutation.isPending}
                  className={cn(
                    'inline-flex items-center gap-2 px-3 py-1.5 text-xs font-medium rounded-lg transition-colors',
                    isDirty
                      ? 'bg-primary-600 text-primary-950 hover:bg-primary-700'
                      : 'bg-surface-100 dark:bg-surface-800 text-surface-400 cursor-not-allowed'
                  )}
                >
                  <Save className="h-3 w-3" />
                  Save
                </button>
              </div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ─── Main Component ──────────────────────────────────────────────────────────

export function ReceiptSettings() {
  const queryClient = useQueryClient();
  const [config, setConfig] = useState<Record<string, string>>({});
  const [dirty, setDirty] = useState(false);
  const [activeTab, setActiveTab] = useState<'content' | 'configuration'>('content');

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
      toast.success('Receipt settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  function set(key: string, value: string) {
    setConfig((prev) => ({ ...prev, [key]: value }));
    setDirty(true);
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
      <div className="p-4 border-b border-surface-100 dark:border-surface-800 flex items-center justify-between">
        <div className="flex items-center gap-4">
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Receipt Settings</h3>
          <div className="flex rounded-lg border border-surface-200 dark:border-surface-700 overflow-hidden">
            <button
              onClick={() => setActiveTab('content')}
              className={cn(
                'px-3 py-1 text-sm font-medium transition-colors',
                activeTab === 'content'
                  ? 'bg-primary-600 text-primary-950'
                  : 'bg-white dark:bg-surface-800 text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-700'
              )}
            >
              Content
            </button>
            <button
              onClick={() => setActiveTab('configuration')}
              className={cn(
                'px-3 py-1 text-sm font-medium transition-colors',
                activeTab === 'configuration'
                  ? 'bg-primary-600 text-primary-950'
                  : 'bg-white dark:bg-surface-800 text-surface-600 dark:text-surface-400 hover:bg-surface-50 dark:hover:bg-surface-700'
              )}
            >
              Configuration
            </button>
          </div>
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

      {activeTab === 'content' && <div className="p-6">
        {/* Componentized live preview (audit §50 enrichment) — updates in real
            time as the form changes. Rendered side-by-side on wide screens. */}
        <div className="mb-6 grid grid-cols-1 gap-4 lg:grid-cols-[1fr_auto]">
          <p className="text-xs text-surface-500 dark:text-surface-400 lg:col-span-2">
            Edit the fields below to see your receipt update in real time.
          </p>
          <div className="order-2 lg:order-1">
            <SectionHeader title="Quick Live Preview" />
            <p className="text-xs text-surface-400">
              Approximate rendering — actual receipts use real customer data.
            </p>
          </div>
          <div className="order-1 lg:order-2">
            <ReceiptLivePreview
              storeName={val('store_name', 'Your Shop')}
              storeAddress={val('store_address')}
              title={val('receipt_title')}
              header={val('receipt_header')}
              footer={val('receipt_thermal_footer') || val('receipt_footer')}
              terms={val('receipt_thermal_terms') || val('receipt_terms')}
              logoUrl={val('receipt_logo')}
              size={val('receipt_default_size', 'receipt80') === 'receipt58'
                ? 'thermal_58'
                : val('receipt_default_size', 'receipt80') === 'letter'
                  ? 'letter'
                  : 'thermal_80'}
            />
          </div>
        </div>

        <SectionHeader title="General" />
        <LogoUploadRow
          label="Receipt Logo"
          description="Logo displayed at the top of receipts (max 500KB)"
          value={val('receipt_logo')}
          onChange={(v) => set('receipt_logo', v)}
        />
        <TextRow
          label="Receipt Title"
          description="Title displayed at the top of receipts"
          value={val('receipt_title', 'Receipt')}
          onChange={(v) => set('receipt_title', v)}
        />
        <TextareaRow
          label="Receipt Header"
          description="Message shown at the top of every receipt (thermal and email), below the store name"
          value={val('receipt_header')}
          onChange={(v) => set('receipt_header', v)}
          placeholder="e.g. Thank you for choosing our shop!"
        />
        <div className="flex items-center justify-between py-3 border-b border-surface-100 dark:border-surface-800">
          <div>
            <p className="text-sm font-medium text-surface-900 dark:text-surface-100">Default Paper Size</p>
            <p className="text-xs text-surface-500 dark:text-surface-400">Used when printing from ticket list and quick print actions</p>
          </div>
          <select
            value={val('receipt_default_size', 'receipt80')}
            onChange={(e) => set('receipt_default_size', e.target.value)}
            className="text-sm rounded-lg border border-surface-200 dark:border-surface-700 bg-white dark:bg-surface-800 text-surface-700 dark:text-surface-300 px-3 py-1.5"
          >
            <option value="receipt80">80mm Thermal</option>
            <option value="receipt58">58mm Thermal</option>
            <option value="letter">Full Page (Letter)</option>
          </select>
        </div>

        <SectionHeader title="Page Print (Letter)" />
        <TextareaRow
          label="Terms & Conditions"
          description="Terms & conditions printed on page-size receipts"
          value={val('receipt_terms')}
          onChange={(v) => set('receipt_terms', v)}
          placeholder="All repairs carry a 90-day warranty..."
        />
        <TextareaRow
          label="Footer"
          description="Footer text for page-size receipts"
          value={val('receipt_footer')}
          onChange={(v) => set('receipt_footer', v)}
          placeholder="Thank you for choosing our shop!"
        />

        <SectionHeader title="Label Print" />
        <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
          <div className="flex-shrink-0">
            <p className="text-sm font-medium text-surface-900 dark:text-surface-100">Label Size</p>
            <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">Width and height in millimeters for label printing (default: 102mm x 51mm / 4"x2")</p>
          </div>
          <div className="flex items-center gap-2">
            <div className="flex items-center gap-1">
              <input
                type="number"
                min="20"
                max="300"
                value={val('label_width_mm', '102')}
                onChange={(e) => set('label_width_mm', e.target.value)}
                className="w-20 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
              />
              <span className="text-xs text-surface-500">mm</span>
            </div>
            <span className="text-surface-400">x</span>
            <div className="flex items-center gap-1">
              <input
                type="number"
                min="10"
                max="300"
                value={val('label_height_mm', '51')}
                onChange={(e) => set('label_height_mm', e.target.value)}
                className="w-20 px-2 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2"
              />
              <span className="text-xs text-surface-500">mm</span>
            </div>
          </div>
        </div>

        <SectionHeader title="Thermal Print (80mm/58mm)" />
        <TextareaRow
          label="Terms & Conditions"
          description="Terms & conditions for thermal receipt printer"
          value={val('receipt_thermal_terms')}
          onChange={(v) => set('receipt_thermal_terms', v)}
          placeholder="90-day warranty on all repairs..."
        />
        <TextareaRow
          label="Footer"
          description="Footer text for thermal receipt printer"
          value={val('receipt_thermal_footer')}
          onChange={(v) => set('receipt_thermal_footer', v)}
          placeholder="Thank you!"
        />

        {/* ─── Live Receipt Preview ──────────────────────────────────── */}
        <SectionHeader title="Live Preview" />
        <p className="text-xs text-surface-500 dark:text-surface-400 mb-3">
          Approximate preview of how your receipt header/footer will look. Not pixel-perfect.
        </p>
        <div className="flex gap-6 flex-wrap">
          {/* Page / Letter preview */}
          <div className="flex-1 min-w-[260px]">
            <p className="text-xs font-medium text-surface-600 dark:text-surface-400 mb-1.5">Page (Letter)</p>
            <div className="border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-900 p-5 shadow-sm min-h-[280px] flex flex-col text-center">
              {val('receipt_logo') && (
                <img src={val('receipt_logo')} alt="Logo" className="h-10 w-auto mx-auto mb-2 object-contain" />
              )}
              <p className="font-semibold text-sm text-surface-900 dark:text-surface-100">
                {val('store_name', 'Your Store Name')}
              </p>
              <p className="text-[11px] text-surface-500 dark:text-surface-400 mt-0.5">
                {val('store_address', 'Your Address')}
              </p>
              <p className="text-xs font-medium text-surface-700 dark:text-surface-300 mt-2">
                {val('receipt_title', 'Receipt')}
              </p>
              <div className="flex-1 flex items-center justify-center my-3">
                <div className="text-[10px] text-surface-300 dark:text-surface-600 italic">-- ticket details --</div>
              </div>
              {val('receipt_terms') && (
                <p className="text-[10px] text-surface-500 dark:text-surface-400 border-t border-surface-100 dark:border-surface-800 pt-2 mt-auto whitespace-pre-line text-left">
                  {val('receipt_terms')}
                </p>
              )}
              {val('receipt_footer') && (
                <p className="text-[10px] text-surface-600 dark:text-surface-400 mt-2 font-medium">
                  {val('receipt_footer')}
                </p>
              )}
            </div>
          </div>

          {/* Thermal preview */}
          <div className="w-[200px] shrink-0">
            <p className="text-xs font-medium text-surface-600 dark:text-surface-400 mb-1.5">Thermal (80mm)</p>
            <div className="border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-900 p-3 shadow-sm min-h-[280px] flex flex-col text-center" style={{ fontFamily: 'monospace' }}>
              {val('receipt_logo') && (
                <img src={val('receipt_logo')} alt="Logo" className="h-8 w-auto mx-auto mb-1 object-contain" />
              )}
              <p className="font-bold text-[10px] text-surface-900 dark:text-surface-100">
                {val('store_name', 'Your Store Name')}
              </p>
              <p className="text-[8px] text-surface-500 dark:text-surface-400">
                {val('store_phone', 'Your Phone')}
              </p>
              <p className="text-[9px] font-semibold text-surface-700 dark:text-surface-300 mt-1 border-b border-dashed border-surface-300 dark:border-surface-600 pb-1">
                {val('receipt_title', 'Receipt')}
              </p>
              <div className="flex-1 flex items-center justify-center my-2">
                <div className="text-[8px] text-surface-300 dark:text-surface-600 italic">-- items --</div>
              </div>
              <div className="border-t border-dashed border-surface-300 dark:border-surface-600 pt-1 mt-auto">
                {val('receipt_thermal_terms') && (
                  <p className="text-[7px] text-surface-500 dark:text-surface-400 whitespace-pre-line text-left mb-1">
                    {val('receipt_thermal_terms')}
                  </p>
                )}
                {val('receipt_thermal_footer') && (
                  <p className="text-[8px] text-surface-600 dark:text-surface-400 font-medium">
                    {val('receipt_thermal_footer')}
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>

        {/* ─── Receipt Templates ────────────────────────────────────── */}
        <SectionHeader title="Receipt Templates" />
        <p className="text-xs text-surface-500 dark:text-surface-400 mb-3">
          Per-transaction-type overrides for header and footer text. The matching template is
          applied automatically (warranty tickets use the Warranty template, trade-ins use
          Trade-In, everything else uses Standard).
        </p>
        <ReceiptTemplatesEditor />
      </div>}

      {activeTab === 'configuration' && <div className="p-6">
        <SectionHeader title="Signature & Verification" />
        <ToggleRow label="Display pre repair device conditions (page)" desc="Show pre-repair condition checklist on page-size receipts" configKey="receipt_cfg_pre_conditions_page" val={val} set={set} />
        <ToggleRow label="Display pre repair device conditions (thermal)" desc="Show pre-repair condition checklist on thermal receipts" configKey="receipt_cfg_pre_conditions_thermal" val={val} set={set} />
        <ToggleRow label="Display post repair device conditions (page)" desc="Show post-repair condition checklist on page-size receipts" configKey="receipt_cfg_post_conditions_page" val={val} set={set} />
        <ToggleRow label="Display signature on page receipt" desc="Print customer signature on page-size receipts" configKey="receipt_cfg_signature_page" val={val} set={set} />
        <ToggleRow label="Display signature on thermal receipt" desc="Print customer signature on thermal receipts" configKey="receipt_cfg_signature_thermal" val={val} set={set} />
        <ToggleRow label="Display P.O/S.O on page receipt" desc="Show purchase order / sales order number on page receipts" configKey="receipt_cfg_po_so_page" val={val} set={set} />
        <ToggleRow label="Display P.O/S.O on thermal receipt" desc="Show purchase order / sales order number on thermal receipts" configKey="receipt_cfg_po_so_thermal" val={val} set={set} />
        <ToggleRow label="Display security code on page receipt" desc="Print device security/passcode on page receipts" configKey="receipt_cfg_security_code_page" val={val} set={set} />
        <ToggleRow label="Display security code on thermal receipt" desc="Print device security/passcode on thermal receipts" configKey="receipt_cfg_security_code_thermal" val={val} set={set} />

        <SectionHeader title="Pricing, Tax & Transaction Details" />
        <ToggleRow label="Display tax" desc="Show tax breakdown on receipts" configKey="receipt_cfg_tax" val={val} set={set} />
        <ToggleRow label="Display discount on thermal receipt" desc="Show discount amounts on thermal receipts" configKey="receipt_cfg_discount_thermal" val={val} set={set} />
        <ToggleRow label="Display line item price (including tax) on thermal receipt" desc="Show per-item price with tax included on thermal receipts" configKey="receipt_cfg_line_price_incl_tax_thermal" val={val} set={set} />
        <ToggleRow label="Display transaction ID/cheque number on page receipt" desc="Print transaction ID or cheque number on page receipts" configKey="receipt_cfg_transaction_id_page" val={val} set={set} />
        <ToggleRow label="Display transaction ID/cheque number on thermal receipt" desc="Print transaction ID or cheque number on thermal receipts" configKey="receipt_cfg_transaction_id_thermal" val={val} set={set} />
        <ToggleRow label="Display receipt due date" desc="Show the due date on receipts" configKey="receipt_cfg_due_date" val={val} set={set} />

        <SectionHeader title="Staff & General" />
        <ToggleRow label="Display employee name" desc="Show the assigned technician or cashier name on receipts" configKey="receipt_cfg_employee_name" val={val} set={set} />

        <SectionHeader title="Service, Part & Description" />
        <ToggleRow label="Display description on page receipt" desc="Show item/service descriptions on page receipts" configKey="receipt_cfg_description_page" val={val} set={set} />
        <ToggleRow label="Display description on thermal receipt" desc="Show item/service descriptions on thermal receipts" configKey="receipt_cfg_description_thermal" val={val} set={set} />
        <ToggleRow label="Display part details on page receipt" desc="Show individual part names and quantities on page receipts" configKey="receipt_cfg_parts_page" val={val} set={set} />
        <ToggleRow label="Display part details on thermal receipt" desc="Show individual part names and quantities on thermal receipts" configKey="receipt_cfg_parts_thermal" val={val} set={set} />
        <ToggleRow label="Display part SKU" desc="Print SKU codes next to parts on receipts" configKey="receipt_cfg_part_sku" val={val} set={set} />
        <ToggleRow label="Display service network on thermal receipt" desc="Show device network/carrier on thermal receipts" configKey="receipt_cfg_network_thermal" val={val} set={set} />
        <ToggleRow label="Display repair service description on page receipt" desc="Show repair service descriptions on page receipts" configKey="receipt_cfg_service_desc_page" val={val} set={set} />
        <ToggleRow label="Display repair service description on thermal receipt" desc="Show repair service descriptions on thermal receipts" configKey="receipt_cfg_service_desc_thermal" val={val} set={set} comingSoon />
        <ToggleRow label="Display item physical location" desc="Show device storage location on receipts" configKey="receipt_cfg_device_location" val={val} set={set} comingSoon />
        <ToggleRow label="Display barcode" desc="Print barcode on receipts for scanning" configKey="receipt_cfg_barcode" val={val} set={set} />
      </div>}
    </div>
  );
}
