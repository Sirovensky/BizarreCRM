import SwiftUI
import DesignSystem
import Networking

// MARK: - CSATSurveyViewModel

@Observable
@MainActor
public final class CSATSurveyViewModel {
    public var rating: Int = 0
    public var comment: String = ""
    public var isSubmitting = false
    public var errorMessage: String?
    public var didSubmit = false

    let customerId: String
    let ticketId: String
    private let api: APIClient

    public init(customerId: String, ticketId: String, api: APIClient) {
        self.customerId = customerId
        self.ticketId = ticketId
        self.api = api
    }

    public var canSubmit: Bool { (1...5).contains(rating) }

    public var ratingLabel: String {
        switch rating {
        case 1: return "Poor"
        case 2: return "Fair"
        case 3: return "Good"
        case 4: return "Very Good"
        case 5: return "Excellent"
        default: return "Tap to rate"
        }
    }

    public func submit() async {
        guard canSubmit else {
            errorMessage = "Please select a rating before submitting."
            return
        }
        isSubmitting = true
        errorMessage = nil
        let body = CSATSubmitRequest(
            customerId: customerId,
            ticketId: ticketId,
            score: rating,
            comment: comment
        )
        do {
            _ = try await api.submitCSAT(body)
            didSubmit = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmitting = false
    }
}

// MARK: - CSATSurveyView

/// Post-service in-app sheet (or public web link via §53): 5-star rating + optional comment.
public struct CSATSurveyView: View {
    @State private var vm: CSATSurveyViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(customerId: String, ticketId: String, api: APIClient) {
        _vm = State(initialValue: CSATSurveyViewModel(customerId: customerId, ticketId: ticketId, api: api))
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: BrandSpacing.xl) {
                headerSection
                starRatingSection
                commentSection
                submitSection
                Spacer()
            }
            .padding(BrandSpacing.base)
            .navigationTitle("Rate Your Experience")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Not Now") { dismiss() }
                }
            }
            .onChange(of: vm.didSubmit) { _, submitted in
                if submitted { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
        .brandGlass(.regular, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.xl))
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            Image(systemName: "star.bubble")
                .font(.system(size: 40))
                .foregroundStyle(.bizarreOrange)
                .accessibilityHidden(true)
            Text("How was your experience?")
                .font(.brandTitleLarge())
                .foregroundStyle(.bizarreOnSurface)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Star rating

    private var starRatingSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            HStack(spacing: BrandSpacing.md) {
                ForEach(1...5, id: \.self) { star in
                    Button {
                        withAnimation(reduceMotion ? .none : BrandMotion.statusChange) {
                            vm.rating = star
                        }
                    } label: {
                        Image(systemName: star <= vm.rating ? "star.fill" : "star")
                            .font(.system(size: 40))
                            .foregroundStyle(star <= vm.rating ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                            .frame(minWidth: DesignTokens.Touch.minTargetSide, minHeight: DesignTokens.Touch.minTargetSide)
                    }
                    .accessibilityLabel("\(star) star\(star == 1 ? "" : "s")")
                    .accessibilityAddTraits(star == vm.rating ? [.isSelected] : [])
                }
            }
            .accessibilityLabel("Star rating: \(vm.rating) out of 5")

            if vm.rating > 0 {
                Text(vm.ratingLabel)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .transition(.opacity)
            }
        }
    }

    // MARK: - Comment

    private var commentSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.xs) {
            Text("Comments (optional)")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextEditor(text: $vm.comment)
                .font(.brandBodyMedium())
                .frame(minHeight: 80)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Optional comment")
        }
    }

    // MARK: - Submit

    private var submitSection: some View {
        VStack(spacing: BrandSpacing.sm) {
            if let err = vm.errorMessage {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreError)
                    .accessibilityLabel("Error: \(err)")
            }

            Button {
                Task { await vm.submit() }
            } label: {
                if vm.isSubmitting {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Submit Rating")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.brandGlassProminent)
            .tint(.bizarreOrange)
            .disabled(!vm.canSubmit || vm.isSubmitting)
            .accessibilityLabel(vm.isSubmitting ? "Submitting rating" : "Submit \(vm.rating) star rating")
        }
    }
}
