import CoreLocation
import SwiftUI

/// Sheet-presented list of saved trips, newest first, under the rider's lifetime totals and personal bests
/// (see `TripLogSummary`). Each row shows only a few details (date, distance, duration); tapping a row
/// pushes to `TripLogDetailView` for the full breakdown.
struct TripLogListView: View {
    let store: TripLogStore

    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            Group {
                if store.entries.isEmpty {
                    ContentUnavailableView("No trips logged yet", systemImage: "list.bullet.clipboard")
                } else {
                    List {
                        summarySections(for: TripLogSummary(entries: store.entries, calendar: rideCalendar))

                        Section {
                            ForEach(store.entries) { entry in
                                NavigationLink(value: entry) {
                                    row(for: entry)
                                }
                            }
                            .onDelete { offsets in
                                store.delete(at: offsets)
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: TripLogEntry.self) { entry in
                TripLogDetailView(entry: entry)
            }
            .navigationTitle(settingsStore.appLanguage.localizedString(forKey: "Trip Log"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// **`Calendar.current`, not the in-app language's calendar.** Where the week starts is a fact about
    /// where the rider lives, not about which language they read the app in: a Norwegian who runs BikeSpeed
    /// in English still rides through a week that begins on Monday. The device's region settles it.
    private var rideCalendar: Calendar { .current }

    @ViewBuilder
    private func summarySections(for summary: TripLogSummary) -> some View {
        Section("Totals") {
            LabeledContent("Rides", value: summary.allTime.rideCount.formatted(.number.locale(locale)))
            LabeledContent("Total distance", value: distance(summary.allTime.distance))
            LabeledContent("Total time", value: TripDurationFormatting.formatted(seconds: summary.allTime.duration, locale: locale))
            // Hidden rather than shown as "0 m" when no ride ever recorded a climb — every trip saved before
            // elevation shipped has no ascent figure at all, and a zero here would call them flat.
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
            // Absent, not zero, when nothing in the log ever recorded altitude: there is no climbing record
            // to hold, rather than a 0 m one.
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

    private func row(for entry: TripLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                Label(settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale), systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                Label(TripDurationFormatting.formatted(seconds: entry.duration, locale: locale), systemImage: "clock")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TripLogListView(store: TripLogStore())
        .environment(SettingsStore())
}
