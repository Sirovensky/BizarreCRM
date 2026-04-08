import { useState, useEffect, useRef } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { Save, Loader2, AlertCircle, Upload, X } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';
import { cn } from '@/utils/cn';

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
        className="w-80 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
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
        className="w-80 px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500 resize-y"
      />
    </div>
  );
}

function SelectRow({ label, description, value, options, onChange }: {
  label: string;
  description: string;
  value: string;
  options: { value: string; label: string }[];
  onChange: (v: string) => void;
}) {
  return (
    <div className="flex items-center justify-between py-4 border-b border-surface-100 dark:border-surface-800 gap-6">
      <div className="flex-shrink-0">
        <p className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</p>
        <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>
      </div>
      <select
        value={value}
        onChange={(e) => onChange(e.target.value)}
        className="px-3 py-1.5 text-sm border border-surface-200 dark:border-surface-700 rounded-lg bg-white dark:bg-surface-800 text-surface-900 dark:text-surface-100 focus:outline-none focus:ring-2 focus:ring-blue-500"
      >
        {options.map((o) => (
          <option key={o.value} value={o.value}>{o.label}</option>
        ))}
      </select>
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

export function InvoiceSettings() {
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
      toast.success('Invoice settings saved');
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
        <Loader2 className="h-8 w-8 animate-spin text-blue-500" />
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
        <h3 className="font-semibold text-surface-900 dark:text-surface-100">Invoice Settings</h3>
        <button
          onClick={() => saveMutation.mutate(config)}
          disabled={!dirty || saveMutation.isPending}
          className={cn(
            'inline-flex items-center gap-2 px-4 py-2 text-sm font-medium rounded-lg transition-colors',
            dirty
              ? 'bg-blue-600 text-white hover:bg-blue-700'
              : 'bg-surface-100 dark:bg-surface-800 text-surface-400 cursor-not-allowed'
          )}
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      <div className="p-6">
        <SectionHeader title="General" />
        <LogoUploadRow
          label="Invoice Logo"
          description="Logo displayed at the top of invoices (max 500KB)"
          value={val('invoice_logo')}
          onChange={(v) => set('invoice_logo', v)}
        />
        <TextRow
          label="Invoice Title"
          description="Title displayed at the top of invoices"
          value={val('invoice_title', 'Invoice')}
          onChange={(v) => set('invoice_title', v)}
        />
        <SelectRow
          label="Payment Terms"
          description="Default payment terms for invoices"
          value={val('invoice_payment_terms', 'due_upon_receipt')}
          options={[
            { value: 'due_upon_receipt', label: 'Due upon Receipt' },
            { value: 'net_15', label: 'Net 15' },
            { value: 'net_30', label: 'Net 30' },
            { value: 'net_60', label: 'Net 60' },
          ]}
          onChange={(v) => set('invoice_payment_terms', v)}
        />
        <TextareaRow
          label="Slogan"
          description="Slogan displayed on invoice"
          value={val('invoice_slogan')}
          onChange={(v) => set('invoice_slogan', v)}
          placeholder="Your business slogan..."
        />
        <TextareaRow
          label="Footer"
          description="Footer text at the bottom of invoices"
          value={val('invoice_footer')}
          onChange={(v) => set('invoice_footer', v)}
          placeholder="Thank you for your business!"
        />

        <SectionHeader title="Terms & Conditions" />
        <TextareaRow
          label="Terms & Conditions"
          description="Terms printed on invoices"
          value={val('invoice_terms')}
          onChange={(v) => set('invoice_terms', v)}
          placeholder="All sales are final..."
        />
        <SectionHeader title="Review & QR Code" />
        <TextRow
          label="Review URL"
          description="Facebook/Google Places URL (generates QR on receipt)"
          value={val('invoice_review_url')}
          onChange={(v) => set('invoice_review_url', v)}
          placeholder="https://g.page/your-business/review"
        />
      </div>
    </div>
  );
}
