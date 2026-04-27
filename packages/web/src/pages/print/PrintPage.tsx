/**
 * Print page — ticket receipt / intake label
 * Route: /print/ticket/:id?size=receipt80|receipt58|label|letter&type=receipt
 *
 * Paper sizes:
 *   receipt80  — 80mm thermal receipt
 *   receipt58  — 58mm thermal receipt
 *   label      — 4"x2" label
 *   letter     — Full US Letter (8.5x11")
 *
 * type=receipt shows payment info; otherwise renders as work order.
 * All receipt content is driven by the 26 receipt_cfg_* toggles in store_config.
 */
import { useEffect, useRef } from 'react';
import { useParams, useSearchParams } from 'react-router-dom';
import { useQuery } from '@tanstack/react-query';
import DOMPurify from 'dompurify';
import { ticketApi, settingsApi } from '@/api/endpoints';
import JsBarcode from 'jsbarcode'; // eslint-disable-line
import { formatCurrency } from '@/utils/format';

type PaperSize = 'receipt80' | 'receipt58' | 'label' | 'letter';

// SCAN-1014: replace the blanket `ticket: any` / `devices: any[]` etc. with
// narrow print-surface types. These cover every property access in this
// file — other fields the server returns are ignored by design (print
// layouts are intentionally a read-only subset of the ticket DTO). Using
// `undefined`-tolerant optionals rather than guarding every read keeps the
// JSX short while still catching typos at compile time.
// Permissive by design — the print surface reads many optional fields from
// the ticket DTO (which varies by tenant schema and by the route that
// produced it). The `[key: string]: unknown` escape hatch lets the JSX
// access tenant-specific extras without a type error, while the named
// fields below keep compile-time help for the common set.
// Intentionally permissive — the print surface reads many tenant-custom
// extras (device type, security_code, warranty_timeframe, service.name
// etc.) that aren't stable enough across tenants to hard-type. Using an
// index signature still gives the JSX compile-time help for the common
// fields while letting extras pass without cast churn.
interface PrintPart extends Record<string, any> {
  part_name?: string | null;
  name?: string | null;
  quantity?: number | null;
  status?: string | null;
}

interface PrintDevice extends Record<string, any> {
  device_name?: string | null;
  imei?: string | null;
  serial?: string | null;
  color?: string | null;
  condition?: string | null;
  issue?: string | null;
  notes?: string | null;
  parts?: PrintPart[];
}

interface PrintPayment extends Record<string, any> {
  method?: string | null;
  reference?: string | null;
  note?: string | null;
  created_at?: string | null;
}

interface PrintNote extends Record<string, any> {
  content?: string | null;
  note_type?: string | null;
  created_at?: string | null;
  author_name?: string | null;
}

interface PrintCustomer extends Record<string, any> {
  first_name?: string | null;
  last_name?: string | null;
  phone?: string | null;
  mobile?: string | null;
  email?: string | null;
}

interface PrintTicket extends Record<string, any> {
  id?: number;
  order_id?: string | null;
  customer?: PrintCustomer | null;
  created_at?: string | null;
  updated_at?: string | null;
  status_name?: string | null;
  notes?: PrintNote[];
  devices?: PrintDevice[];
  payments?: PrintPayment[];
}

type PrintConfig = Record<string, string>;

/**
 * Only allow logo URLs that are relative paths or https://.
 * PDF6 fix: also reject data:image/svg+xml (SVG can carry script via inline
 * handlers / <script> elements) and any explicit data:/javascript:/file: URI.
 * Bare protocol-relative URLs are rejected too — upstream code can still send
 * them if a shop owner tries to work around this, but the print page will
 * silently not render the image rather than loading something we can't vet.
 */
function isSafeLogoUrl(url: string | null | undefined): boolean {
  if (!url) return false;
  const trimmed = url.trim().toLowerCase();
  if (!trimmed) return false;
  // Block anything that isn't a relative path or explicit https://
  if (trimmed.startsWith('data:')) return false;
  if (trimmed.startsWith('javascript:')) return false;
  if (trimmed.startsWith('file:')) return false;
  if (trimmed.startsWith('blob:')) return false;
  if (trimmed.startsWith('//')) return false; // protocol-relative
  return url.startsWith('/') || url.startsWith('https://');
}

/**
 * PDF1 fix: strip all HTML tags from user-supplied receipt_footer /
 * receipt_header / invoice_footer values. React already escapes text nodes
 * in JSX, but the same string may later be piped through html-pdf / wkhtmltopdf
 * and treated as HTML. Rendering it as plain text in both paths keeps the
 * value safe regardless of the downstream renderer.
 */
function sanitizePrintText(value: string | null | undefined): string {
  if (!value) return '';
  // DOMPurify with no allowed tags = pure-text output, preserving whitespace.
  return DOMPurify.sanitize(value, { ALLOWED_TAGS: [], ALLOWED_ATTR: [] });
}

/**
 * PDF2 fix: whitelist / truncate the terms field. RTL override chars and
 * other Unicode bidi overrides can visually rearrange content that a shop
 * customer signs. Strip the control-character ranges that carry bidi
 * influence, remove zero-width characters, and cap at 4 KB.
 */
const BIDI_CONTROL_RE = /[\u202A-\u202E\u2066-\u2069\u200E\u200F\u061C\u200B-\u200D\uFEFF]/g;
const TERMS_MAX_LENGTH = 4096;
function sanitizeTerms(value: string | null | undefined): string {
  if (!value) return '';
  const stripped = DOMPurify.sanitize(value, { ALLOWED_TAGS: [], ALLOWED_ATTR: [] });
  return stripped.replace(BIDI_CONTROL_RE, '').slice(0, TERMS_MAX_LENGTH);
}

/**
 * PDF3 fix: reject signatures that exceed a hard size cap. A base64 PNG at
 * 100 KB encoded = ~75 KB of raw pixel data, which is more than enough for
 * a signature canvas. Anything larger is either corrupt, malicious, or an
 * attempt to bloat the ticket row past the SQLite row-size comfort zone.
 */
const SIGNATURE_MAX_BYTES = 100 * 1024; // 100 KB of base64 payload
function isSafeSignature(value: string | null | undefined): boolean {
  if (!value || typeof value !== 'string') return false;
  if (!value.startsWith('data:image/')) return false;
  if (value.length > SIGNATURE_MAX_BYTES) return false;
  return true;
}

/* ── Helpers ─────────────────────────────────────────────── */

function formatDate(d: string | null | undefined) {
  if (!d) return '';
  const locale = (typeof navigator !== 'undefined' ? navigator.language : undefined) || 'en-US';
  return new Date(d).toLocaleDateString(locale, { day: '2-digit', month: 'short', year: 'numeric' });
}

function formatDateTime(d: string | null | undefined) {
  if (!d) return '';
  const locale = (typeof navigator !== 'undefined' ? navigator.language : undefined) || 'en-US';
  const dt = new Date(d);
  return dt.toLocaleDateString(locale, { day: '2-digit', month: 'short', year: 'numeric' })
    + ' (' + dt.toLocaleTimeString(locale, { hour: 'numeric', minute: '2-digit' }) + ')';
}

function formatPhone(p: string | null | undefined) {
  if (!p) return '';
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11) return `+${digits[0]} (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  return p;
}

function money(v: number | null | undefined) {
  return formatCurrency(v ?? 0);
}

/* ── Barcode ─────────────────────────────────────────────── */

function BarcodeBlock({ value, width = 1.5 }: { value: string; width?: number }) {
  const svgRef = useRef<SVGSVGElement>(null);
  useEffect(() => {
    if (svgRef.current && value) {
      try {
        JsBarcode(svgRef.current, value, {
          format: 'CODE128',
          width,
          height: 40,
          displayValue: true,
          fontSize: 10,
          margin: 4,
          background: 'transparent',
        });
      } catch {
        // invalid barcode value — ignore
      }
    }
  }, [value, width]);
  return <div style={{ textAlign: 'center', marginTop: 8 }}><svg ref={svgRef} /></div>;
}

/* ── Thermal Receipt (80mm / 58mm) ───────────────────────── */

function ThermalReceipt({ ticket, config, size, isReceiptType }: {
  ticket: PrintTicket; config: PrintConfig; size: 'receipt80' | 'receipt58'; isReceiptType: boolean;
}) {
  const cfg = (key: string, fallback = '1') => (config?.[key] ?? fallback) === '1';
  const cfgText = (key: string, fallback = '') => config?.[key] ?? fallback;

  const customer: PrintCustomer = ticket.customer || {};
  const devices: PrintDevice[] = ticket.devices || [];
  const payments: PrintPayment[] = ticket.payments || [];
  const storeName = cfgText('store_name', 'Repair Shop');
  const storePhone = cfgText('store_phone', '');
  const storeAddress = cfgText('store_address', '');
  const storeWebsite = cfgText('store_website', '');
  const logoUrl = cfgText('receipt_logo');

  const s: React.CSSProperties = { fontFamily: "'Courier New', monospace", fontSize: size === 'receipt58' ? 9 : 10, lineHeight: 1.3, color: '#000' };
  const dash: React.CSSProperties = { borderTop: '1px dashed #000', margin: '4px 0' };
  const thick: React.CSSProperties = { borderTop: '2px solid #000', margin: '4px 0' };
  const row: React.CSSProperties = { display: 'flex', justifyContent: 'space-between' };
  const center: React.CSSProperties = { textAlign: 'center' };

  return (
    <div style={s}>
      {/* Logo */}
      {isSafeLogoUrl(logoUrl) && (
        <div style={center}>
          <img src={logoUrl} alt="" style={{ maxWidth: '60%', height: 'auto', margin: '0 auto 4px' }} />
        </div>
      )}

      {/* Store Header */}
      <div style={{ ...center, fontWeight: 'bold', fontSize: '1.4em' }}>{storeName}</div>
      <div style={{ ...center, fontSize: '0.85em' }}>{storeAddress}</div>
      <div style={{ ...center, fontSize: '0.85em' }}>
        Tel: {storePhone}{storeWebsite ? ` | ${storeWebsite}` : ''}
      </div>

      <div style={thick} />

      {/* Receipt header message (receipt_header from store_config) */}
      {cfgText('receipt_header') && (
        <>
          <div style={{ ...center, fontSize: '0.85em', whiteSpace: 'pre-wrap' }}>{sanitizePrintText(cfgText('receipt_header'))}</div>
          <div style={dash} />
        </>
      )}

      {/* Customer */}
      <div style={{ fontWeight: 'bold' }}>{customer.first_name} {customer.last_name}</div>
      {(customer.mobile || customer.phone) && (
        <div>Mobile: {formatPhone(customer.mobile || customer.phone)}</div>
      )}
      {customer.email && <div>Email: {customer.email}</div>}
      <div style={{ height: 4 }} />

      {/* ENR-I10: Warranty badge on thermal receipt */}
      {(ticket.is_warranty === 1 || ticket.is_warranty === true) && (
        <div style={{ ...center, fontWeight: 'bold', fontSize: '1.2em', margin: '4px 0' }}>*** WARRANTY REPAIR ***</div>
      )}

      {/* Ticket meta */}
      <div>Date: {formatDateTime(ticket.created_at)}</div>
      <div>Ticket #: {ticket.order_id}</div>
      {cfg('receipt_cfg_employee_name') && ticket.created_by_name && (
        <div>Prepared By: {ticket.created_by_name}</div>
      )}

      <div style={dash} />

      {/* Column header */}
      <div style={{ ...row, fontWeight: 'bold', fontSize: '0.9em' }}>
        <span>Item</span>
        <span style={{ display: 'flex', gap: 16 }}>
          <span>QTY</span>
          <span style={{ minWidth: 50, textAlign: 'right' }}>Price</span>
        </span>
      </div>
      <div style={dash} />

      {/* Devices */}
      {devices.map((d: PrintDevice, i: number) => (
        <div key={i} style={{ marginBottom: 6 }}>
          <div style={{ fontWeight: 'bold' }}>{d.device_name || d.name}</div>

          {/* Service line */}
          {(d.service_name || d.service?.name) && (
            <div style={row}>
              <span style={{ flex: 1 }}>  Service: {d.service_name || d.service?.name}</span>
              <span style={{ display: 'flex', gap: 16 }}>
                <span>1</span>
                <span style={{ minWidth: 50, textAlign: 'right' }}>{money(d.price)}</span>
              </span>
            </div>
          )}

          {/* Description (IMEI/Serial/device type) */}
          {cfg('receipt_cfg_description_thermal') && (
            <>
              {d.device_type && <div style={{ fontSize: '0.85em' }}>    Device: {d.device_type}</div>}
              {d.imei && <div style={{ fontSize: '0.85em' }}>    IMEI: {d.imei}</div>}
              {d.serial && <div style={{ fontSize: '0.85em' }}>    Serial: {d.serial}</div>}
            </>
          )}

          {/* Security code / passcode */}
          {cfg('receipt_cfg_security_code_thermal') && d.security_code && (
            <div style={{ fontSize: '0.85em' }}>    Passcode: {d.security_code}</div>
          )}

          {/* Network */}
          {cfg('receipt_cfg_network_thermal') && d.network && (
            <div style={{ fontSize: '0.85em' }}>    Network: {d.network}</div>
          )}

          {/* Due date */}
          {cfg('receipt_cfg_due_date') && (d.due_on || ticket.due_on) && (
            <div style={{ fontSize: '0.85em' }}>    Due: {formatDate(d.due_on || ticket.due_on)}</div>
          )}

          {/* Additional notes */}
          {cfg('receipt_cfg_description_thermal') && d.additional_notes && (
            <div style={{ fontSize: '0.85em' }}>    Notes: {d.additional_notes}</div>
          )}

          {/* Service description / warranty */}
          {cfg('receipt_cfg_service_desc_thermal') && (d.warranty || d.warranty_timeframe) && (
            <div style={{ fontSize: '0.85em' }}>    Warranty: {d.warranty_timeframe || d.warranty}</div>
          )}

          {/* Pre-conditions */}
          {cfg('receipt_cfg_pre_conditions_thermal') && d.pre_conditions?.length > 0 && (
            <div style={{ fontSize: '0.85em' }}>    Conditions: {d.pre_conditions.join(', ')}</div>
          )}

          {/* PO/SO reference */}
          {cfg('receipt_cfg_po_so_thermal') && d.po_number && (
            <div style={{ fontSize: '0.85em' }}>    PO#: {d.po_number}</div>
          )}

          {/* Parts */}
          {cfg('receipt_cfg_parts_thermal') && (d.parts?.length ?? 0) > 0 && (
            <div style={{ marginTop: 2 }}>
              <div style={{ fontSize: '0.85em' }}>    Parts:</div>
              {(d.parts ?? []).map((p: PrintPart, pi: number) => (
                <div key={pi}>
                  <div style={{ ...row, fontSize: '0.85em' }}>
                    <span>      {p.name} x{p.quantity || 1}</span>
                    <span style={{ minWidth: 50, textAlign: 'right' }}>{money((p.price || 0) * (p.quantity || 1))}</span>
                  </div>
                  {cfg('receipt_cfg_part_sku') && p.sku && (
                    <div style={{ fontSize: '0.8em' }}>        SKU: {p.sku}</div>
                  )}
                </div>
              ))}
            </div>
          )}

          {/* Device location */}
          {cfg('receipt_cfg_device_location') && d.device_location && (
            <div style={{ fontSize: '0.85em' }}>    Location: {d.device_location}</div>
          )}
        </div>
      ))}

      <div style={dash} />

      {/* Totals */}
      <div style={{ ...row, fontSize: '0.9em' }}>
        <span>Sub Total</span>
        <span>{money(ticket.subtotal ?? ticket.total)}</span>
      </div>

      {cfg('receipt_cfg_discount_thermal') && (ticket.discount > 0) && (
        <div style={{ ...row, fontSize: '0.9em' }}>
          <span>Discount</span>
          <span>-{money(ticket.discount)}</span>
        </div>
      )}

      {cfg('receipt_cfg_tax') && (
        <div style={{ ...row, fontSize: '0.9em' }}>
          <span>Tax</span>
          <span>{money(ticket.total_tax)}</span>
        </div>
      )}

      <div style={{ borderTop: '1px dashed #000', margin: '2px 0' }} />

      <div style={{ ...row, fontWeight: 'bold', fontSize: '1.2em' }}>
        <span>TOTAL</span>
        <span>{money(ticket.total)}</span>
      </div>

      {/* Payments (only on receipt type) */}
      {isReceiptType && payments.length > 0 && (
        <>
          <div style={dash} />
          {payments.map((p: PrintPayment, i: number) => (
            <div key={i} style={{ ...row, fontSize: '0.85em' }}>
              <span>
                Payment: {p.payment_method_name || p.method || 'Payment'} {money(p.amount)}
                {cfg('receipt_cfg_transaction_id_thermal') && p.transaction_id ? ` (txn: ${p.transaction_id})` : ''}
              </span>
            </div>
          ))}
        </>
      )}

      {/* Terms */}
      {cfgText('receipt_thermal_terms') && (
        <>
          <div style={dash} />
          <div style={{ ...center, fontWeight: 'bold', fontSize: '0.85em', marginBottom: 2 }}>Terms & Conditions</div>
          <div style={{ fontSize: '0.8em', whiteSpace: 'pre-wrap' }}>{sanitizeTerms(cfgText('receipt_thermal_terms'))}</div>
        </>
      )}

      {/* Signature */}
      {cfg('receipt_cfg_signature_thermal') && isSafeSignature(ticket.signature) && (
        <>
          <div style={dash} />
          <div style={{ ...center, fontSize: '0.85em', marginBottom: 2 }}>Customer Signature</div>
          <div style={center}>
            <img src={ticket.signature} alt="Signature" style={{ maxWidth: '50%', height: 'auto' }} />
          </div>
        </>
      )}

      {/* Barcode */}
      {cfg('receipt_cfg_barcode') && ticket.order_id && (
        <>
          <div style={dash} />
          <BarcodeBlock value={ticket.order_id} width={size === 'receipt58' ? 1 : 1.5} />
        </>
      )}

      {/* Footer */}
      {cfgText('receipt_thermal_footer') && (
        <>
          <div style={dash} />
          <div style={{ ...center, fontSize: '0.85em' }}>{sanitizePrintText(cfgText('receipt_thermal_footer'))}</div>
        </>
      )}

      {!cfgText('receipt_thermal_footer') && (
        <>
          <div style={dash} />
          <div style={{ ...center, fontSize: '0.85em' }}>Thank you! We will call when ready.</div>
        </>
      )}
    </div>
  );
}

/* ── Page / Letter Receipt ───────────────────────────────── */

function PageReceipt({ ticket, config, isReceiptType }: {
  ticket: PrintTicket; config: PrintConfig; isReceiptType: boolean;
}) {
  const cfg = (key: string, fallback = '1') => (config?.[key] ?? fallback) === '1';
  const cfgText = (key: string, fallback = '') => config?.[key] ?? fallback;

  const customer: PrintCustomer = ticket.customer || {};
  const devices: PrintDevice[] = ticket.devices || [];
  const payments: PrintPayment[] = ticket.payments || [];
  const notes: PrintNote[] = ticket.notes || [];
  const storeName = cfgText('store_name', 'Repair Shop');
  const storePhone = cfgText('store_phone', '');
  const storeAddress = cfgText('store_address', '');
  const storeWebsite = cfgText('store_website', '');
  const storeEmail = cfgText('store_email', '');
  const logoUrl = cfgText('invoice_logo') || cfgText('receipt_logo');
  const receiptTitle = isReceiptType
    ? cfgText('invoice_title', 'Invoice')
    : 'WORK ORDER';
  const invoiceSlogan = cfgText('invoice_slogan');
  const invoiceFooter = cfgText('invoice_footer');
  const invoiceTerms = cfgText('invoice_terms');
  const invoicePaymentTerms = cfgText('invoice_payment_terms');

  // Shared table styles
  const cellBorder = '1px solid #999';
  const sectionHeader: React.CSSProperties = { background: '#333', color: '#fff', padding: '4px 8px', fontSize: 11, fontWeight: 'bold', letterSpacing: 0.5 };
  const labelCell: React.CSSProperties = { padding: '6px 10px', fontSize: 10, fontWeight: 'bold', borderBottom: cellBorder, borderRight: cellBorder, whiteSpace: 'nowrap', width: 100, background: '#f9f9f9' };
  const valueCell: React.CSSProperties = { padding: '6px 10px', fontSize: 10, borderBottom: cellBorder, borderRight: cellBorder };
  const checkBox = (checked: boolean) => checked ? '☑' : '☐';

  // For receipt type, use the simpler invoice format
  if (isReceiptType) {
    return <PageInvoiceReceipt ticket={ticket} config={config} />;
  }

  // ─── WORK ORDER: Full-page intake form layout ───

  return (
    <div style={{ fontFamily: 'Arial, Helvetica, sans-serif', color: '#000', fontSize: 10, maxWidth: 700, lineHeight: 1.4 }}>

      {/* ═══ HEADER ═══ */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8, borderBottom: '2px solid #333', paddingBottom: 8 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          {isSafeLogoUrl(logoUrl) && <img src={logoUrl} alt="" style={{ maxHeight: 50, width: 'auto' }} />}
          <div>
            <div style={{ fontSize: 16, fontWeight: 'bold' }}>{storeName}</div>
            {invoiceSlogan && <div style={{ fontSize: 9, color: '#666', fontStyle: 'italic' }}>{invoiceSlogan}</div>}
          </div>
        </div>
        <div style={{ textAlign: 'right', fontSize: 9, lineHeight: 1.6 }}>
          {storeAddress && <div>{storeAddress}</div>}
          {storePhone && <div>Tel: {storePhone}</div>}
          {storeEmail && <div>{storeEmail}</div>}
          {storeWebsite && <div>{storeWebsite}</div>}
        </div>
      </div>

      {/* ═══ TITLE BAR ═══ */}
      <div style={{ ...sectionHeader, fontSize: 14, textAlign: 'center', marginBottom: 10, padding: '6px 12px' }}>
        {receiptTitle}
      </div>

      {/* ═══ ORDER INFO ROW ═══ */}
      <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 10, border: cellBorder }}>
        <tbody>
          <tr>
            <td style={labelCell}>Order #</td>
            <td style={{ ...valueCell, fontWeight: 'bold', fontSize: 12 }}>{ticket.order_id}</td>
            <td style={labelCell}>Date</td>
            <td style={valueCell}>{formatDateTime(ticket.created_at)}</td>
            <td style={labelCell}>Status</td>
            <td style={{ ...valueCell, fontWeight: 'bold', borderRight: 'none' }}>{ticket.status_name || 'Open'}</td>
          </tr>
          <tr>
            <td style={labelCell}>Technician</td>
            <td style={valueCell}>{ticket.assigned_user_name || '—'}</td>
            <td style={labelCell}>Due Date</td>
            <td style={valueCell}>{ticket.due_on ? formatDate(ticket.due_on) : '—'}</td>
            <td style={labelCell}>Created By</td>
            <td style={{ ...valueCell, borderRight: 'none' }}>{ticket.created_by_name || '—'}</td>
          </tr>
        </tbody>
      </table>

      {/* ═══ CUSTOMER INFO ═══ */}
      <div style={sectionHeader}>Customer Information</div>
      <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 10, border: cellBorder }}>
        <tbody>
          <tr>
            <td style={labelCell}>Name</td>
            <td style={{ ...valueCell, fontWeight: 'bold' }} colSpan={customer.organization ? 1 : 3}>{customer.first_name} {customer.last_name}</td>
            {customer.organization && <><td style={labelCell}>Organization</td><td style={{ ...valueCell, borderRight: 'none' }}>{customer.organization}</td></>}
          </tr>
          <tr>
            <td style={labelCell}>Phone</td>
            <td style={valueCell}>{formatPhone(customer.mobile || customer.phone || '')}</td>
            {customer.email && <><td style={labelCell}>Email</td><td style={{ ...valueCell, borderRight: 'none' }}>{customer.email}</td></>}
            {!customer.email && <td colSpan={2} style={{ ...valueCell, borderRight: 'none' }} />}
          </tr>
          {customer.address1 && (
            <tr>
              <td style={labelCell}>Address</td>
              <td colSpan={3} style={{ ...valueCell, borderRight: 'none' }}>
                {customer.address1}{customer.city ? `, ${customer.city}` : ''}{customer.state ? `, ${customer.state}` : ''} {customer.postcode || ''}
              </td>
            </tr>
          )}
        </tbody>
      </table>

      {/* ═══ DEVICE SECTIONS (one per device) ═══ */}
      {devices.map((d: PrintDevice, i: number) => (
        <div key={i} style={{ marginBottom: 10 }}>
          <div style={sectionHeader}>Device {devices.length > 1 ? `#${i + 1}` : 'Information'}</div>
          <table style={{ width: '100%', borderCollapse: 'collapse', border: cellBorder }}>
            <tbody>
              {/* Row 1: Device name + type (always shown) */}
              <tr>
                <td style={labelCell}>Device</td>
                <td style={{ ...valueCell, fontWeight: 'bold' }} colSpan={d.device_type ? 1 : 3}>{d.device_name || d.name || 'Unknown'}</td>
                {d.device_type && <><td style={labelCell}>Type</td><td style={{ ...valueCell, borderRight: 'none' }}>{d.device_type}</td></>}
              </tr>
              {/* Row 2: IMEI + Serial (only if either exists) */}
              {(d.imei || d.serial) && (
                <tr>
                  {d.imei && <><td style={labelCell}>IMEI</td><td style={{ ...valueCell, fontFamily: 'monospace' }}>{d.imei}</td></>}
                  {d.serial && <><td style={labelCell}>Serial #</td><td style={{ ...valueCell, fontFamily: 'monospace', borderRight: 'none' }}>{d.serial}</td></>}
                  {d.imei && !d.serial && <td colSpan={2} style={{ ...valueCell, borderRight: 'none' }} />}
                  {!d.imei && d.serial && <td colSpan={2} style={valueCell} />}
                </tr>
              )}
              {/* Row 3: Passcode + Service (only if either exists) */}
              {(d.security_code || d.service_name || d.service?.name) && (
                <tr>
                  {d.security_code && <><td style={labelCell}>Passcode</td><td style={{ ...valueCell, fontWeight: 'bold', fontFamily: 'monospace' }}>{d.security_code}</td></>}
                  {(d.service_name || d.service?.name) && <><td style={labelCell}>Service</td><td style={{ ...valueCell, borderRight: 'none' }}>{d.service_name || d.service?.name}</td></>}
                  {d.security_code && !(d.service_name || d.service?.name) && <td colSpan={2} style={{ ...valueCell, borderRight: 'none' }} />}
                  {!d.security_code && (d.service_name || d.service?.name) && <td colSpan={2} style={valueCell} />}
                </tr>
              )}
              {/* Issue description (only if present) */}
              {d.additional_notes && (
                <tr>
                  <td style={labelCell}>Issue</td>
                  <td colSpan={3} style={{ ...valueCell, borderRight: 'none' }}>{d.additional_notes}</td>
                </tr>
              )}
            </tbody>
          </table>

          {/* Pre-Repair Conditions checklist */}
          {d.pre_conditions?.length > 0 && (
            <table style={{ width: '100%', borderCollapse: 'collapse', border: cellBorder, borderTop: 'none' }}>
              <tbody>
                <tr>
                  <td style={{ ...labelCell, verticalAlign: 'top' }}>Conditions</td>
                  <td colSpan={3} style={{ ...valueCell, borderRight: 'none', fontSize: 9 }}>
                    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '2px 16px' }}>
                      {d.pre_conditions.map((c: string, ci: number) => (
                        <span key={ci}>{checkBox(true)} {c}</span>
                      ))}
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          )}

          {/* Parts for this device */}
          {(d.parts?.length ?? 0) > 0 && (
            <table style={{ width: '100%', borderCollapse: 'collapse', border: cellBorder, borderTop: 'none' }}>
              <thead>
                <tr style={{ background: '#f3f4f6' }}>
                  <th style={{ ...labelCell, width: 'auto' }}>Part</th>
                  <th style={{ ...labelCell, width: 50, textAlign: 'center' }}>Qty</th>
                  <th style={{ ...labelCell, width: 70, textAlign: 'right' }}>Price</th>
                  <th style={{ ...labelCell, width: 60, textAlign: 'center', borderRight: 'none' }}>Status</th>
                </tr>
              </thead>
              <tbody>
                {(d.parts ?? []).map((p: PrintPart, pi: number) => (
                  <tr key={pi}>
                    <td style={valueCell}>
                      {p.name || p.item_name}
                      {p.sku ? <span style={{ color: '#888', marginLeft: 4 }}>(SKU: {p.sku})</span> : ''}
                    </td>
                    <td style={{ ...valueCell, textAlign: 'center' }}>{p.quantity || 1}</td>
                    <td style={{ ...valueCell, textAlign: 'right' }}>{money((p.price || 0) * (p.quantity || 1))}</td>
                    <td style={{ ...valueCell, textAlign: 'center', borderRight: 'none', textTransform: 'capitalize' }}>{p.status || 'available'}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}

          {/* Price row */}
          <table style={{ width: '100%', borderCollapse: 'collapse', border: cellBorder, borderTop: 'none' }}>
            <tbody>
              <tr>
                <td style={{ ...labelCell, width: 'auto', textAlign: 'right', paddingRight: 12 }}>Repair Estimate</td>
                <td style={{ ...valueCell, width: 100, textAlign: 'right', fontWeight: 'bold', fontSize: 12, borderRight: 'none' }}>{money(d.price)}</td>
              </tr>
            </tbody>
          </table>
        </div>
      ))}

      {/* ═══ DIAGNOSTIC NOTES ONLY (no internal notes on work order) ═══ */}
      {(() => {
        const diagNotes = notes.filter((n: PrintNote) => n.note_type === 'diagnostic');
        if (diagNotes.length === 0) return null;
        return (
          <>
            <div style={sectionHeader}>Diagnostic Notes</div>
            <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 10, border: cellBorder }}>
              <tbody>
                {diagNotes.map((n: PrintNote, i: number) => (
                  <tr key={i}>
                    <td style={{ ...labelCell, width: 80, fontSize: 8, color: '#888' }}>
                      {n.user_first_name || 'Tech'}
                      <div style={{ fontWeight: 'normal', fontSize: 8 }}>{n.created_at ? formatDateTime(n.created_at) : ''}</div>
                    </td>
                    <td style={{ ...valueCell, borderRight: 'none', whiteSpace: 'pre-wrap' }}>
                      {/* WEB-S4-033: use DOMPurify (already imported) instead of a
                          regex strip so encoded entities, nested tags, and SVG
                          payloads are handled correctly by the DOM parser. */}
                      {DOMPurify.sanitize(n.content || n.note || '', { ALLOWED_TAGS: [], ALLOWED_ATTR: [] })}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </>
        );
      })()}

      {/* ═══ TOTALS ═══ */}
      <table style={{ width: 240, marginLeft: 'auto', borderCollapse: 'collapse', marginBottom: 10, border: cellBorder }}>
        <tbody>
          <tr>
            <td style={{ ...labelCell, textAlign: 'right' }}>Subtotal</td>
            <td style={{ ...valueCell, textAlign: 'right', borderRight: 'none' }}>{money(ticket.subtotal ?? ticket.total)}</td>
          </tr>
          {ticket.discount > 0 && (
            <tr>
              <td style={{ ...labelCell, textAlign: 'right' }}>Discount</td>
              <td style={{ ...valueCell, textAlign: 'right', borderRight: 'none' }}>-{money(ticket.discount)}</td>
            </tr>
          )}
          {cfg('receipt_cfg_tax') && (
            <tr>
              <td style={{ ...labelCell, textAlign: 'right' }}>Tax</td>
              <td style={{ ...valueCell, textAlign: 'right', borderRight: 'none' }}>{money(ticket.total_tax)}</td>
            </tr>
          )}
          <tr>
            <td style={{ ...labelCell, textAlign: 'right', fontSize: 12 }}>TOTAL</td>
            <td style={{ ...valueCell, textAlign: 'right', fontWeight: 'bold', fontSize: 14, borderRight: 'none' }}>{money(ticket.total)}</td>
          </tr>
        </tbody>
      </table>

      {/* ═══ TERMS & CONDITIONS ═══ */}
      {(invoiceTerms || cfgText('receipt_terms')) && (
        <>
          <div style={sectionHeader}>Repair Terms & Conditions</div>
          <div style={{ border: cellBorder, borderTop: 'none', padding: '6px 8px', fontSize: 8, color: '#444', marginBottom: 10, whiteSpace: 'pre-wrap', lineHeight: 1.5 }}>
            {sanitizeTerms(invoiceTerms || cfgText('receipt_terms'))}
          </div>
        </>
      )}

      {/* ═══ SIGNATURES ═══ */}
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 16, marginBottom: 10 }}>
        <div style={{ width: '45%' }}>
          <div style={{ fontSize: 9, marginBottom: 4 }}>Customer acknowledges the above information is correct:</div>
          {isSafeSignature(ticket.signature) ? (
            <img src={ticket.signature} alt="Signature" style={{ maxWidth: 200, height: 50, border: '1px solid #ccc' }} />
          ) : (
            <div style={{ borderBottom: '1px solid #333', height: 40, marginBottom: 4 }} />
          )}
          <div style={{ fontSize: 8, color: '#666' }}>Customer Signature / Date</div>
        </div>
        <div style={{ width: '45%' }}>
          <div style={{ fontSize: 9, marginBottom: 4 }}>Received by:</div>
          <div style={{ borderBottom: '1px solid #333', height: 40, marginBottom: 4 }} />
          <div style={{ fontSize: 8, color: '#666' }}>Technician Signature / Date</div>
        </div>
      </div>

      {/* ═══ BARCODE ═══ */}
      {cfg('receipt_cfg_barcode') && ticket.order_id && (
        <div style={{ textAlign: 'center', marginTop: 8 }}>
          <BarcodeBlock value={ticket.order_id} width={2} />
        </div>
      )}

      {/* ═══ FOOTER ═══ */}
      {(invoiceFooter || cfgText('receipt_footer')) ? (
        <div style={{ textAlign: 'center', fontSize: 9, marginTop: 12, color: '#555' }}>
          {sanitizePrintText(invoiceFooter || cfgText('receipt_footer'))}
        </div>
      ) : (
        <div style={{ textAlign: 'center', fontSize: 9, marginTop: 12, color: '#555' }}>
          Thank you for choosing {storeName}! Questions? Call us at {storePhone}
        </div>
      )}
    </div>
  );
}

/* ── Invoice/Payment Receipt (letter format) ──────────────── */

function PageInvoiceReceipt({ ticket, config }: { ticket: PrintTicket; config: PrintConfig }) {
  const cfg = (key: string, fallback = '1') => (config?.[key] ?? fallback) === '1';
  const cfgText = (key: string, fallback = '') => config?.[key] ?? fallback;

  const customer: PrintCustomer = ticket.customer || {};
  const devices: PrintDevice[] = ticket.devices || [];
  const payments: PrintPayment[] = ticket.payments || [];
  const storeName = cfgText('store_name', 'Repair Shop');
  const storePhone = cfgText('store_phone', '');
  const storeAddress = cfgText('store_address', '');
  const storeWebsite = cfgText('store_website', '');
  const storeEmail = cfgText('store_email', '');
  const logoUrl = cfgText('invoice_logo') || cfgText('receipt_logo');
  // ENR-I10: Show "WARRANTY REPAIR" instead of "Invoice" for warranty tickets
  const isWarranty = ticket.is_warranty === 1 || ticket.is_warranty === true;
  const invoiceTitle = isWarranty ? 'WARRANTY REPAIR' : cfgText('invoice_title', 'Invoice');
  const invoiceSlogan = cfgText('invoice_slogan');
  const invoiceFooter = cfgText('invoice_footer');
  const invoiceTerms = cfgText('invoice_terms');
  const invoicePaymentTerms = cfgText('invoice_payment_terms');

  const thStyle: React.CSSProperties = { textAlign: 'left', padding: '6px 8px', borderBottom: '2px solid #333', fontSize: 12, fontWeight: 'bold' };
  const tdStyle: React.CSSProperties = { padding: '5px 8px', borderBottom: '1px solid #ddd', fontSize: 11, verticalAlign: 'top' };
  const tdRight: React.CSSProperties = { ...tdStyle, textAlign: 'right' };

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', color: '#000', fontSize: 11, maxWidth: 700 }}>
      {/* Header */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {isSafeLogoUrl(logoUrl) && <img src={logoUrl} alt="" style={{ maxHeight: 60, width: 'auto' }} />}
          <div><div style={{ fontSize: 18, fontWeight: 'bold' }}>{storeName}</div></div>
        </div>
        <div style={{ textAlign: 'right', fontSize: 10, lineHeight: 1.5 }}>
          <div>{storeAddress}</div>
          <div>Tel: {storePhone}</div>
          {storeEmail && <div>{storeEmail}</div>}
          {storeWebsite && <div>{storeWebsite}</div>}
        </div>
      </div>
      {invoiceSlogan && <div style={{ textAlign: 'center', fontSize: 10, fontStyle: 'italic', color: '#666', marginBottom: 4 }}>{invoiceSlogan}</div>}

      <div style={{ background: isWarranty ? '#b45309' : '#333', color: '#fff', padding: '6px 12px', fontSize: 14, fontWeight: 'bold', marginBottom: 12 }}>
        {invoiceTitle} — {ticket.order_id}
      </div>

      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
        <div>
          <div style={{ fontWeight: 'bold', marginBottom: 2 }}>Customer</div>
          <div>{customer.first_name} {customer.last_name}</div>
          {(customer.mobile || customer.phone) && <div>Phone: {formatPhone(customer.mobile || customer.phone)}</div>}
          {customer.email && <div>Email: {customer.email}</div>}
        </div>
        <div style={{ textAlign: 'right' }}>
          <div>Date: {formatDateTime(ticket.created_at)}</div>
          <div>Status: <strong>{ticket.status_name || 'Open'}</strong></div>
          {invoicePaymentTerms && <div>Terms: {invoicePaymentTerms.replace(/_/g, ' ')}</div>}
        </div>
      </div>

      {/* Line items */}
      <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 12 }}>
        <thead>
          <tr>
            <th style={thStyle}>#</th>
            <th style={thStyle}>Device / Service</th>
            <th style={{ ...thStyle, textAlign: 'right' }}>Price</th>
          </tr>
        </thead>
        <tbody>
          {devices.map((d: PrintDevice, i: number) => (
            <tr key={i}>
              <td style={tdStyle}>{i + 1}</td>
              <td style={tdStyle}>
                <div style={{ fontWeight: 'bold' }}>{d.device_name || d.name}</div>
                {(d.service_name || d.service?.name) && <div>{d.service_name || d.service?.name}</div>}
                {(d.parts?.length ?? 0) > 0 && (
                  <div style={{ marginTop: 4, paddingLeft: 8, fontSize: 10, color: '#444' }}>
                    {(d.parts ?? []).map((p: PrintPart, pi: number) => (
                      <div key={pi}>Part: {p.name || p.item_name} x{p.quantity || 1} — {money((p.price || 0) * (p.quantity || 1))}</div>
                    ))}
                  </div>
                )}
              </td>
              <td style={tdRight}>{money(d.price)}</td>
            </tr>
          ))}
        </tbody>
      </table>

      {/* Totals */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
        <div style={{ width: 220 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}><span>Subtotal:</span><span>{money(ticket.subtotal ?? ticket.total)}</span></div>
          {ticket.discount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}><span>Discount:</span><span>-{money(ticket.discount)}</span></div>}
          {cfg('receipt_cfg_tax') && <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}><span>Tax:</span><span>{money(ticket.total_tax)}</span></div>}
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0 3px', borderTop: '2px solid #333', fontWeight: 'bold', fontSize: 14 }}><span>TOTAL:</span><span>{money(ticket.total)}</span></div>
        </div>
      </div>

      {/* Payments */}
      {payments.length > 0 && (
        <div style={{ marginBottom: 12, padding: 8, background: '#f9f9f9', border: '1px solid #ddd' }}>
          <div style={{ fontWeight: 'bold', marginBottom: 4 }}>Payments</div>
          {payments.map((p: PrintPayment, i: number) => (
            <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, padding: '2px 0' }}>
              <span>{p.payment_method_name || p.method || 'Payment'}{p.created_at ? ` — ${formatDate(p.created_at)}` : ''}</span>
              <span>{money(p.amount)}</span>
            </div>
          ))}
        </div>
      )}

      {/* Terms */}
      {invoiceTerms && <div style={{ marginBottom: 12, fontSize: 9, color: '#555', borderTop: '1px solid #ccc', paddingTop: 8 }}><div style={{ fontWeight: 'bold', marginBottom: 2 }}>Terms & Conditions</div><div style={{ whiteSpace: 'pre-wrap' }}>{sanitizeTerms(invoiceTerms)}</div></div>}

      {cfg('receipt_cfg_signature_page') && isSafeSignature(ticket.signature) && (
        <div style={{ marginBottom: 12 }}><div style={{ fontSize: 10, marginBottom: 2 }}>Customer Signature:</div><img src={ticket.signature} alt="Signature" style={{ maxWidth: 200, height: 'auto', border: '1px solid #ccc' }} /></div>
      )}
      {cfg('receipt_cfg_barcode') && ticket.order_id && <BarcodeBlock value={ticket.order_id} width={2} />}
      <div style={{ textAlign: 'center', fontSize: 10, marginTop: 16, color: '#555' }}>{sanitizePrintText(invoiceFooter || cfgText('receipt_footer')) || `Thank you for choosing ${storeName}!`}</div>
    </div>
  );
}

/* ── Label layout (unchanged) ────────────────────────────── */

function LabelLayout({ ticket, config }: { ticket: PrintTicket; config: PrintConfig }) {
  const customer: PrintCustomer = ticket.customer || {};
  const devices: PrintDevice[] = ticket.devices || [];
  const storeName = config?.store_name || 'Repair Shop';
  // WEB-FJ-005 (Fixer-A5 2026-04-25): honor a `receipt_cfg_redact_phone_label`
  // store-config toggle so the 2-inch device label can drop the customer
  // phone — it sticks to the device on the workshop bench and is visible
  // to anyone who handles or finds the device after pickup. Default OFF
  // (phone shown) to match prior behaviour; opt-in for CCPA/GDPR
  // data-minimization or per-shop policy.
  const redactPhoneOnLabel = (config?.['receipt_cfg_redact_phone_label'] ?? '0') === '1';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '2in', justifyContent: 'space-between', padding: '3mm', fontFamily: 'Arial, sans-serif', fontSize: 9 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <div style={{ fontWeight: 'bold', fontSize: '1.3em' }}>{ticket.order_id}</div>
          <div style={{ fontWeight: 'bold' }}>{customer.first_name} {customer.last_name}</div>
          {!redactPhoneOnLabel && <div>{formatPhone(customer.mobile || customer.phone)}</div>}
        </div>
        <div style={{ textAlign: 'right' }}>
          <div>{formatDate(ticket.created_at)}</div>
          <div style={{ fontWeight: 'bold' }}>{ticket.status_name || 'Open'}</div>
        </div>
      </div>
      <div style={{ borderTop: '1px dashed #000', margin: '2px 0' }} />
      <div>
        {devices.slice(0, 2).map((d: PrintDevice, i: number) => (
          <div key={i} style={{ fontWeight: 'bold' }}>{d.device_name || d.name}</div>
        ))}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
        <div>{storeName}</div>
        <div style={{ fontWeight: 'bold' }}>{money(ticket.total)}</div>
      </div>
    </div>
  );
}

/* ── Main PrintPage ──────────────────────────────────────── */

export function PrintPage() {
  const { id } = useParams<{ id: string }>();
  const [params] = useSearchParams();
  const size = (params.get('size') || 'receipt80') as PaperSize;
  const isReceiptType = params.get('type') === 'receipt';

  // WEB-FF-008 — opt this route out of the global app-shell print CSS so
  // its bespoke `@page` + `@media print` rules below remain authoritative.
  // The default print stylesheet in `globals.css` applies only when
  // `body` does NOT carry the `print-route` class.
  useEffect(() => {
    document.body.classList.add('print-route');
    return () => document.body.classList.remove('print-route');
  }, []);

  // Guard against missing or non-numeric :id — `Number(undefined)` is NaN
  // and `ticketApi.get(NaN)` hits the backend with a bad id.
  const numericId = id ? Number(id) : NaN;
  const idIsValid = Number.isFinite(numericId);
  const { data, isLoading, error } = useQuery({
    queryKey: ['ticket-print', id],
    queryFn: () => ticketApi.get(numericId),
    enabled: idIsValid,
  });
  // WEB-S4-032: cast to PrintTicket (defined above) instead of `any`.
  const ticket = data?.data?.data as PrintTicket | undefined;

  const { data: configData } = useQuery({
    queryKey: ['settings', 'config'],
    queryFn: async () => { const r = await settingsApi.getConfig(); return r.data.data as Record<string, string>; },
  });
  const config = configData || {};

  const isThermal = size === 'receipt80' || size === 'receipt58';
  const isLabel = size === 'label';

  const labelW = parseInt(config.label_width_mm || '102', 10) || 102;
  const labelH = parseInt(config.label_height_mm || '51', 10) || 51;

  // Embedded mode (inside iframe in PrintPreviewModal) — hide controls
  const isEmbedded = params.get('embed') === '1';
  // Auto-print only if ?autoprint=1 is in URL (explicit opt-in)
  const autoprint = params.get('autoprint') === '1';
  useEffect(() => {
    if (autoprint && ticket && !isLoading) {
      const timer = setTimeout(() => window.print(), 400);
      return () => clearTimeout(timer);
    }
  }, [autoprint, ticket, isLoading]);

  if (isLoading) {
    return <div style={{ padding: '2rem', textAlign: 'center', fontFamily: 'monospace' }}>Loading ticket...</div>;
  }

  if (error || !ticket) {
    return <div style={{ padding: '2rem', fontFamily: 'monospace' }}>Ticket not found.</div>;
  }

  // Paper-size CSS. W12 fix: labelW/labelH are re-clamped to safe integers
  // right before interpolation so even a bad parseInt or a future refactor
  // can't slip a raw config value into the style block. Other branches are
  // static string constants (no interpolation).
  const safeLabelW = Math.max(10, Math.min(500, Number.isFinite(labelW) ? labelW : 102));
  const safeLabelH = Math.max(10, Math.min(500, Number.isFinite(labelH) ? labelH : 51));
  const pageCss: Record<PaperSize, string> = {
    receipt80: `@page { size: 80mm auto; margin: 2mm; } body { width: 76mm; }`,
    receipt58: `@page { size: 58mm auto; margin: 2mm; } body { width: 54mm; }`,
    label: `@page { size: ${safeLabelW}mm ${safeLabelH}mm; margin: 2mm; } body { width: ${safeLabelW}mm; height: ${safeLabelH}mm; overflow: hidden; }`,
    letter: `@page { size: letter; margin: 0.75in; } body { width: auto; }`,
  };

  const maxWidth = isLabel ? '500px' : isThermal ? '400px' : '750px';
  const cssBody = `
* { box-sizing: border-box; margin: 0; padding: 0; }
body { color: #000; background: #fff; }
${pageCss[size] || pageCss.receipt80}
@media screen {
  body { padding: 1rem; max-width: ${maxWidth}; margin: 0 auto; }
}
@media print {
  .print-buttons { display: none !important; }
  /* Fixer-WW (WEB-FH-025): keep table rows whole at page breaks and repeat
     the header on each page so long letter-sized invoice prints don't split
     a line item across pages or lose the column header on overflow. */
  tr { page-break-inside: avoid; }
  thead { display: table-header-group; }
  tfoot { display: table-footer-group; }
}
`;

  return (
    <>
      {/* The CSS is composed from compile-time constants plus clamped integer
          dimensions — no config/user strings reach this block. Using a text
          child (instead of dangerouslySetInnerHTML) removes the last
          "write HTML directly" code path from the print page. */}
      <style>{cssBody}</style>

      {/* Screen-only controls (hidden when embedded in modal) */}
      {!isEmbedded && <div className="print-buttons" style={{ padding: '0.75rem 1rem', background: '#f5f5f5', marginBottom: '1rem', display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
        <strong style={{ marginRight: '0.5rem' }}>Size:</strong>
        {(['receipt80', 'receipt58', 'label', 'letter'] as PaperSize[]).map((s) => {
          const label = s === 'receipt80' ? '80mm Receipt' : s === 'receipt58' ? '58mm Receipt' : s === 'label' ? '4"x2" Label' : 'Letter';
          const typeParam = isReceiptType ? '&type=receipt' : '';
          return (
            <a key={s} href={`/print/ticket/${id}?size=${s}${typeParam}`}
              style={{ padding: '0.25rem 0.75rem', border: '1px solid #333', borderRadius: 4, textDecoration: 'none', fontWeight: s === size ? 'bold' : 'normal', background: s === size ? '#333' : 'transparent', color: s === size ? '#fff' : '#333' }}>
              {label}
            </a>
          );
        })}
        <button onClick={() => window.print()} style={{ padding: '0.25rem 1rem', background: '#2563eb', color: '#fff', border: 'none', borderRadius: 4, cursor: 'pointer', marginLeft: 'auto' }}>
          Print
        </button>
      </div>}

      {/* Content */}
      <div data-print-ready="true" className="receipt-content">
        {isLabel && <LabelLayout ticket={ticket} config={config} />}
        {isThermal && <ThermalReceipt ticket={ticket} config={config} size={size} isReceiptType={isReceiptType} />}
        {size === 'letter' && <PageReceipt ticket={ticket} config={config} isReceiptType={isReceiptType} />}
      </div>
    </>
  );
}
