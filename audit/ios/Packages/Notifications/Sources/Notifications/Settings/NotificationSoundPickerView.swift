import SwiftUI
import DesignSystem
import UserNotifications
import Core

// MARK: - §70.4 Notification sound library
//
// Apple default + 3 brand custom sounds:
//   - Apple default (system "default" sound name)
//   - cash_register.caf  — POS payment confirmed
//   - bell.caf           — General alert / new ticket
//   - ding.caf           — SMS / quick notification
//
// User picks a sound per notification category. Saved to UserDefaults
// keyed by category ID. The server includes the `sound` key in APNs
// payload for each category; client-side pick overrides via local
// notification rescheduling (for foreground) or via the UNNotificationServiceExtension.
//
// Files must be added to the main app bundle under "Notification Sounds" folder
// and listed in the NotificationServiceExtension target.

// MARK: - Sound Model

public enum NotificationSound: String, CaseIterable, Identifiable, Sendable {
    case `default`         = "default"
    case cashRegister      = "cash_register"
    case bell              = "bell"
    case ding              = "ding"
    case none              = "none"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .default:      return "Default"
        case .cashRegister: return "Cash Register"
        case .bell:         return "Bell"
        case .ding:         return "Ding"
        case .none:         return "None"
        }
    }

    public var systemIcon: String {
        switch self {
        case .default:      return "speaker.wave.2"
        case .cashRegister: return "dollarsign.circle"
        case .bell:         return "bell"
        case .ding:         return "bell.badge"
        case .none:         return "speaker.slash"
        }
    }

    /// Value to put in `UNNotificationSound` when scheduling.
    public var unSound: UNNotificationSound? {
        switch self {
        case .default:      return .default
        case .cashRegister: return UNNotificationSound(named: UNNotificationSoundName("cash_register.caf"))
        case .bell:         return UNNotificationSound(named: UNNotificationSoundName("bell.caf"))
        case .ding:         return UNNotificationSound(named: UNNotificationSoundName("ding.caf"))
        case .none:         return nil
        }
    }
}

// MARK: - Preferences Store

public final class NotificationSoundPreferences: @unchecked Sendable {
    public static let shared = NotificationSoundPreferences()
    private init() {}

    private let keyPrefix = "com.bizarrecrm.notif.sound."

    public func sound(for categoryID: String) -> NotificationSound {
        let key = keyPrefix + categoryID
        guard let raw = UserDefaults.standard.string(forKey: key),
              let sound = NotificationSound(rawValue: raw) else {
            return .default
        }
        return sound
    }

    public func setSound(_ sound: NotificationSound, for categoryID: String) {
        let key = keyPrefix + categoryID
        UserDefaults.standard.set(sound.rawValue, forKey: key)
    }

    public func resetAll() {
        NotificationCategoryID.allCases.forEach { category in
            let key = keyPrefix + category.rawValue
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}

// MARK: - ViewModel

@MainActor @Observable
public final class NotificationSoundPickerViewModel {

    public struct CategorySoundSetting: Identifiable {
        public let id: String
        public let displayName: String
        public var selectedSound: NotificationSound
    }

    public var settings: [CategorySoundSetting] = []

    private let store = NotificationSoundPreferences.shared

    public init() {
        loadSettings()
    }

    private func loadSettings() {
        settings = NotificationCategoryID.allCases.map { category in
            CategorySoundSetting(
                id: category.rawValue,
                displayName: category.displayName,
                selectedSound: store.sound(for: category.rawValue)
            )
        }
    }

    public func updateSound(_ sound: NotificationSound, for categoryID: String) {
        store.setSound(sound, for: categoryID)
        if let idx = settings.firstIndex(where: { $0.id == categoryID }) {
            settings[idx].selectedSound = sound
        }
    }

    public func resetAll() {
        store.resetAll()
        loadSettings()
    }
}

// MARK: - Display name extension on NotificationCategoryID

extension NotificationCategoryID {
    var displayName: String {
        switch self {
        case .ticketUpdate:         return "Ticket update"
        case .smsReply:             return "New SMS"
        case .lowStock:             return "Low stock"
        case .appointmentReminder:  return "Appointment reminder"
        case .paymentReceived:      return "Payment received"
        case .paymentFailed:        return "Payment failed"
        case .deadLetterAlert:      return "Dead-letter alert"
        case .mention:              return "@Mention"
        case .scheduleChange:       return "Schedule change"
        }
    }
}

// MARK: - Sound Picker View

public struct NotificationSoundPickerView: View {

    @State private var vm = NotificationSoundPickerViewModel()

    public init() {}

    public var body: some View {
        List {
            Section {
                Text("Choose a sound for each notification category. \"None\" silences that category.")
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }

            Section("Categories") {
                ForEach($vm.settings) { $setting in
                    SoundPickerRow(setting: $setting) { newSound in
                        vm.updateSound(newSound, for: setting.id)
                    }
                }
            }

            Section {
                Button(role: .destructive) {
                    vm.resetAll()
                } label: {
                    Text("Reset all to Default")
                        .frame(maxWidth: .infinity)
                }
                .accessibilityIdentifier("notifSound.resetAll")
            }
        }
        .navigationTitle("Notification Sounds")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Row

private struct SoundPickerRow: View {
    @Binding var setting: NotificationSoundPickerViewModel.CategorySoundSetting
    var onSelect: (NotificationSound) -> Void

    var body: some View {
        NavigationLink {
            SoundSelectionList(
                categoryName: setting.displayName,
                selected: $setting.selectedSound,
                onSelect: onSelect
            )
        } label: {
            HStack {
                Text(setting.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurface)
                Spacer()
                Text(setting.selectedSound.displayName)
                    .font(.brandBodyMedium())
                    .foregroundStyle(.bizarreOnSurfaceMuted)
            }
        }
    }
}

// MARK: - Sound Selection List

private struct SoundSelectionList: View {
    let categoryName: String
    @Binding var selected: NotificationSound
    var onSelect: (NotificationSound) -> Void

    var body: some View {
        List(NotificationSound.allCases) { sound in
            Button {
                selected = sound
                onSelect(sound)
                playPreview(sound)
            } label: {
                HStack(spacing: BrandSpacing.sm) {
                    Image(systemName: sound.systemIcon)
                        .foregroundStyle(.bizarreOrange)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    Text(sound.displayName)
                        .font(.brandBodyMedium())
                        .foregroundStyle(.bizarreOnSurface)
                    Spacer()
                    if selected == sound {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.bizarreOrange)
                            .accessibilityLabel("Selected")
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notifSound.option.\(sound.rawValue)")
        }
        .navigationTitle(categoryName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func playPreview(_ sound: NotificationSound) {
        guard sound != .none else { return }
        // Trigger a local notification preview for the selected sound.
        let content = UNMutableNotificationContent()
        content.title = "Preview"
        content.body = "\(sound.displayName) sound"
        if let unSound = sound.unSound {
            content.sound = unSound
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "com.bizarrecrm.soundPreview",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

#if DEBUG
#Preview("Sound Picker") {
    NavigationStack {
        NotificationSoundPickerView()
    }
}
#endif
