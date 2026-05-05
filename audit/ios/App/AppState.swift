import SwiftUI
import Observation
import Core

@MainActor
@Observable
final class AppState {
    enum Phase: Equatable {
        case launching
        case unauthenticated
        case locked
        case authenticated
    }

    var phase: Phase = .launching
    var colorSchemePreference: ColorSchemePreference = .system

    var forcedColorScheme: ColorScheme? {
        switch colorSchemePreference {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum ColorSchemePreference: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark
    var id: String { rawValue }
}
