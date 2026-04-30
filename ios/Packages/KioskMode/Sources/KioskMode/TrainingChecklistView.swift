import SwiftUI
import DesignSystem
import Core

// MARK: - §51.3 Training checklist by topic

// MARK: - TrainingTopic

/// A training topic with a list of steps. Persisted as completed in UserDefaults.
public struct TrainingTopic: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let icon: String
    public let description: String
    public let steps: [TrainingStep]

    public init(id: String, title: String, icon: String, description: String, steps: [TrainingStep]) {
        self.id = id
        self.title = title
        self.icon = icon
        self.description = description
        self.steps = steps
    }
}

// MARK: - TrainingStep

public struct TrainingStep: Identifiable, Sendable {
    public let id: String
    public let instruction: String

    public init(id: String, instruction: String) {
        self.id = id
        self.instruction = instruction
    }
}

// MARK: - Default topics

public extension TrainingTopic {
    static let all: [TrainingTopic] = [
        TrainingTopic(
            id: "pos-basics",
            title: "POS Basics",
            icon: "dollarsign.circle.fill",
            description: "Ring up a sale and process a payment.",
            steps: [
                TrainingStep(id: "pos-1", instruction: "Open the POS tab from the bottom bar."),
                TrainingStep(id: "pos-2", instruction: "Tap 'Add item' and search for a product by name or SKU."),
                TrainingStep(id: "pos-3", instruction: "Review the cart total and tap 'Charge'."),
                TrainingStep(id: "pos-4", instruction: "Select a payment method (Cash, Card, Gift Card)."),
                TrainingStep(id: "pos-5", instruction: "Confirm the payment and send a receipt via SMS or email.")
            ]
        ),
        TrainingTopic(
            id: "ticket-intake",
            title: "Ticket Intake",
            icon: "wrench.and.screwdriver.fill",
            description: "Create a repair ticket for a customer device.",
            steps: [
                TrainingStep(id: "tk-1", instruction: "Tap the Tickets tab, then '+' to create a new ticket."),
                TrainingStep(id: "tk-2", instruction: "Search for an existing customer or create a new one."),
                TrainingStep(id: "tk-3", instruction: "Add the device: select make and model, enter IMEI/serial if known."),
                TrainingStep(id: "tk-4", instruction: "Complete the intake checklist (screen condition, accessories, etc.)."),
                TrainingStep(id: "tk-5", instruction: "Add diagnostic notes, assign a technician, and set urgency."),
                TrainingStep(id: "tk-6", instruction: "Save the ticket. The customer receives an SMS confirmation.")
            ]
        ),
        TrainingTopic(
            id: "invoicing",
            title: "Invoicing",
            icon: "doc.text.fill",
            description: "Generate and collect payment on an invoice.",
            steps: [
                TrainingStep(id: "inv-1", instruction: "Open the Invoices tab and tap '+' to create a new invoice."),
                TrainingStep(id: "inv-2", instruction: "Link to a customer. Add line items: services + parts."),
                TrainingStep(id: "inv-3", instruction: "Apply any discounts or tax overrides as needed."),
                TrainingStep(id: "inv-4", instruction: "Tap 'Send invoice' — choose SMS or email delivery."),
                TrainingStep(id: "inv-5", instruction: "When the customer pays, tap 'Record payment' and select tender.")
            ]
        ),
        TrainingTopic(
            id: "inventory",
            title: "Inventory",
            icon: "archivebox.fill",
            description: "Look up stock levels and receive new parts.",
            steps: [
                TrainingStep(id: "inv-stk-1", instruction: "Open the Inventory tab. Search by part name, SKU, or barcode."),
                TrainingStep(id: "inv-stk-2", instruction: "Tap an item to see stock level, cost, and location."),
                TrainingStep(id: "inv-stk-3", instruction: "To receive new stock: tap 'Receive' and enter quantities."),
                TrainingStep(id: "inv-stk-4", instruction: "Generate a purchase order for a supplier via the PO tab.")
            ]
        )
    ]
}

// MARK: - TrainingChecklistViewModel

@MainActor
@Observable
public final class TrainingChecklistViewModel {

    // MARK: - State

    public var topics: [TrainingTopic] = TrainingTopic.all
    private var completedStepIds: Set<String>

    private static let defaultsKey = "training.checklist.completedSteps"
    private let defaults: UserDefaults

    // MARK: - Init

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        self.completedStepIds = Set(saved)
    }

    // MARK: - Queries

    public func isCompleted(_ step: TrainingStep) -> Bool {
        completedStepIds.contains(step.id)
    }

    public func completedCount(for topic: TrainingTopic) -> Int {
        topic.steps.filter { completedStepIds.contains($0.id) }.count
    }

    public func isTopicComplete(_ topic: TrainingTopic) -> Bool {
        topic.steps.allSatisfy { completedStepIds.contains($0.id) }
    }

    public var overallProgress: Double {
        let total = topics.flatMap { $0.steps }.count
        guard total > 0 else { return 0 }
        let done = topics.flatMap { $0.steps }.filter { completedStepIds.contains($0.id) }.count
        return Double(done) / Double(total)
    }

    // MARK: - Mutations

    public func toggleStep(_ step: TrainingStep) {
        if completedStepIds.contains(step.id) {
            completedStepIds.remove(step.id)
        } else {
            completedStepIds.insert(step.id)
        }
        persist()
    }

    public func resetAll() {
        completedStepIds = []
        persist()
    }

    private func persist() {
        defaults.set(Array(completedStepIds), forKey: Self.defaultsKey)
    }
}

// MARK: - TrainingChecklistView

/// §51.3 Tutorial checklist organised by topic (POS basics, ticket intake,
/// invoicing, inventory).
///
/// - iPhone: `List` with collapsible topic sections.
/// - iPad: `NavigationSplitView` — topic list on left, steps on right.
public struct TrainingChecklistView: View {

    @State private var vm: TrainingChecklistViewModel
    @State private var selectedTopic: TrainingTopic?

    public init(viewModel: TrainingChecklistViewModel = TrainingChecklistViewModel()) {
        self._vm = State(wrappedValue: viewModel)
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                iPhoneLayout
            } else {
                iPadLayout
            }
        }
        .navigationTitle("Training Checklist")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Reset all") { vm.resetAll() }
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .accessibilityLabel("Reset all training progress")
            }
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        List {
            overallProgressSection

            ForEach(vm.topics) { topic in
                Section {
                    ForEach(topic.steps) { step in
                        stepRow(step)
                    }
                } header: {
                    topicHeader(topic)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(vm.topics, selection: $selectedTopic) { topic in
                topicNavRow(topic)
            }
            .listStyle(.sidebar)
            .navigationTitle("Topics")
        } detail: {
            if let topic = selectedTopic {
                topicDetailView(topic)
            } else {
                ContentUnavailableView(
                    "Select a topic",
                    systemImage: "checkmark.circle",
                    description: Text("Choose a training topic to see its steps.")
                )
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
            }
        }
    }

    // MARK: - Overall progress

    private var overallProgressSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                HStack {
                    Text("Overall progress")
                        .font(.brandBodyMedium())
                    Spacer()
                    Text("\(Int(vm.overallProgress * 100))%")
                        .font(.brandBodyMedium().bold())
                        .foregroundStyle(Color.bizarreOrange)
                }
                ProgressView(value: vm.overallProgress)
                    .tint(Color.bizarreOrange)
                    .accessibilityLabel("Overall training progress \(Int(vm.overallProgress * 100)) percent")
            }
            .padding(.vertical, BrandSpacing.xxs)
        }
    }

    // MARK: - Topic header (iPhone section header)

    private func topicHeader(_ topic: TrainingTopic) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: topic.icon)
                .foregroundStyle(Color.bizarreOrange)
                .accessibilityHidden(true)
            Text(topic.title)
                .font(.brandLabelLarge().bold())
                .foregroundStyle(Color.bizarreOnSurface)
            Spacer()
            Text("\(vm.completedCount(for: topic))/\(topic.steps.count)")
                .font(.brandLabelSmall())
                .foregroundStyle(Color.bizarreOnSurfaceMuted)
        }
        .textCase(nil)
    }

    // MARK: - Topic nav row (iPad sidebar)

    private func topicNavRow(_ topic: TrainingTopic) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: topic.icon)
                .foregroundStyle(Color.bizarreOrange)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(topic.title)
                    .font(.brandBodyLarge())
                Text(topic.description)
                    .font(.brandLabelSmall())
                    .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    .lineLimit(1)
            }
            Spacer()
            if vm.isTopicComplete(topic) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.bizarreSuccess)
                    .accessibilityLabel("Topic complete")
            }
        }
        .tag(topic as TrainingTopic?)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(topic.title), \(vm.completedCount(for: topic)) of \(topic.steps.count) steps done")
    }

    // MARK: - Step row

    private func stepRow(_ step: TrainingStep) -> some View {
        let done = vm.isCompleted(step)
        return HStack(spacing: BrandSpacing.md) {
            Button {
                vm.toggleStep(step)
            } label: {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Color.bizarreSuccess : Color.bizarreOnSurfaceMuted)
                    .frame(width: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "Mark as incomplete" : "Mark as complete")
            .accessibilityHint(step.instruction)

            Text(step.instruction)
                .font(.brandBodyMedium())
                .foregroundStyle(done ? Color.bizarreOnSurfaceMuted : Color.bizarreOnSurface)
                .strikethrough(done, color: Color.bizarreOnSurfaceMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, BrandSpacing.xxs)
        .contentShape(Rectangle())
        .onTapGesture { vm.toggleStep(step) }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Topic detail view (iPad)

    private func topicDetailView(_ topic: TrainingTopic) -> some View {
        List {
            Section {
                ForEach(topic.steps) { step in
                    stepRow(step)
                }
            } header: {
                VStack(alignment: .leading, spacing: BrandSpacing.sm) {
                    HStack(spacing: BrandSpacing.sm) {
                        Image(systemName: topic.icon)
                            .font(.system(size: 28))
                            .foregroundStyle(Color.bizarreOrange)
                        Text(topic.title)
                            .font(.brandDisplaySmall())
                    }
                    Text(topic.description)
                        .font(.brandBodyMedium())
                        .foregroundStyle(Color.bizarreOnSurfaceMuted)
                    ProgressView(value: Double(vm.completedCount(for: topic)) / Double(topic.steps.count))
                        .tint(Color.bizarreOrange)
                        .accessibilityLabel("Topic progress \(vm.completedCount(for: topic)) of \(topic.steps.count) steps done")
                }
                .textCase(nil)
                .padding(.vertical, BrandSpacing.sm)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(topic.title)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

// MARK: - TrainingTopic: Hashable + Equatable (needed for NavigationSplitView selection)

extension TrainingTopic: Hashable, Equatable {
    public static func == (lhs: TrainingTopic, rhs: TrainingTopic) -> Bool {
        lhs.id == rhs.id
    }
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
