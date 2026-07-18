import Foundation
import Testing

@testable import BikeSpeed

/// `TripDateRange.contains` is a pure function of `(date, now, calendar)`, all injected — so, like
/// `TripLogSummaryTests`, every case here is deterministic and pins a boundary. The boundaries are the
/// whole reason the logic lives in a value type rather than inline in the list view.
@Suite
struct TripDateRangeTests {

    @Test
    func allAcceptsEveryDateHoweverFarAway() throws {
        let calendar = utcCalendar()
        let ancient = try date(1998, 1, 1, in: calendar)
        let future = try date(2099, 12, 31, in: calendar)

        #expect(TripDateRange.all.contains(ancient, now: try now(), calendar: calendar))
        #expect(TripDateRange.all.contains(future, now: try now(), calendar: calendar))
    }

    /// The rolling seven-day window is inclusive at its far edge: a ride exactly seven days before `now`
    /// still counts, and one a day older does not.
    @Test(.tags(.edgeCase))
    func last7DaysIncludesTheRideExactlySevenDaysBackAndExcludesTheOneBeyond() throws {
        let calendar = utcCalendar()
        let now = try now() // 2026-07-14 12:00

        let sixDaysAgo = try date(2026, 7, 8, in: calendar)
        let exactlySevenDaysAgo = try date(2026, 7, 7, in: calendar)
        let eightDaysAgo = try date(2026, 7, 6, in: calendar)

        #expect(TripDateRange.last7Days.contains(sixDaysAgo, now: now, calendar: calendar))
        #expect(TripDateRange.last7Days.contains(exactlySevenDaysAgo, now: now, calendar: calendar))
        #expect(!TripDateRange.last7Days.contains(eightDaysAgo, now: now, calendar: calendar))
    }

    /// A future-dated trip (clock skew, a fix stamped ahead of `now`) is outside a window that ends at
    /// `now` — the window looks back, not forward.
    @Test(.tags(.edgeCase))
    func last7DaysExcludesATripDatedAfterNow() throws {
        let calendar = utcCalendar()
        let tomorrow = try date(2026, 7, 15, in: calendar)

        #expect(!TripDateRange.last7Days.contains(tomorrow, now: try now(), calendar: calendar))
    }

    @Test
    func last30DaysSpansThirtyDaysBackButNotThirtyOne() throws {
        let calendar = utcCalendar()
        let now = try now()

        #expect(TripDateRange.last30Days.contains(try date(2026, 6, 14, in: calendar), now: now, calendar: calendar))
        #expect(!TripDateRange.last30Days.contains(try date(2026, 6, 13, in: calendar), now: now, calendar: calendar))
    }

    /// "This year" is the calendar year containing `now`, so 1 January of that year is in and 31 December
    /// of the year before is out — even though the latter is well within the last few months.
    @Test(.tags(.edgeCase))
    func thisYearIsTheCalendarYearNotARollingWindow() throws {
        let calendar = utcCalendar()
        let now = try now() // 2026

        #expect(TripDateRange.thisYear.contains(try date(2026, 1, 1, in: calendar), now: now, calendar: calendar))
        #expect(TripDateRange.thisYear.contains(try date(2026, 12, 31, in: calendar), now: now, calendar: calendar))
        #expect(!TripDateRange.thisYear.contains(try date(2025, 12, 31, in: calendar), now: now, calendar: calendar))
    }

    // MARK: - Helpers

    /// Tuesday 14 July 2026, noon — the day every window here is reasoned from.
    private func now() throws -> Date {
        try date(2026, 7, 14, in: utcCalendar())
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// UTC, so no case turns on the machine's time zone shifting a date across midnight.
    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
