import CoreLocation

extension CLLocation {
    /// The fix's altitude when it can be trusted, nil otherwise. Negative `verticalAccuracy` is CoreLocation's
    /// "no altitude" sentinel; above `ceiling` the reading exists but its error bar dwarfs the measurement —
    /// an accumulator banking every 3 m move can't take a 30 m error bar. Every consumer of `altitude` goes
    /// through here so the rule can't drift apart between height profile, climb totals and live readout.
    func usableAltitude(within ceiling: CLLocationAccuracy = .greatestFiniteMagnitude) -> CLLocationDistance? {
        guard verticalAccuracy >= 0, verticalAccuracy <= ceiling else { return nil }
        return altitude
    }
}
