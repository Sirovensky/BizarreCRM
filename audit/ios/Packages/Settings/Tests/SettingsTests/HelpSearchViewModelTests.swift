import Testing
@testable import Settings

// MARK: - HelpSearchViewModelTests

@Suite("HelpSearchViewModel")
@MainActor
struct HelpSearchViewModelTests {

    // MARK: - Catalog fixture

    private static let catalog: [HelpArticle] = [
        HelpArticle(
            id: "art.a",
            title: "Getting Started",
            category: .gettingStarted,
            markdown: "Login and explore.",
            tags: ["login", "setup"]
        ),
        HelpArticle(
            id: "art.b",
            title: "POS Basics",
            category: .payments,
            markdown: "Checkout flow.",
            tags: ["checkout", "pos"]
        ),
        HelpArticle(
            id: "art.c",
            title: "Barcode Scanning",
            category: .inventory,
            markdown: "Scan items with the camera.",
            tags: ["barcode", "camera"]
        )
    ]

    // MARK: - Initial state

    @Test("Initial results equal full catalog")
    func initialResultsEqualCatalog() {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        #expect(vm.results.count == Self.catalog.count)
    }

    @Test("Initial query is empty")
    func initialQueryIsEmpty() {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        #expect(vm.query.isEmpty)
    }

    // MARK: - Search filtering

    @Test("Search by title prefix returns matching article")
    func searchByTitlePrefix() async throws {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        vm.query = "pos"
        // Wait for the debounce Task to complete
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.contains(where: { $0.id == "art.b" }))
    }

    @Test("Search by tag returns matching article")
    func searchByTag() async throws {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        vm.query = "barcode"
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.contains(where: { $0.id == "art.c" }))
    }

    @Test("Search with no match returns empty results")
    func searchNoMatch() async throws {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        vm.query = "zzznomatch"
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.isEmpty)
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() async throws {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        vm.query = "GETTING"
        try await Task.sleep(for: .milliseconds(50))
        #expect(vm.results.contains(where: { $0.id == "art.a" }))
    }

    // MARK: - Clear

    @Test("Clear resets results to full catalog")
    func clearResetsResults() async throws {
        let vm = HelpSearchViewModel(catalog: Self.catalog, debounceInterval: .zero)
        vm.query = "pos"
        try await Task.sleep(for: .milliseconds(50))
        vm.clear()
        #expect(vm.query.isEmpty)
        #expect(vm.results.count == Self.catalog.count)
        #expect(!vm.isSearching)
    }

    // MARK: - Tokenizer

    @Test("Tokenize splits on non-alphanumeric chars")
    func tokenizeSplits() {
        let tokens = HelpSearchViewModel.tokenize("foo-bar baz")
        #expect(tokens.contains("foo"))
        #expect(tokens.contains("bar"))
        #expect(tokens.contains("baz"))
    }

    @Test("Tokenize drops single-char tokens")
    func tokenizeDropsSingle() {
        let tokens = HelpSearchViewModel.tokenize("a bb ccc")
        #expect(!tokens.contains("a"))
        #expect(tokens.contains("bb"))
        #expect(tokens.contains("ccc"))
    }

    @Test("Tokenize returns lowercase")
    func tokenizeLowercase() {
        let tokens = HelpSearchViewModel.tokenize("UPPER")
        #expect(tokens.contains("upper"))
    }

    // MARK: - Article catalog integrity

    @Test("Default catalog contains at least 15 articles")
    func defaultCatalogSize() {
        #expect(HelpArticleCatalog.all.count >= 15)
    }

    @Test("All catalog articles have unique IDs")
    func catalogUniqueIDs() {
        let ids = HelpArticleCatalog.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test("All catalog articles have non-empty titles")
    func catalogNonEmptyTitles() {
        for article in HelpArticleCatalog.all {
            #expect(!article.title.isEmpty, "Article \(article.id) has empty title")
        }
    }

    @Test("All catalog articles have non-empty markdown")
    func catalogNonEmptyMarkdown() {
        for article in HelpArticleCatalog.all {
            #expect(!article.markdown.isEmpty, "Article \(article.id) has empty markdown")
        }
    }
}
