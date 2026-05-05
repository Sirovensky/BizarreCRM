import Foundation
import Observation
import SwiftUI
import DesignSystem

// MARK: - TrainingModeViewModel

/// Drives the Training Mode settings row and its confirmation sheet flow.
///
/// Place this in a parent view via `@State`:
///
/// ```swift
/// @State private var vm = TrainingModeViewModel()
///
/// var body: some View {
///     TrainingModeSettingsRow(vm: vm)
///         .sheet(isPresented: $vm.showEnterSheet) {
///             TrainingModeEnterSheet(
///                 onConfirm: vm.confirmEnable,
///                 onCancel:  vm.cancelEnable
///             )
///         }
/// }
/// ```
///
/// The VM owns no networking. Training Mode is a local flag backed by
/// `TrainingModeSettings`; no server round-trip is needed at toggle time.
@Observable
@MainActor
public final class TrainingModeViewModel: Sendable {

    // MARK: - Nested types

    /// State machine for the enable / disable flow.
    public enum ToggleState: Equatable, Sendable {
        /// Idle — current value reflects `settings.isEnabled`.
        case idle
        /// Waiting for user to confirm via `TrainingModeEnterSheet`.
        case pendingConfirmation
        /// Transitioning — brief moment between confirm tap and `isEnabled = true`.
        case enabling
        /// Transitioning — brief moment between disable tap and `isEnabled = false`.
        case disabling
    }

    // MARK: - Dependencies

    private let settings: TrainingModeSettings

    // MARK: - Observed state

    /// Whether Training Mode is currently enabled in the underlying store.
    public var isEnabled: Bool { settings.isEnabled }

    /// Drives the `TrainingModeEnterSheet` presentation.
    public var showEnterSheet: Bool = false

    /// Current state machine position.
    public private(set) var toggleState: ToggleState = .idle

    // MARK: - Init

    public init(settings: TrainingModeSettings = .shared) {
        self.settings = settings
    }

    // MARK: - User actions

    /// Called when the user taps the toggle row.
    ///
    /// - Enabling path: enters `.pendingConfirmation`, raises `showEnterSheet`.
    /// - Disabling path: disables immediately (no confirmation needed).
    public func didTapToggle() {
        if settings.isEnabled {
            disable()
        } else {
            toggleState = .pendingConfirmation
            showEnterSheet = true
        }
    }

    /// Called by `TrainingModeEnterSheet.onConfirm`.
    /// Transitions through `.enabling` then sets the persistent flag.
    public func confirmEnable() {
        guard toggleState == .pendingConfirmation else { return }
        toggleState = .enabling
        showEnterSheet = false
        settings.enable()
        toggleState = .idle
    }

    /// Called by `TrainingModeEnterSheet.onCancel`.
    /// Returns to idle without mutating the flag.
    public func cancelEnable() {
        guard toggleState == .pendingConfirmation else { return }
        toggleState = .idle
        showEnterSheet = false
    }

    // MARK: - Private

    private func disable() {
        toggleState = .disabling
        settings.disable()
        toggleState = .idle
    }
}

// MARK: - TrainingModeSettingsRow

/// Settings list row that wires up the toggle + sheet entry point.
/// Drop this inside any `Form` / `List` section that §19 or an owner decides
/// to include.
///
/// The sheet is presented from within this view so callers need no extra
/// binding management.
public struct TrainingModeSettingsRow: View {

    @Bindable var vm: TrainingModeViewModel

    public init(vm: TrainingModeViewModel) {
        self.vm = vm
    }

    public var body: some View {
        Section {
            toggleRow
        } header: {
            Text("Training Mode")
        } footer: {
            Text("Enables a safe sandbox environment. All actions are simulated and no production data is modified.")
                .font(.footnote)
                .foregroundStyle(.bizarreOnSurfaceMuted)
        }
        .sheet(isPresented: $vm.showEnterSheet) {
            TrainingModeEnterSheet(
                onConfirm: vm.confirmEnable,
                onCancel:  vm.cancelEnable
            )
        }
    }

    private var toggleRow: some View {
        HStack {
            Label {
                VStack(alignment: .leading, spacing: BrandSpacing.xxs) {
                    Text("Training / Sandbox")
                        .font(.body)
                        .foregroundStyle(.bizarreOnSurface)
                    if vm.isEnabled {
                        Text("Active — simulated data only")
                            .font(.caption)
                            .foregroundStyle(.bizarreWarning)
                    }
                }
            } icon: {
                Image(systemName: "graduationcap.fill")
                    .foregroundStyle(.bizarreWarning)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { vm.isEnabled },
                set: { _ in vm.didTapToggle() }
            ))
            .labelsHidden()
            .accessibilityLabel("Training Mode toggle")
            .accessibilityIdentifier("trainingMode.toggle")
        }
        #if canImport(UIKit)
        .hoverEffect(.highlight)
        #endif
    }
}
