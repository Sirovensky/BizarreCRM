import SwiftUI
import Observation
import DesignSystem

// MARK: - ExportStatusSummaryViewModel

@MainActor
@Observable
public final class ExportStatusSummaryViewModel: Sendable {

    // MARK: Published state

    public private(set) var state: ViewState = .idle

    public enum ViewState: Sendable, Equatable {
        case idle
        case loading
        case loaded(ExportSummary)
        case error(String)
    }

    // MARK: Derived helpers

    public var pillLabel: String {
        guard case .loaded(let summary) = state else { return "" }
        switch summary.lastResult {
        case .none:     return "No exports yet"
        case .success:  return "Export ready"
        case .failure:  return "Last export failed"
        }
    }

    public var pillHue: PillHue {
        guard case .loaded(let summary) = state else { return .neutral }
        switch summary.lastResult {
        case .none:    return .neutral
        case .success: return .success
        case .failure: return .failure
        }
    }

    public enum PillHue: Sendable, Equatable {
        case neutral, success, failure
    }

    public var isExporting: Bool {
        guard case .loaded(let summary) = state else { return false }
        return summary.isExporting
    }

    /// Human-readable next scheduled run label, or nil if not scheduled.
    public var nextRunLabel: String? {
        guard case .loaded(let summary) = state,
              let raw = summary.nextScheduledRunAt else { return nil }
        return Self.formatNextRun(raw)
    }

    public var lastResultDate: Date? {
        guard case .loaded(let summary) = state else { return nil }
        switch summary.lastResult {
        case .success(let date):    return date
        case .failure(_, let date): return date
        default:                    return nil
        }
    }

    // MARK: Private

    private let provider: (any ExportSummaryProvider)?

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public init(provider: (any ExportSummaryProvider)? = DataBridgeHolder.current.exportProvider) {
        self.provider = provider
    }

    // MARK: Load

    public func load() async {
        guard let provider else {
            state = .loaded(ExportSummary())
            return
        }
        state = .loading
        let summary = await provider.fetchSummary()
        state = .loaded(summary)
    }

    // MARK: Helpers

    private static func formatNextRun(_ iso: String) -> String {
        if let date = iso8601Formatter.date(from: iso) {
            let rel = relativeDateFormatter.localizedString(for: date, relativeTo: Date())
            return "Next: \(rel)"
        }
        // Fallback: return the raw string trimmed to first 16 chars
        return "Next: \(iso.prefix(16))"
    }
}

// MARK: - ExportStatusSummaryCard

/// Settings card showing the last export result pill and the next scheduled run.
public struct ExportStatusSummaryCard: View {

    @State private var vm: ExportStatusSummaryViewModel

    public init(vm: ExportStatusSummaryViewModel? = nil) {
        let resolved = vm ?? ExportStatusSummaryViewModel()
        _vm = State(initialValue: resolved)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Data Export", systemImage: "square.and.arrow.up")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer()

                if vm.isExporting {
                    ProgressView()
                        .scaleEffect(0.75)
                        .accessibilityLabel("Export in progress")
                        .accessibilityIdentifier("exportStatus.inProgress")
                }
            }

            switch vm.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("exportStatus.loading")

            case .loaded:
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    HStack(spacing: BrandSpacing.sm) {
                        pillView

                        if let date = vm.lastResultDate {
                            Text(relativeDate(date))
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                                .accessibilityIdentifier("exportStatus.relativeDate")
                        }
                    }

                    if let next = vm.nextRunLabel {
                        HStack(spacing: BrandSpacing.xs) {
                            Image(systemName: "clock")
                                .font(.caption2)
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            Text(next)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .accessibilityLabel(next)
                        .accessibilityIdentifier("exportStatus.nextRun")
                    }
                }

            case .error(let msg):
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("exportStatus.error")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data Export status")
        .task { await vm.load() }
    }

    @ViewBuilder
    private var pillView: some View {
        let (label, bg, fg) = pillStyle
        Text(label)
            .font(.brandLabelSmall())
            .padding(.horizontal, BrandSpacing.md)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(fg)
            .background(bg, in: Capsule())
            .accessibilityLabel("Export status: \(label)")
            .accessibilityIdentifier("exportStatus.pill")
    }

    private var pillStyle: (String, Color, Color) {
        switch vm.pillHue {
        case .success:  return (vm.pillLabel, .bizarreSuccess, .black)
        case .failure:  return (vm.pillLabel, .bizarreError,   .white)
        case .neutral:  return (vm.pillLabel, .bizarreSurface2, .bizarreOnSurface)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    private func relativeDate(_ date: Date) -> String {
        Self.relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}
