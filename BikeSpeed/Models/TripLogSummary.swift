import CoreLocation
import Foundation

/// Everything the trip log shows *about* the trips, as opposed to the trips themselves: the odometer, the
/// last week and month, and the rider's personal bests.
///
/// A pure function of `(entries, calendar, now)`, with all three injected. Both of the latter two matter:
/// "this week" starts on the calendar's first weekday — Monday in Norway, Sunday in the US — so the same
/// Sunday ride falls in a different week depending on the locale, and "this week" is meaningless without
/// being told when now is. Keeping them as parameters rather than reaching for `.current`/`Date()` is what
/// makes the whole thing testable; `TripLogSummaryTests` pins the weekday case in particular.
///
/// Distances stay in SI units, like every other model type — `TripLogListView` converts for display.
struct TripLogSummary {

    /// A zeroed total is the honest answer for a rider with no rides, and it means the view can render the
    /// section unconditionally rather than branching on emptiness.
    struct Totals: Equatable {
        var rideCount: Int = 0
        var distance: CLLocationDistance = 0 // meters
        var duration: TimeInterval = 0 // seconds
        /// Summed over the trips that *have* an ascent figure. A pre-elevation trip has no answer to "how
        /// much did you climb", which is not the same as having climbed nothing — see `TripLogEntry`.
        var ascent: CLLocationDistance = 0 // meters
    }

    /// Each is nil until there is a ride to hold it. `biggestClimb` stays nil for a log of trips that never
    /// recorded altitude: there is no climbing record, rather than a fictional 0 m one.
    struct PersonalBests {
        var longestRide: TripLogEntry?
        var fastestAverage: TripLogEntry?
        var highestMaxSpeed: TripLogEntry?
        var biggestClimb: TripLogEntry?
    }

    let allTime: Totals
    let thisWeek: Totals
    let thisMonth: Totals
    let personalBests: PersonalBests

    init(entries: [TripLogEntry], calendar: Calendar = .current, now: Date = Date()) {
        allTime = Self.totals(of: entries)
        thisWeek = Self.totals(of: entries, within: .weekOfYear, of: now, calendar: calendar)
        thisMonth = Self.totals(of: entries, within: .month, of: now, calendar: calendar)
        personalBests = PersonalBests(
            longestRide: entries.max { $0.distance < $1.distance },
            fastestAverage: entries.max { $0.averageSpeed < $1.averageSpeed },
            highestMaxSpeed: entries.max { $0.maxSpeed < $1.maxSpeed },
            // Only trips that actually recorded a climb can hold the climbing record — a trip whose ascent
            // is unknown must not win it by being treated as 0, nor lose to one that did nothing.
            biggestClimb: entries.filter { $0.totalAscent != nil }.max { ($0.totalAscent ?? 0) < ($1.totalAscent ?? 0) }
        )
    }

    /// Rides inside the calendar unit — week or month — that contains `now`. `dateInterval(of:for:)` is what
    /// does the real work: it honours the calendar's `firstWeekday`, which is exactly the thing that "seven
    /// days back" would get wrong.
    private static func totals(
        of entries: [TripLogEntry],
        within component: Calendar.Component,
        of now: Date,
        calendar: Calendar
    ) -> Totals {
        guard let interval = calendar.dateInterval(of: component, for: now) else { return Totals() }
        return totals(of: entries.filter { interval.contains($0.startDate) })
    }

    private static func totals(of entries: [TripLogEntry]) -> Totals {
        Totals(
            rideCount: entries.count,
            distance: entries.reduce(0) { $0 + $1.distance },
            duration: entries.reduce(0) { $0 + $1.duration },
            ascent: entries.reduce(0) { $0 + ($1.totalAscent ?? 0) }
        )
    }
}
