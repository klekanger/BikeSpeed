import CoreGraphics
import CoreMotion
import Observation

/// Publishes a smoothed gravity-direction vector used purely as a cosmetic input to shift the
/// gauge's metallic gradients as the phone is tilted, so the bezel/face look like they catch a
/// fixed light source.
///
/// Uses Core Motion's *device-motion gravity* rather than the raw accelerometer: gravity is the
/// sensor-fused "which way is down" unit vector, free of the user-acceleration and vibration noise
/// that dominates a raw accelerometer on a bike-mounted phone. That lets the effect react quickly
/// (light smoothing) without jittering. `tilt.width`/`tilt.height` are gravity's x/y, each roughly
/// in -1...1; at rest in portrait that's about (0, -1).
@MainActor
@Observable
final class MotionManager {
    private(set) var tilt: CGSize = .zero

    private let manager = CMMotionManager()
    private let updateInterval = 1.0 / 20.0
    /// Low-pass strength per update; higher reacts faster. Gravity is already clean, so this only
    /// needs to take the edge off, not hide vibration.
    private let smoothingFactor = 0.18
    /// Don't republish (and thus redraw the gauge Canvas) when the phone is essentially still —
    /// only push a new value once the smoothed tilt has actually drifted a little. Still needed under
    /// `@Observable`: Observation fires on any write, identical or not — it does not diff.
    private let publishThreshold = 0.004
    /// The running filter state, not something anyone draws — tracking it would wake observers 20×/s
    /// for a value no view reads.
    @ObservationIgnored private var smoothedX: Double = 0
    @ObservationIgnored private var smoothedY: Double = 0

    init() {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = updateInterval
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            self.smoothedX += (gravity.x - self.smoothedX) * self.smoothingFactor
            self.smoothedY += (gravity.y - self.smoothedY) * self.smoothingFactor
            let newTilt = CGSize(width: self.smoothedX, height: self.smoothedY)
            if abs(newTilt.width - self.tilt.width) > self.publishThreshold
                || abs(newTilt.height - self.tilt.height) > self.publishThreshold {
                self.tilt = newTilt
            }
        }
    }

    deinit {
        manager.stopDeviceMotionUpdates()
    }
}
