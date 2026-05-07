/**
 * QrReceiptCode — renders a proper scannable QR code for printed receipts
 * (scan-to-pay, scan-to-review) using qrcode.react (already in package.json).
 * Falls back to a labeled-text placeholder if the value is empty or
 * qrcode.react is somehow unavailable.
 *
 * WEB-UIUX-687: renders a human-readable plain-text URL below the QR code so
 * a cellular customer who cannot reach the LAN-internal server URL can still
 * read it aloud or type it. If the URL ends with a numeric ID segment, that ID
 * is also shown prominently as a typeable short code.
 *
 * Usage:
 *   <QrReceiptCode value={`https://shop.example.com/pay/${token}`} size={120} />
 *   <QrReceiptCode value="https://shop.example.com/review/123" label="Scan to review" />
 */
import { QRCodeSVG } from 'qrcode.react';

interface QrReceiptCodeProps {
  value: string;
  size?: number;
  label?: string;
  /** Hide the plain-text URL fallback (e.g. for tokens that should not be typed). */
  hideFallbackUrl?: boolean;
  className?: string;
}

// WEB-UIUX-687: extract the trailing numeric segment from a URL so it can be
// displayed as a short typeable code (e.g. "/invoices/4821" → "4821").
function extractNumericId(url: string): string | null {
  const match = url.match(/\/(\d+)(?:[/?#]|$)/);
  return match ? match[1] : null;
}

export function QrReceiptCode({ value, size = 128, label, hideFallbackUrl = false, className }: QrReceiptCodeProps) {
  // Show labeled-text fallback when there is nothing to encode.
  if (!value) {
    const fallbackText = String(value).slice(0, 40);
    return (
      <div
        className={className}
        style={{
          width: size,
          height: size,
          border: '1px dashed #999',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          fontSize: 10,
          color: '#666',
          textAlign: 'center',
          padding: 4,
        }}
      >
        {fallbackText}
      </div>
    );
  }

  // WEB-UIUX-687: derive human-readable fallback pieces.
  const numericId = extractNumericId(value);

  return (
    <div className={className} style={{ display: 'inline-block', textAlign: 'center' }}>
      <QRCodeSVG
        value={value}
        size={size}
        bgColor="#ffffff"
        fgColor="#000000"
        level="M"
        marginSize={1}
      />
      {label ? (
        <div style={{ fontSize: 10, marginTop: 4, color: '#333' }}>{label}</div>
      ) : null}

      {/* WEB-UIUX-687: plain-text fallback so the URL can be read aloud or
          typed when the QR cannot be scanned (cellular customer, LAN-only URL).
          Suppressed via hideFallbackUrl for opaque token URLs. */}
      {!hideFallbackUrl && (
        <div style={{ marginTop: 6, maxWidth: size + 32 }}>
          {numericId && (
            <div
              style={{
                fontFamily: 'monospace',
                fontSize: 15,
                fontWeight: 700,
                letterSpacing: 2,
                color: '#111',
                marginBottom: 2,
              }}
              title="Typeable receipt code"
            >
              #{numericId}
            </div>
          )}
          <div
            style={{
              fontFamily: 'monospace',
              fontSize: 9,
              color: '#555',
              wordBreak: 'break-all',
              lineHeight: 1.3,
            }}
            title={value}
          >
            {value}
          </div>
        </div>
      )}
    </div>
  );
}
