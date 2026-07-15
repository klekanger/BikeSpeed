import Testing

extension Tag {
    /// Fixes, filtering, and anything else driven by a `CLLocation`.
    @Tag static var gps: Self
    /// The narrow, easily-broken cases: threshold boundaries, hysteresis, teleport artifacts,
    /// the "unknown" sentinels CoreLocation reports as negative numbers.
    @Tag static var edgeCase: Self
    /// Anything that reads or writes `UserDefaults` or the trip log on disk.
    @Tag static var persistence: Self
}
