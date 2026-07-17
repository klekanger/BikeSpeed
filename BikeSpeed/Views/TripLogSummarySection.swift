import CoreLocation
import SwiftUI

/// The rider's lifetime totals and personal bests, above the trip list.
///
/// **Its own `View`, not a `@ViewBuilder` function on `TripLogListView`.** Building it reduces the
/// entire log eight times over (three period totals plus four personal bests, each a full pass); in
/// the parent's `body` that would re-run on every locale change, settings write, and delete-animation
/// frame. As a view with an `Equatable` input, SwiftUI skips it whenever the query hasn't changed.
struct TripLogSummarySection: View {
    let trips: [StoredTrip]

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.locale) private var locale

    /// **`Calendar.current`, not the in-app language's calendar.** Where the week starts is a fact
    /// about where the rider lives, not which language they read the app in — a Norwegian running
    /// BikeSpeed in English still rides a week that begins on Monday. The device region settles it.
    private var rideCalendar: Calendar { .current }

    var body: some View {
        // Scalars only — `StoredTrip.entry` touches neither payload blob, so summarising the log never
        // faults in a single track. That's what earns the blob design; don't reach for a payload here.
        let summary = TripLogSummary(entries: trips.map(\.entry), calendar: rideCalendar)

        Section("Totals") {
            LabeledContent("Rides", value: summary.allTime.rideCount.formatted(.number.locale(locale)))
            LabeledContent("Total distance", value: distance(summary.allTime.distance))
            LabeledContent("Total time", value: TripDurationFormatting.formatted(seconds: summary.allTime.duration, locale: locale))
            // Hidden, not "0 m", when no ride ever recorded a climb — every trip saved before elevation
            // shipped has no ascent figure at all, and a zero here would call them flat.
            if summary.allTime.ascent > 0 {
                LabeledContent("Total ascent", value: altitude(summary.allTime.ascent))
            }
            LabeledContent("This week", value: distance(summary.thisWeek.distance))
            LabeledContent("This month", value: distance(summary.thisMonth.distance))
        }

        Section("Personal bests") {
            if let longest = summary.personalBests.longestRide {
                LabeledContent("Longest ride", value: distance(longest.distance))
            }
            if let fastest = summary.personalBests.fastestAverage {
                LabeledContent("Fastest average", value: speed(fastest.averageSpeed))
            }
            if let quickest = summary.personalBests.highestMaxSpeed {
                LabeledContent("Top speed", value: speed(quickest.maxSpeed))
            }
            // Absent, not zero, when nothing in the log ever recorded altitude: no climbing record to
            // hold, rather than a 0 m one.
            if let ascent = summary.personalBests.biggestClimb?.totalAscent {
                LabeledContent("Biggest climb", value: altitude(ascent))
            }
        }
    }

    private func distance(_ meters: CLLocationDistance) -> String {
        settingsStore.measurementSystem.formattedDistance(meters: meters, locale: locale)
    }

    private func altitude(_ meters: CLLocationDistance) -> String {
        settingsStore.measurementSystem.formattedAltitude(meters: meters, locale: locale)
    }

    private func speed(_ metersPerSecond: CLLocationSpeed) -> String {
        settingsStore.measurementSystem.formattedSpeed(metersPerSecond: metersPerSecond, locale: locale)
    }
}
