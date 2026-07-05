import Combine
import Foundation

/// Persists user-configurable settings via UserDefaults. Values are always stored in a canonical
/// unit (km/h for the gauge max) so the meaning of a stored number never depends on the current
/// display unit.
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let maxGaugeSpeedKMH = "maxGaugeSpeedKMH"
        static let measurementSystem = "measurementSystem"
    }

    @Published var maxGaugeSpeedKMH: Double {
        didSet { UserDefaults.standard.set(maxGaugeSpeedKMH, forKey: Keys.maxGaugeSpeedKMH) }
    }

    @Published var measurementSystem: MeasurementSystem {
        didSet { UserDefaults.standard.set(measurementSystem.rawValue, forKey: Keys.measurementSystem) }
    }

    init() {
        let defaults = UserDefaults.standard
        maxGaugeSpeedKMH = (defaults.object(forKey: Keys.maxGaugeSpeedKMH) as? Double) ?? 60
        measurementSystem = defaults.string(forKey: Keys.measurementSystem)
            .flatMap(MeasurementSystem.init(rawValue:)) ?? .metric
    }
}
