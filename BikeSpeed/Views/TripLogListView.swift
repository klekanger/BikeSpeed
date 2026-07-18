import CoreLocation
import SwiftData
import SwiftUI

/// Sheet-presented list of saved trips, newest first, under the rider's lifetime totals and personal
/// bests (see `TripLogSummary`). Each row shows a few details (date, distance, duration); tapping
/// pushes to `TripLogDetailView`.
struct TripLogListView: View {
    /// Live, database-sorted, and never loads a row it doesn't draw. The old store re-published a whole
    /// in-memory array on every change; this re-runs only when a row actually changes.
    ///
    /// The `deletedAt` filter is a no-op today — nothing writes that field — but is here so that when
    /// `TripDataStack.delete` starts soft-deleting for sync, this view needn't change at all.
    @Query(
        filter: #Predicate<StoredTrip> { $0.deletedAt == nil },
        sort: \StoredTrip.startDate,
        order: .reverse
    )
    private var trips: [StoredTrip]

    @Environment(TripDataStack.self) private var stack
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale

    /// Narrows the *list* to a date window. The summary above stays lifetime regardless — see
    /// `TripDateRange`. Not persisted: it resets to `.all` each time the log is opened.
    @State private var dateRange = TripDateRange.all

    /// The rows the current filter admits. `TripDateRange.contains` reads only `startDate` (a scalar), so
    /// filtering never faults in a track — the same reason the list rows themselves stay blob-free.
    private var visibleTrips: [StoredTrip] {
        trips.filter { dateRange.contains($0.startDate, now: Date(), calendar: .current) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView("No trips logged yet", systemImage: "list.bullet.clipboard")
                } else {
                    List {
                        // Its own view, not a `@ViewBuilder` helper: its body reduces the whole log
                        // eight times over (three period totals, four personal bests), so as a view
                        // it's skipped when the query hasn't changed instead of re-running on every
                        // locale change, sheet toggle and delete animation. Fed the *unfiltered* trips
                        // on purpose — the date filter narrows the list, never the lifetime summary.
                        TripLogSummarySection(trips: trips)

                        if visibleTrips.isEmpty {
                            // The log isn't empty, this window is. Keep the summary and the filter
                            // reachable so the rider can widen the range rather than think trips vanished.
                            ContentUnavailableView(
                                "No trips in this period",
                                systemImage: "calendar",
                                description: Text("Try a wider date range.")
                            )
                            .listRowSeparator(.hidden)
                        } else {
                            Section {
                                ForEach(visibleTrips) { trip in
                                    NavigationLink(value: trip) {
                                        row(for: trip.entry)
                                    }
                                }
                                .onDelete { offsets in
                                    let doomed = offsets.map { visibleTrips[$0] }
                                    Task { await stack.delete(doomed) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: StoredTrip.self) { trip in
                // Value snapshot taken *here*, while the row is still alive. The detail view must not
                // read the model in its body — deleting from there would destroy it mid-pop.
                TripLogDetailView(trip: trip, entry: trip.entry)
            }
            .navigationTitle(settingsStore.appLanguage.localizedString(forKey: "Trip Log"))
            .toolbar {
                if !trips.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        filterMenu
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// A `Picker` inside a `Menu` — iOS renders it as a checklist with the active range ticked. The icon
    /// gains its `.fill` variant while a filter is active, so "a filter is on" reads at a glance without
    /// opening the menu.
    private var filterMenu: some View {
        Menu {
            Picker("Filter", selection: $dateRange) {
                ForEach(TripDateRange.allCases, id: \.self) { range in
                    Text(range.titleKey).tag(range)
                }
            }
        } label: {
            Image(systemName: dateRange == .all
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(Text("Filter trips"))
    }

    private func row(for entry: TripLogEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.startDate.formatted(date: .abbreviated, time: .shortened))
                .font(.headline)
            HStack(spacing: 12) {
                // Icon orange (echoing the home screen's stat icons), text secondary — a touch of the
                // app's accent in the otherwise all-grey list.
                Label {
                    Text(settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale))
                } icon: {
                    Image(systemName: "point.topleft.down.curvedto.point.bottomright.up").foregroundStyle(.orange)
                }
                Label {
                    Text(TripDurationFormatting.formatted(seconds: entry.duration, locale: locale))
                } icon: {
                    Image(systemName: "clock").foregroundStyle(.orange)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    let container = try! TripModelContainer.inMemory()
    TripLogListView()
        .environment(TripDataStack(container: container))
        .environment(SettingsStore())
        .modelContainer(container)
}
