/**
 * QueuePosition — "You're 4th in line; ETA 3-4h"
 *
 * Respects the store's `portal_queue_mode` setting (none | phones | all).
 * When the server returns enabled=false, this component renders nothing
 * so store owners can hide the feature for non-phone repairs where ETAs
 * are unreliable.
 */
import React, { useEffect, useState } from 'react';
import { getQueuePosition, type QueueData } from './enrichApi';
import { usePortalI18n } from '../i18n';

interface QueuePositionProps {
  ticketId: number;
}

function ordinal(n: number): string {
  const s = ['th', 'st', 'nd', 'rd'];
  const v = n % 100;
  return n + (s[(v - 20) % 10] || s[v] || s[0]);
}

export function QueuePosition({ ticketId }: QueuePositionProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [queue, setQueue] = useState<QueueData | null>(null);

  useEffect(() => {
    let cancelled = false;
    getQueuePosition(ticketId)
      .then((data) => {
        if (!cancelled) setQueue(data);
      })
      .catch(() => {
        if (!cancelled) setQueue({ enabled: false });
      });
    return () => {
      cancelled = true;
    };
  }, [ticketId]);

  if (!queue) return null;
  if (!queue.enabled) return null;

  if (queue.closed || queue.position === 0) {
    return (
      <div
        role="status"
        className="rounded-lg bg-green-50 dark:bg-green-900/30 border border-green-200 dark:border-green-800 p-3 text-sm text-green-800 dark:text-green-200"
      >
        {t('queue.closed')}
      </div>
    );
  }

  if (queue.position === undefined) return null;

  return (
    <div
      role="status"
      aria-live="polite"
      className="rounded-lg bg-blue-50 dark:bg-blue-900/30 border border-blue-200 dark:border-blue-800 p-3"
    >
      <div className="text-sm font-medium text-blue-900 dark:text-blue-100">
        {t('queue.position', { n: ordinal(queue.position) })}
      </div>
      {queue.eta_hours_min !== undefined && queue.eta_hours_max !== undefined ? (
        <div className="text-xs text-blue-700 dark:text-blue-300 mt-1">
          {t('queue.eta', {
            min: queue.eta_hours_min,
            max: queue.eta_hours_max,
          })}
        </div>
      ) : null}
    </div>
  );
}
