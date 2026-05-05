import SwiftUI
import Core
import DesignSystem

/// §22 — iPad column-1 entity-kind filter sidebar.
///
/// Displays a vertical list of entity kind buttons (All / Tickets / Customers /
/// Invoices / Inventory / Settings + any remaining known kinds). Tapping a row
/// writes the raw `entityKind` string (or `nil` for "All") back via the binding.
///
/// Liquid Glass chrome on the section header; plain list rows below — following
/// the CLAUDE.md rule: glass on chrome, not on content rows.
public struct AuditEntityFilterSidebar: View {

    /// The currently-selected entity kind (`nil` = All).
    @Binding public var selectedEntityKind: String?

    public init(selectedEntityKind: Binding<String?>) {
        _selectedEntityKind = selectedEntityKind
    }

    // MARK: - Supported entity kinds

    public static let entityKinds: [AuditEntityKind] = [
        .all,
        .init(id: "ticket",    label: "Tickets",   systemImage: "ticket"),
        .init(id: "customer",  label: "Customers",  systemImage: "person.2"),
        .init(id: "invoice",   label: "Invoices",   systemImage: "doc.text"),
        .init(id: "inventory", label: "Inventory",  systemImage: "shippingbox"),
        .init(id: "settings",  label: "Settings",   systemImage: "gearshape"),
        .init(id: "employee",  label: "Employees",  systemImage: "person.badge.key"),
        .init(id: "role",      label: "Roles",      systemImage: "shield"),
        .init(id: "user",      label: "Users",      systemImage: "person.circle"),
    ]

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                sectionHeader
                    .padding(.horizontal, DesignTokens.Spacing.md)
                    .padding(.vertical, DesignTokens.Spacing.sm)

                Divider()
                    .padding(.horizontal, DesignTokens.Spacing.md)

                LazyVStack(spacing: 0) {
                    ForEach(Self.entityKinds) { kind in
                        EntityKindRow(
                            kind: kind,
                            isSelected: kind.id == selectedEntityKind
                                || (kind.id == nil && selectedEntityKind == nil)
                        ) {
                            selectedEntityKind = kind.id
                        }
                    }
                }
                .padding(.vertical, DesignTokens.Spacing.xs)
            }
        }
        .background(Color.bizarreSurface1)
        .accessibilityLabel("Entity kind filter sidebar")
    }

    // MARK: - Section header with Liquid Glass

    private var sectionHeader: some View {
        HStack {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Filter by Entity")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)
            Spacer()
            if selectedEntityKind != nil {
                Button("Clear") { selectedEntityKind = nil }
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityLabel("Clear entity filter")
                    .buttonStyle(.plain)
            }
        }
        .padding(DesignTokens.Spacing.sm)
        .brandGlass(.clear, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
    }
}

// MARK: - AuditEntityKind

/// One entry in the sidebar list.
public struct AuditEntityKind: Identifiable, Sendable {
    /// Nil means "All entities".
    public let id: String?
    public let label: String
    public let systemImage: String

    public init(id: String?, label: String, systemImage: String) {
        self.id = id
        self.label = label
        self.systemImage = systemImage
    }

    /// "All" sentinel.
    public static let all = AuditEntityKind(id: nil, label: "All", systemImage: "tray.full")
}

// MARK: - EntityKindRow

private struct EntityKindRow: View {
    let kind: AuditEntityKind
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isSelected ? .bizarreOrange : .bizarreOnSurfaceMuted)
                    .frame(width: 24)
                    .accessibilityHidden(true)

                Text(kind.label)
                    .font(isSelected ? .brandBodyLarge() : .brandBodyMedium())
                    .foregroundStyle(isSelected ? .bizarreOnSurface : .bizarreOnSurfaceMuted)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.bizarreOrange)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.vertical, DesignTokens.Spacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            isSelected
                ? Color.bizarreOrangeContainer.opacity(0.15)
                : Color.clear
        )
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
        .accessibilityLabel("\(kind.label)\(isSelected ? ", selected" : "")")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("sidebar.entitykind.\(kind.id ?? "all")")
    }
}
