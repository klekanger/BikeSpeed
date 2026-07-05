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
    /// Not sourced from Foundation's locale-aware `Measurement` formatting: that produces "km/hr"
    /// (English) and "mile/t" (Norwegian) for this unit via `MeasurementFormatter`, neither of which
    /// matches the abbreviations riders expect, so the two supported languages are hardcoded instead.
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
    /// Builds the unit suffix from `gaugeUnitLabel` rather than `Measurement`'s locale-aware
    /// formatting: the latter renders mph as "miles/t" in Norwegian, which isn't one of this app's
    /// two supported unit labels (see `gaugeUnitLabel`'s doc comment for the metric equivalent).
    func formattedSpeed(metersPerSecond: Double, fractionDigits: Int = 1, locale: Locale) -> String {
        let value = speedValue(metersPerSecond: metersPerSecond)
        let formattedValue = value.formatted(.number.precision(.fractionLength(fractionDigits)).locale(locale))
        return "\(formattedValue) \(gaugeUnitLabel(locale: locale).lowercased())"
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
    /// See `formattedSpeed` for why the unit suffix comes from `gaugeUnitLabel` rather than
    /// `Measurement`'s own locale-aware formatting.
    func formattedMaxGaugeSpeed(fromCanonicalKMH kmh: Double, fractionDigits: Int = 0, locale: Locale) -> String {
        let value = maxGaugeSpeedValue(fromCanonicalKMH: kmh)
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
