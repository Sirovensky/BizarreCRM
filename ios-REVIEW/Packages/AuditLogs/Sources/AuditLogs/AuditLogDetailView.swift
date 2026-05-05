import SwiftUI
import Core
import DesignSystem

/// Detail view for a single audit log entry — actor info, event/entity info,
/// and expandable scrubbed metadata panel.
/// §50.6, §50.1 (tap row).
public struct AuditLogDetailView: View {

    private let entry: AuditLogEntry
    /// Optional closure called when the user wants to navigate to the affected entity.
    /// Called with (entityType, entityId) when the user taps "View entity".
    private let navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)?

    @State private var isDiffExpanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        entry: AuditLogEntry,
        navigateToEntity: ((_ entityType: String, _ entityId: String) -> Void)? = nil
    ) {
        self.entry = entry
        self.navigateToEntity = navigateToEntity
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                actorSection
                eventSection
                metadataSection
                if navigateToEntity != nil, entry.entityId != nil {
                    entityNavigationButton
                }
            }
            .padding(DesignTokens.Spacing.lg)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Audit Entry")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: Actor

    private var actorSection: some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            ActorAvatar(name: entry.actorName, diameter: 48)
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                Text(entry.actorName)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .textSelection(.enabled)
                if let uid = entry.actorUserId {
                    Text("ID \(uid)")
                        .font(.brandMono(size: 11))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .textSelection(.enabled)
                }
            }
            Spacer()
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Actor: \(entry.actorName)")
    }

    // MARK: Event

    private var eventSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            sectionHeader("Event")
            Grid(alignment: .leading, horizontalSpacing: DesignTokens.Spacing.lg, verticalSpacing: DesignTokens.Spacing.sm) {
                GridRow {
                    Text("Action").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(entry.action).font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface).textSelection(.enabled)
                }
                GridRow {
                    Text("Entity").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    let entityLabel = entry.entityId.map { "\(entry.entityKind) #\($0)" } ?? entry.entityKind
                    Text(entityLabel).font(.brandMono(size: 13)).foregroundStyle(.bizarreOnSurface).textSelection(.enabled)
                }
                GridRow {
                    Text("When").font(.brandLabelLarge()).foregroundStyle(.bizarreOnSurfaceMuted)
                    Text(entry.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
                        .font(.brandBodyMedium()).foregroundStyle(.bizarreOnSurface)
                }
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: Metadata (scrubbed; server enforces SCAN-506 PII allowlist)

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: DesignTokens.Motion.quick)) {
                    isDiffExpanded.toggle()
                }
            } label: {
                HStack {
                    sectionHeader("Details")
                    Spacer()
                    Image(systemName: isDiffExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isDiffExpanded ? "Collapse details" : "Expand details")

            if isDiffExpanded {
                metadataContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    @ViewBuilder
    private var metadataContent: some View {
        if let meta = entry.metadata, !meta.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(meta.keys.sorted(), id: \.self) { key in
                    MetadataRow(key: key, value: meta[key]?.displayString ?? "")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        } else {
            Text("No additional details")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: Entity navigation

    private var entityNavigationButton: some View {
        Button {
            guard let eid = entry.entityId else { return }
            navigateToEntity?(entry.entityKind, String(eid))
        } label: {
            Label("View \(entry.entityKind.capitalized)", systemImage: "arrow.right.circle")
                .font(.brandBodyMedium())
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .accessibilityIdentifier("auditlog.navigate.entity")
    }

    // MARK: Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.brandTitleSmall())
            .foregroundStyle(.bizarreOnSurface)
    }
}

// MARK: - MetadataRow

private struct MetadataRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.xs) {
            Text("\(key):")
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(minWidth: 60, alignment: .leading)
            Text(value)
                .font(.brandMono(size: 12))
                .foregroundStyle(.bizarreOnSurface)
                .textSelection(.enabled)
                .lineLimit(4)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xxs)
        .accessibilityLabel("\(key): \(value)")
    }
}

// MARK: - ActorAvatar (§50.6 initials + color hash)

/// Initials circle with a colour derived from the actor name hash.
/// No real image — placeholder as specified in §50.6.
public struct ActorAvatar: View {
    public let name: String
    public let diameter: CGFloat

    public init(name: String, diameter: CGFloat = 40) {
        self.name = name
        self.diameter = diameter
    }

    public var body: some View {
        ZStack {
            Circle()
                .fill(avatarColor)
            Text(initials)
                .font(.system(size: diameter * 0.36, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityHidden(true)
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.compactMap { $0.first }.map(String.init).joined().uppercased()
    }

    private var avatarColor: Color {
        // Stable hash → hue so the same actor always gets the same colour.
        let hash = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        let hue = Double(abs(hash) % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.75)
    }
}
