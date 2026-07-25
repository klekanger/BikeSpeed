import Combine
import CoreLocation

/// What `TripManager` needs from the GPS: the stream of accepted fixes, and a way to keep them arriving
/// while backgrounded. `LocationManager` is the real implementation; tests substitute a fake, so trip
/// behaviour is asserted against what was *requested* rather than against CoreLocation.
@MainActor
protocol LocationSource: AnyObject {
    var acceptedLocations: PassthroughSubject<CLLocation, Never> { get }

    /// Ask for (or release) background location updates. On only while a trip is recording — held
    /// permanently it would keep GPS awake and drain the battery whenever the app is merely backgrounded.
    func setBackgroundUpdates(_ enabled: Bool)
}
