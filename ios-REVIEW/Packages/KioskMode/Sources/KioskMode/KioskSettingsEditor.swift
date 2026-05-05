import SwiftUI

// MARK: - KioskSettingsEditor

/// §55 Admin configures dim thresholds, night mode schedule, and idle timeout.
public struct KioskSettingsEditor: View {
    @Bindable var manager: KioskModeManager

    @State private var nightModeStartHour: Int
    @State private var nightModeEndHour: Int

    public init(manager: KioskModeManager) {
        self.manager = manager
        self._nightModeStartHour = State(initialValue: manager.config.nightModeStart)
        self._nightModeEndHour   = State(initialValue: manager.config.nightModeEnd)
    }

    public var body: some View {
        Group {
            dimAfterStepper
            blackoutAfterStepper
            nightModeStartPicker
            nightModeEndPicker

            Button("Save Changes") {
                manager.config.nightModeStart = nightModeStartHour
                manager.config.nightModeEnd   = nightModeEndHour
                manager.saveConfig()
            }
            .tint(.orange)
        }
    }

    // MARK: - Controls

    private var dimAfterStepper: some View {
        Stepper(
            value: $manager.config.dimAfterSeconds,
            in: 60...600,
            step: 60
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Dim after")
                    .font(.body)
                Text("\(manager.config.dimAfterSeconds / 60) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: manager.config.dimAfterSeconds) { _, _ in
            manager.saveConfig()
        }
        .accessibilityLabel("Dim after \(manager.config.dimAfterSeconds / 60) minutes")
    }

    private var blackoutAfterStepper: some View {
        Stepper(
            value: $manager.config.blackoutAfterSeconds,
            in: 120...600,
            step: 60
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Blackout after")
                    .font(.body)
                Text("\(manager.config.blackoutAfterSeconds / 60) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: manager.config.blackoutAfterSeconds) { _, _ in
            manager.saveConfig()
        }
        .accessibilityLabel("Blackout after \(manager.config.blackoutAfterSeconds / 60) minutes")
    }

    private var nightModeStartPicker: some View {
        Picker("Night mode starts", selection: $nightModeStartHour) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour)).tag(hour)
            }
        }
        .accessibilityLabel("Night mode starts at \(hourLabel(nightModeStartHour))")
    }

    private var nightModeEndPicker: some View {
        Picker("Night mode ends", selection: $nightModeEndHour) {
            ForEach(0..<24, id: \.self) { hour in
                Text(hourLabel(hour)).tag(hour)
            }
        }
        .accessibilityLabel("Night mode ends at \(hourLabel(nightModeEndHour))")
    }

    // MARK: - Helpers

    private func hourLabel(_ hour: Int) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "h a"
        var comps = DateComponents()
        comps.hour = hour
        comps.minute = 0
        let date = Calendar.current.date(from: comps) ?? Date()
        return fmt.string(from: date)
    }
}

// MARK: - Night mode detection

public extension KioskConfig {
    /// Returns true if the current hour is within the night mode window.
    func isNightModeActive(currentHour: Int? = nil) -> Bool {
        let hour = currentHour ?? Calendar.current.component(.hour, from: Date())
        if nightModeStart <= nightModeEnd {
            // Same-day window (e.g. 8–18)
            return hour >= nightModeStart && hour < nightModeEnd
        } else {
            // Overnight window (e.g. 22–6)
            return hour >= nightModeStart || hour < nightModeEnd
        }
    }
}
