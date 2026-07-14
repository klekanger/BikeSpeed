import CoreLocation
import SwiftData
import SwiftUI

/// Sheet-presented list of saved trips, newest first, under the rider's lifetime totals and personal bests
/// (see `TripLogSummary`). Each row shows only a few details (date, distance, duration); tapping a row
/// pushes to `TripLogDetailView` for the full breakdown.
struct TripLogListView: View {
    /// Live, sorted by the database, and it never loads a row it does not draw. The old store re-published
    /// an entire in-memory array on every change; this re-runs when a row actually changes.
    ///
    /// The `deletedAt` filter is a no-op today — nothing writes that field. It is here so that the day
    /// `TripDataStack.delete` starts soft-deleting for sync, this view does not have to change at all.
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

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView("No trips logged yet", systemImage: "list.bullet.clipboard")
                } else {
                    List {
                        // Its own view, not a `@ViewBuilder` helper here, so its body — which reduces the
                        // whole log eight times over (three period totals, four personal bests) — is skipped
                        // whenever the query hasn't actually changed, instead of re-running on every locale
                        // change, sheet toggle and delete animation.
                        TripLogSummarySection(trips: trips)

                        Section {
                            ForEach(trips) { trip in
                                NavigationLink(value: trip) {
                                    row(for: trip.entry)
                                }
                            }
                            .onDelete { offsets in
                                let doomed = offsets.map { trips[$0] }
                                Task { await stack.delete(doomed) }
                            }
                        }
                    }
                }
            }
            .navigationDestination(for: StoredTrip.self) { trip in
                // The value snapshot is taken *here*, while the row is still alive. The detail view must not
                // read the model in its body — deleting from there would destroy it mid-pop.
                TripLogDetailView(trip: trip, entry: trip.entry)
            }
            .navigationTitle(settingsStore.appLanguage.localizedString(forKey: "Trip Log"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
    let container = try! TripModelContainer.inMemory()
    TripLogListView()
        .environment(TripDataStack(container: container))
        .environment(SettingsStore())
        .modelContainer(container)
}
