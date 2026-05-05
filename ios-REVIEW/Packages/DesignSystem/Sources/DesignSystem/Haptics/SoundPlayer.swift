import Foundation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AudioToolbox)
import AudioToolbox
#endif

// §66 — SoundPlayer
// Plays UI event sounds; respects the device mute switch via AudioToolbox.
// Internal helper — only `HapticCatalog` should call this.

enum SoundPlayer {
    /// Play a sound associated with `event` if one is defined.
    /// Uses system sound IDs (always respects the mute switch on iOS).
    static func play(_ event: HapticEvent) {
        #if canImport(AudioToolbox)
        guard let id = soundID(for: event) else { return }
        AudioServicesPlaySystemSound(id)
        #endif
    }

    /// Maps an event to a system sound ID. Returns `nil` for events with no sound.
    private static func soundID(for event: HapticEvent) -> SystemSoundID? {
        switch event {
        case .saleComplete:
            // 1057 = payment received chime
            return 1057
        case .scanSuccess:
            // 1103 = camera shutter (beep-like)
            return 1103
        case .drawerKick:
            // 1054 = "tock" sound
            return 1054
        default:
            return nil
        }
    }
}
