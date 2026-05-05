import SwiftUI
import Observation
import DesignSystem

// MARK: - SnoozedNotificationsViewModel

@MainActor
@Observable
public final class SnoozedNotificationsViewModel {

    public private(set) var entries: [SnoozedEntry] = []
    public private(set) var isLoading: Bool = false

    private let handler: SnoozeActionHandler

    public init(handler: SnoozeActionHandler = .shared) {
        self.handler = handler
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        entries = await handler.pendingSnoozes()
    }

    public func cancel(entry: SnoozedEntry) async {
        handler.cancelSnooze(for: entry.id)
        entries.removeAll { $0.id == entry.id }
    }
}

// MARK: - SnoozedNotificationsListView

/// Settings → Notifications → Snoozed.
/// Shows pending snoozed notifications; user can cancel any.
public struct SnoozedNotificationsListView: View {

    @State private var vm: SnoozedNotificationsViewModel

    public init(viewModel: SnoozedNotificationsViewModel = SnoozedNotificationsViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Snoozed")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.large)
        #endif
        .task { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading {
            ProgressView()
                .accessibilityLabel("Loading snoozed notifications")
        } else if vm.entries.isEmpty {
            emptyState
        } else {
            list
        }
    }

    @ViewBuilder
    private var list: some View {
        List {
            ForEach(vm.entries) { entry in
                entryRow(entry)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private func entryRow(_ entry: SnoozedEntry) -> some View {
        HStack(spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(entry.title)
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(entry.body)
                    .font(.brandBodySmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .lineLimit(1)
                Label {
                    Text(fireTimeText(entry.fireAt))
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOrange)
                } icon: {
                    Image(systemName: "alarm")
                        .foregroundStyle(.bizarreOrange)
                }
                .accessibilityLabel("Fires at \(fireTimeText(entry.fireAt))")
            }

            Spacer()

            Button(role: .destructive) {
                Task { await vm.cancel(entry: entry) }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.bizarreError)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Cancel snooze for \(entry.title)")
        }
        .padding(.vertical, BrandSpacing.xs)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.title). Snoozed until \(fireTimeText(entry.fireAt))")
        .accessibilityHint("Swipe right to cancel")
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await vm.cancel(entry: entry) }
            } label: {
                Label("Cancel Snooze", systemImage: "alarm.waves.left.and.right.fill")
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: BrandSpacing.lg) {
            Image(systemName: "alarm")
                .font(.system(size: 52))
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("No Snoozed Notifications")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("When you snooze a notification it will appear here so you can cancel it.")
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.xl)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func fireTimeText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today at \(formatter.string(from: date))" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow at \(formatter.string(from: date))" }
        formatter.dateStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Font helpers

private extension Font {
    static func brandLabelLarge() -> Font { .system(size: 15, weight: .semibold) }
    static func brandLabelSmall() -> Font { .system(size: 12) }
    static func brandBodySmall() -> Font { .system(size: 13) }
    static func brandBodyLarge() -> Font { .system(size: 16) }
    static func brandHeadlineMedium() -> Font { .system(size: 20, weight: .semibold) }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        SnoozedNotificationsListView()
    }
}
#endif
