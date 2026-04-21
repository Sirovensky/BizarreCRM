import SwiftUI
import Core
import DesignSystem

// MARK: - §60.1 LocationQuickPickerSheet

/// Compact list of active locations. Selecting one calls
/// `LocationContext.shared.switch(locationId:)` which posts `.locationDidSwitch`.
public struct LocationQuickPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var context: LocationContext

    let locations: [Location]

    public init(context: LocationContext = .shared, locations: [Location]) {
        _context = State(wrappedValue: context)
        self.locations = locations
    }

    public var body: some View {
        NavigationStack {
            List {
                ForEach(activeLocations) { loc in
                    Button {
                        context.switch(locationId: loc.id)
                        dismiss()
                    } label: {
                        HStack(spacing: DesignTokens.Spacing.md) {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(loc.isPrimary ? .bizarreOrange : .bizarreTeal)
                                .font(.title3)
                                .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: DesignTokens.Spacing.xxs) {
                                Text(loc.name)
                                    .font(.headline)
                                    .foregroundStyle(.bizarreOnSurface)
                                Text("\(loc.city), \(loc.region)")
                                    .font(.subheadline)
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }

                            Spacer()

                            if loc.id == context.activeLocationId {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityLabel("Currently selected")
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(loc.name), \(loc.city)")
                    .accessibilityAddTraits(loc.id == context.activeLocationId ? .isSelected : [])
                }
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationTitle("Switch Location")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
            }
        }
    }

    private var activeLocations: [Location] {
        locations.filter(\.active)
    }
}
