import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - ComposeNewThreadView
//
// §12.1 Compose new (FAB) — pick customer or raw phone.
// Presented as a sheet from SmsListView's FAB button.
// iPhone: full-screen sheet. iPad: .medium + .large detents.

@MainActor
@Observable
public final class ComposeNewThreadViewModel {
    public private(set) var customers: [CustomerPickerItem] = []
    public private(set) var isLoading: Bool = false
    public private(set) var isSending: Bool = false
    public private(set) var sendError: String?
    public private(set) var sentPhone: String?

    public var searchQuery: String = ""
    public var rawPhone: String = ""
    public var initialMessage: String = ""
    public var useRawPhone: Bool = false

    public var selectedCustomer: CustomerPickerItem?

    /// Combined recipient phone — either raw input or customer's phone.
    public var recipientPhone: String {
        if useRawPhone { return rawPhone }
        return selectedCustomer?.phone ?? ""
    }

    public var isValid: Bool {
        let p = recipientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        return !p.isEmpty && !m.isEmpty
    }

    /// Filtered customers based on searchQuery.
    public var filteredCustomers: [CustomerPickerItem] {
        guard !searchQuery.isEmpty else { return customers }
        let q = searchQuery.lowercased()
        return customers.filter {
            $0.displayName.lowercased().contains(q) ||
            $0.phone.lowercased().contains(q)
        }
    }

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) {
        self.api = api
    }

    public func loadCustomers() async {
        guard customers.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            // Routed through APIClient+Communications.swift per §20 containment.
            customers = try await api.listCustomerPickerItems()
        } catch {
            AppLog.ui.error("ComposeNewThread load customers failed: \(error.localizedDescription, privacy: .public)")
            // Non-fatal — user can still enter a raw phone.
        }
    }

    public func send(completion: @escaping (String) -> Void) async {
        let p = recipientPhone.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty, !m.isEmpty, !isSending else { return }
        isSending = true
        sendError = nil
        defer { isSending = false }
        do {
            _ = try await api.sendSms(to: p, message: m)
            sentPhone = p
            completion(p)
        } catch {
            AppLog.ui.error("ComposeNewThread send failed: \(error.localizedDescription, privacy: .public)")
            sendError = error.localizedDescription
        }
    }
}

// Note: CustomerPickerItem lives in Networking/APIClient+Communications.swift

// MARK: - View

public struct ComposeNewThreadView: View {
    @State private var vm: ComposeNewThreadViewModel
    @Environment(\.dismiss) private var dismiss
    private let onThreadOpened: (String) -> Void

    public init(api: APIClient, onThreadOpened: @escaping (String) -> Void) {
        _vm = State(wrappedValue: ComposeNewThreadViewModel(api: api))
        self.onThreadOpened = onThreadOpened
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    recipientSection
                    Divider()
                    messageSection
                    Spacer()
                }
            }
            .navigationTitle("New Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarItems }
            .task { await vm.loadCustomers() }
        }
        .presentationDetents(Platform.isCompact ? [.large] : [.medium, .large])
    }

    // MARK: - Recipient section

    @ViewBuilder
    private var recipientSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Toggle("Enter phone number manually", isOn: $vm.useRawPhone)
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.top, BrandSpacing.md)
                .accessibilityLabel("Toggle manual phone entry")

            if vm.useRawPhone {
                rawPhoneField
            } else {
                customerPicker
            }
        }
    }

    private var rawPhoneField: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Phone number")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.md)
            TextField("+1 (555) 000-0000", text: $vm.rawPhone)
                .keyboardType(.phonePad)
                .autocorrectionDisabled()
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .padding(.horizontal, BrandSpacing.md)
                .accessibilityLabel("Recipient phone number")
        }
    }

    @ViewBuilder
    private var customerPicker: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            if vm.isLoading {
                ProgressView()
                    .padding(.horizontal, BrandSpacing.md)
            } else {
                TextField("Search customer name or phone", text: $vm.searchQuery)
                    .autocorrectionDisabled()
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                    .padding(.horizontal, BrandSpacing.md)
                    .accessibilityLabel("Search customers")

                if let sel = vm.selectedCustomer {
                    selectedCustomerRow(sel)
                } else {
                    customerList
                }
            }
        }
    }

    private func selectedCustomerRow(_ customer: CustomerPickerItem) -> some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.crop.circle.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(customer.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                if !customer.phone.isEmpty {
                    Text(customer.phone)
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
            }
            Spacer()
            Button {
                vm.selectedCustomer = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .accessibilityLabel("Remove selected customer")
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreOrange.opacity(0.1), in: RoundedRectangle(cornerRadius: DesignTokens.Radius.sm))
        .padding(.horizontal, BrandSpacing.md)
    }

    @ViewBuilder
    private var customerList: some View {
        let results = vm.filteredCustomers.filter { !$0.phone.isEmpty }.prefix(8)
        if !results.isEmpty {
            ScrollView {
                LazyVStack(spacing: BrandSpacing.xs) {
                    ForEach(Array(results)) { customer in
                        CustomerRow(customer: customer) {
                            vm.selectedCustomer = customer
                            vm.searchQuery = ""
                        }
                    }
                }
                .padding(.horizontal, BrandSpacing.md)
            }
            .frame(maxHeight: 200)
        }
    }

    // MARK: - Message section

    private var messageSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Message")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .padding(.horizontal, BrandSpacing.md)
                .padding(.top, BrandSpacing.md)

            TextEditor(text: $vm.initialMessage)
                .frame(minHeight: 100)
                .padding(BrandSpacing.xs)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .padding(.horizontal, BrandSpacing.md)
                .accessibilityLabel("Message body")

            if let err = vm.sendError {
                Label(err, systemImage: "exclamationmark.circle")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .padding(.horizontal, BrandSpacing.md)
                    .accessibilityLabel("Send error: \(err)")
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
                .accessibilityLabel("Cancel new message")
        }
        ToolbarItem(placement: .primaryAction) {
            if vm.isSending {
                ProgressView()
            } else {
                Button("Send") {
                    Task {
                        await vm.send { phone in
                            dismiss()
                            onThreadOpened(phone)
                        }
                    }
                }
                .disabled(!vm.isValid)
                .fontWeight(.semibold)
                .accessibilityLabel("Send message")
                .keyboardShortcut(.return, modifiers: [.command])
            }
        }
    }
}

// MARK: - CustomerRow

private struct CustomerRow: View {
    let customer: CustomerPickerItem
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: BrandSpacing.sm) {
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(initials)
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(customer.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    if !customer.phone.isEmpty {
                        Text(customer.phone)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                Spacer()
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(customer.displayName), \(customer.phone)")
        .hoverEffect(.highlight)
    }

    private var initials: String {
        let f = customer.firstName?.prefix(1).uppercased() ?? ""
        let l = customer.lastName?.prefix(1).uppercased() ?? ""
        let c = f + l
        return c.isEmpty ? "#" : c
    }
}
