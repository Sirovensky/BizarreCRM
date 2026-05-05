import SwiftUI
import Observation
import DesignSystem

// MARK: - ImportStatusSummaryViewModel

@MainActor
@Observable
public final class ImportStatusSummaryViewModel: Sendable {

    // MARK: Published state

    /// Current display state driven by the most-recent fetch.
    public private(set) var state: ViewState = .idle

    public enum ViewState: Sendable, Equatable {
        case idle
        case loading
        case loaded(ImportSummary)
        case error(String)
    }

    // MARK: Derived helpers (pure — safe to test without async)

    public var pillLabel: String {
        guard case .loaded(let summary) = state else { return "" }
        switch summary.lastResult {
        case .none:
            return "No imports yet"
        case .success(let count, _):
            return "\(count) records imported"
        case .failure:
            return "Last import failed"
        }
    }

    public var pillHue: PillHue {
        guard case .loaded(let summary) = state else { return .neutral }
        switch summary.lastResult {
        case .none:               return .neutral
        case .success:            return .success
        case .failure:            return .failure
        }
    }

    public enum PillHue: Sendable, Equatable {
        case neutral, success, failure
    }

    public var hasActiveJob: Bool {
        guard case .loaded(let summary) = state else { return false }
        return summary.activeJobCount > 0
    }

    public var lastResultDate: Date? {
        guard case .loaded(let summary) = state else { return nil }
        switch summary.lastResult {
        case .success(_, let date): return date
        case .failure(_, let date): return date
        default:                    return nil
        }
    }

    // MARK: Private

    private let provider: (any ImportSummaryProvider)?

    public init(provider: (any ImportSummaryProvider)? = DataBridgeHolder.current.importProvider) {
        self.provider = provider
    }

    // MARK: Load

    public func load() async {
        guard let provider else {
            state = .loaded(ImportSummary())
            return
        }
        state = .loading
        let summary = await provider.fetchSummary()
        state = .loaded(summary)
    }
}

// MARK: - ImportStatusSummaryCard

/// Settings card that shows the last import result (success/failure pill)
/// and the number of active jobs.
public struct ImportStatusSummaryCard: View {

    @State private var vm: ImportStatusSummaryViewModel

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f
    }()

    public init(vm: ImportStatusSummaryViewModel? = nil) {
        let resolved = vm ?? ImportStatusSummaryViewModel()
        _vm = State(initialValue: resolved)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Label("Data Import", systemImage: "square.and.arrow.down")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                Spacer()

                if vm.hasActiveJob {
                    ProgressView()
                        .scaleEffect(0.75)
                        .accessibilityLabel("Import in progress")
                        .accessibilityIdentifier("importStatus.inProgress")
                }
            }

            switch vm.state {
            case .idle, .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("importStatus.loading")

            case .loaded:
                HStack(spacing: BrandSpacing.sm) {
                    pillView

                    if let date = vm.lastResultDate {
                        Text(Self.dateFormatter.localizedString(for: date, relativeTo: Date()))
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityIdentifier("importStatus.relativeDate")
                    }
                }

            case .error(let msg):
                Text(msg)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreError)
                    .accessibilityIdentifier("importStatus.error")
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Data Import status")
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
            .accessibilityLabel("Import status: \(label)")
            .accessibilityIdentifier("importStatus.pill")
    }

    private var pillStyle: (String, Color, Color) {
        switch vm.pillHue {
        case .success:  return (vm.pillLabel, .bizarreSuccess, .black)
        case .failure:  return (vm.pillLabel, .bizarreError,   .white)
        case .neutral:  return (vm.pillLabel, .bizarreSurface2, .bizarreOnSurface)
        }
    }
}
