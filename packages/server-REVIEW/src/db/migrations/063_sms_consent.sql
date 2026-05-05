-- ENR-SMS3: SMS consent tracking columns on customers
ALTER TABLE customers ADD COLUMN sms_consent_marketing INTEGER NOT NULL DEFAULT 1;
ALTER TABLE customers ADD COLUMN sms_consent_transactional INTEGER NOT NULL DEFAULT 1;
ALTER TABLE customers ADD COLUMN sms_quiet_hours_start TEXT;
ALTER TABLE customers ADD COLUMN sms_quiet_hours_end TEXT;
