import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Automatic"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

enum AppearanceStorage {
    static let key = "appearanceMode"

    static var current: AppearanceMode {
        let raw = UserDefaults.standard.string(forKey: key) ?? AppearanceMode.system.rawValue
        return AppearanceMode(rawValue: raw) ?? .system
    }
}

// NEW: Add this custom Environment Key to pass the true system theme down
private struct SystemColorSchemeKey: EnvironmentKey {
    static let defaultValue: ColorScheme = .light
}

extension EnvironmentValues {
    var systemColorScheme: ColorScheme {
        get { self[SystemColorSchemeKey.self] }
        set { self[SystemColorSchemeKey.self] = newValue }
    }
}