import Foundation

// MARK: - HelpArticle

/// A single help-center article. Immutable value type — create new instances on update.
public struct HelpArticle: Identifiable, Sendable, Hashable {

    public enum Category: String, Sendable, CaseIterable, Hashable {
        case gettingStarted  = "Getting Started"
        case tickets         = "Tickets"
        case payments        = "Payments"
        case inventory       = "Inventory"
        case hardware        = "Hardware"
        case customers       = "Customers"
        case reports         = "Reports"
        case communications  = "Communications"
        case appointments    = "Appointments"
        case loyalty         = "Loyalty"
    }

    public let id: String
    public let title: String
    public let category: Category
    /// Bundled Markdown source.
    public let markdown: String
    public let tags: [String]
    public let relatedArticleIds: [String]

    public init(
        id: String,
        title: String,
        category: Category,
        markdown: String,
        tags: [String] = [],
        relatedArticleIds: [String] = []
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.markdown = markdown
        self.tags = tags
        self.relatedArticleIds = relatedArticleIds
    }
}
