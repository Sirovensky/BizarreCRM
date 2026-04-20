import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { CheckCircle2, AlertTriangle, XCircle, ChevronDown, ChevronRight, ListChecks } from 'lucide-react';
import { getAPI } from '@/api/bridge';
import type { EnvSettingField } from '@/api/bridge';
import { useServerStore } from '@/stores/serverStore';

type CheckStatus = 'pass' | 'warn' | 'fail';

interface CheckItem {
  id: string;
  label: string;
  status: CheckStatus;
  detail: string;
  /** Optional dashboard link to take action. */
  to?: string;
  /** Hash/query for the link target (e.g. ?tab=alerts). */
  toHash?: string;
}

interface ChecklistProps {
  /** Default-collapsed only when score is 100% — operator still sees something is wrong. */
  collapsedWhenComplete?: boolean;
}

export function SetupChecklist({ collapsedWhenComplete = true }: ChecklistProps) {
  const [envFields, setEnvFields] = useState<EnvSettingField[] | null>(null);
  const [backupCount, setBackupCount] = useState<number | null>(null);
  const [latestBackupAt, setLatestBackupAt] = useState<string | null>(null);
  const stats = useServerStore((s) => s.stats);
  const isMultiTenant = stats?.multiTenant ?? false;

  const [expanded, setExpanded] = useState(true);

  useEffect(() => {
    getAPI().admin.getEnvSettings()
      .then((res) => {
        if (res.success && res.data) setEnvFields(res.data.fields);
      })
      .catch((err) => console.warn('[SetupChecklist] getEnvSettings failed', err));

    getAPI().admin.listBackups()
      .then((res) => {
        if (res.success && Array.isArray(res.data)) {
          const list = res.data as Array<{ created: string }>;
          setBackupCount(list.length);
          setLatestBackupAt(list[0]?.created ?? null);
        } else {
          setBackupCount(0);
        }
      })
      .catch((err) => console.warn('[SetupChecklist] listBackups failed', err));
  }, []);

  if (!envFields) {
    return null;
  }

  function envValue(key: string): string {
    return envFields?.find((f) => f.key === key)?.value ?? '';
  }
  function envHasSecret(key: string): boolean {
    return envFields?.find((f) => f.key === key)?.hasValue ?? false;
  }

  const checks: CheckItem[] = [];

  // Captcha — only required when multi-tenant prod with require=true.
  const captchaRequired = envValue('SIGNUP_CAPTCHA_REQUIRED') !== 'false';
  if (isMultiTenant) {
    if (captchaRequired) {
      checks.push({
        id: 'hcaptcha',
        label: 'hCaptcha secret',
        status: envHasSecret('HCAPTCHA_SECRET') ? 'pass' : 'fail',
        detail: envHasSecret('HCAPTCHA_SECRET')
          ? 'HCAPTCHA_SECRET is set; signup endpoint protected.'
          : 'Multi-tenant prod requires HCAPTCHA_SECRET — server will refuse to boot. Either paste the secret or flip the toggle to skip captcha.',
        to: '/settings',
      });
    } else {
      checks.push({
        id: 'hcaptcha-bypass',
        label: 'Signup bot protection',
        status: 'warn',
        detail: 'SIGNUP_CAPTCHA_REQUIRED=false — relying on upstream Cloudflare/WAF. Confirm the edge filter is actually catching abusive signups.',
        to: '/settings',
      });
    }
  }

  // Cloudflare — only meaningful in multi-tenant.
  if (isMultiTenant) {
    const cfComplete = envHasSecret('CLOUDFLARE_API_TOKEN') && envValue('CLOUDFLARE_ZONE_ID') && envValue('SERVER_PUBLIC_IP');
    checks.push({
      id: 'cloudflare',
      label: 'Cloudflare DNS auto-provisioning',
      status: cfComplete ? 'pass' : 'warn',
      detail: cfComplete
        ? 'Token + Zone + Public IP all set. New tenant subdomains will auto-create DNS records.'
        : 'Missing one of CLOUDFLARE_API_TOKEN / CLOUDFLARE_ZONE_ID / SERVER_PUBLIC_IP. New tenant signups will not get DNS records automatically.',
      to: '/settings',
    });
  }

  // Stripe — billing. Optional but warn if partial (a known foot-gun).
  const stripeKeys = [envHasSecret('STRIPE_SECRET_KEY'), envHasSecret('STRIPE_WEBHOOK_SECRET'), !!envValue('STRIPE_PRO_PRICE_ID')];
  const stripeFilledCount = stripeKeys.filter(Boolean).length;
  if (stripeFilledCount === 3) {
    checks.push({
      id: 'stripe',
      label: 'Stripe billing',
      status: 'pass',
      detail: 'All three Stripe keys set. /billing routes operational.',
      to: '/settings',
    });
  } else if (stripeFilledCount > 0) {
    checks.push({
      id: 'stripe',
      label: 'Stripe billing',
      status: 'fail',
      detail: `${stripeFilledCount} / 3 keys set. Partially-configured Stripe makes /billing fail at runtime — finish all three or clear them.`,
      to: '/settings',
    });
  } else {
    // Not configured at all is OK — billing simply disabled.
    checks.push({
      id: 'stripe',
      label: 'Stripe billing',
      status: 'warn',
      detail: 'Not configured — paid-plan upgrades disabled. Add the three Stripe keys when ready to charge.',
      to: '/settings',
    });
  }

  // Backups
  if (backupCount === null) {
    // Loading — skip.
  } else if (backupCount === 0) {
    checks.push({
      id: 'backups',
      label: 'Backups',
      status: 'fail',
      detail: 'No backups have ever completed. Run a manual backup before relying on this server.',
      to: '/backups',
    });
  } else {
    const ageMs = latestBackupAt ? Date.now() - new Date(latestBackupAt).getTime() : Infinity;
    const ageHours = ageMs / (1000 * 60 * 60);
    if (ageHours < 24) {
      checks.push({
        id: 'backups',
        label: 'Backups',
        status: 'pass',
        detail: `${backupCount} backups; last completed ${humanAge(ageMs)} ago.`,
        to: '/backups',
      });
    } else if (ageHours < 72) {
      checks.push({
        id: 'backups',
        label: 'Backups',
        status: 'warn',
        detail: `Last backup was ${humanAge(ageMs)} ago — verify the schedule is firing.`,
        to: '/backups',
      });
    } else {
      checks.push({
        id: 'backups',
        label: 'Backups',
        status: 'fail',
        detail: `Last backup was ${humanAge(ageMs)} ago — well past the 72h threshold.`,
        to: '/backups',
      });
    }
  }

  // Kill switches sanity — warn if any are ON unexpectedly.
  const anyKill =
    envValue('DISABLE_OUTBOUND_EMAIL') === 'true' ||
    envValue('DISABLE_OUTBOUND_SMS') === 'true' ||
    envValue('DISABLE_OUTBOUND_VOICE') === 'true';
  if (anyKill) {
    checks.push({
      id: 'killswitches',
      label: 'Outbound kill switches',
      status: 'warn',
      detail: 'One or more outbound channels are DISABLED. Customers will not receive notifications until you turn them back on.',
      to: '/settings',
    });
  }

  // Security alerts unack count from the live stats poll (no extra fetch).
  const unack = stats?.unacknowledgedSecurityAlerts ?? 0;
  if (unack > 0) {
    checks.push({
      id: 'unack-alerts',
      label: 'Security alerts',
      status: unack > 10 ? 'fail' : 'warn',
      detail: `${unack} unacknowledged ${unack === 1 ? 'alert' : 'alerts'}. Review and clear from the Activity → Security Alerts tab.`,
      to: '/activity',
      toHash: '?tab=alerts',
    });
  }

  if (checks.length === 0) return null;

  const passCount = checks.filter((c) => c.status === 'pass').length;
  const failCount = checks.filter((c) => c.status === 'fail').length;
  const warnCount = checks.filter((c) => c.status === 'warn').length;
  const allGood = failCount === 0 && warnCount === 0;

  // Auto-collapse when complete IF the prop allows.
  useEffect(() => {
    if (allGood && collapsedWhenComplete) setExpanded(false);
  }, [allGood, collapsedWhenComplete]);

  const headerColor = failCount > 0
    ? 'border-red-900/60 bg-red-950/30 text-red-300'
    : warnCount > 0
      ? 'border-amber-900/60 bg-amber-950/30 text-amber-300'
      : 'border-emerald-900/60 bg-emerald-950/30 text-emerald-300';

  return (
    <div className={`rounded-lg border ${headerColor}`}>
      <button
        onClick={() => setExpanded((v) => !v)}
        className="w-full flex items-center justify-between p-3 hover:bg-surface-800/30 transition-colors rounded-lg"
      >
        <div className="flex items-center gap-2">
          <ListChecks className="w-4 h-4" />
          <span className="text-sm font-medium">
            Setup checklist · {passCount}/{checks.length} OK
            {failCount > 0 && <span className="ml-2 text-red-400">· {failCount} blocking</span>}
            {warnCount > 0 && <span className="ml-2 text-amber-400">· {warnCount} warn</span>}
          </span>
        </div>
        {expanded ? <ChevronDown className="w-4 h-4" /> : <ChevronRight className="w-4 h-4" />}
      </button>

      {expanded && (
        <div className="px-3 pb-3 space-y-2">
          {checks.map((c) => {
            const Icon = c.status === 'pass' ? CheckCircle2 : c.status === 'fail' ? XCircle : AlertTriangle;
            const colorCls = c.status === 'pass' ? 'text-emerald-400' : c.status === 'fail' ? 'text-red-400' : 'text-amber-400';
            const target = c.to ? c.to + (c.toHash ?? '') : null;
            return (
              <div key={c.id} className="flex items-start gap-2 px-2 py-1.5 rounded hover:bg-surface-900/40">
                <Icon className={`w-4 h-4 mt-0.5 flex-shrink-0 ${colorCls}`} />
                <div className="flex-1 min-w-0">
                  <div className="text-xs font-medium text-surface-200">{c.label}</div>
                  <div className="text-[11px] text-surface-400 mt-0.5 leading-relaxed">{c.detail}</div>
                </div>
                {target && (
                  <Link
                    to={target}
                    className="text-[11px] text-accent-300 hover:text-accent-200 flex-shrink-0 px-2 py-0.5 rounded border border-accent-900/60 hover:bg-accent-950/40 transition-colors whitespace-nowrap"
                  >
                    Fix
                  </Link>
                )}
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}

function humanAge(ms: number): string {
  if (!isFinite(ms) || ms < 0) return 'unknown';
  const sec = Math.floor(ms / 1000);
  if (sec < 60) return `${sec}s`;
  const min = Math.floor(sec / 60);
  if (min < 60) return `${min}m`;
  const hr = Math.floor(min / 60);
  if (hr < 24) return `${hr}h`;
  const day = Math.floor(hr / 24);
  const remHr = hr % 24;
  return remHr > 0 ? `${day}d ${remHr}h` : `${day}d`;
}
