import SwiftUI

#if os(iOS)

/// Admin settings panel for widget behaviour.
///
/// Writes to the shared App Group UserDefaults via `WidgetDataStore`.
/// Intended to be embedded in `Settings → Appearance → Widgets`.
///
/// - Note: Requires the App Group entitlement `group.com.bizarrecrm` in both
///   the main app target and the widget extension target.
@available(iOS 17.0, *)
@MainActor
public struct WidgetSettingsView: View {

    // MARK: - State

    @State private var refreshIntervalRaw: Int
    @State private var liveActivitiesEnabled: Bool
    @State private var saveError: String?

    private let store: WidgetDataStore

    // MARK: - Init

    public init(store: WidgetDataStore) {
        self.store = store
        // We read initial values synchronously — actor isolation means
        // we can't await here, so we seed sensible defaults and then
        // fetch real values in .task.
        _refreshIntervalRaw = State(initialValue: WidgetDataStore.RefreshInterval.fifteenMinutes.rawValue)
        _liveActivitiesEnabled = State(initialValue: true)
    }

    // MARK: - Body

    public var body: some View {
        List {
            Section {
                Picker(
                    "Widget refresh interval",
                    selection: $refreshIntervalRaw
                ) {
                    ForEach(WidgetDataStore.RefreshInterval.allCases, id: \.rawValue) { interval in
                        Text(intervalLabel(interval))
                            .tag(interval.rawValue)
                    }
                }
                .accessibilityLabel("Widget refresh interval")
                .onChange(of: refreshIntervalRaw) { _, newValue in
                    persistRefreshInterval(newValue)
                }
            } header: {
                Text("Widgets")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Controls how often Home Screen widgets request fresh data from the app.")
            }

            Section {
                Toggle(isOn: $liveActivitiesEnabled) {
                    Label("Enable Live Activities", systemImage: "timer")
                        .accessibilityLabel("Enable Live Activities")
                }
                .onChange(of: liveActivitiesEnabled) { _, newValue in
                    persistLiveActivities(newValue)
                }
            } header: {
                Text("Live Activities")
                    .accessibilityAddTraits(.isHeader)
            } footer: {
                Text("Show clock-in shift timer and POS sale progress in the Dynamic Island and on the Lock Screen.")
            }

            if let error = saveError {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Widget settings error: \(error)")
                }
            }
        }
        .navigationTitle("Widget Settings")
        .task {
            await loadCurrentValues()
        }
    }

    // MARK: - Helpers

    private func intervalLabel(_ interval: WidgetDataStore.RefreshInterval) -> String {
        switch interval {
        case .fiveMinutes:    return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes:  return "30 minutes"
        }
    }

    private func loadCurrentValues() async {
        let interval = await store.refreshInterval
        let enabled = await store.liveActivitiesEnabled
        refreshIntervalRaw = interval.rawValue
        liveActivitiesEnabled = enabled
    }

    private func persistRefreshInterval(_ rawValue: Int) {
        guard let interval = WidgetDataStore.RefreshInterval(rawValue: rawValue) else { return }
        Task {
            await store.set(refreshInterval: interval)
        }
    }

    private func persistLiveActivities(_ enabled: Bool) {
        Task {
            await store.set(liveActivitiesEnabled: enabled)
        }
    }
}

#endif // os(iOS)
