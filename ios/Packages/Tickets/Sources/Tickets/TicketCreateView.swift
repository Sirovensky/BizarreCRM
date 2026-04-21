#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking
import Customers

public struct TicketCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: TicketCreateViewModel
    @State private var showingCustomerPicker = false
    @State private var pendingBanner: String?
    private let customerRepo: CustomerRepository

    public init(api: APIClient, customerRepo: CustomerRepository) {
        self.customerRepo = customerRepo
        _vm = State(wrappedValue: TicketCreateViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §63 ext — draft recovery banner
                if let record = vm.draftRecord {
                    DraftRecoveryBanner(record: record) {
                        vm.restoreDraft()
                    } onDiscard: {
                        vm.discardDraft()
                    }
                }

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
                            .onChange(of: vm.deviceName) { _, _ in vm.scheduleAutoSave() }
                        TextField("IMEI", text: $vm.imei)
                            .keyboardType(.numbersAndPunctuation)
                            .onChange(of: vm.imei) { _, _ in vm.scheduleAutoSave() }
                        TextField("Serial", text: $vm.serial)
                            .autocorrectionDisabled()
                            .onChange(of: vm.serial) { _, _ in vm.scheduleAutoSave() }
                        TextField("Price (USD)", text: $vm.priceText)
                            .keyboardType(.decimalPad)
                            .onChange(of: vm.priceText) { _, _ in vm.scheduleAutoSave() }
                    }

                    Section("Notes") {
                        TextField("What's wrong / customer said…", text: $vm.additionalNotes, axis: .vertical)
                            .lineLimit(3...6)
                            .onChange(of: vm.additionalNotes) { _, _ in vm.scheduleAutoSave() }
                    }

                    if let err = vm.errorMessage {
                        Section { Text(err).foregroundStyle(.bizarreError) }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            }
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New ticket")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                try? await Task.sleep(nanoseconds: 900_000_000)
                                dismiss()
                            } else if vm.createdId != nil {
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .sheet(isPresented: $showingCustomerPicker) {
                CustomerPickerSheet(repo: customerRepo) { customer in
                    vm.selectedCustomer = customer
                    vm.scheduleAutoSave()
                    showingCustomerPicker = false
                }
            }
            .overlay(alignment: .top) {
                if let banner = pendingBanner {
                    TicketPendingSyncBanner(text: banner)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                }
            }
            .task { await vm.onAppear() }
        }
    }
}

// MARK: - Pending-sync banner

/// Small glass banner for "Saved — will sync" — chrome only, per the
/// Liquid-Glass rule (not a row or card).
struct TicketPendingSyncBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "checkmark.icloud")
            Text(text).font(.brandLabelLarge())
        }
        .foregroundStyle(.bizarreOnSurface)
        .padding(.horizontal, BrandSpacing.base)
        .padding(.vertical, BrandSpacing.sm)
        .brandGlass(.regular, tint: .bizarreOrange)
        .transition(.move(edge: .top).combined(with: .opacity))
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
#endif
