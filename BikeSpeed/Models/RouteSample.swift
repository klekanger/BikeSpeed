import CoreLocation
import Foundation

/// One point of a trip's recorded track. Lat/lon are plain `Double`s because `CLLocationCoordinate2D` isn't
/// `Codable`; the computed `coordinate` hands MapKit what it wants.
///
/// Carries a `timestamp` (unlike `AltitudeSample`, indexed by distance): GPX is a time series, and a track
/// without times can't be imported as a ride by Strava or Komoot.
struct RouteSample: Codable, Hashable, Sendable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// Absent, not zero, when the fix had no usable vertical accuracy — GPX omits `<ele>` rather than
    /// claiming sea level.
    let altitude: CLLocationDistance? // meters
    let timestamp: Date

    /// `nonisolated` so `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` doesn't pin this pure function to the main
    /// actor: `TripLogDetailView` maps a whole track through it inside a `Task.detached`, the whole point of
    /// which is to keep that work off the run loop.
    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
