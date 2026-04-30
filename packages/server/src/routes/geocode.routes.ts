import { Router } from 'express';
import { asyncHandler } from '../middleware/asyncHandler.js';
import { AppError } from '../middleware/errorHandler.js';
import { createLogger } from '../utils/logger.js';

const log = createLogger('geocode');

const router = Router();

const NOMINATIM_URL = 'https://nominatim.openstreetmap.org/search';
const USER_AGENT = 'BizarreCRM/1.0 (self-hosted repair shop CRM)';

// GET /geocode?address=…
// Calls Nominatim (no API key). Returns { lat, lng } or null when not found.
// Nominatim rate-limit: 1 req/s per IP. Staff-initiated address-blur events
// are infrequent so this is well within limits.
router.get(
  '/',
  asyncHandler(async (req, res) => {
    const address = typeof req.query.address === 'string' ? req.query.address.trim() : '';
    if (!address || address.length < 5) {
      throw new AppError('address query param is required (min 5 chars)', 400);
    }
    if (address.length > 500) {
      throw new AppError('address too long (max 500 chars)', 400);
    }

    const url = new URL(NOMINATIM_URL);
    url.searchParams.set('q', address);
    url.searchParams.set('format', 'json');
    url.searchParams.set('limit', '1');
    url.searchParams.set('addressdetails', '0');

    let body: unknown;
    try {
      const response = await fetch(url.toString(), {
        headers: {
          'User-Agent': USER_AGENT,
          'Accept-Language': 'en',
        },
        signal: AbortSignal.timeout(5000),
      });
      if (!response.ok) {
        log.warn('Nominatim returned non-OK', { status: response.status });
        return void res.json({ success: true, data: null });
      }
      body = await response.json();
    } catch (err) {
      log.warn('Nominatim fetch failed', { err: err instanceof Error ? err.message : String(err) });
      return void res.json({ success: true, data: null });
    }

    const results = Array.isArray(body) ? body : [];
    if (results.length === 0) {
      return void res.json({ success: true, data: null });
    }

    const first = results[0] as Record<string, unknown>;
    const lat = parseFloat(String(first.lat ?? ''));
    const lng = parseFloat(String(first.lon ?? ''));

    if (isNaN(lat) || isNaN(lng)) {
      return void res.json({ success: true, data: null });
    }

    res.json({ success: true, data: { lat, lng } });
  }),
);

export default router;
