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
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(fractionDigits))))
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

    /// Formats a gauge max speed stored canonically in km/h in this system's speed unit.
    func formattedMaxGaugeSpeed(fromCanonicalKMH kmh: Double, fractionDigits: Int = 0) -> String {
        Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
            .converted(to: speedUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(fractionDigits))))
    }

    /// Converts a gauge max speed expressed in this system's speed unit back into canonical km/h (for stepper use).
    func canonicalKMH(fromMaxGaugeSpeedValue value: Double) -> Double {
        Measurement(value: value, unit: speedUnit)
            .converted(to: .kilometersPerHour)
            .value
    }

    /// Stepper increment for the gauge max speed, expressed in this system's speed unit.
    var maxGaugeSpeedStep: Double { 5 }

    /// Stepper range for the gauge max speed, expressed in this system's speed unit.
    var maxGaugeSpeedRange: ClosedRange<Double> {
        switch self {
        case .metric: return 20...200
        case .imperial: return 10...125
        }
    }
}
