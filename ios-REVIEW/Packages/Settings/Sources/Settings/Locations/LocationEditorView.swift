import SwiftUI
import Core
import DesignSystem

// MARK: - §60.2 LocationEditorView

public struct LocationEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let location: Location?     // nil → create mode
    let repo: any LocationRepository
    let onSave: (Location) -> Void

    @State private var name: String = ""
    @State private var addressLine1: String = ""
    @State private var addressLine2: String = ""
    @State private var city: String = ""
    @State private var region: String = ""
    @State private var postal: String = ""
    @State private var country: String = "US"
    @State private var phone: String = ""
    @State private var timezone: String = TimeZone.current.identifier
    @State private var taxRateId: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil

    private var isEditMode: Bool { location != nil }

    public init(location: Location?, repo: any LocationRepository, onSave: @escaping (Location) -> Void) {
        self.location = location
        self.repo = repo
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Location name", text: $name)
                        .accessibilityLabel("Location name")
                    TextField("Timezone", text: $timezone)
                        .accessibilityLabel("Timezone")
                    TextField("Tax rate ID (optional)", text: $taxRateId)
                        .accessibilityLabel("Tax rate ID")
                }

                Section("Address") {
                    TextField("Address line 1", text: $addressLine1)
                        .accessibilityLabel("Address line 1")
                    TextField("Address line 2 (optional)", text: $addressLine2)
                        .accessibilityLabel("Address line 2")
                    TextField("City", text: $city)
                        .accessibilityLabel("City")
                    TextField("State / Province", text: $region)
                        .accessibilityLabel("Region")
                    TextField("Postal code", text: $postal)
                        .accessibilityLabel("Postal code")
                    TextField("Country", text: $country)
                        .accessibilityLabel("Country")
                }

                Section("Contact") {
                    TextField("Phone", text: $phone)
                        #if canImport(UIKit)
                        .keyboardType(.phonePad)
                        #endif
                        .accessibilityLabel("Phone number")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.bizarreError)
                            .accessibilityLabel("Error: \(errorMessage)")
                    }
                }
            }
            .navigationTitle(isEditMode ? "Edit Location" : "New Location")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityLabel("Cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || name.isEmpty || addressLine1.isEmpty)
                    .accessibilityLabel("Save location")
                }
            }
            .onAppear(perform: populateFields)
        }
    }

    // MARK: Private

    private func populateFields() {
        guard let loc = location else { return }
        name = loc.name
        addressLine1 = loc.addressLine1
        addressLine2 = loc.addressLine2 ?? ""
        city = loc.city
        region = loc.region
        postal = loc.postal
        country = loc.country
        phone = loc.phone
        timezone = loc.timezone
        taxRateId = loc.taxRateId ?? ""
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            let saved: Location
            if let existing = location {
                saved = try await repo.updateLocation(
                    id: existing.id,
                    request: UpdateLocationRequest(
                        name: name,
                        addressLine1: addressLine1,
                        addressLine2: addressLine2.isEmpty ? nil : addressLine2,
                        city: city,
                        region: region,
                        postal: postal,
                        country: country,
                        phone: phone,
                        timezone: timezone,
                        taxRateId: taxRateId.isEmpty ? nil : taxRateId
                    )
                )
            } else {
                saved = try await repo.createLocation(
                    CreateLocationRequest(
                        name: name,
                        addressLine1: addressLine1,
                        addressLine2: addressLine2.isEmpty ? nil : addressLine2,
                        city: city,
                        region: region,
                        postal: postal,
                        country: country,
                        phone: phone,
                        timezone: timezone,
                        taxRateId: taxRateId.isEmpty ? nil : taxRateId
                    )
                )
            }
            onSave(saved)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
