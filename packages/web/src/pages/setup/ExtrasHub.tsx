import {
  Clock,
  Calculator,
  Image as ImageIcon,
  Receipt,
  Download,
  MessageSquare,
  Mail,
  ArrowLeft,
  Check,
} from 'lucide-react';
import type { ExtraCardId } from './wizardTypes';

interface ExtrasHubProps {
  completedCards: Set<ExtraCardId>;
  onOpenCard: (card: ExtraCardId) => void;
  onFinish: () => void;
  onBack: () => void;
}

interface HubCard {
  id: ExtraCardId;
  title: string;
  description: string;
  estMinutes: string;
  Icon: typeof Clock;
}

const CARDS: HubCard[] = [
  {
    id: 'hours',
    title: 'Business Hours',
    description: 'Set your weekly schedule so off-hours auto-replies work correctly.',
    estMinutes: '~30 sec',
    Icon: Clock,
  },
  {
    id: 'tax',
    title: 'Tax Rates',
    description: 'Add a primary tax rate to apply to invoices by default.',
    estMinutes: '~30 sec',
    Icon: Calculator,
  },
  {
    id: 'logo',
    title: 'Logo & Branding',
    description: 'Upload a logo and optionally pick an accent color for your shop.',
    estMinutes: '~1 min',
    Icon: ImageIcon,
  },
  {
    id: 'receipts',
    title: 'Receipt Layout',
    description: "Customize the header and footer text on thermal and A4 receipts.",
    estMinutes: '~1 min',
    Icon: Receipt,
  },
  {
    id: 'import',
    title: 'Import Existing Data',
    description: 'Migrate customers, tickets, and inventory from RepairDesk, RepairShopr, or MyRepairApp.',
    estMinutes: '2-30 min',
    Icon: Download,
  },
  {
    id: 'sms',
    title: 'SMS Notifications',
    description: 'Connect Twilio, Telnyx, Bandwidth, Plivo, or Vonage for automated SMS.',
    estMinutes: '~2 min',
    Icon: MessageSquare,
  },
  {
    id: 'email',
    title: 'Email (SMTP)',
    description: 'Configure outgoing mail for receipts and customer notifications.',
    estMinutes: '~1 min',
    Icon: Mail,
  },
];

/**
 * Extras Hub — the non-linear card grid where users pick optional
 * configurations to go through. Each card opens a sub-step; completed cards
 * get a green checkmark badge and an "Edit" button instead of "Configure".
 * The finish CTA label changes based on how many cards have been completed.
 */
export function ExtrasHub({ completedCards, onOpenCard, onFinish, onBack }: ExtrasHubProps) {
  const completedCount = completedCards.size;
  const totalCount = CARDS.length;

  const finishLabel =
    completedCount === 0
      ? "I'm all set — take me to the dashboard"
      : completedCount < totalCount
      ? 'Finish setup and go to dashboard'
      : 'All done — enter dashboard';

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-6 text-center">
        <h2 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          What else would you like to set up?
        </h2>
        <p className="mt-2 text-sm text-surface-500 dark:text-surface-400">
          These are optional. Pick what you want to configure now — you can always do the rest later in Settings.
        </p>
        {completedCount > 0 && (
          <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
            {completedCount} of {totalCount} extras configured
          </p>
        )}
      </div>

      {/* Card grid */}
      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {CARDS.map(({ id, title, description, estMinutes, Icon }) => {
          const done = completedCards.has(id);
          return (
            <button
              key={id}
              type="button"
              onClick={() => onOpenCard(id)}
              className={`group relative flex h-full flex-col items-start rounded-2xl border-2 bg-white p-6 text-left shadow-sm transition-all hover:shadow-md dark:bg-surface-800 ${
                done
                  ? 'border-green-400 dark:border-green-500/60'
                  : 'border-surface-200 hover:border-primary-300 dark:border-surface-700 dark:hover:border-primary-500/50'
              }`}
            >
              {/* Badge in the top-right */}
              <div className="absolute right-4 top-4">
                {done ? (
                  <div className="flex h-6 w-6 items-center justify-center rounded-full bg-green-500 text-white">
                    <Check className="h-4 w-4" />
                  </div>
                ) : (
                  <span className="rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-medium text-surface-500 dark:bg-surface-700 dark:text-surface-400">
                    {estMinutes}
                  </span>
                )}
              </div>

              {/* Icon */}
              <div
                className={`mb-3 flex h-11 w-11 items-center justify-center rounded-xl ${
                  done
                    ? 'bg-green-100 dark:bg-green-500/10'
                    : 'bg-primary-100 dark:bg-primary-500/10'
                }`}
              >
                <Icon
                  className={`h-5 w-5 ${
                    done ? 'text-green-600 dark:text-green-400' : 'text-primary-600 dark:text-primary-400'
                  }`}
                />
              </div>

              {/* Title + description */}
              <h3 className="font-['League_Spartan'] text-lg font-bold tracking-wide text-surface-900 dark:text-surface-50">
                {title}
              </h3>
              <p className="mt-1 flex-1 text-xs text-surface-500 dark:text-surface-400">
                {description}
              </p>

              {/* Action pill */}
              <span
                className={`mt-4 inline-flex items-center gap-1 rounded-full px-3 py-1 text-xs font-semibold transition-colors ${
                  done
                    ? 'bg-green-100 text-green-700 dark:bg-green-500/20 dark:text-green-300'
                    : 'bg-primary-100 text-primary-700 group-hover:bg-primary-200 dark:bg-primary-500/20 dark:text-primary-300'
                }`}
              >
                {done ? 'Edit' : 'Configure'}
              </span>
            </button>
          );
        })}
      </div>

      {/* Bottom CTAs */}
      <div className="mt-8 flex flex-col items-center gap-4">
        <button
          type="button"
          onClick={onFinish}
          className={`flex items-center gap-2 rounded-xl px-8 py-4 text-sm font-semibold shadow-lg transition-colors ${
            completedCount === totalCount
              ? 'bg-green-600 text-white hover:bg-green-700'
              : 'bg-primary-600 text-white hover:bg-primary-700'
          }`}
        >
          {finishLabel}
        </button>
        <button
          type="button"
          onClick={onBack}
          className="flex items-center gap-1 text-xs font-medium text-surface-500 hover:text-surface-900 dark:text-surface-400 dark:hover:text-surface-100"
        >
          <ArrowLeft className="h-3 w-3" />
          Back to trial info
        </button>
      </div>
    </div>
  );
}
