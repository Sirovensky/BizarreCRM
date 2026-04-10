import { Router } from 'express';

const router = Router();

// SECURITY: TV display routes are intentionally public (no auth middleware).
// These endpoints serve data to wall-mounted TV screens in the shop that
// cannot authenticate. Access is controlled via the tv_display_enabled setting.
router.get('/', async (req, res) => {
  const adb = req.asyncDb;
  const enabled = await adb.get<{ value: string }>("SELECT value FROM store_config WHERE key = 'tv_display_enabled'");
  if (!enabled || enabled.value !== '1') {
    res.json({ success: true, data: [] });
    return;
  }
  res.json({ success: true, data: [] });
});

export default router;
