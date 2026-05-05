# BizarreCRM Localization Glossary

**Purpose.** Canonical term decisions per domain.  All translators and agents must follow
this glossary to prevent drift.  When a term is unlisted, open a PR adding it here
before committing a translation.

**Style guide.**
- Spanish target: informal "tú" register (not "usted") unless noted otherwise.
- Gender-inclusive phrasing preferred where grammar allows.
- Never use regional slang that excludes any Spanish-speaking territory.
- Numbers, dates, currency: always via `Locale` formatter — never translated manually.

---

## English → Spanish term table

| # | English term | Spanish (canonical) | Forbidden alternatives | Notes |
|---|---|---|---|---|
| 1 | Ticket | Ticket | Boleto, Vale, Tiquete | Kept as-is; universally understood in tech repair context |
| 2 | Invoice | Factura | Cuenta, Recibo | Legal term in LATAM/Spain |
| 3 | Estimate | Presupuesto | Cotización | Preferred in repair-shop context |
| 4 | Inventory | Inventario | Stock (standalone) | "Stock bajo" acceptable as modifier |
| 5 | Customer | Cliente | Consumidor, Usuario | Consistent across all surfaces |
| 6 | Employee | Empleado | Trabajador, Personal | Neutral form; employee list context |
| 7 | Refund | Reembolso | Devolución (for returns) | Use "reembolso" for money back; "devolución" only for physical returns |
| 8 | Discount | Descuento | Rebaja, Promoción | "Descuento" is universal |
| 9 | Membership | Membresía | Suscripción | "Membresía" is the CRM loyalty sense |
| 10 | Receipt | Comprobante | Recibo | "Comprobante" is preferred in LATAM formal contexts |
| 11 | Dashboard | Panel | Tablero, Inicio | "Panel" is concise and clear |
| 12 | Settings | Configuración | Ajustes, Preferencias | "Ajustes" is iOS-system term; use "Configuración" to differentiate from OS settings |
| 13 | Appointment | Cita | Turno, Reunión | "Cita" is standard for service scheduling |
| 14 | Category | Categoría | Tipo, Clase | Keep the accent |
| 15 | POS / Point of Sale | Punto de venta | Caja | "Punto de venta" is the full form; "PDV" acceptable in tight UI contexts |
| 16 | Report | Reporte | Informe | "Reporte" is dominant in LATAM; "Informe" in Spain |
| 17 | Expense | Gasto | Egreso, Costo | "Gasto" for operational spend |
| 18 | Payment | Pago | Cobro | "Pago" from customer perspective |
| 19 | Charge | Cobro | Cargo | "Cobro" when initiated by the business |
| 20 | Lead | Lead | Prospecto, Interesado | "Lead" kept as-is (common in sales tools in Spanish) |
| 21 | Status | Estado | Estatus | "Estado" is grammatically preferred; "Estatus" acceptable in UI label if space-constrained |
| 22 | Draft | Borrador | — | Standard |
| 23 | Archive | Archivar (v) / Archivado (n) | — | Verb vs noun form must match grammar |
| 24 | Notification | Notificación | Aviso | "Notificación" in system context |
| 25 | Sync / Syncing | Sincronizar / Sincronizando | — | Gerund for in-progress indicator |
| 26 | Offline | Sin conexión | Desconectado | "Sin conexión" is iOS-idiomatic (matches system banner) |
| 27 | In stock | En existencia | Disponible, En stock | "En existencia" is precise; "En stock" OK in tight UI |
| 28 | Out of stock | Sin existencia | Agotado | "Sin existencia" matches "En existencia" pattern |
| 29 | Low stock | Stock bajo | Pocas existencias | Short form for UI badges |
| 30 | Repair | Reparación | Arreglo | "Reparación" is formal and universally understood |
| 31 | Device | Dispositivo | Equipo, Aparato | "Dispositivo" is tech-standard |
| 32 | Technician | Técnico | — | Same in masculine; use "Técnica" when employee gender is known |
| 33 | Cashier | Persona cajera | Cajero/Cajera | Gender-neutral form per §27 inclusivity rule |
| 34 | Manager | Gerente | Encargado | "Gerente" for formal role labels |
| 35 | Role | Rol | Función, Cargo | "Rol" is consistent with software role management |
| 36 | Permission | Permiso | Acceso | "Permiso" in role/auth context |
| 37 | Serial number | Número de serie | — | Standard |
| 38 | Barcode | Código de barras | — | Standard |
| 39 | SKU | SKU | Referencia | Keep as-is; "SKU" is universally understood in retail |
| 40 | Tax | Impuesto | IVA (only if locale-specific) | "Impuesto" generically; "IVA" only when locale config confirms |
| 41 | Subtotal | Subtotal | — | Same in both languages |
| 42 | Total | Total | — | Same in both languages |
| 43 | Due date | Fecha de vencimiento | Fecha límite | "Fecha de vencimiento" for invoices/payments |
| 44 | Pick up / Picked up | Recoger (v) / Entregado (adj) | — | "Entregado" for past-tense status label |
| 45 | Intake | Recepción | Entrada | "Recepción" for the initial ticket intake step |
| 46 | Ready for pickup | Listo para recoger | Listo para entregar | "Recoger" is customer-action framing |
| 47 | Unrepairable | Sin reparación posible | Irreparable | Avoids the false cognate; sounds more natural |
| 48 | Clock in | Registrar entrada | Fichar entrada | "Registrar" is neutral across LATAM/Spain |
| 49 | Clock out | Registrar salida | Fichar salida | Same rationale |
| 50 | Lifetime value | Valor de por vida | Valor histórico | "Valor de por vida" is the standard CRM term in Spanish |

---

## Notes for future locale phases

- **French (fr)**: "ticket" stays as-is; "facture" for invoice; "devis" for estimate.
- **Portuguese (pt-BR)**: "chamado" acceptable for ticket in Brazil; confirm with native reviewers.
- **Arabic (ar)**: RTL layout required; use Eastern Arabic numerals by default unless tenant overrides.
- **CJK (zh/ja/ko)**: No plural forms; singular only.  Inter/Barlow lack CJK — SF fallback applies (see ios/CLAUDE.md).

---

## RTL (Right-to-Left) layout notes  — §27

### Supported RTL languages (roadmap)
- **Arabic (ar)** — primary RTL target; Saudi Arabia (ar-SA) is the first locale.
- **Hebrew (he)** — RTL; numerals and punctuation have nuanced bidi rules.
- **Farsi / Persian (fa)** — RTL; uses Extended Arabic-Indic numerals.
- **Urdu (ur)** — RTL; Nastaliq script; line spacing and glyph joining differ.

### Layout direction
- SwiftUI `.environment(\.layoutDirection, .rightToLeft)` flips the coordinate
  system so logical `leading` becomes the visual right, `trailing` becomes the
  visual left.
- **Never** use `.padding(.left, ...)` / `.padding(.right, ...)` — these are
  physical edges that do not flip.  Always use `.leading` / `.trailing`.
- **Never** hard-code `.environment(\.layoutDirection, .leftToRight)` outside of
  `#Preview` blocks — this overrides the system locale and locks RTL users into
  LTR layout.

### Numerals
- **Eastern Arabic-Indic** (`٠١٢٣٤٥٦٧٨٩`) — default for `ar` locale unless
  tenant disables via `NumberFormatter.locale = Locale(identifier: "en_US_POSIX")`.
- **Hebrew** — uses standard Western Arabic numerals (0–9) for prices and dates.
- **Rule**: always use `NumberFormatter` / `Decimal.FormatStyle` with
  `Locale.current` — **never** manually translate digit strings.

### Price formatting
- **Arabic (ar-SA)**: `250٫00 ر.س.` (SAR) — trailing currency symbol, decimal
  separator is `٫` (Arabic decimal separator U+066B).
- **Hebrew (he-IL)**: `₪250.00` — leading shekel sign; period decimal separator.
- **General rule**: use `NumberFormatter` with `.currencyCode` set to the
  tenant-configured currency. Example:
  ```swift
  let fmt = NumberFormatter()
  fmt.numberStyle = .currency
  fmt.currencyCode = tenantCurrencyCode   // e.g. "ILS" or "SAR"
  fmt.locale = Locale.current
  return fmt.string(from: amount as NSDecimalNumber) ?? ""
  ```

### Keyboard and text direction
- iOS automatically switches the software keyboard layout and character set when
  the device input language is Arabic / Hebrew.
- `TextField` default text alignment follows the active keyboard direction.
- Do **not** set `.multilineTextAlignment(.trailing)` unconditionally — it
  right-aligns text even in LTR locales.  Use `.leading` (bidi-safe default) or
  `.automatic` for mixed-direction fields.

### Icon mirroring policy
| Icon type | Mirrors in RTL? | Example SF Symbols |
|---|---|---|
| Directional (arrow/chevron) | **Yes** — use `RTLHelpers.directionalImage(_:)` | `arrow.right`, `chevron.right` |
| Back navigation chevron | **Yes** — SwiftUI `NavigationStack` handles automatically | `chevron.left` |
| Symmetric / non-directional | **No** — use `RTLHelpers.staticImage(_:)` | `clock`, `info.circle`, `star` |
| Loader / spinner | **No** | `arrow.clockwise` |
| Check / X mark | **No** | `checkmark`, `xmark` |

Use `RTLHelpers.directionalImage(_:)` (applies `.flipsForRightToLeftLayoutDirection(true)`)
for any arrow or chevron that communicates direction.

### Text wrapping and truncation
- Longer Arabic / Hebrew strings can be 20–40% wider than English equivalents.
- Always test with pseudo-locale (`xx-PS`) 40%-expansion tool (`gen-pseudo-loc.sh`)
  before testing with real Arabic.
- Truncation mode `.tail` in RTL clips the wrong (visual right) end.  SwiftUI's
  default `.lineLimit` + `truncationMode` respects bidi — avoid overriding
  `.truncationMode(.head)` unless intentional.
- Avoid fixed `frame(width: N)` on text containers; use `.frame(maxWidth: .infinity)`
  or `Layout` containers that adapt.

### Bidi-isolated strings (mixed content)
- English brand names, IDs, phone numbers, and URLs embedded inside Arabic
  sentences must be wrapped with Unicode bidi-isolation markers so they render
  in the correct visual order:
  - LTR isolate: U+2066 `⁦` … U+2069 `⁩`
  - Example: `"رقم الطلب ⁦BZ-0042⁩"` keeps `BZ-0042` reading left-to-right
    inside the RTL paragraph.
- SwiftUI `Text` with `.environment(\.locale, ...)` does **not** automatically
  insert bidi marks — the server must include them in API-provided strings where
  needed, or the client must inject them at render time.

### Testing strategy
- **`RTLPreviewModifier.swift`**: `.rtlPreview()` and `.bothDirectionsPreviews()`
  — use in all `#Preview` blocks.
- **`RTLPreviewCatalog.swift`**: canonical list of screens requiring coverage.
- **`rtl-lint.sh`**: CI script that flags physical-edge padding, hardwired LTR
  environment, fixed rotation angles, and hardcoded trailing alignment.
- **`RTLSmokeTests.swift`**: XCUITest suite launching four key screens with
  `-AppleLanguages (ar)` and asserting element visibility + no clipping.

---

## Change log

| Date | Change | Author |
|---|---|---|
| 2026-04-20 | Initial 50-term glossary — §27 i18n scaffold | iOS Phase 10 agent |
| 2026-04-20 | §27 RTL notes — Arabic/Hebrew/Farsi/Urdu, numeral rules, price format, icon policy, text wrapping, bidi isolation, testing strategy | iOS §27 agent |
