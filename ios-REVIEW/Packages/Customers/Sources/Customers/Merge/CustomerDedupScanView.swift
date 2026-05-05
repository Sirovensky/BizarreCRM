#if canImport(UIKit)
import SwiftUI
import Core
import DesignSystem
import Networking

// MARK: - §5 Dedup Detection on Create + Dedup Scan
//
// - Dupe detection on create: same phone / same email / similar name + address
// - Suggest merge at entry
// - Side-by-side record comparison merge UI (extends existing CustomerMergeView)
// - Settings → Data → Run dedup scan → lists candidates
// - Manager batch review of dedup candidates
// - Optional auto-merge when 100% phone + email match

// MARK: - Dedup candidate model

public struct CustomerDedupCandidate: Decodable, Identifiable, Sendable {
    public let id: Int64
    public let existingCustomerId: Int64
    public let existingCustomerName: String
    public let existingPhone: String?
    public let existingEmail: String?
    /// How certain the match is (0–100)
    public let confidenceScore: Int
    /// Which fields matched
    public let matchedFields: [String]
    /// True if phone+email are 100% match → auto-merge eligible
    public let isExactMatch: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case existingCustomerId   = "existing_customer_id"
        case existingCustomerName = "existing_customer_name"
        case existingPhone        = "existing_phone"
        case existingEmail        = "existing_email"
        case confidenceScore      = "confidence_score"
        case matchedFields        = "matched_fields"
        case isExactMatch         = "is_exact_match"
    }
}

// MARK: - Create-time dupe check alert sheet

/// Shown during customer create when a probable duplicate is detected.
/// Options: Use existing / Merge / Create anyway.
public struct CustomerDuplicateCheckAlertSheet: View {
    public let candidate: CustomerDedupCandidate
    public var onUseExisting: ((Int64) -> Void)?
    public var onMerge: ((Int64) -> Void)?
    public var onCreateAnyway: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    public init(
        candidate: CustomerDedupCandidate,
        onUseExisting: ((Int64) -> Void)? = nil,
        onMerge: ((Int64) -> Void)? = nil,
        onCreateAnyway: (() -> Void)? = nil
    ) {
        self.candidate = candidate
        self.onUseExisting = onUseExisting
        self.onMerge = onMerge
        self.onCreateAnyway = onCreateAnyway
    }

    public var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BrandSpacing.md) {
                // Warning banner
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(.bizarreWarning)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Possible Duplicate")
                            .font(.brandHeadlineSmall())
                            .foregroundStyle(.bizarreOnSurface)
                        Text("This looks like it might be an existing customer.")
                            .font(.brandBodyMedium())
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                    }
                }
                .padding(BrandSpacing.base)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))

                // Existing record summary
                VStack(alignment: .leading, spacing: BrandSpacing.xs) {
                    Text("Existing record")
                        .font(.brandLabelLarge().weight(.semibold))
                        .foregroundStyle(.bizarreOnSurfaceMuted)

                    HStack(spacing: BrandSpacing.sm) {
                        ZStack {
                            Circle().fill(Color.bizarreOrangeContainer)
                            Text(String(candidate.existingCustomerName.prefix(1)))
                                .font(.brandLabelLarge())
                                .foregroundStyle(.bizarreOnOrange)
                        }
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.existingCustomerName)
                                .font(.brandBodyMedium().weight(.semibold))
                                .foregroundStyle(.bizarreOnSurface)
                            if let phone = candidate.existingPhone {
                                Text(phone)
                                    .font(.brandMono(size: 13))
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            if let email = candidate.existingEmail {
                                Text(email)
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(candidate.confidenceScore)%")
                                .font(.brandMono(size: 18).weight(.bold))
                                .foregroundStyle(.bizarreWarning)
                                .monospacedDigit()
                            Text("match")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                    }

                    // Matched fields
                    FlowLayout(spacing: 4) {
                        ForEach(candidate.matchedFields, id: \.self) { field in
                            Text(field)
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOrange)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.bizarreOrange.opacity(0.1), in: Capsule())
                        }
                    }
                }
                .padding(BrandSpacing.base)
                .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.bizarreOutline.opacity(0.4), lineWidth: 0.5))

                Spacer()

                // Actions
                VStack(spacing: BrandSpacing.sm) {
                    Button {
                        onUseExisting?(candidate.existingCustomerId)
                        dismiss()
                    } label: {
                        Label("Use Existing Customer", systemImage: "person.crop.circle.badge.checkmark")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.bizarreOrange)

                    Button {
                        onMerge?(candidate.existingCustomerId)
                        dismiss()
                    } label: {
                        Label("Merge Records", systemImage: "arrow.triangle.merge")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOrange)

                    Button {
                        onCreateAnyway?()
                        dismiss()
                    } label: {
                        Label("Create Anyway", systemImage: "plus")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.bordered)
                    .tint(.bizarreOnSurfaceMuted)
                }
            }
            .padding(BrandSpacing.base)
            .navigationTitle("Duplicate Found")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.fraction(0.75), .large])
    }
}

// MARK: - Dedup scan view (Settings → Data → Run Dedup Scan)

public struct CustomerDedupScanView: View {
    let api: APIClient
    /// Called when user confirms merging a pair.
    var onMergePair: ((Int64, Int64) -> Void)?

    @State private var candidates: [CustomerDedupCandidate] = []
    @State private var isScanning = false
    @State private var errorMessage: String?
    @State private var selectedCandidate: CustomerDedupCandidate?
    @State private var autoMergeExact = false
    @State private var autoMergeCount = 0

    public init(api: APIClient, onMergePair: ((Int64, Int64) -> Void)? = nil) {
        self.api = api
        self.onMergePair = onMergePair
    }

    public var body: some View {
        Group {
            if isScanning {
                VStack(spacing: BrandSpacing.md) {
                    ProgressView("Scanning for duplicates…")
                    Text("This may take a moment for large customer lists.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = errorMessage {
                ContentUnavailableView(err, systemImage: "exclamationmark.triangle")
                    .toolbar { runButton }
            } else if candidates.isEmpty {
                emptyState
            } else {
                candidateList
            }
        }
        .navigationTitle("Dedup Scan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { runButton }
        .sheet(item: $selectedCandidate) { c in
            CustomerDuplicateCheckAlertSheet(
                candidate: c,
                onMerge: { existingId in
                    onMergePair?(existingId, c.id)
                    candidates.removeAll { $0.id == c.id }
                }
            )
        }
    }

    private var runButton: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await runScan() }
            } label: {
                Label("Run Scan", systemImage: "magnifyingglass")
            }
            .disabled(isScanning)
            .accessibilityLabel("Run duplicate scan")
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Duplicates Found", systemImage: "checkmark.seal")
        } description: {
            Text("Tap 'Run Scan' to check your customer list for probable duplicates.")
        } actions: {
            Button("Run Scan") { Task { await runScan() } }
                .buttonStyle(.borderedProminent)
                .tint(.bizarreOrange)
        }
    }

    private var candidateList: some View {
        List {
            if autoMergeCount > 0 {
                Section {
                    Label("\(autoMergeCount) exact match\(autoMergeCount == 1 ? "" : "es") auto-merged (100% phone + email).",
                          systemImage: "checkmark.circle.fill")
                        .font(.brandLabelLarge())
                        .foregroundStyle(.bizarreSuccess)
                        .accessibilityLabel("\(autoMergeCount) exact matches were auto-merged.")
                }
            }

            Section("\(candidates.count) candidate\(candidates.count == 1 ? "" : "s")") {
                ForEach(candidates) { c in
                    Button {
                        selectedCandidate = c
                    } label: {
                        HStack(spacing: BrandSpacing.sm) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.existingCustomerName)
                                    .font(.brandBodyMedium())
                                    .foregroundStyle(.bizarreOnSurface)
                                Text(c.matchedFields.joined(separator: " · "))
                                    .font(.brandLabelSmall())
                                    .foregroundStyle(.bizarreOnSurfaceMuted)
                            }
                            Spacer()
                            Text("\(c.confidenceScore)%")
                                .font(.brandMono(size: 14).weight(.semibold))
                                .foregroundStyle(.bizarreWarning)
                                .monospacedDigit()
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(c.existingCustomerName), \(c.confidenceScore)% match. Fields: \(c.matchedFields.joined(separator: ", ")). Tap to review.")
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func runScan() async {
        isScanning = true
        errorMessage = nil
        autoMergeCount = 0
        defer { isScanning = false }
        do {
            let result = try await api.runCustomerDedupScan(autoMergeExact: autoMergeExact)
            candidates = result.candidates
            autoMergeCount = result.autoMergedCount
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Scan result DTO

public struct CustomerDedupScanResult: Decodable, Sendable {
    public let candidates: [CustomerDedupCandidate]
    public let autoMergedCount: Int

    enum CodingKeys: String, CodingKey {
        case candidates
        case autoMergedCount = "auto_merged_count"
    }
}

// MARK: - Minimal FlowLayout for matched-field chips

private struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0) { $0 + $1 + spacing } - spacing
        return CGSize(width: proposal.width ?? 0, height: max(0, height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for item in row.items {
                let size = item.view.sizeThatFits(.unspecified)
                item.view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(view: LayoutSubview, width: CGFloat)]
        var height: CGFloat
    }

    private func computeRows(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var current = Row(items: [], height: 0)
        var x: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, !current.items.isEmpty {
                rows.append(current)
                current = Row(items: [], height: 0)
                x = 0
            }
            current.items.append((view, size.width))
            current.height = max(current.height, size.height)
            x += size.width + spacing
        }
        if !current.items.isEmpty { rows.append(current) }
        return rows
    }
}

// MARK: - APIClient extension

extension APIClient {
    /// `POST /api/v1/customers/dedup-scan` — run dedup analysis across all customers.
    public func runCustomerDedupScan(autoMergeExact: Bool) async throws -> CustomerDedupScanResult {
        return try await post("/api/v1/customers/dedup-scan",
                              body: CustomerDedupScanBody(auto_merge_exact: autoMergeExact),
                              as: CustomerDedupScanResult.self)
    }
}

private struct CustomerDedupScanBody: Encodable, Sendable {
    let auto_merge_exact: Bool
}

#endif
