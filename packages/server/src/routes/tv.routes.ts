import { Router } from 'express';

const router = Router();

// SECURITY: TV display routes are intentionally public (no auth middleware).
// These endpoints serve data to wall-mounted TV screens in the shop that
// cannot authenticate. Access is controlled via the tv_display_enabled setting.
router.get('/', (req, res) => {
  const db = req.db;
  const enabled = db.prepare("SELECT value FROM store_config WHERE key = 'tv_display_enabled'").get() as { value: string } | undefined;
  if (!enabled || enabled.value !== '1') {
    res.json({ success: true, data: [] });
    return;
  }
  res.json({ success: true, data: [] });
});

export default router;
