import CoreLocation
import Foundation

/// One point of a trip's recorded track. Latitude and longitude are stored as plain `Double`s
/// rather than a `CLLocationCoordinate2D`, which is not `Codable` — the computed `coordinate` hands
/// MapKit what it wants without the storage having to know about it.
///
/// Unlike `AltitudeSample`, which is indexed by distance-so-far because it is charted against it,
/// a route sample carries its `timestamp`: GPX is a time series, and a track without times can't be
/// imported as a ride by Strava or Komoot.
struct RouteSample: Codable, Hashable, Sendable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// Absent, not zero, when the fix carried no usable vertical accuracy — GPX simply omits `<ele>`
    /// for such a point rather than claiming the rider was at sea level.
    let altitude: CLLocationDistance? // meters
    let timestamp: Date

    /// `nonisolated` because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin even this — a
    /// pure function of two `Double`s — to the main actor, and `TripLogDetailView` maps a whole track through
    /// it inside a `Task.detached`, which is the entire point of doing that work off the run loop.
    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
