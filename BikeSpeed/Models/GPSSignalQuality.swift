import CoreLocation

/// Coarse GPS signal quality derived from a fix's horizontal accuracy, used to drive the
/// signal indicator in the top-left corner. `.poor` means the fix is too inaccurate to trust,
/// so `LocationManager` freezes speed and stops accumulating distance rather than feeding it in.
enum GPSSignalQuality: Equatable {
    case good
    case fair
    case poor

    /// Buckets a horizontal accuracy (meters; negative means "invalid" per CoreLocation) into a
    /// quality level. `good` and `max` are the upper accuracy bounds (in meters) for the green and
    /// yellow bands respectively; anything worse than `max`, or invalid, is `.poor`.
    init(horizontalAccuracy: CLLocationAccuracy, goodWithin good: CLLocationAccuracy, acceptableWithin max: CLLocationAccuracy) {
        if horizontalAccuracy < 0 || horizontalAccuracy > max {
            self = .poor
        } else if horizontalAccuracy <= good {
            self = .good
        } else {
            self = .fair
        }
    }

    /// Whether a fix at this quality should be trusted enough to update speed / accumulate distance.
    var isUsable: Bool { self != .poor }
}
