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

    // §9.4 Extended fields
    public var company: String = ""
    public var title: String = ""
    public var estimatedValue: String = ""
    public var stage: String = "new"
    public var followUpDate: Date = Date().addingTimeInterval(86400 * 3)
    public var hasFollowUpDate: Bool = false
    public var tagInput: String = ""

    public private(set) var isSubmitting = false
    public private(set) var errorMessage: String?
    public private(set) var createdId: Int64?
    /// True when the create was queued offline (not yet sent to server).
    public private(set) var queuedOffline: Bool = false

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
            let created = try await api.createLead(req)
            createdId = created.id
        } catch {
            let appError = AppError.from(error)
            if case .offline = appError {
                await enqueueOffline(req)
            } else if LeadOfflineQueue.isNetworkError(error) {
                await enqueueOffline(req)
            } else {
                AppLog.ui.error("Lead create failed: \(error.localizedDescription, privacy: .public)")
                errorMessage = error.localizedDescription
            }
        }
    }

    private func buildRequest() -> CreateLeadRequest {
        let valueCents: Int? = estimatedValue.isEmpty ? nil
            : Int((Double(estimatedValue) ?? 0) * 100)
        let followUp: String? = hasFollowUpDate
            ? ISO8601DateFormatter().string(from: followUpDate)
            : nil
        return CreateLeadRequest(
            firstName: firstName.trimmingCharacters(in: .whitespaces),
            lastName: nilIfEmpty(lastName),
            email: nilIfEmpty(email),
            phone: nilIfEmpty(phone).map(PhoneFormatter.normalize),
            source: nilIfEmpty(source),
            notes: nilIfEmpty(notes),
            company: nilIfEmpty(company),
            title: nilIfEmpty(title),
            estimatedValueCents: valueCents,
            stage: nilIfEmpty(stage),
            followUpAt: followUp
        )
    }

    private func enqueueOffline(_ req: CreateLeadRequest) async {
        do {
            let payload = try LeadOfflineQueue.encode(req)
            await LeadOfflineQueue.enqueue(op: "create", payload: payload)
            createdId = PendingSyncLeadId
            queuedOffline = true
            errorMessage = nil
        } catch {
            AppLog.sync.error("Lead offline encode failed: \(error.localizedDescription, privacy: .public)")
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
                Section("Contact") {
                    TextField("First name *", text: $vm.firstName).textContentType(.givenName)
                    TextField("Last name", text: $vm.lastName).textContentType(.familyName)
                    TextField("Company", text: $vm.company).textContentType(.organizationName)
                    TextField("Title", text: $vm.title).textContentType(.jobTitle)
                    TextField("Phone", text: $vm.phone)
                        .textContentType(.telephoneNumber)
#if !os(macOS)
                        .keyboardType(.phonePad)
#endif
                    TextField("Email", text: $vm.email)
                        .textContentType(.emailAddress)
#if !os(macOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
#endif
                }

                // §9.4 Extended fields
                Section("Pipeline") {
                    Picker("Stage", selection: $vm.stage) {
                        ForEach(["new", "contacted", "scheduled", "qualified", "proposal"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                    TextField("Source (Google, Yelp, walk-in…)", text: $vm.source)
                    TextField("Est. value ($)", text: $vm.estimatedValue)
#if !os(macOS)
                        .keyboardType(.decimalPad)
#endif
                }

                Section("Follow-up") {
                    Toggle("Set follow-up date", isOn: $vm.hasFollowUpDate)
                    if vm.hasFollowUpDate {
                        DatePicker(
                            "Follow-up date",
                            selection: $vm.followUpDate,
                            in: Date()...,
                            displayedComponents: [.date]
                        )
                    }
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
#if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
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
