import SwiftUI
import Observation
import Core
import DesignSystem
import Networking

// MARK: - SelfReviewViewModel

@MainActor
@Observable
public final class SelfReviewViewModel {
    public var strengths: String = ""
    public var growthAreas: String = ""
    public var nextGoals: String = ""
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String?

    @ObservationIgnored private let repo: any ReviewsRepository
    @ObservationIgnored private let review: PerformanceReview
    @ObservationIgnored private let onSaved: @MainActor (PerformanceReview) -> Void

    public init(repo: any ReviewsRepository, review: PerformanceReview, onSaved: @escaping @MainActor (PerformanceReview) -> Void) {
        self.repo = repo
        self.review = review
        self.onSaved = onSaved
        self.strengths = review.selfReview
    }

    public func save() async {
        let combined = [
            "Strengths: \(strengths)",
            "Growth areas: \(growthAreas)",
            "Next-period goals: \(nextGoals)"
        ].joined(separator: "\n\n")

        guard !strengths.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Please fill in at least your strengths."
            return
        }
        // BUGHUNT-2026-05-17: re-entry guard. The toolbar swaps Submit for
        // ProgressView when isSaving, but a quick double-tap before the
        // re-render fires two updateReview PATCHes, both transitioning to
        // .peerPending — the audit log records two transitions with
        // identical timestamps.
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil
        do {
            let updated = try await repo.updateReview(
                id: review.id,
                UpdateReviewRequest(selfReview: combined, status: .peerPending)
            )
            onSaved(updated)
        } catch let e where AppError.isCancellation(e) {
            // BUGHUNT-2026-05-17: updateReview PATCH may have landed before
            // cancellation fired. Painting "cancelled" tempts the employee
            // to retap Submit, double-stamping the .peerPending transition.
            // Suppress so the parent refresh shows the actual saved state.
            errorMessage = nil
        } catch {
            AppLog.ui.error("SelfReview save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - SelfReviewView

public struct SelfReviewView: View {
    @State private var vm: SelfReviewViewModel
    @Environment(\.dismiss) private var dismiss

    public init(repo: any ReviewsRepository, review: PerformanceReview, onSaved: @escaping @MainActor (PerformanceReview) -> Void) {
        _vm = State(wrappedValue: SelfReviewViewModel(repo: repo, review: review, onSaved: onSaved))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Reflect honestly — this is shared only with your manager.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("What are your strengths?") {
                    TextEditor(text: $vm.strengths)
                        .frame(minHeight: 80)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .accessibilityLabel("Strengths field")
                }

                Section("Growth areas") {
                    TextEditor(text: $vm.growthAreas)
                        .frame(minHeight: 80)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .accessibilityLabel("Growth areas field")
                }

                Section("Goals for next period") {
                    TextEditor(text: $vm.nextGoals)
                        .frame(minHeight: 80)
                        #if canImport(UIKit)
                        .textInputAutocapitalization(.sentences)
                        #endif
                        .accessibilityLabel("Next period goals field")
                }

                if let err = vm.errorMessage {
                    Section { Text(err).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Self Review")
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
                        Button("Submit") {
                            Task { await vm.save() }
                        }
                        .keyboardShortcut(.return)
                    }
                }
            }
        }
        .presentationDetents([.large])
    }
}
