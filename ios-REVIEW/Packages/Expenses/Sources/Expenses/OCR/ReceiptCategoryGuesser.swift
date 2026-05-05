import Foundation

// MARK: - ReceiptCategoryGuesser

/// Pure stateless utility. Given a merchant name, returns the most likely
/// expense category. Matching is case-insensitive and partial.
public enum ReceiptCategoryGuesser {

    // MARK: - Types

    public enum Category: String, Sendable, CaseIterable, Equatable {
        case supplies = "Supplies"
        case fuel = "Fuel"
        case meals = "Meals"
        case travel = "Travel"
        case utilities = "Utilities"
        case software = "Software"
        case office = "Office Supplies"
        case maintenance = "Maintenance"
        case marketing = "Marketing"
        case shipping = "Shipping"
        case insurance = "Insurance"
        case rent = "Rent"
        case other = "Other"
    }

    // MARK: - Rules

    /// Each rule is an array of merchant name fragments (lowercased) → category.
    private static let rules: [(fragments: [String], category: Category)] = [
        // Fuel
        (["shell", "bp", "exxon", "mobil", "chevron", "sunoco", "arco", "texaco",
          "valero", "speedway", "pilot", "flying j", "fuel", "gas station", "gasoline",
          "petro", "love's", "wawa", "kwik trip", "circle k", "casey's"], .fuel),

        // Meals
        (["mcdonald", "starbucks", "chipotle", "subway", "dunkin", "domino",
          "pizza", "burger", "taco", "wendy", "chick-fil", "panera", "grubhub",
          "doordash", "uber eats", "restaurant", "cafe", "coffee", "diner", "bistro",
          "sushi", "bbq", "grill", "kitchen", "eatery", "deli", "poke", "ramen",
          "noodle", "bar & grill", "pub"], .meals),

        // Travel
        (["delta", "united airlines", "american airlines", "southwest", "jetblue",
          "spirit airlines", "frontier", "alaska airlines", "airbnb", "marriott",
          "hilton", "hyatt", "sheraton", "westin", "hotel", "motel", "inn",
          "doubletree", "holiday inn", "uber", "lyft", "taxi", "enterprise rent",
          "hertz", "avis", "budget car", "amtrak", "expedia", "booking.com",
          "travelport", "priceline"], .travel),

        // Software / SaaS
        (["adobe", "microsoft", "github", "aws", "amazon web", "google cloud",
          "dropbox", "slack", "zoom", "atlassian", "jira", "notion", "figma",
          "shopify", "quickbooks", "xero", "stripe", "twilio", "digitalocean",
          "netlify", "vercel", "cloudflare", "salesforce", "hubspot", "zendesk",
          "app store", "google play", "saas", "software"], .software),

        // Shipping
        (["fedex", "ups", "usps", "dhl", "ups store", "postal", "shipping",
          "freight", "courier", "logistics"], .shipping),

        // Office Supplies
        (["staples", "office depot", "officemax", "uline", "quill", "viking",
          "brother", "epson", "canon", "hp supply", "paper", "toner", "ink",
          "printful", "print", "office supply", "stationery"], .office),

        // Supplies / Hardware
        (["home depot", "lowe's", "lowes", "ace hardware", "menards", "harbor freight",
          "fastenal", "grainger", "amazon", "walmart", "costco", "sam's club",
          "target", "best buy", "supplies", "parts", "hardware", "tool"], .supplies),

        // Utilities
        (["at&t", "verizon", "comcast", "xfinity", "spectrum", "t-mobile",
          "sprint", "electric", "power company", "water company", "pg&e",
          "con edison", "duke energy", "utility", "internet", "broadband",
          "phone bill", "wireless"], .utilities),

        // Marketing
        (["google ads", "facebook ads", "meta ads", "instagram ads", "yelp",
          "canva", "mailchimp", "constant contact", "advertising", "marketing",
          "media", "pr firm", "seo", "social media"], .marketing),

        // Insurance
        (["allstate", "geico", "state farm", "progressive", "liberty mutual",
          "farmers", "nationwide", "travelers", "aetna", "cigna", "humana",
          "blue cross", "insurance", "insurer", "premium"], .insurance),

        // Rent
        (["property management", "realty", "rent", "lease", "rental", "landlord"], .rent),

        // Maintenance
        (["jiffy lube", "midas", "pep boys", "o'reilly", "autozone", "napa auto",
          "car wash", "mechanic", "auto repair", "brake", "oil change",
          "tire", "muffler", "hvac", "plumber", "electrician", "repair service",
          "maintenance", "service center"], .maintenance),
    ]

    // MARK: - Public API

    /// Returns the best-guess category for the given merchant name, or `nil`
    /// if no rule matches.
    public static func guess(merchantName: String) -> Category? {
        let lower = merchantName.lowercased()
        for rule in rules {
            if rule.fragments.contains(where: { lower.contains($0) }) {
                return rule.category
            }
        }
        return nil
    }

    /// Returns the category's raw string value, or "Other" when unknown.
    public static func categoryString(for merchantName: String) -> String {
        guess(merchantName: merchantName)?.rawValue ?? Category.other.rawValue
    }
}
