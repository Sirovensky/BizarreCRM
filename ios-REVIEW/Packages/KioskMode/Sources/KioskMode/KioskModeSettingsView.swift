import SwiftUI

// MARK: - KioskModeSettingsView

/// §55.1 Settings → Kiosk → mode picker.
/// On first activation, presents PIN enrollment if no PIN is stored.
public struct KioskModeSettingsView: View {
    @Bindable var manager: KioskModeManager
    let pinStorage: any KioskPINStorage

    @State private var showEnrollSheet = false
    @State private var pendingMode: KioskMode?

    public init(manager: KioskModeManager, pinStorage: (any KioskPINStorage)? = nil) {
        self.manager = manager
        self.pinStorage = pinStorage ?? PINStoreKioskAdapter()
    }

    public var body: some View {
        List {
            modeSection
            if manager.currentMode != .off {
                configSection
            }
        }
        .navigationTitle("Kiosk Mode")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showEnrollSheet) {
            if let mode = pendingMode {
                KioskPINEnrollView(
                    pinStorage: pinStorage,
                    onEnrolled: {
                        showEnrollSheet = false
                        manager.setMode(mode)
                        pendingMode = nil
                    },
                    onCancel: {
                        showEnrollSheet = false
                        pendingMode = nil
                    }
                )
            }
        }
    }

    // MARK: - Mode picker section

    private var modeSection: some View {
        Section("Mode") {
            ForEach(KioskMode.allCases, id: \.rawValue) { mode in
                modeRow(mode)
            }
        }
    }

    @ViewBuilder
    private func modeRow(_ mode: KioskMode) -> some View {
        Button {
            let result = manager.requestActivation(mode: mode, pinStorage: pinStorage)
            if case .needsEnrollment(let m) = result {
                pendingMode = m
                showEnrollSheet = true
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.displayName)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(mode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if manager.currentMode == mode {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Selected")
                }
            }
        }
        .accessibilityLabel(mode.displayName)
        .accessibilityValue(manager.currentMode == mode ? "Selected" : "")
    }

    // MARK: - Config section

    private var configSection: some View {
        Section("Idle & Burn-in") {
            KioskSettingsEditor(manager: manager)
        }
    }
}

// MARK: - KioskMode display helpers

extension KioskMode {
    var displayName: String {
        switch self {
        case .off:         return "Off"
        case .posOnly:     return "POS Only"
        case .clockInOnly: return "Clock-In Only"
        case .training:    return "Training Profile"
        }
    }

    var description: String {
        switch self {
        case .off:         return "Full app access"
        case .posOnly:     return "Only the POS screen is accessible"
        case .clockInOnly: return "Only the clock-in/out screen is accessible"
        case .training:    return "Simplified large-button interface for demos"
        }
    }
}
