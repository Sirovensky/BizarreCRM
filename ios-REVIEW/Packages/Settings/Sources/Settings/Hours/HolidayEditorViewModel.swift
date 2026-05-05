import Foundation
import Observation

// MARK: - §19 HolidayEditorViewModel

public enum HolidayEditorMode: Sendable {
    case create
    case edit(HolidayException)
}

@Observable
@MainActor
public final class HolidayEditorViewModel {

    // MARK: - Editable state

    public var date: Date
    public var isOpen: Bool
    public var openAt: DateComponents
    public var closeAt: DateComponents
    public var reason: String
    public var recurring: Recurrence

    public var isSaving: Bool = false
    public var errorMessage: String?
    public var saveSucceeded: Bool = false

    // MARK: - Internal

    private let mode: HolidayEditorMode
    private let repository: any HoursRepository

    // MARK: - Init

    public init(mode: HolidayEditorMode, repository: any HoursRepository) {
        self.mode = mode
        self.repository = repository

        switch mode {
        case .create:
            self.date = Date()
            self.isOpen = false
            self.openAt = DateComponents(hour: 9, minute: 0)
            self.closeAt = DateComponents(hour: 17, minute: 0)
            self.reason = ""
            self.recurring = .once

        case .edit(let holiday):
            self.date = holiday.date
            self.isOpen = holiday.isOpen
            self.openAt = holiday.openAt ?? DateComponents(hour: 9, minute: 0)
            self.closeAt = holiday.closeAt ?? DateComponents(hour: 17, minute: 0)
            self.reason = holiday.reason
            self.recurring = holiday.recurring
        }
    }

    // MARK: - Validation

    public var isValid: Bool {
        !reason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Save

    public func save() async {
        guard isValid else {
            errorMessage = "Please enter a reason for this holiday."
            return
        }

        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let holiday = buildHoliday()

        do {
            switch mode {
            case .create:
                _ = try await repository.createHoliday(holiday)
            case .edit:
                _ = try await repository.updateHoliday(holiday)
            }
            saveSucceeded = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Private

    private func buildHoliday() -> HolidayException {
        let existingID: String
        if case .edit(let h) = mode {
            existingID = h.id
        } else {
            existingID = UUID().uuidString
        }

        return HolidayException(
            id: existingID,
            date: date,
            isOpen: isOpen,
            openAt: isOpen ? openAt : nil,
            closeAt: isOpen ? closeAt : nil,
            reason: reason.trimmingCharacters(in: .whitespaces),
            recurring: recurring
        )
    }
}
