import SwiftUI
import Core
import DesignSystem

// MARK: - HelpCenterView

/// Searchable FAQ index. Entry point: Settings → Help.
/// iPhone: vertical list. iPad: sidebar categories + detail.
public struct HelpCenterView: View {

    // MARK: - State

    @State private var searchVM = HelpSearchViewModel()
    @State private var selectedArticle: HelpArticle?
    @State private var selectedCategory: HelpArticle.Category?
    @State private var showSupportSheet = false

    @Environment(\.horizontalSizeClass) private var hSizeClass

    // MARK: - Body

    public init() {}

    public var body: some View {
        Group {
            #if os(iOS)
            if hSizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
            #else
            iPadLayout
            #endif
        }
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .sheet(isPresented: $showSupportSheet) {
            SupportEmailComposerView()
        }
    }

    // MARK: - iPhone layout (vertical)

    private var iPhoneLayout: some View {
        NavigationStack {
            searchableList
                .navigationTitle("Help Center")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.large)
                #endif
                .toolbar { toolbarContent }
        }
    }

    // MARK: - iPad layout (sidebar + detail)

    private var iPadLayout: some View {
        NavigationSplitView {
            categoryList
                .navigationTitle("Help")
        } detail: {
            if let article = selectedArticle {
                NavigationStack {
                    HelpArticleView(article: article)
                }
            } else {
                searchableList
            }
        }
        .toolbar { toolbarContent }
    }

    // MARK: - Searchable article list

    @ViewBuilder
    private var searchableList: some View {
        List {
            if searchVM.query.isEmpty {
                categoriesSection
                allArticlesSection
                contactSupportFooterSection
            } else {
                searchResultsSection
                contactSupportFooterSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .searchable(text: $searchVM.query, prompt: "Search help articles")
        .overlay {
            if searchVM.isSearching {
                ProgressView()
                    .accessibilityLabel("Searching…")
            }
        }
    }

    // MARK: - Category sidebar (iPad)

    @ViewBuilder
    private var categoryList: some View {
        List(HelpArticle.Category.allCases, id: \.self, selection: $selectedCategory) { cat in
            Label(cat.rawValue, systemImage: categoryIcon(cat))
                .accessibilityLabel(cat.rawValue)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .onChange(of: selectedCategory) { _, newCat in
            guard let newCat else { return }
            selectedArticle = HelpArticleCatalog.all.first(where: { $0.category == newCat })
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var categoriesSection: some View {
        Section("Browse by Category") {
            ForEach(HelpArticle.Category.allCases, id: \.self) { cat in
                let articles = HelpArticleCatalog.all.filter { $0.category == cat }
                if !articles.isEmpty {
                    NavigationLink(destination: categoryDetailList(cat: cat, articles: articles)) {
                        HStack {
                            Image(systemName: categoryIcon(cat))
                                .foregroundStyle(.bizarreOrange)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            Text(cat.rawValue)
                                .font(.brandBodyLarge())
                                .foregroundStyle(.bizarreOnSurface)
                            Spacer()
                            Text("\(articles.count)")
                                .font(.brandLabelSmall())
                                .foregroundStyle(.bizarreOnSurfaceMuted)
                        }
                        .padding(.vertical, BrandSpacing.xs)
                    }
                    .listRowBackground(Color.bizarreSurface1)
                    .accessibilityLabel("\(cat.rawValue), \(articles.count) articles")
                    #if os(iOS)
                    .hoverEffect(.highlight)
                    #endif
                }
            }
        }
    }

    @ViewBuilder
    private var allArticlesSection: some View {
        Section("All Articles") {
            ForEach(HelpArticleCatalog.all) { article in
                articleRow(article)
            }
        }
    }

    /// Footer shown below articles with a direct "Contact Support" link.
    @ViewBuilder
    private var contactSupportFooterSection: some View {
        Section {
            HStack(spacing: BrandSpacing.sm) {
                Image(systemName: "envelope")
                    .foregroundStyle(.bizarreOrange)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Still need help?")
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                    Text("Contact our support team — we respond within one business day.")
                        .font(.brandLabelSmall())
                        .foregroundStyle(.bizarreOnSurfaceMuted)
                }
                Spacer()
            }
            .padding(.vertical, BrandSpacing.xs)
            .contentShape(Rectangle())
            .onTapGesture { showSupportSheet = true }
            .listRowBackground(Color.bizarreSurface1)
            .accessibilityLabel("Contact Support — opens email composer")
            .accessibilityAddTraits(.isButton)
            #if os(iOS)
            .hoverEffect(.highlight)
            #endif
        } footer: {
            Text("bizarrecrm.com/support · Typical response: 1 business day")
                .font(.brandLabelSmall())
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
    }

    @ViewBuilder
    private var searchResultsSection: some View {
        Section("Results (\(searchVM.results.count))") {
            if searchVM.results.isEmpty {
                Text("No articles match '\(searchVM.query)'")
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
                    .listRowBackground(Color.bizarreSurface1)
            } else {
                ForEach(searchVM.results) { article in
                    articleRow(article)
                }
            }
        }
    }

    // MARK: - Row helpers

    @ViewBuilder
    private func articleRow(_ article: HelpArticle) -> some View {
        NavigationLink(destination: HelpArticleView(article: article)) {
            VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                Text(article.title)
                    .font(.brandBodyLarge())
                    .foregroundStyle(.bizarreOnSurface)
                Text(article.category.rawValue)
                    .font(.brandLabelSmall())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
            .padding(.vertical, BrandSpacing.xs)
        }
        .listRowBackground(Color.bizarreSurface1)
        .accessibilityLabel("\(article.title), \(article.category.rawValue)")
        #if os(iOS)
        .hoverEffect(.highlight)
        #endif
    }

    @ViewBuilder
    private func categoryDetailList(cat: HelpArticle.Category, articles: [HelpArticle]) -> some View {
        List(articles) { article in
            NavigationLink(destination: HelpArticleView(article: article)) {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text(article.title)
                        .font(.brandBodyLarge())
                        .foregroundStyle(.bizarreOnSurface)
                }
                .padding(.vertical, BrandSpacing.xs)
            }
            .listRowBackground(Color.bizarreSurface1)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #endif
        .scrollContentBackground(.hidden)
        .background(Color.bizarreSurfaceBase.ignoresSafeArea())
        .navigationTitle(cat.rawValue)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            NavigationLink(destination: BugReportSheet()) {
                Label("Report a Bug", systemImage: "ladybug")
                    .accessibilityLabel("Report a Bug")
            }
            .brandGlass(interactive: true)
        }
    }

    // MARK: - Helpers

    private func categoryIcon(_ cat: HelpArticle.Category) -> String {
        switch cat {
        case .gettingStarted:  return "star.circle"
        case .tickets:         return "wrench.and.screwdriver"
        case .payments:        return "creditcard"
        case .inventory:       return "shippingbox"
        case .hardware:        return "printer"
        case .customers:       return "person.2"
        case .reports:         return "chart.bar"
        case .communications:  return "message"
        case .appointments:    return "calendar"
        case .loyalty:         return "heart.circle"
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview {
    HelpCenterView()
}
#endif
