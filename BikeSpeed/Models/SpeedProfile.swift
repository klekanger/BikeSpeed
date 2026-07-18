import CoreLocation
import Foundation

/// Turns a recorded `RouteSample` track into the `[SpeedSample]` a speed-over-distance chart draws.
///
/// Distance (the X-axis) comes from `RouteSample.distance` — the trip's guarded accumulated distance, the
/// *same* basis `AltitudeSample` uses — so the speed and height charts, and the trip's distance total, all
/// agree. Legacy trips didn't store it; there a geodesic running total stands in.
///
/// Speed comes from two sources, in order of trust:
/// 1. `RouteSample.speed` — the live GPS (Doppler) reading captured per point (new trips).
/// 2. Position-derived — segment distance ÷ time between two points (older trips whose samples have
///    `speed == nil`).
///
/// The derived path is inherently spiky (a metre of GPS wander over a second reads as a speed jump), so a
/// small centred moving average smooths the series. That smoothing is harmless on the already-clean stored
/// readings, so the same pass runs for both. A long ride is then decimated to a chart-appropriate density.
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

    /// Above this gap between two samples, `segment ÷ dt` no longer reads as an instantaneous speed — the
    /// interval spans a stop (a light, a manual pause), so its distance was covered over riding time plus
    /// idle time. Deriving across it would draw a phantom near-standstill; carry the last real speed instead.
    /// Only the derived (legacy) path consults this — stored GPS speed is authoritative. 60 s is comfortably
    /// above the widest genuine riding interval (10 m at a crawl) and well below any real pause.
    static let maxDerivationGap: TimeInterval = 60

    /// Cap on plotted points. A phone-width, 200 pt-tall chart can't resolve more, and it keeps a 40 km ride
    /// (~4000 route samples) from rendering thousands of marks and running as many per-point unit
    /// conversions on the main actor. Well above what the eye needs, so the decimated line stays faithful.
    static let maxChartPoints = 500

    /// Builds the profile. Empty for a track too short to define a single segment — the chart then shows
    /// its "no data" state, exactly as the height profile does for a trip without altitude.
    nonisolated static func build(from route: [RouteSample]) -> [SpeedSample] {
        guard route.count >= 2 else { return [] }

        // (distance at this point, speed there). Distance is the stored accumulated distance where present,
        // and a geodesic running total only for legacy trips that didn't record it.
        var raw: [(distance: CLLocationDistance, speed: CLLocationSpeed)] = []
        raw.reserveCapacity(route.count)
        var derivedCumulative: CLLocationDistance = 0

        for index in route.indices {
            let sample = route[index]

            let distance: CLLocationDistance
            let speed: CLLocationSpeed
            if index == 0 {
                distance = sample.distance ?? 0
                // No preceding segment yet; corrected below once the first segment's speed is known.
                speed = sample.speed.map { max(0, $0) } ?? 0
            } else {
                let previous = route[index - 1]
                if let stored = sample.distance {
                    distance = stored
                } else {
                    derivedCumulative += haversineMeters(from: previous, to: sample)
                    distance = derivedCumulative
                }

                if let stored = sample.speed, stored >= 0 {
                    speed = stored
                } else {
                    let dt = sample.timestamp.timeIntervalSince(previous.timestamp)
                    let segment = distance - (raw.last?.distance ?? 0)
                    if dt > 0, dt <= maxDerivationGap {
                        speed = segment / dt
                    } else {
                        // dt <= 0 (bad timestamps) or a stop-sized gap: keep the last real speed rather
                        // than derive a misleading value across non-riding time.
                        speed = raw.last?.speed ?? 0
                    }
                }
            }
            raw.append((distance, min(speed, maxPlausibleSpeed)))
        }

        // The starting point had no segment to derive from; when it also had no stored reading it reads 0,
        // which would draw a false dip to a standstill on a ride that began mid-motion. Lift it to the
        // first real speed instead.
        if route.first?.speed == nil, raw.count >= 2 {
            raw[0].speed = raw[1].speed
        }

        return decimated(smoothed(raw))
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

    /// Thins an over-long series to at most `maxChartPoints` by an even stride, always keeping the final
    /// point so the chart still reaches the trip's full distance. Short rides pass through untouched.
    private nonisolated static func decimated(_ samples: [SpeedSample]) -> [SpeedSample] {
        guard samples.count > maxChartPoints else { return samples }
        let stride = Int((Double(samples.count) / Double(maxChartPoints)).rounded(.up))
        var result = samples.enumerated().compactMap { $0.offset.isMultiple(of: stride) ? $0.element : nil }
        if let last = samples.last, result.last?.distance != last.distance {
            result.append(last)
        }
        return result
    }

    /// Great-circle distance between two samples, in meters. A plain `Double` haversine rather than
    /// `CLLocation.distance(from:)`, which would allocate two `CLLocation` objects per segment — thousands
    /// on a long ride — for a legacy-only fallback path.
    private nonisolated static func haversineMeters(from: RouteSample, to: RouteSample) -> CLLocationDistance {
        let earthRadius = 6_371_000.0 // meters
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = lat2 - lat1
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
