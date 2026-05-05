import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - ReviewMeetingHelperViewModel

@MainActor
@Observable
public final class ReviewMeetingHelperViewModel {
    public let review: PerformanceReview
    public private(set) var isExportingPDF: Bool = false
    public private(set) var exportedPDFURL: URL?
    public private(set) var errorMessage: String?

    public init(review: PerformanceReview) {
        self.review = review
    }

    public func generatePDF() async {
        isExportingPDF = true
        defer { isExportingPDF = false }
        errorMessage = nil
        do {
            exportedPDFURL = try await ReviewPDFExporter.export(review: review)
        } catch {
            AppLog.ui.error("ReviewMeeting PDF export failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - ReviewMeetingHelperView

public struct ReviewMeetingHelperView: View {
    @State private var vm: ReviewMeetingHelperViewModel

    public init(review: PerformanceReview) {
        _vm = State(wrappedValue: ReviewMeetingHelperViewModel(review: review))
    }

    public var body: some View {
        if Platform.isCompact {
            compactLayout
        } else {
            regularLayout
        }
    }

    // MARK: - Compact (iPhone) — scrollable sections

    @ViewBuilder private var compactLayout: some View {
        NavigationStack {
            List {
                reviewSections
            }
            .navigationTitle("Review Meeting")
            .toolbar { pdfToolbarItem }
        }
    }

    // MARK: - Regular (iPad) — side-by-side columns

    @ViewBuilder private var regularLayout: some View {
        NavigationStack {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.xxl) {
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    sectionCard(title: "Manager Draft", text: vm.review.managerDraft)
                    sectionCard(title: "Self Review", text: vm.review.selfReview)
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                    peerAggregateCard
                    competencyCard
                }
                .frame(maxWidth: .infinity)
            }
            .padding(DesignTokens.Spacing.xxl)
            .navigationTitle("Review Meeting")
            .toolbar { pdfToolbarItem }
        }
    }

    // MARK: - Shared sections (for List)

    @ViewBuilder private var reviewSections: some View {
        Section("Manager Draft") {
            Text(vm.review.managerDraft.isEmpty ? "No draft yet." : vm.review.managerDraft)
                .foregroundStyle(vm.review.managerDraft.isEmpty ? .secondary : .primary)
        }
        Section("Self Review") {
            Text(vm.review.selfReview.isEmpty ? "Not submitted." : vm.review.selfReview)
                .foregroundStyle(vm.review.selfReview.isEmpty ? .secondary : .primary)
        }
        Section("Peer Feedback (\(vm.review.peerFeedback.count))") {
            ForEach(vm.review.peerFeedback) { peer in
                Text(peer.feedbackText)
                    .font(.callout)
            }
        }
        Section("Competency Ratings") {
            ForEach(vm.review.competencyRatings) { rating in
                LabeledContent(rating.competency.displayName) {
                    Text("\(rating.score)/5")
                        .foregroundStyle(.secondary)
                }
            }
        }
        if let err = vm.errorMessage {
            Section { Text(err).foregroundStyle(.red) }
        }
    }

    // MARK: - iPad cards

    @ViewBuilder private func sectionCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title).font(.headline)
            Text(text.isEmpty ? "—" : text)
                .font(.callout)
                .foregroundStyle(text.isEmpty ? .secondary : .primary)
        }
        .padding(DesignTokens.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    @ViewBuilder private var peerAggregateCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Peer Feedback (\(vm.review.peerFeedback.count))")
                .font(.headline)
            ForEach(vm.review.peerFeedback) { peer in
                Text(peer.feedbackText)
                    .font(.callout)
                Divider()
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    @ViewBuilder private var competencyCard: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text("Competencies").font(.headline)
            ForEach(vm.review.competencyRatings) { rating in
                LabeledContent(rating.competency.displayName) {
                    Text("\(rating.score)/5").foregroundStyle(.secondary)
                }
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.lg))
    }

    // MARK: - PDF toolbar

    @ToolbarContentBuilder private var pdfToolbarItem: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            if vm.isExportingPDF {
                ProgressView()
            } else {
                Button("Generate PDF") {
                    Task { await vm.generatePDF() }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - ReviewPDFExporter (stub — wired for §46 PDF requirement)

enum ReviewPDFExporter {
    static func export(review: PerformanceReview) async throws -> URL {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("review-\(review.id).pdf")
        // PDF rendering would be implemented with PDFKit / UIGraphicsPDFRenderer.
        // Stub creates an empty file so the plumbing is wired.
        try Data().write(to: tempURL)
        return tempURL
    }
}
