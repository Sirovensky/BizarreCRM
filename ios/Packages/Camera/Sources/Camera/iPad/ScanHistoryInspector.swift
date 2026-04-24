#if canImport(UIKit)
import SwiftUI
import DesignSystem

// MARK: - ScanHistoryInspector

/// Trailing-edge slide-over panel showing the last N barcodes scanned in the
/// current camera session.
///
/// Design:
/// - Liquid Glass panel header with "Scan History" title + close button.
/// - Scrollable list of ``ScannedBarcodeEntry`` rows (value + symbology + time).
/// - Empty state when no codes have been scanned yet.
/// - "Clear" toolbar action wipes the session list.
///
/// Pluggable: callers own the `entries` array; this view is read-only with
/// an `onClose` callback and an optional `onClear` for the clear action.
public struct ScanHistoryInspector: View {

    // MARK: - Init

    /// Maximum entries rendered; older overflow is trimmed by the caller.
    private static let maxVisible = 50

    private let entries: [ScannedBarcodeEntry]
    private let onClose: () -> Void
    private let onClear: (() -> Void)?

    public init(
        entries: [ScannedBarcodeEntry],
        onClose: @escaping () -> Void,
        onClear: (() -> Void)? = nil
    ) {
        self.entries = entries
        self.onClose = onClose
        self.onClear = onClear
    }

    // MARK: - State

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Body

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
                .background(Color.white.opacity(0.2))
            scrollContent
        }
        .background(Color.bizarreSurface1.opacity(0.96))
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
        .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Scan history panel")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Scan History")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if let onClear, !entries.isEmpty {
                Button(action: onClear) {
                    Text("Clear")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear scan history")
                .accessibilityIdentifier("camera.ipad.scanHistory.clear")
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.1), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close scan history")
            .accessibilityIdentifier("camera.ipad.scanHistory.close")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .brandGlass(.regular, in: Rectangle())
    }

    // MARK: - Scroll content

    @ViewBuilder
    private var scrollContent: some View {
        if entries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries.prefix(Self.maxVisible)) { entry in
                        EntryRow(entry: entry)
                        Divider()
                            .padding(.leading, DesignTokens.Spacing.lg)
                            .background(Color.white.opacity(0.08))
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Spacer()
            Image(systemName: "barcode.viewfinder")
                .font(.system(size: 44, weight: .ultraLight))
                .foregroundStyle(.bizarreOnSurfaceMuted.opacity(0.5))
                .accessibilityHidden(true)
            Text("No codes scanned yet")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(DesignTokens.Spacing.lg)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("No barcodes scanned in this session")
    }
}

// MARK: - EntryRow

private struct EntryRow: View {
    let entry: ScannedBarcodeEntry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.value)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .accessibilityLabel("Barcode value: \(entry.value)")

                Text(entry.symbology)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            Text(Self.timeFormatter.string(from: entry.scannedAt))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityLabel("Scanned at \(Self.timeFormatter.string(from: entry.scannedAt))")
        }
        .padding(.horizontal, DesignTokens.Spacing.lg)
        .padding(.vertical, DesignTokens.Spacing.md)
        .hoverEffect(.highlight)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - ScanHistoryInspector + append helper

public extension ScanHistoryInspector {
    /// Creates a new entry array by prepending a fresh entry, capped at `limit`.
    /// Pure function — never mutates the original array.
    static func prepending(
        _ barcode: ScannedBarcodeEntry,
        to existing: [ScannedBarcodeEntry],
        limit: Int = 50
    ) -> [ScannedBarcodeEntry] {
        let updated = [barcode] + existing
        return Array(updated.prefix(limit))
    }
}

#endif
