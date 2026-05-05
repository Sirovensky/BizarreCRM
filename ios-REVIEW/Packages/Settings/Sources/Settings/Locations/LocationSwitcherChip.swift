import SwiftUI
import Core
import DesignSystem

// MARK: - §60.1 LocationSwitcherChip

/// A Liquid Glass chip that displays the active location and opens
/// `LocationQuickPickerSheet` on tap.
///
/// iPad: pinned in the toolbar header.
/// iPhone: displayed inside the tab bar via `.locationScoped()` modifier.
public struct LocationSwitcherChip: View {
    @State private var context: LocationContext
    @State private var showPicker: Bool = false

    private let locations: [Location]

    public init(context: LocationContext = .shared, locations: [Location]) {
        _context = State(wrappedValue: context)
        self.locations = locations
    }

    public var body: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .accessibilityHidden(true)
                Text(activeLocationName)
                    .font(.brandLabelLarge())
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
            .padding(.vertical, DesignTokens.Spacing.xs)
        }
        .brandGlass(.regular, tint: .bizarreOrange, interactive: true)
        .accessibilityLabel("Active location: \(activeLocationName)")
        .accessibilityHint("Double-tap to switch location")
        .accessibilityAddTraits(.isButton)
        .sheet(isPresented: $showPicker) {
            LocationQuickPickerSheet(
                context: context,
                locations: locations
            )
            .presentationDetents([.fraction(0.45), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    private var activeLocationName: String {
        locations.first(where: { $0.id == context.activeLocationId })?.name ?? "All Locations"
    }
}
