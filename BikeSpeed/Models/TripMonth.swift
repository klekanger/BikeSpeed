import Foundation

/// The calendar month a trip belongs to — the bucket `TripLogListView` groups its rows under, so a long
/// log reads as "July 2026 / June 2026 / …" section cards rather than one unbroken scroll.
///
/// A `(year, month)` pair, not a `Date`: two rides on different days of the same month must land in the
/// *same* bucket, and comparing whole months is what orders the sections. Built from an injected
/// `Calendar` (region-based, like `TripLogSummarySection`'s `rideCalendar`) so the month boundary is the
/// rider's, and pure/`Comparable` so `TripMonthTests` can pin the year-boundary ordering without SwiftUI.
struct TripMonth: Hashable, Comparable {
    let year: Int
    let month: Int

    init(containing date: Date, calendar: Calendar) {
        let components = calendar.dateComponents([.year, .month], from: date)
        year = components.year ?? 0
        month = components.month ?? 0
    }

    /// Chronological: an earlier month is "less than" a later one, so December 2025 precedes January 2026
    /// rather than sorting after it on the month number alone. The list sorts sections in reverse for
    /// newest-first.
    static func < (lhs: TripMonth, rhs: TripMonth) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    /// A stand-in `Date` (the 1st, noon) for formatting a localized "MMMM yyyy" header — the view has only
    /// the year/month, but `Date.FormatStyle` needs a date to localize the month name against.
    func representativeDate(calendar: Calendar) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12))
    }
}
