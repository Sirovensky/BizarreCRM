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

## Change log

| Date | Change | Author |
|---|---|---|
| 2026-04-20 | Initial 50-term glossary — §27 i18n scaffold | iOS Phase 10 agent |
