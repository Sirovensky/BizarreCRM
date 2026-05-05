import { useSentimentDetect } from '@/hooks/useSentimentDetect';
import type { Sentiment } from '@/hooks/useSentimentDetect';
import { cn } from '@/utils/cn';

/**
 * Sentiment badge — audit §51.5.
 *
 * Renders an emoji + label for an inbound message. Pure client-side keyword
 * classification via useSentimentDetect. Angry and urgent auto-flag to
 * priority by showing red/amber; happy is green, neutral is hidden.
 */

interface SentimentBadgeProps {
  text: string;
  className?: string;
  /** When true, neutral sentiment is still rendered (otherwise hidden) */
  showNeutral?: boolean;
  /** Compact mode hides the text label */
  compact?: boolean;
}

const EMOJI: Record<Sentiment, string> = {
  angry: 'angry',
  happy: 'happy',
  neutral: '—',
  urgent: 'urgent',
};

const LABEL: Record<Sentiment, string> = {
  angry: 'Angry',
  happy: 'Happy',
  neutral: 'Neutral',
  urgent: 'Urgent',
};

const COLOR: Record<Sentiment, string> = {
  angry: 'bg-red-100 text-red-700 dark:bg-red-900/30 dark:text-red-300',
  happy: 'bg-green-100 text-green-700 dark:bg-green-900/30 dark:text-green-300',
  neutral: 'bg-surface-100 text-surface-600 dark:bg-surface-700 dark:text-surface-400',
  urgent: 'bg-amber-100 text-amber-800 dark:bg-amber-900/30 dark:text-amber-300',
};

export function SentimentBadge({
  text,
  className,
  showNeutral = false,
  compact = false,
}: SentimentBadgeProps) {
  const { sentiment } = useSentimentDetect(text);
  if (sentiment === 'neutral' && !showNeutral) return null;

  return (
    <span
      title={`Sentiment: ${LABEL[sentiment]}`}
      className={cn(
        'inline-flex items-center gap-1 rounded-full px-2 py-0.5 text-[10px] font-medium',
        COLOR[sentiment],
        className,
      )}
    >
      <span aria-hidden className="text-[10px]">{EMOJI[sentiment]}</span>
      {!compact && <span>{LABEL[sentiment]}</span>}
    </span>
  );
}
