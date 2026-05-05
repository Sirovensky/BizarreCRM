import Foundation

// MARK: - PTOType

public enum PTOType: String, Codable, CaseIterable, Sendable {
    case vacation = "vacation"
    case sick     = "sick"
    case personal = "personal"
    case unpaid   = "unpaid"

    public var displayName: String {
        switch self {
        case .vacation: return "Vacation"
        case .sick:     return "Sick Leave"
        case .personal: return "Personal"
        case .unpaid:   return "Unpaid"
        }
    }
}

// MARK: - PTOStatus

public enum PTOStatus: String, Codable, CaseIterable, Sendable {
    case pending  = "pending"
    case approved = "approved"
    case denied   = "denied"
    case canceled = "canceled"
}

// MARK: - PTORequest

public struct PTORequest: Codable, Sendable, Identifiable, Hashable {
    public let id: String
    public var employeeId: String
    public var type: PTOType
    public var startDate: Date
    public var endDate: Date
    public var reason: String
    public var status: PTOStatus
    public var reviewedBy: String?

    public init(
        id: String,
        employeeId: String,
        type: PTOType,
        startDate: Date,
        endDate: Date,
        reason: String = "",
        status: PTOStatus = .pending,
        reviewedBy: String? = nil
    ) {
        self.id = id
        self.employeeId = employeeId
        self.type = type
        self.startDate = startDate
        self.endDate = endDate
        self.reason = reason
        self.status = status
        self.reviewedBy = reviewedBy
    }

    enum CodingKeys: String, CodingKey {
        case id, type, reason, status
        case employeeId = "employee_id"
        case startDate  = "start_date"
        case endDate    = "end_date"
        case reviewedBy = "reviewed_by"
    }

    /// Calendar days requested (inclusive).
    public var calendarDays: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: startDate, to: endDate).day.map { $0 + 1 } ?? 1
    }
}

// MARK: - PTOBalanceTracker

/// Pure stateless accrual helper. Fully testable without mocks.
/// Required 80%+ test coverage per §46 constraints.
public enum PTOBalanceTracker: Sendable {

    /// Compute available PTO balance as of `asOf`.
    ///
    /// - Parameters:
    ///   - employeeId: Identifier (unused in computation, included for traceability).
    ///   - accrualRate: Days accrued per year.
    ///   - usedDays: Days already consumed.
    ///   - asOf: Reference date. Accrual prorated to this date from `hireDate`.
    ///   - hireDate: Employee hire date. Defaults to start of current year.
    public static func computeBalance(
        employeeId: String,
        accrualRate: Double,
        usedDays: Int,
        asOf: Date,
        hireDate: Date = Calendar.current.date(from: Calendar.current.dateComponents([.year], from: Date())) ?? Date()
    ) -> Double {
        let cal = Calendar.current
        let effectiveStart = max(hireDate, cal.startOfYear(for: asOf))
        let elapsed = asOf.timeIntervalSince(effectiveStart)
        let yearSeconds: Double = 365.25 * 24 * 3600
        let fraction = min(max(elapsed / yearSeconds, 0), 1)
        let accrued = accrualRate * fraction
        return max(accrued - Double(usedDays), 0)
    }
}

// MARK: - Calendar helper

private extension Calendar {
    func startOfYear(for date: Date) -> Date {
        let comps = dateComponents([.year], from: date)
        return self.date(from: comps) ?? date
    }
}
