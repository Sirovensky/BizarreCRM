import Foundation

// MARK: - ConflictResult

public enum ScheduleConflict: Sendable, Equatable {
    /// Two shifts for the same employee overlap in time.
    case doubleBooking(employeeId: Int64, existingShiftId: Int64, newStartAt: String, newEndAt: String)
    /// The shift overlaps with an approved PTO block for that employee.
    case ptoOverlap(employeeId: Int64, ptoDescription: String)
}

// MARK: - PTOBlock

/// Minimal PTO representation needed for overlap checking.
public struct PTOBlock: Sendable, Equatable {
    public let employeeId: Int64
    public let startAt: String
    public let endAt: String
    public let description: String

    public init(employeeId: Int64, startAt: String, endAt: String, description: String = "") {
        self.employeeId = employeeId
        self.startAt = startAt
        self.endAt = endAt
        self.description = description
    }
}

// MARK: - ShiftScheduleConflictChecker

/// Pure, stateless conflict detector.
///
/// Detects:
/// 1. Double-booking — same employee scheduled for overlapping shifts.
/// 2. PTO overlap — shift overlaps an approved PTO block.
///
/// All times are compared in UTC. Returns every conflict found.
public enum ShiftScheduleConflictChecker {

    // MARK: - Public

    /// Check a proposed new shift against existing shifts and PTO blocks.
    public static func check(
        proposed: CreateScheduledShiftBody,
        existingShifts: [ScheduledShift],
        ptoBlocks: [PTOBlock]
    ) -> [ScheduleConflict] {
        let parser = ISO8601DateFormatter()
        guard let propStart = parser.date(from: proposed.startAt),
              let propEnd   = parser.date(from: proposed.endAt),
              propEnd > propStart
        else { return [] }

        var conflicts: [ScheduleConflict] = []

        // 1. Double-booking check
        let sameEmployee = existingShifts.filter { $0.employeeId == proposed.employeeId }
        for existing in sameEmployee {
            guard let exStart = parser.date(from: existing.startAt),
                  let exEnd   = parser.date(from: existing.endAt)
            else { continue }
            if overlaps(aStart: propStart, aEnd: propEnd, bStart: exStart, bEnd: exEnd) {
                conflicts.append(.doubleBooking(
                    employeeId: proposed.employeeId,
                    existingShiftId: existing.id,
                    newStartAt: proposed.startAt,
                    newEndAt: proposed.endAt
                ))
            }
        }

        // 2. PTO overlap check
        let empPTO = ptoBlocks.filter { $0.employeeId == proposed.employeeId }
        for pto in empPTO {
            guard let ptoStart = parser.date(from: pto.startAt),
                  let ptoEnd   = parser.date(from: pto.endAt)
            else { continue }
            if overlaps(aStart: propStart, aEnd: propEnd, bStart: ptoStart, bEnd: ptoEnd) {
                conflicts.append(.ptoOverlap(
                    employeeId: proposed.employeeId,
                    ptoDescription: pto.description
                ))
            }
        }

        return conflicts
    }

    /// Check a full proposed week of shifts against each other and PTO.
    public static func checkAll(
        proposed: [CreateScheduledShiftBody],
        existingShifts: [ScheduledShift],
        ptoBlocks: [PTOBlock]
    ) -> [ScheduleConflict] {
        var all: [ScheduleConflict] = []
        for (i, shift) in proposed.enumerated() {
            let otherProposed: [ScheduledShift] = proposed
                .enumerated()
                .filter { $0.offset != i }
                .map { pair in
                    ScheduledShift(
                        id: Int64(-(pair.offset + 1)),
                        employeeId: pair.element.employeeId,
                        startAt: pair.element.startAt,
                        endAt: pair.element.endAt,
                        role: pair.element.role,
                        notes: pair.element.notes
                    )
                }
            let conflicts = check(
                proposed: shift,
                existingShifts: existingShifts + otherProposed,
                ptoBlocks: ptoBlocks
            )
            all.append(contentsOf: conflicts)
        }
        // Deduplicate
        var seen = Set<ScheduleConflict>()
        return all.filter { seen.insert($0).inserted }
            .sorted { "\($0)" < "\($1)" }
    }

    // MARK: - Private

    /// Half-open interval overlap: [aStart, aEnd) ∩ [bStart, bEnd)
    private static func overlaps(aStart: Date, aEnd: Date, bStart: Date, bEnd: Date) -> Bool {
        aStart < bEnd && bStart < aEnd
    }
}

// Hashable conformance for dedup
extension ScheduleConflict: Hashable {}
