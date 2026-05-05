import Testing
import Foundation
@testable import Settings

// MARK: - TrainingModeSettingsTests

@Suite("TrainingModeSettings — persistence")
@MainActor
struct TrainingModeSettingsTests {

    // MARK: - Helpers

    /// Returns a fresh SUT backed by an ephemeral UserDefaults suite.
    /// Each call gets a unique suite name so tests never bleed into each other.
    private func makeSUT() -> TrainingModeSettings {
        let suite = UserDefaults(suiteName: UUID().uuidString)!
        return TrainingModeSettings(defaults: suite)
    }

    // MARK: - Default state

    @Test("Default isEnabled is false when no value stored")
    func defaultIsDisabled() {
        let sut = makeSUT()
        #expect(sut.isEnabled == false)
    }

    // MARK: - enable()

    @Test("enable() sets isEnabled to true")
    func enableSetsTrue() {
        let sut = makeSUT()
        sut.enable()
        #expect(sut.isEnabled == true)
    }

    @Test("enable() is idempotent — calling twice stays true")
    func enableIdempotent() {
        let sut = makeSUT()
        sut.enable()
        sut.enable()
        #expect(sut.isEnabled == true)
    }

    // MARK: - disable()

    @Test("disable() sets isEnabled to false")
    func disableSetsfalse() {
        let sut = makeSUT()
        sut.enable()
        sut.disable()
        #expect(sut.isEnabled == false)
    }

    @Test("disable() is idempotent — calling twice stays false")
    func disableIdempotent() {
        let sut = makeSUT()
        sut.disable()
        sut.disable()
        #expect(sut.isEnabled == false)
    }

    // MARK: - toggle()

    @Test("toggle() flips false → true")
    func toggleFalseToTrue() {
        let sut = makeSUT()
        sut.toggle()
        #expect(sut.isEnabled == true)
    }

    @Test("toggle() flips true → false")
    func toggleTrueToFalse() {
        let sut = makeSUT()
        sut.enable()
        sut.toggle()
        #expect(sut.isEnabled == false)
    }

    @Test("toggle() round-trips back to original value")
    func toggleRoundTrip() {
        let sut = makeSUT()
        let initial = sut.isEnabled
        sut.toggle()
        sut.toggle()
        #expect(sut.isEnabled == initial)
    }

    // MARK: - Persistence across instances

    @Test("Value persists when a second instance is created from the same suite")
    func persistenceAcrossInstances() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!

        let sut1 = TrainingModeSettings(defaults: defaults)
        sut1.enable()

        // Simulate app restart: new instance, same suite
        let sut2 = TrainingModeSettings(defaults: defaults)
        #expect(sut2.isEnabled == true)
    }

    @Test("Disabling persists when a second instance is created from the same suite")
    func disablePersistsAcrossInstances() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!

        let sut1 = TrainingModeSettings(defaults: defaults)
        sut1.enable()
        sut1.disable()

        let sut2 = TrainingModeSettings(defaults: defaults)
        #expect(sut2.isEnabled == false)
    }

    // MARK: - Direct assignment

    @Test("Direct assignment to isEnabled = true persists")
    func directAssignmentTrue() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = TrainingModeSettings(defaults: defaults)
        sut.isEnabled = true

        let sut2 = TrainingModeSettings(defaults: defaults)
        #expect(sut2.isEnabled == true)
    }

    @Test("Direct assignment to isEnabled = false persists")
    func directAssignmentFalse() {
        let suiteName = UUID().uuidString
        let defaults = UserDefaults(suiteName: suiteName)!
        let sut = TrainingModeSettings(defaults: defaults)
        sut.isEnabled = true
        sut.isEnabled = false

        let sut2 = TrainingModeSettings(defaults: defaults)
        #expect(sut2.isEnabled == false)
    }
}

// MARK: - TrainingModeViewModelTests

@Suite("TrainingModeViewModel — state transitions")
@MainActor
struct TrainingModeViewModelTests {

    // MARK: - Helpers

    private func makeSUT() -> (vm: TrainingModeViewModel, settings: TrainingModeSettings) {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let settings = TrainingModeSettings(defaults: defaults)
        let vm = TrainingModeViewModel(settings: settings)
        return (vm, settings)
    }

    // MARK: - Initial state

    @Test("ViewModel reflects settings.isEnabled = false initially")
    func initialStateIsDisabled() {
        let (vm, _) = makeSUT()
        #expect(vm.isEnabled == false)
        #expect(vm.toggleState == .idle)
        #expect(vm.showEnterSheet == false)
    }

    // MARK: - didTapToggle() when disabled

    @Test("didTapToggle() when disabled raises showEnterSheet and enters pendingConfirmation")
    func tapToggleWhenDisabledRaisesSheet() {
        let (vm, _) = makeSUT()
        vm.didTapToggle()
        #expect(vm.toggleState == .pendingConfirmation)
        #expect(vm.showEnterSheet == true)
        // Should NOT have enabled yet — confirmation pending
        #expect(vm.isEnabled == false)
    }

    // MARK: - confirmEnable()

    @Test("confirmEnable() enables training mode and returns to idle")
    func confirmEnableEnablesAndIdle() {
        let (vm, settings) = makeSUT()
        vm.didTapToggle()
        vm.confirmEnable()
        #expect(vm.toggleState == .idle)
        #expect(vm.showEnterSheet == false)
        #expect(vm.isEnabled == true)
        #expect(settings.isEnabled == true)
    }

    @Test("confirmEnable() is no-op if state is not pendingConfirmation")
    func confirmEnableNoOpWhenIdle() {
        let (vm, settings) = makeSUT()
        // Call confirm without going through the tap flow
        vm.confirmEnable()
        #expect(vm.isEnabled == false)
        #expect(settings.isEnabled == false)
        #expect(vm.toggleState == .idle)
    }

    // MARK: - cancelEnable()

    @Test("cancelEnable() returns to idle without enabling")
    func cancelEnableDoesNotEnable() {
        let (vm, settings) = makeSUT()
        vm.didTapToggle()
        vm.cancelEnable()
        #expect(vm.toggleState == .idle)
        #expect(vm.showEnterSheet == false)
        #expect(vm.isEnabled == false)
        #expect(settings.isEnabled == false)
    }

    @Test("cancelEnable() is no-op if state is not pendingConfirmation")
    func cancelEnableNoOpWhenIdle() {
        let (vm, _) = makeSUT()
        vm.cancelEnable()
        #expect(vm.toggleState == .idle)
        #expect(vm.showEnterSheet == false)
    }

    // MARK: - didTapToggle() when enabled

    @Test("didTapToggle() when enabled disables immediately without confirmation")
    func tapToggleWhenEnabledDisablesImmediately() {
        let (vm, settings) = makeSUT()
        settings.enable()
        #expect(vm.isEnabled == true)
        vm.didTapToggle()
        #expect(vm.isEnabled == false)
        #expect(vm.toggleState == .idle)
        #expect(vm.showEnterSheet == false)
    }

    // MARK: - Full enable/disable round-trip

    @Test("Full enable → disable round-trip transitions correctly")
    func fullRoundTrip() {
        let (vm, settings) = makeSUT()

        // Enable flow
        vm.didTapToggle()
        #expect(vm.toggleState == .pendingConfirmation)
        vm.confirmEnable()
        #expect(vm.isEnabled == true)
        #expect(settings.isEnabled == true)

        // Disable flow — no sheet
        vm.didTapToggle()
        #expect(vm.isEnabled == false)
        #expect(settings.isEnabled == false)
        #expect(vm.toggleState == .idle)
    }

    // MARK: - Multiple enable/disable cycles

    @Test("Multiple enable/disable cycles maintain consistent state")
    func multipleCycles() {
        let (vm, settings) = makeSUT()

        for _ in 1...3 {
            vm.didTapToggle()
            vm.confirmEnable()
            #expect(settings.isEnabled == true)

            vm.didTapToggle()
            #expect(settings.isEnabled == false)
        }
        #expect(vm.toggleState == .idle)
    }

    // MARK: - isEnabled mirrors settings

    @Test("isEnabled reflects the injected settings object at all times")
    func isEnabledMirrorsSettings() {
        let (vm, settings) = makeSUT()
        settings.enable()
        #expect(vm.isEnabled == true)
        settings.disable()
        #expect(vm.isEnabled == false)
    }
}
