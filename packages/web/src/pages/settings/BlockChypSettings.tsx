import { useState, useEffect } from 'react';
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  Save, Loader2, Eye, EyeOff, Wifi, WifiOff, Check, AlertCircle,
} from 'lucide-react';
import toast from 'react-hot-toast';
import { settingsApi, blockchypApi } from '@/api/endpoints';

// ─── Types ────────────────────────────────────────────────────────

interface BlockChypFormState {
  blockchyp_enabled: string;
  blockchyp_api_key: string;
  blockchyp_bearer_token: string;
  blockchyp_signing_key: string;
  blockchyp_terminal_name: string;
  blockchyp_test_mode: string;
  blockchyp_tc_enabled: string;
  blockchyp_tc_content: string;
  blockchyp_tc_name: string;
  blockchyp_prompt_for_tip: string;
  blockchyp_sig_required_payment: string;
  blockchyp_sig_format: string;
  blockchyp_sig_width: string;
  blockchyp_auto_close_ticket: string;
  invoice_signature_terms: string;
  invoice_refund_terms: string;
}

const DEFAULTS: BlockChypFormState = {
  blockchyp_enabled: 'false',
  blockchyp_api_key: '',
  blockchyp_bearer_token: '',
  blockchyp_signing_key: '',
  blockchyp_terminal_name: 'Front Counter',
  blockchyp_test_mode: 'false',
  blockchyp_tc_enabled: 'true',
  blockchyp_tc_content: 'I authorize this repair shop to perform diagnostic and repair services on my device. I understand that the shop is not responsible for any data loss. I agree to pay for all parts and labor required to complete the repair.',
  blockchyp_tc_name: 'Repair Agreement',
  blockchyp_prompt_for_tip: 'false',
  blockchyp_sig_required_payment: 'true',
  blockchyp_sig_format: 'png',
  blockchyp_sig_width: '400',
  blockchyp_auto_close_ticket: 'false',
  invoice_signature_terms: '',
  invoice_refund_terms: '',
};

// ─── Password input with toggle ─────────────────────────────────────

function PasswordInput({ value, onChange, placeholder }: { value: string; onChange: (v: string) => void; placeholder: string }) {
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
        type="button"
        onClick={() => setShow(!show)}
        className="absolute right-2 top-1/2 -translate-y-1/2 p-1 text-surface-400 hover:text-surface-600 dark:hover:text-surface-300"
      >
        {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
      </button>
    </div>
  );
}

// ─── Toggle switch ──────────────────────────────────────────────────

function Toggle({ checked, onChange, label, description }: { checked: boolean; onChange: (v: boolean) => void; label: string; description?: string }) {
  return (
    <label className="flex items-start gap-3 cursor-pointer">
      <button
        type="button"
        role="switch"
        aria-checked={checked}
        onClick={() => onChange(!checked)}
        className={`relative mt-0.5 inline-flex h-6 w-11 flex-shrink-0 rounded-full transition-colors ${checked ? 'bg-green-500' : 'bg-surface-300 dark:bg-surface-600'}`}
      >
        <span className={`inline-block h-5 w-5 rounded-full bg-white shadow transform transition-transform ${checked ? 'translate-x-5' : 'translate-x-0.5'} mt-0.5`} />
      </button>
      <div>
        <span className="text-sm font-medium text-surface-900 dark:text-surface-100">{label}</span>
        {description && <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">{description}</p>}
      </div>
    </label>
  );
}

// ─── Main component ─────────────────────────────────────────────────

export function BlockChypSettings() {
  const queryClient = useQueryClient();
  const [form, setForm] = useState<BlockChypFormState>(DEFAULTS);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);
  const [testing, setTesting] = useState(false);

  // Load config
  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: () => settingsApi.getConfig(),
  });

  useEffect(() => {
    if (configData?.data?.data) {
      const cfg = configData.data.data as Record<string, string>;
      setForm((prev) => ({
        ...prev,
        ...Object.fromEntries(
          Object.keys(DEFAULTS).map((key) => [key, cfg[key] ?? prev[key as keyof BlockChypFormState]])
        ),
      }));
    }
  }, [configData]);

  // Save mutation
  const saveMutation = useMutation({
    mutationFn: (data: Record<string, string>) => settingsApi.updateConfig(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['settings'] });
      queryClient.invalidateQueries({ queryKey: ['blockchyp'] });
      toast.success('BlockChyp settings saved');
    },
    onError: () => toast.error('Failed to save settings'),
  });

  const handleSave = () => {
    saveMutation.mutate({ ...form } as Record<string, string>);
  };

  const handleTestConnection = async () => {
    setTesting(true);
    setTestResult(null);
    try {
      const res = await blockchypApi.testConnection(form.blockchyp_terminal_name);
      const data = res.data?.data;
      if (data?.success) {
        setTestResult({ success: true, message: `Connected: ${data.terminalName}${data.firmwareVersion ? ` (firmware ${data.firmwareVersion})` : ''}` });
      } else {
        setTestResult({ success: false, message: data?.error || 'Connection failed' });
      }
    } catch (err: unknown) {
      const message = err instanceof Error ? err.message : 'Connection test failed';
      setTestResult({ success: false, message });
    } finally {
      setTesting(false);
    }
  };

  const update = (key: keyof BlockChypFormState, value: string) => {
    setForm((prev) => ({ ...prev, [key]: value }));
  };

  const enabled = form.blockchyp_enabled === 'true';

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h3 className="font-semibold text-surface-900 dark:text-surface-100">Payment Terminal (BlockChyp)</h3>
          <p className="text-sm text-surface-500 dark:text-surface-400 mt-1">
            Connect your BlockChyp payment terminal for card payments and customer signature capture.
          </p>
        </div>
        <button
          onClick={handleSave}
          disabled={saveMutation.isPending}
          className="flex items-center gap-2 rounded-lg bg-green-600 px-4 py-2 text-sm font-medium text-white hover:bg-green-700 disabled:opacity-50"
        >
          {saveMutation.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Save className="h-4 w-4" />}
          Save Changes
        </button>
      </div>

      {/* Section 1: Connection */}
      <div className="rounded-lg border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800 space-y-4">
        <h4 className="font-medium text-surface-900 dark:text-surface-100">Connection</h4>

        <Toggle
          checked={enabled}
          onChange={(v) => update('blockchyp_enabled', v ? 'true' : 'false')}
          label="Enable BlockChyp Terminal"
          description="Turn on to process payments and capture signatures through the terminal"
        />

        {enabled && (
          <div className="space-y-4 mt-4 pl-2 border-l-2 border-green-500/30">
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">API Key</label>
              <PasswordInput value={form.blockchyp_api_key} onChange={(v) => update('blockchyp_api_key', v)} placeholder="Enter your BlockChyp API key" />
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Bearer Token</label>
              <PasswordInput value={form.blockchyp_bearer_token} onChange={(v) => update('blockchyp_bearer_token', v)} placeholder="Enter your BlockChyp bearer token" />
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Signing Key</label>
              <PasswordInput value={form.blockchyp_signing_key} onChange={(v) => update('blockchyp_signing_key', v)} placeholder="Enter your BlockChyp signing key" />
            </div>
            <div>
              <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Terminal Name</label>
              <input
                type="text"
                value={form.blockchyp_terminal_name}
                onChange={(e) => update('blockchyp_terminal_name', e.target.value)}
                placeholder="Front Counter"
                className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
              />
              <p className="text-xs text-surface-500 mt-1">The name assigned to your terminal in the BlockChyp dashboard</p>
            </div>

            <Toggle
              checked={form.blockchyp_test_mode === 'true'}
              onChange={(v) => update('blockchyp_test_mode', v ? 'true' : 'false')}
              label="Test Mode (Sandbox)"
              description="Route transactions through the BlockChyp test gateway — no real charges"
            />

            {/* Test Connection */}
            <div className="flex items-center gap-3">
              <button
                onClick={handleTestConnection}
                disabled={testing || !form.blockchyp_api_key || !form.blockchyp_bearer_token || !form.blockchyp_signing_key}
                className="flex items-center gap-2 rounded-lg border border-surface-300 bg-surface-50 px-4 py-2 text-sm font-medium hover:bg-surface-100 disabled:opacity-50 dark:border-surface-600 dark:bg-surface-700 dark:hover:bg-surface-600"
              >
                {testing ? <Loader2 className="h-4 w-4 animate-spin" /> : <Wifi className="h-4 w-4" />}
                Test Connection
              </button>
              {testResult && (
                <div className={`flex items-center gap-2 text-sm ${testResult.success ? 'text-green-600' : 'text-red-500'}`}>
                  {testResult.success ? <Check className="h-4 w-4" /> : <AlertCircle className="h-4 w-4" />}
                  {testResult.message}
                </div>
              )}
            </div>
          </div>
        )}
      </div>

      {/* Section 2: Check-In Signature */}
      {enabled && (
        <div className="rounded-lg border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800 space-y-4">
          <h4 className="font-medium text-surface-900 dark:text-surface-100">Check-In Signature</h4>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            When a customer drops off a device, the terminal displays your repair agreement and captures their signature.
          </p>

          <Toggle
            checked={form.blockchyp_tc_enabled === 'true'}
            onChange={(v) => update('blockchyp_tc_enabled', v ? 'true' : 'false')}
            label="Require customer signature at check-in"
            description="The terminal will display terms and capture a signature after ticket creation"
          />

          {form.blockchyp_tc_enabled === 'true' && (
            <div className="space-y-4 mt-2 pl-2 border-l-2 border-blue-500/30">
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Agreement Title</label>
                <input
                  type="text"
                  value={form.blockchyp_tc_name}
                  onChange={(e) => update('blockchyp_tc_name', e.target.value)}
                  placeholder="Repair Agreement"
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
                />
              </div>
              <div>
                <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Terms & Conditions</label>
                <textarea
                  value={form.blockchyp_tc_content}
                  onChange={(e) => update('blockchyp_tc_content', e.target.value)}
                  rows={5}
                  placeholder="Enter the repair agreement text..."
                  className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800 resize-y"
                />
                <p className="text-xs text-surface-500 mt-1">This text will be displayed on the terminal screen for the customer to read and sign.</p>
              </div>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Signature Format</label>
                  <select
                    value={form.blockchyp_sig_format}
                    onChange={(e) => update('blockchyp_sig_format', e.target.value)}
                    className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
                  >
                    <option value="png">PNG</option>
                    <option value="jpg">JPG</option>
                  </select>
                </div>
                <div>
                  <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Signature Width (px)</label>
                  <input
                    type="number"
                    min={100}
                    max={1000}
                    value={form.blockchyp_sig_width}
                    onChange={(e) => update('blockchyp_sig_width', e.target.value)}
                    className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
                  />
                </div>
              </div>
            </div>
          )}
        </div>
      )}

      {/* Section 3: Payment Settings */}
      {enabled && (
        <div className="rounded-lg border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800 space-y-4">
          <h4 className="font-medium text-surface-900 dark:text-surface-100">Payment</h4>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Configure how the terminal handles card payments during checkout.
          </p>

          <Toggle
            checked={form.blockchyp_sig_required_payment === 'true'}
            onChange={(v) => update('blockchyp_sig_required_payment', v ? 'true' : 'false')}
            label="Require signature on payments"
            description="Prompt the customer to sign on the terminal after card authorization"
          />

          <Toggle
            checked={form.blockchyp_prompt_for_tip === 'true'}
            onChange={(v) => update('blockchyp_prompt_for_tip', v ? 'true' : 'false')}
            label="Prompt for tip on terminal"
            description="Show a tip selection screen before processing the payment"
          />

          <Toggle
            checked={form.blockchyp_auto_close_ticket === 'true'}
            onChange={(v) => update('blockchyp_auto_close_ticket', v ? 'true' : 'false')}
            label="Auto-close ticket after successful payment"
            description="Automatically set the ticket status to Closed when payment is approved"
          />
        </div>
      )}

      {/* Section 4: Signature Terms (displayed on terminal) */}
      {enabled && (
        <div className="rounded-lg border border-surface-200 bg-white p-6 dark:border-surface-700 dark:bg-surface-800 space-y-4">
          <h4 className="font-medium text-surface-900 dark:text-surface-100">Signature & Terms Text</h4>
          <p className="text-sm text-surface-500 dark:text-surface-400">
            Text displayed on the terminal during signature capture and on printed receipts/invoices.
          </p>

          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Signature Terms</label>
            <textarea
              value={form.invoice_signature_terms ?? ''}
              onChange={(e) => update('invoice_signature_terms', e.target.value)}
              rows={2}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
              placeholder="I agree to the terms..."
            />
            <p className="mt-1 text-xs text-surface-400">Displayed on the terminal signature line</p>
          </div>

          <div>
            <label className="block text-sm font-medium text-surface-700 dark:text-surface-300 mb-1">Refund Signature Terms</label>
            <textarea
              value={form.invoice_refund_terms ?? ''}
              onChange={(e) => update('invoice_refund_terms', e.target.value)}
              rows={2}
              className="w-full rounded-lg border border-surface-300 bg-surface-50 px-3 py-2 text-sm dark:border-surface-600 dark:bg-surface-800"
              placeholder="Refund policy terms..."
            />
            <p className="mt-1 text-xs text-surface-400">Displayed on the terminal for refund signature capture</p>
          </div>
        </div>
      )}
    </div>
  );
}
