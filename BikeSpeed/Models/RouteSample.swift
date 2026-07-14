import CoreLocation
import Foundation

/// One point of a trip's recorded track. Latitude and longitude are stored as plain `Double`s
/// rather than a `CLLocationCoordinate2D`, which is not `Codable` — the computed `coordinate` hands
/// MapKit what it wants without the storage having to know about it.
///
/// Unlike `AltitudeSample`, which is indexed by distance-so-far because it is charted against it,
/// a route sample carries its `timestamp`: GPX is a time series, and a track without times can't be
/// imported as a ride by Strava or Komoot.
struct RouteSample: Codable, Hashable {
    let latitude: CLLocationDegrees
    let longitude: CLLocationDegrees
    /// Absent, not zero, when the fix carried no usable vertical accuracy — GPX simply omits `<ele>`
    /// for such a point rather than claiming the rider was at sea level.
    let altitude: CLLocationDistance? // meters
    let timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}
