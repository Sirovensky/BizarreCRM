import { Router, Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { validateSlug, isSlugAvailable, provisionTenant } from '../services/tenant-provisioning.js';

const router = Router();

// ─── In-memory rate limiters ───────────────────────────────────────

interface RateBucket { count: number; resetAt: number; }

const signupAttempts = new Map<string, RateBucket>();
const slugCheckAttempts = new Map<string, RateBucket>();

// Cleanup stale entries every 10 minutes
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of signupAttempts) { if (v.resetAt < now) signupAttempts.delete(k); }
  for (const [k, v] of slugCheckAttempts) { if (v.resetAt < now) slugCheckAttempts.delete(k); }
}, 10 * 60 * 1000);

function makeRateLimiter(store: Map<string, RateBucket>, maxRequests: number, windowMs: number) {
  return (req: Request, res: Response, next: NextFunction): void => {
    const ip = req.ip || 'unknown';
    const now = Date.now();
    const bucket = store.get(ip);

    if (bucket && bucket.resetAt > now) {
      if (bucket.count >= maxRequests) {
        res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
        return;
      }
      bucket.count++;
    } else {
      store.set(ip, { count: 1, resetAt: now + windowMs });
    }
    next();
  };
}

// Signup creation: 5 per hour per IP
const signupLimiter = makeRateLimiter(signupAttempts, 5, 60 * 60 * 1000);

// Slug check: 30 per minute per IP
const slugCheckLimiter = makeRateLimiter(slugCheckAttempts, 30, 60 * 1000);

// POST /signup — Create a new tenant (repair shop)
router.post('/', signupLimiter, async (req, res) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Signup not available in single-tenant mode' });
  }

  const { slug, shop_name, admin_email, admin_password, admin_first_name, admin_last_name } = req.body;

  if (!slug || !shop_name || !admin_email || !admin_password) {
    return res.status(400).json({
      success: false,
      message: 'All fields required: slug, shop_name, admin_email, admin_password',
    });
  }

  // Input length validation (prevent bcrypt DoS and oversized payloads)
  if (typeof admin_password !== 'string' || admin_password.length > 128) {
    return res.status(400).json({ success: false, message: 'Password must be at most 128 characters' });
  }
  if (typeof admin_email !== 'string' || admin_email.length > 254) {
    return res.status(400).json({ success: false, message: 'Invalid email format' });
  }
  if (typeof shop_name !== 'string' || shop_name.length > 100) {
    return res.status(400).json({ success: false, message: 'Shop name must be at most 100 characters' });
  }

  const result = await provisionTenant({
    slug: slug.toLowerCase().trim(),
    name: shop_name.trim(),
    adminEmail: admin_email.trim(),
    adminPassword: admin_password,
    adminFirstName: admin_first_name?.trim(),
    adminLastName: admin_last_name?.trim(),
  });

  if (!result.success) {
    return res.status(400).json({ success: false, message: result.error });
  }

  res.status(201).json({
    success: true,
    data: {
      tenant_id: result.tenantId,
      slug: result.slug,
      url: `https://${result.slug}.${config.baseDomain}`,
      message: 'Shop created successfully. You can now log in.',
    },
  });
});

// GET /signup/check-slug/:slug — Check if a slug is available
router.get('/check-slug/:slug', slugCheckLimiter, (req, res) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Not available' });
  }

  const slug = req.params.slug.toLowerCase().trim();
  const validation = validateSlug(slug);

  if (!validation.valid) {
    return res.json({ success: true, data: { available: false, reason: validation.error } });
  }

  const available = isSlugAvailable(slug);
  res.json({
    success: true,
    data: { available, reason: available ? null : 'This name is already taken' },
  });
});

export default router;
