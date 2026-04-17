# Security Policy

## Reporting a Vulnerability

If you believe you've found a security vulnerability in Bizarre Electronics CRM,
please report it privately. **Do not open a public GitHub issue for security
reports.**

- Email: **security@bizarrecrm.com**
- Expected first response: within 3 business days
- Please include:
  - A clear description of the issue
  - Steps to reproduce (or a minimal proof-of-concept)
  - The affected version / commit SHA, if known
  - Your assessment of impact (data exposure, auth bypass, RCE, etc.)

We ask that you give us a reasonable window — typically 90 days, or sooner for
critical issues — to investigate and ship a fix before any public disclosure.

## Scope

In scope:

- The Node.js API server (`packages/server`)
- The React web client (`packages/web`)
- The Electron management console (`packages/management`)
- The Android companion app (`packages/android`)
- Auth, session handling, RBAC, tenant isolation, file uploads, SQL/XSS,
  SSRF, and secrets handling

Out of scope:

- Denial-of-service via traffic volume
- Issues that require physical access to a logged-in workstation
- Social-engineering of shop staff
- Third-party dependencies with no demonstrated exploit path in this codebase
  (please report those upstream; we track `npm audit` internally)

## Supported Versions

This is a shop-line-of-business application, not a widely distributed library.
We support the **latest release on `main`**. Older tagged releases (e.g.
`v1.0.0`) are not patched — upgrade to the latest commit to receive fixes.

| Version        | Supported |
| -------------- | :-------: |
| `main` (latest)| Yes       |
| `v1.0.0`       | No        |
| Older          | No        |

## Handling

After a report lands:

1. We acknowledge receipt.
2. We reproduce and confirm the issue.
3. We develop and test a fix on a private branch.
4. We ship the fix to `main` and note the CVE / internal ID in the commit body.
5. We coordinate disclosure timing with the reporter.

## Supply-chain hygiene audits

Findings from repo-wide `package.json` audits (PROD65/66/67, 2026-04-17):

- **Install hooks:** none of the five `package.json` files (root,
  `packages/server`, `packages/web`, `packages/shared`, `packages/management`)
  define `preinstall`, `postinstall`, `prepare`, `preuninstall`, or
  `postuninstall` scripts. `npm install` does not execute any repo-defined code
  at install time. Adding any of these lifecycle hooks requires a security
  review.
- **Local absolute paths in scripts:** no `C:\Users\`, `C:/`, `/home/`,
  `/Users/`, or `/mnt/c/` references anywhere in `scripts` blocks. All scripts
  are portable across dev machines.
- **`repository`/`bugs`/`homepage` fields:** intentionally absent on all
  packages (packages are private / unpublished; repo URL is tracked via
  `.git/config`).

Thank you for helping keep repair-shop data safe.
