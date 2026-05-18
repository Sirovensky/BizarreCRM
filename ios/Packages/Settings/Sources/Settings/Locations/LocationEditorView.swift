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
                    // USABILITY-2026-05-18: textContentType lets iOS Autofill
                    // suggest matching address-book entries and route the
                    // postal-code field to a digits-leaning keyboard instead
                    // of the default alphabetic one (BusinessProfile +
                    // CompanyInfo already do this — LocationEditor was the
                    // outlier).
                    TextField("Address line 1", text: $addressLine1)
                        #if canImport(UIKit)
                        .textContentType(.streetAddressLine1)
                        #endif
                        .accessibilityLabel("Address line 1")
                    TextField("Address line 2 (optional)", text: $addressLine2)
                        #if canImport(UIKit)
                        .textContentType(.streetAddressLine2)
                        #endif
                        .accessibilityLabel("Address line 2")
                    TextField("City", text: $city)
                        #if canImport(UIKit)
                        .textContentType(.addressCity)
                        #endif
                        .accessibilityLabel("City")
                    TextField("State / Province", text: $region)
                        #if canImport(UIKit)
                        .textContentType(.addressState)
                        #endif
                        .accessibilityLabel("Region")
                    TextField("Postal code", text: $postal)
                        #if canImport(UIKit)
                        .textContentType(.postalCode)
                        .keyboardType(.numbersAndPunctuation)
                        #endif
                        .accessibilityLabel("Postal code")
                    TextField("Country", text: $country)
                        #if canImport(UIKit)
                        .textContentType(.countryName)
                        #endif
                        .accessibilityLabel("Country")
                }

                Section("Contact") {
                    TextField("Phone", text: $phone)
                        #if canImport(UIKit)
                        .textContentType(.telephoneNumber)
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
        // BUGHUNT-2026-05-17: re-entry guard — primary action stays
        // enabled until SwiftUI redraws on `isSaving=true`. Two rapid
        // taps would otherwise fire two parallel create/update calls.
        guard !isSaving else { return }
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
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: location create POST has no idempotency
            // key. A cancellation banner tempted retap that — if the
            // server accepted the first POST — created a duplicate
            // location row (two physical stores with identical address
            // confuses inventory transfers and tax routing).
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
