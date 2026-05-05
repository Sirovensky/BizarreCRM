import SwiftUI
import DesignSystem

// MARK: - ExternalReview model

/// Payload carried by `kind: "review.new"` push notification.
public struct ExternalReview: Sendable, Identifiable {
    public let id: String
    public let platform: ReviewPlatform
    public let authorName: String
    public let rating: Int          // 1-5
    public let body: String
    public let receivedAt: Date

    public init(
        id: String,
        platform: ReviewPlatform,
        authorName: String,
        rating: Int,
        body: String,
        receivedAt: Date
    ) {
        self.id = id
        self.platform = platform
        self.authorName = authorName
        self.rating = rating
        self.body = body
        self.receivedAt = receivedAt
    }
}

// MARK: - ExternalReviewAlertViewModel

@Observable
@MainActor
public final class ExternalReviewAlertViewModel {
    public let review: ExternalReview
    public var draftResponse: String = ""
    public var isExpanded = false

    public init(review: ExternalReview) {
        self.review = review
        draftResponse = defaultDraft(for: review)
    }

    public var openURL: URL? {
        switch review.platform {
        case .google:   return URL(string: "https://business.google.com")
        case .yelp:     return URL(string: "https://biz.yelp.com")
        case .facebook: return URL(string: "https://www.facebook.com")
        case .other(_, let url): return url
        }
    }

    private func defaultDraft(for review: ExternalReview) -> String {
        if review.rating >= 4 {
            return "Thank you so much for the kind words, \(review.authorName)! We're thrilled you had a great experience and look forward to seeing you again."
        } else {
            return "Hi \(review.authorName), thank you for your feedback. We're sorry to hear your experience didn't meet your expectations. Please reach out to us directly so we can make it right."
        }
    }
}

// MARK: - ExternalReviewAlert

/// Sheet triggered by `kind: "review.new"` push — shows review + draft-response text area.
/// Staff drafts reply here; posting happens via Safari (iOS opens external platform).
public struct ExternalReviewAlert: View {
    @State private var vm: ExternalReviewAlertViewModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    public init(review: ExternalReview) {
        _vm = State(initialValue: ExternalReviewAlertViewModel(review: review))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: BrandSpacing.lg) {
                    reviewHeader
                    reviewBody
                    Divider()
                    draftSection
                    openInSafariButton
                }
                .padding(BrandSpacing.base)
            }
            .navigationTitle("New Review")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Dismiss") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - Review header

    private var reviewHeader: some View {
        HStack(alignment: .top, spacing: BrandSpacing.md) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(vm.review.authorName)
                    .font(.brandTitleSmall())
                    .foregroundStyle(.bizarreOnSurface)

                Text(vm.review.platform.displayName)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Spacer()

            starRating(vm.review.rating)
        }
    }

    private func starRating(_ rating: Int) -> some View {
        HStack(spacing: BrandSpacing.xxs) {
            ForEach(1...5, id: \.self) { star in
                Image(systemName: star <= rating ? "star.fill" : "star")
                    .foregroundStyle(star <= rating ? Color.bizarreOrange : Color.bizarreOnSurfaceMuted)
                    .font(.system(size: 14))
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("\(rating) out of 5 stars")
    }

    // MARK: - Review body

    private var reviewBody: some View {
        Text(vm.review.body)
            .font(.brandBodyMedium())
            .foregroundStyle(.bizarreOnSurface)
            .textSelection(.enabled)
            .accessibilityLabel("Review: \(vm.review.body)")
    }

    // MARK: - Draft response

    private var draftSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Draft Response")
                .font(.brandTitleSmall())
                .foregroundStyle(.bizarreOnSurface)

            Text("Copy this text and paste it when you open the platform below. Posting happens on \(vm.review.platform.displayName) — not from the app.")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)

            TextEditor(text: $vm.draftResponse)
                .font(.brandBodyMedium())
                .frame(minHeight: 120)
                .padding(BrandSpacing.sm)
                .background(Color.bizarreSurface2, in: RoundedRectangle(cornerRadius: DesignTokens.Radius.md))
                .accessibilityLabel("Draft response text")

            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = vm.draftResponse
                #endif
            } label: {
                Label("Copy Draft", systemImage: "doc.on.doc")
                    .font(.brandLabelLarge())
            }
            .buttonStyle(.brandGlass)
            .accessibilityLabel("Copy draft response to clipboard")
        }
    }

    // MARK: - Open Safari button

    private var openInSafariButton: some View {
        Button {
            if let url = vm.openURL {
                openURL(url)
            }
        } label: {
            Label("Open \(vm.review.platform.displayName) to Post", systemImage: "safari")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.brandGlassProminent)
        .tint(.bizarreOrange)
        .disabled(vm.openURL == nil)
        .accessibilityLabel("Open \(vm.review.platform.displayName) in Safari to post response")
    }
}
