import CoreMotion
import Testing
@testable import BikeSpeed

/// The Motion & Fitness prompt fires once per install and can never be re-shown; the only recovery
/// from a denial is the user flipping the toggle in the Settings app. These pin when the app's
/// Settings screen offers that pointer — and, as importantly, when it must not.
struct AltimeterManagerTests {
    @Test func aDeniedPermissionOnBarometerHardwareEarnsTheHint() {
        #expect(AltimeterManager.needsMotionPermissionHint(hardwareAvailable: true, authorization: .denied))
    }

    /// Without a barometer (notably the Simulator) there is nothing the permission would unlock —
    /// climb is measured by GPS either way, so pointing the user at the toggle would be noise.
    @Test func hardwareWithoutABarometerNeverEarnsTheHint() {
        #expect(AltimeterManager.needsMotionPermissionHint(hardwareAvailable: false, authorization: .denied) == false)
    }

    /// `.notDetermined` means the first trip hasn't asked yet, `.authorized` means nothing is wrong,
    /// and `.restricted` means parental controls or a device profile own the toggle — the user can't
    /// flip it, so sending them to Settings would dead-end.
    @Test(arguments: [CMAuthorizationStatus.notDetermined, .authorized, .restricted])
    func onlyAnActualDenialEarnsTheHint(status: CMAuthorizationStatus) {
        #expect(AltimeterManager.needsMotionPermissionHint(hardwareAvailable: true, authorization: status) == false)
    }
}
