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

    /// True once the list has been scrolled far enough that returning to the top by hand is a chore —
    /// drives the floating jump-to-top button. A `Bool` (not the raw offset) so the view only re-renders
    /// as it crosses the threshold, not on every scroll frame.
    @State private var isScrolledDown = false

    /// The rows the current filter admits. `TripDateRange.contains` reads only `startDate` (a scalar), so
    /// filtering never faults in a track — the same reason the list rows themselves stay blob-free.
    private var visibleTrips: [StoredTrip] {
        // Hoisted out of the closure: one `Date()` and one `Calendar.current` per pass, not one per trip.
        let now = Date()
        let calendar = Calendar.current
        return trips.filter { dateRange.contains($0.startDate, now: now, calendar: calendar) }
    }

    /// `visibleTrips` grouped into calendar-month sections, newest month first. The rows arrive already
    /// sorted newest-first, and `Dictionary(grouping:)` preserves that order within each bucket, so only
    /// the sections themselves need sorting. `.current` matches `TripLogSummarySection`'s ride calendar —
    /// the month boundary is the rider's region, not the app language.
    private var monthSections: [(month: TripMonth, trips: [StoredTrip])] {
        let calendar = Calendar.current
        let groups = Dictionary(grouping: visibleTrips) { TripMonth(containing: $0.startDate, calendar: calendar) }
        return groups
            .map { (month: $0.key, trips: $0.value) }
            .sorted { $0.month > $1.month }
    }

    var body: some View {
        NavigationStack {
            Group {
                if trips.isEmpty {
                    ContentUnavailableView("No trips logged yet", systemImage: "list.bullet.clipboard")
                } else {
                    ScrollViewReader { proxy in
                        // Filter + group once per body: `sections` drives both the empty check and the
                        // rows, so the O(N) filter runs a single time rather than once for each.
                        let sections = monthSections
                        List {
                            // Its own view, not a `@ViewBuilder` helper: its body reduces the whole log
                            // eight times over (three period totals, four personal bests), so as a view
                            // it's skipped when the query hasn't changed instead of re-running on every
                            // locale change, sheet toggle and delete animation. Fed the *unfiltered* trips
                            // on purpose — the date filter narrows the list, never the lifetime summary.
                            // `.id` is the jump-to-top anchor.
                            TripLogSummarySection(trips: trips)
                                .id(Self.topAnchor)

                            if sections.isEmpty {
                                // The log isn't empty, this window is. Keep the summary and the filter
                                // reachable so the rider can widen the range rather than think trips vanished.
                                ContentUnavailableView(
                                    "No trips in this period",
                                    systemImage: "calendar",
                                    description: Text("Try a wider date range.")
                                )
                                .listRowSeparator(.hidden)
                            } else {
                                // One Section per month. Delete offsets index into *that* section's rows,
                                // so `section.trips[$0]` is the trip to remove, not `visibleTrips[$0]`.
                                ForEach(sections, id: \.month) { section in
                                    Section {
                                        ForEach(section.trips) { trip in
                                            NavigationLink(value: trip) {
                                                row(for: trip.entry)
                                            }
                                        }
                                        .onDelete { offsets in
                                            let doomed = offsets.map { section.trips[$0] }
                                            Task { await stack.delete(doomed) }
                                        }
                                    } header: {
                                        Text(monthTitle(section.month))
                                    }
                                }
                            }
                        }
                        // A `Bool` transform, so `action` fires only as the flag flips, not per frame.
                        .onScrollGeometryChange(for: Bool.self) { geometry in
                            geometry.contentOffset.y > Self.jumpToTopThreshold
                        } action: { _, scrolledDown in
                            withAnimation(.easeInOut) { isScrolledDown = scrolledDown }
                        }
                        .overlay(alignment: .bottomTrailing) {
                            if isScrolledDown {
                                jumpToTopButton(proxy: proxy)
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
                    Text(label(for: range)).tag(range)
                }
            }
        } label: {
            Image(systemName: dateRange == .all
                ? "line.3.horizontal.decrease.circle"
                : "line.3.horizontal.decrease.circle.fill")
        }
        .accessibilityLabel(Text("Filter trips"))
    }

    /// The menu label for each range. Lives in the view, not on `TripDateRange`, so the model stays a
    /// pure SwiftUI-free value type — the same layering `MeasurementSystem`'s picker and this diff's own
    /// `TripMonth` already follow.
    private func label(for range: TripDateRange) -> LocalizedStringKey {
        switch range {
        case .all: "All"
        case .last7Days: "Last 7 days"
        case .last30Days: "Last 30 days"
        case .thisYear: "This year"
        }
    }

    /// Identifies the summary row so the jump-to-top button can scroll back to it.
    private static let topAnchor = "top"

    /// Roughly a screen of scrolling — past this the summary is well out of view and hand-scrolling back
    /// is the chore the button exists to skip.
    private static let jumpToTopThreshold: CGFloat = 400

    /// Localized "MMMM yyyy" header (e.g. "July 2026", "juli 2026"). Formatted against the in-app language's
    /// `locale`, not the device's, so it follows the Language override like the rest of the log.
    private func monthTitle(_ month: TripMonth) -> String {
        guard let date = month.representativeDate(calendar: .current) else { return "" }
        return date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    /// Floating "back to top" affordance, shown only once scrolled down. Bottom-trailing and circular so it
    /// sits over the list without stealing a row, the standard iOS long-list pattern.
    private func jumpToTopButton(proxy: ScrollViewProxy) -> some View {
        Button {
            withAnimation { proxy.scrollTo(Self.topAnchor, anchor: .top) }
        } label: {
            Image(systemName: "chevron.up")
                .font(.headline)
                .padding(14)
                .background(.thinMaterial, in: Circle())
                .overlay(Circle().stroke(.separator))
        }
        .tint(.orange)
        .padding()
        .transition(.scale.combined(with: .opacity))
        .accessibilityLabel(Text("Scroll to top"))
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
