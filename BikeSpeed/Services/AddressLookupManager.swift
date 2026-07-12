import Combine
import CoreLocation
import MapKit

/// Reverse-geocodes accepted GPS fixes into the name of the street the rider is currently on.
///
/// Subscribes to `LocationManager`'s accepted fixes itself (like `TripManager` does), so it only
/// ever sees positions that passed the accuracy filter, and it stays live regardless of trip state.
///
/// Reverse geocoding is a network call and `CLGeocoder` throttles callers that ask too often, so a
/// lookup only fires once the rider has moved `minimumDistanceMeters` *and* `minimumLookupInterval`
/// has passed since the previous attempt. At 20 km/h, 75 m apart is only ~13 seconds — the time
/// gate is what keeps a real ride from being throttled. Apple's throttle is per device (there's no
/// API key and no shared per-developer quota, unlike MapKit JS), so this is about protecting one
/// rider's session, not a resource shared across users.
///
/// Consecutive failures back the interval off exponentially up to `maximumLookupInterval`: if we
/// *are* being throttled, retrying at a fixed 10 s only keeps us throttled.
@MainActor
final class AddressLookupManager: ObservableObject {
    /// The street the rider is currently on, or nil when unknown — no lookup has resolved yet, or
    /// the position is genuinely off-road. Held at its last value across geocoding *failures*
    /// rather than blanking, since a network blip is no reason to throw away a good answer.
    @Published private(set) var streetName: String?

    private var cancellable: AnyCancellable?
    /// Position of the last *resolved* lookup — the anchor the distance gate measures against.
    private var lastLookupLocation: CLLocation?
    /// Time of the last *attempt*, resolved or not; this is what the interval gate measures against.
    private var lastLookupAttempt: Date?
    private var isLookupInProgress = false
    private var consecutiveFailures = 0

    private let minimumDistanceMeters: CLLocationDistance
    private let minimumLookupInterval: TimeInterval
    private let maximumLookupInterval: TimeInterval

    init(
        locationManager: LocationManager,
        minimumDistanceMeters: CLLocationDistance = 75,
        minimumLookupInterval: TimeInterval = 10,
        maximumLookupInterval: TimeInterval = 120
    ) {
        self.minimumDistanceMeters = minimumDistanceMeters
        self.minimumLookupInterval = minimumLookupInterval
        self.maximumLookupInterval = maximumLookupInterval

        cancellable = locationManager.acceptedLocations.sink { [weak self] location in
            self?.consume(location)
        }
    }

    /// How long to wait before the next attempt: the base interval while things are healthy,
    /// doubling per consecutive failure (10 s → 20 s → 40 s …) up to `maximumLookupInterval`.
    private var currentLookupInterval: TimeInterval {
        guard consecutiveFailures > 0 else { return minimumLookupInterval }
        let backoff = minimumLookupInterval * pow(2, Double(consecutiveFailures))
        return min(backoff, maximumLookupInterval)
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

        Task { [weak self] in
            guard let self else { return }
            defer { self.isLookupInProgress = false }

            do {
                self.resolve(try await self.reverseGeocode(location), at: location)
            } catch let error as CLError where error.code == .geocodeFoundNoResult {
                // Not a failure — there genuinely is no street here (a trail, or out at sea). It's a
                // resolved "nothing", so blank the caption and let the gates advance as usual.
                self.resolve(nil, at: location)
            } catch {
                // Network down, or the geocoder is throttling us. Keep showing the last street we
                // did resolve, and leave `lastLookupLocation` where it was so the next fix retries —
                // but back off first, so a throttle doesn't turn into us hammering every 10 s.
                self.consecutiveFailures += 1
            }
        }
    }

    private func resolve(_ street: String?, at location: CLLocation) {
        lastLookupLocation = location
        streetName = street
        consecutiveFailures = 0
    }

    private func reverseGeocode(_ location: CLLocation) async throws -> String? {
        if #available(iOS 26.0, *) {
            return try await modernStreetName(for: location)
        } else {
            return try await legacyStreetName(for: location)
        }
    }

    /// `shortAddress` is the only street-bearing string MapKit offers — `MKAddress` exposes just
    /// `fullAddress`/`shortAddress`, and `MKAddressRepresentations` only adds city/region — so the
    /// street has to be picked out of a formatted address by hand.
    ///
    /// Known difference from the legacy path: with no street nearby, `shortAddress` falls back to a
    /// broader place name ("Nord-Atlanteren" out at sea, a park name on a trail) where
    /// `thoroughfare` would simply be nil. That's a reasonable thing to show on a bike, so it's left
    /// alone — just don't expect the two paths to blank out at the same moment.
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
    /// `thoroughfare` the legacy path returns. `shortAddress` carries a locality ("Stockton St,
    /// San Francisco") and a house number, neither of which is useful at a glance on a handlebar.
    ///
    /// The house number sits on whichever side the locale puts it — leading in the US
    /// ("1-99 Stockton St"), trailing in Norway ("Storgata 12") — so both ends are trimmed.
    static func streetComponent(of shortAddress: String) -> String? {
        let street = shortAddress
            .split(separator: ",", maxSplits: 1)
            .first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""

        var parts = street.split(separator: " ")
        if parts.count > 1, isHouseNumber(parts[0]) {
            parts.removeFirst()
        }
        if parts.count > 1, let last = parts.last, isHouseNumber(last) {
            parts.removeLast()
        }

        let result = parts.joined(separator: " ")
        return result.isEmpty ? nil : result
    }

    /// Whether a token is a house number rather than part of the street's name. Numbers can be
    /// ranged or suffixed ("1-99", "12B"), but a street genuinely named with a numeral — "5th
    /// Avenue" — carries more than one letter, which is what tells the two apart.
    private static func isHouseNumber(_ token: Substring) -> Bool {
        guard let first = token.first, first.isNumber else { return false }
        return token.filter(\.isLetter).count <= 1
    }
}
