#if canImport(UIKit)
import SwiftUI
import DesignSystem
import Core
import Networking

// §5 — Per-customer communication preferences:
//   preferred channel (SMS / email / push / none)
//   times-of-day preference
//   granular opt-out: marketing vs transactional
//   preferred language for comms
//   system blocks sends against preference; staff override with reason + audit

// MARK: - Models

/// Preferred communication channel per §5.
public enum CustomerPreferredChannel: String, CaseIterable, Codable, Sendable {
    case sms    = "sms"
    case email  = "email"
    case push   = "push"
    case none   = "none"

    public var displayName: String {
        switch self {
        case .sms:   return "SMS"
        case .email: return "Email"
        case .push:  return "Push notification"
        case .none:  return "No messages"
        }
    }

    public var systemImage: String {
        switch self {
        case .sms:   return "message.fill"
        case .email: return "envelope.fill"
        case .push:  return "bell.fill"
        case .none:  return "nosign"
        }
    }
}

/// Time-of-day windows for comms delivery.
public enum CustomerContactWindow: String, CaseIterable, Codable, Sendable {
    case morning   = "morning"    // 08:00–12:00
    case afternoon = "afternoon"  // 12:00–17:00
    case evening   = "evening"    // 17:00–20:00
    case anytime   = "anytime"

    public var displayName: String {
        switch self {
        case .morning:   return "Morning (8am–12pm)"
        case .afternoon: return "Afternoon (12pm–5pm)"
        case .evening:   return "Evening (5pm–8pm)"
        case .anytime:   return "Any time"
        }
    }
}

/// Full preferences record for a customer.
public struct CustomerCommsPreferences: Codable, Sendable {
    public var preferredChannel: CustomerPreferredChannel
    public var preferredWindow: CustomerContactWindow
    public var marketingOptIn: Bool
    public var transactionalOptIn: Bool
    public var preferredLanguage: String?   // ISO 639-1 code, e.g. "en", "es"

    public init(
        preferredChannel: CustomerPreferredChannel = .sms,
        preferredWindow: CustomerContactWindow = .anytime,
        marketingOptIn: Bool = false,
        transactionalOptIn: Bool = true,
        preferredLanguage: String? = nil
    ) {
        self.preferredChannel = preferredChannel
        self.preferredWindow = preferredWindow
        self.marketingOptIn = marketingOptIn
        self.transactionalOptIn = transactionalOptIn
        self.preferredLanguage = preferredLanguage
    }

    enum CodingKeys: String, CodingKey {
        case preferredChannel   = "preferred_channel"
        case preferredWindow    = "preferred_window"
        case marketingOptIn     = "marketing_opt_in"
        case transactionalOptIn = "transactional_opt_in"
        case preferredLanguage  = "preferred_language"
    }
}

// MARK: - View

/// Sheet for viewing and editing a customer's communication preferences.
public struct CustomerCommPrefsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerCommPrefsViewModel

    public init(api: APIClient, customerId: Int64) {
        _vm = State(wrappedValue: CustomerCommPrefsViewModel(api: api, customerId: customerId))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Form {
                        channelSection
                        windowSection
                        optInsSection
                        languageSection

                        if let err = vm.errorMessage {
                            Section {
                                Text(err).foregroundStyle(.bizarreError).font(.brandBodyMedium())
                            }
                            .listRowBackground(Color.bizarreError.opacity(0.08))
                        }

                        staffOverrideSection
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Communication Preferences")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSaving ? "Saving…" : "Save") {
                        Task {
                            await vm.save()
                            if vm.savedSuccessfully { dismiss() }
                        }
                    }
                    .disabled(vm.isSaving || vm.isLoading)
                    .fontWeight(.semibold)
                }
            }
            .task { await vm.load() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Sections

    private var channelSection: some View {
        Section("Preferred channel for receipts, status & marketing") {
            ForEach(CustomerPreferredChannel.allCases, id: \.rawValue) { channel in
                Button {
                    vm.prefs.preferredChannel = channel
                } label: {
                    HStack {
                        Label(channel.displayName, systemImage: channel.systemImage)
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer(minLength: 0)
                        if vm.prefs.preferredChannel == channel {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.bizarreOrange)
                                .accessibilityHidden(true)
                        }
                    }
                }
                .accessibilityLabel("\(channel.displayName)\(vm.prefs.preferredChannel == channel ? ", selected" : "")")
            }
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var windowSection: some View {
        Section("Best time to contact") {
            Picker("Time window", selection: $vm.prefs.preferredWindow) {
                ForEach(CustomerContactWindow.allCases, id: \.rawValue) { w in
                    Text(w.displayName).tag(w)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Contact time window: \(vm.prefs.preferredWindow.displayName)")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var optInsSection: some View {
        Section("Message opt-ins") {
            Toggle("Transactional messages (receipts, status updates)", isOn: $vm.prefs.transactionalOptIn)
                .accessibilityLabel("Allow transactional messages: \(vm.prefs.transactionalOptIn ? "on" : "off")")
            Toggle("Marketing & promotional messages", isOn: $vm.prefs.marketingOptIn)
                .accessibilityLabel("Allow marketing messages: \(vm.prefs.marketingOptIn ? "on" : "off")")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var languageSection: some View {
        Section("Preferred language for messages") {
            Picker("Language", selection: Binding(
                get: { vm.prefs.preferredLanguage ?? "en" },
                set: { vm.prefs.preferredLanguage = $0 }
            )) {
                Text("English").tag("en")
                Text("Spanish").tag("es")
                Text("French").tag("fr")
                Text("Portuguese").tag("pt")
                Text("Chinese (Simplified)").tag("zh")
                Text("Arabic").tag("ar")
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Preferred language")
        }
        .listRowBackground(Color.bizarreSurface1)
    }

    private var staffOverrideSection: some View {
        Section {
            Label("System blocks sends that violate these preferences. Staff can override with an audit reason.", systemImage: "info.circle")
                .font(.brandBodySmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .listRowBackground(Color.bizarreSurface1)
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class CustomerCommPrefsViewModel {
    public var prefs: CustomerCommsPreferences = .init()
    public private(set) var isLoading = true
    public private(set) var isSaving = false
    public private(set) var errorMessage: String?
    public private(set) var savedSuccessfully = false

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let customerId: Int64

    public init(api: APIClient, customerId: Int64) {
        self.api = api
        self.customerId = customerId
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            prefs = try await api.customerCommPrefs(customerId: customerId)
        } catch {
            // Graceful degrade — start with defaults if endpoint not yet live.
            AppLog.ui.warning("Comm prefs fetch failed (may be 404): \(error.localizedDescription, privacy: .public)")
            prefs = .init()
        }
    }

    public func save() async {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        savedSuccessfully = false
        defer { isSaving = false }
        do {
            try await api.updateCustomerCommPrefs(customerId: customerId, prefs)
            savedSuccessfully = true
        } catch {
            errorMessage = AppError.from(error).localizedDescription
        }
    }
}

// MARK: - APIClient extension

public extension APIClient {
    /// `GET /api/v1/customers/:id/comm-prefs`
    func customerCommPrefs(customerId: Int64) async throws -> CustomerCommsPreferences {
        try await get("/api/v1/customers/\(customerId)/comm-prefs", as: CustomerCommsPreferences.self)
    }

    /// `PUT /api/v1/customers/:id/comm-prefs`
    @discardableResult
    func updateCustomerCommPrefs(customerId: Int64, _ prefs: CustomerCommsPreferences) async throws -> CustomerCommsPreferences {
        try await put("/api/v1/customers/\(customerId)/comm-prefs", body: prefs, as: CustomerCommsPreferences.self)
    }
}
#endif
