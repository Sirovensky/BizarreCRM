/**
 * AutomationsListPage — standalone page at /automations.
 *
 * Renders AutomationsTab (list/create/edit/toggle/delete) inside a
 * standard page shell. The same tab is also reachable via
 * /settings/automations — this page exists so the feature has its own
 * top-level route without requiring the user to navigate into Settings.
 */

import { Zap } from 'lucide-react';
import { AutomationsTab } from '@/pages/settings/AutomationsTab';

export function AutomationsListPage() {
  return (
    <div className="mx-auto max-w-4xl p-6">
      <div className="mb-6">
        <h1 className="flex items-center gap-2 text-2xl font-semibold text-surface-900 dark:text-surface-100">
          <Zap className="h-6 w-6 text-primary-500" />
          Automations
        </h1>
        <p className="mt-1 text-sm text-surface-500 dark:text-surface-400">
          Rules that automatically perform actions when events occur in your shop.
        </p>
      </div>
      <AutomationsTab />
    </div>
  );
}
