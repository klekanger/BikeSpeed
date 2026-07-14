import CoreLocation
import Foundation

/// A saved, completed trip — the *scalar* summary of one. All measurements are in SI units (meters, m/s,
/// seconds), matching the convention used throughout the model layer; the view layer converts via
/// `MeasurementSystem` for display, same as the live trip stats.
///
/// This is the domain value, not the row: `StoredTrip` is what SwiftData persists, and this is what the pure
/// code speaks — what `TripLogSummary` reduces, what the list draws, and (being `Codable` already) what a
/// future web service would put on the wire unchanged.
///
/// **The heavy per-trip payloads are deliberately not here.** The height profile and the recorded track are
/// hundreds-to-thousands of samples each, and the trip list draws neither. They live as blobs on `StoredTrip`
/// and are loaded only when a single trip's detail is opened — off the main actor, which is exactly when they
/// are cheap. Folding either one back into this struct would put every trip's payload into every render of
/// the list.
struct TripLogEntry: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let startDate: Date
    let duration: TimeInterval // seconds, active duration only
    let distance: CLLocationDistance // meters
    let averageSpeed: CLLocationSpeed // m/s
    let maxSpeed: CLLocationSpeed // m/s
    /// Nil, not zero. A trip recorded without usable altitude data has no answer to "how much did you climb",
    /// and 0 would be indistinguishable from a genuinely flat ride.
    let totalAscent: CLLocationDistance? // meters
    let totalDescent: CLLocationDistance? // meters, positive
}
