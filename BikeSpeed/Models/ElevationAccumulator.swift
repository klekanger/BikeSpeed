import Foundation

/// Turns a stream of altitude readings into total ascent and descent, through a deadband.
///
/// Naively summing positive deltas manufactures hundreds of phantom metres an hour out of sensor noise.
/// Instead each reading is measured against an anchor that moves only when the difference crosses `deadband`:
/// noise oscillating inside the band cancels against the fixed point, while a real climb — however slowly it
/// accumulates — eventually crosses the band, is banked in full, and re-anchors.
struct ElevationAccumulator {
    /// How far altitude must move from the anchor before it's believed. Sized to the source's noise:
    /// ~1 m for the barometer, ~3 m for the much noisier GPS fallback.
    let deadband: Double

    private(set) var ascent: Double = 0 // meters
    private(set) var descent: Double = 0 // meters, positive
    /// Distinguishes a flat trip (zero ascent) from no altitude data ever arriving — the saved log entry
    /// stores nil for the latter, not a misleading 0.
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

    /// Forgets the reference point but keeps the totals. For breaks in sampling — a pause, a long standstill,
    /// a stopped-and-restarted barometer — where readings across the gap aren't comparable: whatever altitude
    /// did in between wasn't ridden, so the next reading anchors fresh instead of banking the difference as
    /// climb. `hasRecordedAltitude` deliberately survives (and is stored, not derived from the anchor, for
    /// this reason): data did arrive, the trip merely re-baselined.
    mutating func reanchor() {
        anchor = nil
    }

    mutating func reset() {
        ascent = 0
        descent = 0
        anchor = nil
        hasRecordedAltitude = false
    }
}
