/**
 * SetupProgressTab — the "did you actually finish configuring your shop?"
 * checklist that lives at the front of the settings page. Reads the
 * onboarding state from the server and cross-references it with the store
 * config so each checklist item reflects reality instead of a local flag.
 *
 * Each item has a "Go" button that navigates to the appropriate tab. This
 * eliminates the "where do I go to fix this?" paper cut from the audit.
 */

import { useMemo } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  CheckCircle2,
  Circle,
  ArrowRight,
  Store,
  Receipt,
  CreditCard,
  Users,
  Ticket,
  MessageSquare,
  Rocket,
  Loader2,
  AlertTriangle,
} from 'lucide-react';
import { settingsApi, onboardingApi, type OnboardingState } from '@/api/endpoints';
import { cn } from '@/utils/cn';

export interface SetupProgressTabProps {
  /** Navigate to a settings tab by key. Parent passes its setActiveTab. */
  onNavigateTab: (tab: string) => void;
}

interface ChecklistItem {
  id: string;
  title: string;
  description: string;
  icon: typeof Store;
  completed: boolean;
  tab: string;
  critical: boolean;
}

export function SetupProgressTab({ onNavigateTab }: SetupProgressTabProps) {
  // Onboarding state (first ticket, first invoice, etc.)
  const { data: onboardingRes, isLoading: obLoading } = useQuery({
    queryKey: ['onboarding', 'state'],
    queryFn: () => onboardingApi.getState(),
    staleTime: 15_000,
  });

  // Store config for store name, tax rate presence, payment methods, etc
  const { data: store = {}, isLoading: storeLoading } = useQuery({
    queryKey: ['settings', 'store'],
    queryFn: async () => {
      const res = await settingsApi.getStore();
      return (res.data?.data ?? {}) as Record<string, string>;
    },
    staleTime: 15_000,
  });

  // Tax classes — checkmark if at least one is configured
  const { data: taxClasses = [] } = useQuery({
    queryKey: ['settings', 'tax-classes'],
    queryFn: async () => {
      const res = await settingsApi.getTaxClasses();
      return (res.data?.data ?? []) as Array<{ id: number; rate: number }>;
    },
    staleTime: 30_000,
  });

  // Payment methods — checkmark if at least one exists
  const { data: paymentMethods = [] } = useQuery({
    queryKey: ['settings', 'payment-methods'],
    queryFn: async () => {
      const res = await settingsApi.getPaymentMethods();
      return (res.data?.data ?? []) as Array<{ id: number }>;
    },
    staleTime: 30_000,
  });

  // Users — checkmark if at least one active user exists. The admin counts.
  const { data: users = [] } = useQuery({
    queryKey: ['settings', 'users'],
    queryFn: async () => {
      const res = await settingsApi.getUsers();
      return (res.data?.data ?? []) as Array<{ id: number; role: string; is_active?: number }>;
    },
    staleTime: 30_000,
  });

  const onboarding = (onboardingRes?.data?.data ?? null) as OnboardingState | null;

  const items: ChecklistItem[] = useMemo(() => {
    const storeNameOk = !!store.store_name?.trim();
    const phoneOk = !!store.phone?.trim();
    const taxConfigured = taxClasses.length > 0;
    const paymentsConfigured = paymentMethods.length > 0;
    const activeUsers = users.filter((user) => user.is_active !== 0);
    const usersConfigured = activeUsers.length > 0;
    const firstTicketOk = !!onboarding?.first_ticket_at;
    const firstInvoiceOk = !!onboarding?.first_invoice_at;
    const shopTypeOk = !!onboarding?.shop_type;

    return [
      {
        id: 'store-info',
        title: 'Store information',
        description: storeNameOk && phoneOk
          ? `Set: ${store.store_name}`
          : 'Add your shop name, phone, address, and hours.',
        icon: Store,
        completed: storeNameOk && phoneOk,
        tab: 'store',
        critical: true,
      },
      {
        id: 'shop-type',
        title: 'Shop type',
        description: shopTypeOk
          ? `Shop type: ${onboarding?.shop_type?.replace(/_/g, ' ')}`
          : 'Pick what kind of shop you run so we can tune defaults for you.',
        icon: Rocket,
        completed: shopTypeOk,
        tab: 'store',
        critical: false,
      },
      {
        id: 'tax-classes',
        title: 'Tax classes',
        description: taxConfigured
          ? `${taxClasses.length} tax ${taxClasses.length === 1 ? 'class' : 'classes'} configured`
          : 'Add at least one sales tax rate so invoices are correct.',
        icon: Receipt,
        completed: taxConfigured,
        tab: 'tax',
        critical: true,
      },
      {
        id: 'payment-methods',
        title: 'Payment methods',
        description: paymentsConfigured
          ? `${paymentMethods.length} payment methods enabled`
          : 'Enable the payment methods you accept (cash, card, etc.).',
        icon: CreditCard,
        completed: paymentsConfigured,
        tab: 'payment',
        critical: true,
      },
      {
        id: 'users',
        title: 'Team members',
        description: usersConfigured
          ? `${activeUsers.length} active user${activeUsers.length === 1 ? '' : 's'} including admin`
          : 'Create an active admin user.',
        icon: Users,
        completed: usersConfigured,
        tab: 'users',
        critical: false,
      },
      {
        id: 'first-ticket',
        title: 'Create your first ticket',
        description: firstTicketOk
          ? 'At least one ticket has been created.'
          : 'Once you create your first repair ticket, the rest of the CRM lights up.',
        icon: Ticket,
        completed: firstTicketOk,
        tab: 'tickets-repairs',
        critical: false,
      },
      {
        id: 'first-invoice',
        title: 'Create your first invoice',
        description: firstInvoiceOk
          ? 'You have created at least one invoice.'
          : 'Run a sale through POS or bill a ticket — this unlocks reports.',
        icon: Receipt,
        completed: firstInvoiceOk,
        tab: 'pos',
        critical: false,
      },
      {
        id: 'sms-provider',
        title: 'SMS provider',
        description: store.sms_provider_type && store.sms_provider_type !== 'console'
          ? `SMS via ${store.sms_provider_type}`
          : 'Connect Twilio or Telnyx so customer notifications actually send.',
        icon: MessageSquare,
        completed: !!store.sms_provider_type && store.sms_provider_type !== 'console',
        tab: 'sms-voice',
        critical: true,
      },
    ];
  }, [store, taxClasses, paymentMethods, users, onboarding]);

  const completedCount = items.filter((i) => i.completed).length;
  const totalCount = items.length;
  const criticalRemaining = items.filter((i) => i.critical && !i.completed).length;
  const percent = totalCount > 0 ? Math.round((completedCount / totalCount) * 100) : 0;

  const isLoading = obLoading || storeLoading;

  return (
    <div>
      {/* Hero card */}
      <div className="card overflow-hidden">
        <div className="border-b border-surface-100 p-4 dark:border-surface-800">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="flex items-center gap-2">
                <Rocket className="h-4 w-4 text-primary-500" />
                <h3 className="text-base font-semibold text-surface-900 dark:text-surface-100">
                  Setup Progress
                </h3>
              </div>
              <p className="mt-0.5 text-xs text-surface-500 dark:text-surface-400">
                Finish these to unlock the full CRM. Critical items affect invoices, receipts, and customer messaging.
              </p>
            </div>
            <div className="text-right">
              <div className="text-xl font-bold leading-6 text-primary-600 dark:text-primary-400">
                {completedCount}/{totalCount}
              </div>
              <div className="text-xs text-surface-400">complete</div>
            </div>
          </div>

          {/* Progress bar */}
          <div className="mt-3 h-1.5 w-full overflow-hidden rounded-full bg-surface-100 dark:bg-surface-800">
            <div
              className={cn(
                'h-full transition-all duration-500',
                percent === 100 ? 'bg-green-500' : 'bg-primary-500'
              )}
              style={{ width: `${percent}%` }}
            />
          </div>

          {criticalRemaining > 0 && (
            <div className="mt-2 flex items-center gap-2 rounded-md border border-amber-200 bg-amber-50 px-3 py-1.5 text-xs text-amber-700 dark:border-amber-500/40 dark:bg-amber-500/10 dark:text-amber-300">
              <AlertTriangle className="h-3.5 w-3.5 flex-shrink-0" />
              {criticalRemaining} critical {criticalRemaining === 1 ? 'item is' : 'items are'} still missing.
              Invoices and notifications may not work correctly until you finish them.
            </div>
          )}
        </div>

        {isLoading ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="h-6 w-6 animate-spin text-surface-400" />
          </div>
        ) : (
          <ul className="divide-y divide-surface-100 dark:divide-surface-800">
            {items.map((item) => (
              <SetupItem
                key={item.id}
                item={item}
                onGo={() => onNavigateTab(item.tab)}
              />
            ))}
          </ul>
        )}
      </div>
    </div>
  );
}

function SetupItem({
  item,
  onGo,
}: {
  item: ChecklistItem;
  onGo: () => void;
}) {
  const Icon = item.icon;
  return (
    <li className="flex items-center gap-3 px-4 py-2.5">
      <div
        className={cn(
          'flex h-7 w-7 flex-shrink-0 items-center justify-center rounded-full',
          item.completed
            ? 'bg-green-100 text-green-600 dark:bg-green-500/20 dark:text-green-300'
            : 'bg-surface-100 text-surface-500 dark:bg-surface-800 dark:text-surface-400'
        )}
      >
        {item.completed ? (
          <CheckCircle2 className="h-4 w-4" />
        ) : (
          <Circle className="h-4 w-4" />
        )}
      </div>
      <div className="min-w-0 flex-1">
        <div className="flex items-center gap-2">
          <Icon className="h-3.5 w-3.5 text-surface-400" />
          <p
            className={cn(
              'text-xs font-medium',
              item.completed
                ? 'text-surface-500 line-through dark:text-surface-500'
                : 'text-surface-900 dark:text-surface-100'
            )}
          >
            {item.title}
          </p>
          {item.critical && !item.completed && (
            <span className="rounded-full bg-red-100 px-1.5 py-0.5 text-[10px] font-semibold uppercase text-red-700 dark:bg-red-500/20 dark:text-red-300">
              Critical
            </span>
          )}
        </div>
        <p className="text-xs leading-4 text-surface-500 dark:text-surface-400">
          {item.description}
        </p>
      </div>
      <button
        type="button"
        onClick={onGo}
        className={cn(
          'inline-flex h-7 flex-shrink-0 items-center gap-1 rounded-md px-2.5 text-xs font-medium transition-colors',
          item.completed
            ? 'text-surface-500 hover:bg-surface-100 dark:text-surface-400 dark:hover:bg-surface-800'
            : 'bg-primary-600 text-primary-950 hover:bg-primary-700'
        )}
      >
        {item.completed ? 'Review' : 'Go'}
        <ArrowRight className="h-3 w-3" />
      </button>
    </li>
  );
}
