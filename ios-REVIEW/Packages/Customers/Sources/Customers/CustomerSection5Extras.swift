#if canImport(UIKit)
import SwiftUI
import UniformTypeIdentifiers
import Core
import DesignSystem
import Networking

// MARK: - §5 CSV Import Upload UI
//
// Lets staff pick a CSV file (from Files, iCloud Drive, etc.) or paste raw
// text, then previews the first rows and POSTs to
// `POST /api/v1/customers/import-csv`.

// MARK: CSV import request / result

/// `POST /api/v1/customers/import-csv` request body.
public struct CustomerImportCSVRequest: Encodable, Sendable {
    public let csvData: String
    public init(csvData: String) { self.csvData = csvData }
    enum CodingKeys: String, CodingKey { case csvData = "csv_data" }
}

/// Response from `POST /api/v1/customers/import-csv`.
public struct CustomerImportCSVResult: Decodable, Sendable {
    public let imported: Int
    public let errors: [CustomerImportCSVRowError]
    public init(imported: Int, errors: [CustomerImportCSVRowError]) {
        self.imported = imported; self.errors = errors
    }
}

public struct CustomerImportCSVRowError: Decodable, Sendable, Identifiable {
    public var id: Int { row }
    public let row: Int
    public let message: String
}

public extension APIClient {
    /// `POST /api/v1/customers/import-csv` — send raw CSV body.
    @discardableResult
    func importCustomersCSV(_ request: CustomerImportCSVRequest) async throws -> CustomerImportCSVResult {
        try await post("/api/v1/customers/import-csv",
                       body: request,
                       as: CustomerImportCSVResult.self)
    }
}

// MARK: CSV parser helper

enum CustomerCSVParser {
    struct Row: Identifiable {
        let id: Int
        let firstName: String
        let lastName: String
        let email: String
        let phone: String
        let organization: String
    }

    /// Parse a RFC-4180 CSV string into preview rows (up to `limit`).
    /// Expected header (case-insensitive): first_name,last_name,email,phone,organization
    static func parse(_ csv: String, limit: Int = 5) -> [Row] {
        var lines = csv.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }
        let header = lines.removeFirst()
            .lowercased()
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }

        func idx(_ keys: [String]) -> Int? { keys.compactMap { header.firstIndex(of: $0) }.first }
        let fnIdx  = idx(["first_name", "firstname", "first"])
        let lnIdx  = idx(["last_name",  "lastname",  "last"])
        let emIdx  = idx(["email"])
        let phIdx  = idx(["phone", "mobile"])
        let orgIdx = idx(["organization", "company"])

        return lines.prefix(limit).enumerated().map { (i, line) in
            let fields = splitCSVLine(line)
            func f(_ index: Int?) -> String {
                guard let index, index < fields.count else { return "" }
                return fields[index]
            }
            return Row(id: i + 2,
                       firstName: f(fnIdx),
                       lastName: f(lnIdx),
                       email: f(emIdx),
                       phone: f(phIdx),
                       organization: f(orgIdx))
        }
    }

    /// Minimal RFC-4180 field splitter (handles quoted fields).
    private static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var chars = line.makeIterator()
        while let ch = chars.next() {
            if ch == "\"" {
                inQuotes.toggle()
            } else if ch == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}

// MARK: CustomerCSVImportSheet

/// Sheet presented from the customer list toolbar that lets staff
/// import customers from a CSV file.
public struct CustomerCSVImportSheet: View {
    let api: APIClient
    var onComplete: (() -> Void)?

    @State private var phase: Phase = .pick
    @State private var rawCSV: String = ""
    @State private var previewRows: [CustomerCSVParser.Row] = []
    @State private var isImporting = false
    @State private var importResult: CustomerImportCSVResult?
    @State private var importError: String?
    @State private var showingFilePicker = false
    @Environment(\.dismiss) private var dismiss

    enum Phase { case pick, preview, result }

    public init(api: APIClient, onComplete: (() -> Void)? = nil) {
        self.api = api
        self.onComplete = onComplete
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                switch phase {
                case .pick:    pickView
                case .preview: previewView
                case .result:  resultView
                }
            }
            .navigationTitle("Import Customers from CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("customerCSVImport.cancel")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [UTType.commaSeparatedText, UTType.plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFilePickerResult(result)
        }
    }

    // MARK: - Pick phase

    private var pickView: some View {
        ScrollView {
            VStack(spacing: BrandSpacing.lg) {
                Image(systemName: "tablecells.badge.ellipsis")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)

                VStack(spacing: BrandSpacing.xs) {
                    Text("Import from CSV")
                        .font(.brandTitleMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Pick a CSV file or paste text below. The file must include a header row with columns: first_name, last_name, email, phone, organization.")
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, BrandSpacing.lg)

                Button {
                    showingFilePicker = true
                } label: {
                    Label("Choose File…", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityIdentifier("customerCSVImport.pickFile")

                Text("— or paste CSV text —")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)

                TextEditor(text: $rawCSV)
                    .font(.brandMono(size: 13))
                    .frame(minHeight: 120)
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5)
                    )
                    .padding(.horizontal, BrandSpacing.base)
                    .accessibilityLabel("Paste CSV text here")
                    .accessibilityIdentifier("customerCSVImport.pasteField")

                Button {
                    advanceToPreview()
                } label: {
                    Label("Preview Import", systemImage: "eye")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreTeal)
                .disabled(rawCSV.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, BrandSpacing.base)
                .accessibilityIdentifier("customerCSVImport.preview")
            }
            .padding(.vertical, BrandSpacing.lg)
        }
    }

    // MARK: - Preview phase

    private var previewView: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.md) {
            Text("Preview (first \(previewRows.count) row\(previewRows.count == 1 ? "" : "s"))")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .padding(.horizontal, BrandSpacing.base)
                .padding(.top, BrandSpacing.md)

            ScrollView {
                VStack(spacing: BrandSpacing.xs) {
                    ForEach(previewRows) { row in
                        previewRowCard(row)
                    }
                }
                .padding(.horizontal, BrandSpacing.base)
            }

            Spacer(minLength: 0)

            HStack(spacing: BrandSpacing.md) {
                Button("Back") {
                    phase = .pick
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("customerCSVImport.back")

                Button {
                    Task { await runImport() }
                } label: {
                    if isImporting {
                        ProgressView().tint(.white)
                    } else {
                        Label("Import All", systemImage: "square.and.arrow.down")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
                .disabled(isImporting)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("customerCSVImport.confirm")
            }
            .padding(BrandSpacing.base)
        }
    }

    private func previewRowCard(_ row: CustomerCSVParser.Row) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            HStack {
                Text("Row \(row.id)")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                Spacer()
            }
            if !row.firstName.isEmpty || !row.lastName.isEmpty {
                Text([row.firstName, row.lastName].filter { !$0.isEmpty }.joined(separator: " "))
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
            }
            if !row.email.isEmpty {
                Label(row.email, systemImage: "envelope")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if !row.phone.isEmpty {
                Label(row.phone, systemImage: "phone")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            if !row.organization.isEmpty {
                Label(row.organization, systemImage: "building.2")
                    .font(.brandLabelLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
        .padding(BrandSpacing.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Row \(row.id): \([row.firstName, row.lastName].filter { !$0.isEmpty }.joined(separator: " "))")
    }

    // MARK: - Result phase

    private var resultView: some View {
        VStack(spacing: BrandSpacing.lg) {
            if let result = importResult {
                Image(systemName: result.errors.isEmpty
                      ? "checkmark.circle.fill"
                      : "exclamationmark.triangle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(result.errors.isEmpty ? .bizarreTeal : .bizarreWarning)
                    .accessibilityHidden(true)

                Text("Imported \(result.imported) customer\(result.imported == 1 ? "" : "s")")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)

                if !result.errors.isEmpty {
                    VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                        Text("\(result.errors.count) row\(result.errors.count == 1 ? "" : "s") with errors:")
                            .font(.brandLabelLarge())
                            .foregroundStyle(.bizarreError)
                        ForEach(result.errors) { err in
                            Text("Row \(err.row): \(err.message)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreError.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal, BrandSpacing.base)
                }
            } else if let err = importError {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.bizarreError)
                    .accessibilityHidden(true)
                Text("Import failed")
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Text(err)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, BrandSpacing.lg)
            }

            Button("Done") {
                onComplete?()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(.bizarreOrange)
            .accessibilityIdentifier("customerCSVImport.done")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func handleFilePickerResult(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            // Security-scoped resource access
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                rawCSV = text
                advanceToPreview()
            } else if let text = try? String(contentsOf: url, encoding: .isoLatin1) {
                rawCSV = text
                advanceToPreview()
            }
        case .failure(let err):
            importError = err.localizedDescription
            phase = .result
        }
    }

    private func advanceToPreview() {
        previewRows = CustomerCSVParser.parse(rawCSV)
        phase = .preview
    }

    private func runImport() async {
        isImporting = true
        defer { isImporting = false }
        do {
            let result = try await api.importCustomersCSV(
                CustomerImportCSVRequest(csvData: rawCSV)
            )
            importResult = result
        } catch {
            importError = error.localizedDescription
        }
        phase = .result
    }
}

// MARK: - §5 Family-member relationship link sheet
//
// Replaces the "coming soon" placeholder in CustomerRelatedCustomersCard.
// Lets staff search for a customer by name / phone and pick a relationship type.

public struct CustomerLinkRelationshipSheet: View {
    let customerId: Int64
    let api: APIClient
    var onLinked: (() -> Void)?

    @State private var searchText = ""
    @State private var results: [CustomerSummary] = []
    @State private var selectedCustomer: CustomerSummary?
    @State private var relType: CustomerRelationship.RelationshipType = .family
    @State private var isSearching = false
    @State private var isSubmitting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    public init(customerId: Int64, api: APIClient, onLinked: (() -> Void)? = nil) {
        self.customerId = customerId
        self.api = api
        self.onLinked = onLinked
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.bizarreSurfaceBase.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchBar
                    if isSearching {
                        ProgressView().padding(.top, BrandSpacing.lg)
                        Spacer()
                    } else if !results.isEmpty {
                        resultsList
                    } else if !searchText.isEmpty {
                        noResultsState
                    } else {
                        promptState
                    }
                }
            }
            .navigationTitle("Link Related Customer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("customerLinkRelationship.cancel")
                }
                if selectedCustomer != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            Task { await submitLink() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text("Link")
                                    .fontWeight(.semibold)
                            }
                        }
                        .disabled(isSubmitting)
                        .accessibilityIdentifier("customerLinkRelationship.submit")
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Subviews

    private var searchBar: some View {
        HStack(spacing: BrandSpacing.sm) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            TextField("Search by name or phone…", text: $searchText)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .onChange(of: searchText) { _, q in
                    Task { await search(query: q) }
                }
                .accessibilityLabel("Search customers")
                .accessibilityIdentifier("customerLinkRelationship.search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    results = []
                    selectedCustomer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
        .padding(BrandSpacing.base)
    }

    private var resultsList: some View {
        ScrollView {
            VStack(spacing: 0) {
                if let sel = selectedCustomer {
                    selectedCustomerCard(sel)
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.bottom, BrandSpacing.sm)
                }
                ForEach(results.filter { $0.id != customerId }) { customer in
                    Button {
                        selectedCustomer = customer
                    } label: {
                        HStack(spacing: BrandSpacing.sm) {
                            // Avatar
                            ZStack {
                                Circle().fill(Color.bizarreOrangeContainer)
                                Text(customer.initials)
                                    .font(.brandLabelLarge())
                                    .foregroundStyle(.bizarreOnOrange)
                            }
                            .frame(width: 36, height: 36)
                            .accessibilityHidden(true)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(customer.displayName)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                if let line = customer.contactLine {
                                    Text(line)
                                        .font(.brandLabelSmall())
                                        .foregroundStyle(.bizarreOnSurfaceMuted)
                                }
                            }

                            Spacer(minLength: 0)

                            if selectedCustomer?.id == customer.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.bizarreOrange)
                                    .accessibilityLabel("Selected")
                            }
                        }
                        .padding(.horizontal, BrandSpacing.base)
                        .padding(.vertical, BrandSpacing.sm)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hoverEffect(.highlight)
                    .accessibilityLabel("\(customer.displayName)\(selectedCustomer?.id == customer.id ? ", selected" : "")")
                    Divider().padding(.leading, BrandSpacing.base + 36 + BrandSpacing.sm)
                }
            }
        }
    }

    private func selectedCustomerCard(_ customer: CustomerSummary) -> some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            HStack {
                Text("Linking: \(customer.displayName)")
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
            }

            Text("Relationship type")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: BrandSpacing.xs) {
                    ForEach(
                        [CustomerRelationship.RelationshipType.family,
                         .household, .coworker, .business, .referral, .other],
                        id: \.self
                    ) { type in
                        Button {
                            relType = type
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: type.icon)
                                    .font(.caption)
                                Text(type.label)
                                    .font(.brandLabelLarge())
                            }
                            .padding(.horizontal, BrandSpacing.sm)
                            .padding(.vertical, BrandSpacing.xs)
                            .foregroundStyle(relType == type ? .white : .bizarreOnSurface)
                            .background(
                                relType == type
                                    ? Color.bizarreOrange
                                    : Color.bizarreSurface2,
                                in: Capsule()
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(type.label)\(relType == type ? ", selected" : "")")
                        .accessibilityAddTraits(relType == type ? [.isSelected] : [])
                    }
                }
                .padding(.horizontal, 2)
            }

            if let err = error {
                Text(err)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
            }
        }
        .padding(BrandSpacing.sm)
        .background(Color.bizarreOrange.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Color.bizarreOrange.opacity(0.25), lineWidth: 0.5))
    }

    private var promptState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityHidden(true)
            Text("Search for a customer to link")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noResultsState: some View {
        VStack(spacing: BrandSpacing.sm) {
            Text("No customers matching \"\(searchText)\"")
                .font(.brandBodyMedium())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, BrandSpacing.lg)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Actions

    private func search(query: String) async {
        guard query.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        defer { isSearching = false }
        results = (try? await api.listCustomers(keyword: query, pageSize: 20).customers) ?? []
    }

    private func submitLink() async {
        guard let target = selectedCustomer else { return }
        isSubmitting = true
        defer { isSubmitting = false }
        error = nil
        do {
            try await api.linkCustomerRelationship(
                customerId: customerId,
                relatedCustomerId: target.id,
                relationshipType: relType
            )
            onLinked?()
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - APIClient extension for relationship link

public struct CustomerRelationshipLinkRequest: Encodable, Sendable {
    public let relatedCustomerId: Int64
    public let relationshipType: String
    enum CodingKeys: String, CodingKey {
        case relatedCustomerId = "related_customer_id"
        case relationshipType  = "relationship_type"
    }
}

private struct CustomerRelationshipLinkResponse: Decodable, Sendable {}

public extension APIClient {
    /// `POST /api/v1/customers/:id/relationships` — link two customers.
    func linkCustomerRelationship(
        customerId: Int64,
        relatedCustomerId: Int64,
        relationshipType: CustomerRelationship.RelationshipType
    ) async throws {
        let body = CustomerRelationshipLinkRequest(
            relatedCustomerId: relatedCustomerId,
            relationshipType: relationshipType.rawValue
        )
        _ = try await post("/api/v1/customers/\(customerId)/relationships",
                           body: body, as: CustomerRelationshipLinkResponse.self)
    }
}

// MARK: - CustomerRelatedCustomersCard update to use real link sheet
//
// Extend the existing card's "+" button behaviour via a wrapper that swaps the
// placeholder sheet for `CustomerLinkRelationshipSheet`.

public extension CustomerRelatedCustomersCard {
    /// Returns a version of the card that presents the real link sheet on "+".
    func withLinkSheet() -> some View {
        CustomerRelatedCustomersCardWithLink(
            customerId: self.customerId,
            api: self.api,
            onSelectCustomer: self.onSelectCustomer
        )
    }
}

/// Drop-in replacement for `CustomerRelatedCustomersCard` that wires the "+"
/// button to `CustomerLinkRelationshipSheet` instead of a placeholder.
public struct CustomerRelatedCustomersCardWithLink: View {
    let customerId: Int64
    let api: APIClient
    var onSelectCustomer: ((Int64) -> Void)?

    @State private var relationships: [CustomerRelationship] = []
    @State private var isLoading = true
    @State private var showingLinkSheet = false

    public init(
        customerId: Int64,
        api: APIClient,
        onSelectCustomer: ((Int64) -> Void)? = nil
    ) {
        self.customerId = customerId
        self.api = api
        self.onSelectCustomer = onSelectCustomer
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            header
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 40)
            } else if relationships.isEmpty {
                Text("No linked accounts")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(relationships) { rel in
                    relationshipRow(rel)
                    if rel.id != relationships.last?.id {
                        Divider().opacity(0.4)
                    }
                }
            }
        }
        .padding(BrandSpacing.base)
        .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))
        .task { await load() }
        .sheet(isPresented: $showingLinkSheet) {
            CustomerLinkRelationshipSheet(
                customerId: customerId,
                api: api,
                onLinked: { Task { await load() } }
            )
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("Related Accounts")
                .font(.brandTitleMedium())
                .foregroundStyle(.bizarreOnSurface)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                showingLinkSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.bizarreOrange)
            }
            .accessibilityLabel("Link a related customer")
            .accessibilityIdentifier("relatedAccounts.link")
        }
    }

    private func relationshipRow(_ rel: CustomerRelationship) -> some View {
        Button { onSelectCustomer?(rel.relatedCustomerId) } label: {
            HStack(spacing: BrandSpacing.sm) {
                ZStack {
                    Circle().fill(Color.bizarreOrangeContainer)
                    Text(String(rel.relatedCustomerName.prefix(1)).uppercased())
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreOnOrange)
                }
                .frame(width: 36, height: 36)
                .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rel.relatedCustomerName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    HStack(spacing: 4) {
                        Image(systemName: rel.relationshipType.icon)
                            .font(.caption2)
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                        Text(rel.relationshipType.label)
                            .font(.brandLabelSmall())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }

                Spacer(minLength: 0)

                if let phone = rel.relatedCustomerPhone, !phone.isEmpty {
                    Text(phone)
                        .font(.brandMono(size: 12))
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                        .monospacedDigit()
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(.highlight)
        .accessibilityLabel("\(rel.relatedCustomerName), \(rel.relationshipType.label). Tap to open.")
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        relationships = (try? await api.customerRelationships(customerId: customerId)) ?? []
    }
}

// MARK: - §5 NSItemProvider drag from customer row
//
// Conforming CustomerSummary to Transferable lets SwiftUI attach
// `.draggable` to any row, making the customer draggable to
// Shortcuts, Notes, Calendar, or other split-view panes.

extension CustomerSummary: Transferable {
    /// The plain-text drag representation is "Name\nphone\nemail" —
    /// readable by any drop target and usable in Shortcuts automations.
    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .plainText) { customer in
            var lines: [String] = [customer.displayName]
            if let phone = customer.mobile ?? customer.phone, !phone.isEmpty { lines.append(phone) }
            if let email = customer.email, !email.isEmpty { lines.append(email) }
            let text = lines.joined(separator: "\n")
            return Data(text.utf8)
        }
    }
}

/// Modifier that adds `.draggable(customer)` to any view.
/// Usage: `customerRow(...).draggableCustomer(customer)`
public struct DraggableCustomerModifier: ViewModifier {
    let customer: CustomerSummary

    public func body(content: Content) -> some View {
        content
            .draggable(customer) {
                // Drag preview: avatar circle + name label
                HStack(spacing: 8) {
                    ZStack {
                        Circle().fill(Color.bizarreOrangeContainer)
                        Text(customer.initials)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.bizarreOnOrange)
                    }
                    .frame(width: 28, height: 28)
                    Text(customer.displayName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.bizarreOnSurface)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
            }
    }
}

public extension View {
    /// Attach drag support for a `CustomerSummary` to any view.
    func draggableCustomer(_ customer: CustomerSummary) -> some View {
        modifier(DraggableCustomerModifier(customer: customer))
    }
}

// MARK: - §5 Accessibility-labelled tag chips
//
// Extends the existing `CustomerDetail.CustomerTagItem` chips with
// full VoiceOver traits: announces "Tag: {name}" and marks each chip
// with `.isStaticText` + `.isButton` (if tappable).

/// Accessible flow-layout tag chip row used in `CustomerDetailView.TagsCard`.
/// Replaces the existing `FlowTags` with proper VoiceOver labelling,
/// `accessibilityAddTraits`, and `.accessibilityValue` for color.
public struct AccessibleTagChips: View {
    let tagItems: [CustomerDetail.CustomerTagItem]
    /// Optional callback — when provided, chips are tappable (filter action).
    var onTapTag: ((String) -> Void)?

    public init(
        tagItems: [CustomerDetail.CustomerTagItem],
        onTapTag: ((String) -> Void)? = nil
    ) {
        self.tagItems = tagItems
        self.onTapTag = onTapTag
    }

    public var body: some View {
        let columns = [GridItem(.adaptive(minimum: 80), spacing: BrandSpacing.xs)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: BrandSpacing.xs) {
            ForEach(tagItems, id: \.name) { item in
                chip(item)
            }
        }
    }

    @ViewBuilder
    private func chip(_ item: CustomerDetail.CustomerTagItem) -> some View {
        let accent = item.color.flatMap { Color(hexString: $0) } ?? Color.bizarreSurface2
        let hasColor = item.color != nil
        let colorDesc = colorDescription(hex: item.color)

        if let onTapTag {
            Button { onTapTag(item.name) } label: {
                chipLabel(item.name, accent: accent, hasColor: hasColor)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Tag: \(item.name)\(colorDesc.isEmpty ? "" : ", \(colorDesc)")")
            .accessibilityHint("Tap to filter by this tag")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("customer.tag.\(item.name)")
        } else {
            chipLabel(item.name, accent: accent, hasColor: hasColor)
                .accessibilityLabel("Tag: \(item.name)\(colorDesc.isEmpty ? "" : ", \(colorDesc)")")
                .accessibilityAddTraits(.isStaticText)
                .accessibilityIdentifier("customer.tag.\(item.name)")
        }
    }

    private func chipLabel(_ name: String, accent: Color, hasColor: Bool) -> some View {
        Text(name)
            .font(.brandLabelLarge())
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .foregroundStyle(hasColor ? .white : .bizarreOnSurface)
            .background(accent.opacity(hasColor ? 0.85 : 1), in: Capsule())
    }

    /// Maps a hex color string to a human-readable color name for VoiceOver.
    private func colorDescription(hex: String?) -> String {
        guard let hex else { return "" }
        // Simple luminance-based hue bucket — good-enough for VoiceOver.
        let stripped = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard stripped.count == 6, let value = UInt32(stripped, radix: 16) else { return "" }
        let r = Double((value >> 16) & 0xFF)
        let g = Double((value >>  8) & 0xFF)
        let b = Double( value        & 0xFF)
        let max = Swift.max(r, g, b)
        let min = Swift.min(r, g, b)
        let lum = (max + min) / (2 * 255)
        if lum < 0.15 { return "dark" }
        if lum > 0.85 { return "light" }
        if r > g && r > b { return "red" }
        if g > r && g > b { return "green" }
        if b > r && b > g { return "blue" }
        if r > 180 && g > 100 && b < 80 { return "orange" }
        return ""
    }
}

// MARK: - §5 Customer-since date formatting
//
// The existing `CustomerDetailView` shows `createdAt` as a raw ISO-8601
// string prefix.  This formatter converts it to a localised, human-readable
// string, e.g. "Member since April 3, 2023".

public enum CustomerSinceDateFormatter {
    private static func makeISOFullFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }

    private static func makeISOBasicFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }

    private static func makeISODateFormatter() -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }

    private static func makeDisplayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }

    /// Parse an ISO-8601 date string (with or without time component) and
    /// return a human-readable "Member since {date}" string.
    /// Returns `nil` if the string cannot be parsed.
    public static func memberSince(_ isoString: String?) -> String? {
        guard let raw = isoString, !raw.isEmpty else { return nil }
        let date = makeISOFullFormatter().date(from: raw)
            ?? makeISOBasicFormatter().date(from: raw)
            ?? makeISODateFormatter().date(from: raw)
            ?? parsePartialDate(raw)
        guard let date else { return nil }
        return "Member since \(makeDisplayFormatter().string(from: date))"
    }

    /// Formats just the date portion for compact contexts (e.g. list subtitle).
    public static func shortDate(_ isoString: String?) -> String? {
        guard let raw = isoString, !raw.isEmpty else { return nil }
        let date = makeISOFullFormatter().date(from: raw)
            ?? makeISOBasicFormatter().date(from: raw)
            ?? makeISODateFormatter().date(from: raw)
            ?? parsePartialDate(raw)
        guard let date else { return nil }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }

    /// Fallback: try parsing the leading `YYYY-MM-DD` fragment.
    private static func parsePartialDate(_ raw: String) -> Date? {
        let fragment = String(raw.prefix(10))
        return makeISODateFormatter().date(from: fragment)
    }
}

/// A View that displays a "Member since …" badge in the customer detail header.
public struct CustomerSinceBadge: View {
    let createdAt: String?

    public init(createdAt: String?) {
        self.createdAt = createdAt
    }

    public var body: some View {
        if let label = CustomerSinceDateFormatter.memberSince(createdAt) {
            HStack(spacing: BrandSpacing.xs) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12))
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(Color.bizarreSurface2.opacity(0.7), in: Capsule())
            .accessibilityLabel(label)
            .accessibilityAddTraits(.isStaticText)
            .accessibilityIdentifier("customer.since.badge")
        }
    }
}

// MARK: - Hex Color helper (local — mirrors the one in CustomerDetailView)

private extension Color {
    init?(hexString: String) {
        let stripped = hexString.hasPrefix("#") ? String(hexString.dropFirst()) : hexString
        guard stripped.count == 6, let value = UInt32(stripped, radix: 16) else { return nil }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >>  8) & 0xFF) / 255
        let b = Double( value        & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}

#endif
