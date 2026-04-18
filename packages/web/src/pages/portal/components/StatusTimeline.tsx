/**
 * StatusTimeline — vertical timeline of ticket_history status events.
 * Replaces the sparse "status + progress bar" view with a live story.
 *
 * Shows the timeline in the user's current locale, uses ARIA list semantics
 * for screen readers, and degrades gracefully on older browsers (no CSS
 * grid). Empty state hides the component entirely so it never shows a
 * blank box when ticket_history is empty.
 */
import React, { useEffect, useState } from 'react';
import { getTimeline, type TimelineEvent } from './enrichApi';
import { usePortalI18n } from '../i18n';

interface StatusTimelineProps {
  ticketId: number;
}

function formatTime(at: string): string {
  try {
    // SQLite stores UTC strings without a TZ suffix — append Z for correct parsing.
    const iso = at.includes('T') ? at : at.replace(' ', 'T');
    const stamped = iso.endsWith('Z') || iso.includes('+') ? iso : iso + 'Z';
    return new Date(stamped).toLocaleString(undefined, {
      month: 'short',
      day: 'numeric',
      hour: 'numeric',
      minute: '2-digit',
    });
  } catch {
    return at;
  }
}

export function StatusTimeline({ ticketId }: StatusTimelineProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [events, setEvents] = useState<TimelineEvent[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    getTimeline(ticketId)
      .then((data) => {
        if (!cancelled) setEvents(data.events);
      })
      .catch((err: unknown) => {
        if (!cancelled) {
          const message = err instanceof Error ? err.message : 'Failed to load timeline';
          setError(message);
        }
      });
    return () => {
      cancelled = true;
    };
  }, [ticketId]);

  if (error) return null;
  if (events === null) {
    return (
      <section aria-busy="true" className="rounded-lg bg-gray-50 dark:bg-gray-800 p-4">
        <div className="text-sm text-gray-400 dark:text-gray-500">{t('portal.loading')}</div>
      </section>
    );
  }
  if (events.length === 0) return null;

  return (
    <section
      aria-label={t('timeline.title')}
      className="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4"
    >
      <h3 className="text-sm font-semibold text-gray-900 dark:text-gray-100 mb-3">
        {t('timeline.title')}
      </h3>
      <ol className="relative border-l-2 border-primary-200 dark:border-primary-900 ml-2 space-y-4">
        {events.map((event, index) => {
          const isLast = index === events.length - 1;
          return (
            <li key={`${event.at}-${index}`} className="ml-4">
              <div
                className={`absolute w-3 h-3 rounded-full -left-[7px] border-2 border-white dark:border-gray-800 ${
                  isLast
                    ? 'bg-primary-600 dark:bg-primary-400 ring-2 ring-primary-200 dark:ring-primary-800'
                    : 'bg-gray-300 dark:bg-gray-600'
                }`}
                aria-hidden="true"
              />
              <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
                {event.label}
              </div>
              <time className="text-xs text-gray-500 dark:text-gray-400">
                {formatTime(event.at)}
              </time>
            </li>
          );
        })}
      </ol>
    </section>
  );
}
