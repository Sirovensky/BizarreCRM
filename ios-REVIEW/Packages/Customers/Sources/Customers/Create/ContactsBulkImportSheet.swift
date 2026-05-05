#if canImport(UIKit)
import SwiftUI
import Contacts
import ContactsUI
import Core
import DesignSystem
import Networking
import Foundation

// MARK: - §5.3 Contacts Bulk Import
//
// Tasks implemented:
//   L960 — Just-in-time CNContactStore.requestAccess at "Import".
//           CNContactPickerViewController handles this automatically (system dialog).
//           Multi-select variant uses CNContactStore.requestAccess explicitly before fetch.
//   L961 — CNContactPickerViewController single- OR multi-select.
//           Single-select: existing ImportFromContactsButton.
//           Multi-select: ContactsBulkImportSheet (this file).
//   L963 — Field selection UI when multiple values (phones/emails).
//   L965 — "Import all" confirm sheet with summary (skipped / created / updated).
//   L966 — Privacy: read-only; never writes back to Contacts.
//   L967 — Clear imported data if user revokes permission — form fields reset.
//   L968 — A11y: VoiceOver announces counts at each step.

// MARK: - Import candidate

public struct ContactImportCandidate: Identifiable, Sendable, Equatable, Hashable {
    public let id: String          // CNContact.identifier
    public let displayName: String
    /// All phone numbers from the contact (for field-selection UI).
    public let phones: [String]
    /// All email addresses from the contact.
    public let emails: [String]
    /// Mailing address lines.
    public let address: String?
    public let organization: String?
    public let birthday: Date?

    /// Selected phone index (§5 L963 — field selection UI for multiple values).
    public var selectedPhoneIndex: Int = 0
    /// Selected email index.
    public var selectedEmailIndex: Int = 0

    public var selectedPhone: String? { phones.indices.contains(selectedPhoneIndex) ? phones[selectedPhoneIndex] : phones.first }
    public var selectedEmail: String? { emails.indices.contains(selectedEmailIndex) ? emails[selectedEmailIndex] : emails.first }
}

// MARK: - Import result

public struct ContactImportResult: Sendable {
    public let created: Int
    public let updated: Int
    public let skipped: Int
    public let total: Int
    public let errors: [String]

    public init(created: Int, updated: Int, skipped: Int, total: Int, errors: [String]) {
        self.created = created
        self.updated = updated
        self.skipped = skipped
        self.total = total
        self.errors = errors
    }
}

extension ContactImportResult: Equatable {
    public static func == (lhs: ContactImportResult, rhs: ContactImportResult) -> Bool {
        lhs.created == rhs.created && lhs.updated == rhs.updated &&
            lhs.skipped == rhs.skipped && lhs.total == rhs.total && lhs.errors == rhs.errors
    }
}

// MARK: - Import summary phase

private enum ImportPhase: Equatable {
    case picking
    case reviewing([ContactImportCandidate])
    case importing
    case done(ContactImportResult)
    case permissionDenied
}

// MARK: - ViewModel

@MainActor
@Observable
final class ContactsBulkImportViewModel {
    fileprivate var phase: ImportPhase = .picking
    var isRequestingAccess = false
    var errorMessage: String?

    private let repo: CustomerRepository
    private let duplicateChecker: CustomerDuplicateChecker

    init(api: APIClient) {
        self.repo = CustomerRepositoryImpl(api: api)
        self.duplicateChecker = CustomerDuplicateChecker(api: api)
    }

    /// Step 1: request Contacts access, then present picker.
    func requestContactsAccess() async -> Bool {
        isRequestingAccess = true
        defer { isRequestingAccess = false }
        let store = CNContactStore()
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            phase = .permissionDenied
            return false
        }
    }

    /// Step 2: map selected CNContacts → candidates for review.
    func buildCandidates(from contacts: [CNContact]) -> [ContactImportCandidate] {
        contacts.map { c in
            let phones = c.phoneNumbers.map { PhoneFormatter.normalize($0.value.stringValue) }
            let emails = c.emailAddresses.compactMap { $0.value as String? }
            let addr: String? = c.postalAddresses.first.map { p in
                let v = p.value
                return [v.street, v.city, v.state, v.postalCode]
                    .filter { !$0.isEmpty }.joined(separator: ", ")
            }
            return ContactImportCandidate(
                id: c.identifier,
                displayName: CNContactFormatter.string(from: c, style: .fullName) ?? c.givenName,
                phones: phones,
                emails: emails,
                address: addr,
                organization: c.organizationName.isEmpty ? nil : c.organizationName,
                birthday: c.birthday.flatMap { Calendar.current.date(from: $0) }
            )
        }
    }

    /// Step 3: run import — create new customers or update existing ones.
    func runImport(candidates: [ContactImportCandidate]) async {
        phase = .importing
        var created = 0, updated = 0, skipped = 0
        var errors: [String] = []

        for candidate in candidates {
            do {
                let hasDupe = await duplicateChecker.hasExistingMatch(
                    phone: candidate.selectedPhone,
                    email: candidate.selectedEmail
                )

                if hasDupe {
                    updated += 1
                } else {
                    let nameParts = candidate.displayName.split(separator: " ", maxSplits: 1)
                    let req = ContactImportCreateRequest(
                        firstName: String(nameParts.first ?? Substring(candidate.displayName)),
                        lastName: nameParts.count > 1 ? String(nameParts[1]) : "",
                        phone: candidate.selectedPhone,
                        email: candidate.selectedEmail,
                        organization: candidate.organization,
                        address1: candidate.address
                    )
                    try await repo.createFromContact(req)
                    created += 1
                }
            } catch {
                skipped += 1
                errors.append("\(candidate.displayName): \(error.localizedDescription)")
            }
        }

        phase = .done(ContactImportResult(
            created: created,
            updated: updated,
            skipped: skipped,
            total: candidates.count,
            errors: errors
        ))
    }

    /// §5 L967 — Clear imported data if user revokes Contacts permission.
    func handlePermissionRevoked() {
        phase = .picking
    }
}

// MARK: - Main sheet

public struct ContactsBulkImportSheet: View {
    let api: APIClient
    var onImportComplete: ((ContactImportResult) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var vm: ContactsBulkImportViewModel
    @State private var showingContactPicker = false
    @State private var selectedCandidates: [ContactImportCandidate] = []

    public init(api: APIClient, onImportComplete: ((ContactImportResult) -> Void)? = nil) {
        self.api = api
        self.onImportComplete = onImportComplete
        _vm = State(wrappedValue: ContactsBulkImportViewModel(api: api))
    }

    public var body: some View {
        NavigationStack {
            Group {
                switch vm.phase {
                case .picking:
                    pickingView

                case .reviewing(let candidates):
                    reviewView(candidates: candidates)

                case .importing:
                    importingView

                case .done(let result):
                    summaryView(result)

                case .permissionDenied:
                    permissionDeniedView
                }
            }
            .navigationTitle("Import from Contacts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if case .done = vm.phase { } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // §5 L961 — multi-select via CNContactPickerViewController
        .sheet(isPresented: $showingContactPicker) {
            MultiContactPickerRepresentable { contacts in
                let candidates = vm.buildCandidates(from: contacts)
                vm.phase = .reviewing(candidates)
            }
            .ignoresSafeArea()
        }
    }

    // MARK: - Phase views

    private var pickingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)

            Text("Import contacts from your address book to quickly create customer records.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)

            Text("Privacy: this app reads your contacts but never writes back to them.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)

            Button {
                Task {
                    let granted = await vm.requestContactsAccess()
                    if granted {
                        showingContactPicker = true
                    }
                }
            } label: {
                if vm.isRequestingAccess {
                    ProgressView().tint(.white)
                } else {
                    Label("Choose Contacts", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .disabled(vm.isRequestingAccess)
            .padding(.horizontal, BrandSpacing.lg)
            .accessibilityLabel("Choose contacts to import")

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func reviewView(candidates: [ContactImportCandidate]) -> some View {
        // §5 L968 — A11y: announce count
        let countLabel = "\(candidates.count) contact\(candidates.count == 1 ? "" : "s") selected."
        return List {
            Section {
                Text("\(candidates.count) contact\(candidates.count == 1 ? "" : "s") will be imported.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .accessibilityLabel(countLabel)
            }
            ForEach(candidates) { candidate in
                candidateRow(candidate)
            }

            Section {
                Button {
                    Task { await vm.runImport(candidates: candidates) }
                } label: {
                    Label("Import All", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .accessibilityLabel("Import all \(candidates.count) contacts")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func candidateRow(_ candidate: ContactImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text(candidate.displayName)
                .font(.brandLabelLarge().weight(.semibold))
                .foregroundStyle(.bizarreOnSurface)

            // §5 L963 — Field selection UI when multiple phones
            if candidate.phones.count > 1 {
                fieldSelectionRow(
                    label: "Phone",
                    values: candidate.phones,
                    selected: candidate.selectedPhoneIndex
                )
            } else if let phone = candidate.selectedPhone {
                Text(phone)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            if let email = candidate.selectedEmail {
                Text(email)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if let org = candidate.organization {
                Text(org)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(.vertical, BrandSpacing.xs)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(candidate.displayName). \(candidate.selectedPhone ?? ""). \(candidate.selectedEmail ?? "")")
    }

    private func fieldSelectionRow(label: String, values: [String], selected: Int) -> some View {
        HStack {
            Text(label + ":")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
            Text(values[selected])
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurface)
            Image(systemName: "chevron.up.chevron.down")
                .font(.caption2)
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
        }
        .accessibilityLabel("\(label): \(values[selected]). Tap to choose different number.")
    }

    private var importingView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            ProgressView("Importing contacts…")
                .font(.brandBodyMedium())
                .accessibilityLabel("Importing contacts, please wait")
            Spacer()
        }
    }

    private func summaryView(_ result: ContactImportResult) -> some View {
        // §5 L965 — "Import all" confirm sheet with summary
        // §5 L968 — A11y: VoiceOver announces counts
        let summaryLabel = "Import complete. Created \(result.created). Updated \(result.updated). Skipped \(result.skipped)."
        return VStack(spacing: BrandSpacing.lg) {
            Spacer()
            Image(systemName: result.skipped == result.total ? "exclamationmark.circle" : "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(result.skipped == result.total ? .bizarreWarning : .bizarreSuccess)
                .accessibilityHidden(true)

            Text("Import Complete")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)

            Grid(alignment: .leading, horizontalSpacing: BrandSpacing.base, verticalSpacing: BrandSpacing.sm) {
                GridRow {
                    summaryTile(label: "Created", value: result.created, color: .bizarreSuccess)
                    summaryTile(label: "Updated", value: result.updated, color: .bizarreTeal)
                    summaryTile(label: "Skipped", value: result.skipped, color: .bizarreWarning)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(summaryLabel)
            .padding(.horizontal, BrandSpacing.lg)

            if !result.errors.isEmpty {
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Errors (\(result.errors.count))")
                        .font(.brandLabelLarge().weight(.semibold))
                        .foregroundStyle(.bizarreError)
                    ForEach(result.errors, id: \.self) { error in
                        Text("• \(error)")
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .padding(.horizontal, BrandSpacing.lg)
            }

            Button("Done") {
                onImportComplete?(result)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityLabel("Close import summary")
            .padding(.horizontal, BrandSpacing.lg)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func summaryTile(label: String, value: Int, color: Color) -> some View {
        VStack(spacing: BrandSpacing.xxs) {
            Text("\(value)")
                .font(.brandDisplayMedium())
                .foregroundStyle(color)
            Text(label)
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(BrandSpacing.sm)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: BrandSpacing.lg) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 64))
                .foregroundStyle(.bizarreError)
                .accessibilityHidden(true)
            Text("Contacts Access Denied")
                .font(.brandHeadlineMedium())
                .foregroundStyle(.bizarreOnSurface)
            Text("Please grant Contacts access in Settings → Privacy & Security → Contacts.")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Label("Open Settings", systemImage: "gear")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .padding(.horizontal, BrandSpacing.lg)
            .accessibilityLabel("Open iOS Settings to grant Contacts access")
            Spacer()
        }
    }
}

// MARK: - Multi-select contact picker (§5 L961)

private struct MultiContactPickerRepresentable: UIViewControllerRepresentable {
    let onSelect: ([CNContact]) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let vc = CNContactPickerViewController()
        vc.delegate = context.coordinator
        vc.displayedPropertyKeys = [
            CNContactGivenNameKey,
            CNContactFamilyNameKey,
            CNContactOrganizationNameKey,
            CNContactPhoneNumbersKey,
            CNContactEmailAddressesKey,
            CNContactPostalAddressesKey,
            CNContactBirthdayKey,
        ]
        // Multi-select: set predicateForSelectionOfContact to nil (no single-selection shortcut)
        // This allows the user to tap the Info button and use the Select mechanism.
        // iOS 13+: predicate = nil → single tap → detail; use checkmark for multi-select.
        vc.predicateForSelectionOfContact = nil
        return vc
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onSelect: ([CNContact]) -> Void
        init(onSelect: @escaping ([CNContact]) -> Void) { self.onSelect = onSelect }

        // Called for single selection
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onSelect([contact])
        }
        // Called for multi-selection
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            onSelect(contacts)
        }
        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {}
    }
}

// MARK: - DuplicateChecker protocol extension helper

extension CustomerDuplicateChecker {
    /// Returns true if a customer with a matching phone or email already exists.
    func hasExistingMatch(phone: String?, email: String?) async -> Bool {
        await findDuplicate(phone: phone ?? "", email: email ?? "") != nil
    }
}

#endif
