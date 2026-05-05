import SwiftUI
import DesignSystem

// MARK: - §13.1 Notification tabs + filter chips

// MARK: - Tab model

public enum NotificationTab: String, CaseIterable, Identifiable, Sendable {
    case all        = "all"
    case unread     = "unread"
    case assignedMe = "assigned_me"
    case mentions   = "mentions"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .all:        return "All"
        case .unread:     return "Unread"
        case .assignedMe: return "Assigned to me"
        case .mentions:   return "Mentions"
        }
    }
}

// MARK: - Type filter chip model

public enum NotificationTypeFilter: String, CaseIterable, Identifiable, Sendable {
    case ticket      = "ticket"
    case sms         = "sms"
    case invoice     = "invoice"
    case payment     = "payment"
    case appointment = "appointment"
    case mention     = "mention"
    case system      = "system"

    public var id: String { rawValue }
    public var label: String {
        switch self {
        case .ticket:      return "Ticket"
        case .sms:         return "SMS"
        case .invoice:     return "Invoice"
        case .payment:     return "Payment"
        case .appointment: return "Appointment"
        case .mention:     return "Mention"
        case .system:      return "System"
        }
    }
    public var icon: String {
        switch self {
        case .ticket:      return "wrench.and.screwdriver"
        case .sms:         return "message"
        case .invoice:     return "doc.text"
        case .payment:     return "creditcard"
        case .appointment: return "calendar"
        case .mention:     return "at"
        case .system:      return "gear"
        }
    }
}

// MARK: - Tab bar (All / Unread / Assigned to me / Mentions)

public struct NotificationTabBar: View {
    @Binding var selectedTab: NotificationTab

    public init(selectedTab: Binding<NotificationTab>) {
        _selectedTab = selectedTab
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.sm) {
                ForEach(NotificationTab.allCases) { tab in
                    TabChip(
                        label: tab.label,
                        isSelected: selectedTab == tab
                    ) {
                        selectedTab = tab
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification filter tabs")
    }
}

// MARK: - Type filter chip row

public struct NotificationTypeFilterBar: View {
    @Binding var selectedTypes: Set<NotificationTypeFilter>

    public init(selectedTypes: Binding<Set<NotificationTypeFilter>>) {
        _selectedTypes = selectedTypes
    }

    public var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: BrandSpacing.xs) {
                ForEach(NotificationTypeFilter.allCases) { type in
                    let selected = selectedTypes.contains(type)
                    TypeFilterChip(type: type, isSelected: selected) {
                        if selected {
                            selectedTypes.remove(type)
                        } else {
                            selectedTypes.insert(type)
                        }
                    }
                }
            }
            .padding(.horizontal, BrandSpacing.base)
            .padding(.vertical, BrandSpacing.xs)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Notification type filters")
    }
}

// MARK: - Chip components

private struct TabChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.brandLabelLarge())
                .padding(.horizontal, BrandSpacing.md)
                .padding(.vertical, BrandSpacing.xs)
                .foregroundStyle(isSelected ? .white : .bizarreOnSurfaceMuted)
                .background(isSelected ? Color.bizarreOrange : Color.bizarreSurface2, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(label)\(isSelected ? ", selected" : "")")
    }
}

private struct TypeFilterChip: View {
    let type: NotificationTypeFilter
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(type.label, systemImage: type.icon)
                .labelStyle(.titleAndIcon)
                .font(.brandLabelSmall())
                .padding(.horizontal, BrandSpacing.sm)
                .padding(.vertical, 5)
                .foregroundStyle(isSelected ? Color.bizarreOrange : .bizarreOnSurfaceMuted)
                .background(
                    isSelected ? Color.bizarreOrange.opacity(0.12) : Color.bizarreSurface2,
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.bizarreOrange.opacity(0.5) : Color.clear,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityLabel("\(type.label) filter\(isSelected ? ", active" : "")")
    }
}
