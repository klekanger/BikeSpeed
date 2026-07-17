import Foundation

/// An exponential moving average over a compass bearing.
///
/// A bearing is an angle, not a number. Averaging 359° and 1° in degrees-space gives 180° — due south —
/// when the answer is due north, because the figures read as 358 apart and smooth the long way round. On a
/// bar-mounted phone that's an arrow that whips through south every time the rider crosses north.
///
/// The fix: smooth the *unit vector*, not the angle — keep an exponentially weighted `(cos, sin)` and read
/// the bearing back with `atan2`, so interpolation always takes the short way round.
///
/// (Different problem from the scalar `displaySpeed` EMA in `LocationManager`: speed has no wrap-around.)
struct CircularMean {
    /// Weight given to each new bearing. Lower lags further behind, keeping a jittering magnetometer from
    /// twitching the arrow at a standstill.
    private let smoothingFactor: Double

    /// The smoothed unit vector. Nil until the first bearing arrives — easing in from an arbitrary zero would
    /// point the arrow at nothing real for the first second of every stop.
    private var vector: (x: Double, y: Double)?

    init(smoothingFactor: Double = 0.25) {
        self.smoothingFactor = smoothingFactor
    }

    /// The smoothed bearing in 0..<360, or nil before any bearing has been added.
    var value: Double? {
        vector.map { Self.degrees(x: $0.x, y: $0.y) }
    }

    /// Folds in a bearing and returns the new smoothed one.
    @discardableResult
    mutating func add(_ degrees: Double) -> Double {
        let radians = degrees * .pi / 180
        let sample = (x: cos(radians), y: sin(radians))

        guard let previous = vector else {
            // Nothing to average against: the first bearing is the answer.
            vector = sample
            return Self.degrees(x: sample.x, y: sample.y)
        }

        let smoothed = (
            x: smoothingFactor * sample.x + (1 - smoothingFactor) * previous.x,
            y: smoothingFactor * sample.y + (1 - smoothingFactor) * previous.y
        )
        vector = smoothed
        return Self.degrees(x: smoothed.x, y: smoothed.y)
    }

    mutating func reset() {
        vector = nil
    }

    /// Back to a bearing, inverting the `(cos θ, sin θ)` encoding in `add`. The compass/`atan2` axis
    /// mismatch (clockwise-from-north vs counter-clockwise-from-east) is harmless because encode and decode
    /// agree and averaging is rotation-invariant. The normalization matters: `atan2` answers in -π…π, and a
    /// consumer rotating an arrow must never be handed -3°.
    private static func degrees(x: Double, y: Double) -> Double {
        let degrees = atan2(y, x) * 180 / .pi
        return (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
