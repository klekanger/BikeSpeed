import Charts
import MapKit
import SwiftData
import SwiftUI

/// Full detail for a single saved trip: date, duration, distance, average/max speed, the recorded
/// track on a map, and a height-profile chart plotted against accumulated distance.
struct TripLogDetailView: View {
    /// The row, used only to load the payloads and to delete it. **Never read in `body`** — see `entry`.
    let trip: StoredTrip

    /// The scalars, snapshotted as a value by the caller. The body reads *this*, not `trip`: deleting
    /// invalidates the `StoredTrip` the moment the context saves, while this view is still mounted
    /// through the pop animation, and a body observing the model would re-evaluate against a destroyed
    /// instance and trap. A value can't be destroyed out from under a view.
    let entry: TripLogEntry

    @Environment(TripDataStack.self) private var stack
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingDeleteConfirmation = false
    /// Loaded in `.task`, not read off `trip` in the body: both payloads are external-storage blobs,
    /// and touching either on this actor would fault the file in and decode it on the run loop — the
    /// cost the trip *list* is built never to pay. Nil while loading.
    @State private var loaded: Loaded?

    /// The decoded payloads plus everything the Route section and share sheet derive from them,
    /// computed **once** at load. `Map(initialPosition:)` consults its rect only at first creation,
    /// so recomputing the bounding box in the view builder would redo an O(samples) pass on every
    /// re-render (delete-confirmation toggle, environment change) and throw it away each time.
    private struct Loaded {
        /// Empty for a trip recorded without usable altitude — including everything saved before
        /// elevation shipped.
        let profile: [AltitudeSample]
        /// Empty for a trip with no track — everything saved before route recording shipped.
        let coordinates: [CLLocationCoordinate2D]
        let cameraRect: MKMapRect
        /// The GPX backing the share sheet. `ShareLink` needs a URL that already exists, so it can't
        /// be built lazily at tap time.
        let gpxFileURL: URL?
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Date", value: entry.startDate.formatted(date: .abbreviated, time: .shortened))
                LabeledContent("Duration", value: TripDurationFormatting.formatted(seconds: entry.duration, locale: locale))
                LabeledContent("Distance", value: settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale))
                LabeledContent("Average speed", value: settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.averageSpeed, locale: locale))
                LabeledContent("Max speed", value: settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.maxSpeed, locale: locale))
                // Absent, not zero, on trips recorded without altitude data (including anything saved
                // before v2) — a "0 m" row would claim the ride was flat.
                if let totalAscent = entry.totalAscent {
                    LabeledContent("Total ascent", value: settingsStore.measurementSystem.formattedAltitude(meters: totalAscent, locale: locale))
                }
                if let totalDescent = entry.totalDescent {
                    LabeledContent("Total descent", value: settingsStore.measurementSystem.formattedAltitude(meters: totalDescent, locale: locale))
                }
            }

            if let loaded, loaded.coordinates.count >= 2 {
                Section("Route") {
                    routeMap(for: loaded)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Height profile") {
                if let loaded {
                    if loaded.profile.isEmpty {
                        Text("No altitude data for this trip")
                            .foregroundStyle(.secondary)
                    } else {
                        Chart(loaded.profile, id: \.distance) { sample in
                            AreaMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Altitude", sample.altitude)
                            )
                            .foregroundStyle(.orange.opacity(0.3))
                            LineMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Altitude", sample.altitude)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: 200)
                    }
                } else {
                    // Payloads still decoding. "No altitude data" here would be a lie that corrects
                    // itself a frame later, reading as a flicker.
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .navigationTitle(entry.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            let id = entry.id
            let repository = stack.repository // an actor reference; Sendable
            // Resolved on the main actor so it sees the environment locale: `Date.formatted()` without
            // one follows the *device* language, not the in-app override (see `AppLanguage`).
            let trackName = entry.startDate.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
            )
            let fileName = "BikeSpeed-\(Self.fileNameDateFormatter.string(from: entry.startDate))"

            // Reads only the two blob columns (`propertiesToFetch`), off the main actor, handing back
            // bytes — a `@Model` could not cross this boundary and doesn't need to.
            let payloads = try? await repository.payloads(for: id)
            let altitudeData = payloads?.altitudeData
            let routeData = payloads?.routeData

            // `Task.detached`, and it has to be. With `SWIFT_APPROACHABLE_CONCURRENCY = YES` a plain
            // `nonisolated async` function runs on its *caller's* executor — the main actor here — so
            // "just await it" would put this O(samples) decode and the GPX render back on the run loop,
            // with no compiler complaint and no failing test to catch it.
            let prepared = await Task.detached { () -> Loaded in
                let profile = altitudeData
                    .flatMap { try? TripPayloadCoder.decode([AltitudeSample].self, from: $0) } ?? []

                guard let routeData,
                      let route = try? TripPayloadCoder.decode([RouteSample].self, from: routeData),
                      !route.isEmpty
                else {
                    return Loaded(profile: profile, coordinates: [], cameraRect: .world, gpxFileURL: nil)
                }

                let url = try? GPXExporter.write(
                    route: route,
                    trackName: trackName,
                    fileName: fileName,
                    in: GPXExporter.exportsDirectory(forTrip: id)
                )
                let coordinates = route.map(\.coordinate)
                return Loaded(
                    profile: profile,
                    coordinates: coordinates,
                    cameraRect: Self.boundingRect(of: coordinates),
                    gpxFileURL: url
                )
            }.value

            loaded = prepared
        }
        .toolbar {
            if let gpxFileURL = loaded?.gpxFileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: gpxFileURL) {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    isShowingDeleteConfirmation = true
                } label: {
                    Label("Delete Trip", systemImage: "trash")
                }
            }
        }
        .alert(
            "Delete this trip?",
            isPresented: $isShowingDeleteConfirmation
        ) {
            Button("Delete Trip", role: .destructive) {
                let doomed = trip
                Task { await stack.delete([doomed]) }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    /// The track, framed to itself. Interaction is off deliberately: inside a `Form` a pannable map
    /// swallows the vertical drag meant for the page — the ride is being looked at, not explored, and
    /// the GPX export is there for anyone who wants more.
    private func routeMap(for track: Loaded) -> some View {
        Map(initialPosition: .rect(track.cameraRect), interactionModes: []) {
            MapPolyline(coordinates: track.coordinates)
                .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            if let start = track.coordinates.first {
                Marker("Start", systemImage: "flag", coordinate: start)
                    .tint(.green)
            }
            if let finish = track.coordinates.last {
                Marker("Finish", systemImage: "flag.checkered", coordinate: finish)
                    .tint(.red)
            }
        }
    }

    /// A track's bounding box, padded so the polyline doesn't run along the frame edge. The padding
    /// floors in *metres* because a ride can be perfectly straight — a due-north commute has a
    /// zero-wide box, and a purely proportional inset of zero would leave the camera on a degenerate
    /// rect. `nonisolated` to run inside the `Task.detached` above: an O(samples) pass must not land
    /// on the run loop.
    private nonisolated static func boundingRect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            let point = MKMapPoint(coordinate)
            return rect.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
        }
        guard !rect.isNull else { return MKMapRect.world }

        let latitude = coordinates.first?.latitude ?? 0
        let minimumPadding = MKMapPointsPerMeterAtLatitude(latitude) * 100 // 100 m
        let padding = max(rect.size.width, rect.size.height) * 0.15
        return rect.insetBy(dx: -max(padding, minimumPadding), dy: -max(padding, minimumPadding))
    }

    /// Fixed format on purpose — this names a file, so it must be stable and sortable, not localized.
    /// The *track name* inside the GPX is the human-readable one, and that is localized.
    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

#Preview {
    let container = try! TripModelContainer.inMemory()
    let profile = stride(from: 0.0, through: 12_400.0, by: 200.0).map {
        AltitudeSample(distance: $0, altitude: 100 + 30 * sin($0 / 1000))
    }
    let trip = StoredTrip(
        id: UUID(),
        startDate: Date(),
        duration: 1830,
        distance: 12_400,
        averageSpeed: 6.8,
        maxSpeed: 11.4,
        totalAscent: 312,
        totalDescent: 296,
        altitudeData: try? TripPayloadCoder.encode(profile),
        routeData: nil,
        updatedAt: Date()
    )
    container.mainContext.insert(trip)

    return NavigationStack {
        TripLogDetailView(trip: trip, entry: trip.entry)
            .environment(TripDataStack(container: container))
            .environment(SettingsStore())
            .modelContainer(container)
    }
}
