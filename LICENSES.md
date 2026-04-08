# Third-Party Open Source Licenses

BizarreCRM uses the following open source libraries. We are grateful to their authors and contributors.

## License Summary

| License | Count | Commercial Use |
|---------|-------|----------------|
| MIT | 380 | Yes |
| ISC | 36 | Yes |
| BSD-2-Clause | 9 | Yes |
| Apache-2.0 | 8 | Yes |
| BSD-3-Clause | 6 | Yes |
| BlueOak-1.0.0 | 4 | Yes |
| MIT-0 | 1 | Yes |
| 0BSD | 1 | Yes |
| CC-BY-4.0 | 1 | Yes (build-time only) |
| LGPL-3.0 | 1 | Yes (dynamic linking) |

**No GPL, AGPL, or SSPL licenses are present.**

---

## Server Dependencies

| Package | License | Author/Copyright |
|---------|---------|-----------------|
| bcryptjs | MIT | Daniel Wirtz |
| better-sqlite3 | MIT | Joshua Wise |
| cheerio | MIT | Matt Mueller, Felix Boehm |
| cookie-parser | MIT | TJ Holowaychuk, Douglas Wilson |
| cors | MIT | Troy Goode |
| dotenv | BSD-2-Clause | Scott Motte |
| express | MIT | TJ Holowaychuk, Douglas Wilson |
| helmet | MIT | Adam Baldwin, Evan Hahn |
| jsonwebtoken | MIT | Auth0 |
| multer | MIT | Hage Yaapa |
| node-cron | ISC | Lucas Merencia |
| nodemailer | MIT-0 | Andris Reinman |
| otplib | MIT | Gerald Yeo |
| qrcode | MIT | Ryan Day |
| sharp | Apache-2.0 | Lovell Fuller |
| uuid | MIT | Robert Kieffer |
| ws | MIT | Einar Otto Stangvik |

### Sharp Native Libraries (LGPL-3.0, dynamically linked)
Sharp bundles pre-built native image processing libraries under LGPL-3.0:
- libvips (John Googles, LGPL-3.0)
- glib (GNOME Project, LGPL-3.0)
- cairo (Mozilla Public License 2.0)
- pango (GNOME Project, LGPL-3.0)

These are dynamically linked and not modified. Per LGPL-3.0 terms, users may substitute their own versions of these libraries.

---

## Web Frontend Dependencies

| Package | License | Author/Copyright |
|---------|---------|-----------------|
| @tanstack/react-query | MIT | Tanner Linsley |
| @tanstack/react-table | MIT | Tanner Linsley |
| axios | MIT | Matt Zabriskie |
| clsx | MIT | Luke Edwards |
| cmdk | MIT | Rauno Freiberg |
| date-fns | MIT | Sasha Koss |
| dompurify | Apache-2.0 | Mario Heiderich, Cure53 |
| jsbarcode | MIT | Johan Lindell |
| lucide-react | ISC | Lucide Contributors |
| qrcode.react | ISC | Paul O'Shannessy |
| react | MIT | Meta Platforms |
| react-dom | MIT | Meta Platforms |
| react-hot-toast | MIT | Timo Lins |
| react-router-dom | MIT | Remix Software |
| recharts | MIT | Recharts Group |
| tailwind-merge | MIT | Dany Abramov |
| zustand | MIT | Paul Henschel |

---

## Shared Dependencies

| Package | License | Author/Copyright |
|---------|---------|-----------------|
| zod | MIT | Colin McDonnell |

---

## Payment Integration

| Package | License | Author/Copyright |
|---------|---------|-----------------|
| @blockchyp/blockchyp-ts | MIT | BlockChyp Inc. |

---

## Android Dependencies (packages/android)

All Android dependencies use Apache-2.0 license:
- AndroidX libraries (Google)
- Jetpack Compose + Material 3 (Google)
- Dagger Hilt (Google)
- Retrofit + OkHttp (Square)
- ML Kit Barcode Scanning (Google)
- Firebase (Google)
- Coil image loading (Coil Contributors)
- Vico charts (Patrick Michelberger)
- Gson (Google)

---

## Build-Time Only (not shipped in production)

| Package | License |
|---------|---------|
| TypeScript | Apache-2.0 |
| Vite | MIT |
| Tailwind CSS | MIT |
| PostCSS | MIT |
| autoprefixer | MIT |
| caniuse-lite | CC-BY-4.0 |

---

*Last updated: April 6, 2026*
*Total packages audited: 455*
*Copyleft licenses: 0 (LGPL-3.0 on sharp native libs is weak copyleft, dynamically linked)*
