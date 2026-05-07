import { useState, useEffect, useRef, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { Sun, Moon } from 'lucide-react';
import { useUiStore } from '@/stores/uiStore';

/* --------------------------------------------------------------------------
   BizarreCRM Landing Page
   Public marketing surface for multi-tenant mode.
   -------------------------------------------------------------------------- */

function useInView(threshold = 0.12) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;

    const rect = el.getBoundingClientRect();
    if (rect.top < window.innerHeight && rect.bottom > 0) {
      setVisible(true);
      return;
    }

    const obs = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          obs.disconnect();
        }
      },
      { threshold },
    );
    obs.observe(el);
    return () => obs.disconnect();
  }, [threshold]);

  return { ref, visible };
}

/**
 * Landing-page theme toggle. Cycles light → dark → light. Uses the same
 * uiStore.setTheme as the logged-in app, so a visitor's choice persists
 * into the authenticated experience and across reloads. We DON'T expose
 * 'system' here — visitors who want OS-tracking can leave the default
 * untouched (controlled by uiStore.getInitialTheme; currently 'light' so
 * a dark-mode OS doesn't surprise operators).
 */
function ThemeToggle() {
  const theme = useUiStore((s) => s.theme);
  const setTheme = useUiStore((s) => s.setTheme);
  // 'system' is treated as light here — toggle moves to 'dark'. From any
  // other state, toggle moves to the opposite.
  const isDark = theme === 'dark';
  return (
    <button
      type="button"
      onClick={() => setTheme(isDark ? 'light' : 'dark')}
      aria-label={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
      title={isDark ? 'Switch to light mode' : 'Switch to dark mode'}
      className="inline-flex h-9 w-9 items-center justify-center rounded-full border border-surface-300 bg-white/80 text-surface-700 transition hover:bg-fuchsia-50 hover:text-fuchsia-700 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-fuchsia-500 focus-visible:ring-offset-2 dark:border-surface-700 dark:bg-surface-900/80 dark:text-surface-200 dark:hover:bg-surface-800 dark:hover:text-fuchsia-300 dark:focus-visible:ring-offset-surface-950"
    >
      {isDark ? <Sun className="h-4 w-4" /> : <Moon className="h-4 w-4" />}
    </button>
  );
}

function WavyDivider({ flip = false }: { flip?: boolean }) {
  return (
    <div className={`overflow-hidden bg-[#FBF3DB] text-fuchsia-700/35 dark:bg-surface-950 dark:text-fuchsia-300/40 ${flip ? '-scale-y-100' : ''}`}>
      <svg viewBox="0 0 1600 60" preserveAspectRatio="none" className="block h-10 w-full">
        <path
          d="M0,30 Q100,10 200,30 Q300,50 400,30 Q500,10 600,30 Q700,50 800,30 Q900,10 1000,30 Q1100,50 1200,30 Q1300,10 1400,30 Q1500,50 1600,30"
          fill="none"
          stroke="currentColor"
          strokeWidth="12"
          strokeLinecap="round"
        />
      </svg>
    </div>
  );
}

const features = [
  { title: 'Tickets & Repairs', desc: 'Track every device from check-in to pickup. Full history, notes, photos, and status updates so nothing slips through the cracks.', emoji: '\uD83D\uDD27' },
  { title: 'Point of Sale', desc: 'Ring up sales, split payments, apply discounts, print thermal receipts. Fast checkout that does not slow you down.', emoji: '\uD83D\uDCB3' },
  { title: 'Inventory', desc: 'Real-time stock levels, auto-reorder alerts, barcode scanning, and supplier catalog tools built right in.', emoji: '\uD83D\uDCE6' },
  { title: 'SMS & Communications', desc: 'Text customers from tickets. Templates, scheduled messages, and delivery tracking without extra bolt-ons.', emoji: '\uD83D\uDCAC' },
  { title: 'Mobile App', desc: 'Create tickets, check stock, and send SMS from the floor, the bench, or the back room.', emoji: '\uD83D\uDCF1' },
  { title: 'Reports & Analytics', desc: 'Revenue trends, tech performance, parts usage, warranty claims, and shop activity in one dashboard.', emoji: '\uD83D\uDCCA' },
];

const benefits = [
  'Free tier, with enough room to run a real trial',
  'Multiple SMS providers built in',
  'Full-function mobile apps available',
  'Source-available architecture',
  'Import paths for RepairDesk, RepairShopr, and MyRepairApp',
];

// @audit-fixed: #20 - Pro tier price was quoted as $49/mo here but the
// authoritative tier-pricing memory says $69/mo (Free $0, Pro $69, Enterprise
// custom, 14-day Pro trial). Bringing the landing page in sync with the
// actual plan definition so prospects do not get a surprise at checkout.
// Free tier keeps 50 tickets/month (rolling 30 days - see usageTracker #19).
const pricingTiers = [
  { name: 'Free', price: '$0', period: '/mo', desc: 'Get started with the basics', features: ['1 user', '50 tickets/month', 'Basic POS', 'Inventory tracking', 'Basic SMS & reports', 'Email support'], cta: 'Start Free', pop: false },
  { name: 'Pro', price: '$69', period: '/mo', desc: 'Everything your shop needs', badge: 'Most Popular', features: ['Unlimited users', 'Unlimited tickets', 'SMS messaging', 'Mobile app', 'Reports & analytics', 'Priority support', 'Split payments', '14-day free trial'], cta: 'Start Pro Trial', pop: true },
  { name: 'Enterprise', price: 'Custom', period: '', desc: 'Multi-location shops', features: ['Everything in Pro', 'Multi-location', 'Custom branding', 'API access', 'Dedicated support', 'SLA guarantee'], cta: 'Contact Sales', pop: false },
];

const proofPoints = [
  {
    title: 'Try the real workflow first',
    desc: 'Start on the free tier, then use the 14-day Pro trial when your shop needs unlimited tickets, SMS, mobile access, and deeper reports.',
  },
  {
    title: 'Bring existing shop data',
    desc: 'Migration paths are planned around the repair tools shops already know: RepairDesk, RepairShopr, and MyRepairApp.',
  },
  {
    title: 'Run the counter and the bench',
    desc: 'Tickets, POS, inventory, customer texts, photos, and mobile work all stay in one operating flow.',
  },
];

// WEB-FG-002 / FIXED-by-Fixer-U 2026-04-25 - trust only known base domains
// when computing tenant URLs. The previous heuristic blindly trusted whatever
// DNS the browser landed on, so a phishing host could redirect credentials to
// an attacker-controlled subdomain.
const TRUSTED_BASE_DOMAINS = ['bizarrecrm.com', 'localhost'] as const;

const revealDelays = ['', 'delay-75', 'delay-150', 'delay-200', 'delay-300', 'delay-500'] as const;

const displayText = 'font-display tracking-normal';
const headingText = 'font-sans font-semibold';
const brandText = 'font-logo tracking-normal';

const primaryButton =
  'inline-flex shrink-0 items-center justify-center rounded-lg border border-cyan-700 bg-cyan-700 px-9 py-3.5 font-sans text-base font-semibold text-white no-underline shadow-sm transition hover:-translate-y-0.5 hover:bg-cyan-800 hover:shadow-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-500 focus-visible:ring-offset-2 motion-reduce:transform-none dark:border-cyan-400 dark:bg-cyan-400 dark:text-surface-950 dark:hover:bg-cyan-300 dark:focus-visible:ring-offset-surface-950';
const magentaButton =
  'inline-flex shrink-0 items-center justify-center rounded-lg border border-fuchsia-700 bg-fuchsia-700 px-9 py-3.5 font-sans text-base font-semibold text-white no-underline shadow-sm transition hover:-translate-y-0.5 hover:bg-fuchsia-800 hover:shadow-lg focus:outline-none focus-visible:ring-2 focus-visible:ring-fuchsia-500 focus-visible:ring-offset-2 motion-reduce:transform-none dark:border-fuchsia-400 dark:bg-fuchsia-500 dark:text-surface-950 dark:hover:bg-fuchsia-400 dark:focus-visible:ring-offset-surface-950';
const outlineButton =
  'inline-flex shrink-0 items-center justify-center rounded-lg border-2 border-cyan-700 bg-transparent px-8 py-3 font-sans text-base font-semibold text-cyan-800 no-underline transition hover:bg-cyan-700 hover:text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan-500 focus-visible:ring-offset-2 dark:border-cyan-400 dark:text-cyan-200 dark:hover:bg-cyan-400 dark:hover:text-surface-950 dark:focus-visible:ring-offset-surface-950';
const footerAction =
  'font-sans text-sm font-medium text-surface-600 transition hover:text-fuchsia-700 focus:outline-none focus-visible:ring-2 focus-visible:ring-fuchsia-500 dark:text-surface-300 dark:hover:text-fuchsia-300';

function resolveBaseDomain(hostname: string): string | null {
  if (hostname === 'localhost' || hostname.endsWith('.localhost')) return 'localhost';
  for (const allowed of TRUSTED_BASE_DOMAINS) {
    if (hostname === allowed || hostname.endsWith(`.${allowed}`)) return allowed;
  }
  return null;
}

function getTenantUrl(slug: string, path = '/'): string | null {
  const { protocol, port, hostname } = window.location;
  const baseDomain = resolveBaseDomain(hostname);
  if (!baseDomain) return null;

  if (baseDomain === 'localhost') {
    const portSuffix = port && port !== '443' && port !== '80' ? `:${port}` : '';
    return `${protocol}//${hostname}${portSuffix}/t/${slug}${path}`;
  }

  const portSuffix = port && port !== '443' && port !== '80' ? `:${port}` : '';
  return `${protocol}//${slug}.${baseDomain}${portSuffix}${path}`;
}

function delayFor(index: number) {
  return revealDelays[Math.min(index, revealDelays.length - 1)];
}

function reveal(base: string, show: boolean, delay = '') {
  return [
    base,
    'transform-gpu transition-all duration-500 ease-out motion-reduce:translate-y-0 motion-reduce:transition-none',
    show ? 'translate-y-0 opacity-100' : 'translate-y-6 opacity-0',
    delay,
  ].filter(Boolean).join(' ');
}

function LoginModal({ onClose }: { onClose: () => void }) {
  const [slug, setSlug] = useState('');
  const [error, setError] = useState('');

  const handleGo = () => {
    const cleaned = slug.trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
    if (!cleaned || cleaned.length < 3) {
      setError('Enter your shop name (at least 3 characters)');
      return;
    }
    const target = getTenantUrl(cleaned, '/login');
    if (!target) {
      setError('This page is not on a recognized BizarreCRM domain. Visit https://bizarrecrm.com to log in.');
      return;
    }
    window.location.href = target;
  };

  return (
    <div className="fixed inset-0 z-[200] flex items-center justify-center bg-surface-950/70 p-4 backdrop-blur" onClick={onClose}>
      <div
        className="w-full max-w-[420px] rounded-xl border border-surface-200 bg-white p-8 shadow-2xl dark:border-surface-700 dark:bg-surface-900"
        onClick={e => e.stopPropagation()}
      >
        <h3 className={`${displayText} mb-2 text-[28px] leading-tight text-cyan-700 dark:text-cyan-300`}>Login to Your Shop</h3>
        <p className="mb-6 text-sm text-surface-600 dark:text-surface-300">Enter your shop name to go to your CRM login page.</p>
        <div className="mb-2 flex">
          <input
            type="text"
            value={slug}
            onChange={e => { setSlug(e.target.value); setError(''); }}
            onKeyDown={e => {
              if (e.key === 'Enter') {
                e.preventDefault();
                handleGo();
              }
            }}
            placeholder="yourshop"
            aria-label="Shop name"
            autoFocus
            className="min-w-0 flex-1 rounded-l-lg border-2 border-r-0 border-surface-300 bg-white px-3.5 py-3 font-sans text-base text-surface-900 outline-none focus:border-cyan-700 dark:border-surface-700 dark:bg-surface-950 dark:text-surface-100 dark:focus:border-cyan-400"
          />
          <span className="flex items-center whitespace-nowrap rounded-r-lg border-2 border-l-0 border-surface-300 bg-surface-100 px-3.5 text-sm text-surface-500 dark:border-surface-700 dark:bg-surface-800 dark:text-surface-400">
            {resolveBaseDomain(window.location.hostname) === 'localhost'
              ? ' /t/yourshop'
              : `.${resolveBaseDomain(window.location.hostname) ?? 'bizarrecrm.com'}`}
          </span>
        </div>
        {error && <p className="mb-2 text-[13px] text-error-600 dark:text-error-400">{error}</p>}
        <div className="mt-5 flex flex-wrap gap-3">
          <button type="button" className={`${primaryButton} flex-1 px-5 py-3`} onClick={handleGo}>Go to Login</button>
          <button type="button" className={`${outlineButton} px-6 py-3`} onClick={onClose}>Cancel</button>
        </div>
      </div>
    </div>
  );
}

export default function LandingPage() {
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenu, setMobileMenu] = useState(false);
  const [showLogin, setShowLogin] = useState(() => new URLSearchParams(window.location.search).get('login') === 'true');

  useEffect(() => {
    const handleScroll = () => setScrolled(window.scrollY > 40);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const scrollTo = useCallback((id: string) => {
    setMobileMenu(false);
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  const hero = useInView(0.1);
  const feat = useInView();
  const sw = useInView();
  const price = useInView();
  const proof = useInView();
  const cta = useInView();

  return (
    <div className="min-h-screen overflow-x-hidden bg-[#FBF3DB] font-sans text-surface-800 antialiased dark:bg-surface-950 dark:text-surface-100">
      <nav className={`fixed inset-x-0 top-0 z-[100] px-6 transition-all duration-300 ${scrolled ? 'border-b border-fuchsia-700/15 bg-[#FBF3DB]/95 shadow-sm backdrop-blur-md dark:border-cyan-400/20 dark:bg-surface-950/90' : 'bg-transparent'}`}>
        <div className="mx-auto flex h-16 max-w-[1120px] items-center justify-between">
          <span
            className={`${brandText} cursor-pointer text-[28px] leading-none text-fuchsia-700 dark:text-fuchsia-300`}
            onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
            role="button"
            tabIndex={0}
            aria-label="BizarreCRM - scroll to top"
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                window.scrollTo({ top: 0, behavior: 'smooth' });
              }
            }}
          >
            BIZARRECRM
          </span>
          <div className="hidden items-center gap-6 md:flex">
            {[{ label: 'Features', id: 'features' }, { label: 'Pricing', id: 'pricing' }, { label: 'Why Switch', id: 'switch' }].map(n => (
              <button
                type="button"
                key={n.id}
                onClick={() => scrollTo(n.id)}
                className={`${displayText} cursor-pointer border-0 bg-transparent text-lg text-surface-800 transition hover:text-fuchsia-700 dark:text-surface-100 dark:hover:text-fuchsia-300`}
              >
                {n.label}
              </button>
            ))}
            <ThemeToggle />
            <button type="button" className={`${outlineButton} px-5 py-2 text-sm`} onClick={() => setShowLogin(true)}>Login</button>
            <Link className={`${primaryButton} px-6 py-2.5 text-sm`} to="/signup">Get Started Free</Link>
          </div>
          <button
            type="button"
            onClick={() => setMobileMenu(!mobileMenu)}
            className="cursor-pointer border-0 bg-transparent text-2xl text-surface-800 dark:text-surface-100 md:hidden"
            aria-label={mobileMenu ? 'Close menu' : 'Open menu'}
            aria-expanded={mobileMenu}
            aria-controls="landing-mobile-menu"
          >
            {mobileMenu ? '\u2715' : '\u2630'}
          </button>
        </div>
        {mobileMenu && (
          <div id="landing-mobile-menu" className="border-t border-surface-200 bg-[#FBF3DB] px-6 pb-4 pt-2 shadow-lg dark:border-surface-800 dark:bg-surface-950 md:hidden">
            {[{ label: 'Features', id: 'features' }, { label: 'Pricing', id: 'pricing' }, { label: 'Why Switch', id: 'switch' }].map(n => (
              <button
                type="button"
                key={n.id}
                onClick={() => scrollTo(n.id)}
                className={`${displayText} block w-full cursor-pointer border-0 bg-transparent py-2.5 text-left text-xl text-surface-800 dark:text-surface-100`}
              >
                {n.label}
              </button>
            ))}
            <button type="button" className={`${outlineButton} mt-2 w-full`} onClick={() => { setMobileMenu(false); setShowLogin(true); }}>Login</button>
            <Link className={`${primaryButton} mt-2 w-full text-center`} to="/signup" onClick={() => setMobileMenu(false)}>Get Started Free</Link>
            <div className="mt-2 flex justify-center">
              <ThemeToggle />
            </div>
          </div>
        )}
      </nav>

      <section className="flex min-h-screen items-center bg-[#FBF3DB] pt-20 dark:bg-surface-950">
        <div ref={hero.ref} className="mx-auto grid max-w-[1120px] grid-cols-1 items-center gap-10 px-6 pb-[60px] pt-10 text-center md:grid-cols-2 md:text-left">
          <div>
            <p className={reveal('mb-4 text-sm font-semibold uppercase text-fuchsia-700 dark:text-fuchsia-300', hero.visible)}>
              Built by repair techs, for repair techs
            </p>
            <h1 className={reveal(`${displayText} mb-5 text-[clamp(42px,7vw,80px)] leading-none text-cyan-700 dark:text-cyan-300`, hero.visible, delayFor(1))}>
              The CRM That Actually Gets Repair Shops
            </h1>
            <p className={reveal('mb-8 max-w-[540px] text-[clamp(16px,1.6vw,20px)] leading-[1.7] text-surface-600 dark:text-surface-300', hero.visible, delayFor(2))}>
              Tickets, POS, inventory, SMS &mdash; all in one place.
              No corporate nonsense. Just tools that work the way your shop does.
            </p>
            <div className={reveal('flex flex-wrap justify-center gap-3.5 md:justify-start', hero.visible, delayFor(3))}>
              <Link className={`${primaryButton} px-10 py-4 text-[17px]`} to="/signup">Get Started Free</Link>
              <button type="button" className={outlineButton} onClick={() => setShowLogin(true)}>Login</button>
            </div>
          </div>
          <div className={reveal('flex justify-center', hero.visible, delayFor(3))}>
            <div className="w-[90%] max-w-[440px] overflow-hidden rounded-2xl">
              <img src="/landing/sticker.png" alt="Bizarre Electronics Repair" className="block w-full drop-shadow-2xl" />
            </div>
          </div>
        </div>
      </section>

      <WavyDivider />

      <section id="features" className="bg-primary-50/70 px-6 pb-20 pt-16 dark:bg-surface-900/40">
        <div ref={feat.ref} className="mx-auto max-w-[1120px]">
          <h2 className={reveal(`${displayText} mb-2 text-center text-[clamp(36px,5vw,56px)] leading-[1.1] text-cyan-800 dark:text-cyan-300`, feat.visible)}>
            Everything Your Shop Needs
          </h2>
          <p className={reveal('mb-12 text-center text-[17px] text-surface-600 dark:text-surface-300', feat.visible, delayFor(1))}>
            One platform. Zero headaches. Built for the way repair shops actually work.
          </p>
          <div className="grid grid-cols-1 gap-5 md:grid-cols-3">
            {features.map((f, i) => (
              <div
                key={f.title}
                className={reveal('cursor-default rounded-xl border border-fuchsia-700/10 bg-white/95 px-6 py-7 shadow-sm transition hover:-translate-y-1 hover:shadow-lg motion-reduce:transform-none dark:border-fuchsia-300/15 dark:bg-surface-900', feat.visible, delayFor(i + 1))}
              >
                <div className="mb-3 text-[32px]">{f.emoji}</div>
                <h3 className={`${headingText} mb-2 text-lg text-surface-900 dark:text-surface-50`}>{f.title}</h3>
                <p className="m-0 text-[15px] leading-[1.6] text-surface-600 dark:text-surface-300">{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      <section id="switch" className="bg-[#FBF3DB] px-6 pb-20 pt-16 dark:bg-surface-950">
        <div ref={sw.ref} className="mx-auto flex max-w-[1120px] flex-col gap-12 md:flex-row">
          <div className="flex-1">
            <h2 className={reveal(`${displayText} mb-5 text-[clamp(36px,5vw,56px)] leading-[1.1] text-cyan-800 dark:text-cyan-300`, sw.visible)}>
              Why Should You Switch?
            </h2>
            <div className="flex flex-col gap-4">
              {benefits.map((b, i) => (
                <div key={b} className={reveal('flex items-start gap-3.5', sw.visible, delayFor(i + 1))}>
                  <span className="mt-px shrink-0 text-xl font-bold text-fuchsia-700 dark:text-fuchsia-300">{'\u2713'}</span>
                  <span className="text-base leading-[1.5] text-surface-700 dark:text-surface-200">{b}</span>
                </div>
              ))}
            </div>
            <div className={reveal('mt-8', sw.visible, delayFor(5))}>
              <button type="button" className={magentaButton} onClick={() => scrollTo('pricing')}>See Pricing</button>
            </div>
          </div>
          <div className={reveal('flex flex-1 items-center justify-center', sw.visible, delayFor(3))}>
            <div className="aspect-[16/10] w-full max-w-[480px] overflow-hidden rounded-xl border border-surface-200 shadow-xl transition hover:scale-[1.02] motion-reduce:transform-none dark:border-surface-700 dark:shadow-black/40">
              <img src="/landing/lounge.jpg" alt="Bizarre Electronics Lounge" loading="lazy" className="block h-full w-full object-cover" />
            </div>
          </div>
        </div>
      </section>

      <WavyDivider />

      <section id="pricing" className="bg-primary-50/70 px-6 pb-20 pt-16 dark:bg-surface-900/40">
        <div ref={price.ref} className="mx-auto max-w-[1120px]">
          <h2 className={reveal(`${displayText} mb-2 text-center text-[clamp(36px,5vw,56px)] leading-[1.1] text-cyan-800 dark:text-cyan-300`, price.visible)}>
            Simple Pricing
          </h2>
          <p className={reveal('mb-12 text-center text-[17px] text-surface-600 dark:text-surface-300', price.visible, delayFor(1))}>
            Start free. Upgrade when you are ready. No contracts, no surprises.
          </p>
          <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
            {pricingTiers.map((t, i) => (
              <div
                key={t.name}
                className={reveal(
                  `relative rounded-xl bg-white/95 p-8 dark:bg-surface-900 ${t.pop ? 'scale-[1.02] border-2 border-fuchsia-700 shadow-xl shadow-fuchsia-700/10 dark:border-fuchsia-400 dark:shadow-black/40' : 'border border-surface-200 shadow-sm dark:border-surface-700 dark:shadow-black/20'}`,
                  price.visible,
                  delayFor(i + 1),
                )}
              >
                {t.badge && (
                  <div className="absolute -top-[13px] left-1/2 -translate-x-1/2 rounded-full bg-fuchsia-700 px-5 py-[5px] font-sans text-xs font-bold text-white dark:bg-fuchsia-400 dark:text-surface-950">{t.badge}</div>
                )}
                <h3 className={`${headingText} mb-1 text-[22px] text-surface-900 dark:text-surface-50`}>{t.name}</h3>
                <p className="mb-4 text-sm text-surface-600 dark:text-surface-300">{t.desc}</p>
                <div className="mb-6 flex items-baseline gap-1">
                  <span className={`${displayText} text-5xl text-surface-900 dark:text-surface-50`}>{t.price}</span>
                  <span className="text-base text-surface-600 dark:text-surface-300">{t.period}</span>
                </div>
                <ul className="mb-6 flex list-none flex-col gap-2.5 p-0">
                  {t.features.map((f) => (
                    <li key={f} className="flex items-center gap-2.5 text-[15px] text-surface-700 dark:text-surface-200">
                      <span className="font-bold text-cyan-700 dark:text-cyan-300">{'\u2713'}</span>{f}
                    </li>
                  ))}
                </ul>
                {t.name === 'Enterprise' ? (
                  <a
                    href="mailto:sales@bizarreelectronics.com?subject=Enterprise%20Plan%20Inquiry"
                    className={`${t.pop ? primaryButton : outlineButton} w-full text-center no-underline`}
                  >
                    {t.cta}
                  </a>
                ) : (
                  <Link
                    to="/signup"
                    className={`${t.pop ? primaryButton : outlineButton} w-full text-center`}
                  >
                    {t.cta}
                  </Link>
                )}
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      <section className="bg-[#FBF3DB] px-6 pb-20 pt-16 dark:bg-surface-950">
        <div ref={proof.ref} className="mx-auto max-w-[1120px]">
          <h2 className={reveal(`${displayText} mb-4 text-center text-[clamp(36px,5vw,56px)] leading-[1.1] text-fuchsia-800 dark:text-fuchsia-300`, proof.visible)}>
            Proof You Can Check Before Switching
          </h2>
          <p className={reveal('mx-auto mb-12 max-w-[680px] text-center text-[17px] leading-[1.7] text-surface-600 dark:text-surface-300', proof.visible, delayFor(1))}>
            No placeholder quotes. No mystery logos. Evaluate the plan limits, migration paths, and day-to-day workflow directly.
          </p>
          <div className="grid grid-cols-1 gap-6 md:grid-cols-3">
            {proofPoints.map((point, i) => (
              <div key={point.title} className={reveal('rounded-xl border border-surface-200 bg-white/95 p-7 shadow-sm dark:border-surface-700 dark:bg-surface-900 dark:shadow-black/20', proof.visible, delayFor(i + 1))}>
                <div className="mb-4 flex h-10 w-10 items-center justify-center rounded-lg bg-fuchsia-700/10 text-lg font-bold text-fuchsia-700 dark:bg-fuchsia-400/15 dark:text-fuchsia-300">{i + 1}</div>
                <h3 className={`${headingText} mb-3 text-lg text-surface-900 dark:text-surface-50`}>{point.title}</h3>
                <p className="m-0 text-base leading-[1.7] text-surface-600 dark:text-surface-300">{point.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      <section className="bg-primary-50/70 px-6 py-20 text-center dark:bg-surface-900/40">
        <div ref={cta.ref} className="mx-auto max-w-[640px]">
          <h2 className={reveal(`${displayText} mb-4 text-[clamp(40px,6vw,72px)] leading-[1.05] text-cyan-700 dark:text-cyan-300`, cta.visible)}>
            Ready to Fix Your Workflow?
          </h2>
          <p className={reveal('mb-8 text-lg leading-[1.6] text-surface-600 dark:text-surface-300', cta.visible, delayFor(1))}>
            Start with the free tier and upgrade when the workflow earns it.
            No credit card required.
          </p>
          <div className={reveal('', cta.visible, delayFor(2))}>
            <Link className={`${primaryButton} px-12 py-[18px] text-lg`} to="/signup">Get Started Free</Link>
          </div>
          <p className={reveal('mt-5 text-[13px] text-surface-600 dark:text-surface-400', cta.visible, delayFor(3))}>
            Free migration from RepairDesk &middot; Setup in under 5 minutes
          </p>
        </div>
      </section>

      <footer className="border-t-2 border-fuchsia-700/15 bg-[#FBF3DB] px-6 py-8 dark:border-cyan-400/15 dark:bg-surface-950">
        <div className="mx-auto flex max-w-[1120px] flex-wrap items-center justify-between gap-4">
          <div className="flex items-center gap-3">
            <span className={`${brandText} text-[22px] leading-none text-fuchsia-700 dark:text-fuchsia-300`}>BIZARRECRM</span>
          </div>
          <div className="flex flex-wrap gap-6">
            <button type="button" onClick={() => scrollTo('features')} className={`${footerAction} bg-transparent p-0`}>Features</button>
            <button type="button" onClick={() => scrollTo('pricing')} className={`${footerAction} bg-transparent p-0`}>Pricing</button>
            <a href="mailto:hello@bizarreelectronics.com" className={footerAction}>Contact</a>
            <Link to="/privacy" className={footerAction}>Privacy</Link>
            <button type="button" onClick={() => setShowLogin(true)} className={`${footerAction} bg-transparent p-0`}>Login</button>
          </div>
          <div className="text-[13px] text-surface-600 dark:text-surface-400">&copy; 2026 Bizarre Electronics Repair</div>
        </div>
      </footer>

      {showLogin && <LoginModal onClose={() => setShowLogin(false)} />}
    </div>
  );
}
