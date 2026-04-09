import { useState, useEffect, useRef, useCallback } from 'react';
import { useNavigate } from 'react-router-dom';

/* ═══════════════════════════════════════════════════════════════
   BizarreCRM Landing Page — v2 Fresh
   Matching bizarreelectronics.com — authentic brand, real assets
   Fonts: Bebas Neue (display) · League Spartan (headings) · Roboto (body)
   Palette: Cream #FBF3DB · Cyan #0E7490 · Magenta #bc398f · Btn #0891B2
   ═══════════════════════════════════════════════════════════════ */

function useInView(threshold = 0.12) {
  const ref = useRef<HTMLDivElement>(null);
  const [visible, setVisible] = useState(false);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    // Check if already in view on mount (mobile: hero fills viewport immediately)
    const rect = el.getBoundingClientRect();
    if (rect.top < window.innerHeight && rect.bottom > 0) {
      setVisible(true);
      return;
    }
    const obs = new IntersectionObserver(([e]) => { if (e.isIntersecting) { setVisible(true); obs.disconnect(); } }, { threshold });
    obs.observe(el);
    return () => obs.disconnect();
  }, [threshold]);
  return { ref, visible };
}

// Brand wavy divider — thick, slow-drifting magenta wave (matches IdleSteamCafe style)
function WavyDivider({ flip = false }: { flip?: boolean }) {
  return (
    <div style={{ lineHeight: 0, overflow: 'hidden', transform: flip ? 'scaleY(-1)' : undefined }}>
      <svg viewBox="0 0 1600 60" preserveAspectRatio="none" style={{ width: '200%', height: 40, display: 'block', animation: 'wave-scroll 25s linear infinite' }}>
        <path
          d="M0,30 Q100,10 200,30 Q300,50 400,30 Q500,10 600,30 Q700,50 800,30 Q900,10 1000,30 Q1100,50 1200,30 Q1300,10 1400,30 Q1500,50 1600,30"
          fill="none" stroke="#bc398f" strokeWidth="12" strokeLinecap="round" opacity="0.45"
        />
      </svg>
    </div>
  );
}

const features = [
  { title: 'Tickets & Repairs', desc: 'Track every device from check-in to pickup. Full history, notes, photos, and status updates — nothing slips through the cracks.', emoji: '\uD83D\uDD27' },
  { title: 'Point of Sale', desc: 'Ring up sales, split payments, apply discounts, print thermal receipts. Fast checkout that doesn\'t slow you down.', emoji: '\uD83D\uDCB3' },
  { title: 'Inventory', desc: 'Real-time stock levels, auto-reorder alerts, barcode scanning, supplier catalog built right in.', emoji: '\uD83D\uDCE6' },
  { title: 'SMS & Communications', desc: 'Text customers from tickets. Templates, scheduled messages, delivery tracking. No add-ons needed.', emoji: '\uD83D\uDCAC' },
  { title: 'Mobile App', desc: 'Full CRM in your pocket. Create tickets, check stock, send SMS — works even offline in the back room.', emoji: '\uD83D\uDCF1' },
  { title: 'Reports & Analytics', desc: 'Revenue trends, tech performance, parts usage, warranty claims — all in one dashboard.', emoji: '\uD83D\uDCCA' },
];

const benefits = [
  'Free tier — yes, an actual usable free tier',
  'Multiple SMS providers built in',
  'Full functionality mobile apps available',
  'Source available architecture',
  'Easy migration — import from RepairDesk, RepairShopr, or MyRepairApp in minutes',
];

const pricingTiers = [
  { name: 'Free', price: '$0', period: '/mo', desc: 'Get started with the basics', features: ['1 user', '50 tickets/month', 'Basic POS', 'Inventory tracking', 'Email support'], cta: 'Start Free', pop: false },
  { name: 'Pro', price: '$49', period: '/mo', desc: 'Everything your shop needs', badge: 'Most Popular', features: ['Unlimited users', 'Unlimited tickets', 'SMS messaging', 'Mobile app', 'Reports & analytics', 'Priority support', 'Split payments'], cta: 'Start Pro Trial', pop: true },
  { name: 'Enterprise', price: 'Custom', period: '', desc: 'Multi-location shops', features: ['Everything in Pro', 'Multi-location', 'Custom branding', 'API access', 'Dedicated support', 'SLA guarantee'], cta: 'Contact Sales', pop: false },
];

const testimonials = [
  { quote: "We switched from RepairDesk and saved hours every week. The SMS integration alone was worth it.", name: 'Mike R.', shop: 'QuickFix Mobile, Denver' },
  { quote: "Finally a CRM that doesn't feel like it was built by someone who's never touched a soldering iron.", name: 'Sarah L.', shop: 'TechRevive, Austin' },
  { quote: "The mobile app is a game-changer. I check ticket status from the bench without running to the computer.", name: 'James K.', shop: 'PhoneDoc, Miami' },
];

// Build the tenant URL from a slug
function getTenantUrl(slug: string, path = '/'): string {
  const { protocol, port, hostname } = window.location;
  const portSuffix = port && port !== '443' && port !== '80' ? `:${port}` : '';
  const baseDomain = hostname === 'localhost' || hostname.endsWith('.localhost') ? 'localhost' : hostname.split('.').slice(-2).join('.');
  return `${protocol}//${slug}.${baseDomain}${portSuffix}${path}`;
}

// Login modal — asks for shop slug, redirects to tenant login
function LoginModal({ onClose }: { onClose: () => void }) {
  const [slug, setSlug] = useState('');
  const [error, setError] = useState('');

  const handleGo = () => {
    const cleaned = slug.trim().toLowerCase().replace(/[^a-z0-9-]/g, '');
    if (!cleaned || cleaned.length < 3) {
      setError('Enter your shop name (at least 3 characters)');
      return;
    }
    window.location.href = getTenantUrl(cleaned, '/login');
  };

  return (
    <div style={{ position: 'fixed', inset: 0, zIndex: 200, display: 'flex', alignItems: 'center', justifyContent: 'center', background: 'rgba(0,0,0,.5)', backdropFilter: 'blur(4px)' }} onClick={onClose}>
      <div style={{ background: '#fff', borderRadius: 12, padding: 32, maxWidth: 420, width: '90%', boxShadow: '0 20px 60px rgba(0,0,0,.2)' }} onClick={e => e.stopPropagation()}>
        <h3 className="display" style={{ fontSize: 28, color: '#0891B2', marginBottom: 8 }}>Login to Your Shop</h3>
        <p style={{ color: '#666', fontSize: 14, marginBottom: 24 }}>Enter your shop name to go to your CRM login page.</p>
        <div style={{ display: 'flex', gap: 0, marginBottom: 8 }}>
          <input
            type="text"
            value={slug}
            onChange={e => { setSlug(e.target.value); setError(''); }}
            onKeyDown={e => e.key === 'Enter' && handleGo()}
            placeholder="yourshop"
            autoFocus
            style={{
              flex: 1, padding: '12px 14px', fontSize: 16, border: '2px solid #ddd', borderRight: 'none',
              borderRadius: '8px 0 0 8px', outline: 'none', fontFamily: "'Roboto', sans-serif",
            }}
            onFocus={e => e.currentTarget.style.borderColor = '#0E7490'}
            onBlur={e => e.currentTarget.style.borderColor = '#ddd'}
          />
          <span style={{
            display: 'flex', alignItems: 'center', padding: '0 14px',
            background: '#f5f5f5', border: '2px solid #ddd', borderLeft: 'none',
            borderRadius: '0 8px 8px 0', color: '#999', fontSize: 14, whiteSpace: 'nowrap',
          }}>.{window.location.hostname === 'localhost' || window.location.hostname.endsWith('.localhost') ? 'localhost' : window.location.hostname.split('.').slice(-2).join('.')}</span>
        </div>
        {error && <p style={{ color: '#dc2626', fontSize: 13, marginBottom: 8 }}>{error}</p>}
        <div style={{ display: 'flex', gap: 12, marginTop: 20 }}>
          <button className="btn-cyan" onClick={handleGo} style={{ flex: 1 }}>Go to Login</button>
          <button className="btn-outline" onClick={onClose} style={{ padding: '12px 24px' }}>Cancel</button>
        </div>
      </div>
    </div>
  );
}

export default function LandingPage() {
  const navigate = useNavigate();
  const [scrolled, setScrolled] = useState(false);
  const [mobileMenu, setMobileMenu] = useState(false);
  const [showLogin, setShowLogin] = useState(() => new URLSearchParams(window.location.search).get('login') === 'true');

  useEffect(() => {
    const h = () => setScrolled(window.scrollY > 40);
    window.addEventListener('scroll', h, { passive: true });
    return () => window.removeEventListener('scroll', h);
  }, []);

  const scrollTo = useCallback((id: string) => {
    setMobileMenu(false);
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
  }, []);

  const hero = useInView(0.1);
  const feat = useInView();
  const sw = useInView();
  const price = useInView();
  const test = useInView();
  const cta = useInView();

  const cl = (base: string, show: boolean, d = '') => `${base} ${show ? 'show' : ''} ${d}`;

  return (
    <div className="landing-root">
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=League+Spartan:wght@400;500;600;700&family=Roboto:wght@400;500;700&display=swap');

        .landing-root {
          font-family: 'Roboto', sans-serif;
          color: #333;
          background: #FBF3DB;
          overflow-x: hidden;
          -webkit-font-smoothing: antialiased;
        }
        .display { font-family: 'Bebas Neue', cursive; letter-spacing: 2px; }
        .heading { font-family: 'League Spartan', sans-serif; font-weight: 600; }

        /* Animations */
        .fade-up { opacity: 0; transform: translateY(24px); transition: opacity .55s ease, transform .55s ease; }
        .fade-up.show { opacity: 1; transform: translateY(0); }
        .d1 { transition-delay: .08s } .d2 { transition-delay: .16s } .d3 { transition-delay: .24s }
        .d4 { transition-delay: .32s } .d5 { transition-delay: .4s }

        /* Buttons — clean, brand-colored, WCAG AA compliant */
        .btn-cyan {
          display: inline-block; background: #0E7490; color: #fff; border: none;
          padding: 14px 36px; border-radius: 6px; font-family: 'League Spartan', sans-serif;
          font-weight: 600; font-size: 16px; cursor: pointer; transition: all .2s;
          text-decoration: none;
        }
        .btn-cyan:hover { background: #155E75; transform: translateY(-1px); box-shadow: 0 4px 16px rgba(14,116,144,.35); }

        .btn-magenta {
          display: inline-block; background: #bc398f; color: #fff; border: none;
          padding: 14px 36px; border-radius: 6px; font-family: 'League Spartan', sans-serif;
          font-weight: 600; font-size: 16px; cursor: pointer; transition: all .2s;
          text-decoration: none;
        }
        .btn-magenta:hover { background: #a82e7d; transform: translateY(-1px); box-shadow: 0 4px 16px rgba(188,57,143,.3); }

        .btn-outline {
          display: inline-block; background: transparent; color: #0E7490; border: 2px solid #0E7490;
          padding: 12px 34px; border-radius: 6px; font-family: 'League Spartan', sans-serif;
          font-weight: 600; font-size: 16px; cursor: pointer; transition: all .2s;
          text-decoration: none;
        }
        .btn-outline:hover { background: #0E7490; color: #fff; }

        /* Grid paper subtle background */
        .grid-bg {
          background-image:
            linear-gradient(rgba(188,57,143,.06) 1px, transparent 1px),
            linear-gradient(90deg, rgba(188,57,143,.06) 1px, transparent 1px);
          background-size: 28px 28px;
        }

        /* Photo styling */
        .photo-card {
          border-radius: 12px; overflow: hidden;
          box-shadow: 0 8px 32px rgba(0,0,0,.12);
          transition: transform .3s ease;
        }
        .photo-card:hover { transform: scale(1.02); }
        .photo-card img { display: block; width: 100%; height: 100%; object-fit: cover; }

        @keyframes wave-scroll { 0% { transform: translateX(0); } 100% { transform: translateX(-50%); } }

        html { scroll-behavior: smooth; }
        ::selection { background: rgba(188,57,143,.2); }

        /* Responsive grid helper */
        @media (min-width: 768px) {
          .hero-grid { grid-template-columns: 1fr 1fr !important; text-align: left !important; }
          .hero-grid .hero-text { text-align: left !important; }
          .hero-grid .hero-btns { justify-content: flex-start !important; }
          .feat-grid { grid-template-columns: repeat(3, 1fr) !important; }
          .price-grid { grid-template-columns: repeat(3, 1fr) !important; }
          .test-grid { grid-template-columns: repeat(3, 1fr) !important; }
          .benefit-row { flex-direction: row !important; }
        }
      `}</style>

      {/* ═══ NAV ═══ */}
      <nav style={{
        position: 'fixed', top: 0, left: 0, right: 0, zIndex: 100,
        background: scrolled ? 'rgba(251,243,219,.96)' : 'transparent',
        backdropFilter: scrolled ? 'blur(10px)' : 'none',
        boxShadow: scrolled ? '0 1px 0 rgba(188,57,143,.15)' : 'none',
        transition: 'all .3s', padding: '0 24px',
      }}>
        <div style={{ maxWidth: 1120, margin: '0 auto', display: 'flex', alignItems: 'center', justifyContent: 'space-between', height: 64 }}>
          <span className="display" onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })} style={{ fontSize: 28, color: '#bc398f', letterSpacing: 3, cursor: 'pointer' }}>BIZARRECRM</span>
          <div className="hidden md:flex" style={{ alignItems: 'center', gap: 24 }}>
            {[{ l: 'Features', id: 'features' }, { l: 'Pricing', id: 'pricing' }, { l: 'Why Switch', id: 'switch' }].map(n => (
              <button key={n.id} onClick={() => scrollTo(n.id)} className="display" style={{ background: 'none', border: 'none', color: '#333', fontSize: 20, cursor: 'pointer', letterSpacing: 2 }}>{n.l}</button>
            ))}
            <button className="btn-outline" onClick={() => setShowLogin(true)} style={{ padding: '8px 20px', fontSize: 14 }}>Login</button>
            <button className="btn-cyan" onClick={() => navigate('/signup')} style={{ padding: '10px 24px', fontSize: 14 }}>Get Started Free</button>
          </div>
          <button onClick={() => setMobileMenu(!mobileMenu)} className="md:hidden" style={{ background: 'none', border: 'none', color: '#333', cursor: 'pointer', fontSize: 24 }}>{mobileMenu ? '\u2715' : '\u2630'}</button>
        </div>
        {mobileMenu && (
          <div className="md:hidden" style={{ padding: '8px 24px 16px', background: '#FBF3DB' }}>
            {[{ l: 'Features', id: 'features' }, { l: 'Pricing', id: 'pricing' }, { l: 'Why Switch', id: 'switch' }].map(n => (
              <button key={n.id} onClick={() => scrollTo(n.id)} className="display" style={{ display: 'block', background: 'none', border: 'none', color: '#333', fontSize: 20, padding: '10px 0', width: '100%', textAlign: 'left', cursor: 'pointer' }}>{n.l}</button>
            ))}
            <button className="btn-outline" onClick={() => { setMobileMenu(false); setShowLogin(true); }} style={{ marginTop: 8, width: '100%' }}>Login</button>
            <button className="btn-cyan" onClick={() => navigate('/signup')} style={{ marginTop: 8, width: '100%' }}>Get Started Free</button>
          </div>
        )}
      </nav>

      {/* ═══ HERO ═══ */}
      <section style={{ minHeight: '100vh', display: 'flex', alignItems: 'center', paddingTop: 80, background: '#FBF3DB' }}>
        <div ref={hero.ref} className="hero-grid" style={{ maxWidth: 1120, margin: '0 auto', padding: '40px 24px 60px', display: 'grid', gridTemplateColumns: '1fr', gap: 40, alignItems: 'center', textAlign: 'center' }}>
          <div className="hero-text">
            <p className={cl('fade-up', hero.visible)} style={{ color: '#bc398f', fontWeight: 600, fontSize: 14, letterSpacing: 2, textTransform: 'uppercase', marginBottom: 16 }}>
              Built by repair techs, for repair techs
            </p>
            <h1 className={cl('fade-up display', hero.visible, 'd1')} style={{ fontSize: 'clamp(42px, 7vw, 80px)', lineHeight: 1, color: '#0891B2', marginBottom: 20 }}>
              The CRM That Actually Gets Repair Shops
            </h1>
            <p className={cl('fade-up', hero.visible, 'd2')} style={{ fontSize: 'clamp(16px, 1.6vw, 20px)', color: '#555', lineHeight: 1.7, marginBottom: 32, maxWidth: 540 }}>
              Tickets, POS, inventory, SMS &mdash; all in one place.
              No corporate nonsense. Just tools that work the way your shop does.
            </p>
            <div className={cl('fade-up hero-btns', hero.visible, 'd3')} style={{ display: 'flex', gap: 14, flexWrap: 'wrap', justifyContent: 'center' }}>
              <button className="btn-cyan" onClick={() => navigate('/signup')} style={{ padding: '16px 40px', fontSize: 17 }}>Get Started Free</button>
              <button className="btn-outline" onClick={() => setShowLogin(true)}>Login</button>
            </div>
          </div>
          <div className={cl('fade-up', hero.visible, 'd3')} style={{ display: 'flex', justifyContent: 'center' }}>
            <div style={{ maxWidth: 440, width: '90%', overflow: 'hidden', borderRadius: 16 }}>
              <img src="/landing/sticker.png" alt="Bizarre Electronics Repair" style={{ width: '100%', display: 'block', filter: 'drop-shadow(0 12px 32px rgba(188,57,143,.15))' }} />
            </div>
          </div>
        </div>
      </section>

      <WavyDivider />

      {/* ═══ FEATURES ═══ */}
      <section id="features" className="grid-bg" style={{ background: '#FBF3DB', padding: '64px 24px 80px' }}>
        <div ref={feat.ref} style={{ maxWidth: 1120, margin: '0 auto' }}>
          <h2 className={cl('fade-up display', feat.visible)} style={{ fontSize: 'clamp(36px, 5vw, 56px)', textAlign: 'center', color: '#0E7490', marginBottom: 8, lineHeight: 1.1 }}>
            Everything Your Shop Needs
          </h2>
          <p className={cl('fade-up', feat.visible, 'd1')} style={{ textAlign: 'center', color: '#555', marginBottom: 48, fontSize: 17 }}>
            One platform. Zero headaches. Built for the way repair shops actually work.
          </p>
          <div className="feat-grid" style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 20 }}>
            {features.map((f, i) => (
              <div key={i} className={cl('fade-up', feat.visible, `d${Math.min(i + 1, 5)}`)}
                style={{
                  background: '#fff', borderRadius: 12, padding: '28px 24px',
                  border: '1px solid rgba(188,57,143,.1)',
                  transition: 'box-shadow .25s, transform .25s', cursor: 'default',
                }}
                onMouseEnter={e => { e.currentTarget.style.boxShadow = '0 8px 28px rgba(0,0,0,.08)'; e.currentTarget.style.transform = 'translateY(-3px)'; }}
                onMouseLeave={e => { e.currentTarget.style.boxShadow = 'none'; e.currentTarget.style.transform = ''; }}
              >
                <div style={{ fontSize: 32, marginBottom: 12 }}>{f.emoji}</div>
                <h3 className="heading" style={{ fontSize: 18, marginBottom: 8, color: '#222' }}>{f.title}</h3>
                <p style={{ color: '#666', fontSize: 15, lineHeight: 1.6, margin: 0 }}>{f.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      {/* ═══ WHY SWITCH ═══ */}
      <section id="switch" style={{ background: '#FBF3DB', padding: '64px 24px 80px' }}>
        <div ref={sw.ref} className="benefit-row" style={{ maxWidth: 1120, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 48 }}>
          <div style={{ flex: 1 }}>
            <h2 className={cl('fade-up display', sw.visible)} style={{ fontSize: 'clamp(36px, 5vw, 56px)', color: '#0E7490', marginBottom: 8, lineHeight: 1.1 }}>
              Why Should You Switch?
            </h2>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
              {benefits.map((b, i) => (
                <div key={i} className={cl('fade-up', sw.visible, `d${Math.min(i + 1, 5)}`)}
                  style={{ display: 'flex', gap: 14, alignItems: 'flex-start' }}>
                  <span style={{ color: '#bc398f', fontSize: 20, fontWeight: 700, flexShrink: 0, marginTop: 1 }}>{'\u2713'}</span>
                  <span style={{ fontSize: 16, color: '#444', lineHeight: 1.5 }}>{b}</span>
                </div>
              ))}
            </div>
            <div className={cl('fade-up', sw.visible, 'd5')} style={{ marginTop: 32 }}>
              <button className="btn-magenta" onClick={() => scrollTo('pricing')}>See Pricing</button>
            </div>
          </div>
          <div className={cl('fade-up', sw.visible, 'd3')} style={{ flex: 1, display: 'flex', justifyContent: 'center', alignItems: 'center' }}>
            <div className="photo-card" style={{ maxWidth: 480, width: '100%', aspectRatio: '16/10' }}>
              <img src="/landing/lounge.jpg" alt="Bizarre Electronics Lounge" loading="lazy" />
            </div>
          </div>
        </div>
      </section>

      <WavyDivider />

      {/* ═══ PRICING ═══ */}
      <section id="pricing" className="grid-bg" style={{ background: '#FBF3DB', padding: '64px 24px 80px' }}>
        <div ref={price.ref} style={{ maxWidth: 1120, margin: '0 auto' }}>
          <h2 className={cl('fade-up display', price.visible)} style={{ fontSize: 'clamp(36px, 5vw, 56px)', textAlign: 'center', color: '#0E7490', marginBottom: 8, lineHeight: 1.1 }}>
            Simple Pricing
          </h2>
          <p className={cl('fade-up', price.visible, 'd1')} style={{ textAlign: 'center', color: '#555', marginBottom: 48, fontSize: 17 }}>
            Start free. Upgrade when you're ready. No contracts, no surprises.
          </p>
          <div className="price-grid" style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 24 }}>
            {pricingTiers.map((t, i) => (
              <div key={i} className={cl('fade-up', price.visible, `d${i + 1}`)} style={{
                background: '#fff', borderRadius: 12, padding: 32, position: 'relative',
                border: t.pop ? '2px solid #bc398f' : '1px solid rgba(0,0,0,.08)',
                boxShadow: t.pop ? '0 12px 40px rgba(188,57,143,.12)' : '0 2px 12px rgba(0,0,0,.04)',
                transform: t.pop ? 'scale(1.02)' : 'none',
              }}>
                {t.badge && (
                  <div style={{ position: 'absolute', top: -13, left: '50%', transform: 'translateX(-50%)', background: '#bc398f', color: 'white', padding: '5px 20px', borderRadius: 20, fontSize: 12, fontWeight: 700, letterSpacing: 1, fontFamily: "'League Spartan', sans-serif" }}>{t.badge}</div>
                )}
                <h3 className="heading" style={{ fontSize: 22, color: '#222', marginBottom: 4 }}>{t.name}</h3>
                <p style={{ color: '#666', fontSize: 14, marginBottom: 16 }}>{t.desc}</p>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginBottom: 24 }}>
                  <span className="display" style={{ fontSize: 48, color: '#222' }}>{t.price}</span>
                  <span style={{ color: '#666', fontSize: 16 }}>{t.period}</span>
                </div>
                <ul style={{ listStyle: 'none', padding: 0, margin: '0 0 24px', display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {t.features.map((f, fi) => (
                    <li key={fi} style={{ display: 'flex', alignItems: 'center', gap: 10, fontSize: 15, color: '#555' }}>
                      <span style={{ color: '#0E7490', fontWeight: 700 }}>{'\u2713'}</span>{f}
                    </li>
                  ))}
                </ul>
                <button className={t.pop ? 'btn-cyan' : 'btn-outline'} onClick={() => navigate('/signup')} style={{ width: '100%' }}>{t.cta}</button>
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      {/* ═══ TESTIMONIALS ═══ */}
      <section style={{ background: '#FBF3DB', padding: '64px 24px 80px' }}>
        <div ref={test.ref} style={{ maxWidth: 1120, margin: '0 auto' }}>
          <h2 className={cl('fade-up display', test.visible)} style={{ fontSize: 'clamp(36px, 5vw, 56px)', textAlign: 'center', color: '#924299', marginBottom: 48, lineHeight: 1.1 }}>
            Shops That Made The Switch
          </h2>
          <div className="test-grid" style={{ display: 'grid', gridTemplateColumns: '1fr', gap: 24 }}>
            {testimonials.map((t, i) => (
              <div key={i} className={cl('fade-up', test.visible, `d${i + 1}`)} style={{
                background: '#fff', borderRadius: 12, padding: 28,
                border: '1px solid rgba(0,0,0,.06)',
                boxShadow: '0 2px 12px rgba(0,0,0,.04)',
              }}>
                <div style={{ fontSize: 40, color: '#bc398f', opacity: .2, fontFamily: 'Georgia, serif', lineHeight: 1, marginBottom: 8 }}>{'\u201C'}</div>
                <p style={{ fontSize: 16, lineHeight: 1.7, color: '#444', marginBottom: 20 }}>{t.quote}</p>
                <div className="heading" style={{ fontSize: 15, color: '#222' }}>{t.name}</div>
                <div style={{ fontSize: 14, color: '#666' }}>{t.shop}</div>
              </div>
            ))}
          </div>
        </div>
      </section>

      <WavyDivider />

      {/* ═══ FINAL CTA ═══ */}
      <section style={{ background: '#FBF3DB', padding: '80px 24px', textAlign: 'center' }}>
        <div ref={cta.ref} style={{ maxWidth: 640, margin: '0 auto' }}>
          <h2 className={cl('fade-up display', cta.visible)} style={{ fontSize: 'clamp(40px, 6vw, 72px)', color: '#0891B2', lineHeight: 1.05, marginBottom: 16 }}>
            Ready to Fix Your Workflow?
          </h2>
          <p className={cl('fade-up', cta.visible, 'd1')} style={{ color: '#666', fontSize: 18, marginBottom: 32, lineHeight: 1.6 }}>
            Join hundreds of repair shops running on BizarreCRM.
            No credit card required.
          </p>
          <div className={cl('fade-up', cta.visible, 'd2')}>
            <button className="btn-cyan" onClick={() => navigate('/signup')} style={{ fontSize: 18, padding: '18px 48px' }}>Get Started Free</button>
          </div>
          <p className={cl('fade-up', cta.visible, 'd3')} style={{ color: '#666', fontSize: 13, marginTop: 20 }}>
            Free migration from RepairDesk &middot; Setup in under 5 minutes
          </p>
        </div>
      </section>

      {/* ═══ FOOTER ═══ */}
      <footer style={{ borderTop: '2px solid rgba(188,57,143,.15)', padding: '32px 24px', background: '#FBF3DB' }}>
        <div style={{ maxWidth: 1120, margin: '0 auto', display: 'flex', flexWrap: 'wrap', justifyContent: 'space-between', alignItems: 'center', gap: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <span className="display" style={{ fontSize: 22, color: '#bc398f', letterSpacing: 3 }}>BIZARRECRM</span>
          </div>
          <div style={{ display: 'flex', gap: 24, fontSize: 14 }}>
            {['Features', 'Pricing', 'Contact', 'Privacy'].map(l => (
              <a key={l} href={`#${l.toLowerCase()}`} style={{ color: '#666', textDecoration: 'none', fontFamily: "'League Spartan', sans-serif", fontWeight: 500 }}
                onMouseEnter={e => (e.target as HTMLElement).style.color = '#bc398f'}
                onMouseLeave={e => (e.target as HTMLElement).style.color = '#888'}>
                {l}
              </a>
            ))}
            <button onClick={() => setShowLogin(true)} style={{ background: 'none', border: 'none', color: '#666', cursor: 'pointer', fontFamily: "'League Spartan', sans-serif", fontWeight: 500, fontSize: 14, padding: 0 }}
              onMouseEnter={e => (e.target as HTMLElement).style.color = '#bc398f'}
              onMouseLeave={e => (e.target as HTMLElement).style.color = '#666'}>
              Login
            </button>
          </div>
          <div style={{ fontSize: 13, color: '#666' }}>&copy; 2026 Bizarre Electronics Repair</div>
        </div>
      </footer>

      {/* Login Modal */}
      {showLogin && <LoginModal onClose={() => setShowLogin(false)} />}
    </div>
  );
}
