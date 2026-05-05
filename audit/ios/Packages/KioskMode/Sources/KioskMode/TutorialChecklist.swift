import SwiftUI
import DesignSystem
import Core

// MARK: - TutorialTopic
//
// §51.3 — Tutorial checklist by topic (POS basics, ticket intake, invoicing, etc.)
// Each topic contains multiple steps that the user walks through in order.

public struct TutorialTopic: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let steps: [TutorialStep]

    public init(id: String, title: String, systemImage: String, steps: [TutorialStep]) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.steps = steps
    }
}

public extension TutorialTopic {
    /// Full built-in tutorial topic catalog (§51.3).
    static let catalog: [TutorialTopic] = [
        TutorialTopic(
            id: "pos-basics",
            title: "POS basics",
            systemImage: "cart",
            steps: [
                TutorialStep(id: 0, message: "Tap the POS tab to open the point-of-sale screen"),
                TutorialStep(id: 1, message: "Search or scan a product to add it to the cart"),
                TutorialStep(id: 2, message: "Tap Charge to collect payment"),
                TutorialStep(id: 3, message: "Choose cash, card, or gift card and confirm the sale"),
                TutorialStep(id: 4, message: "Print or email the receipt to the customer")
            ]
        ),
        TutorialTopic(
            id: "ticket-intake",
            title: "Ticket intake",
            systemImage: "wrench.and.screwdriver",
            steps: [
                TutorialStep(id: 0, message: "Tap the Tickets tab and press the + button"),
                TutorialStep(id: 1, message: "Search or create a customer record"),
                TutorialStep(id: 2, message: "Select the device type and describe the issue"),
                TutorialStep(id: 3, message: "Set a due date and assign a technician"),
                TutorialStep(id: 4, message: "Tap Save — the ticket is now in your queue")
            ]
        ),
        TutorialTopic(
            id: "invoicing",
            title: "Invoicing",
            systemImage: "doc.text",
            steps: [
                TutorialStep(id: 0, message: "Open a completed ticket and tap Create Invoice"),
                TutorialStep(id: 1, message: "Review line items — add parts or labour if needed"),
                TutorialStep(id: 2, message: "Apply a discount or tax rate if required"),
                TutorialStep(id: 3, message: "Tap Send to email the invoice to the customer"),
                TutorialStep(id: 4, message: "When paid, mark it as Paid — reports update instantly")
            ]
        ),
        TutorialTopic(
            id: "inventory",
            title: "Inventory",
            systemImage: "shippingbox",
            steps: [
                TutorialStep(id: 0, message: "Go to Inventory and tap the + to add a new part"),
                TutorialStep(id: 1, message: "Enter SKU, name, cost, and selling price"),
                TutorialStep(id: 2, message: "Set a reorder threshold so you get low-stock alerts"),
                TutorialStep(id: 3, message: "Scan a barcode to look up any item instantly"),
                TutorialStep(id: 4, message: "Use Stocktake to verify on-hand quantities")
            ]
        )
    ]
}

// MARK: - Completion store

/// Tracks which tutorial topics the current user has completed.
/// Persisted in UserDefaults keyed by topic ID.
public final class TutorialCompletionStore: ObservableObject {
    @Published public private(set) var completedTopicIDs: Set<String>

    private let key = "training.tutorialCompletedTopics"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let raw = defaults.stringArray(forKey: key) ?? []
        self.completedTopicIDs = Set(raw)
    }

    public func markComplete(_ topicID: String) {
        completedTopicIDs.insert(topicID)
        defaults.set(Array(completedTopicIDs), forKey: key)
    }

    public func reset() {
        completedTopicIDs = []
        defaults.removeObject(forKey: key)
    }

    public func isComplete(_ topicID: String) -> Bool {
        completedTopicIDs.contains(topicID)
    }
}

// MARK: - TutorialChecklistView

/// §51.3 — Checklist of tutorial topics by category.
/// Tapping a topic starts the overlay tutorial; completion marks the row green.
public struct TutorialChecklistView: View {
    @StateObject private var store = TutorialCompletionStore()
    @State private var activeTopic: TutorialTopic? = nil

    public init() {}

    public var body: some View {
        List {
            Section {
                ForEach(TutorialTopic.catalog) { topic in
                    TutorialTopicRow(
                        topic: topic,
                        isComplete: store.isComplete(topic.id)
                    ) {
                        activeTopic = topic
                    }
                }
            } header: {
                Text("Learn at your own pace")
                    .textCase(nil)
            } footer: {
                let done = TutorialTopic.catalog.filter { store.isComplete($0.id) }.count
                let total = TutorialTopic.catalog.count
                Text("\(done) of \(total) topics complete")
            }
        }
        .navigationTitle("Tutorials")
        .fullScreenCover(item: $activeTopic) { topic in
            TutorialTopicPlayer(topic: topic) {
                store.markComplete(topic.id)
                activeTopic = nil
            }
        }
    }
}

// MARK: - Topic row

private struct TutorialTopicRow: View {
    let topic: TutorialTopic
    let isComplete: Bool
    let onStart: () -> Void

    var body: some View {
        Button(action: onStart) {
            HStack(spacing: 12) {
                Image(systemName: topic.systemImage)
                    .font(.title3)
                    .foregroundStyle(isComplete ? .bizarreSuccess : .bizarreOrange)
                    .frame(width: 32)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(topic.title)
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("\(topic.steps.count) steps")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }

                Spacer()

                if isComplete {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel("Completed")
                } else {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(topic.title). \(topic.steps.count) steps. \(isComplete ? "Completed." : "Not started.")")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Topic player

/// Wraps `TutorialOverlayView` for a full topic, then calls `onComplete`.
private struct TutorialTopicPlayer: View {
    let topic: TutorialTopic
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            TutorialOverlayView(steps: topic.steps, onDismiss: onComplete)
        }
    }
}
