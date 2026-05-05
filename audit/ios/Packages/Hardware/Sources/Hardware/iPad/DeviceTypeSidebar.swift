#if canImport(SwiftUI)
import SwiftUI

// MARK: - HardwareDeviceType
//
// Semantic device categories shown in the iPad sidebar column.
// Matches the 5 hardware subsystems: Printers, Drawer, Scale, Scanner, Terminal.

public enum HardwareDeviceType: String, CaseIterable, Identifiable, Hashable, Sendable {
    case printer  = "printer"
    case drawer   = "drawer"
    case scale    = "scale"
    case scanner  = "scanner"
    case terminal = "terminal"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .printer:  return "Printers"
        case .drawer:   return "Cash Drawer"
        case .scale:    return "Weight Scales"
        case .scanner:  return "Barcode Scanners"
        case .terminal: return "Payment Terminal"
        }
    }

    public var systemImage: String {
        switch self {
        case .printer:  return "printer.fill"
        case .drawer:   return "tray.full.fill"
        case .scale:    return "scalemass.fill"
        case .scanner:  return "barcode.viewfinder"
        case .terminal: return "creditcard.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .printer:  return .blue
        case .drawer:   return .orange
        case .scale:    return .green
        case .scanner:  return .purple
        case .terminal: return .pink
        }
    }

    public var accessibilityLabel: String { "\(title), hardware category" }

    public var accessibilityHint: String {
        switch self {
        case .printer:  return "Show configured printers and test actions"
        case .drawer:   return "Show cash drawer status and open test"
        case .scale:    return "Show paired weight scales and live readings"
        case .scanner:  return "Show paired barcode scanners"
        case .terminal: return "Show payment terminal pairing and ping"
        }
    }
}

// MARK: - DeviceTypeSidebar

/// iPad sidebar column: lists all 5 hardware device type categories.
///
/// Placement: leading column of `HardwareThreeColumnView`.
/// Liquid Glass applied to navigation chrome only.
/// Full a11y: every row has label + hint.
public struct DeviceTypeSidebar: View {

    @Binding var selection: HardwareDeviceType?

    public init(selection: Binding<HardwareDeviceType?>) {
        _selection = selection
    }

    public var body: some View {
        List(HardwareDeviceType.allCases, selection: $selection) { type in
            DeviceTypeSidebarRow(type: type, isSelected: selection == type)
                .tag(type)
                .accessibilityLabel(type.accessibilityLabel)
                .accessibilityHint(type.accessibilityHint)
                .accessibilityAddTraits(selection == type ? .isSelected : [])
        }
        .listStyle(.sidebar)
        .navigationTitle("Hardware")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
    }
}

// MARK: - DeviceTypeSidebarRow

private struct DeviceTypeSidebarRow: View {
    let type: HardwareDeviceType
    let isSelected: Bool

    var body: some View {
        Label {
            Text(type.title)
                .font(.body)
                .fontWeight(isSelected ? .semibold : .regular)
        } icon: {
            Image(systemName: type.systemImage)
                .foregroundStyle(type.accentColor)
                .frame(width: 28)
        }
        .padding(.vertical, 2)
        .hoverEffect(.highlight)
    }
}

#endif
