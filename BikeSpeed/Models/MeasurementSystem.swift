import Foundation

enum MeasurementSystem: String, CaseIterable, Identifiable {
    case metric
    case imperial

    var id: String { rawValue }

    var speedUnit: UnitSpeed {
        switch self {
        case .metric: return .kilometersPerHour
        case .imperial: return .milesPerHour
        }
    }

    var distanceUnit: UnitLength {
        switch self {
        case .metric: return .kilometers
        case .imperial: return .miles
        }
    }

    var altitudeUnit: UnitLength {
        switch self {
        case .metric: return .meters
        case .imperial: return .feet
        }
    }

    /// Center-of-gauge unit label, e.g. "KM/H" / "MPH".
    var gaugeUnitLabel: String {
        switch self {
        case .metric: return "KM/H"
        case .imperial: return "MPH"
        }
    }

    func speedValue(metersPerSecond: Double) -> Double {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: speedUnit)
            .value
    }

    func formattedSpeed(metersPerSecond: Double, fractionDigits: Int = 1) -> String {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: speedUnit)
            .formatted(.measurement(width: .abbreviated, numberFormatStyle: .number.precision(.fractionLength(fractionDigits))))
    }

    func formattedDistance(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: distanceUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))))
    }

    func formattedAltitude(meters: Double) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: altitudeUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    /// Converts a gauge max speed stored canonically in km/h into this system's speed unit (for display/stepper use).
    func maxGaugeSpeedValue(fromCanonicalKMH kmh: Double) -> Double {
        Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
            .converted(to: speedUnit)
            .value
    }
}
