import Foundation
import Observation
import Core

// MARK: - Notification name

public extension Notification.Name {
    /// Posted when the user defers the Setup Wizard. Observers (e.g. Dashboard)
    /// show a "Resume setup" banner. No userInfo required.
    static let setupStatusDeferred = Notification.Name("com.bizarrecrm.setup.deferred")
}

// MARK: - ViewModel

@MainActor
@Observable
public final class SetupWizardViewModel {

    // MARK: Published state

    public private(set) var currentStep: SetupStep = .welcome
    public private(set) var completedSteps: Set<Int> = []
    public private(set) var isSaving: Bool = false
    public private(set) var errorMessage: String? = nil
    public private(set) var isDismissed: Bool = false

    /// Drives the sheet/fullScreenCover presentation at the call site.
    public var isPresented: Bool = true

    // MARK: Dependencies

    @ObservationIgnored public let repository: any SetupRepository

    // MARK: Init

    public init(repository: any SetupRepository) {
        self.repository = repository
    }

    // MARK: Step navigation

    public var canGoBack: Bool {
        currentStep.previous != nil
    }

    public var canGoNext: Bool {
        !isSaving
    }

    public var isOnLastStep: Bool {
        currentStep == .complete
    }

    public var progress: Double {
        Double(currentStep.rawValue - 1) / Double(SetupStep.totalCount - 1)
    }

    public func goNext() async {
        guard let next = currentStep.next else {
            await finishWizard()
            return
        }
        await submitCurrentStep()
        currentStep = next
    }

    public func goBack() {
        guard let prev = currentStep.previous else { return }
        currentStep = prev
    }

    public func skipStep() async {
        guard let next = currentStep.next else {
            await finishWizard()
            return
        }
        currentStep = next
    }

    public func deferWizard() {
        isDismissed = true
        isPresented = false
        NotificationCenter.default.post(name: .setupStatusDeferred, object: nil)
        AppLog.ui.info("Setup Wizard deferred by user")
    }

    // MARK: Accumulated wizard payload

    /// Accumulated structured payload for the whole wizard. Step views write to
    /// this directly; `submitCurrentStep()` serialises the relevant subset.
    public var wizardPayload: SetupPayload = SetupPayload()

    // MARK: Step submission

    /// Override payload per step — callers inject via `pendingPayload`.
    /// Prefer writing to `wizardPayload` for typed steps 4-8.
    public var pendingPayload: [String: String] = [:]

    private func submitCurrentStep() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        let payload = resolvedPayload(for: currentStep)
        do {
            _ = try await repository.submitStep(currentStep.rawValue, payload: payload)
            completedSteps.insert(currentStep.rawValue)
            pendingPayload = [:]
        } catch {
            errorMessage = error.localizedDescription
            AppLog.ui.error("Setup step \(self.currentStep.rawValue) submit error: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Returns the flat [String:String] payload for the given step, merging
    /// typed `wizardPayload` fields with any legacy `pendingPayload` entries.
    private func resolvedPayload(for step: SetupStep) -> [String: String] {
        switch step {
        case .timezoneLocale:  return wizardPayload.timezoneLocalePayload()
        case .businessHours:   return wizardPayload.businessHoursPayload()
        case .taxSetup:        return wizardPayload.taxRatePayload()
        case .paymentMethods:  return wizardPayload.paymentMethodsPayload()
        case .firstLocation:   return wizardPayload.firstLocationPayload()
        case .teammates:       return wizardPayload.inviteesPayload()
        case .smsSetup:        return wizardPayload.smsPayload()
        case .deviceTemplates: return wizardPayload.deviceFamiliesPayload()
        case .dataImport:      return wizardPayload.importPayload()
        case .theme:           return wizardPayload.themePayload()
        default:               return pendingPayload
        }
    }

    private func finishWizard() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await repository.completeSetup()
            isDismissed = true
            isPresented = false
            AppLog.ui.info("Setup Wizard completed")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Server state loading

    public func loadServerState() async {
        do {
            let status = try await repository.fetchStatus()
            if let step = SetupStep(rawValue: status.currentStep) {
                currentStep = step
            }
            completedSteps = Set(status.completed)
        } catch {
            AppLog.ui.warning("Could not load setup status: \(error.localizedDescription, privacy: .public)")
        }
    }
}
