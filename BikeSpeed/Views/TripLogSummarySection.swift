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

    /// Which pane is showing. Shared by the segmented control and the paged `TabView` below, so a tap
    /// and a swipe drive the same selection.
    @State private var pane = Pane.totals

    private enum Pane: Hashable { case totals, bests }

    /// **`Calendar.current`, not the in-app language's calendar.** Where the week starts is a fact
    /// about where the rider lives, not which language they read the app in — a Norwegian running
    /// BikeSpeed in English still rides a week that begins on Monday. The device region settles it.
    private var rideCalendar: Calendar { .current }

    var body: some View {
        // Scalars only — `StoredTrip.entry` touches neither payload blob, so summarising the log never
        // faults in a single track. That's what earns the blob design; don't reach for a payload here.
        let summary = TripLogSummary(entries: trips.map(\.entry), calendar: rideCalendar)

        // The segmented control switches the pane in place — the point of the tabs is to spend the
        // vertical room of one pane, not both stacked. It drives a *paged* `TabView` rather than the
        // default `Tab` bar, whose floating Liquid Glass bar would sit on top of these rows; page style
        // gives the swipe with no bar. The `TabView` has no intrinsic height, so it's pinned to one that
        // fits the taller (Totals) pane; the shorter pane top-aligns and leaves the slack empty.
        VStack(spacing: 12) {
            Picker("", selection: $pane) {
                Text("Totals").tag(Pane.totals)
                Text("Personal bests").tag(Pane.bests)
            }
            .pickerStyle(.segmented)

            TabView(selection: $pane) {
                totalsPane(summary).tag(Pane.totals)
                bestsPane(summary).tag(Pane.bests)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 176)
        }
        .padding(.vertical, 4)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private func totalsPane(_ summary: TripLogSummary) -> some View {
        rows {
            statRow("Rides", "bicycle", summary.allTime.rideCount.formatted(.number.locale(locale)))
            statRow("Total distance", "point.topleft.down.curvedto.point.bottomright.up", distance(summary.allTime.distance))
            statRow("Total time", "clock", TripDurationFormatting.formatted(seconds: summary.allTime.duration, locale: locale))
            // Hidden, not "0 m", when no ride ever recorded a climb — every trip saved before elevation
            // shipped has no ascent figure at all, and a zero here would call them flat.
            if summary.allTime.ascent > 0 {
                statRow("Total ascent", "mountain.2.fill", altitude(summary.allTime.ascent))
            }
            statRow("This week", "calendar", distance(summary.thisWeek.distance))
            statRow("This month", "calendar", distance(summary.thisMonth.distance))
        }
    }

    @ViewBuilder
    private func bestsPane(_ summary: TripLogSummary) -> some View {
        rows {
            if let longest = summary.personalBests.longestRide {
                statRow("Longest ride", "point.topleft.down.curvedto.point.bottomright.up", distance(longest.distance))
            }
            if let fastest = summary.personalBests.fastestAverage {
                statRow("Fastest average", "speedometer", speed(fastest.averageSpeed))
            }
            if let quickest = summary.personalBests.highestMaxSpeed {
                statRow("Top speed", "gauge.with.dots.needle.100percent", speed(quickest.maxSpeed))
            }
            // Absent, not zero, when nothing in the log ever recorded altitude: no climbing record to
            // hold, rather than a 0 m one.
            if let ascent = summary.personalBests.biggestClimb?.totalAscent {
                statRow("Biggest climb", "mountain.2.fill", altitude(ascent))
            }
        }
    }

    /// A summary row: an orange leading icon (matching the home screen's `StatCell` icons, so the log
    /// carries the same accent) beside the name, with the value trailing.
    private func statRow(_ title: LocalizedStringKey, _ systemImage: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label {
                Text(title)
            } icon: {
                // Fixed-width icon column so titles line up regardless of glyph width — `bicycle` and
                // `mountain.2.fill` are far wider than `clock`, and without this the labels stagger.
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .frame(width: 24)
            }
        }
    }

    /// One pane's stat rows, stacked (a page isn't a `List`, so nothing lays them out otherwise) and
    /// pinned to the top of the fixed-height `TabView`.
    @ViewBuilder
    private func rows(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 8) {
            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
