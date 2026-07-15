import Combine
import CoreLocation

/// What `TripManager` needs from the GPS: the stream of accepted fixes to accumulate, and a way to ask
/// for those fixes to keep arriving while the app is in the background. `LocationManager` is the real
/// implementation; tests substitute a fake, so trip behaviour is asserted against what was *requested*
/// rather than against CoreLocation.
@MainActor
protocol LocationSource: AnyObject {
    var acceptedLocations: PassthroughSubject<CLLocation, Never> { get }

    /// Ask for (or release) location updates while the app is backgrounded. On only while a trip is
    /// actually recording — held permanently, it would keep GPS awake, and the battery draining,
    /// whenever the app is merely backgrounded with no trip running.
    func setBackgroundUpdates(_ enabled: Bool)
}
