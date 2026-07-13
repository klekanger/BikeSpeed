import Combine
import CoreMotion

/// Publishes the barometer's relative altitude for the trip's ascent/descent accumulation.
///
/// Barometric altitude resolves to roughly ±1 m against GPS's ±10–20 m — the difference between a
/// believable climb figure and a meaningless one. Only altitude *changes* are consumed downstream,
/// so the relative reading (zeroed wherever updates happened to start) is all that's needed.
///
/// Unlike `MotionManager`'s device-motion, `CMAltimeter` requires `NSMotionUsageDescription` — the
/// system prompts on first use.
@MainActor
final class AltimeterManager: ObservableObject, AltitudeSource {
    @Published private(set) var relativeAltitude: Double? // meters, relative to start of updates

    /// False in the Simulator and on devices without a barometer; `TripManager` then falls back to
    /// GPS altitude with a wider deadband.
    let isAvailable: Bool

    private let altimeter = CMAltimeter()

    init() {
        isAvailable = CMAltimeter.isRelativeAltitudeAvailable()
        guard isAvailable else { return }
        altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            Task { @MainActor in
                self.relativeAltitude = data.relativeAltitude.doubleValue
            }
        }
    }

    deinit {
        altimeter.stopRelativeAltitudeUpdates()
    }
}
