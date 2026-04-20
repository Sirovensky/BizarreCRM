interface SparklineProps {
  data: readonly number[];
  /** Total width in px (SVG render box). */
  width?: number;
  /** Total height in px. */
  height?: number;
  /** Stroke colour. Defaults to currentColor so the parent can drive it. */
  color?: string;
  /** Fill area below the line (translucent). */
  fill?: boolean;
  /** Optional className for the SVG. */
  className?: string;
}

/**
 * Tiny inline trend renderer. Designed to live inside a StatCard so the
 * absolute number stays the dominant element and the sparkline sits as
 * subtext giving "is this rising or falling" context. Renders nothing
 * when given fewer than 2 points so the layout stays stable while the
 * series fills in after a few stat polls.
 */
export function Sparkline({
  data, width = 64, height = 20, color = 'currentColor', fill = false, className,
}: SparklineProps) {
  if (data.length < 2) {
    return (
      <svg width={width} height={height} className={className} aria-hidden>
        <line x1={0} y1={height / 2} x2={width} y2={height / 2} stroke={color} strokeWidth={1} strokeOpacity={0.2} strokeDasharray="2 3" />
      </svg>
    );
  }
  const max = Math.max(...data);
  const min = Math.min(...data);
  const range = max - min || 1;
  const stepX = data.length > 1 ? width / (data.length - 1) : width;
  const points = data
    .map((v, i) => `${(i * stepX).toFixed(2)},${(height - ((v - min) / range) * (height - 2) - 1).toFixed(2)}`)
    .join(' ');

  return (
    <svg width={width} height={height} className={className} aria-hidden>
      {fill && (
        <polygon
          points={`0,${height} ${points} ${width},${height}`}
          fill={color}
          fillOpacity={0.15}
        />
      )}
      <polyline
        points={points}
        fill="none"
        stroke={color}
        strokeWidth={1.25}
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  );
}
