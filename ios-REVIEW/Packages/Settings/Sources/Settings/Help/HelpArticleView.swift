import SwiftUI
import Core
import DesignSystem

// MARK: - HelpArticleView

/// Renders a single help article. Markdown is parsed with `AttributedString`
/// and displayed via SwiftUI `Text`. Liquid Glass toolbar.
public struct HelpArticleView: View {

    // MARK: - State

    private let article: HelpArticle
    private let catalog: [HelpArticle]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    // MARK: - Init

    public init(article: HelpArticle, catalog: [HelpArticle] = HelpArticleCatalog.all) {
        self.article = article
        self.catalog = catalog
    }

    // MARK: - Body

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrandSpacing.base) {
                categoryChip
                markdownContent
                if !relatedArticles.isEmpty {
                    relatedSection
                }
            }
            .padding(BrandSpacing.base)
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle(article.title)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(article.title)
                    .font(.brandTitleMedium())
                    .foregroundStyle(.bizarreOnSurface)
                    .brandGlass(.clear)
            }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var categoryChip: some View {
        Text(article.category.rawValue.uppercased())
            .font(.brandLabelSmall())
            .foregroundStyle(.bizarreOnOrange)
            .padding(.horizontal, BrandSpacing.sm)
            .padding(.vertical, BrandSpacing.xxs)
            .background(
                Capsule().fill(Color.bizarreOrange)
            )
            .accessibilityLabel("Category: \(article.category.rawValue)")
    }

    @ViewBuilder
    private var markdownContent: some View {
        if let attributed = try? AttributedString(
            markdown: article.markdown
        ) {
            Text(attributed)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Article body")
        } else {
            Text(article.markdown)
                .font(.brandBodyLarge())
                .foregroundStyle(.bizarreOnSurface)
        }
    }

    @ViewBuilder
    private var relatedSection: some View {
        VStack(alignment: .leading, spacing: BrandSpacing.sm) {
            Text("Related Articles")
                .font(.brandLabelLarge())
                .foregroundStyle(.bizarreOnSurfaceMuted)
                .accessibilityAddTraits(.isHeader)

            ForEach(relatedArticles) { related in
                NavigationLink(destination: HelpArticleView(article: related, catalog: catalog)) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityHidden(true)
                        Text(related.title)
                            .font(.brandBodyLarge())
                            .foregroundStyle(.bizarreOnSurface)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundStyle(.bizarreOnSurfaceMuted)
                            .accessibilityHidden(true)
                    }
                    .padding(BrandSpacing.sm)
                    .background(Color.bizarreSurface1, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Related article: \(related.title)")
                #if os(iOS)
                .hoverEffect(.highlight)
                #endif
            }
        }
    }

    // MARK: - Helpers

    private var relatedArticles: [HelpArticle] {
        catalog.filter { article.relatedArticleIds.contains($0.id) }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    NavigationStack {
        HelpArticleView(article: HelpArticleCatalog.gettingStarted)
    }
}
#endif
