import SwiftUI
import DesignSystem
import Observation

// MARK: - DigestPreviewSheetViewModel

/// Computes what the next digest would look like given the current pending notification queue.
/// Pure projection — no side effects, no persistence.
@MainActor
@Observable
public final class DigestPreviewSheetViewModel {

    // MARK: - Inputs

    public private(set) var pendingNotifications: [GroupableNotification]
    public private(set) var scheduleConfig: DigestScheduleConfig
    public private(set) var includedCategories: Set<EventCategory>

    // MARK: - Derived

    /// Summary rows for the preview card, one per included category with pending items.
    public var previewItems: [DigestSummaryItem] {
        let filtered = pendingNotifications.filter { n in
            includedCategories.contains(n.category) && n.priority != .critical
        }
        var counts = [EventCategory: Int]()
        for n in filtered {
            counts[n.category, default: 0] += 1
        }
        return EventCategory.allCases
            .filter { counts[$0, default: 0] > 0 }
            .map { DigestSummaryItem(category: $0, count: counts[$0]!) }
    }

    /// Total notification count that would appear in the next digest.
    public var totalCount: Int { previewItems.reduce(0) { $0 + $1.count } }

    /// Human-readable description of when the next digest fires.
    public var nextFireDescription: String {
        guard scheduleConfig.cadence.isActive else { return "Digest is disabled." }
        let now = Calendar.current.component(.hour, from: Date())
        if let next = scheduleConfig.nextFireHour(after: now) {
            let time = DigestTime(hour: next, minute: 0)
            return "Next digest at \(time.displayString)"
        }
        return "All hours suppressed by quiet hours."
    }

    /// Whether quiet hours are currently active.
    public var isInQuietHours: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return scheduleConfig.quietHours.isSuppressed(hour: hour)
    }

    // MARK: - Init

    public init(
        pendingNotifications: [GroupableNotification] = [],
        scheduleConfig: DigestScheduleConfig = DigestScheduleConfig(),
        includedCategories: Set<EventCategory> = Set(EventCategory.allCases)
    ) {
        self.pendingNotifications = pendingNotifications
        self.scheduleConfig       = scheduleConfig
        self.includedCategories   = includedCategories
    }

    // MARK: - Mutations

    public func update(
        notifications: [GroupableNotification]? = nil,
        config: DigestScheduleConfig? = nil,
        categories: Set<EventCategory>? = nil
    ) {
        if let n = notifications { pendingNotifications = n }
        if let c = config        { scheduleConfig = c }
        if let cats = categories { includedCategories = cats }
    }
}

// MARK: - DigestPreviewSheet

/// Sheet that shows what the next digest would contain given the live queue.
/// Presented as a bottom sheet on iPhone; popover/modal on iPad.
public struct DigestPreviewSheet: View {

    @State private var vm: DigestPreviewSheetViewModel
    @Environment(\.dismiss) private var dismiss

    public init(viewModel: DigestPreviewSheetViewModel = DigestPreviewSheetViewModel()) {
        _vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                content
            }
            .navigationTitle("Next Digest Preview")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { closeButton }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.base) {
                scheduleStatusCard
                previewCard
                if vm.isInQuietHours {
                    quietHoursBanner
                }
                if vm.totalCount == 0 {
                    emptyQueueCard
                }
            }
            .padding(BrandSpacing.base)
        }
    }

    // MARK: - Schedule status card

    @ViewBuilder
    private var scheduleStatusCard: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: cadenceIconName)
                .font(.system(size: 22))
                .foregroundStyle(Color.bizarreTeal)
                .frame(width: 36)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(vm.scheduleConfig.cadence.displayName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.bizarreOnSurface)
                Text(vm.nextFireDescription)
                    .font(.system(size: 13))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            cadencePill
        }
        .padding(BrandSpacing.md)
        .background(glassBackground)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Schedule: \(vm.scheduleConfig.cadence.accessibilityLabel). \(vm.nextFireDescription)")
    }

    @ViewBuilder
    private var cadencePill: some View {
        Text(vm.scheduleConfig.cadence.displayName)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(vm.scheduleConfig.cadence.isActive ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted,
                        in: Capsule())
    }

    // MARK: - Preview card

    @ViewBuilder
    private var previewCard: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            headerRow
            Divider()
            if vm.previewItems.isEmpty {
                noItemsRow
            } else {
                itemRows
            }
            Spacer(minLength: 0)
        }
        .padding(BrandSpacing.base)
        .background(glassBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(vm.totalCount == 0
            ? "Digest preview: no pending notifications"
            : "Digest preview: \(vm.totalCount) notifications")
    }

    @ViewBuilder
    private var headerRow: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
            Text("Would contain \(vm.totalCount) notification\(vm.totalCount == 1 ? "" : "s")")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
    }

    @ViewBuilder
    private var noItemsRow: some View {
        Text("Queue is empty — nothing to digest right now.")
            .font(.system(size: 14))
            .foregroundStyle(.bizarreOnSurfaceMuted)
    }

    @ViewBuilder
    private var itemRows: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            ForEach(vm.previewItems) { item in
                HStack {
                    Circle()
                        .fill(Color.bizarreOrange)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(item.label.capitalized)
                        .font(.system(size: 14))
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    Text("\(item.count)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurface)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.count) \(item.category.rawValue.lowercased()) notifications")
            }
        }
    }

    // MARK: - Quiet-hours banner

    @ViewBuilder
    private var quietHoursBanner: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "moon.fill")
                .foregroundStyle(Color.bizarreTeal)
                .accessibilityHidden(true)
            Text("Quiet hours active (\(vm.scheduleConfig.quietHours.displayString)). Delivery paused.")
                .font(.system(size: 13))
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
        }
        .padding(BrandSpacing.md)
        .background(Color.bizarreTeal.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityLabel("Quiet hours are active. Digest delivery is paused until \(vm.scheduleConfig.quietHours.endHour) AM.")
    }

    // MARK: - Empty queue card

    @ViewBuilder
    private var emptyQueueCard: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.bizarreTeal)
                .accessibilityHidden(true)
            Text("All caught up!")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.bizarreOnSurface)
            Text("No pending notifications to digest.")
                .font(.system(size: 13))
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.xl)
        .accessibilityLabel("No pending notifications to include in digest.")
    }

    // MARK: - Glass background

    @ViewBuilder
    private var glassBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color.bizarreSurface1)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.bizarreOutline.opacity(0.25), lineWidth: 1)
            )
    }

    // MARK: - Cadence icon

    private var cadenceIconName: String {
        switch vm.scheduleConfig.cadence {
        case .off:        return "bell.slash"
        case .hourly:     return "clock.arrow.circlepath"
        case .threeDaily: return "3.circle"
        case .daily:      return "sun.max"
        }
    }

    // MARK: - Close button

    @ToolbarContentBuilder
    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
                .accessibilityLabel("Close digest preview")
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    let items: [GroupableNotification] = [
        GroupableNotification(event: .ticketAssigned, title: "Ticket #1001", body: "Screen repair", receivedAt: Date()),
        GroupableNotification(event: .ticketStatusChangeMine, title: "Ticket #999 updated", body: "In progress", receivedAt: Date().addingTimeInterval(-600)),
        GroupableNotification(event: .invoicePaid, title: "Invoice #456 paid", body: "$120.00", receivedAt: Date().addingTimeInterval(-3600)),
        GroupableNotification(event: .smsInbound, title: "SMS from +1-555-1234", body: "Is my phone ready?", receivedAt: Date().addingTimeInterval(-60)),
    ]
    DigestPreviewSheet(
        viewModel: DigestPreviewSheetViewModel(
            pendingNotifications: items,
            scheduleConfig: DigestScheduleConfig(cadence: .threeDaily)
        )
    )
}
#endif
