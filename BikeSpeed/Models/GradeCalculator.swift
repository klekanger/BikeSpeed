import Foundation

/// The live gradient: rise over run across a trailing window of ridden distance.
///
/// Never computed fix-to-fix — a ~5 m distance delta against ±1 m of altitude noise is meaningless.
/// Samples of (trip distance so far, altitude) queue up until they span `windowDistance`, and the
/// grade is the slope between the window's two ends; older samples fall off the back, so a hill
/// crested a while ago stops being reported once it leaves the window.
struct GradeCalculator {
    /// How much riding the slope is measured across. ~30 m is short enough to feel live at bike
    /// speeds and long enough that altitude noise can't dominate the rise.
    let windowDistance: Double

    private var samples: [(distance: Double, altitude: Double)] = []

    init(windowDistance: Double) {
        self.windowDistance = windowDistance
    }

    /// Nil until a full window's worth of distance has been ridden — a made-up early reading would
    /// be worse than none.
    var grade: Double? {
        guard let first = samples.first, let last = samples.last else { return nil }
        let run = last.distance - first.distance
        guard run >= windowDistance else { return nil }
        return (last.altitude - first.altitude) / run
    }

    /// `distance` is the trip's accumulated distance at this reading, so it is monotonic and
    /// unaffected by pauses — the same X-axis convention as `AltitudeSample`.
    mutating func add(distance: Double, altitude: Double) {
        samples.append((distance, altitude))
        // Trim to the oldest sample still needed to span the window, keeping one beyond it so the
        // run stays >= windowDistance rather than collapsing under it after every trim.
        while samples.count > 2, samples[1].distance <= samples[samples.count - 1].distance - windowDistance {
            samples.removeFirst()
        }
    }

    mutating func reset() {
        samples.removeAll()
    }
}
