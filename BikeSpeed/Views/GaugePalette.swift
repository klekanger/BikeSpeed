import SwiftUI

/// Named colors shared across the gauge views, so tweaks to the look don't require
/// hunting down repeated `Color(white:)` literals.
extension Color {
    static let gaugeFaceCenter = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1B / 255)
}
