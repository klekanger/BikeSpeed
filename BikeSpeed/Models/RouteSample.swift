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
    /// The instantaneous GPS (Doppler) speed at this point, in m/s — the same reading the gauge shows,
    /// which is more trustworthy than deriving speed from consecutive positions. Optional (a fix can lack
    /// a usable speed) and additive to the stored JSON blob: trips saved before it shipped decode with
    /// `speed == nil`, and `SpeedProfile` fills that gap by deriving speed from the timestamps instead.
    ///
    /// Not defaulted at the property (`let x = nil` would make Codable *skip* decoding it, silently
    /// dropping the value on every round-trip); the default lives on the initializer below instead.
    let speed: CLLocationSpeed?

    init(
        latitude: CLLocationDegrees,
        longitude: CLLocationDegrees,
        altitude: CLLocationDistance?,
        timestamp: Date,
        speed: CLLocationSpeed? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.speed = speed
    }

    /// `nonisolated` so `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` doesn't pin this pure function to the main
    /// actor: `TripLogDetailView` maps a whole track through it inside a `Task.detached`, the whole point of
    /// which is to keep that work off the run loop.
    nonisolated var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
