import Foundation

/// User-selectable in-app display language, independent of `MeasurementSystem`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case norwegian

    var id: String { rawValue }

    /// Locale to force app-wide, or `nil` to follow the device's language setting.
    var locale: Locale? {
        switch self {
        case .system: return nil
        case .english: return Locale(identifier: "en")
        case .norwegian: return Locale(identifier: "nb")
        }
    }
}
