import Foundation

/// 8-point compass direction derived from a GPS course (degrees clockwise from true north).
enum CompassDirection: Int, CaseIterable {
    case n, ne, e, se, s, sw, w, nw

    init(course: Double) {
        let normalized = course.truncatingRemainder(dividingBy: 360)
        let positive = normalized < 0 ? normalized + 360 : normalized
        let index = Int(((positive + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        self = CompassDirection(rawValue: index) ?? .n
    }

    /// Norwegian differs on the east/west axis: Ø (øst) and V (vest) replace E and W.
    ///
    /// Resolved through `AppLanguage`, not `String(localized:)`, so the in-app language override is honored —
    /// see `AppLanguage.localizedString(forKey:)`.
    func abbreviation(language: AppLanguage) -> String {
        language.localizedString(forKey: englishAbbreviation)
    }

    /// Doubles as the `Localizable.xcstrings` key, matching the catalog's source-string-as-key convention.
    private var englishAbbreviation: String {
        switch self {
        case .n: return "N"
        case .ne: return "NE"
        case .e: return "E"
        case .se: return "SE"
        case .s: return "S"
        case .sw: return "SW"
        case .w: return "W"
        case .nw: return "NW"
        }
    }
}
