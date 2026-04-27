import { useState, useEffect } from 'react';
import { useSearchParams } from 'react-router-dom';
import toast from 'react-hot-toast';
import { usePortalAuth } from './usePortalAuth';
import { PortalLogin } from './PortalLogin';
import { PortalRegister } from './PortalRegister';
import { PortalDashboard } from './PortalDashboard';
import { PortalTicketDetail } from './PortalTicketDetail';
import { PortalEstimatesView } from './PortalEstimatesView';
import { PortalInvoicesView } from './PortalInvoicesView';
import * as api from './portalApi';
import { safeColor } from '../../utils/safeColor';
import { formatShortDateTime } from '@/utils/format';
// Portal enrichment (criticalaudit.md §45)
import { StatusTimeline } from './components/StatusTimeline';
import { QueuePosition } from './components/QueuePosition';
import { TechCard } from './components/TechCard';
import { PhotoGallery } from './components/PhotoGallery';
import { PayNowButton } from './components/PayNowButton';
import { ReviewPromptModal } from './components/ReviewPromptModal';
import { TrustBadges } from './components/TrustBadges';
import { LanguageSwitcher } from './components/LanguageSwitcher';
import { getReceiptUrl, getWarrantyUrl } from './components/enrichApi';
import { usePortalI18n } from './i18n';

type View = 'login' | 'register' | 'dashboard' | 'ticket-detail' | 'estimates' | 'invoices';

export function CustomerPortalPage() {
  const [searchParams] = useSearchParams();
  const isWidget = searchParams.get('mode') === 'widget';
  const tokenParam = searchParams.get('token');
  const auth = usePortalAuth();

  const [view, setView] = useState<View>('login');
  const [selectedTicketId, setSelectedTicketId] = useState<number | null>(null);
  const [initialTicketData, setInitialTicketData] = useState<api.TicketDetail | null>(null);
  const [storeName, setStoreName] = useState('Repair Shop');
  const [storeLogo, setStoreLogo] = useState<string | null>(null);

  // Load store branding — T8 fix: on failure, log the error and show a
  // non-blocking toast so the user understands why the portal is rendering
  // with the fallback branding ("Repair Shop" / no logo).
  useEffect(() => {
    let cancelled = false;
    api.getEmbedConfig()
      .then(config => {
        if (cancelled) return;
        setStoreName(config.name);
        setStoreLogo(config.logo);
      })
      .catch(err => {
        if (cancelled) return;
        console.error('Failed to load portal branding:', err);
        toast.error('Could not load store branding. Using defaults.');
      });
    return () => { cancelled = true; };
  }, []);

  // Auto-login from token in URL — T8 fix: surface verification failures so
  // the customer knows their magic link was invalid instead of landing on
  // a blank login screen with no context.
  useEffect(() => {
    if (tokenParam && !auth.isAuthenticated && !auth.isLoading) {
      // Remove token from URL immediately to prevent it lingering in browser history
      const url = new URL(window.location.href);
      url.searchParams.delete('token');
      window.history.replaceState({}, '', url.toString());

      // WEB-FJ-018: capture the trailing token chars BEFORE stripping it from
      // the URL so a verification-failure toast can echo "your link …XYZ123"
      // — gives the customer a recognisable handle to forward to support
      // even though the URL has been scrubbed for browser-history hygiene.
      const tokenTail = tokenParam.slice(-6);

      api.verifySession(tokenParam)
        .then(result => {
          if (result.valid) {
            sessionStorage.setItem('portal_token', tokenParam);
            auth.loginWithToken(
              tokenParam,
              result.scope as 'ticket' | 'full',
              result.customer_first_name || '',
              result.ticket_id || undefined,
            );
          } else {
            toast.error(`Your sign-in link (…${tokenTail}) is invalid or has expired. Please request a new one.`);
          }
        })
        .catch(err => {
          console.error('Portal session verification failed:', err);
          toast.error(`Could not verify your sign-in link (…${tokenTail}). Please try again.`);
        });
    }
  }, [tokenParam, auth.isAuthenticated, auth.isLoading]);

  // Set view based on auth state
  useEffect(() => {
    if (auth.isLoading) return;
    if (!auth.isAuthenticated) {
      setView('login');
      return;
    }
    if (auth.scope === 'ticket' && auth.ticketId) {
      setSelectedTicketId(auth.ticketId);
      setView('ticket-detail');
    } else if (auth.scope === 'full') {
      setView('dashboard');
    }
  }, [auth.isAuthenticated, auth.isLoading, auth.scope, auth.ticketId]);

  // Send height to parent for widget auto-resize
  useEffect(() => {
    if (!isWidget) return;
    const observer = new ResizeObserver(() => {
      const height = document.documentElement.scrollHeight;
      window.parent.postMessage({ type: 'bizarre-portal-resize', height }, window.location.origin);
    });
    observer.observe(document.body);
    return () => observer.disconnect();
  }, [isWidget]);

  if (auth.isLoading) {
    return (
      <div className="flex items-center justify-center min-h-screen bg-surface-50 dark:bg-surface-950">
        <div className="h-8 w-8 border-4 border-primary-200 border-t-primary-600 rounded-full animate-spin" />
      </div>
    );
  }

  // Widget mode: lightweight tracking only
  if (isWidget) {
    return (
      <WidgetTracker
        storeName={storeName}
        portalUrl={window.location.origin + '/customer-portal'}
      />
    );
  }

  // Full standalone views
  switch (view) {
    case 'login':
      return (
        <PortalLogin
          storeName={storeName}
          storeLogo={storeLogo}
          onQuickTrack={(token, ticket) => {
            auth.loginWithToken(token, 'ticket', ticket.customer_first_name || '', ticket.id);
            setInitialTicketData(ticket);
            setSelectedTicketId(ticket.id);
            setView('ticket-detail');
          }}
          onFullLogin={(token, customerName) => {
            auth.loginWithToken(token, 'full', customerName);
            setView('dashboard');
          }}
          onRegister={() => setView('register')}
        />
      );

    case 'register':
      return (
        <PortalRegister
          onRegistered={(token, customerName) => {
            auth.loginWithToken(token, 'full', customerName);
            setView('dashboard');
          }}
          onBack={() => setView('login')}
        />
      );

    case 'dashboard':
      return (
        <PortalDashboard
          customerName={auth.customerName}
          onViewTicket={(id) => {
            setSelectedTicketId(id);
            setInitialTicketData(null);
            setView('ticket-detail');
          }}
          onViewEstimates={() => setView('estimates')}
          onViewInvoices={() => setView('invoices')}
          onLogout={async () => {
            await auth.logout();
            setView('login');
          }}
        />
      );

    case 'ticket-detail':
      return (
        <TicketDetailWithEnrichment
          ticketId={selectedTicketId!}
          initialData={initialTicketData}
          onBack={auth.scope === 'full' ? () => setView('dashboard') : null}
          scope={auth.scope}
          hasAccount={auth.hasAccount}
          onCreateAccount={() => setView('register')}
        />
      );

    case 'estimates':
      return <PortalEstimatesView onBack={() => setView('dashboard')} />;

    case 'invoices':
      return <PortalInvoicesView onBack={() => setView('dashboard')} />;

    default:
      return null;
  }
}

/** Lightweight widget: track repair only, no auth/accounts */
function WidgetTracker({ storeName, portalUrl }: { storeName: string; portalUrl: string }) {
  const [orderId, setOrderId] = useState('');
  const [phoneLast4, setPhoneLast4] = useState('');
  const [ticket, setTicket] = useState<api.TicketDetail | null>(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  // Auto-resize iframe
  useEffect(() => {
    const observer = new ResizeObserver(() => {
      window.parent.postMessage({ type: 'bizarre-portal-resize', height: document.documentElement.scrollHeight }, window.location.origin);
    });
    observer.observe(document.body);
    return () => observer.disconnect();
  }, []);

  async function handleTrack(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    if (!orderId.trim() || phoneLast4.length !== 4) {
      setError('Enter your ticket ID and last 4 digits of your phone');
      return;
    }
    setLoading(true);
    try {
      const result = await api.quickTrack(orderId.trim(), phoneLast4);
      sessionStorage.setItem('portal_token', result.token);
      setTicket(result.ticket);
    } catch (err: unknown) {
      const status = (err as any)?.response?.status;
      if (!status) {
        setError('Unable to connect. Please check your internet connection.');
      } else if (status === 404) {
        setError('No matching repair found. Please check your details.');
      } else if (status === 429) {
        setError('Too many attempts. Please wait a minute before trying again.');
      } else {
        setError('Something went wrong. Please try again.');
      }
    } finally {
      setLoading(false);
    }
  }

  function handleReset() {
    setTicket(null);
    setOrderId('');
    setPhoneLast4('');
    setError('');
    sessionStorage.removeItem('portal_token');
    api.clearPortalSecurityTokens();
  }

  const STATUS_PROGRESS: Record<string, number> = {
    'Open': 10, 'In Progress': 40, 'Waiting for Parts': 50, 'Waiting on Customer': 50,
    'Parts Arrived': 60, 'On Hold': 30, 'Closed': 100, 'Cancelled': 100,
  };

  // Search form
  if (!ticket) {
    return (
      <div className="bg-white dark:bg-surface-900 p-5">
        <div className="text-center mb-4">
          <h2 className="text-base font-bold text-surface-900 dark:text-surface-100">{storeName}</h2>
          <p className="text-xs text-surface-500 dark:text-surface-400 mt-0.5">Check your repair status</p>
        </div>

        {error && (
          <div className="mb-3 rounded-lg bg-red-50 dark:bg-red-950/40 border border-red-200 dark:border-red-900 px-3 py-2 text-xs text-red-700 dark:text-red-300">{error}</div>
        )}

        <form onSubmit={handleTrack} className="space-y-3">
          <div>
            <label htmlFor="w-order" className="block text-xs font-medium text-surface-600 dark:text-surface-300 mb-1">Ticket ID</label>
            <input
              id="w-order"
              type="text"
              placeholder="e.g. T-1042"
              value={orderId}
              onChange={e => setOrderId(e.target.value)}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
              autoComplete="off"
            />
          </div>
          <div>
            <label htmlFor="w-phone" className="block text-xs font-medium text-surface-600 dark:text-surface-300 mb-1">Last 4 digits of phone</label>
            <input
              id="w-phone"
              type="tel"
              placeholder="1234"
              maxLength={4}
              value={phoneLast4}
              onChange={e => setPhoneLast4(e.target.value.replace(/\D/g, '').slice(0, 4))}
              className="w-full rounded-lg border border-surface-300 dark:border-surface-700 bg-white dark:bg-surface-800 px-3 py-2.5 text-sm text-surface-900 dark:text-surface-100 placeholder-surface-400 dark:placeholder-surface-500 focus:border-primary-500 focus:ring-1 focus:ring-primary-500 outline-none"
              autoComplete="off"
            />
          </div>
          <button
            type="submit"
            disabled={loading}
            className="w-full rounded-lg bg-primary-600 px-4 py-2.5 text-sm font-medium text-primary-950 hover:bg-primary-700 disabled:opacity-50 transition-colors"
          >
            {loading ? 'Looking up...' : 'Track My Repair'}
          </button>
        </form>

        <p className="mt-3 text-center text-[10px] text-surface-400 dark:text-surface-500">
          Your ticket ID is on your receipt or check-in confirmation
        </p>
      </div>
    );
  }

  // Ticket result view
  const progress = STATUS_PROGRESS[ticket.status.name] ?? 20;
  const latestUpdate = ticket.timeline.length > 0 ? ticket.timeline[ticket.timeline.length - 1] : null;

  return (
    <div className="bg-white dark:bg-surface-900 p-5">
      {/* Header */}
      <div className="flex items-center justify-between mb-4">
        <button onClick={handleReset} className="text-xs text-surface-400 dark:text-surface-500 hover:text-surface-600 dark:hover:text-surface-300 flex items-center gap-1">
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M15 19l-7-7 7-7" />
          </svg>
          New search
        </button>
        <span className="text-xs font-medium text-surface-500 dark:text-surface-400">{ticket.order_id}</span>
      </div>

      {/* Status */}
      <div className="text-center mb-4">
        <span
          className="inline-flex items-center rounded-full px-3 py-1 text-sm font-semibold text-white"
          style={{ backgroundColor: safeColor(ticket.status.color) }}
        >
          {ticket.status.name}
        </span>
      </div>

      {/* Progress bar */}
      <div className="mb-4">
        <div className="h-2 rounded-full bg-surface-100 dark:bg-surface-800 overflow-hidden">
          <div
            className="h-full rounded-full transition-all duration-500"
            style={{
              width: `${progress}%`,
              backgroundColor: ticket.status.is_closed ? '#10b981' : safeColor(ticket.status.color, '#3b82f6'),
            }}
          />
        </div>
        <div className="flex justify-between mt-1 text-[10px] text-surface-400 dark:text-surface-500">
          <span>Received</span><span>In Progress</span><span>Ready</span><span>Complete</span>
        </div>
      </div>

      {/* Device */}
      {ticket.devices.length > 0 && (
        <div className="text-sm text-surface-700 dark:text-surface-300 mb-3">
          {ticket.devices.map(d => d.name || d.type).join(', ')}
        </div>
      )}

      {/* Latest update */}
      {latestUpdate && (
        <div className="bg-surface-50 dark:bg-surface-800/60 rounded-lg p-3 mb-3">
          <div className="text-xs font-medium text-surface-500 dark:text-surface-400 mb-1">Latest Update</div>
          <div className="text-sm text-surface-700 dark:text-surface-300">{latestUpdate.description}</div>
          <div className="text-[10px] text-surface-400 dark:text-surface-500 mt-1">{formatWidgetDate(latestUpdate.created_at)}</div>
        </div>
      )}

      {/* Invoice summary (if exists) */}
      {ticket.invoice && (
        <div className="bg-surface-50 dark:bg-surface-800/60 rounded-lg p-3 mb-3">
          <div className="flex justify-between text-sm">
            <span className="text-surface-600 dark:text-surface-300">Total</span>
            <span className="font-semibold text-surface-900 dark:text-surface-100">${ticket.invoice.total.toFixed(2)}</span>
          </div>
          {ticket.invoice.amount_due > 0 ? (
            <div className="flex justify-between text-sm mt-1">
              <span className="text-surface-600 dark:text-surface-300">Balance due</span>
              <span className="font-semibold text-red-600 dark:text-red-400">${ticket.invoice.amount_due.toFixed(2)}</span>
            </div>
          ) : (
            <div className="text-xs text-green-600 dark:text-green-400 mt-1 font-medium">Paid in full</div>
          )}
        </div>
      )}

      {/* Link to full portal */}
      <div className="pt-2 border-t border-surface-100 dark:border-surface-800 text-center">
        <a
          href={portalUrl}
          target="_blank"
          rel="noopener noreferrer"
          className="inline-flex items-center gap-1 text-xs text-primary-600 hover:text-primary-700 hover:underline"
        >
          View all tickets & manage account
          <svg className="w-3 h-3" fill="none" viewBox="0 0 24 24" stroke="currentColor" strokeWidth={2}>
            <path strokeLinecap="round" strokeLinejoin="round" d="M10 6H6a2 2 0 00-2 2v10a2 2 0 002 2h10a2 2 0 002-2v-4M14 4h6m0 0v6m0-6L10 14" />
          </svg>
        </a>
      </div>
    </div>
  );
}

function formatWidgetDate(date: string): string {
  try {
    return formatShortDateTime(date);
  } catch {
    return date;
  }
}

// ---------------------------------------------------------------------------
// TicketDetailWithEnrichment — wraps the prior-agent-owned PortalTicketDetail
// with the enrichment panel described in criticalaudit.md §45. All enrichment
// components render nothing when disabled by store config, so this is a safe
// additive wrapper.
// ---------------------------------------------------------------------------
interface TicketDetailWithEnrichmentProps {
  ticketId: number;
  initialData: api.TicketDetail | null;
  onBack: (() => void) | null;
  scope: 'ticket' | 'full' | null;
  hasAccount: boolean;
  onCreateAccount: () => void;
}

function TicketDetailWithEnrichment({
  ticketId,
  initialData,
  onBack,
  scope,
  hasAccount,
  onCreateAccount,
}: TicketDetailWithEnrichmentProps) {
  const { t } = usePortalI18n();
  const [reviewOpen, setReviewOpen] = useState(false);
  const [amountDue, setAmountDue] = useState<number>(
    initialData?.invoice?.amount_due ?? 0,
  );
  const [isClosed, setIsClosed] = useState<boolean>(
    initialData?.status?.is_closed ?? false,
  );

  // Fetch ticket to get current amount_due + closed status for enrichment.
  useEffect(() => {
    let cancelled = false;
    api.getTicketDetail(ticketId)
      .then((data) => {
        if (cancelled) return;
        setAmountDue(data.invoice?.amount_due ?? 0);
        setIsClosed(data.status?.is_closed ?? false);
      })
      .catch(() => {
        /* PortalTicketDetail owns the error UI */
      });
    return () => {
      cancelled = true;
    };
  }, [ticketId]);

  // Auto-prompt for review once, after pickup (closed ticket).
  useEffect(() => {
    if (!isClosed) return;
    const reviewedKey = `portal_reviewed_${ticketId}`;
    if (sessionStorage.getItem(reviewedKey)) return;
    const timer = setTimeout(() => {
      setReviewOpen(true);
      sessionStorage.setItem(reviewedKey, '1');
    }, 2500);
    return () => clearTimeout(timer);
  }, [isClosed, ticketId]);

  return (
    <div className="min-h-screen bg-surface-50 dark:bg-surface-950">
      <header className="flex justify-end px-4 pt-3">
        <LanguageSwitcher />
      </header>

      <PortalTicketDetail
        ticketId={ticketId}
        initialData={initialData}
        onBack={onBack}
        scope={scope}
        hasAccount={hasAccount}
        onCreateAccount={onCreateAccount}
      />

      <div className="max-w-3xl mx-auto px-4 pb-10 space-y-4">
        <TrustBadges />
        <QueuePosition ticketId={ticketId} />
        <TechCard ticketId={ticketId} />
        <StatusTimeline ticketId={ticketId} />
        <PhotoGallery ticketId={ticketId} />
        {amountDue > 0 ? (
          <PayNowButton ticketId={ticketId} amountDue={amountDue} />
        ) : null}

        {isClosed ? (
          <div className="flex gap-2 flex-wrap">
            <a
              href={getReceiptUrl(ticketId)}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded border border-surface-300 dark:border-surface-600 px-3 py-2 text-xs font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-800"
            >
              {t('receipt.download')}
            </a>
            <a
              href={getWarrantyUrl(ticketId)}
              target="_blank"
              rel="noopener noreferrer"
              className="inline-flex items-center gap-1 rounded border border-surface-300 dark:border-surface-600 px-3 py-2 text-xs font-medium text-surface-700 dark:text-surface-200 hover:bg-surface-100 dark:hover:bg-surface-800"
            >
              {t('warranty.download')}
            </a>
            <button
              type="button"
              onClick={() => setReviewOpen(true)}
              className="inline-flex items-center gap-1 rounded bg-primary-600 hover:bg-primary-700 text-primary-950 px-3 py-2 text-xs font-medium"
            >
              {t('review.title')}
            </button>
          </div>
        ) : null}
      </div>

      <ReviewPromptModal
        ticketId={ticketId}
        open={reviewOpen}
        onClose={() => setReviewOpen(false)}
      />
    </div>
  );
}
