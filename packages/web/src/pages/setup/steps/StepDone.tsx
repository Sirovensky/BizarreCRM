import type { JSX } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { ArrowRight, CheckCircle2, Globe, Grid3X3, Repeat } from 'lucide-react';
import type { StepProps } from '../wizardTypes';
import { WizardBreadcrumb } from '../components/WizardBreadcrumb';

interface DeepLinkCard {
  title: string;
  description: string;
  to: string;
  Icon: typeof Grid3X3;
}

/**
 * Step 26 — Done.
 *
 * Final wizard screen. Celebrates completion and surfaces three deeper
 * Settings screens worth visiting later. The cards here are intentionally
 * NON-DUPLICATE with the dashboard "first-setup" suggestions — these point
 * at config-heavy pages that don't fit the dashboard quick-action model.
 *
 * Per-device pricing matrix, Customer portal, and Auto-reorder rules were
 * picked because:
 *   - Pricing matrix overrides Step 8's tier defaults with per-model labor.
 *   - Customer portal needs domain/widget decisions the dashboard can't capture.
 *   - Auto-reorder rules require per-part thresholds, a long-tail config job.
 *
 * The primary CTA navigates to /dashboard with replace:true so the user can't
 * Back-button into the wizard. onNext() fires first so the SetupPage shell
 * flushes wizard_completed='true' on the Review→Done transition.
 */
const DEEP_LINKS: DeepLinkCard[] = [
  {
    title: 'Per-device pricing matrix',
    description:
      'Override the tier defaults you set in Step 8 with per-model labor prices. Newest iPhones at +$200 profit, legacy Androids at +$40 — set the matrix once, never argue at the counter.',
    to: '/settings?tab=repair-pricing&view=matrix',
    Icon: Grid3X3,
  },
  {
    title: 'Customer portal',
    description:
      'Let customers track their tickets via a public link, embed a "Repair status" widget on your existing site, or stand up a custom subdomain — all from one settings page.',
    to: '/settings?tab=customer-portal',
    Icon: Globe,
  },
  {
    title: 'Auto-reorder rules',
    description:
      'Set min-stock thresholds per part. When stock dips, the system drafts a PO to your preferred supplier. Beats restocking by gut on a Monday morning.',
    to: '/settings?tab=inventory&section=reorder',
    Icon: Repeat,
  },
];

export function StepDone({ onNext }: StepProps): JSX.Element {
  const navigate = useNavigate();

  const handleGoToDashboard = () => {
    // Fire onNext first so the SetupPage shell flushes wizard_completed
    // on the Review→Done transition (idempotent if already flushed).
    onNext?.();
    navigate('/dashboard', { replace: true });
  };

  return (
    <div className="mx-auto max-w-4xl">
      <div className="mb-6 flex justify-center">
        <WizardBreadcrumb
          prevLabel="Step 25 · Review"
          currentLabel="Step 26 · Done"
        />
      </div>

      <div className="mb-8 text-center">
        <div className="mx-auto mb-4 flex h-16 w-16 items-center justify-center rounded-full bg-green-100 dark:bg-green-500/10">
          <CheckCircle2
            className="h-10 w-10 text-green-500"
            aria-hidden="true"
          />
        </div>
        <h1 className="font-['League_Spartan'] text-3xl font-bold tracking-wide text-surface-900 dark:text-surface-50">
          You're all set!
        </h1>
        <p className="mx-auto mt-3 max-w-2xl text-sm text-surface-500 dark:text-surface-400">
          Your shop is ready to take in tickets. Here are three deeper-config
          screens worth visiting next when you have time.
        </p>
      </div>

      <div className="mb-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {DEEP_LINKS.map(({ title, description, to, Icon }) => (
          <Link
            key={title}
            to={to}
            className="group flex cursor-pointer flex-col rounded-xl border border-surface-200 bg-white p-5 transition hover:border-primary-400 hover:shadow-md dark:border-surface-700 dark:bg-surface-800"
          >
            <div className="mb-3 flex h-11 w-11 items-center justify-center rounded-full bg-primary-100 dark:bg-primary-500/10">
              <Icon
                className="h-5 w-5 text-primary-600 dark:text-primary-400"
                aria-hidden="true"
              />
            </div>
            <h3 className="mb-1 font-semibold text-surface-900 dark:text-surface-50">
              {title}
            </h3>
            <p className="flex-1 text-sm text-surface-500 dark:text-surface-400">
              {description}
            </p>
            <div className="mt-3 inline-flex items-center gap-1 text-xs font-medium text-primary-600 transition group-hover:gap-2 dark:text-primary-400">
              Open setting
              <ArrowRight className="h-3 w-3" aria-hidden="true" />
            </div>
          </Link>
        ))}
      </div>

      <div className="flex flex-col items-center gap-2">
        <button
          type="button"
          onClick={handleGoToDashboard}
          className="inline-flex items-center gap-2 rounded-xl bg-primary-500 px-8 py-3.5 text-base font-semibold text-primary-950 shadow-sm transition hover:bg-primary-400 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-primary-500 focus-visible:ring-offset-2 dark:focus-visible:ring-offset-surface-900"
        >
          Go to dashboard
          <ArrowRight className="h-4 w-4" aria-hidden="true" />
        </button>
        <p className="text-xs text-surface-500 dark:text-surface-400">
          You can revisit this wizard anytime from Settings → Setup.
        </p>
      </div>
    </div>
  );
}

export default StepDone;
