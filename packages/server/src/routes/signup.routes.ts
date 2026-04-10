import { Router, Request, Response, NextFunction } from 'express';
import { config } from '../config.js';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { validateSlug, isSlugAvailable, provisionTenant } from '../services/tenant-provisioning.js';
import { checkWindowRate, recordWindowFailure } from '../utils/rateLimiter.js';

const router = Router();

// ─── SQLite-backed rate limiters ──────────────────────────────────

// Signup creation: 5 per hour per IP
function signupLimiter(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || 'unknown';
  if (!checkWindowRate(req.db, 'signup', ip, 5, 60 * 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
    return;
  }
  recordWindowFailure(req.db, 'signup', ip, 60 * 60 * 1000);
  next();
}

// Slug check: 30 per minute per IP
function slugCheckLimiter(req: Request, res: Response, next: NextFunction): void {
  const ip = req.ip || 'unknown';
  if (!checkWindowRate(req.db, 'slug_check', ip, 30, 60 * 1000)) {
    res.status(429).json({ success: false, message: 'Too many requests. Please try again later.' });
    return;
  }
  recordWindowFailure(req.db, 'slug_check', ip, 60 * 1000);
  next();
}

// POST /signup — Create a new tenant (repair shop)
router.post('/', signupLimiter, asyncHandler(async (req: Request, res: Response) => {
  if (!config.multiTenant) {
    res.status(404).json({ success: false, message: 'Signup not available in single-tenant mode' });
    return;
  }

  const { slug, shop_name, admin_email, admin_password, admin_first_name, admin_last_name } = req.body;

  if (!slug || !shop_name || !admin_email || !admin_password) {
    res.status(400).json({ success: false, message: 'All fields required: slug, shop_name, admin_email, admin_password' });
    return;
  }

  // Input length validation (prevent bcrypt DoS and oversized payloads)
  if (typeof admin_password !== 'string' || admin_password.length > 128) {
    res.status(400).json({ success: false, message: 'Password must be at most 128 characters' });
    return;
  }
  if (typeof admin_email !== 'string' || admin_email.length > 254) {
    res.status(400).json({ success: false, message: 'Invalid email format' });
    return;
  }
  if (typeof shop_name !== 'string' || shop_name.length > 100) {
    res.status(400).json({ success: false, message: 'Shop name must be at most 100 characters' });
    return;
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
    res.status(400).json({ success: false, message: result.error });
    return;
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
}));

// GET /signup/check-slug/:slug — Check if a slug is available
router.get('/check-slug/:slug', slugCheckLimiter, (req, res) => {
  if (!config.multiTenant) {
    return res.status(404).json({ success: false, message: 'Not available' });
  }

  const slug = (req.params.slug as string).toLowerCase().trim();
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
