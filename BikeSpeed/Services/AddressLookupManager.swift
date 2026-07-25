import Combine
import CoreLocation
import MapKit
import Observation

/// Reverse-geocodes accepted GPS fixes into the name of the street the rider is currently on.
///
/// Subscribes to `LocationManager`'s accepted fixes (like `TripManager`), so it only sees positions past
/// the accuracy filter and stays live regardless of trip state.
///
/// Reverse geocoding is a network call and `CLGeocoder` throttles callers that ask too often, so a lookup
/// fires only once the rider has moved `minimumDistanceMeters` *and* `minimumLookupInterval` has passed
/// since the last attempt. At 20 km/h, 75 m is ~13 s, so the time gate is what keeps a real ride from being
/// throttled. The throttle is per device (no API key or shared quota, unlike MapKit JS) — this protects one
/// rider's session, not a shared resource.
///
/// Consecutive failures back the interval off exponentially up to `maximumLookupInterval`: if we *are*
/// throttled, retrying at a fixed 10 s only keeps us throttled.
@MainActor
@Observable
final class AddressLookupManager {
    /// The street the rider is on, or nil when unknown (nothing resolved yet, or genuinely off-road). Held
    /// at its last value across geocoding *failures* — a network blip is no reason to drop a good answer.
    private(set) var streetName: String?

    /// All untracked: the lookup gates are internal bookkeeping; `streetName` is the only thing views draw.
    @ObservationIgnored private var cancellable: AnyCancellable?
    /// Position of the last *resolved* lookup — anchor for the distance gate.
    @ObservationIgnored private var lastLookupLocation: CLLocation?
    /// Time of the last *attempt*, resolved or not — anchor for the interval gate.
    @ObservationIgnored private var lastLookupAttempt: Date?
    @ObservationIgnored private var isLookupInProgress = false
    @ObservationIgnored private var consecutiveFailures = 0

    private let minimumDistanceMeters: CLLocationDistance = 75
    private let minimumLookupInterval: TimeInterval = 10
    private let maximumLookupInterval: TimeInterval = 120

    init(locationManager: LocationManager) {
        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
    }

    /// Wait before the next attempt: base interval while healthy, doubling per consecutive failure
    /// (10 s → 20 s → 40 s …) up to `maximumLookupInterval`.
    private var currentLookupInterval: TimeInterval {
        min(minimumLookupInterval * pow(2, Double(consecutiveFailures)), maximumLookupInterval)
    }

    private func consume(_ location: CLLocation) {
        guard !isLookupInProgress else { return }

        if let lastLookupLocation, location.distance(from: lastLookupLocation) < minimumDistanceMeters {
            return
        }
        if let lastLookupAttempt, Date().timeIntervalSince(lastLookupAttempt) < currentLookupInterval {
            return
        }

        isLookupInProgress = true
        lastLookupAttempt = Date()

        Task { [self] in
            defer { isLookupInProgress = false }

            do {
                resolve(try await reverseGeocode(location), at: location)
            } catch let error as CLError where error.code == .geocodeFoundNoResult {
                // Not a failure — genuinely no street here (trail, or out at sea). A resolved "nothing":
                // blank the caption and let the gates advance.
                resolve(nil, at: location)
            } catch {
                // Network down or throttled. Keep the last resolved street and leave `lastLookupLocation`
                // put so the next fix retries — but back off first, so a throttle doesn't become hammering.
                consecutiveFailures += 1
            }
        }
    }

    private func resolve(_ street: String?, at location: CLLocation) {
        lastLookupLocation = location
        consecutiveFailures = 0
        // One street spans many lookup windows, so most resolutions repeat the last answer. Publish only
        // real changes — every write invalidates the whole ContentView tree.
        if streetName != street {
            streetName = street
        }
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String? {
        if #available(iOS 26.0, *) {
            return try await modernStreetName(for: location)
        } else {
            return try await legacyStreetName(for: location)
        }
    }

    /// `shortAddress` is the only street-bearing string MapKit offers (`MKAddress` exposes only
    /// `fullAddress`/`shortAddress`; `MKAddressRepresentations` only adds city/region), so the street has
    /// to be picked out of a formatted address by hand.
    ///
    /// Differs from the legacy path: with no street nearby, `shortAddress` falls back to a broader place
    /// name ("Nord-Atlanteren" at sea, a park name on a trail) where `thoroughfare` is simply nil. Fine to
    /// show on a bike, so left alone — just don't expect the two paths to blank at the same moment.
    @available(iOS 26.0, *)
    private func modernStreetName(for location: CLLocation) async throws -> String? {
        guard let request = MKReverseGeocodingRequest(location: location) else { return nil }
        let mapItems = try await request.mapItems
        return mapItems.first?.address?.shortAddress.flatMap(Self.streetComponent)
    }

    @available(iOS, deprecated: 26.0, message: "Superseded by MKReverseGeocodingRequest; still the only path on iOS 17–25.")
    private func legacyStreetName(for location: CLLocation) async throws -> String? {
        let placemarks = try await CLGeocoder().reverseGeocodeLocation(location)
        return placemarks.first?.thoroughfare
    }

    /// Reduces a formatted short address to just the street, so the modern path matches the bare
    /// `thoroughfare` the legacy path returns. `shortAddress` carries a locality ("Stockton St, San
    /// Francisco") and a house number, neither useful at a glance on a handlebar.
    ///
    /// The house number sits on whichever side the locale puts it — leading in the US ("1-99 Stockton St"),
    /// trailing in Norway ("Storgata 12") — so both ends are trimmed.
    private static func streetComponent(of shortAddress: String) -> String? {
        var parts = shortAddress.prefix { $0 != "," }.split(separator: " ")
        if parts.count > 1, isHouseNumber(parts[0]) {
            parts.removeFirst()
        }
        if parts.count > 1, let last = parts.last, isHouseNumber(last) {
            parts.removeLast()
        }

        let result = parts.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Whether a token is a house number rather than part of the street name. House numbers can be ranged
    /// or suffixed ("1-99", "12B"); a numeral-named street ("5th Avenue") carries more than one letter,
    /// which tells the two apart.
    private static func isHouseNumber(_ token: Substring) -> Bool {
        guard let first = token.first, first.isNumber else { return false }
        return token.filter(\.isLetter).count <= 1
    }
}
