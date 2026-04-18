/**
 * TechCard — "John is handling your repair" with avatar.
 *
 * Two privacy gates: the global `portal_show_tech` toggle AND each tech's
 * per-user `portal_tech_visible` opt-in. If either is false, the backend
 * returns `visible: false` and this renders nothing.
 */
import React, { useEffect, useState } from 'react';
import { getTech, type TechData } from './enrichApi';
import { usePortalI18n } from '../i18n';

interface TechCardProps {
  ticketId: number;
}

export function TechCard({ ticketId }: TechCardProps): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [tech, setTech] = useState<TechData | null>(null);

  useEffect(() => {
    let cancelled = false;
    getTech(ticketId)
      .then((data) => {
        if (!cancelled) setTech(data);
      })
      .catch(() => {
        if (!cancelled) setTech({ visible: false });
      });
    return () => {
      cancelled = true;
    };
  }, [ticketId]);

  if (!tech || !tech.visible || !tech.first_name) return null;

  const initials = tech.first_name.slice(0, 1).toUpperCase();

  return (
    <section
      aria-label={t('tech.title')}
      className="rounded-lg bg-white dark:bg-gray-800 border border-gray-200 dark:border-gray-700 p-4 flex items-center gap-3"
    >
      {tech.avatar_url ? (
        <img
          src={tech.avatar_url}
          alt={`${tech.first_name} avatar`}
          className="w-12 h-12 rounded-full object-cover border-2 border-primary-200 dark:border-primary-900"
        />
      ) : (
        <div
          aria-hidden="true"
          className="w-12 h-12 rounded-full bg-primary-100 dark:bg-primary-900 text-primary-700 dark:text-primary-200 flex items-center justify-center font-semibold text-lg border-2 border-primary-200 dark:border-primary-800"
        >
          {initials}
        </div>
      )}
      <div>
        <div className="text-xs text-gray-500 dark:text-gray-400 uppercase tracking-wide">
          {t('tech.title')}
        </div>
        <div className="text-sm font-medium text-gray-900 dark:text-gray-100">
          {t('tech.handling', { name: tech.first_name })}
        </div>
      </div>
    </section>
  );
}
