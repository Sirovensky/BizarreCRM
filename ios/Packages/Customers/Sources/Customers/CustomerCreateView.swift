import Foundation
import Observation
import Core
import Networking

public let PendingSyncCustomerId: Int64 = -1

@MainActor
@Observable
public final class CustomerCreateViewModel {
    public var firstName: String = ""
    public var lastName: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var mobile: String = ""
    public var organization: String = ""
    public var address1: String = ""
    public var city: String = ""
    public var state: String = ""
    public var postcode: String = ""
    public var notes: String = ""

    public internal(set) var isSubmitting: Bool = false
    public internal(set) var errorMessage: String?
    public internal(set) var createdId: Int64?
    public internal(set) var queuedOffline: Bool = false

    // §63 ext — draft recovery
    public internal(set) var _draftRecord: DraftRecord?
    public internal(set) var _pendingDraft: CustomerDraft?
    public internal(set) var validationErrors: [String: String] = [:]

    @ObservationIgnored internal let _draftStoreValue: DraftStore = DraftStore()
    @ObservationIgnored internal lazy var _draftAutoSaverValue: DraftAutoSaver<CustomerDraft> =
        DraftAutoSaver(screen: "customer.create", store: _draftStoreValue)

    @ObservationIgnored private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        queuedOffline = false
        guard isValid else {
            errorMessage = "First name is required."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = buildRequest()

        do {
            let created = try await api.createCustomer(req)
            createdId = created.id
            await _draftAutoSaverValue.clear()
        } catch {
            let appError = AppError.from(error)
            if case .offline = appError {
                await enqueueOffline(req)
                await handleAppError(appError)
            } else if CustomerOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Customer create failed: \(error.localizedDescription, privacy: .public)")
                await handleAppError(appError)
            }
        }
    }

    private func buildRequest() -> CreateCustomerRequest {
        CreateCustomerRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: trim(lastName),
            email: trim(email),
            phone: trim(phone).map { PhoneFormatter.normalize($0) },
            mobile: trim(mobile).map { PhoneFormatter.normalize($0) },
            organization: trim(organization),
            address1: trim(address1),
            city: trim(city),
            state: trim(state),
            postcode: trim(postcode),
            notes: trim(notes)
        )
    }

    private func enqueueOffline(_ req: CreateCustomerRequest) async {
        do {
            let payload = try CustomerOfflineQueue.encode(req)
            await CustomerOfflineQueue.enqueue(op: "create", payload: payload)
            createdId = PendingSyncCustomerId
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Customer create encode failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func trim(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

#if canImport(UIKit)
import SwiftUI
import DesignSystem

public struct CustomerCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: CustomerCreateViewModel
    @State private var pendingBanner: String?

    /// Optional hook fired before dismiss after a successful create.
    /// §16.4 POS cart attach uses this to attach the new customer
    /// without re-querying.
    private let onCreated: ((Int64, CustomerCreateViewModel) -> Void)?

    public init(api: APIClient) {
        _vm = State(wrappedValue: CustomerCreateViewModel(api: api))
        self.onCreated = nil
    }

    public init(
        api: APIClient,
        onCreated: @escaping (Int64, CustomerCreateViewModel) -> Void
    ) {
        _vm = State(wrappedValue: CustomerCreateViewModel(api: api))
        self.onCreated = onCreated
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // §63 ext — draft recovery banner
                if let record = vm._draftRecord {
                    DraftRecoveryBanner(record: record) {
                        vm.restoreDraft()
                    } onDiscard: {
                        vm.discardDraft()
                    }
                }

                CustomerFormView(
                    firstName: $vm.firstName,
                    lastName: $vm.lastName,
                    email: $vm.email,
                    phone: $vm.phone,
                    mobile: $vm.mobile,
                    organization: $vm.organization,
                    address1: $vm.address1,
                    city: $vm.city,
                    state: $vm.state,
                    postcode: $vm.postcode,
                    notes: $vm.notes,
                    errorMessage: vm.errorMessage
                )
                .onChange(of: vm.firstName)      { _, _ in vm.scheduleAutoSave() }
                .onChange(of: vm.lastName)       { _, _ in vm.scheduleAutoSave() }
                .onChange(of: vm.email)          { _, _ in vm.scheduleAutoSave() }
                .onChange(of: vm.phone)          { _, _ in vm.scheduleAutoSave() }
                .onChange(of: vm.notes)          { _, _ in vm.scheduleAutoSave() }
            }
            .navigationTitle("New customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(vm.isSubmitting ? "Saving…" : "Save") {
                        Task {
                            await vm.submit()
                            if vm.queuedOffline {
                                pendingBanner = "Saved — will sync when online"
                                if let id = vm.createdId { onCreated?(id, vm) }
                                try? await Task.sleep(nanoseconds: 900_000_000)
                                dismiss()
                            } else if let id = vm.createdId {
                                onCreated?(id, vm)
                                dismiss()
                            }
                        }
                    }
                    .disabled(!vm.isValid || vm.isSubmitting)
                }
            }
            .overlay(alignment: .top) {
                if let banner = pendingBanner {
                    PendingSyncBanner(text: banner)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.top, BrandSpacing.sm)
                }
            }
            .task { await vm.onAppear() }
        }
    }
}

struct PendingSyncBanner: View {
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
#endif
