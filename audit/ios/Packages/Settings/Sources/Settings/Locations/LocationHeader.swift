import SwiftUI
import Core
import DesignSystem

// MARK: - §60.1 LocationHeader — `.locationScoped()` modifier

/// Attach to any screen to:
/// 1. Add a `LocationSwitcherChip` to the toolbar.
/// 2. Re-run `onLocationChange` whenever `.locationDidSwitch` fires.
///
/// Usage:
/// ```swift
/// MyListView()
///     .locationScoped(locations: locations) {
///         Task { await viewModel.reload() }
///     }
/// ```
///
/// Wiring snippet for `RootView.swift` (DO NOT edit RootView directly — paste snippet):
/// ```swift
/// // In your tab view / NavigationSplitView detail:
/// SomeFeatureView()
///     .locationScoped(locations: locationRepo.cachedLocations) {
///         // domain repo re-fetch
///     }
/// ```
public struct LocationScopedModifier: ViewModifier {
    @State private var context: LocationContext = .shared
    @State private var locations: [Location]
    private let onLocationChange: () -> Void

    public init(locations: [Location], onLocationChange: @escaping () -> Void) {
        _locations = State(initialValue: locations)
        self.onLocationChange = onLocationChange
    }

    public func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(placement: Platform.isCompact ? .principal : .primaryAction) {
                    LocationSwitcherChip(context: context, locations: locations)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: LocationContext.locationDidSwitch)) { _ in
                onLocationChange()
            }
    }
}

public extension View {
    /// Pins a `LocationSwitcherChip` to the toolbar and re-invokes `onLocationChange`
    /// whenever the user switches location.
    func locationScoped(locations: [Location], onLocationChange: @escaping () -> Void = {}) -> some View {
        modifier(LocationScopedModifier(locations: locations, onLocationChange: onLocationChange))
    }
}
