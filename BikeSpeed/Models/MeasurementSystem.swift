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

    /// Center-of-gauge unit label, e.g. "KM/H" / "KM/T" / "MPH".
    ///
    /// Hardcoded rather than from `Measurement` formatting, which yields "km/hr" (English) and "mile/t"
    /// (Norwegian) — neither the abbreviation riders expect.
    func gaugeUnitLabel(locale: Locale) -> String {
        let isNorwegian = locale.language.languageCode == Locale.LanguageCode("nb")
        switch self {
        case .metric: return isNorwegian ? "KM/T" : "KM/H"
        case .imperial: return "MPH"
        }
    }

    func speedValue(metersPerSecond: Double) -> Double {
        Measurement(value: metersPerSecond, unit: UnitSpeed.metersPerSecond)
            .converted(to: speedUnit)
            .value
    }

    /// Formats speed as "<value> <unit>", e.g. "24.3 km/h" / "24,3 km/t" / "15.1 mph".
    ///
    /// Unit suffix comes from `gaugeUnitLabel`, not `Measurement`'s formatting (which renders mph as
    /// "miles/t" in Norwegian) — see `gaugeUnitLabel`.
    func formattedSpeed(metersPerSecond: Double, fractionDigits: Int = 1, locale: Locale) -> String {
        formattedSpeedValue(speedValue(metersPerSecond: metersPerSecond), fractionDigits: fractionDigits, locale: locale)
    }

    func formattedDistance(meters: Double, locale: Locale) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: distanceUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(2))).locale(locale))
    }

    func formattedAltitude(meters: Double, locale: Locale) -> String {
        Measurement(value: meters, unit: UnitLength.meters)
            .converted(to: altitudeUnit)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    /// Converts a gauge max speed stored canonically in km/h into this system's speed unit (for display/stepper use).
    func maxGaugeSpeedValue(fromCanonicalKMH kmh: Double) -> Double {
        Measurement(value: kmh, unit: UnitSpeed.kilometersPerHour)
            .converted(to: speedUnit)
            .value
    }

    /// Formats a gauge max speed stored canonically in km/h in this system's speed unit.
    /// See `formattedSpeed` for why the unit suffix comes from `gaugeUnitLabel`.
    func formattedMaxGaugeSpeed(fromCanonicalKMH kmh: Double, fractionDigits: Int = 0, locale: Locale) -> String {
        formattedSpeedValue(maxGaugeSpeedValue(fromCanonicalKMH: kmh), fractionDigits: fractionDigits, locale: locale)
    }

    /// Formats an already-converted speed value with this system's unit suffix.
    private func formattedSpeedValue(_ value: Double, fractionDigits: Int, locale: Locale) -> String {
        let formattedValue = value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
        return "\(formattedValue) \(gaugeUnitLabel(locale: locale).lowercased())"
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
