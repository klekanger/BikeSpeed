import Foundation

/// Turns a stream of altitude readings into total ascent and descent, through a deadband.
///
/// Naively summing positive deltas manufactures hundreds of phantom metres an hour out of sensor
/// noise. Instead every reading is measured against an anchor that only moves when the difference
/// crosses `deadband`: noise oscillating inside the band cancels against a fixed point and adds
/// nothing, while a real climb — however slowly it accumulates — eventually crosses the band, is
/// banked in full, and re-anchors for the next step.
struct ElevationAccumulator {
    /// How far altitude must move from the anchor before it is believed. Sized to the source's
    /// noise: ~1 m suits the barometer, ~3 m the much noisier GPS fallback.
    let deadband: Double

    private(set) var ascent: Double = 0 // meters
    private(set) var descent: Double = 0 // meters, positive
    /// Distinguishes "a flat trip" (zero ascent) from "no altitude data ever arrived" (nothing to
    /// report) — the saved log entry stores nil for the latter, not a misleading 0.
    private(set) var hasRecordedAltitude = false

    private var anchor: Double?

    init(deadband: Double) {
        self.deadband = deadband
    }

    mutating func add(altitude: Double) {
        hasRecordedAltitude = true
        guard let anchor else {
            self.anchor = altitude
            return
        }
        let delta = altitude - anchor
        if delta >= deadband {
            ascent += delta
            self.anchor = altitude
        } else if delta <= -deadband {
            descent += -delta
            self.anchor = altitude
        }
    }

    mutating func reset() {
        ascent = 0
        descent = 0
        anchor = nil
        hasRecordedAltitude = false
    }
}
