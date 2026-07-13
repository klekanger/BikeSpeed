import Combine
import CoreMotion

/// Provides the barometer's relative altitude for the trip's ascent/descent accumulation.
///
/// Barometric altitude resolves to roughly ±1 m against GPS's ±10–20 m — the difference between a
/// believable climb figure and a meaningless one. Only altitude *changes* are consumed downstream,
/// so the relative reading (zeroed wherever updates happened to start) is all that's needed.
///
/// Unlike `MotionManager`'s device-motion, `CMAltimeter` requires `NSMotionUsageDescription` — the
/// system prompts when updates first start, which is why they start with the first trip (see
/// `AltitudeSource`) rather than in `init`.
@MainActor
final class AltimeterManager: ObservableObject, AltitudeSource {
    /// Deliberately not `@Published`: nothing subscribes — `TripManager` samples it synchronously at
    /// each accepted fix — and a published write here would re-evaluate the app's scene body once a
    /// second for the whole time the barometer runs.
    private(set) var relativeAltitude: Double?

    /// Starts as "does the hardware exist" and drops to false the first time an update errors —
    /// which is how a denied Motion & Fitness permission presents; `isRelativeAltitudeAvailable()`
    /// itself keeps reporting true. `TripManager` reads this to fall back to GPS altitude, so
    /// hardware presence alone must not keep it waiting on readings that will never come.
    private(set) var isAvailable: Bool

    private let altimeter = CMAltimeter()
    private var isUpdating = false

    init() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
    }

    /// Whether Settings should point the user at the Motion & Fitness toggle. iOS shows the
    /// permission prompt once per install and it can never be re-triggered, so after a denial this
    /// pointer is the only way back to barometric climb. True only for an actual `.denied`: without
    /// barometer hardware the permission unlocks nothing (climb is GPS either way), and under
    /// `.restricted` the toggle isn't the user's to flip. The defaults read the live system state;
    /// tests pass both explicitly.
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

    /// Stops the barometer and forgets its reading: relative altitude is zeroed wherever updates
    /// start, so a value from before the stop must never be readable afterwards — the next trip
    /// would latch onto a baseline the restarted sensor no longer measures against.
    func stopUpdates() {
        guard isUpdating else { return }
        isUpdating = false
        altimeter.stopRelativeAltitudeUpdates()
        relativeAltitude = nil
    }
}
