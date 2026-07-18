import Foundation
import Testing

@testable import BikeSpeed

/// `TripMonth` is the grouping key for the trip log's month sections. The cases that would silently
/// mis-bucket or mis-order a long log — two days in one month, and the December→January boundary — are the
/// ones worth pinning; they're pure `(year, month)` arithmetic, so no SwiftUI is involved.
@Suite
struct TripMonthTests {

    @Test
    func twoDatesInTheSameMonthShareOneBucket() throws {
        let calendar = utcCalendar()
        let early = TripMonth(containing: try date(2026, 7, 2, in: calendar), calendar: calendar)
        let late = TripMonth(containing: try date(2026, 7, 30, in: calendar), calendar: calendar)

        #expect(early == late, "the 2nd and the 30th of July are the same section")
        #expect(early.year == 2026)
        #expect(early.month == 7)
    }

    /// The trap: comparing month numbers alone puts December (12) after January (1). `TripMonth` orders by
    /// year first, so January 2026 is *later* than December 2025 — which is what a newest-first list needs.
    @Test(.tags(.edgeCase))
    func januaryOfTheNextYearSortsLaterThanTheDecemberBefore() throws {
        let calendar = utcCalendar()
        let december = TripMonth(containing: try date(2025, 12, 31, in: calendar), calendar: calendar)
        let january = TripMonth(containing: try date(2026, 1, 1, in: calendar), calendar: calendar)

        #expect(december < january)
        #expect([december, january].max() == january)
    }

    @Test
    func representativeDateLandsInsideTheMonthItNames() throws {
        let calendar = utcCalendar()
        let month = TripMonth(containing: try date(2026, 3, 17, in: calendar), calendar: calendar)

        let representative = try #require(month.representativeDate(calendar: calendar))
        let components = calendar.dateComponents([.year, .month], from: representative)
        #expect(components.year == 2026)
        #expect(components.month == 3)
    }

    // MARK: - Helpers

    private func date(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func utcCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
}
