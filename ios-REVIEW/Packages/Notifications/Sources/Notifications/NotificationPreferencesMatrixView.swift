import SwiftUI
import Core
import DesignSystem
import Observation

// MARK: - NotificationPreferencesMatrixViewModel

@MainActor
@Observable
public final class NotificationPreferencesMatrixViewModel {

    // MARK: - State

    public private(set) var preferences: [NotificationPreference] = []
    public private(set) var isLoading: Bool = false
    public private(set) var errorMessage: String?
    public private(set) var isSaving: Bool = false
    /// If true the user tried to enable SMS on a self-to-high-volume event.
    public var showSMSCostWarning: Bool = false
    public private(set) var pendingSMSToggle: NotificationPreference?

    // MARK: - Dependencies

    private let repository: any NotificationPreferencesRepository

    // MARK: - Init

    public init(repository: any NotificationPreferencesRepository) {
        self.repository = repository
    }

    // MARK: - Public API

    public func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            preferences = try await repository.fetchAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggle(event: NotificationEvent, channel: NotificationChannel) async {
        guard let idx = preferences.firstIndex(where: { $0.event == event }) else { return }
        let current = preferences[idx]
        let updated = current.toggling(channel)

        // Guard: warn if enabling SMS on a high-volume event
        if channel == .sms && updated.smsEnabled && event.isHighVolumeForSMS {
            pendingSMSToggle = updated
            showSMSCostWarning = true
            return
        }

        applyOptimistically(updated, at: idx)
        await persist(updated)
    }

    /// Called when user confirms the SMS cost warning.
    public func confirmSMSToggle() async {
        guard let pending = pendingSMSToggle,
              let idx = preferences.firstIndex(where: { $0.event == pending.event }) else {
            showSMSCostWarning = false
            return
        }
        showSMSCostWarning = false
        pendingSMSToggle = nil
        applyOptimistically(pending, at: idx)
        await persist(pending)
    }

    /// Called when user cancels the SMS cost warning.
    public func cancelSMSToggle() {
        showSMSCostWarning = false
        pendingSMSToggle = nil
    }

    public func resetAllToDefault() async {
        isLoading = true
        defer { isLoading = false }
        let defaults = NotificationEvent.allCases.map { NotificationPreference.defaultPreference(for: $0) }
        preferences = defaults
        for pref in defaults {
            _ = try? await repository.update(pref)
        }
    }

    // MARK: - Helpers

    private func applyOptimistically(_ updated: NotificationPreference, at idx: Int) {
        var copy = preferences
        copy[idx] = updated
        preferences = copy
    }

    private func persist(_ preference: NotificationPreference) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let saved = try await repository.update(preference)
            if let idx = preferences.firstIndex(where: { $0.event == saved.event }) {
                applyOptimistically(saved, at: idx)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - NotificationPreferencesMatrixView

/// Per-event × per-channel (Push / In-App / Email / SMS) toggle grid.
/// iPhone: vertical. iPad: side-by-side category sidebar + detail grid.
public struct NotificationPreferencesMatrixView: View {

    @State private var vm: NotificationPreferencesMatrixViewModel
    @State private var selectedCategory: EventCategory?
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(repository: any NotificationPreferencesRepository) {
        _vm = State(wrappedValue: NotificationPreferencesMatrixViewModel(repository: repository))
    }

    // MARK: - Body

    public var body: some View {
        Group {
            #if os(iOS)
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
            #else
            iPadLayout
            #endif
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle("Notification Matrix")
        .task { await vm.load() }
        .alert("SMS Cost Warning", isPresented: $vm.showSMSCostWarning) {
            Button("Enable SMS", role: .destructive) { Task { await vm.confirmSMSToggle() } }
            Button("Cancel", role: .cancel) { vm.cancelSMSToggle() }
        } message: {
            Text("This event fires frequently. Enabling SMS may generate 50+ texts per day and charges may apply.")
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        matrixContent(events: displayedEvents)
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(EventCategory.allCases, id: \.self, selection: $selectedCategory) { cat in
                Text(cat.rawValue)
                    .font(.brandBodyLarge())
                    .accessibilityLabel(cat.rawValue)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationTitle("Categories")
        } detail: {
            matrixContent(events: displayedEvents)
        }
    }

    // MARK: - Matrix content

    @ViewBuilder
    private func matrixContent(events: [NotificationPreference]) -> some View {
        if vm.isLoading && events.isEmpty {
            ProgressView("Loading preferences…")
                .accessibilityLabel("Loading notification preferences")
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(events) { pref in
                        eventRow(pref: pref)
                    }
                    resetButton
                        .padding(BrandSpacing.base)
                }
                .padding(.horizontal, BrandSpacing.base)
            }
            .background(Color.bizarreSurfaceBase)
            .overlay(alignment: .top) {
                if vm.isSaving {
                    ProgressView()
                        .padding(BrandSpacing.sm)
                        .brandGlass(.regular, in: Capsule())
                        .padding(.top, BrandSpacing.sm)
                }
            }
        }
    }

    // MARK: - Header row

    private var headerRow: some View {
        HStack(spacing: 0) {
            Text("Event")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            ForEach(NotificationChannel.allCases) { channel in
                Text(channel.rawValue)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 56, alignment: .center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityLabel("Column: \(channel.rawValue)")
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface2)
        .cornerRadius(8)
        .padding(.bottom, BrandSpacing.xs)
    }

    // MARK: - Event row

    @ViewBuilder
    private func eventRow(pref: NotificationPreference) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(pref.event.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)
                if pref.event.isCritical {
                    Text("Critical")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(pref.event.displayName)

            ForEach(NotificationChannel.allCases) { channel in
                channelToggle(pref: pref, channel: channel)
                    .frame(width: 56, alignment: .center)
            }
        }
        .padding(.vertical, BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 8))
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Row: \(pref.event.displayName)")
    }

    // MARK: - Channel toggle

    @ViewBuilder
    private func channelToggle(pref: NotificationPreference, channel: NotificationChannel) -> some View {
        let isOn = isChannelEnabled(pref: pref, channel: channel)
        Button {
            Task { await vm.toggle(event: pref.event, channel: channel) }
        } label: {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isOn ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                .font(.title3)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(channel.rawValue) for \(pref.event.displayName): \(isOn ? "on" : "off")")
        .accessibilityHint("Double-tap to \(isOn ? "disable" : "enable")")
        .accessibilityIdentifier("matrix.\(pref.event.rawValue).\(channel.rawValue)")
    }

    // MARK: - Reset button

    @ViewBuilder
    private var resetButton: some View {
        Button("Reset all to default") {
            Task { await vm.resetAllToDefault() }
        }
        .font(.brandLabelLarge())
        .foregroundStyle(.bizarreOrange)
        .accessibilityLabel("Reset all notification preferences to default")
        .padding(.top, BrandSpacing.sm)
    }

    // MARK: - Helpers

    private var displayedEvents: [NotificationPreference] {
        guard let cat = selectedCategory else { return vm.preferences }
        return vm.preferences.filter { $0.event.category == cat }
    }

    private func isChannelEnabled(pref: NotificationPreference, channel: NotificationChannel) -> Bool {
        switch channel {
        case .push:   return pref.pushEnabled
        case .inApp:  return pref.inAppEnabled
        case .email:  return pref.emailEnabled
        case .sms:    return pref.smsEnabled
        }
    }
}
