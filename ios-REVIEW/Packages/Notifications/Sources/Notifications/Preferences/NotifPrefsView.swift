import SwiftUI
import Core
import DesignSystem

// MARK: - NotifPrefsView

/// Per-channel notification preferences screen.
///
/// Layout:
/// - iPhone: vertical `Form`, grouped by category, toggle rows per channel.
/// - iPad: `NavigationSplitView` sidebar (categories) + detail (event toggles).
///
/// Each event row shows Push / In-App / Email / SMS toggles.
/// Tapping the clock icon opens quiet-hours editor for that event.
public struct NotifPrefsView: View {

    @State private var vm: NotifPrefsViewModel
    @State private var selectedCategory: EventCategory?
    @Environment(\.horizontalSizeClass) private var hSizeClass

    public init(repository: any NotifPrefsRepository) {
        _vm = State(wrappedValue: NotifPrefsViewModel(repository: repository))
    }

    public var body: some View {
        Group {
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .task { await vm.load() }
        .overlay(alignment: .top) { savingOverlay }
        .alert("SMS Cost Warning", isPresented: $vm.showSMSCostWarning) {
            Button("Enable SMS", role: .destructive) { Task { await vm.confirmSMSToggle() } }
            Button("Cancel", role: .cancel) { vm.cancelSMSToggle() }
        } message: {
            Text("This event fires frequently. Enabling SMS may generate 50+ texts per day and charges may apply.")
        }
        .sheet(item: $vm.editingQuietHoursEvent) { event in
            quietHoursSheet(for: event)
        }
    }

    // MARK: - iPhone layout

    private var iPhoneLayout: some View {
        NavigationStack {
            if vm.isLoading && vm.preferences.isEmpty {
                ProgressView("Loading preferences…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Notifications")
            } else if let err = vm.errorMessage, vm.preferences.isEmpty {
                errorPane(err)
                    .navigationTitle("Notifications")
            } else {
                Form {
                    ForEach(vm.categories) { category in
                        let prefs = vm.preferences(for: category)
                        if !prefs.isEmpty {
                            categorySection(category: category, prefs: prefs)
                        }
                    }
                    resetSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .navigationTitle("Notifications")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        if vm.isSaving { ProgressView().controlSize(.small) }
                    }
                }
            }
        }
    }

    // MARK: - iPad layout

    private var iPadLayout: some View {
        NavigationSplitView {
            List(vm.categories, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: categoryIcon(category))
                    .tag(category)
                    .font(.brandBodyLarge())
                    .hoverEffect(.highlight)
                    .accessibilityLabel(category.rawValue)
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .navigationTitle("Categories")
        } detail: {
            if let category = selectedCategory {
                categoryDetailView(category: category)
            } else {
                categoryDetailView(category: .tickets)
            }
        }
    }

    private func categoryDetailView(category: EventCategory) -> some View {
        let prefs = vm.preferences(for: category)
        return Group {
            if vm.isLoading && prefs.isEmpty {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Form {
                    categorySection(category: category, prefs: prefs)
                    resetSection
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle(category.rawValue)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if vm.isSaving { ProgressView().controlSize(.small) }
            }
        }
    }

    // MARK: - Category section

    @ViewBuilder
    private func categorySection(
        category: EventCategory,
        prefs: [NotificationPreference]
    ) -> some View {
        Section {
            ForEach(prefs) { pref in
                eventRow(pref: pref)
            }
        } header: {
            Label(category.rawValue, systemImage: categoryIcon(category))
                .font(.brandLabelLarge())
                .accessibilityAddTraits(.isHeader)
        }
    }

    // MARK: - Event row

    @ViewBuilder
    private func eventRow(pref: NotificationPreference) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text(pref.event.displayName)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                    .lineLimit(2)

                Spacer()

                if pref.event.isCritical {
                    Text("Critical")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreWarning)
                        .padding(.horizontal, BrandSpacing.xs)
                        .padding(.vertical, 2)
                        .background(Color.bizarreWarning.opacity(0.12), in: Capsule())
                }

                // Quiet hours clock button
                Button {
                    vm.editingQuietHoursEvent = pref.event
                } label: {
                    Image(systemName: pref.quietHours != nil ? "clock.fill" : "clock")
                        .foregroundStyle(pref.quietHours != nil ? .bizarreOrange : .bizarreOnSurfaceMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(pref.quietHours != nil
                    ? "Quiet hours set for \(pref.event.displayName)"
                    : "Set quiet hours for \(pref.event.displayName)")
                .accessibilityIdentifier("notifPrefs.quietHours.\(pref.event.rawValue)")
            }

            // Channel toggles row
            HStack(spacing: BrandSpacing.sm) {
                ForEach(NotificationChannel.allCases) { channel in
                    channelToggle(pref: pref, channel: channel)
                }
                Spacer()
            }
        }
        .listRowBackground(Color.bizarreSurface1)
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Preferences for \(pref.event.displayName)")
    }

    // MARK: - Channel toggle

    @ViewBuilder
    private func channelToggle(pref: NotificationPreference, channel: NotificationChannel) -> some View {
        let isOn = channelEnabled(pref, channel: channel)
        VStack(spacing: 2) {
            Button {
                Task { await vm.toggle(event: pref.event, channel: channel) }
            } label: {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isOn ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 36)
            }
            .buttonStyle(.plain)

            Text(channelLabel(channel))
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .accessibilityLabel("\(channel.rawValue) for \(pref.event.displayName): \(isOn ? "on" : "off")")
        .accessibilityHint("Double-tap to \(isOn ? "disable" : "enable")")
        .accessibilityIdentifier("notifPrefs.\(pref.event.rawValue).\(channel.rawValue)")
    }

    // MARK: - Reset section

    @ViewBuilder
    private var resetSection: some View {
        Section {
            Button("Reset all to default") {
                Task { await vm.resetAllToDefault() }
            }
            .foregroundStyle(.bizarreError)
            .accessibilityLabel("Reset all notification preferences to defaults")
            .accessibilityIdentifier("notifPrefs.resetAll")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    // MARK: - Quiet hours sheet

    private func quietHoursSheet(for event: NotificationEvent) -> some View {
        let existingQH = vm.preferences.first(where: { $0.event == event })?.quietHours
        return NavigationStack {
            QuietHoursEditorView(
                quietHours: Binding(
                    get: { vm.preferences.first(where: { $0.event == event })?.quietHours },
                    set: { _ in }   // Save via onSave callback
                ),
                onSave: { qh in
                    Task { await vm.saveQuietHours(qh, for: event) }
                }
            )
            .navigationTitle("Quiet Hours: \(event.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { vm.editingQuietHoursEvent = nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Saving overlay

    @ViewBuilder
    private var savingOverlay: some View {
        if vm.isSaving {
            HStack(spacing: BrandSpacing.sm) {
                ProgressView().controlSize(.small)
                Text("Saving…")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            .padding(BrandSpacing.md)
            .brandGlass(.regular, in: Capsule())
            .padding(.top, BrandSpacing.sm)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: - Error pane

    private func errorPane(_ err: String) -> some View {
        VStack(spacing: BrandSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Couldn't load preferences")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text(err)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button("Try again") { Task { await vm.load() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func channelEnabled(_ pref: NotificationPreference, channel: NotificationChannel) -> Bool {
        switch channel {
        case .push:   return pref.pushEnabled
        case .inApp:  return pref.inAppEnabled
        case .email:  return pref.emailEnabled
        case .sms:    return pref.smsEnabled
        }
    }

    private func channelLabel(_ channel: NotificationChannel) -> String {
        switch channel {
        case .push:   return "Push"
        case .inApp:  return "In-App"
        case .email:  return "Email"
        case .sms:    return "SMS"
        }
    }

    private func categoryIcon(_ category: EventCategory) -> String {
        switch category {
        case .tickets:        return "wrench.and.screwdriver"
        case .communications: return "message"
        case .customers:      return "person"
        case .billing:        return "doc.text"
        case .appointments:   return "calendar"
        case .inventory:      return "shippingbox"
        case .pos:            return "creditcard"
        case .staff:          return "person.2"
        case .marketing:      return "megaphone"
        case .admin:          return "gear"
        }
    }
}

// MARK: - EventCategory: Identifiable

extension EventCategory: Identifiable {
    public var id: String { rawValue }
}

// MARK: - NotificationChannel: Identifiable (re-export in case downstream needs it)

extension NotificationChannel {
    /// Short label for channel toggle buttons.
    public var shortLabel: String {
        switch self {
        case .push:   return "Push"
        case .inApp:  return "In-App"
        case .email:  return "Email"
        case .sms:    return "SMS"
        }
    }
}

// MARK: - NotificationEvent: Identifiable (sheet binding)

extension NotificationEvent {
    // Already Identifiable via `var id: String` — this allows using it as
    // an `Identifiable?` in `.sheet(item:)` without ceremony.
}
