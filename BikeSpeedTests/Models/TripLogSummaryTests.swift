import CoreLocation
import Foundation
import Testing

@testable import BikeSpeed

/// `TripLogSummary` is a pure function of `(entries, calendar, now)` — all three injected — so every case
/// here is deterministic. That is the whole reason the type exists rather than the arithmetic living in the
/// view: "this week" depends on a calendar and a clock, and neither is testable through SwiftUI.
@Suite
struct TripLogSummaryTests {

    /// The rider who opens the log before their first ride must see zeroes, not an empty screen and not a
    /// crash — the view renders the Totals section unconditionally.
    @Test
    func anEmptyLogSummarizesToZeroRatherThanNil() throws {
        let summary = TripLogSummary(entries: [], calendar: calendar(firstWeekday: 2), now: try today())

        #expect(summary.allTime.rideCount == 0)
        expectClose(summary.allTime.distance, 0)
        expectClose(summary.allTime.duration, 0)
        expectClose(summary.allTime.ascent, 0)
        #expect(summary.personalBests.longestRide == nil)
        #expect(summary.personalBests.biggestClimb == nil)
    }

    @Test
    func lifetimeTotalsSumEveryRide() throws {
        let calendar = calendar(firstWeekday: 2)
        let entries = [
            makeEntry(startDate: try date(2026, 7, 14, in: calendar), distance: 10_000, duration: 1_800, ascent: 120),
            makeEntry(startDate: try date(2026, 3, 2, in: calendar), distance: 5_000, duration: 900, ascent: 40),
        ]

        let summary = TripLogSummary(entries: entries, calendar: calendar, now: try today())

        #expect(summary.allTime.rideCount == 2)
        expectClose(summary.allTime.distance, 15_000)
        expectClose(summary.allTime.duration, 2_700)
        expectClose(summary.allTime.ascent, 160)
    }

    /// A trip recorded before elevation shipped has no ascent figure at all — that is not the same as having
    /// climbed nothing, and counting it as zero would quietly drag the lifetime total down.
    @Test
    func ridesWithNoAscentFigureAreSkippedRatherThanCountedAsFlat() throws {
        let calendar = calendar(firstWeekday: 2)
        let entries = [
            makeEntry(startDate: try date(2026, 7, 14, in: calendar), distance: 10_000, ascent: 120),
            makeEntry(startDate: try date(2026, 7, 14, in: calendar), distance: 10_000, ascent: nil),
        ]

        let summary = TripLogSummary(entries: entries, calendar: calendar, now: try today())

        expectClose(summary.allTime.ascent, 120)
        #expect(summary.allTime.rideCount == 2, "the ride still happened — only its climb is unknown")
        expectClose(summary.allTime.distance, 20_000)
    }

    /// **The `nb_NO` trap.** "This week" is not a fixed seven days back: it starts on the calendar's first
    /// weekday, which is Monday in Norway and Sunday in the US. The same Sunday ride therefore belongs to a
    /// different week depending on the locale, and a naive implementation gets one of the two wrong.
    ///
    /// `now` here is Tuesday 14 July 2026. With a Monday-start calendar the week began on the 13th, so the
    /// ride on Sunday the 12th belongs to *last* week. With a Sunday-start calendar the week began on the
    /// 12th, so the very same ride is in *this* one.
    @Test(.tags(.edgeCase))
    func thisWeekStartsOnTheCalendarsFirstWeekdayRatherThanSevenDaysBack() throws {
        let mondayStart = calendar(firstWeekday: 2)
        let sundayStart = calendar(firstWeekday: 1)
        let sundayRide = makeEntry(startDate: try date(2026, 7, 12, in: mondayStart), distance: 8_000)

        let norwegian = TripLogSummary(entries: [sundayRide], calendar: mondayStart, now: try today())
        let american = TripLogSummary(entries: [sundayRide], calendar: sundayStart, now: try today())

        #expect(norwegian.thisWeek.rideCount == 0, "a Monday-start week beginning the 13th excludes the 12th")
        #expect(american.thisWeek.rideCount == 1, "a Sunday-start week beginning the 12th includes it")
        #expect(norwegian.allTime.rideCount == 1, "and the ride is in the lifetime total either way")
    }

    @Test
    func thisWeekCountsARideInsideTheCurrentWeek() throws {
        let calendar = calendar(firstWeekday: 2)
        let entries = [
            makeEntry(startDate: try date(2026, 7, 13, in: calendar), distance: 8_000, duration: 1_200), // Monday
            makeEntry(startDate: try date(2026, 7, 6, in: calendar), distance: 4_000, duration: 600), // last Monday
        ]

        let summary = TripLogSummary(entries: entries, calendar: calendar, now: try today())

        #expect(summary.thisWeek.rideCount == 1)
        expectClose(summary.thisWeek.distance, 8_000)
        expectClose(summary.thisWeek.duration, 1_200)
    }

    @Test(.tags(.edgeCase))
    func thisMonthExcludesTheRideOnTheLastDayOfTheMonthBefore() throws {
        let calendar = calendar(firstWeekday: 2)
        let entries = [
            makeEntry(startDate: try date(2026, 7, 1, in: calendar), distance: 3_000),
            makeEntry(startDate: try date(2026, 6, 30, in: calendar), distance: 9_000),
        ]

        let summary = TripLogSummary(entries: entries, calendar: calendar, now: try today())

        #expect(summary.thisMonth.rideCount == 1)
        expectClose(summary.thisMonth.distance, 3_000, within: 0.01)
    }

    @Test
    func personalBestsPickTheRightRideForEachCategory() throws {
        let calendar = calendar(firstWeekday: 2)
        let long = makeEntry(startDate: try date(2026, 7, 1, in: calendar), distance: 80_000, averageSpeed: 5, maxSpeed: 9, ascent: 100)
        let fast = makeEntry(startDate: try date(2026, 7, 2, in: calendar), distance: 20_000, averageSpeed: 9, maxSpeed: 12, ascent: 50)
        let quick = makeEntry(startDate: try date(2026, 7, 3, in: calendar), distance: 10_000, averageSpeed: 6, maxSpeed: 18, ascent: 20)
        let hilly = makeEntry(startDate: try date(2026, 7, 4, in: calendar), distance: 30_000, averageSpeed: 4, maxSpeed: 10, ascent: 900)

        let bests = TripLogSummary(entries: [long, fast, quick, hilly], calendar: calendar, now: try today()).personalBests

        #expect(bests.longestRide?.id == long.id)
        #expect(bests.fastestAverage?.id == fast.id)
        #expect(bests.highestMaxSpeed?.id == quick.id)
        #expect(bests.biggestClimb?.id == hilly.id)
    }

    /// A trip with no ascent figure cannot hold the climbing record — and when *no* trip has one, there is no
    /// record to show rather than a fictional 0 m best.
    @Test(.tags(.edgeCase))
    func theClimbingRecordIgnoresRidesThatNeverRecordedAscent() throws {
        let calendar = calendar(firstWeekday: 2)
        let climbed = makeEntry(startDate: try date(2026, 7, 1, in: calendar), distance: 10_000, ascent: 250)
        let unknown = makeEntry(startDate: try date(2026, 7, 2, in: calendar), distance: 90_000, ascent: nil)

        #expect(TripLogSummary(entries: [climbed, unknown], calendar: calendar, now: try today()).personalBests.biggestClimb?.id == climbed.id)
        #expect(
            TripLogSummary(entries: [unknown], calendar: calendar, now: try today()).personalBests.biggestClimb == nil,
            "no trip has climbed, so there is no climbing record — not a 0 m one"
        )
    }

    /// Two rides of exactly the same length is an ordinary thing (a commute, ridden twice). It must pick one
    /// and carry on, not trap on an ambiguous maximum.
    @Test(.tags(.edgeCase))
    func tiedPersonalBestsPickOneRideRatherThanFailing() throws {
        let calendar = calendar(firstWeekday: 2)
        let first = makeEntry(startDate: try date(2026, 7, 1, in: calendar), distance: 12_000)
        let second = makeEntry(startDate: try date(2026, 7, 2, in: calendar), distance: 12_000)

        let best = try #require(TripLogSummary(entries: [first, second], calendar: calendar, now: try today()).personalBests.longestRide)

        #expect([first.id, second.id].contains(best.id))
    }

    // MARK: - Helpers

    /// Tuesday 14 July 2026 — the day every "this week"/"this month" case above is reasoned from.
    private func today() throws -> Date {
        try date(2026, 7, 14, in: calendar(firstWeekday: 2))
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    /// UTC throughout, so a case never turns on the machine's time zone shifting a date across midnight.
    private func calendar(firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    private func makeEntry(
        startDate: Date,
        distance: CLLocationDistance = 10_000,
        duration: TimeInterval = 1_800,
        averageSpeed: CLLocationSpeed = 6.8,
        maxSpeed: CLLocationSpeed = 11.4,
        ascent: CLLocationDistance? = nil
    ) -> TripLogEntry {
        TripLogEntry(
            id: UUID(),
            startDate: startDate,
            duration: duration,
            distance: distance,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            totalAscent: ascent,
            totalDescent: ascent
        )
    }
}
