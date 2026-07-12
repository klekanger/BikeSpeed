import Combine
import Foundation

/// Persists user-configurable settings via UserDefaults. Values are always stored in a canonical
/// unit (km/h for the gauge max) so the meaning of a stored number never depends on the current
/// display unit.
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let maxGaugeSpeedKMH = "maxGaugeSpeedKMH"
        static let measurementSystem = "measurementSystem"
        static let appLanguage = "appLanguage"
        static let autoPauseEnabled = "autoPauseEnabled"
    }

    @Published var maxGaugeSpeedKMH: Double {
        didSet { UserDefaults.standard.set(maxGaugeSpeedKMH, forKey: Keys.maxGaugeSpeedKMH) }
    }

    @Published var measurementSystem: MeasurementSystem {
        didSet { UserDefaults.standard.set(measurementSystem.rawValue, forKey: Keys.measurementSystem) }
    }

    @Published var appLanguage: AppLanguage {
        didSet { UserDefaults.standard.set(appLanguage.rawValue, forKey: Keys.appLanguage) }
    }

    @Published var autoPauseEnabled: Bool {
        didSet { UserDefaults.standard.set(autoPauseEnabled, forKey: Keys.autoPauseEnabled) }
    }

    init() {
        let defaults = UserDefaults.standard
        maxGaugeSpeedKMH = (defaults.object(forKey: Keys.maxGaugeSpeedKMH) as? Double) ?? 60
        measurementSystem = defaults.string(forKey: Keys.measurementSystem)
            .flatMap(MeasurementSystem.init(rawValue:)) ?? .metric
        appLanguage = defaults.string(forKey: Keys.appLanguage)
            .flatMap(AppLanguage.init(rawValue:)) ?? .system
        // `object(forKey:)`, not `bool(forKey:)`: the latter reports an unset key as `false`, which
        // is indistinguishable from a deliberate off and would quietly defeat the default-on.
        autoPauseEnabled = (defaults.object(forKey: Keys.autoPauseEnabled) as? Bool) ?? true
    }
}
