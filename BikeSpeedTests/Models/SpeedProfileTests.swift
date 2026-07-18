import CoreLocation
import Foundation
import Testing

@testable import BikeSpeed

/// The speed profile is derived at view time from the recorded track, never stored. It has two jobs:
/// use the live GPS speed a new trip records per point, and fall back to deriving speed from the
/// timestamps for older trips whose samples carry no speed — so every trip with a route gets a chart.
struct SpeedProfileTests {

    /// Builds a straight northbound track `count` points long, one point every `spacingMeters`, one
    /// second apart. `storedSpeed` is written onto every point when non-nil (the new-trip path); leaving
    /// it nil exercises the derive-from-timestamps fallback.
    private func track(
        count: Int,
        spacingMeters: CLLocationDistance,
        secondsApart: TimeInterval = 1,
        storedSpeed: CLLocationSpeed? = nil
    ) -> [RouteSample] {
        let start = CLLocationCoordinate2D(latitude: 59.9139, longitude: 10.7522)
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        return (0..<count).map { index in
            RouteSample(
                latitude: start.latitude + (Double(index) * spacingMeters) / 111_320,
                longitude: start.longitude,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index) * secondsApart),
                speed: storedSpeed
            )
        }
    }

    @Test
    func aTrackTooShortForASegmentYieldsNothing() {
        #expect(SpeedProfile.build(from: []).isEmpty)
        #expect(SpeedProfile.build(from: track(count: 1, spacingMeters: 10)).isEmpty)
    }

    @Test
    func distanceIsCumulativeAndStartsAtZero() throws {
        // 5 points, 10 m apart → cumulative distances 0, 10, 20, 30, 40.
        let profile = SpeedProfile.build(from: track(count: 5, spacingMeters: 10))

        #expect(profile.count == 5)
        expectClose(try #require(profile.first).distance, 0, within: 0.01)
        expectClose(try #require(profile.last).distance, 40, within: 0.5)
    }

    @Test
    func storedSpeedIsUsedWhenPresent() throws {
        // A steady 8 m/s recorded on every point. Smoothing a constant series leaves it constant.
        let profile = SpeedProfile.build(from: track(count: 8, spacingMeters: 8, storedSpeed: 8))

        for sample in profile {
            expectClose(sample.speed, 8, within: 0.01)
        }
    }

    @Test
    func speedIsDerivedFromTimestampsWhenNoStoredSpeed() throws {
        // 10 m every second with no stored speed → 10 m/s derived on every segment.
        let profile = SpeedProfile.build(from: track(count: 8, spacingMeters: 10, secondsApart: 1))

        // Middle of the series, away from window-edge shrinkage, reads the true speed.
        expectClose(profile[4].speed, 10, within: 0.1)
    }

    @Test
    func theStartingPointDoesNotDipToZeroWhenDerived() throws {
        // Riding at a steady 10 m/s from the first point. With no stored speed the anchor point has no
        // segment to derive from; it must inherit the first real speed rather than read a false standstill.
        let profile = SpeedProfile.build(from: track(count: 8, spacingMeters: 10))

        #expect(try #require(profile.first).speed > 5, "the start must not draw a phantom standstill")
    }

    @Test
    func aDerivedSpeedSpikeIsClampedToTheTeleportCeiling() throws {
        // One point jumps 300 m in a single second — 1080 km/h, the kind of GPS glitch the teleport guard
        // rejects live. Derived speed must not carry it into the chart's Y-axis.
        var samples = track(count: 5, spacingMeters: 10)
        let glitch = samples[2]
        samples[2] = RouteSample(
            latitude: glitch.latitude + 300 / 111_320,
            longitude: glitch.longitude,
            altitude: glitch.altitude,
            timestamp: glitch.timestamp
        )

        let profile = SpeedProfile.build(from: samples)

        for sample in profile {
            #expect(sample.speed <= SpeedProfile.maxPlausibleSpeed + 0.01, "a glitch must not exceed the clamp")
        }
    }

    @Test
    func smoothingTamesAlternatingJitter() throws {
        // Points alternate fast/slow segments (5 m then 15 m per second). The raw derived speed would
        // swing 5↔15 m/s; the smoothed series stays near the 10 m/s mean through the middle.
        let start = CLLocationCoordinate2D(latitude: 59.9139, longitude: 10.7522)
        let base = Date(timeIntervalSince1970: 1_760_000_000)
        var cumulative = 0.0
        var samples: [RouteSample] = []
        for index in 0..<10 {
            if index > 0 { cumulative += index.isMultiple(of: 2) ? 15 : 5 }
            samples.append(RouteSample(
                latitude: start.latitude + cumulative / 111_320,
                longitude: start.longitude,
                altitude: 100,
                timestamp: base.addingTimeInterval(Double(index))
            ))
        }

        let profile = SpeedProfile.build(from: samples)

        // A middle point stays close to the mean, well inside the raw 5↔15 swing.
        expectClose(profile[5].speed, 10, within: 3)
    }
}
