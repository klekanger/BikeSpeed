import SwiftUI

/// Named colors shared across the gauge views, so a look tweak isn't a hunt for repeated
/// `Color(white:)` literals.
extension Color {
    static let gaugeFaceCenter = Color(red: 0x1B / 255, green: 0x1B / 255, blue: 0x1B / 255)
}

extension Gradient {
    /// Brushed-metal ring gradient shared by the speedometer bezel (`GaugeFaceView`) and the
    /// stats-panel bezel (`StatsPanel`), so both catch light the same way. Rendered conic/angular,
    /// with the angle nudged by device tilt at the call site.
    static let metallicBezel = Gradient(colors: [
        Color(white: 0.8), Color(white: 0.25), Color(white: 0.9),
        Color(white: 0.2), Color(white: 0.65), Color(white: 0.3),
        Color(white: 0.8),
    ])
}
