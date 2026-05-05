# Setup Wizard Field Audit (SSW3)

Generated: 2026-04-26

## REQUIRED Keys (6 total)

All collected by mandatory wizard steps:
- store_name (StepWelcome)
- store_address, store_phone, store_email, store_timezone, store_currency (StepStoreInfo)

Blocks Complete button until all filled.

## OPTIONAL Keys (28 total)

Hub cards, all skippable:
- business_hours (StepBusinessHours)
- store_logo, theme_primary_color (StepLogo)
- receipt_header, receipt_footer, receipt_title (StepReceipts)
- sms_provider_type + 20 SMS/provider-specific creds (StepSmsProvider)
- smtp_host, smtp_port, smtp_user, smtp_pass, smtp_from (StepEmailSmtp)
- theme (StepWelcome)

## ADVANCED Keys (130+ total)

Settings-only, not in wizard:
- All ticket_*, pos_*, receipt_cfg_* toggles
- All repair_default_*, tax_default_*
- BlockChyp, 3CX, webhooks, membership, booking, backup, billing, etc.

## Key Gaps

### Missing from ALLOWED_CONFIG_KEYS (21 keys)
But referenced in code: catalog_auto_sync, billing_dunning_enabled, file_count_quota, grandfathered, invoice_auto_reminder, invoice_reminder_days, invoice_reminder_template, membership_enabled, owner_email, payment_provider, profit_threshold_amber, profit_threshold_green, retention_sweep_enabled, scheduled_report_email, stall_followup_days, tv_display_enabled, wallet_pass_cert_path, wallet_pass_signing_enabled, wallet_pass_team_id, wallet_pass_type_id, widget_allowed_origins, weekly_summary_last_sent_at

Action: Whitelist in ALLOWED_CONFIG_KEYS or remove from code.

### OPTIONAL Keys Not Yet in Wizard
Tax defaults, repair defaults, ticket rules, POS settings, receipt toggles, feedback config

Action (SSW2-3): Add hub cards or pre-seed defaults.

## Encrypted Fields

At rest (AES-256-GCM): smtp_pass, sms_twilio_auth_token, sms_telnyx_api_key, sms_bandwidth_password, sms_plivo_auth_token, sms_vonage_api_secret, blockchyp_api_key, blockchyp_bearer_token, blockchyp_signing_key, tcx_password, rd_access_token, rd_refresh_token

Masked as *** in audit logs; hidden from non-admins.

## Existing Wizard Coverage

| Step | Keys Written | Mandatory |
|------|-------------|-----------|
| StepWelcome | store_name, theme | YES |
| StepStoreInfo | store_address, phone, email, timezone, currency | YES |
| StepBusinessHours | business_hours | NO |
| StepLogo | store_logo, theme_primary_color | NO |
| StepReceipts | receipt_header, footer, title | NO |
| StepSmsProvider | sms_provider_type + creds | NO |
| StepEmailSmtp | smtp_host, port, user, pass, from | NO |
| StepImport | rd_access_token, refresh_token, expires | NO |
| StepTax | (tax_classes table, not config) | NO |
| StepDefaultStatuses | (ticket_statuses table, not config) | NO |

Total: 6 required + 28 optional = 34 keys collected.

## Recommendations

**SSW1:** Whitelist 21 missing keys in ALLOWED_CONFIG_KEYS.

**SSW2-3:** Add pre-seeding for tax/repair defaults or new hub cards. Mark grandfathered tenants.

**SSW4-5:** Mobile responsiveness, i18n, error recovery, analytics.

## Key Counts

- REQUIRED (Mandatory): 6
- OPTIONAL (Hub): 28
- ADVANCED (Settings Only): 130+
- Missing from ALLOWED_CONFIG_KEYS: 21
- TOTAL in ALLOWED_CONFIG_KEYS: 243

---
Generated: 2026-04-26
