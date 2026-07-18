import CoreLocation
import Foundation

/// Turns a recorded `RouteSample` track into the `[SpeedSample]` a speed-over-distance chart draws.
///
/// Two sources of speed, in order of trust:
/// 1. `RouteSample.speed` — the live GPS (Doppler) reading captured per point (new trips).
/// 2. Position-derived — segment distance ÷ time between two points (older trips, recorded before
///    per-point speed shipped, whose samples have `speed == nil`).
///
/// The derived path is inherently spiky (a metre of GPS wander over a second reads as a speed jump), so a
/// small centred moving average smooths the series. That smoothing is harmless on the already-clean stored
/// readings, so the same pass runs for both and the chart looks the same whichever source fed it.
///
/// Pure and `nonisolated` on purpose: `TripLogDetailView` runs this inside a `Task.detached` alongside the
/// track decode, keeping an O(samples) pass off the main actor.
enum SpeedProfile {
    /// Mirrors `TripManager`'s teleport guard (120 km/h). A GPS jitter between two samples can imply an
    /// absurd derived speed; clamp it so one bad point can't blow out the chart's Y-axis.
    static let maxPlausibleSpeed: CLLocationSpeed = 120 / 3.6

    /// Samples spanned by the smoothing window. Route points land roughly every 10 m
    /// (`TripManager.routeSampleDistanceInterval`), so five points ≈ 40 m of riding — enough to tame
    /// position-derived jitter without flattening a real acceleration.
    static let smoothingWindow = 5

    /// Builds the profile. Empty for a track too short to define a single segment — the chart then shows
    /// its "no data" state, exactly as the height profile does for a trip without altitude.
    nonisolated static func build(from route: [RouteSample]) -> [SpeedSample] {
        guard route.count >= 2 else { return [] }

        // (cumulative distance at this point, speed there). The first point anchors the X-axis at 0.
        var raw: [(distance: CLLocationDistance, speed: CLLocationSpeed)] = []
        raw.reserveCapacity(route.count)
        var cumulative: CLLocationDistance = 0

        for index in route.indices {
            let sample = route[index]

            let speed: CLLocationSpeed
            if index == 0 {
                // No preceding segment yet; corrected below once the first segment's speed is known.
                speed = sample.speed.map { max(0, $0) } ?? 0
            } else {
                let previous = route[index - 1]
                let segment = CLLocation(latitude: previous.latitude, longitude: previous.longitude)
                    .distance(from: CLLocation(latitude: sample.latitude, longitude: sample.longitude))
                cumulative += segment

                if let stored = sample.speed, stored >= 0 {
                    speed = stored
                } else {
                    let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
                    speed = dt > 0 ? segment / dt : (raw.last?.speed ?? 0)
                }
            }
            raw.append((cumulative, min(speed, maxPlausibleSpeed)))
        }

        // The starting point had no segment to derive from; when it also had no stored reading it reads 0,
        // which would draw a false dip to a standstill on a ride that began mid-motion. Lift it to the
        // first real speed instead.
        if route.first?.speed == nil, raw.count >= 2 {
            raw[0].speed = raw[1].speed
        }

        return smoothed(raw)
    }

    /// A centred moving average over `smoothingWindow` points. Centred (not trailing) so the curve doesn't
    /// lag the ride; the window shrinks at the two ends rather than inventing points beyond them.
    private nonisolated static func smoothed(
        _ raw: [(distance: CLLocationDistance, speed: CLLocationSpeed)]
    ) -> [SpeedSample] {
        let half = smoothingWindow / 2
        return raw.indices.map { index in
            let lower = max(0, index - half)
            let upper = min(raw.count - 1, index + half)
            let window = raw[lower...upper]
            let average = window.reduce(0) { $0 + $1.speed } / Double(window.count)
            return SpeedSample(distance: raw[index].distance, speed: average)
        }
    }
}
