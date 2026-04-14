import { useState, useEffect, useRef, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { signupApi } from '../../api/endpoints';

/* ═══════════════════════════════════════════════════════════════
   Self-service signup page for new repair shops.
   Creates a new tenant via POST /api/v1/signup/, then redirects
   to the tenant's setup URL to create the admin user + 2FA.
   ═══════════════════════════════════════════════════════════════ */

// Build the tenant URL from a slug
function getTenantUrl(slug: string, path = '/'): string {
  const { protocol, port, hostname } = window.location;
  const portSuffix = port && port !== '443' && port !== '80' ? `:${port}` : '';
  // Use actual hostname domain - works in both dev (localhost) and production.
  const baseDomain = hostname === 'localhost' || hostname.endsWith('.localhost') ? 'localhost' : hostname.split('.').slice(-2).join('.');
  return `${protocol}//${slug}.${baseDomain}${portSuffix}${path}`;
}

interface FieldErrors {
  slug?: string;
  shop_name?: string;
  admin_email?: string;
  admin_password?: string;
  confirm_password?: string;
}

export function SignupPage() {
  const [slug, setSlug] = useState('');
  const [shopName, setShopName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);

  const [slugStatus, setSlugStatus] = useState<'idle' | 'checking' | 'available' | 'taken' | 'invalid'>('idle');
  const [slugMessage, setSlugMessage] = useState('');
  const [fieldErrors, setFieldErrors] = useState<FieldErrors>({});
  const [apiError, setApiError] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [success, setSuccess] = useState<{ slug: string; message: string } | null>(null);

  const slugTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);

  // Auto-generate slug from shop name
  const handleShopNameChange = (name: string) => {
    setShopName(name);
    // Only auto-fill slug if user hasn't manually edited it
    if (!slug || slug === slugify(shopName)) {
      setSlug(slugify(name));
    }
  };

  // Debounced slug availability check
  const checkSlug = useCallback((value: string) => {
    if (slugTimerRef.current) clearTimeout(slugTimerRef.current);

    if (!value || value.length < 3) {
      setSlugStatus(value ? 'invalid' : 'idle');
      setSlugMessage(value ? 'At least 3 characters' : '');
      return;
    }
    if (!/^[a-z0-9]([a-z0-9-]*[a-z0-9])?$/.test(value)) {
      setSlugStatus('invalid');
      setSlugMessage('Only lowercase letters, numbers, and hyphens');
      return;
    }

    setSlugStatus('checking');
    setSlugMessage('');

    slugTimerRef.current = setTimeout(async () => {
      try {
        const res = await signupApi.checkSlug(value);
        const { available, reason } = res.data.data;
        setSlugStatus(available ? 'available' : 'taken');
        setSlugMessage(available ? 'Available!' : (reason || 'Already taken'));
      } catch {
        setSlugStatus('idle');
        setSlugMessage('Could not check availability');
      }
    }, 400);
  }, []);

  useEffect(() => {
    checkSlug(slug);
    return () => { if (slugTimerRef.current) clearTimeout(slugTimerRef.current); };
  }, [slug, checkSlug]);

  const validate = (): boolean => {
    const errors: FieldErrors = {};
    if (!slug || slug.length < 3) errors.slug = 'Shop URL is required (min 3 characters)';
    if (slugStatus === 'taken') errors.slug = 'This name is already taken';
    if (slugStatus === 'invalid') errors.slug = 'Invalid format';
    if (!shopName.trim() || shopName.trim().length < 2) errors.shop_name = 'Shop name is required';
    if (!email.trim() || !/\S+@\S+\.\S+/.test(email)) errors.admin_email = 'Valid email is required';
    if (!password || password.length < 8) errors.admin_password = 'Password must be at least 8 characters';
    if (password !== confirmPassword) errors.confirm_password = 'Passwords do not match';
    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setApiError('');
    if (!validate()) return;

    setSubmitting(true);
    try {
      const res = await signupApi.createShop({
        slug: slug.toLowerCase().trim(),
        shop_name: shopName.trim(),
        admin_email: email.trim(),
        admin_password: password,
        captcha_token: 'dev-captcha-token',
      });
      const { message } = res.data.data;
      setSuccess({ slug: slug.toLowerCase().trim(), message });
      // Redirect after brief success message is no longer performed automatically,
      // as the user needs to check their email for the token URL.
    } catch (err: unknown) {
      const msg = (err as any)?.response?.data?.message || 'Something went wrong. Please try again.';
      setApiError(msg);
    } finally {
      setSubmitting(false);
    }
  };

  // Success state
  if (success) {
    return (
      <div style={{ minHeight: '100vh', background: '#FBF3DB', display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: "'Roboto', sans-serif" }}>
        <div style={{ textAlign: 'center', maxWidth: 440, padding: 32 }}>
          <div style={{ fontSize: 48, marginBottom: 16 }}>&#x2709;&#xFE0F;</div>
          <h2 style={{ fontFamily: "'Bebas Neue', cursive", fontSize: 36, color: '#0891B2', letterSpacing: 2, marginBottom: 8 }}>Check Your Email</h2>
          <p style={{ color: '#555', fontSize: 16, marginBottom: 24, lineHeight: 1.5 }}>
            {success.message || `We've sent a confirmation link to help finish creating your shop at ${success.slug}.`}
          </p>
          <div style={{ marginTop: 24, fontSize: 14, color: '#666' }}>
            <Link to="/" style={{ color: '#0E7490', fontWeight: 600, textDecoration: 'none' }}>Return to home</Link>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div style={{ minHeight: '100vh', background: '#FBF3DB', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '40px 16px', fontFamily: "'Roboto', sans-serif" }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=Bebas+Neue&family=League+Spartan:wght@400;500;600;700&family=Roboto:wght@400;500;700&display=swap');
      `}</style>
      <div style={{ width: '100%', maxWidth: 460 }}>
        {/* Header */}
        <div style={{ textAlign: 'center', marginBottom: 32 }}>
          <Link to="/" style={{ textDecoration: 'none', display: 'inline-block' }}>
            <span style={{ fontFamily: "'Bebas Neue', cursive", fontSize: 32, color: '#bc398f', letterSpacing: 3, cursor: 'pointer' }}>BIZARRECRM</span>
          </Link>
          <h1 style={{ fontFamily: "'Bebas Neue', cursive", fontSize: 40, color: '#0891B2', letterSpacing: 2, marginTop: 8, marginBottom: 4 }}>
            Create Your Shop
          </h1>
          <p style={{ color: '#666', fontSize: 15 }}>Free to start. No credit card required.</p>
        </div>

        {/* Form card */}
        <form onSubmit={handleSubmit} style={{ background: '#fff', borderRadius: 12, padding: 32, boxShadow: '0 4px 24px rgba(0,0,0,.08)' }}>
          {apiError && (
            <div style={{ background: '#fef2f2', border: '1px solid #fecaca', borderRadius: 8, padding: '10px 14px', marginBottom: 20, color: '#dc2626', fontSize: 14 }}>
              {apiError}
            </div>
          )}

          {/* Shop Name */}
          <FieldGroup label="Shop Name" error={fieldErrors.shop_name}>
            <input
              type="text"
              value={shopName}
              onChange={e => handleShopNameChange(e.target.value)}
              placeholder="My Repair Shop"
              maxLength={100}
              autoFocus
              style={inputStyle(!!fieldErrors.shop_name)}
            />
          </FieldGroup>

          {/* Slug */}
          <FieldGroup label="Shop URL" error={fieldErrors.slug}>
            <div style={{ display: 'flex' }}>
              <input
                type="text"
                value={slug}
                onChange={e => setSlug(e.target.value.toLowerCase().replace(/[^a-z0-9-]/g, ''))}
                placeholder="your-shop"
                maxLength={30}
                style={{ ...inputStyle(!!fieldErrors.slug), borderRadius: '8px 0 0 8px', borderRight: 'none' }}
              />
              <span style={{
                display: 'flex', alignItems: 'center', padding: '0 12px',
                background: '#f5f5f5', border: `2px solid ${fieldErrors.slug ? '#fca5a5' : '#ddd'}`,
                borderLeft: 'none', borderRadius: '0 8px 8px 0', color: '#999', fontSize: 13, whiteSpace: 'nowrap',
              }}>.{window.location.hostname === 'localhost' ? 'localhost' : window.location.hostname.split('.').slice(-2).join('.')}</span>
            </div>
            {slugStatus !== 'idle' && (
              <div style={{ marginTop: 4, fontSize: 13, color: slugStatus === 'available' ? '#16a34a' : slugStatus === 'checking' ? '#999' : '#dc2626' }}>
                {slugStatus === 'checking' ? 'Checking...' : slugMessage}
              </div>
            )}
          </FieldGroup>

          {/* Email */}
          <FieldGroup label="Email" error={fieldErrors.admin_email}>
            <input
              type="email"
              value={email}
              onChange={e => { setEmail(e.target.value); setFieldErrors(p => ({ ...p, admin_email: undefined })); }}
              placeholder="you@example.com"
              maxLength={254}
              style={inputStyle(!!fieldErrors.admin_email)}
            />
          </FieldGroup>

          {/* Password */}
          <FieldGroup label="Password" error={fieldErrors.admin_password}>
            <div style={{ position: 'relative' }}>
              <input
                type={showPassword ? 'text' : 'password'}
                value={password}
                onChange={e => { setPassword(e.target.value); setFieldErrors(p => ({ ...p, admin_password: undefined })); }}
                placeholder="Min 8 characters"
                maxLength={128}
                style={{ ...inputStyle(!!fieldErrors.admin_password), paddingRight: 44 }}
              />
              <button type="button" onClick={() => setShowPassword(!showPassword)}
                style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', background: 'none', border: 'none', color: '#999', cursor: 'pointer', fontSize: 13, fontFamily: "'Roboto', sans-serif" }}>
                {showPassword ? 'Hide' : 'Show'}
              </button>
            </div>
          </FieldGroup>

          {/* Confirm Password */}
          <FieldGroup label="Confirm Password" error={fieldErrors.confirm_password}>
            <input
              type={showPassword ? 'text' : 'password'}
              value={confirmPassword}
              onChange={e => { setConfirmPassword(e.target.value); setFieldErrors(p => ({ ...p, confirm_password: undefined })); }}
              placeholder="Repeat password"
              maxLength={128}
              style={inputStyle(!!fieldErrors.confirm_password)}
            />
          </FieldGroup>

          {/* Submit */}
          <button
            type="submit"
            disabled={submitting || slugStatus === 'checking'}
            style={{
              width: '100%', padding: '14px 0', marginTop: 8,
              background: submitting ? '#999' : '#0E7490', color: '#fff', border: 'none', borderRadius: 8,
              fontFamily: "'League Spartan', sans-serif", fontWeight: 600, fontSize: 16,
              cursor: submitting ? 'not-allowed' : 'pointer', transition: 'background .2s',
            }}
          >
            {submitting ? 'Creating Your Shop...' : 'Create My Shop'}
          </button>
        </form>

        {/* Footer links */}
        <div style={{ textAlign: 'center', marginTop: 20, fontSize: 14, color: '#666' }}>
          Already have a shop?{' '}
          <Link to="/?login=true" style={{ color: '#0E7490', fontWeight: 600, textDecoration: 'none' }}>Log in</Link>
        </div>
      </div>
    </div>
  );
}

// ─── Helpers ──────────────────────────────────────────────────

function slugify(text: string): string {
  return text.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 30);
}

function inputStyle(hasError: boolean): React.CSSProperties {
  return {
    width: '100%', padding: '11px 14px', fontSize: 15, color: '#1a1a1a',
    border: `2px solid ${hasError ? '#fca5a5' : '#ddd'}`, borderRadius: 8,
    outline: 'none', fontFamily: "'Roboto', sans-serif",
    transition: 'border-color .2s', boxSizing: 'border-box',
  };
}

function FieldGroup({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <label style={{ display: 'block', marginBottom: 6, fontSize: 14, fontWeight: 600, fontFamily: "'League Spartan', sans-serif", color: '#333' }}>
        {label}
      </label>
      {children}
      {error && <div style={{ marginTop: 4, fontSize: 13, color: '#dc2626' }}>{error}</div>}
    </div>
  );
}
