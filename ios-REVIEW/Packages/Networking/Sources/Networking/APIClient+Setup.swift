import Foundation

// MARK: - Setup Wizard — Networking layer
//
// Server routes (grounded from packages/server/src/routes/):
//
//   Settings (prefix: /api/v1/settings — registered in index.ts l.1556):
//     GET  /setup-status          → { success, data: { setup_completed, store_name, wizard_completed } }
//     POST /complete-setup        → { success, data: { message } }
//
//   Onboarding (prefix: /api/v1/onboarding — registered in index.ts l.1637):
//     GET    /state               → { success, data: OnboardingStateResponse }
//     PATCH  /state               → { success, data: OnboardingStateResponse }  (boolean flags only)
//     POST   /sample-data         → { success, data: { state, created, counts? } }
//     DELETE /sample-data         → { success, data: { state, removed } }
//     POST   /set-shop-type       → { success, data: { state, templates_installed } }
//
//   Settings users (prefix: /api/v1/settings — admin only):
//     POST /users                 → { success, data: User }
//
// NOTE: The Setup package's SetupEndpoints.swift has its own APIClient extension
// covering the wizard step-submission bridge routes (setup/status, setup/step/:n,
// setup/complete). This file provides the *server-grounded* counterparts used
// directly by new wizard steps that need real endpoints.
//
// Envelope: { success: Bool, data: T?, message: String? }  — see APIResponse.swift.

// MARK: - Setup Status

public struct SetupStatusData: Decodable, Sendable {
    public let setupCompleted: Bool
    public let storeName: String?
    /// "true" | "skipped" | "grandfathered" | nil
    public let wizardCompleted: String?

    public init(setupCompleted: Bool, storeName: String?, wizardCompleted: String?) {
        self.setupCompleted = setupCompleted
        self.storeName = storeName
        self.wizardCompleted = wizardCompleted
    }

    enum CodingKeys: String, CodingKey {
        case setupCompleted    = "setup_completed"
        case storeName         = "store_name"
        case wizardCompleted   = "wizard_completed"
    }
}

// MARK: - Complete Setup

public struct CompleteSetupBody: Encodable, Sendable {
    public let storeName: String
    public let address: String?
    public let phone: String?
    public let email: String?
    public let timezone: String?
    public let currency: String?

    public init(
        storeName: String,
        address: String? = nil,
        phone: String? = nil,
        email: String? = nil,
        timezone: String? = nil,
        currency: String? = nil
    ) {
        self.storeName = storeName
        self.address = address
        self.phone = phone
        self.email = email
        self.timezone = timezone
        self.currency = currency
    }

    enum CodingKeys: String, CodingKey {
        case storeName = "store_name"
        case address, phone, email, timezone, currency
    }
}

public struct CompleteSetupData: Decodable, Sendable {
    public let message: String?
    public init(message: String?) { self.message = message }
}

// MARK: - Onboarding State

/// Maps the server's `OnboardingStateResponse` shape.
public struct OnboardingState: Decodable, Sendable {
    public let checklistDismissed: Bool
    public let shopType: String?
    public let sampleDataLoaded: Bool
    public let sampleDataCounts: SampleDataCounts?
    public let firstCustomerAt: String?
    public let firstTicketAt: String?
    public let createdAt: String?

    public init(
        checklistDismissed: Bool,
        shopType: String?,
        sampleDataLoaded: Bool,
        sampleDataCounts: SampleDataCounts?,
        firstCustomerAt: String?,
        firstTicketAt: String?,
        createdAt: String?
    ) {
        self.checklistDismissed = checklistDismissed
        self.shopType = shopType
        self.sampleDataLoaded = sampleDataLoaded
        self.sampleDataCounts = sampleDataCounts
        self.firstCustomerAt = firstCustomerAt
        self.firstTicketAt = firstTicketAt
        self.createdAt = createdAt
    }

    enum CodingKeys: String, CodingKey {
        case checklistDismissed = "checklist_dismissed"
        case shopType           = "shop_type"
        case sampleDataLoaded   = "sample_data_loaded"
        case sampleDataCounts   = "sample_data_counts"
        case firstCustomerAt    = "first_customer_at"
        case firstTicketAt      = "first_ticket_at"
        case createdAt          = "created_at"
    }
}

public struct SampleDataCounts: Decodable, Sendable, Equatable {
    public let customers: Int
    public let tickets: Int
    public let invoices: Int
    public let parts: Int

    public init(customers: Int, tickets: Int, invoices: Int, parts: Int) {
        self.customers = customers
        self.tickets = tickets
        self.invoices = invoices
        self.parts = parts
    }
}

/// POST /api/v1/onboarding/sample-data response `data` field.
public struct SampleDataResult: Decodable, Sendable {
    public let state: OnboardingState
    public let created: Bool
    public let counts: SampleDataCounts?

    public init(state: OnboardingState, created: Bool, counts: SampleDataCounts?) {
        self.state = state
        self.created = created
        self.counts = counts
    }
}

/// DELETE /api/v1/onboarding/sample-data response `data` field.
public struct SampleDataRemoveResult: Decodable, Sendable {
    public let state: OnboardingState
    public let removed: Int

    public init(state: OnboardingState, removed: Int) {
        self.state = state
        self.removed = removed
    }
}

/// POST /api/v1/onboarding/set-shop-type body.
public struct SetShopTypeBody: Encodable, Sendable {
    public let shopType: String

    public init(shopType: String) { self.shopType = shopType }

    enum CodingKeys: String, CodingKey {
        case shopType = "shop_type"
    }
}

/// POST /api/v1/onboarding/set-shop-type response `data` field.
public struct SetShopTypeResult: Decodable, Sendable {
    public let state: OnboardingState
    public let templatesInstalled: Int

    public init(state: OnboardingState, templatesInstalled: Int) {
        self.state = state
        self.templatesInstalled = templatesInstalled
    }

    enum CodingKeys: String, CodingKey {
        case state
        case templatesInstalled = "templates_installed"
    }
}

// MARK: - First Employee (POST /api/v1/settings/users — admin only)

public struct CreateUserBody: Encodable, Sendable {
    public let firstName: String
    public let lastName: String
    public let email: String
    public let role: String
    public let phone: String?

    public init(
        firstName: String,
        lastName: String,
        email: String,
        role: String,
        phone: String? = nil
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.role = role
        self.phone = phone
    }

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName  = "last_name"
        case email, role, phone
    }
}

public struct CreatedUser: Decodable, Sendable {
    public let id: Int64
    public let firstName: String
    public let lastName: String
    public let email: String
    public let role: String

    public init(id: Int64, firstName: String, lastName: String, email: String, role: String) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.role = role
    }

    enum CodingKeys: String, CodingKey {
        case id
        case firstName = "first_name"
        case lastName  = "last_name"
        case email, role
    }
}

// MARK: - APIClient extensions

public extension APIClient {

    // MARK: Settings — Setup Status

    /// GET /api/v1/settings/setup-status
    func fetchSetupStatus() async throws -> SetupStatusData {
        try await get("settings/setup-status", as: SetupStatusData.self)
    }

    // MARK: Settings — Complete Setup

    /// POST /api/v1/settings/complete-setup
    /// Saves store info and marks wizard_completed='true'.
    func completeSetupWizard(_ body: CompleteSetupBody) async throws -> CompleteSetupData {
        try await post("settings/complete-setup", body: body, as: CompleteSetupData.self)
    }

    // MARK: Onboarding State

    /// GET /api/v1/onboarding/state
    func fetchOnboardingState() async throws -> OnboardingState {
        try await get("onboarding/state", as: OnboardingState.self)
    }

    // MARK: Onboarding — Sample Data

    /// POST /api/v1/onboarding/sample-data
    /// Idempotent: if data already loaded, returns `created: false`.
    /// Admin/manager/owner role required on the server.
    func loadSampleData() async throws -> SampleDataResult {
        try await post("onboarding/sample-data", body: EmptyBody(), as: SampleDataResult.self)
    }

    /// DELETE /api/v1/onboarding/sample-data
    /// Removes all sample rows tagged with [Sample].
    /// Returns the result including removed count, then re-fetches state to surface updated counts.
    func removeSampleData() async throws {
        try await delete("onboarding/sample-data")
    }

    // MARK: Onboarding — Shop Type

    /// POST /api/v1/onboarding/set-shop-type
    func setShopType(_ shopType: String) async throws -> SetShopTypeResult {
        let body = SetShopTypeBody(shopType: shopType)
        return try await post("onboarding/set-shop-type", body: body, as: SetShopTypeResult.self)
    }

    // MARK: Settings — Users (first employee)

    /// POST /api/v1/settings/users
    /// Admin only. Creates a new user (employee) account.
    func createFirstEmployee(_ body: CreateUserBody) async throws -> CreatedUser {
        try await post("settings/users", body: body, as: CreatedUser.self)
    }
}
