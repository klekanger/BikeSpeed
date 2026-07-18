import Foundation
import SwiftUI

/// The date window the trip-log *list* is narrowed to.
///
/// A pure value type in the shape of `TripLogSummary`: `contains(_:now:calendar:)` takes `now` and a
/// `Calendar` as arguments rather than reading `Date()`/`.current`, so `TripDateRangeTests` can pin every
/// boundary deterministically instead of testing through SwiftUI.
///
/// **It filters the list only, never the summary above it.** Lifetime totals and personal bests stay
/// lifetime whatever range is selected — your top speed is your top speed regardless of which window you
/// are looking at. `TripLogListView` keeps feeding `TripLogSummarySection` the full, unfiltered query.
enum TripDateRange: CaseIterable, Hashable {
    case all
    case last7Days
    case last30Days
    case thisYear

    /// The menu/Picker label. A `LocalizedStringKey` handed to `Text` and resolved through the in-app
    /// language override's locale (`BikeSpeedApp` injects `\.locale`) — deliberately *not*
    /// `AppLanguage.localizedString(forKey:)`, which is only for `String`-typed code.
    var titleKey: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .thisYear: "This year"
        }
    }

    /// Whether a trip that started at `date` falls inside this range as of `now`.
    ///
    /// The day-count windows are *rolling* — "last 7 days" is the seven days up to `now`, not a calendar
    /// week; the summary's "This week" already covers the calendar-week meaning. "This year" is the
    /// calendar year containing `now`, via the same `dateInterval(of:for:)` idiom `TripLogSummary` uses,
    /// so it honours the calendar's own year boundary rather than a naive 365-day slice.
    func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
        switch self {
        case .all:
            return true
        case .last7Days:
            return isWithin(days: 7, of: date, now: now, calendar: calendar)
        case .last30Days:
            return isWithin(days: 30, of: date, now: now, calendar: calendar)
        case .thisYear:
            // A calendar with no representable year interval can't sensibly exclude anything, so fall open.
            guard let interval = calendar.dateInterval(of: .year, for: now) else { return true }
            return interval.contains(date)
        }
    }

    private func isWithin(days: Int, of date: Date, now: Date, calendar: Calendar) -> Bool {
        guard let start = calendar.date(byAdding: .day, value: -days, to: now) else { return true }
        return date >= start && date <= now
    }
}
