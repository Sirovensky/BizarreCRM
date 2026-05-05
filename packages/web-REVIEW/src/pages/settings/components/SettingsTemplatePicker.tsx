/**
 * SettingsTemplatePicker — installs a starter template for the chosen shop
 * type. Reuses the onboarding agent's `set-shop-type` endpoint so the server
 * stays the single source of truth for what "phone repair" or "computer
 * repair" actually means.
 *
 * Why a settings-tab component instead of a wizard step?
 *   - New shops can run the setup wizard once. Existing shops that decide to
 *     change their focus later (e.g. a phone shop that adds TV repair) need
 *     a way to install a fresh template bundle from inside Settings.
 *   - Idempotency: the server uses `INSERT OR IGNORE` on name, so re-applying
 *     a template on an already-configured shop is safe. We still show a
 *     confirm prompt to avoid surprise.
 *
 * The picker is intentionally tiny — it delegates all heavy lifting to the
 * server and only renders 4 cards.
 */

import { useState } from 'react';
import {
  Smartphone,
  Laptop,
  Watch,
  Cpu,
  Loader2,
  CheckCircle2,
} from 'lucide-react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import toast from 'react-hot-toast';
import {
  onboardingApi,
  type OnboardingShopType,
} from '@/api/endpoints';
import { cn } from '@/utils/cn';

interface TemplateOption {
  id: OnboardingShopType;
  label: string;
  description: string;
  icon: typeof Smartphone;
}

const TEMPLATE_OPTIONS: TemplateOption[] = [
  {
    id: 'phone_repair',
    label: 'Phone Repair',
    description: 'Screen, battery, and charge-port SMS templates tuned for phone shops.',
    icon: Smartphone,
  },
  {
    id: 'computer_repair',
    label: 'Computer Repair',
    description: 'Diagnostic, pickup, and parts-on-order templates for computer shops.',
    icon: Laptop,
  },
  {
    id: 'watch_repair',
    label: 'Watch Repair',
    description: 'Watch-specific battery, crystal, and water-resistance messages.',
    icon: Watch,
  },
  {
    id: 'general_electronics',
    label: 'General Electronics',
    description: 'Broad repair-shop templates covering a mix of device types.',
    icon: Cpu,
  },
];

export interface SettingsTemplatePickerProps {
  /** Optional className for layout inside the host tab */
  className?: string;
  /** Called after a successful install so the parent can refresh counts */
  onInstalled?: (shopType: OnboardingShopType) => void;
}

export function SettingsTemplatePicker({
  className,
  onInstalled,
}: SettingsTemplatePickerProps) {
  const queryClient = useQueryClient();
  const [confirmingId, setConfirmingId] = useState<OnboardingShopType | null>(null);

  // Fetch current onboarding state so we can show which template (if any) is
  // already installed. Cached — no network request unless stale.
  const { data: stateRes } = useQuery({
    queryKey: ['onboarding', 'state'],
    queryFn: () => onboardingApi.getState(),
    staleTime: 60_000,
  });
  const currentShopType =
    (stateRes as unknown as { data?: { data?: { shop_type?: OnboardingShopType | null } } })
      ?.data?.data?.shop_type ?? null;

  const mutation = useMutation({
    mutationFn: (shopType: OnboardingShopType) => onboardingApi.setShopType(shopType),
    onSuccess: (_, shopType) => {
      queryClient.invalidateQueries({ queryKey: ['onboarding', 'state'] });
      queryClient.invalidateQueries({ queryKey: ['sms-templates'] });
      toast.success(`Installed "${labelFor(shopType)}" starter template`);
      setConfirmingId(null);
      onInstalled?.(shopType);
    },
    onError: () => {
      toast.error('Failed to install template');
      setConfirmingId(null);
    },
  });

  function handlePick(option: TemplateOption) {
    if (confirmingId === option.id) {
      mutation.mutate(option.id);
      return;
    }
    setConfirmingId(option.id);
  }

  return (
    <div
      className={cn(
        'rounded-xl border border-surface-200 bg-white p-4 dark:border-surface-700 dark:bg-surface-800/60',
        className
      )}
    >
      <header className="mb-3">
        <h4 className="text-sm font-semibold text-surface-900 dark:text-surface-100">
          Starter Templates
        </h4>
        <p className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">
          Install a curated bundle of SMS templates tuned for your shop type. Safe to
          re-run — existing templates with the same name are kept intact.
        </p>
      </header>

      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {TEMPLATE_OPTIONS.map((opt) => (
          <TemplateCard
            key={opt.id}
            option={opt}
            isCurrent={currentShopType === opt.id}
            isConfirming={confirmingId === opt.id}
            isRunning={mutation.isPending && confirmingId === opt.id}
            onClick={() => handlePick(opt)}
          />
        ))}
      </div>

      {confirmingId && !mutation.isPending && (
        <p className="mt-3 text-center text-xs text-surface-500">
          Click again to install. Existing data is not touched.
          <button
            type="button"
            onClick={() => setConfirmingId(null)}
            className="ml-2 text-primary-600 hover:underline"
          >
            cancel
          </button>
        </p>
      )}
    </div>
  );
}

interface TemplateCardProps {
  option: TemplateOption;
  isCurrent: boolean;
  isConfirming: boolean;
  isRunning: boolean;
  onClick: () => void;
}

function TemplateCard({
  option,
  isCurrent,
  isConfirming,
  isRunning,
  onClick,
}: TemplateCardProps) {
  const Icon = option.icon;
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={isRunning}
      className={cn(
        'flex items-start gap-2 rounded-lg border p-3 text-left transition-colors',
        'bg-surface-50 hover:border-primary-300 hover:bg-primary-50/50 dark:bg-surface-800 dark:hover:border-primary-500/50 dark:hover:bg-primary-500/10',
        isConfirming
          ? 'border-primary-500 ring-2 ring-primary-500/20'
          : 'border-surface-200 dark:border-surface-700',
        isRunning && 'opacity-50'
      )}
    >
      <div
        className={cn(
          'flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg',
          'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-300'
        )}
      >
        {isRunning ? <Loader2 className="h-4 w-4 animate-spin" /> : <Icon className="h-4 w-4" />}
      </div>
      <div className="min-w-0 flex-1">
        <p className="flex items-center gap-1 text-sm font-medium text-surface-900 dark:text-surface-100">
          {option.label}
          {isCurrent && (
            <CheckCircle2 className="h-3 w-3 text-green-600" aria-label="Currently installed" />
          )}
        </p>
        <p className="mt-0.5 text-[11px] text-surface-500 dark:text-surface-400">
          {option.description}
        </p>
        {isConfirming && !isRunning && (
          <p className="mt-1 text-[11px] font-semibold text-primary-600">
            Click again to install
          </p>
        )}
      </div>
    </button>
  );
}

function labelFor(id: OnboardingShopType): string {
  return TEMPLATE_OPTIONS.find((o) => o.id === id)?.label ?? id;
}
