import SwiftUI
import DesignSystem

// MARK: - ContextualHelpButton

/// Reusable `?` icon button that presents the relevant help article as a sheet.
/// Place on complex screens — pass the `articleId` that best matches the context.
///
/// Example:
/// ```swift
/// .toolbar {
///     ToolbarItem(placement: .topBarTrailing) {
///         ContextualHelpButton(articleId: "help.pos-basics")
///     }
/// }
/// ```
public struct ContextualHelpButton: View {

    // MARK: - Properties

    private let articleId: String
    @State private var isPresented: Bool = false

    // MARK: - Init

    public init(articleId: String) {
        self.articleId = articleId
    }

    // MARK: - Body

    public var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .accessibilityLabel("Help")
                .accessibilityHint("Opens help for this screen")
        }
        .tint(.bizarreOrange)
        .brandGlass(interactive: true)
        .sheet(isPresented: $isPresented) {
            helpSheet
        }
    }

    // MARK: - Help sheet

    @ViewBuilder
    private var helpSheet: some View {
        NavigationStack {
            if let article = resolvedArticle {
                HelpArticleView(article: article)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresented = false }
                                .accessibilityLabel("Close help")
                        }
                    }
            } else {
                // Fallback: open full help center
                HelpCenterView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresented = false }
                                .accessibilityLabel("Close help center")
                        }
                    }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Helpers

    private var resolvedArticle: HelpArticle? {
        HelpArticleCatalog.all.first(where: { $0.id == articleId })
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        Text("Screen Content")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    ContextualHelpButton(articleId: "help.pos-basics")
                }
            }
    }
}
#endif
