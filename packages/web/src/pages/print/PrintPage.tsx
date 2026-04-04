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
import { ticketApi, settingsApi } from '@/api/endpoints';
import JsBarcode from 'jsbarcode'; // eslint-disable-line

type PaperSize = 'receipt80' | 'receipt58' | 'label' | 'letter';

/* ── Helpers ─────────────────────────────────────────────── */

function formatDate(d: string | null | undefined) {
  if (!d) return '';
  return new Date(d).toLocaleDateString('en-US', { day: '2-digit', month: 'short', year: 'numeric' });
}

function formatDateTime(d: string | null | undefined) {
  if (!d) return '';
  const dt = new Date(d);
  return dt.toLocaleDateString('en-US', { day: '2-digit', month: 'short', year: 'numeric' })
    + ' (' + dt.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' }) + ')';
}

function formatPhone(p: string | null | undefined) {
  if (!p) return '';
  const digits = p.replace(/\D/g, '');
  if (digits.length === 10) return `(${digits.slice(0, 3)}) ${digits.slice(3, 6)}-${digits.slice(6)}`;
  if (digits.length === 11) return `+${digits[0]} (${digits.slice(1, 4)}) ${digits.slice(4, 7)}-${digits.slice(7)}`;
  return p;
}

function money(v: number | null | undefined) {
  return '$' + (v || 0).toFixed(2);
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
  ticket: any; config: Record<string, string>; size: 'receipt80' | 'receipt58'; isReceiptType: boolean;
}) {
  const cfg = (key: string, fallback = '1') => (config?.[key] ?? fallback) === '1';
  const cfgText = (key: string, fallback = '') => config?.[key] ?? fallback;

  const customer = ticket.customer || {};
  const devices: any[] = ticket.devices || [];
  const payments: any[] = ticket.payments || [];
  const storeName = cfgText('store_name', 'Bizarre Electronics');
  const storePhone = cfgText('store_phone', '(303) 261-1911');
  const storeAddress = cfgText('store_address', '506 11th Ave, Longmont, CO 80501');
  const storeWebsite = cfgText('store_website', 'bizarreelectronics.com');
  const logoUrl = cfgText('receipt_logo');

  const s: React.CSSProperties = { fontFamily: "'Courier New', monospace", fontSize: size === 'receipt58' ? 9 : 10, lineHeight: 1.3, color: '#000' };
  const dash: React.CSSProperties = { borderTop: '1px dashed #000', margin: '4px 0' };
  const thick: React.CSSProperties = { borderTop: '2px solid #000', margin: '4px 0' };
  const row: React.CSSProperties = { display: 'flex', justifyContent: 'space-between' };
  const center: React.CSSProperties = { textAlign: 'center' };

  return (
    <div style={s}>
      {/* Logo */}
      {logoUrl && (
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

      {/* Customer */}
      <div style={{ fontWeight: 'bold' }}>{customer.first_name} {customer.last_name}</div>
      {(customer.mobile || customer.phone) && (
        <div>Mobile: {formatPhone(customer.mobile || customer.phone)}</div>
      )}
      {customer.email && <div>Email: {customer.email}</div>}
      <div style={{ height: 4 }} />

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
      {devices.map((d: any, i: number) => (
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
          {cfg('receipt_cfg_parts_thermal') && d.parts?.length > 0 && (
            <div style={{ marginTop: 2 }}>
              <div style={{ fontSize: '0.85em' }}>    Parts:</div>
              {d.parts.map((p: any, pi: number) => (
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
          {payments.map((p: any, i: number) => (
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
          <div style={{ fontSize: '0.8em', whiteSpace: 'pre-wrap' }}>{cfgText('receipt_thermal_terms')}</div>
        </>
      )}

      {/* Signature */}
      {cfg('receipt_cfg_signature_thermal') && ticket.signature && (
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
          <div style={{ ...center, fontSize: '0.85em' }}>{cfgText('receipt_thermal_footer')}</div>
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
  ticket: any; config: Record<string, string>; isReceiptType: boolean;
}) {
  const cfg = (key: string, fallback = '1') => (config?.[key] ?? fallback) === '1';
  const cfgText = (key: string, fallback = '') => config?.[key] ?? fallback;

  const customer = ticket.customer || {};
  const devices: any[] = ticket.devices || [];
  const payments: any[] = ticket.payments || [];
  const storeName = cfgText('store_name', 'Bizarre Electronics');
  const storePhone = cfgText('store_phone', '(303) 261-1911');
  const storeAddress = cfgText('store_address', '506 11th Ave, Longmont, CO 80501');
  const storeWebsite = cfgText('store_website', 'bizarreelectronics.com');
  const storeEmail = cfgText('store_email', '');
  const logoUrl = cfgText('receipt_logo');
  const receiptTitle = cfgText('receipt_title', 'Receipt');

  const thStyle: React.CSSProperties = { textAlign: 'left', padding: '6px 8px', borderBottom: '2px solid #333', fontSize: 12, fontWeight: 'bold' };
  const tdStyle: React.CSSProperties = { padding: '5px 8px', borderBottom: '1px solid #ddd', fontSize: 11, verticalAlign: 'top' };
  const tdRight: React.CSSProperties = { ...tdStyle, textAlign: 'right' };

  return (
    <div style={{ fontFamily: 'Arial, sans-serif', color: '#000', fontSize: 11, maxWidth: 700 }}>
      {/* Header: logo left, store info right */}
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 16 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          {logoUrl && <img src={logoUrl} alt="" style={{ maxHeight: 60, width: 'auto' }} />}
          <div>
            <div style={{ fontSize: 18, fontWeight: 'bold' }}>{storeName}</div>
          </div>
        </div>
        <div style={{ textAlign: 'right', fontSize: 10, lineHeight: 1.5 }}>
          <div>{storeAddress}</div>
          <div>Tel: {storePhone}</div>
          {storeEmail && <div>{storeEmail}</div>}
          {storeWebsite && <div>{storeWebsite}</div>}
        </div>
      </div>

      {/* Title bar */}
      <div style={{ background: '#333', color: '#fff', padding: '6px 12px', fontSize: 14, fontWeight: 'bold', marginBottom: 12 }}>
        {isReceiptType ? receiptTitle : 'WORK ORDER'} — {ticket.order_id}
      </div>

      {/* Info row */}
      <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 12 }}>
        <div>
          <div style={{ fontWeight: 'bold', marginBottom: 2 }}>Customer</div>
          <div>{customer.first_name} {customer.last_name}</div>
          {(customer.mobile || customer.phone) && <div>Mobile: {formatPhone(customer.mobile || customer.phone)}</div>}
          {customer.email && <div>Email: {customer.email}</div>}
          {customer.address1 && <div>{customer.address1}{customer.city ? `, ${customer.city}` : ''}{customer.state ? `, ${customer.state}` : ''} {customer.postcode || ''}</div>}
        </div>
        <div style={{ textAlign: 'right' }}>
          <div>Date: {formatDateTime(ticket.created_at)}</div>
          <div>Status: <strong>{ticket.status_name || 'Open'}</strong></div>
          {cfg('receipt_cfg_employee_name') && ticket.created_by_name && (
            <div>Prepared By: {ticket.created_by_name}</div>
          )}
          {cfg('receipt_cfg_due_date') && ticket.due_on && (
            <div>Due: {formatDate(ticket.due_on)}</div>
          )}
        </div>
      </div>

      {/* Line items table */}
      <table style={{ width: '100%', borderCollapse: 'collapse', marginBottom: 12 }}>
        <thead>
          <tr>
            <th style={thStyle}>#</th>
            <th style={thStyle}>Device / Service</th>
            {cfg('receipt_cfg_description_page') && <th style={thStyle}>Details</th>}
            <th style={{ ...thStyle, textAlign: 'right' }}>Qty</th>
            <th style={{ ...thStyle, textAlign: 'right' }}>Price</th>
          </tr>
        </thead>
        <tbody>
          {devices.map((d: any, i: number) => {
            const details: string[] = [];
            if (cfg('receipt_cfg_description_page')) {
              if (d.device_type) details.push(`Device: ${d.device_type}`);
              if (d.imei) details.push(`IMEI: ${d.imei}`);
              if (d.serial) details.push(`S/N: ${d.serial}`);
            }
            if (cfg('receipt_cfg_security_code_page') && d.security_code) details.push(`Passcode: ${d.security_code}`);
            if (cfg('receipt_cfg_service_desc_page') && (d.warranty || d.warranty_timeframe)) details.push(`Warranty: ${d.warranty_timeframe || d.warranty}`);
            if (cfg('receipt_cfg_pre_conditions_page') && d.pre_conditions?.length > 0) details.push(`Conditions: ${d.pre_conditions.join(', ')}`);
            if (cfg('receipt_cfg_post_conditions_page', '0') && d.post_conditions?.length > 0) details.push(`Post: ${d.post_conditions.join(', ')}`);
            if (cfg('receipt_cfg_po_so_page') && d.po_number) details.push(`PO#: ${d.po_number}`);
            if (cfg('receipt_cfg_device_location') && d.device_location) details.push(`Location: ${d.device_location}`);
            if (d.additional_notes && cfg('receipt_cfg_description_page')) details.push(`Notes: ${d.additional_notes}`);

            return (
              <tr key={i}>
                <td style={tdStyle}>{i + 1}</td>
                <td style={tdStyle}>
                  <div style={{ fontWeight: 'bold' }}>{d.device_name || d.name}</div>
                  {(d.service_name || d.service?.name) && <div>{d.service_name || d.service?.name}</div>}
                  {/* Parts under device */}
                  {cfg('receipt_cfg_parts_page') && d.parts?.length > 0 && (
                    <div style={{ marginTop: 4, paddingLeft: 8, fontSize: 10, color: '#444' }}>
                      {d.parts.map((p: any, pi: number) => (
                        <div key={pi}>
                          Part: {p.name} x{p.quantity || 1} — {money((p.price || 0) * (p.quantity || 1))}
                          {cfg('receipt_cfg_part_sku') && p.sku ? ` (SKU: ${p.sku})` : ''}
                        </div>
                      ))}
                    </div>
                  )}
                </td>
                {cfg('receipt_cfg_description_page') && (
                  <td style={{ ...tdStyle, fontSize: 10, color: '#444' }}>
                    {details.map((line, li) => <div key={li}>{line}</div>)}
                  </td>
                )}
                <td style={tdRight}>1</td>
                <td style={tdRight}>{money(d.price)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>

      {/* Totals */}
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
        <div style={{ width: 220 }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}>
            <span>Sub Total:</span>
            <span>{money(ticket.subtotal ?? ticket.total)}</span>
          </div>
          {(ticket.discount > 0) && (
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}>
              <span>Discount:</span>
              <span>-{money(ticket.discount)}</span>
            </div>
          )}
          {cfg('receipt_cfg_tax') && (
            <div style={{ display: 'flex', justifyContent: 'space-between', padding: '3px 0' }}>
              <span>Tax:</span>
              <span>{money(ticket.total_tax)}</span>
            </div>
          )}
          <div style={{ display: 'flex', justifyContent: 'space-between', padding: '6px 0 3px', borderTop: '2px solid #333', fontWeight: 'bold', fontSize: 14 }}>
            <span>TOTAL:</span>
            <span>{money(ticket.total)}</span>
          </div>
        </div>
      </div>

      {/* Payments (receipt type only) */}
      {isReceiptType && payments.length > 0 && (
        <div style={{ marginBottom: 12, padding: '8px', background: '#f9f9f9', border: '1px solid #ddd' }}>
          <div style={{ fontWeight: 'bold', marginBottom: 4 }}>Payments</div>
          {payments.map((p: any, i: number) => (
            <div key={i} style={{ display: 'flex', justifyContent: 'space-between', fontSize: 10, padding: '2px 0' }}>
              <span>
                {p.payment_method_name || p.method || 'Payment'}
                {p.created_at ? ` — ${formatDate(p.created_at)}` : ''}
                {cfg('receipt_cfg_transaction_id_page') && p.transaction_id ? ` (Txn: ${p.transaction_id})` : ''}
              </span>
              <span>{money(p.amount)}</span>
            </div>
          ))}
        </div>
      )}

      {/* Terms */}
      {cfgText('receipt_terms') && (
        <div style={{ marginBottom: 12, fontSize: 9, color: '#555', borderTop: '1px solid #ccc', paddingTop: 8 }}>
          <div style={{ fontWeight: 'bold', marginBottom: 2 }}>Terms & Conditions</div>
          <div style={{ whiteSpace: 'pre-wrap' }}>{cfgText('receipt_terms')}</div>
        </div>
      )}

      {/* Signature */}
      {cfg('receipt_cfg_signature_page') && ticket.signature && (
        <div style={{ marginBottom: 12 }}>
          <div style={{ fontSize: 10, marginBottom: 2 }}>Customer Signature:</div>
          <img src={ticket.signature} alt="Signature" style={{ maxWidth: 200, height: 'auto', border: '1px solid #ccc' }} />
        </div>
      )}

      {/* Barcode */}
      {cfg('receipt_cfg_barcode') && ticket.order_id && (
        <BarcodeBlock value={ticket.order_id} width={2} />
      )}

      {/* Footer */}
      {cfgText('receipt_footer') && (
        <div style={{ textAlign: 'center', fontSize: 10, marginTop: 16, color: '#555' }}>
          {cfgText('receipt_footer')}
        </div>
      )}

      {!cfgText('receipt_footer') && (
        <div style={{ textAlign: 'center', fontSize: 10, marginTop: 16, color: '#555' }}>
          Thank you for choosing {storeName}! Questions? Call us at {storePhone}
        </div>
      )}
    </div>
  );
}

/* ── Label layout (unchanged) ────────────────────────────── */

function LabelLayout({ ticket, config }: { ticket: any; config: Record<string, string> }) {
  const customer = ticket.customer || {};
  const devices: any[] = ticket.devices || [];
  const storeName = config?.store_name || 'Bizarre Electronics';

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '2in', justifyContent: 'space-between', padding: '3mm', fontFamily: 'Arial, sans-serif', fontSize: 9 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
        <div>
          <div style={{ fontWeight: 'bold', fontSize: '1.3em' }}>{ticket.order_id}</div>
          <div style={{ fontWeight: 'bold' }}>{customer.first_name} {customer.last_name}</div>
          <div>{formatPhone(customer.mobile || customer.phone)}</div>
        </div>
        <div style={{ textAlign: 'right' }}>
          <div>{formatDate(ticket.created_at)}</div>
          <div style={{ fontWeight: 'bold' }}>{ticket.status_name || 'Open'}</div>
        </div>
      </div>
      <div style={{ borderTop: '1px dashed #000', margin: '2px 0' }} />
      <div>
        {devices.slice(0, 2).map((d: any, i: number) => (
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

  const { data, isLoading, error } = useQuery({
    queryKey: ['ticket-print', id],
    queryFn: () => ticketApi.get(Number(id)),
  });
  const ticket = data?.data?.data as any;

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

  // Paper-size CSS
  const pageCss: Record<PaperSize, string> = {
    receipt80: `@page { size: 80mm auto; margin: 2mm; } body { width: 76mm; }`,
    receipt58: `@page { size: 58mm auto; margin: 2mm; } body { width: 54mm; }`,
    label: `@page { size: ${labelW}mm ${labelH}mm; margin: 2mm; } body { width: ${labelW}mm; height: ${labelH}mm; overflow: hidden; }`,
    letter: `@page { size: letter; margin: 0.75in; } body { width: auto; }`,
  };

  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: `
        * { box-sizing: border-box; margin: 0; padding: 0; }
        body { color: #000; background: #fff; }
        ${pageCss[size] || pageCss.receipt80}
        @media screen {
          body { padding: 1rem; max-width: ${isLabel ? '500px' : isThermal ? '400px' : '750px'}; margin: 0 auto; }
        }
        @media print {
          .print-buttons { display: none !important; }
        }
      `}} />

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
