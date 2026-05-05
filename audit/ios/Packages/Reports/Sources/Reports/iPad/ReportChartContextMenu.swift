import SwiftUI
import DesignSystem

// MARK: - ReportChartContextMenu

/// Context-menu modifier for iPad chart surfaces in Reports.
///
/// Provides three actions:
///   - Save as PDF    — triggers `onSaveAsPDF`, caller presents `ShareLink`
///   - Copy Summary   — copies a text summary to the clipboard
///   - Toggle Legend  — flips `isLegendVisible` binding
///
/// Liquid Glass is applied only to the toolbar chrome layer above the chart,
/// never inside the chart surface itself (per CLAUDE.md rule).
public struct ReportChartContextMenu: ViewModifier {

    // MARK: - Configuration

    /// Called when the user taps "Save as PDF". Caller should present `ShareLink(item: url)`.
    public let onSaveAsPDF: () -> Void

    /// A plain-text summary to copy to the pasteboard (e.g. "Revenue $12,345 (+5%)").
    public let summaryText: String

    /// Binding that toggles the legend inspector.
    @Binding public var isLegendVisible: Bool

    // MARK: - Body

    public func body(content: Content) -> some View {
        content
            .contextMenu {
                Button {
                    onSaveAsPDF()
                } label: {
                    Label("Save as PDF", systemImage: "doc.richtext")
                }
                .accessibilityLabel("Save report as PDF")

                Button {
                    copyToClipboard(summaryText)
                } label: {
                    Label("Copy Summary", systemImage: "doc.on.clipboard")
                }
                .accessibilityLabel("Copy report summary to clipboard")

                Divider()

                Button {
                    isLegendVisible.toggle()
                } label: {
                    Label(
                        isLegendVisible ? "Hide Legend" : "Show Legend",
                        systemImage: isLegendVisible
                            ? "list.bullet.rectangle.fill"
                            : "list.bullet.rectangle"
                    )
                }
                .accessibilityLabel(isLegendVisible ? "Hide legend" : "Show legend")
            }
    }

    // MARK: - Private

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }
}

// MARK: - View extension

public extension View {
    /// Attaches the `ReportChartContextMenu` to a chart view.
    ///
    /// Example:
    /// ```swift
    /// RevenueChartCard(...)
    ///     .reportChartContextMenu(
    ///         summaryText: "Revenue $12,345",
    ///         isLegendVisible: $showLegend,
    ///         onSaveAsPDF: { Task { await exportPDF() } }
    ///     )
    /// ```
    func reportChartContextMenu(
        summaryText: String,
        isLegendVisible: Binding<Bool>,
        onSaveAsPDF: @escaping () -> Void
    ) -> some View {
        modifier(
            ReportChartContextMenu(
                onSaveAsPDF: onSaveAsPDF,
                summaryText: summaryText,
                isLegendVisible: isLegendVisible
            )
        )
    }
}

// MARK: - ReportChartContextMenuState

/// Observable state holder for a chart's context-menu lifecycle.
/// Holds a pending export URL until the caller presents `ShareLink`.
@Observable
@MainActor
public final class ReportChartContextMenuState {
    public var isLegendVisible: Bool = false
    public var pendingShareURL: URL? = nil
    public var exportError: String? = nil

    public init() {}

    /// Prepare a PDF URL and make it available for `ShareLink` presentation.
    public func setPendingShare(url: URL) {
        pendingShareURL = url
    }

    /// Clear the pending URL (called after share sheet dismissal).
    public func clearPendingShare() {
        pendingShareURL = nil
    }

    public func setExportError(_ message: String) {
        exportError = message
    }

    public func clearExportError() {
        exportError = nil
    }
}
