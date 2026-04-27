import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.7 Invoice Settings
//
// Covers: invoice # format, net terms, late fee, email-from, auto-reminders,
// allowed payment methods, processing surcharge fee.
// Server endpoint: GET/PUT /settings/invoices

// MARK: - Model

public struct InvoiceSettings: Codable, Sendable, Equatable {
    /// Number format template, e.g. "INV-{year}-{seq:04}".
    public var numberFormat: String
    /// Net terms in days; 0 = due on receipt.
    public var netTermsDays: Int
    /// Late fee percentage (0 = disabled).
    public var lateFeePercent: Double
    /// Grace period in days before late fee applies.
    public var lateFeGraceDays: Int
    /// Email "from" address for invoice delivery.
    public var emailFrom: String
    /// "Reply-to" address (can differ from from address).
    public var emailReplyTo: String
    /// Auto-reminder schedule: days relative to due date (negative = before, positive = after).
    public var reminderDays: [Int]
    /// Allowed payment methods (subset of: card, cash, check, ach, financing).
    public var allowedPaymentMethods: [String]
    /// Processing surcharge percentage (0 = disabled).
    public var surchargePct: Double

    public init(
        numberFormat: String = "INV-{year}-{seq:04}",
        netTermsDays: Int = 0,
        lateFeePercent: Double = 0,
        lateFeGraceDays: Int = 0,
        emailFrom: String = "",
        emailReplyTo: String = "",
        reminderDays: [Int] = [-3, 0, 3, 7],
        allowedPaymentMethods: [String] = ["card", "cash", "check"],
        surchargePct: Double = 0
    ) {
        self.numberFormat = numberFormat
        self.netTermsDays = netTermsDays
        self.lateFeePercent = lateFeePercent
        self.lateFeGraceDays = lateFeGraceDays
        self.emailFrom = emailFrom
        self.emailReplyTo = emailReplyTo
        self.reminderDays = reminderDays
        self.allowedPaymentMethods = allowedPaymentMethods
        self.surchargePct = surchargePct
    }

    enum CodingKeys: String, CodingKey {
        case numberFormat          = "number_format"
        case netTermsDays          = "net_terms_days"
        case lateFeePercent        = "late_fee_percent"
        case lateFeGraceDays       = "late_fee_grace_days"
        case emailFrom             = "email_from"
        case emailReplyTo          = "email_reply_to"
        case reminderDays          = "reminder_days"
        case allowedPaymentMethods = "allowed_payment_methods"
        case surchargePct          = "surcharge_pct"
    }
}

// MARK: - Net terms presets

private enum NetTermsPreset: Int, CaseIterable, Identifiable {
    case dueOnReceipt = 0
    case net15        = 15
    case net30        = 30
    case net45        = 45
    case net60        = 60

    var id: Int { rawValue }
    var displayName: String {
        switch self {
        case .dueOnReceipt: return "Due on receipt"
        case .net15:        return "Net 15"
        case .net30:        return "Net 30"
        case .net45:        return "Net 45"
        case .net60:        return "Net 60"
        }
    }
}

// MARK: - ViewModel

@MainActor
@Observable
public final class InvoiceSettingsViewModel {
    public var settings: InvoiceSettings = InvoiceSettings()
    public private(set) var isLoading = false
    public private(set) var isSaving = false
    public var errorMessage: String?
    public var successMessage: String?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await api.getInvoiceSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            settings = try await api.putInvoiceSettings(settings)
            successMessage = "Invoice settings saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Networking

extension APIClient {
    func getInvoiceSettings() async throws -> InvoiceSettings {
        try await get("/api/v1/settings/invoices", as: InvoiceSettings.self)
    }

    func putInvoiceSettings(_ settings: InvoiceSettings) async throws -> InvoiceSettings {
        struct Wrapper: Encodable { let settings: InvoiceSettings }
        return try await put("/api/v1/settings/invoices", body: Wrapper(settings: settings), as: InvoiceSettings.self)
    }
}

// MARK: - View

public struct InvoiceSettingsPage: View {
    @State private var vm: InvoiceSettingsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: InvoiceSettingsViewModel(api: api))
    }

    public var body: some View {
        ZStack {
            Color.bizarreSurfaceBase.ignoresSafeArea()
            Form {
                numberFormatSection
                netTermsSection
                lateFeeSection
                emailSection
                remindersSection
                paymentMethodsSection
                surchargeSection
            }
            #if canImport(UIKit)
            .listStyle(.insetGrouped)
            #endif
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Invoice Settings")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("invoiceSettings.save")
            }
        }
        .task { await vm.load() }
        .alert("Saved", isPresented: Binding(
            get: { vm.successMessage != nil },
            set: { if !$0 { vm.successMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.successMessage = nil }
        } message: {
            Text(vm.successMessage ?? "")
        }
    }

    // MARK: - Sections

    private var numberFormatSection: some View {
        Section {
            VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                TextField("e.g. INV-{year}-{seq:04}", text: $vm.settings.numberFormat)
                    .autocorrectionDisabled()
                    .font(.brandBodyMedium().monospaced())
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityIdentifier("invoice.numberFormat")
                Text("Tokens: {year} {month} {day} {seq} {seq:04} {seq:06}")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Invoice Number Format")
        } footer: {
            Text("Preview: \(invoiceNumberPreview)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOrange)
        }
    }

    private var netTermsSection: some View {
        Section {
            Picker("Net Terms", selection: $vm.settings.netTermsDays) {
                ForEach(NetTermsPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
            }
            .pickerStyle(.menu)
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityIdentifier("invoice.netTerms")

            if !NetTermsPreset.allCases.map(\.rawValue).contains(vm.settings.netTermsDays) {
                Stepper("Custom: \(vm.settings.netTermsDays) days",
                        value: $vm.settings.netTermsDays, in: 1...180)
                    .listRowBackground(Color.bizarreSurface1)
            }
        } header: {
            Text("Net Terms")
        }
    }

    private var lateFeeSection: some View {
        Section {
            HStack {
                Text("Late fee")
                Spacer()
                TextField("0", value: $vm.settings.lateFeePercent, format: .percent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityIdentifier("invoice.lateFee")
            }
            .listRowBackground(Color.bizarreSurface1)

            Stepper("Grace period: \(vm.settings.lateFeGraceDays) days",
                    value: $vm.settings.lateFeGraceDays, in: 0...30)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("invoice.graceDays")
        } header: {
            Text("Late Fee")
        } footer: {
            Text("0% disables the late fee. The grace period starts from the due date.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var emailSection: some View {
        Section {
            HStack {
                Text("From")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 60, alignment: .leading)
                TextField("invoices@yourshop.com", text: $vm.settings.emailFrom)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("invoice.emailFrom")
            }
            .listRowBackground(Color.bizarreSurface1)

            HStack {
                Text("Reply-to")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(width: 60, alignment: .leading)
                TextField("support@yourshop.com", text: $vm.settings.emailReplyTo)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .accessibilityIdentifier("invoice.emailReplyTo")
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Email Settings")
        }
    }

    private var remindersSection: some View {
        Section {
            ForEach(reminderLabels, id: \.day) { item in
                Toggle(item.label, isOn: Binding(
                    get: { vm.settings.reminderDays.contains(item.day) },
                    set: { enabled in
                        if enabled {
                            vm.settings.reminderDays.append(item.day)
                            vm.settings.reminderDays.sort()
                        } else {
                            vm.settings.reminderDays.removeAll { $0 == item.day }
                        }
                    }
                ))
                .tint(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
            }
        } header: {
            Text("Auto-Reminders")
        } footer: {
            Text("Reminders sent automatically relative to the invoice due date.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    private var paymentMethodsSection: some View {
        let methods = [("card", "Card"), ("cash", "Cash"), ("check", "Check"),
                       ("ach", "ACH / Bank transfer"), ("financing", "Financing")]
        return Section {
            ForEach(methods, id: \.0) { (key, label) in
                Toggle(label, isOn: Binding(
                    get: { vm.settings.allowedPaymentMethods.contains(key) },
                    set: { enabled in
                        if enabled {
                            vm.settings.allowedPaymentMethods.append(key)
                        } else {
                            vm.settings.allowedPaymentMethods.removeAll { $0 == key }
                        }
                    }
                ))
                .tint(.bizarreOrange)
                .listRowBackground(Color.bizarreSurface1)
                .accessibilityIdentifier("invoice.method.\(key)")
            }
        } header: {
            Text("Accepted Payment Methods")
        }
    }

    private var surchargeSection: some View {
        Section {
            HStack {
                Text("Card surcharge")
                Spacer()
                TextField("0", value: $vm.settings.surchargePct, format: .percent)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    .accessibilityIdentifier("invoice.surcharge")
            }
            .listRowBackground(Color.bizarreSurface1)
        } header: {
            Text("Processing Surcharge")
        } footer: {
            Text("Added to card payments. 0% disables. Check local regulations before enabling.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    // MARK: - Helpers

    private var invoiceNumberPreview: String {
        let fmt = vm.settings.numberFormat
        let year = Calendar.current.component(.year, from: Date())
        return fmt
            .replacingOccurrences(of: "{year}", with: "\(year)")
            .replacingOccurrences(of: "{month}", with: "01")
            .replacingOccurrences(of: "{day}", with: "01")
            .replacingOccurrences(of: "{seq:06}", with: "000042")
            .replacingOccurrences(of: "{seq:04}", with: "0042")
            .replacingOccurrences(of: "{seq}", with: "42")
    }

    private var reminderLabels: [(day: Int, label: String)] {
        [
            (-7, "7 days before due"),
            (-3, "3 days before due"),
            (0,  "On due date"),
            (3,  "3 days overdue"),
            (7,  "7 days overdue"),
            (14, "14 days overdue"),
        ]
    }
}
