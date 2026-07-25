import Foundation

/// Unwinds a wrapping compass bearing (0..<360) into a continuous, ever-accumulating angle, so a view
/// animating `.rotationEffect` crosses north the short way round instead of spinning back through south.
///
/// This is a *different* wrap-around problem from `CircularMean`. That one is about *averaging* two
/// bearings on the circle; this one is about *interpolating* between two already-chosen bearings for a
/// view animation. SwiftUI animates an `Angle` by lerping its degree figure linearly: handed 359° then
/// 1°, it sweeps 359 → 180 → 1 — the arrow whips a full half-turn through south every time the rider
/// crosses north. Smoothing the source (`CircularMean`) cannot fix this: 359° and 1° are already only
/// two degrees apart on the compass, yet still 358 apart as *numbers*, which is all the animation sees.
///
/// The fix is to never hand the animation a value that jumps more than 180°. Each new bearing is folded
/// in as the *shortest* signed step from the last one, so the running total drifts past 360° (or below
/// 0°) freely — 359° → 361° rather than 359° → 1°. `.rotationEffect(.degrees(361))` points exactly where
/// `.degrees(1)` does, but the animation between them takes the two-degree path it should.
struct ContinuousBearing {
    /// The accumulated continuous angle in degrees. Unbounded on purpose: it may sit at 361 or -5 or
    /// 720, all of which render identically to their mod-360 equivalent but animate the short way.
    private(set) var degrees: Double = 0
    private var seeded = false

    /// Folds in a bearing in 0..<360 and returns the continuous angle nearest the previous one.
    @discardableResult
    mutating func update(_ bearing: Double) -> Double {
        guard seeded else {
            // Nothing to unwind against: the first bearing is the answer, verbatim.
            degrees = bearing
            seeded = true
            return degrees
        }

        // IEEE `remainder` rounds the quotient to nearest, so it folds the raw gap into [-180, 180] —
        // exactly the shortest signed step. The running total then drifts past 360° (or below 0°)
        // rather than jumping the long way round.
        degrees += (bearing - degrees).remainder(dividingBy: 360)
        return degrees
    }
}
