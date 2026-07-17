import CoreMotion

/// Provides the barometer's relative altitude for the trip's ascent/descent accumulation.
///
/// Barometric altitude resolves to ~±1 m against GPS's ±10–20 m. Only altitude *changes* are consumed,
/// so the relative reading (zeroed wherever updates started) is all that's needed.
///
/// `CMAltimeter` requires `NSMotionUsageDescription`; the system prompts when updates first start, so
/// they start with the first trip (see `AltitudeSource`), not in `init`.
///
/// Deliberately **not** `@Observable` and not in the environment: no view reads a barometer —
/// `TripManager` samples it synchronously at each accepted fix. Making it observable would only invite
/// a view to read `relativeAltitude` and re-evaluate once a second for as long as the barometer runs.
@MainActor
final class AltimeterManager: AltitudeSource {
    private(set) var relativeAltitude: Double?

    /// Starts as "does the hardware exist", then drops to false the first time an update errors — how a
    /// denied Motion & Fitness permission presents, since `isRelativeAltitudeAvailable()` keeps reporting
    /// true. `TripManager` reads this to fall back to GPS altitude rather than wait on readings that will
    /// never come.
    private(set) var isAvailable: Bool

    private let altimeter = CMAltimeter()
    private var isUpdating = false

    init() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
    }

    /// Whether Settings should point the user at the Motion & Fitness toggle. iOS shows the permission
    /// prompt once per install and never re-triggers it, so after a denial this pointer is the only way
    /// back to barometric climb. True only for an actual `.denied`: without hardware the permission
    /// unlocks nothing (climb is GPS either way), and under `.restricted` the toggle isn't the user's to
    /// flip. Defaults read live system state; tests pass both explicitly.
    static func needsMotionPermissionHint(
        hardwareAvailable: Bool = CMAltimeter.isRelativeAltitudeAvailable(),
        authorization: CMAuthorizationStatus = CMAltimeter.authorizationStatus()
    ) -> Bool {
        hardwareAvailable && authorization == .denied
    }

    deinit {
        altimeter.stopRelativeAltitudeUpdates()
    }

    func startUpdates() {
        guard isAvailable, !isUpdating else { return }
        isUpdating = true
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, error in
            Task { @MainActor in
                guard let self else { return }
                if let data {
                    self.relativeAltitude = data.relativeAltitude.doubleValue
                } else if error != nil {
                    self.isAvailable = false
                    self.stopUpdates()
                }
            }
        }
    }

    /// Stops the barometer and forgets its reading. Relative altitude is zeroed wherever updates start,
    /// so a pre-stop value must never survive: the next trip would latch onto a baseline the restarted
    /// sensor no longer measures against.
    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        altimeter.stopRelativeAltitudeUpdates()
        relativeAltitude = nil
    }
}
