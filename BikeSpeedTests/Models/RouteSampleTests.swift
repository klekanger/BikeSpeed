import Foundation
import Testing

@testable import BikeSpeed

/// `RouteSample` is stored as a JSON blob (`StoredTrip.routeData`) via `TripPayloadCoder`. These pin two
/// things a careless change breaks silently: the newly added `speed` must survive the round-trip, and a
/// blob written before `speed` existed must still decode (as nil) rather than fail the whole track.
struct RouteSampleTests {

    @Test
    func speedSurvivesTheEncodeDecodeRoundTrip() throws {
        // Guards the specific trap that `let speed = nil` (a property-level default) would spring: Swift's
        // Codable synthesis *skips decoding* an immutable property with a default, so every stored speed
        // would come back nil. The default lives on the initializer instead, which is why this passes.
        let original = RouteSample(
            latitude: 59.9139,
            longitude: 10.7522,
            altitude: 142.5,
            timestamp: Date(timeIntervalSince1970: 1_760_000_000),
            speed: 7.25
        )

        let data = try TripPayloadCoder.encode([original])
        let decoded = try TripPayloadCoder.decode([RouteSample].self, from: data)

        #expect(decoded == [original])
        expectClose(try #require(decoded.first?.speed), 7.25, within: 0.001)
    }

    @Test
    func aLegacyBlobWithoutSpeedStillDecodes() throws {
        // A track saved before per-point speed shipped: JSON with no "speed" key. It must decode with
        // speed == nil, not throw — otherwise upgrading would lose every pre-existing route.
        let legacyJSON = """
        [{"latitude":59.9139,"longitude":10.7522,"altitude":100,"timestamp":"2025-10-09T12:00:00Z"}]
        """
        let data = Data(legacyJSON.utf8)

        let decoded = try TripPayloadCoder.decode([RouteSample].self, from: data)

        #expect(decoded.count == 1)
        #expect(decoded.first?.speed == nil)
    }
}
