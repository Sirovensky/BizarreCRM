import { useEffect, useMemo, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { AlertCircle, Check, Eye, EyeOff, Loader2, Save, Wifi } from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi } from '@/api/endpoints';

interface StripeFormState {
  billing_pay_link_enabled: string;
  stripe_secret_key: string;
  stripe_publishable_key: string;
  stripe_webhook_secret: string;
}

const DEFAULTS: StripeFormState = {
  billing_pay_link_enabled: '0',
  stripe_secret_key: '',
  stripe_publishable_key: '',
  stripe_webhook_secret: '',
};

const SECRET_KEYS: ReadonlyArray<keyof StripeFormState> = [
  'stripe_secret_key',
  'stripe_publishable_key',
  'stripe_webhook_secret',
];

function PasswordInput({
  value,
  onChange,
  placeholder,
}: {
  value: string;
  onChange: (value: string) => void;
  placeholder: string;
}) {
  const [show, setShow] = useState(false);
  return (
    <div className="relative">
      <input
        type={show ? 'text' : 'password'}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 pr-10 text-sm dark:border-surface-600 dark:bg-surface-800"
      />
      <button
        aria-label={show ? 'Hide value' : 'Show value'}
        type="button"
        onClick={() => setShow((v) => !v)}
        className="btn-icon btn-xs absolute right-2 top-1/2 -translate-y-1/2 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
      >
        {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </button>
    </div>
  );
}

function Toggle({
  checked,
  onChange,
  label,
  description,
}: {
  checked: boolean;
  onChange: (value: boolean) => void;
  label: string;
  description?: string;
}) {
  return (
    <label className="flex cursor-pointer items-start gap-3">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative mt-0.5 inline-flex h-6 w-11 flex-shrink-0 rounded-full transition-colors ${checked ? 'bg-indigo-500' : 'bg-surface-300 dark:bg-surface-600'}`}
      >
        <span className={`mt-0.5 inline-block h-5 w-5 transform rounded-full bg-white shadow transition-transform ${checked ? 'translate-x-5' : 'translate-x-0.5'}`} />
      </button>
      <div>
        <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</span>
        {description ? <p className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">{description}</p> : null}
      </div>
    </label>
  );
}

function deriveTenantSlug(): string {
  const host = window.location.hostname.toLowerCase();
  if (host.endsWith('.localhost')) return host.replace(/\.localhost$/, '');
  const parts = host.split('.');
  const candidate = parts.length > 2 ? parts[0] : 'your-shop-slug';
  return /^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(candidate) ? candidate : 'your-shop-slug';
}

export function TenantStripeSettings() {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<StripeFormState>(DEFAULTS);
  const [baseline, setBaseline] = useState<StripeFormState>(DEFAULTS);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);

  const webhookUrl = useMemo(() => {
    const slug = deriveTenantSlug();
    return `${window.location.origin}/api/v1/webhooks/stripe/tenant/${slug}`;
  }, []);

  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
  });

  useEffect(() => {
    if (!configData?.data?.data) return;
    const cfg = configData.data.data as Record<string, string>;
    const next = {
      ...DEFAULTS,
      ...Object.fromEntries(
        Object.keys(DEFAULTS).map((key) => [key, cfg[key] ?? DEFAULTS[key as keyof StripeFormState]]),
      ),
    } as StripeFormState;
    setForm(next);
    setBaseline(next);
  }, [configData]);

  const update = (key: keyof StripeFormState, value: string) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const dirtyPayload = (): Record<string, string> => {
    const out: Record<string, string> = {};
    (Object.keys(DEFAULTS) as Array<keyof StripeFormState>).forEach((key) => {
      if (form[key] !== baseline[key]) {
        if (SECRET_KEYS.includes(key) && form[key] === '' && baseline[key] === '') return;
        out[key] = form[key];
      }
    });
    return out;
  };

  const isDirty = (Object.keys(DEFAULTS) as Array<keyof StripeFormState>).some(
    (key) => form[key] !== baseline[key],
  );

  const saveMutation = useMutation({
    mutationFn: (data: Record<string, string>) => settingsApi.updateConfig(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings', 'config'] });
      toast.success('Stripe settings saved');
      setBaseline(form);
    },
    onError: (err: unknown) => {
      const message = err && typeof err === 'object' && 'response' in err
        ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
        : undefined;
      toast.error(message || 'Failed to save Stripe settings');
    },
  });

  const testMutation = useMutation({
    mutationFn: () => settingsApi.testStripeConnection({
      secret_key: form.stripe_secret_key,
      publishable_key: form.stripe_publishable_key,
      webhook_secret: form.stripe_webhook_secret,
    }),
    onSuccess: (res) => {
      const data = res.data.data;
      setTestResult({
        success: true,
        message: data.displayName ? `${data.displayName} (${data.accountId})` : data.accountId || 'Stripe account verified',
      });
    },
    onError: (err: unknown) => {
      const message = err && typeof err === 'object' && 'response' in err
        ? (err as { response?: { data?: { message?: string } } }).response?.data?.message
        : undefined;
      setTestResult({ success: false, message: message || 'Stripe connection test failed' });
    },
  });

  const handleSave = () => {
    const payload = dirtyPayload();
    if (Object.keys(payload).length === 0) {
      toast('No changes to save');
      return;
    }
    saveMutation.mutate(payload);
  };

  const enabled = form.billing_pay_link_enabled === '1' || form.billing_pay_link_enabled === 'true';

  return (
    <div className="space-y-6">
      <div className="flex items-center justify-between gap-4">
        <div>
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Online Checkout (Stripe)</h3>
          <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
            Customer card checkout uses the shop's Stripe account and never the platform billing key.
          </p>
        </div>
        <button
          type="button"
          onClick={handleSave}
          disabled={saveMutation.isPending || !isDirty}
          className="btn btn-md bg-indigo-600 text-white hover:bg-indigo-700"
          title={!isDirty ? 'No changes to save' : 'Save Stripe settings'}
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      <div className="space-y-4 rounded-lg border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800">
        <Toggle
          checked={enabled}
          onChange={(value) => update('billing_pay_link_enabled', value ? '1' : '0')}
          label="Enable Stripe payment links"
          description="Customers can pay invoice request links through Stripe Checkout after webhooks are configured."
        />

        <div className="grid gap-4 md:grid-cols-2">
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Secret Key</label>
            <PasswordInput
              value={form.stripe_secret_key}
              onChange={(value) => update('stripe_secret_key', value)}
              placeholder="sk_test_..."
            />
          </div>
          <div>
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Publishable Key</label>
            <PasswordInput
              value={form.stripe_publishable_key}
              onChange={(value) => update('stripe_publishable_key', value)}
              placeholder="pk_test_..."
            />
          </div>
          <div className="md:col-span-2">
            <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Webhook Signing Secret</label>
            <PasswordInput
              value={form.stripe_webhook_secret}
              onChange={(value) => update('stripe_webhook_secret', value)}
              placeholder="whsec_..."
            />
          </div>
        </div>

        <div>
          <label className="mb-1 block text-sm font-medium text-surface-700 dark:text-surface-300">Webhook Endpoint</label>
          <input
            readOnly
            value={webhookUrl}
            className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 font-mono text-xs text-surface-700 dark:border-surface-600 dark:bg-surface-900 dark:text-surface-200"
          />
        </div>

        <div className="flex flex-wrap items-center gap-3">
          <button
            type="button"
            onClick={() => {
              setTestResult(null);
              testMutation.mutate();
            }}
            disabled={testMutation.isPending || !form.stripe_secret_key}
            className="btn btn-secondary btn-sm border border-surface-300 bg-surface-50 dark:border-surface-600 dark:bg-surface-700 dark:hover:bg-surface-600"
          >
            {testMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Wifi className="h-4 w-4" />}
            Test Connection
          </button>
          {testResult ? (
            <div className={`flex items-center gap-2 text-sm ${testResult.success ? 'text-green-600' : 'text-red-500'}`}>
              {testResult.success ? <Check className="h-4 w-4" /> : <AlertCircle className="h-4 w-4" />}
              {testResult.message}
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}
