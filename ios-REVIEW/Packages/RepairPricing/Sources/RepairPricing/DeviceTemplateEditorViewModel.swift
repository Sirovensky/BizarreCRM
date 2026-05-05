import Foundation
import Observation
import Networking

// MARK: - §43.5 Device Template Editor ViewModel

@MainActor
@Observable
public final class DeviceTemplateEditorViewModel {

    // MARK: - Form state
    public var name: String = ""
    public var family: String = ""
    public var customFamily: String = ""
    public var isCustomFamily: Bool = false
    public var year: String = ""
    public var selectedConditionIds: Set<String> = []
    public var inlineServices: [InlineService] = []

    // MARK: - Available families
    public var availableFamilies: [String] = []

    // MARK: - Save / load state
    public private(set) var isSaving: Bool = false
    public private(set) var validationErrors: [DeviceTemplateValidator.ValidationError] = []
    public private(set) var saveError: String?
    public private(set) var savedTemplate: DeviceTemplate?

    // MARK: - Computed

    public var effectiveFamily: String {
        isCustomFamily ? customFamily : family
    }

    public var isEditing: Bool { editingId != nil }

    // MARK: - Private
    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private let editingId: Int64?

    /// `editingId == nil` → Create; `editingId != nil` → Update.
    public init(api: APIClient, editingTemplate: DeviceTemplate? = nil) {
        self.api = api
        self.editingId = editingTemplate?.id
        if let t = editingTemplate {
            self.name = t.name
            self.family = t.family ?? ""
            self.year = ""  // server doesn't expose year yet
            self.selectedConditionIds = Set(t.conditions)
        }
    }

    // MARK: - Load families from catalog

    public func loadFamilies() async {
        do {
            let templates = try await api.listDeviceTemplates()
            var seen = Set<String>()
            availableFamilies = templates
                .compactMap { $0.family }
                .filter { !$0.isEmpty && seen.insert($0).inserted }
        } catch {
            // Non-critical — form still works with empty list
        }
    }

    // MARK: - Inline services (immutable pattern)

    public func addInlineService() {
        inlineServices = inlineServices + [InlineService()]
    }

    public func removeInlineService(at index: Int) {
        guard inlineServices.indices.contains(index) else { return }
        var updated = inlineServices
        updated.remove(at: index)
        inlineServices = updated
    }

    public func updateInlineService(at index: Int, name: String? = nil, rawPrice: String? = nil, description: String? = nil) {
        guard inlineServices.indices.contains(index) else { return }
        var updated = inlineServices
        let s = updated[index]
        updated[index] = InlineService(
            name: name ?? s.name,
            rawPrice: rawPrice ?? s.rawPrice,
            description: description ?? s.description
        )
        inlineServices = updated
    }

    // MARK: - Condition toggle (immutable)

    public func toggleCondition(_ conditionId: String) {
        var updated = selectedConditionIds
        if updated.contains(conditionId) {
            updated.remove(conditionId)
        } else {
            updated.insert(conditionId)
        }
        selectedConditionIds = updated
    }

    // MARK: - Save

    public func save() async {
        saveError = nil
        let fam = effectiveFamily
        let errors = DeviceTemplateValidator.validate(
            name: name,
            family: fam,
            inlineServices: inlineServices
        )
        validationErrors = errors
        guard errors.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let serviceRequests = inlineServices.compactMap { svc -> InlineServiceRequest? in
            guard let cents = svc.priceCents else { return nil }
            return InlineServiceRequest(
                serviceName: svc.name.trimmingCharacters(in: .whitespacesAndNewlines),
                defaultPriceCents: cents,
                description: svc.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : svc.description
            )
        }

        let conditions = DeviceCondition.allCases
            .filter { selectedConditionIds.contains($0.id) }
            .map { $0.label }

        let yearInt = Int(year.trimmingCharacters(in: .whitespacesAndNewlines))

        do {
            if let editId = editingId {
                let req = UpdateDeviceTemplateRequest(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    deviceCategory: fam.trimmingCharacters(in: .whitespacesAndNewlines),
                    deviceModel: nil,
                    year: yearInt,
                    conditions: conditions,
                    services: serviceRequests
                )
                savedTemplate = try await api.updateDeviceTemplate(id: editId, body: req)
            } else {
                let req = CreateDeviceTemplateRequest(
                    name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                    deviceCategory: fam.trimmingCharacters(in: .whitespacesAndNewlines),
                    deviceModel: nil,
                    year: yearInt,
                    conditions: conditions,
                    services: serviceRequests
                )
                savedTemplate = try await api.createDeviceTemplate(body: req)
            }
        } catch {
            saveError = error.localizedDescription
        }
    }
}
