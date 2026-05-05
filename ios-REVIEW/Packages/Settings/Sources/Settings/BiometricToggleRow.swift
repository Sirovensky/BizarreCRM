import SwiftUI
import Persistence

/// §2.6 Settings-side biometric opt-in toggle.
///
/// Reads/writes `BiometricPreference.shared`. The actual biometric prompt
/// lives in Auth — when the user flips this toggle on, the next unlock
/// flow triggers the LAContext eval. Keeping it declarative means we
/// don't need to import Auth here and don't wire a second LAContext.
struct BiometricToggleRow: View {
    @State private var enabled: Bool = BiometricPreference.shared.isEnabled

    var body: some View {
        Toggle(isOn: $enabled) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Unlock with Face ID / Touch ID")
                Text("Uses the system biometric already enrolled on this device.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .tint(.orange)
        .onChange(of: enabled) { _, new in
            if new {
                BiometricPreference.shared.enable()
            } else {
                BiometricPreference.shared.disable()
            }
        }
        .accessibilityIdentifier("settings.biometricToggle")
    }
}
