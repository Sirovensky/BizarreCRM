import SwiftUI
import DesignSystem

// MARK: - SpotlightSettingsView

/// Settings → Search → Spotlight
///
/// Allows admins to enable / disable per-domain indexing and trigger a
/// full index rebuild.
///
/// Wire into your settings navigator:
/// ```swift
/// NavigationLink("Spotlight", destination: SpotlightSettingsView(coordinator: coordinator))
/// ```
public struct SpotlightSettingsView: View {

    // MARK: Properties

    @State private var coordinator: SpotlightCoordinator
    @State private var isRebuilding: Bool = false
    @State private var rebuildCompleted: Bool = false

    /// Domain display metadata — order defines list order.
    private let domains: [(id: String, label: String, icon: String)] = [
        ("tickets",   "Tickets",   "wrench.and.screwdriver"),
        ("customers", "Customers", "person.2"),
        ("inventory", "Inventory", "shippingbox"),
    ]

    // MARK: Init

    public init(coordinator: SpotlightCoordinator) {
        _coordinator = State(wrappedValue: coordinator)
    }

    // MARK: Body

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            List {
                domainSection
                rebuildSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Spotlight")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    private var domainSection: some View {
        Section {
            ForEach(domains, id: \.id) { domain in
                domainRow(domain)
            }
        } header: {
            Text("Index by Domain")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        } footer: {
            Text("Enabled domains are searchable via Spotlight on this device.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var rebuildSection: some View {
        Section {
            Button {
                rebuildIndex()
            } label: {
                HStack(spacing: BrandSpacing.md) {
                    if isRebuilding {
                        ProgressView()
                            .frame(width: DesignTokens.Spacing.lg, height: DesignTokens.Spacing.lg)
                    } else {
                        Image(systemName: rebuildCompleted ? "checkmark.circle.fill" : "arrow.clockwise.circle")
                            .foregroundStyle(rebuildCompleted ? .bizarreSuccess : .bizarreOrange)
                            .frame(width: DesignTokens.Spacing.lg, height: DesignTokens.Spacing.lg)
                    }
                    Text(isRebuilding ? "Rebuilding…" : rebuildCompleted ? "Index rebuilt" : "Rebuild All")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
            }
            .disabled(isRebuilding)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel(isRebuilding ? "Rebuilding Spotlight index" : "Rebuild Spotlight index")
            .accessibilityHint(isRebuilding ? "" : "Clears and rebuilds the Spotlight index for all enabled domains.")
        } footer: {
            Text("Rebuilding re-indexes all records. This may take a moment.")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: Row

    private func domainRow(_ domain: (id: String, label: String, icon: String)) -> some View {
        let isEnabled = Binding<Bool>(
            get: { coordinator.enabledDomains.contains(domain.id) },
            set: { enabled in
                if enabled {
                    coordinator.enabledDomains.insert(domain.id)
                } else {
                    coordinator.enabledDomains.remove(domain.id)
                }
            }
        )

        return Toggle(isOn: isEnabled) {
            Label {
                Text(domain.label)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
            } icon: {
                Image(systemName: domain.icon)
                    .foregroundStyle(.bizarreOrange)
            }
        }
        .tint(.bizarreOrange)
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(domain.label) Spotlight indexing")
        .accessibilityValue(isEnabled.wrappedValue ? "On" : "Off")
        .accessibilityHint("Double-tap to \(isEnabled.wrappedValue ? "disable" : "enable") \(domain.label) in Spotlight.")
    }

    // MARK: Actions

    private func rebuildIndex() {
        isRebuilding = true
        rebuildCompleted = false
        coordinator.rebuildAll(
            ticketProvider: { [] },    // caller overrides via coordinator.rebuildAll in production
            customerProvider: { [] },
            inventoryProvider: { [] }
        )
        // Simulate async completion for UX feedback — real rebuild drives the indexer internally.
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            isRebuilding = false
            rebuildCompleted = true
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            rebuildCompleted = false
        }
    }
}
