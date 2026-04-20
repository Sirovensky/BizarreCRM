# Third-Party Licenses

BizarreCRM is licensed under [MIT](./LICENSE). This file enumerates the top-level declared dependencies in each workspace and the license each ships under.

> **Note:** Transitive dependencies inherit the licenses of their parents — this file tracks top-level declared deps only. Run `npx license-checker --summary` (or `npx license-checker --production --json`) from the repo root for a full transitive audit.

## License summary

| License | Commercial use | Notes |
|---|---|---|
| MIT | Yes | Most common across deps. |
| ISC | Yes | Functionally equivalent to MIT. |
| Apache-2.0 | Yes | Includes patent grant. Applies to `sharp`, `dompurify`, TypeScript, all Android libs. |
| BSD-2-Clause / BSD-3-Clause | Yes | Permissive. |
| BlueOak-1.0.0 | Yes | Permissive (used by some transitive deps). |
| MIT-0 | Yes | MIT without attribution requirement. |
| 0BSD | Yes | Zero-clause BSD. |
| CC-BY-4.0 | Yes (build-time only) | `caniuse-lite` data. |
| LGPL-3.0 | Yes (dynamic linking) | `sharp`'s bundled `libvips` / `glib` / `pango` natives. Dynamically linked, not modified — users may substitute their own. |

**No GPL, AGPL, or SSPL licenses are present in the top-level dependency set.**

---

## Server (`packages/server`)

| Package | Version | License |
|---|---|---|
| @bizarre-crm/shared | * (workspace) | MIT |
| @blockchyp/blockchyp-ts | ^2.30.1 | MIT |
| bcryptjs | ^3.0.2 | MIT |
| better-sqlite3 | ^12.8.0 | MIT |
| canvas | ^3.2.3 | MIT |
| cheerio | ^1.2.0 | MIT |
| compression | ^1.8.1 | MIT |
| cookie-parser | ^1.4.7 | MIT |
| cors | ^2.8.5 | MIT |
| dotenv | ^16.4.0 | BSD-2-Clause |
| express | ^4.21.0 | MIT |
| helmet | ^8.1.0 | MIT |
| jsbarcode | ^3.12.3 | MIT |
| jsonwebtoken | ^9.0.2 | MIT |
| multer | ^2.1.1 | MIT |
| node-cron | ^3.0.3 | ISC |
| nodemailer | ^8.0.4 | MIT-0 |
| otplib | ^13.4.0 | MIT |
| piscina | ^5.1.4 | MIT |
| qrcode | ^1.5.4 | MIT |
| sharp | ^0.34.5 | Apache-2.0 |
| stripe | ^22.0.1 | MIT |
| uuid | ^11.0.0 | MIT |
| ws | ^8.18.0 | MIT |

### Sharp native libraries (LGPL-3.0, dynamically linked)

`sharp` bundles pre-built native image-processing libraries: `libvips` (LGPL-3.0), `glib` (LGPL-3.0), `cairo` (MPL-2.0), `pango` (LGPL-3.0). These are dynamically linked and unmodified — per LGPL-3.0 terms, users may substitute their own versions.

---

## Web (`packages/web`)

| Package | Version | License |
|---|---|---|
| @bizarre-crm/shared | * (workspace) | MIT |
| @tanstack/react-query | ^5.62.0 | MIT |
| @tanstack/react-table | ^8.20.0 | MIT |
| axios | ^1.7.0 | MIT |
| clsx | ^2.1.0 | MIT |
| cmdk | ^1.0.0 | MIT |
| date-fns | ^4.1.0 | MIT |
| dompurify | ^3.3.3 | Apache-2.0 |
| jsbarcode | ^3.12.3 | MIT |
| lucide-react | ^0.468.0 | ISC |
| qrcode.react | ^4.2.0 | ISC |
| react | ^19.0.0 | MIT |
| react-dom | ^19.0.0 | MIT |
| react-hot-toast | ^2.4.0 | MIT |
| react-router-dom | ^7.1.0 | MIT |
| recharts | ^2.15.4 | MIT |
| tailwind-merge | ^2.6.0 | MIT |
| zustand | ^5.0.0 | MIT |

---

## Shared (`packages/shared`)

| Package | Version | License |
|---|---|---|
| zod | ^3.24.0 | MIT |

---

## Management dashboard (`packages/management`)

| Package | Version | License |
|---|---|---|
| @bizarre-crm/shared | * (workspace) | MIT |
| app-builder-bin | ^5.0.0-alpha.10 | MIT |
| electron | 39.8.7 (dev) | MIT |
| electron-builder | ^26.8.1 (dev) | MIT |

---

## Android (`android`)

All Android top-level deps are **Apache-2.0** (Google / Square / Coil Contributors / Patrick Michelberger), except SQLCipher which is BSD-style.

| Package | Version | License |
|---|---|---|
| androidx.core:core-ktx | 1.15.0 | Apache-2.0 |
| androidx.lifecycle:lifecycle-runtime-compose | 2.8.7 | Apache-2.0 |
| androidx.lifecycle:lifecycle-viewmodel-compose | 2.8.7 | Apache-2.0 |
| androidx.activity:activity-compose | 1.10.0 | Apache-2.0 |
| androidx.compose:compose-bom | 2025.03.00 | Apache-2.0 |
| androidx.compose.material3 | (bom) | Apache-2.0 |
| androidx.navigation:navigation-compose | 2.8.6 | Apache-2.0 |
| androidx.room:room-runtime | 2.7.0 | Apache-2.0 |
| androidx.room:room-ktx | 2.7.0 | Apache-2.0 |
| net.zetetic:sqlcipher-android | 4.6.1 | BSD-style (Zetetic) |
| androidx.sqlite:sqlite-ktx | 2.4.0 | Apache-2.0 |
| com.google.dagger:hilt-android | 2.53 | Apache-2.0 |
| androidx.hilt:hilt-navigation-compose | 1.2.0 | Apache-2.0 |
| androidx.hilt:hilt-work | 1.2.0 | Apache-2.0 |
| com.squareup.retrofit2:retrofit | 2.11.0 | Apache-2.0 |
| com.squareup.retrofit2:converter-gson | 2.11.0 | Apache-2.0 |
| com.squareup.okhttp3:okhttp | 4.12.0 | Apache-2.0 |
| com.squareup.okhttp3:logging-interceptor | 4.12.0 | Apache-2.0 |
| androidx.work:work-runtime-ktx | 2.10.0 | Apache-2.0 |
| androidx.camera:camera-camera2 | 1.4.1 | Apache-2.0 |
| androidx.camera:camera-lifecycle | 1.4.1 | Apache-2.0 |
| androidx.camera:camera-view | 1.4.1 | Apache-2.0 |
| com.google.mlkit:barcode-scanning | 17.3.0 | Apache-2.0 |
| com.google.firebase:firebase-bom | 33.8.0 | Apache-2.0 |
| com.google.firebase:firebase-messaging-ktx | (bom) | Apache-2.0 |
| io.coil-kt.coil3:coil-compose | 3.1.0 | Apache-2.0 |
| io.coil-kt.coil3:coil-network-okhttp | 3.1.0 | Apache-2.0 |
| com.patrykandpatrick.vico:compose-m3 | 2.0.1 | Apache-2.0 |
| androidx.security:security-crypto | 1.1.0-alpha06 | Apache-2.0 |
| androidx.biometric:biometric | 1.2.0-alpha05 | Apache-2.0 |
| com.google.code.gson:gson | 2.11.0 | Apache-2.0 |
| androidx.core:core-splashscreen | 1.0.1 | Apache-2.0 |
| androidx.datastore:datastore-preferences | 1.1.2 | Apache-2.0 |

---

## Build-time only (not shipped in production)

| Package | License |
|---|---|
| TypeScript | Apache-2.0 |
| Vite | MIT |
| Tailwind CSS | MIT |
| PostCSS | MIT |
| autoprefixer | MIT |
| caniuse-lite | CC-BY-4.0 |
| tsx | MIT |
| concurrently | MIT |

---

*Last regenerated: 2026-04-17. Run `npx license-checker --summary` in the repo root for a live full-transitive audit.*
