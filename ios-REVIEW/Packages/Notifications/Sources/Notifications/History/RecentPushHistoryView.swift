import SwiftUI
import Core
import DesignSystem

// MARK: - §70 Settings → Notifications → "Recent" — last 100 pushes for audit

// MARK: - ViewModel

@MainActor
@Observable
public final class RecentPushHistoryViewModel {

    public private(set) var records: [RecentPushRecord] = []
    public private(set) var isLoading: Bool = false

    private let store: RecentPushStore

    public init(store: RecentPushStore = .shared) {
        self.store = store
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        records = await store.all()
    }

    public func clearAll() async {
        await store.clearAll()
        records = []
    }
}

// MARK: - View

/// Shows the last 100 delivered push notifications.
/// Accessible via Settings → Notifications → Recent.
public struct RecentPushHistoryView: View {

    @State private var vm: RecentPushHistoryViewModel
    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var showClearConfirm = false

    public init(viewModel: RecentPushHistoryViewModel = RecentPushHistoryViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Recent Notifications")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .toolbar { toolbarContent }
        .task { await vm.load() }
        .confirmationDialog(
            "Clear notification history?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear All", role: .destructive) {
                Task { await vm.clearAll() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all \(vm.records.count) locally-stored notification records.")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if vm.records.isEmpty {
            emptyState
        } else {
            recordList
        }
    }

    private var emptyState: some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "bell.badge.slash")
                .font(.system(size: 48))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No recent notifications")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Notifications you receive will appear here for audit.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("No recent notifications. Notifications you receive will appear here for audit.")
    }

    private var recordList: some View {
        List(vm.records) { record in
            RecentPushRow(record: record)
                .listRowBackground(Color.bizarreSurface1)
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.plain)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .destructiveAction) {
            Button("Clear") {
                showClearConfirm = true
            }
            .foregroundStyle(.bizarreError)
            .disabled(vm.records.isEmpty)
            .accessibilityLabel("Clear all recent notifications")
        }
    }
}

// MARK: - RecentPushRow

private struct RecentPushRow: View {

    let record: RecentPushRecord

    private static let dateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(record.title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                    Text(record.body)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .lineLimit(2)
                }
                Spacer(minLength: BrandSpacing.xs)
                Text(Self.dateFormatter.localizedString(for: record.receivedAt, relativeTo: Date()))
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .fixedSize()
            }
            categoryBadge
        }
        .padding(.vertical, BrandSpacing.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.title). \(record.body). \(categoryLabel). Received \(Self.dateFormatter.localizedString(for: record.receivedAt, relativeTo: Date())).")
    }

    private var categoryLabel: String {
        record.eventType?.replacingOccurrences(of: ".", with: " ").capitalized
            ?? record.categoryID
    }

    private var categoryBadge: some View {
        Text(categoryLabel)
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreTeal)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, 2)
            .background(Color.bizarreTeal.opacity(0.12), in: Capsule())
            .accessibilityHidden(true)
    }
}

// MARK: - Font extensions (local aliases matching the rest of the package)

private extension Font {
    static func brandTitleMedium() -> Font { .system(size: 18, weight: .semibold) }
    static func brandBodyLarge()   -> Font { .system(size: 16) }
    static func brandBodyMedium()  -> Font { .system(size: 14) }
    static func brandLabelSmall()  -> Font { .system(size: 12) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        RecentPushHistoryView(
            viewModel: {
                let vm = RecentPushHistoryViewModel()
                return vm
            }()
        )
    }
}
#endif
