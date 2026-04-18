import SwiftUI
import Observation
import Core
import DesignSystem
import Networking
import Customers

@MainActor
@Observable
public final class TicketCreateViewModel {
    public var selectedCustomer: CustomerSummary?

    public var deviceName: String = ""
    public var imei: String = ""
    public var serial: String = ""
    public var additionalNotes: String = ""
    public var priceText: String = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var price: Double { Double(priceText.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    public var isValid: Bool {
        selectedCustomer != nil
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard let customer = selectedCustomer else {
            errorMessage = "Pick a customer first."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let device = CreateTicketRequest.NewDevice(
            deviceName: deviceName.trimmingCharacters(in: .whitespaces),
            imei: nilIfEmpty(imei),
            serial: nilIfEmpty(serial),
            additionalNotes: nilIfEmpty(additionalNotes),
            price: price
        )
        let req = CreateTicketRequest(customerId: customer.id, devices: [device])
        do {
            let created = try await api.createTicket(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Ticket create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct TicketCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketCreateViewModel
    @State private var showingCustomerPicker = false
    private let customerRepo: CustomerRepository

    public init(api: APIClient, customerRepo: CustomerRepository) {
        self.customerRepo = customerRepo
        _vm = State(wrappedValue: TicketCreateViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Customer") {
                    Button {
                        showingCustomerPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.circle")
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                            if let customer = vm.selectedCustomer {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(customer.displayName)
                                        .foregroundStyle(.bizarreOnSurface)
                                    if let line = customer.contactLine {
                                        Text(line).font(.brandLabelSmall()).foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                }
                            } else {
                                Text("Choose customer").foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("Device") {
                    TextField("Device (e.g. iPhone 14 Pro)", text: $vm.deviceName)
                    TextField("IMEI", text: $vm.imei).keyboardType(.numbersAndPunctuation)
                    TextField("Serial", text: $vm.serial).autocorrectionDisabled()
                    TextField("Price (USD)", text: $vm.priceText).keyboardType(.decimalPad)
                }

                Section("Notes") {
                    TextField("What's wrong / customer said…", text: $vm.additionalNotes, axis: .vertical)
                        .lineLimit(3...6)
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.createdId != nil { dismiss() }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .sheet(isPresented: $showingCustomerPicker) {
                CustomerPickerSheet(repo: customerRepo) { customer in
                    vm.selectedCustomer = customer
                    showingCustomerPicker = false
                }
            }
        }
    }
}

// MARK: - Customer picker sheet

private struct CustomerPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerListViewModel
    @State private var searchText: String = ""
    let onPick: (CustomerSummary) -> Void

    init(repo: CustomerRepository, onPick: @escaping (CustomerSummary) -> Void) {
        _vm = State(wrappedValue: CustomerListViewModel(repo: repo))
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.customers.isEmpty {
                    ContentUnavailableView(
                        "No customers",
                        systemImage: "person.2",
                        description: Text("Search above or create a customer first.")
                    )
                } else {
                    List {
                        ForEach(vm.customers) { customer in
                            Button { onPick(customer) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(customer.displayName)
                                        .foregroundStyle(.bizarreOnSurface)
                                    if let line = customer.contactLine {
                                        Text(line)
                                            .font(.brandLabelSmall())
                                            .foregroundStyle(.bizarreOnSurfaceMuted)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle("Choose customer")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search customers")
            .onChange(of: searchText) { _, new in vm.onSearchChange(new) }
            .task { await vm.load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }
}
