# BizarreCRM API Contract Reference

This folder is a safe, human-readable reference for shared API request and response shapes. It is not generated code, not a runtime dependency, and not wired into any build step yet.

Update this file in the same commit whenever a shared server API shape changes and that endpoint is used by web, Android, or both.

## Safety Rules

- Do not store secrets here.
- Do not copy values from `.env`.
- Do not include real customer, shop, tenant, token, password, JWT, hCaptcha, Cloudflare, database, or production data.
- Use fake examples only, such as `demo-shop`, `admin@example.com`, and `https://demo-shop.example.com`.

## Shared Response Envelopes

Successful responses use:

```json
{
  "success": true,
  "data": {}
}
```

Error responses use:

```json
{
  "success": false,
  "message": "Human-readable error"
}
```

## Signup Mode

Current intended website signup mode is immediate tenant creation until platform email is configured.

Future email verification should remain available behind a signup mode/config flag once platform SMTP/email exists.

Relevant implementation files:

- `packages/server/src/routes/signup.routes.ts`
- `packages/web/src/pages/signup/SignupPage.tsx`
- `packages/web/src/api/endpoints.ts`

## GET /api/v1/signup/config

Public endpoint used by clients to discover the active signup mode and verification requirements.

### Success Response

```json
{
  "success": true,
  "data": {
    "enabled": true,
    "mode": "immediate",
    "emailVerificationConfigured": false,
    "captcha": {
      "enabled": false,
      "siteKey": null
    }
  }
}
```

### Fields

| Field | Type | Notes |
|---|---|---|
| `enabled` | boolean | Whether public signup is available. |
| `mode` | `"immediate" \| "email" \| "approval" \| "disabled"` | Active signup behavior. |
| `emailVerificationConfigured` | boolean | Whether platform email verification can send messages. |
| `captcha.enabled` | boolean | Whether the signup page must collect a captcha token. |
| `captcha.siteKey` | string or null | Public captcha site key only. Never put the secret here. |

## POST /api/v1/signup

Public endpoint for shop creation.

### Request

```json
{
  "slug": "demo-shop",
  "shop_name": "Demo Repair Shop",
  "admin_email": "admin@example.com",
  "admin_password": "example-password-only",
  "captcha_token": "dev-captcha-token"
}
```

### Immediate Mode Success Response

```json
{
  "success": true,
  "data": {
    "tenant_id": 123,
    "slug": "demo-shop",
    "url": "https://demo-shop.example.com",
    "message": "Shop created successfully. You can now log in.",
    "mode": "immediate"
  }
}
```

### Email Mode Pending Response

```json
{
  "success": true,
  "data": {
    "message": "Please check your email to confirm and finish creating your shop.",
    "mode": "email"
  }
}
```

### Disabled Mode Error Response

```json
{
  "success": false,
  "message": "Shop creation is temporarily unavailable."
}
```

## GET /api/v1/signup/verify/:token

Public endpoint used only when signup mode is `email`.

### Success Response

```json
{
  "success": true,
  "data": {
    "tenant_id": 123,
    "slug": "demo-shop",
    "url": "https://demo-shop.example.com",
    "message": "Shop created successfully. You can now log in.",
    "mode": "email"
  }
}
```

### Expired Or Invalid Link Response

```json
{
  "success": false,
  "message": "Invalid or expired verification link. Please sign up again."
}
```

## Drift Prevention Rule

If one of these API shapes changes, update all affected code in the same commit:

- Server route behavior in `packages/server/src/routes`
- Web API wrapper/types in `packages/web/src/api`
- Android Retrofit interface/DTOs in `packages/android/app/src/main/java/com/bizarreelectronics/crm/data/remote`
- This contract reference
