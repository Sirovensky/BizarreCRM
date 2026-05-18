import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - PerformanceReviewComposeViewModel

@MainActor
@Observable
public final class PerformanceReviewComposeViewModel {
    public var managerDraft: String = ""
    public var competencyRatings: [CompetencyRating] = Competency.allCases.map { CompetencyRating(competency: $0, score: 3) }
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: any ReviewsRepository
    @ObservationIgnored private let review: PerformanceReview
    @ObservationIgnored private let onSaved: @MainActor (PerformanceReview) -> Void

    public init(repo: any ReviewsRepository, review: PerformanceReview, onSaved: @escaping @MainActor (PerformanceReview) -> Void) {
        self.repo = repo
        self.review = review
        self.onSaved = onSaved
        self.managerDraft = review.managerDraft
        self.competencyRatings = review.competencyRatings.isEmpty
            ? Competency.allCases.map { CompetencyRating(competency: $0, score: 3) }
            : review.competencyRatings
    }

    public func save() async {
        guard !managerDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Manager draft cannot be empty."
            return
        }
        // BUGHUNT-2026-05-17: re-entry guard. The toolbar swaps Save for a
        // ProgressView while isSaving, but a quick double-tap before
        // SwiftUI re-renders fires two updateReview PATCHes — the second
        // can transition the review to .managerReady on top of a partial
        // save, scrambling the audit history.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let updated = try await repo.updateReview(
                id: review.id,
                UpdateReviewRequest(
                    managerDraft: managerDraft,
                    competencyRatings: competencyRatings,
                    status: .managerReady
                )
            )
            onSaved(updated)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: updateReview PATCH may have landed before
            // cancellation fired. Painting "cancelled" as errorMessage
            // tempts the manager to retap Save, double-stamping the
            // .managerReady transition (audit log records two transitions
            // with the same timestamp). Suppress so the list refresh on
            // dismiss reveals the actual saved review.
            errorMessage = nil
        } catch {
            AppLog.ui.error("ReviewCompose save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }

    public func setScore(for competency: Competency, score: Int) {
        guard let idx = competencyRatings.firstIndex(where: { $0.competency == competency }) else { return }
        competencyRatings[idx] = CompetencyRating(competency: competency, score: score)
    }
}

// MARK: - PerformanceReviewComposeView

public struct PerformanceReviewComposeView: View {
    @State private var vm: PerformanceReviewComposeViewModel
    @Environment(\.dismiss) private var dismiss

    public init(repo: any ReviewsRepository, review: PerformanceReview, onSaved: @escaping @MainActor (PerformanceReview) -> Void) {
        _vm = State(wrappedValue: PerformanceReviewComposeViewModel(repo: repo, review: review, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Competency Ratings") {
                    ForEach(vm.competencyRatings) { rating in
                        CompetencyRatingRow(
                            rating: rating,
                            onScore: { score in
                                vm.setScore(for: rating.competency, score: score)
                            }
                        )
                    }
                }

                Section("Manager Notes") {
                    TextEditor(text: $vm.managerDraft)
                        .frame(minHeight: 120)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .accessibilityLabel("Manager draft notes")
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Write Review")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if vm.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") {
                            Task { await vm.save() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
    }
}

// MARK: - CompetencyRatingRow

private struct CompetencyRatingRow: View {
    let rating: CompetencyRating
    let onScore: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(rating.competency.displayName)
                .font(.subheadline.weight(.medium))
            HStack(spacing: DesignTokens.Spacing.sm) {
                ForEach(1...5, id: \.self) { star in
                    Image(systemName: star <= rating.score ? "star.fill" : "star")
                        .foregroundStyle(star <= rating.score ? .yellow : .secondary)
                        .onTapGesture { onScore(star) }
                        .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                        .frame(minWidth: DesignTokens.Touch.minTargetSide,
                               minHeight: DesignTokens.Touch.minTargetSide)
                }
            }
        }
        .padding(.vertical, DesignTokens.Spacing.xs)
    }
}
