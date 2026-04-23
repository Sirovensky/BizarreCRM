import Foundation

// MARK: - List response

/// `GET /api/v1/expenses`.
/// Envelope: `{ expenses: [...], summary: {...}, categories: [...], pagination: {...} }`.
/// We expose `expenses` + `summary` at MVP; `categories` is for chart
/// screens (not wired yet).
public struct ExpensesListResponse: Decodable, Sendable {
    public let expenses: [Expense]
    public let summary: Summary?

    public init(expenses: [Expense], summary: Summary?) {
        self.expenses = expenses
        self.summary = summary
    }

    public struct Summary: Decodable, Sendable {
        public let totalAmount: Double
        public let totalCount: Int

        public init(totalAmount: Double, totalCount: Int) {
            self.totalAmount = totalAmount
            self.totalCount = totalCount
        }

        enum CodingKeys: String, CodingKey {
            case totalAmount = "total_amount"
            case totalCount = "total_count"
        }
    }
}

// MARK: - Expense model

/// Known approval statuses returned by the server.
public enum ExpenseStatus: String, Decodable, Sendable, CaseIterable {
    case pending
    case approved
    case denied
}

/// Payment method labels that match the category picker list in the server.
public enum PaymentMethod: String, CaseIterable, Sendable {
    case cash = "Cash"
    case creditCard = "Credit Card"
    case debitCard = "Debit Card"
    case bankTransfer = "Bank Transfer"
    case check = "Check"
    case other = "Other"
}

/// Server-side expense categories (§11.3 category picker list).
public enum ExpenseCategory: String, CaseIterable, Sendable {
    case rent = "Rent"
    case utilities = "Utilities"
    case parts = "Parts"
    case tools = "Tools"
    case marketing = "Marketing"
    case insurance = "Insurance"
    case payroll = "Payroll"
    case software = "Software"
    case officeSupplies = "Office Supplies"
    case shipping = "Shipping"
    case travel = "Travel"
    case maintenance = "Maintenance"
    case taxes = "Taxes"
    case fuel = "Fuel"
    case meals = "Meals"
    case other = "Other"
}

public struct Expense: Decodable, Sendable, Identifiable, Hashable {
    public let id: Int64
    public let category: String?
    public let amount: Double?
    public let description: String?
    public let date: String?
    public let receiptPath: String?
    /// Server field: `receipt_image_path` (upload route stamps this).
    public let receiptImagePath: String?
    public let receiptUploadedAt: String?
    public let userId: Int64?
    public let firstName: String?
    public let lastName: String?
    public let createdAt: String?
    public let updatedAt: String?
    // Extended fields (phase 4 write parity)
    public let vendor: String?
    public let taxAmount: Double?
    public let paymentMethod: String?
    public let notes: String?
    public let isReimbursable: Bool?
    public let status: String?
    public let expenseSubtype: String?
    public let approvedByUserId: Int64?
    public let approvedAt: String?
    public let denialReason: String?

    public var createdByName: String? {
        let parts = [firstName, lastName].compactMap { $0?.isEmpty == false ? $0 : nil }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Resolved receipt path — prefers `receiptImagePath` (set by upload route)
    /// and falls back to legacy `receiptPath`.
    public var resolvedReceiptPath: String? {
        receiptImagePath ?? receiptPath
    }

    public var approvalStatus: ExpenseStatus? {
        guard let s = status else { return nil }
        return ExpenseStatus(rawValue: s)
    }

    enum CodingKeys: String, CodingKey {
        case id, category, amount, description, date, vendor, notes, status
        case receiptPath = "receipt_path"
        case receiptImagePath = "receipt_image_path"
        case receiptUploadedAt = "receipt_uploaded_at"
        case userId = "user_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case taxAmount = "tax_amount"
        case paymentMethod = "payment_method"
        case isReimbursable = "is_reimbursable"
        case expenseSubtype = "expense_subtype"
        case approvedByUserId = "approved_by_user_id"
        case approvedAt = "approved_at"
        case denialReason = "denial_reason"
    }
}

// MARK: - Request bodies

/// Body for `POST /api/v1/expenses`.
public struct CreateExpenseRequest: Encodable, Sendable {
    public let category: String
    public let amount: Double
    public let description: String?
    public let date: String?
    public let vendor: String?
    public let taxAmount: Double?
    public let paymentMethod: String?
    public let notes: String?
    public let isReimbursable: Bool?

    public init(
        category: String,
        amount: Double,
        description: String? = nil,
        date: String? = nil,
        vendor: String? = nil,
        taxAmount: Double? = nil,
        paymentMethod: String? = nil,
        notes: String? = nil,
        isReimbursable: Bool? = nil
    ) {
        self.category = category
        self.amount = amount
        self.description = description
        self.date = date
        self.vendor = vendor
        self.taxAmount = taxAmount
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.isReimbursable = isReimbursable
    }

    enum CodingKeys: String, CodingKey {
        case category, amount, description, date, vendor, notes
        case taxAmount = "tax_amount"
        case paymentMethod = "payment_method"
        case isReimbursable = "is_reimbursable"
    }
}

/// Body for `PUT /api/v1/expenses/:id` — all fields optional (COALESCE on server).
public struct UpdateExpenseRequest: Encodable, Sendable {
    public let category: String?
    public let amount: Double?
    public let description: String?
    public let date: String?
    public let vendor: String?
    public let taxAmount: Double?
    public let paymentMethod: String?
    public let notes: String?
    public let isReimbursable: Bool?

    public init(
        category: String? = nil,
        amount: Double? = nil,
        description: String? = nil,
        date: String? = nil,
        vendor: String? = nil,
        taxAmount: Double? = nil,
        paymentMethod: String? = nil,
        notes: String? = nil,
        isReimbursable: Bool? = nil
    ) {
        self.category = category
        self.amount = amount
        self.description = description
        self.date = date
        self.vendor = vendor
        self.taxAmount = taxAmount
        self.paymentMethod = paymentMethod
        self.notes = notes
        self.isReimbursable = isReimbursable
    }

    enum CodingKeys: String, CodingKey {
        case category, amount, description, date, vendor, notes
        case taxAmount = "tax_amount"
        case paymentMethod = "payment_method"
        case isReimbursable = "is_reimbursable"
    }
}

/// Minimal response from `POST /api/v1/expenses` and
/// `PUT /api/v1/expenses/:id` — just the confirmed `id`.
public struct ExpenseWriteResponse: Decodable, Sendable {
    public let id: Int64
}

// MARK: - Receipt upload response

/// Row returned by `POST /api/v1/expenses/:id/receipt`.
public struct ExpenseReceiptUploadResponse: Decodable, Sendable {
    public let id: Int64
    public let expenseId: Int64
    public let filePath: String
    public let mimeType: String?
    public let ocrStatus: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case expenseId = "expense_id"
        case filePath = "file_path"
        case mimeType = "mime_type"
        case ocrStatus = "ocr_status"
        case createdAt = "created_at"
    }
}

/// Response from `GET /api/v1/expenses/:id/receipt`.
public struct ExpenseReceiptStatusResponse: Decodable, Sendable {
    public let expenseId: Int64
    public let receiptImagePath: String?
    public let receiptOcrText: String?
    public let receiptUploadedAt: String?

    enum CodingKeys: String, CodingKey {
        case expenseId = "expense_id"
        case receiptImagePath = "receipt_image_path"
        case receiptOcrText = "receipt_ocr_text"
        case receiptUploadedAt = "receipt_uploaded_at"
    }
}

// MARK: - APIClient extension

public extension APIClient {
    func listExpenses(keyword: String? = nil, category: String? = nil,
                      fromDate: String? = nil, toDate: String? = nil,
                      status: String? = nil,
                      pageSize: Int = 50) async throws -> ExpensesListResponse {
        var items: [URLQueryItem] = [URLQueryItem(name: "pagesize", value: String(pageSize))]
        if let k = keyword, !k.isEmpty { items.append(URLQueryItem(name: "keyword", value: k)) }
        if let c = category { items.append(URLQueryItem(name: "category", value: c)) }
        if let f = fromDate { items.append(URLQueryItem(name: "from_date", value: f)) }
        if let t = toDate { items.append(URLQueryItem(name: "to_date", value: t)) }
        if let s = status { items.append(URLQueryItem(name: "status", value: s)) }
        return try await get("/api/v1/expenses", query: items, as: ExpensesListResponse.self)
    }

    /// `GET /api/v1/expenses/:id` — single expense with user name fields.
    func getExpense(id: Int64) async throws -> Expense {
        try await get("/api/v1/expenses/\(id)", as: Expense.self)
    }

    /// `POST /api/v1/expenses` — create a general expense.
    func createExpense(_ body: CreateExpenseRequest) async throws -> ExpenseWriteResponse {
        try await post("/api/v1/expenses", body: body, as: ExpenseWriteResponse.self)
    }

    /// `PUT /api/v1/expenses/:id` — update an expense (COALESCE fields on server).
    func updateExpense(id: Int64, body: UpdateExpenseRequest) async throws -> ExpenseWriteResponse {
        try await put("/api/v1/expenses/\(id)", body: body, as: ExpenseWriteResponse.self)
    }

    /// `DELETE /api/v1/expenses/:id`.
    func deleteExpense(id: Int64) async throws {
        try await delete("/api/v1/expenses/\(id)")
    }

    /// `GET /api/v1/expenses/:id/receipt` — fetch current receipt status.
    func getExpenseReceiptStatus(expenseId: Int64) async throws -> ExpenseReceiptStatusResponse {
        try await get("/api/v1/expenses/\(expenseId)/receipt", as: ExpenseReceiptStatusResponse.self)
    }

    /// `DELETE /api/v1/expenses/:id/receipt` — remove the receipt from an expense.
    func deleteExpenseReceipt(expenseId: Int64) async throws {
        try await delete("/api/v1/expenses/\(expenseId)/receipt")
    }

    /// `POST /api/v1/expenses/:expenseId/receipt` — multipart/form-data upload.
    ///
    /// - Parameters:
    ///   - expenseId: Expense that will own the receipt.
    ///   - imageData: JPEG / PNG / WebP / HEIC bytes.
    ///   - mimeType: e.g. "image/jpeg" or "image/png".
    ///   - filename: Suggested filename (e.g. "receipt.jpg").
    ///   - authToken: Bearer token for the Authorization header.
    /// - Returns: The newly created `ExpenseReceiptUploadResponse`.
    ///
    /// Why not on the `APIClient` protocol? The protocol is in `Core/Networking`
    /// and is off-limits for §11. This free function uses `currentBaseURL()` /
    /// `authToken` exposed on the actor to compose the request without touching
    /// any protocol file.
    func uploadExpenseReceipt(
        expenseId: Int64,
        imageData: Data,
        mimeType: String,
        filename: String,
        authToken: String?
    ) async throws -> ExpenseReceiptUploadResponse {
        guard let base = await currentBaseURL() else {
            throw URLError(.badURL)
        }

        let path = "/api/v1/expenses/\(expenseId)/receipt"
        let url: URL
        if path.hasPrefix("http") {
            url = URL(string: path)!
        } else {
            let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
            url = base.appendingPathComponent(trimmed)
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        // Part header
        body.append("--\(boundary)\r\n".utf8Data)
        body.append("Content-Disposition: form-data; name=\"receipt\"; filename=\"\(filename)\"\r\n".utf8Data)
        body.append("Content-Type: \(mimeType)\r\n\r\n".utf8Data)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".utf8Data)

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ios", forHTTPHeaderField: "X-Origin")
        if let origin = Self.originString(for: url) {
            req.setValue(origin, forHTTPHeaderField: "Origin")
        }
        if let token = authToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(APIResponse<ExpenseReceiptUploadResponse>.self, from: data))?.message
            throw APITransportError.httpStatus(http.statusCode, message: msg)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(APIResponse<ExpenseReceiptUploadResponse>.self, from: data)
        guard envelope.success, let upload = envelope.data else {
            throw APITransportError.envelopeFailure(message: envelope.message)
        }
        return upload
    }
}

// MARK: - Private helpers (file-local, no protocol requirements)

private extension APIClient {
    static func originString(for url: URL) -> String? {
        guard let scheme = url.scheme, let host = url.host else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)"
    }
}

private extension String {
    var utf8Data: Data { Data(utf8) }
}
