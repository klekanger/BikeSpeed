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

    /// Looks up `key` in `Localizable.xcstrings`, forcing this language's `.lproj` bundle. Needed because
    /// `String(localized:locale:)` was observed to ignore its `locale:` override for this project's compiled
    /// String Catalog and always resolve against the device language; loading the bundle directly bypasses
    /// that.
    func localizedString(forKey key: String) -> String {
        guard let locale,
              let path = Bundle.main.path(forResource: locale.identifier, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
        }
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
}
