import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - §19.6 Required fields at intake
//
// Admin tool: pick which intake fields must be filled in before a new ticket
// can be saved. Server endpoint: GET/PUT /settings/tickets/required-fields.
// Stored as a flat array of field keys (e.g. ["customer", "deviceModel"]).
//
// Layout: iPhone shows a vertical Form with toggle rows; iPad uses a 2-col
// LazyVGrid of toggle cards so admins can see every option at once on the
// wider canvas (CLAUDE.md: iPhone vs iPad must look different).

// MARK: - Field catalog

public struct TicketIntakeField: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let symbol: String
    public let helpText: String

    public init(id: String, label: String, symbol: String, helpText: String) {
        self.id = id; self.label = label; self.symbol = symbol; self.helpText = helpText
    }

    public static let catalog: [TicketIntakeField] = [
        .init(id: "customer",         label: "Customer",          symbol: "person.fill",
              helpText: "Link the ticket to a customer record."),
        .init(id: "deviceModel",      label: "Device model",      symbol: "iphone",
              helpText: "Make + model selected from device template catalog."),
        .init(id: "imei",             label: "IMEI / serial",     symbol: "barcode.viewfinder",
              helpText: "Scanned or typed; flagged if a duplicate already exists."),
        .init(id: "passcode",         label: "Passcode / pattern", symbol: "lock.fill",
              helpText: "Required when device must be unlocked for diagnosis."),
        .init(id: "accessories",      label: "Accessories",       symbol: "cable.connector",
              helpText: "Cables, cases, SIM trays handed in with the device."),
        .init(id: "reportedIssue",    label: "Reported issue",    symbol: "text.alignleft",
              helpText: "Customer-described problem — printed on intake receipt."),
        .init(id: "estimatedCost",    label: "Estimated cost",    symbol: "dollarsign.circle",
              helpText: "Up-front quote shown to the customer."),
        .init(id: "depositCollected", label: "Deposit collected", symbol: "creditcard.fill",
              helpText: "Down-payment captured before work starts."),
        .init(id: "dueDate",          label: "Promised by date",  symbol: "calendar",
              helpText: "Customer-promised completion date."),
        .init(id: "technician",       label: "Assigned technician", symbol: "wrench.adjustable.fill",
              helpText: "Tech who owns the ticket from intake."),
    ]
}

// MARK: - ViewModel

@MainActor
@Observable
public final class TicketRequiredFieldsViewModel {
    public var requiredFields: Set<String> = []
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
        errorMessage = nil
        do {
            let dto = try await api.fetchTicketRequiredFields()
            requiredFields = Set(dto.requiredFields)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func save() async {
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let body = TicketRequiredFieldsDTO(requiredFields: Array(requiredFields).sorted())
            let saved = try await api.saveTicketRequiredFields(body)
            requiredFields = Set(saved.requiredFields)
            successMessage = "Required fields saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func toggle(_ field: TicketIntakeField, on: Bool) {
        if on { requiredFields.insert(field.id) }
        else  { requiredFields.remove(field.id) }
    }

    public func isRequired(_ field: TicketIntakeField) -> Bool {
        requiredFields.contains(field.id)
    }

    public func resetToDefaults() {
        // Sensible defaults for a typical repair shop.
        requiredFields = ["customer", "deviceModel", "reportedIssue"]
    }

    public var requiredCount: Int { requiredFields.count }
}

// MARK: - View

public struct TicketRequiredFieldsPage: View {
    @State private var vm: TicketRequiredFieldsViewModel

    public init(api: APIClient) {
        _vm = State(wrappedValue: TicketRequiredFieldsViewModel(api: api))
    }

    public var body: some View {
        Group {
            if Platform.isCompact {
                phoneLayout
            } else {
                padLayout
            }
        }
        .navigationTitle("Required Fields")
        #if canImport(UIKit)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await vm.save() } }
                    .disabled(vm.isSaving)
                    .keyboardShortcut("s", modifiers: .command)
                    .accessibilityIdentifier("ticketRequired.save")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Reset to defaults", systemImage: "arrow.counterclockwise") {
                    vm.resetToDefaults()
                }
                .accessibilityIdentifier("ticketRequired.reset")
            }
        }
        .task { await vm.load() }
        .alert("Saved", isPresented: Binding(
            get: { vm.successMessage != nil },
            set: { if !$0 { vm.successMessage = nil } }
        )) {
            Button("OK", role: .cancel) { vm.successMessage = nil }
        } message: { Text(vm.successMessage ?? "") }
        .overlay {
            if vm.isLoading {
                ProgressView().accessibilityLabel("Loading required-field policy")
            }
        }
    }

    // MARK: iPhone layout — vertical Form with toggle rows

    private var phoneLayout: some View {
        Form {
            Section {
                ForEach(TicketIntakeField.catalog) { field in
                    Toggle(isOn: Binding(
                        get: { vm.isRequired(field) },
                        set: { vm.toggle(field, on: $0) }
                    )) {
                        HStack(spacing: BrandSpacing.sm) {
                            Image(systemName: field.symbol)
                                .foregroundStyle(.bizarreOrange)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(field.label)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(field.helpText)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }
                    }
                    .tint(.bizarreOrange)
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityIdentifier("ticketRequired.field.\(field.id)")
                }
            } header: {
                Text("Required at intake")
            } footer: {
                Text("\(vm.requiredCount) required of \(TicketIntakeField.catalog.count). New tickets cannot be saved until every required field is filled in.")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                }
            }
        }
        #if canImport(UIKit)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
    }

    // MARK: iPad layout — 2-column grid of toggle cards

    private var padLayout: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                summaryHeader
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: BrandSpacing.lg),
                              GridItem(.flexible(), spacing: BrandSpacing.lg)],
                    alignment: .leading,
                    spacing: BrandSpacing.lg
                ) {
                    ForEach(TicketIntakeField.catalog) { field in
                        padCard(for: field)
                    }
                }

                if let err = vm.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.bizarreError)
                        .padding(BrandSpacing.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                }
            }
            .padding(BrandSpacing.lg)
        }
    }

    private var summaryHeader: some View {
        HStack(spacing: BrandSpacing.md) {
            Image(systemName: "checklist")
                .font(.title2)
                .foregroundStyle(.bizarreOrange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Intake gates")
                    .font(.brandHeadlineSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Text("\(vm.requiredCount) of \(TicketIntakeField.catalog.count) fields required before save.")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            Spacer()
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    private func padCard(for field: TicketIntakeField) -> some View {
        let isOn = vm.isRequired(field)
        return Toggle(isOn: Binding(
            get: { vm.isRequired(field) },
            set: { vm.toggle(field, on: $0) }
        )) {
            HStack(alignment: .top, spacing: BrandSpacing.sm) {
                Image(systemName: field.symbol)
                    .font(.title3)
                    .foregroundStyle(isOn ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(field.label)
                        .font(.brandBodyMedium().bold())
                        .foregroundStyle(.bizarreOnSurface)
                    Text(field.helpText)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(.bizarreOrange)
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.lg)
                .stroke(isOn ? Color.bizarreOrange.opacity(0.6) : Color.clear, lineWidth: 1)
        )
        .hoverEffect(.highlight)
        .contextMenu {
            Button(isOn ? "Make optional" : "Make required") {
                vm.toggle(field, on: !isOn)
            }
        }
        .accessibilityIdentifier("ticketRequired.card.\(field.id)")
        .accessibilityLabel("\(field.label), \(isOn ? "required" : "optional")")
    }
}
