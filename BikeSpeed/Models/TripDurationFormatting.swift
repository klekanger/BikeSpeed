import Foundation

/// Formats a trip's active duration. Independent of metric/imperial, so it lives here rather than on
/// `MeasurementSystem`.
enum TripDurationFormatting {
    static func formatted(seconds: TimeInterval, locale: Locale) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(Int(seconds.rounded()))
            .formatted(.time(pattern: pattern).locale(locale))
    }
}
