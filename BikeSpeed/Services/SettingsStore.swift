import Foundation
import Observation

/// Persists user-configurable settings via UserDefaults. Values are stored in a canonical unit (km/h
/// for the gauge max) so a stored number's meaning never depends on the current display unit.
///
/// The `didSet` writes are the whole persistence mechanism; they survive `@Observable` because the macro
/// leaves the observer on the stored property it generates behind each. Not obvious enough to trust
/// silently — `SettingsStoreTests.settingsSurviveARelaunch` pins it.
@Observable
final class SettingsStore {
    private enum Keys {
        static let maxGaugeSpeedKMH = "maxGaugeSpeedKMH"
        static let measurementSystem = "measurementSystem"
        static let appLanguage = "appLanguage"
        static let autoPauseEnabled = "autoPauseEnabled"
    }

    var maxGaugeSpeedKMH: Double {
        didSet { defaults.set(maxGaugeSpeedKMH, forKey: Keys.maxGaugeSpeedKMH) }
    }

    var measurementSystem: MeasurementSystem {
        didSet { defaults.set(measurementSystem.rawValue, forKey: Keys.measurementSystem) }
    }

    var appLanguage: AppLanguage {
        didSet { defaults.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    var autoPauseEnabled: Bool {
        didSet { defaults.set(autoPauseEnabled, forKey: Keys.autoPauseEnabled) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    /// Injectable so tests get a throwaway suite instead of reading and writing the real shared defaults.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        maxGaugeSpeedKMH = (defaults.object(forKey: Keys.maxGaugeSpeedKMH) as? Double) ?? 60
        measurementSystem = defaults.string(forKey: Keys.measurementSystem)
            .flatMap(MeasurementSystem.init(rawValue:)) ?? .metric
        appLanguage = defaults.string(forKey: Keys.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        // `object(forKey:)`, not `bool(forKey:)`: the latter reports an unset key as `false`,
        // indistinguishable from a deliberate off, which would defeat the default-on.
        autoPauseEnabled = (defaults.object(forKey: Keys.autoPauseEnabled) as? Bool) ?? true
    }
}
