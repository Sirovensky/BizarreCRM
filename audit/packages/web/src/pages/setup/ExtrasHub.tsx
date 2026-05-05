import { useState } from 'react';
import {
  Clock,
  Calculator,
  Image as ImageIcon,
  Receipt,
  Download,
  MessageSquare,
  MessageSquareText,
  Mail,
  ArrowLeft,
  ChevronDown,
  ChevronUp,
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

/**
 * Primary extras — the 4 most common first-run configurations, always visible
 * in the hub. Picked for: (a) highest chance of being relevant to a typical
 * repair shop, (b) quickest to configure, (c) biggest immediate UX impact.
 */
const PRIMARY_CARDS: HubCard[] = [
  {
    id: 'notifications',
    title: 'Customer Notifications',
    description: 'Pick which ticket statuses auto-SMS the customer.',
    estMinutes: '~1 min',
    Icon: MessageSquareText,
  },
  {
    id: 'hours',
    title: 'Business Hours',
    description: 'Weekly schedule — drives off-hours SMS auto-replies.',
    estMinutes: '~30 sec',
    Icon: Clock,
  },
  {
    id: 'tax',
    title: 'Tax Rates',
    description: 'Primary tax rate applied to invoices by default.',
    estMinutes: '~30 sec',
    Icon: Calculator,
  },
  {
    id: 'logo',
    title: 'Logo & Branding',
    description: 'Upload your logo and pick an accent color.',
    estMinutes: '~1 min',
    Icon: ImageIcon,
  },
  {
    id: 'import',
    title: 'Import Existing Data',
    description: 'Migrate from RepairDesk, RepairShopr, or MyRepairApp.',
    estMinutes: '2-30 min',
    Icon: Download,
  },
];

/**
 * Secondary extras — less common, hidden behind "Show more options" so the
 * hub fits in one viewport without scrolling. These tend to either (a) need
 * external accounts (SMS providers, SMTP server) or (b) be pure customization
 * the user can come back to later (receipt text).
 */
const SECONDARY_CARDS: HubCard[] = [
  {
    id: 'receipts',
    title: 'Receipt Layout',
    description: 'Customize header and footer on thermal + A4 receipts.',
    estMinutes: '~1 min',
    Icon: Receipt,
  },
  {
    id: 'sms',
    title: 'SMS Notifications',
    description: 'Connect Twilio, Telnyx, Bandwidth, Plivo, or Vonage.',
    estMinutes: '~2 min',
    Icon: MessageSquare,
  },
  {
    id: 'email',
    title: 'Email (SMTP)',
    description: 'Outgoing mail for receipts and customer notifications.',
    estMinutes: '~1 min',
    Icon: Mail,
  },
];

const ALL_CARDS = [...PRIMARY_CARDS, ...SECONDARY_CARDS];
const TOTAL_COUNT = ALL_CARDS.length;

/**
 * Extras Hub — the non-linear card grid where users pick optional
 * configurations to go through. Primary cards (4) are always visible; the
 * remaining 3 are hidden behind a "Show more options" toggle so the hub
 * fits in one viewport without scrolling on a typical desktop.
 *
 * Each card opens a sub-step; completed cards get a green checkmark badge
 * and an "Edit" button instead of "Configure". The finish CTA label changes
 * based on how many cards have been completed.
 */
export function ExtrasHub({ completedCards, onOpenCard, onFinish, onBack }: ExtrasHubProps) {
  // If any secondary card is already completed (e.g. user opened it, went
  // back, came forward again), auto-expand the secondary section so they see
  // their progress without hunting for the toggle.
  const hasCompletedSecondary = SECONDARY_CARDS.some((c) => completedCards.has(c.id));
  const [showMore, setShowMore] = useState(hasCompletedSecondary);

  const completedCount = completedCards.size;
  const finishLabel =
    completedCount === 0
      ? "I'm all set — take me to the dashboard"
      : completedCount < TOTAL_COUNT
      ? 'Finish setup and go to dashboard'
      : 'All done — enter dashboard';

  return (
    <div className="mx-auto max-w-5xl">
      <div className="mb-4 text-center">
        <h2 className="font-['League_Spartan'] text-2xl font-bold tracking-wide text-surface-900 dark:text-surface-50 sm:text-3xl">
          What else would you like to set up?
        </h2>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          Optional — pick what you want now, do the rest later in Settings.
        </p>
        {completedCount > 0 && (
          <p className="mt-1 text-xs text-surface-400 dark:text-surface-500">
            {completedCount} of {TOTAL_COUNT} extras configured
          </p>
        )}
      </div>

      {/* Primary card grid — always visible */}
      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        {PRIMARY_CARDS.map((card) => (
          <HubCardButton key={card.id} card={card} done={completedCards.has(card.id)} onOpen={onOpenCard} />
        ))}
      </div>

      {/* Show-more toggle + secondary cards */}
      <div className="mt-4">
        <button
          type="button"
          onClick={() => setShowMore((s) => !s)}
          className="mx-auto flex items-center gap-1.5 rounded-full border border-surface-200 bg-white px-4 py-1.5 text-xs font-medium text-surface-600 shadow-sm transition-colors hover:border-surface-300 hover:bg-surface-50 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-300 dark:hover:border-surface-600 dark:hover:bg-surface-700"
        >
          {showMore ? (
            <>
              <ChevronUp className="h-3.5 w-3.5" />
              Hide extra options
            </>
          ) : (
            <>
              <ChevronDown className="h-3.5 w-3.5" />
              Show {SECONDARY_CARDS.length} more options
            </>
          )}
        </button>

        {showMore && (
          <div className="mt-3 grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {SECONDARY_CARDS.map((card) => (
              <HubCardButton key={card.id} card={card} done={completedCards.has(card.id)} onOpen={onOpenCard} />
            ))}
          </div>
        )}
      </div>

      {/* Bottom CTAs */}
      <div className="mt-6 flex flex-col items-center gap-3">
        <button
          type="button"
          onClick={onFinish}
          className={`flex items-center gap-2 rounded-xl px-8 py-3.5 text-sm font-semibold shadow-lg transition-colors ${
            completedCount === TOTAL_COUNT
              ? 'bg-green-600 text-white hover:bg-green-700'
              : 'bg-primary-600 text-primary-950 hover:bg-primary-700'
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

/**
 * Individual hub card — shared between primary and secondary grids.
 * Compact design: reduced padding, smaller icon, single-line description
 * so all 7 cards fit comfortably in one viewport when expanded.
 */
function HubCardButton({
  card,
  done,
  onOpen,
}: {
  card: HubCard;
  done: boolean;
  onOpen: (id: ExtraCardId) => void;
}) {
  const { id, title, description, estMinutes, Icon } = card;
  return (
    <button
      type="button"
      onClick={() => onOpen(id)}
      className={`group relative flex h-full flex-col items-start rounded-xl border-2 bg-white p-4 text-left shadow-sm transition-all hover:shadow-md dark:bg-surface-800 ${
        done
          ? 'border-green-400 dark:border-green-500/60'
          : 'border-surface-200 hover:border-primary-300 dark:border-surface-700 dark:hover:border-primary-500/50'
      }`}
    >
      {/* Badge in the top-right */}
      <div className="absolute right-3 top-3">
        {done ? (
          <div className="flex h-5 w-5 items-center justify-center rounded-full bg-green-500 text-white">
            <Check className="h-3 w-3" />
          </div>
        ) : (
          <span className="rounded-full bg-surface-100 px-2 py-0.5 text-[10px] font-medium text-surface-500 dark:bg-surface-700 dark:text-surface-400">
            {estMinutes}
          </span>
        )}
      </div>

      {/* Icon + title row */}
      <div className="flex items-center gap-2.5">
        <div
          className={`flex h-8 w-8 flex-shrink-0 items-center justify-center rounded-lg ${
            done
              ? 'bg-green-100 dark:bg-green-500/10'
              : 'bg-primary-100 dark:bg-primary-500/10'
          }`}
        >
          <Icon
            className={`h-4 w-4 ${
              done ? 'text-green-600 dark:text-green-400' : 'text-primary-600 dark:text-primary-400'
            }`}
          />
        </div>
        <h3 className="font-['League_Spartan'] text-base font-bold tracking-wide text-surface-900 dark:text-surface-50">
          {title}
        </h3>
      </div>

      {/* Description — clamped to 2 lines so tall descriptions don't bloat the card */}
      <p className="mt-2 line-clamp-2 flex-1 text-xs text-surface-500 dark:text-surface-400">
        {description}
      </p>

      {/* Action label */}
      <span
        className={`mt-2.5 inline-flex items-center gap-1 rounded-full px-2.5 py-0.5 text-[11px] font-semibold transition-colors ${
          done
            ? 'bg-green-100 text-green-700 dark:bg-green-500/20 dark:text-green-300'
            : 'bg-primary-100 text-primary-700 group-hover:bg-primary-200 dark:bg-primary-500/20 dark:text-primary-300'
        }`}
      >
        {done ? 'Edit' : 'Configure'}
      </span>
    </button>
  );
}
