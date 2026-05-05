-- SCAN-507 — receipt OCR cron hot path
-- receiptOcrCron: WHERE ocr_status='pending' ORDER BY created_at ASC LIMIT 10
CREATE INDEX IF NOT EXISTS idx_expense_receipt_uploads_ocr_status
  ON expense_receipt_uploads(ocr_status, created_at);

-- SCAN-511 — SLA breach cron first-response scan (partial index avoids indexing NULL rows)
-- slaBreachCron: WHERE sla_first_response_due_at <= now() AND sla_breached=0
CREATE INDEX IF NOT EXISTS idx_tickets_sla_first_response_due
  ON tickets(sla_first_response_due_at)
  WHERE sla_first_response_due_at IS NOT NULL;
