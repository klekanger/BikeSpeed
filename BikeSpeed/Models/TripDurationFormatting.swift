import Foundation

/// Formats a trip's active duration for display. Unlike `MeasurementSystem`'s formatters, this
/// doesn't vary between metric/imperial, so it lives as its own small utility rather than as a
/// method on that type.
enum TripDurationFormatting {
    static func formatted(seconds: TimeInterval, locale: Locale) -> String {
        let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600 ? .hourMinuteSecond : .minuteSecond
        return Duration.seconds(Int(seconds.rounded()))
            .formatted(.time(pattern: pattern).locale(locale))
    }
}
