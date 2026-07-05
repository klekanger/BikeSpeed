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

    var abbreviation: String {
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
