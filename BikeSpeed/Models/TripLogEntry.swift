import CoreLocation
import Foundation

/// A saved, completed trip. All measurements are stored in SI units (meters, m/s, seconds),
/// matching the convention used throughout the model layer — the view layer converts via
/// `MeasurementSystem` for display, same as the live trip stats.
struct TripLogEntry: Codable, Identifiable, Hashable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval // seconds, active duration only
    let distance: CLLocationDistance // meters
    let averageSpeed: CLLocationSpeed // m/s
    let maxSpeed: CLLocationSpeed // m/s
    let altitudeProfile: [AltitudeSample]
}

/// One point of a trip's height profile. `distance` is the accumulated trip distance-so-far at
/// the moment this sample was taken (not a timestamp), since it's monotonic and unaffected by
/// pause gaps — the natural X-axis for an elevation chart.
struct AltitudeSample: Codable, Hashable {
    let distance: CLLocationDistance // meters
    let altitude: CLLocationDistance // meters
}
