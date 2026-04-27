/**
 * TrustBadges — encrypted-connection badge, shop address, hours, phone,
 * optional SLA guarantee banner. Shown near the top of the portal to build
 * confidence before the customer scrolls to payment / personal info.
 */
import React, { useEffect, useState } from 'react';
import { getPortalConfig, type PortalConfig } from './enrichApi';
import { usePortalI18n } from '../i18n';
// WEB-FV-008 (Fixer-B21 2026-04-25): record a breadcrumb when the portal
// config endpoint fails so ops aren't blind to portal enrichment outages.
import { safeRun } from '@/utils/safeRun';

export function TrustBadges(): React.ReactElement | null {
  const { t } = usePortalI18n();
  const [config, setConfig] = useState<PortalConfig | null>(null);

  useEffect(() => {
    let cancelled = false;
    getPortalConfig()
      .then((data) => {
        if (!cancelled) setConfig(data);
      })
      .catch((err: unknown) => {
        if (!cancelled) setConfig({});
        // WEB-FV-008: degrade silently for the customer, breadcrumb for ops.
        safeRun(() => { throw err; }, { tag: 'portal:trustBadges' });
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
      className="rounded-lg bg-gradient-to-br from-surface-50 to-primary-50 dark:from-surface-800 dark:to-primary-900/30 border border-surface-200 dark:border-surface-700 p-4 space-y-3"
    >
      {showSla && slaMessage ? (
        <div className="text-xs font-medium text-primary-800 dark:text-primary-200 flex items-center gap-2">
          <span aria-hidden="true">{'\u2713'}</span>
          {slaMessage}
        </div>
      ) : null}

      <div className="flex flex-wrap gap-2 text-[11px]">
        <span className="inline-flex items-center gap-1 rounded-full bg-green-100 dark:bg-green-900/50 text-green-800 dark:text-green-200 px-2 py-1 font-medium">
          <span aria-hidden="true">{'\u{1F512}'}</span>
          {t('trust.ssl')}
        </span>
        <span className="inline-flex items-center gap-1 rounded-full bg-primary-100 dark:bg-primary-900/50 text-primary-800 dark:text-primary-200 px-2 py-1 font-medium">
          <span aria-hidden="true">{'\u{1F4B3}'}</span>
          {t('trust.pci')}
        </span>
      </div>

      <dl className="text-xs text-surface-700 dark:text-surface-300 space-y-1">
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
                className="text-primary-700 dark:text-primary-300 hover:underline"
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
