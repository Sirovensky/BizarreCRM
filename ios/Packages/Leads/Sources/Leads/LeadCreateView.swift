import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

@MainActor
@Observable
public final class LeadCreateViewModel {
    public var firstName: String = ""
    public var lastName: String = ""
    public var email: String = ""
    public var phone: String = ""
    public var source: String = ""
    public var notes: String = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?

    @ObservationIgnored private let api: APIClient
    public init(api: APIClient) { self.api = api }

    public var isValid: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public func submit() async {
        guard !isSubmitting else { return }
        errorMessage = nil
        guard isValid else {
            errorMessage = "First name is required."
            return
        }
        isSubmitting = true
        defer { isSubmitting = false }

        let req = CreateLeadRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: nilIfEmpty(lastName),
            email: nilIfEmpty(email),
            phone: nilIfEmpty(phone).map(PhoneFormatter.normalize),
            source: nilIfEmpty(source),
            notes: nilIfEmpty(notes)
        )
        do {
            let created = try await api.createLead(req)
            createdId = created.id
        } catch {
            AppLog.ui.error("Lead create failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    private func nilIfEmpty(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

public struct LeadCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vm: LeadCreateViewModel

    public init(api: APIClient) { _vm = State(wrappedValue: LeadCreateViewModel(api: api)) }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Lead") {
                    TextField("First name", text: $vm.firstName).textContentType(.givenName)
                    TextField("Last name", text: $vm.lastName).textContentType(.familyName)
                    TextField("Phone", text: $vm.phone)
                        .textContentType(.telephoneNumber).keyboardType(.phonePad)
                    TextField("Email", text: $vm.email)
                        .textContentType(.emailAddress).keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Source (Google, Yelp, walk-in…)", text: $vm.source)
                }
                Section("Notes") {
                    TextField("Notes", text: $vm.notes, axis: .vertical).lineLimit(3...6)
                }
                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.bizarreError) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.bizarreSurfaceBase.ignoresSafeArea())
            .navigationTitle("New lead")
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
        }
    }
}
