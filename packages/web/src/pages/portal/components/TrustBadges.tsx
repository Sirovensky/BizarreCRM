/**
 * TrustBadges — encrypted-connection badge, shop address, hours, phone,
 * optional SLA guarantee banner. Shown near the top of the portal to build
 * confidence before the customer scrolls to payment / personal info.
 */
import React, { useEffect, useState } from 'react';
import { getPortalConfig, type PortalConfig } from './enrichApi';
import { usePortalI18n } from '../i18n';

export function TrustBadges(): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [config, setConfig] = useState<PortalConfig | null>(null);

  useEffect(() => {
    let cancelled = false;
    getPortalConfig()
      .then((data) => {
        if (!cancelled) setConfig(data);
      })
      .catch(() => {
        if (!cancelled) setConfig({});
      });
    return () => {
      cancelled = true;
    };
  }, []);

  if (!config) return null;

  const address = [
    config.store_address,
    config.store_city,
    config.store_state,
    config.store_zip,
  ]
    .filter(Boolean)
    .join(', ');

  const showSla = (config.portal_sla_enabled || 'true') === 'true';
  const slaMessage = config.portal_sla_message || t('sla.default');

  return (
    <section
      aria-label="Shop information and trust badges"
      className="rounded-lg bg-gradient-to-br from-gray-50 to-blue-50 dark:from-gray-800 dark:to-blue-900/30 border border-gray-200 dark:border-gray-700 p-4 space-y-3"
    >
      {showSla && slaMessage ? (
        <div className="text-xs font-medium text-blue-800 dark:text-blue-200 flex items-center gap-2">
          <span aria-hidden="true">{'\u2713'}</span>
          {slaMessage}
        </div>
      ) : null}

      <div className="flex flex-wrap gap-2 text-[11px]">
        <span className="inline-flex items-center gap-1 rounded-full bg-green-100 dark:bg-green-900/50 text-green-800 dark:text-green-200 px-2 py-1 font-medium">
          <span aria-hidden="true">{'\u{1F512}'}</span>
          {t('trust.ssl')}
        </span>
        <span className="inline-flex items-center gap-1 rounded-full bg-blue-100 dark:bg-blue-900/50 text-blue-800 dark:text-blue-200 px-2 py-1 font-medium">
          <span aria-hidden="true">{'\u{1F4B3}'}</span>
          {t('trust.pci')}
        </span>
      </div>

      <dl className="text-xs text-gray-700 dark:text-gray-300 space-y-1">
        {address ? (
          <div className="flex gap-2">
            <dt className="font-medium w-14">{t('trust.address')}</dt>
            <dd className="flex-1">{address}</dd>
          </div>
        ) : null}
        {config.store_phone ? (
          <div className="flex gap-2">
            <dt className="font-medium w-14">{t('trust.phone')}</dt>
            <dd className="flex-1">
              <a
                href={`tel:${config.store_phone}`}
                className="text-blue-700 dark:text-blue-300 hover:underline"
              >
                {config.store_phone}
              </a>
            </dd>
          </div>
        ) : null}
        {config.store_hours ? (
          <div className="flex gap-2">
            <dt className="font-medium w-14">{t('trust.hours')}</dt>
            <dd className="flex-1">{config.store_hours}</dd>
          </div>
        ) : null}
      </dl>
    </section>
  );
}
