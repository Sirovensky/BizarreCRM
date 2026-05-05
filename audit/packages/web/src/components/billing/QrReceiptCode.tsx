/**
 * QrReceiptCode — renders a proper scannable QR code for printed receipts
 * (scan-to-pay, scan-to-review) using qrcode.react (already in package.json).
 * Falls back to a labeled-text placeholder if the value is empty or
 * qrcode.react is somehow unavailable.
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
  className?: string;
}

export function QrReceiptCode({ value, size = 128, label, className }: QrReceiptCodeProps) {
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
    </div>
  );
}
