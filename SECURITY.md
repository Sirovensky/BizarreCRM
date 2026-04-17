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

### Dependency typo-squat audit (PROD64, 2026-04-17)

**Methodology.** Enumerated top-level `dependencies` and `devDependencies`
across all five in-repo `package.json` files (root, `packages/server`,
`packages/web`, `packages/shared`, `packages/management`) — vendored packages
under `dashboard/resources/crm-source/` and any `node_modules/` subtrees were
excluded. Each unique name was checked against:

1. ASCII/Unicode homoglyph patterns (Cyrillic/Greek confusables such as
   `lodaѕh` with U+0455, Greek `ο` in `eХpress`, etc.) — visual/byte-level
   inspection of all names.
2. Known typo-squat patterns (`reqeust`/`reqest` vs `request`, `loadsh`/`lodahs`
   vs `lodash`, `expres` vs `express`, `axios2`, `mom3nt`, `chakra-uii`,
   `reactt`, `react-dom2`, `next-js`, `babl`, `crosss-spawn`, misspelled scoped
   packages like `@eletron`/`@electronn`).
3. Registry sanity check via `npm view <name> name maintainers time.created`
   for every package — confirmed each resolves to the canonical package, has
   multi-year publish history (earliest: `nodemailer` 2011-01-21; most recent:
   `tailwind-merge` 2021-07-18), and is published by a reasonable maintainer
   set (well-known individuals, org accounts, or official bot accounts).
4. `@types/*` packages — all eighteen confirmed published by Microsoft's
   official DefinitelyTyped bot account (`types <ts-npm-types@microsoft.com>`).

**Packages audited.** 60 unique non-workspace entries:
`@bizarre-crm/shared` (internal workspace, skipped),
`@blockchyp/blockchyp-ts`, `@tanstack/react-query`, `@tanstack/react-table`,
`@types/bcryptjs`, `@types/better-sqlite3`, `@types/cheerio`,
`@types/compression`, `@types/cookie-parser`, `@types/cors`,
`@types/dompurify`, `@types/express`, `@types/jsbarcode`,
`@types/jsonwebtoken`, `@types/multer`, `@types/node-cron`,
`@types/nodemailer`, `@types/qrcode`, `@types/react`, `@types/react-dom`,
`@types/uuid`, `@types/ws`, `@vitejs/plugin-react`, `app-builder-bin`,
`autoprefixer`, `axios`, `bcryptjs`, `better-sqlite3`, `canvas`, `cheerio`,
`clsx`, `cmdk`, `compression`, `concurrently`, `cookie-parser`, `cors`,
`date-fns`, `dompurify`, `dotenv`, `electron`, `electron-builder`, `express`,
`helmet`, `jsbarcode`, `jsonwebtoken`, `lucide-react`, `multer`, `node-cron`,
`nodemailer`, `otplib`, `piscina`, `postcss`, `qrcode`, `qrcode.react`,
`react`, `react-dom`, `react-hot-toast`, `react-router-dom`, `recharts`,
`sharp`, `stripe`, `tailwind-merge`, `tailwindcss`, `tsx`, `typescript`,
`uuid`, `vite`, `ws`, `zod`, `zustand`.

**Result:** Clean — 60 packages audited, 0 suspicious. Zero homoglyphs, zero
typo-squat matches, zero low-reputation or recently created namespaces. Every
dependency resolves to a well-established registry entry with a reasonable
maintainer set.

**Recommendation.** No removals or replacements required. Re-run this audit
whenever a new top-level dependency is added (any new name that appears in a
`package.json` during code review should be grep'd against this list and
registry-checked before merge).

Thank you for helping keep repair-shop data safe.
