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
    /// Drives the full-screen interactive map cover. The embedded preview stays non-interactive (see
    /// `routeMap`); tapping it opens *this* instead, where panning/zooming has the whole screen and
    /// can't fight the Form's scroll.
    @State private var isShowingFullScreenMap = false
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
        /// Derived from the track (not stored), so it's present for any trip with a route — the live
        /// per-point speed on new trips, timestamp-derived on older ones. Empty only without a track.
        let speedProfile: [SpeedSample]
        /// Empty for a trip with no track — everything saved before route recording shipped.
        let coordinates: [CLLocationCoordinate2D]
        let cameraRect: MKMapRect
        /// The GPX backing the share sheet. `ShareLink` needs a URL that already exists, so it can't
        /// be built lazily at tap time.
        let gpxFileURL: URL?
        /// Title shown at the top of the share sheet. iOS hides the file's known `.gpx` extension from
        /// the sheet's title, so without this the header reads as a bare date; this spells out the
        /// export type. Built with the in-app locale alongside `trackName`, not derived in `body`.
        let shareTitle: String
    }

    var body: some View {
        Form {
            Section {
                infoRow("Date", "calendar", entry.startDate.formatted(date: .abbreviated, time: .shortened))
                infoRow("Duration", "clock", TripDurationFormatting.formatted(seconds: entry.duration, locale: locale))
                infoRow("Distance", "point.topleft.down.curvedto.point.bottomright.up", settingsStore.measurementSystem.formattedDistance(meters: entry.distance, locale: locale))
                infoRow("Average speed", "speedometer", settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.averageSpeed, locale: locale))
                infoRow("Max speed", "gauge.with.dots.needle.100percent", settingsStore.measurementSystem.formattedSpeed(metersPerSecond: entry.maxSpeed, locale: locale))
                // Absent, not zero, on trips recorded without altitude data (including anything saved
                // before v2) — a "0 m" row would claim the ride was flat.
                if let totalAscent = entry.totalAscent {
                    infoRow("Total ascent", "mountain.2.fill", settingsStore.measurementSystem.formattedAltitude(meters: totalAscent, locale: locale))
                }
                if let totalDescent = entry.totalDescent {
                    infoRow("Total descent", "arrow.down.right", settingsStore.measurementSystem.formattedAltitude(meters: totalDescent, locale: locale))
                }
            }

            if let loaded, loaded.coordinates.count >= 2 {
                Section("Route") {
                    routeMap(for: loaded)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                        // The preview's own map takes no gestures (`interactionModes: []`), so this tap
                        // reaches the row; `contentShape` makes the whole frame — not just the drawn
                        // pixels — the hit target.
                        .contentShape(Rectangle())
                        .onTapGesture { isShowingFullScreenMap = true }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel("Open full-screen map")
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

            Section("Speed profile") {
                if let loaded {
                    if loaded.speedProfile.isEmpty {
                        Text("No speed data for this trip")
                            .foregroundStyle(.secondary)
                    } else {
                        // Y in the user's unit (km/h or mph): the model stores m/s, the view converts —
                        // same split as every other speed on screen. X is distance, matching the height
                        // profile above so the two charts read against a shared axis.
                        Chart(loaded.speedProfile, id: \.distance) { sample in
                            let speed = settingsStore.measurementSystem.speedValue(metersPerSecond: sample.speed)
                            AreaMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Speed", speed)
                            )
                            .foregroundStyle(.orange.opacity(0.3))
                            LineMark(
                                x: .value("Distance", sample.distance),
                                y: .value("Speed", speed)
                            )
                            .foregroundStyle(.orange)
                        }
                        .frame(height: 200)
                    }
                } else {
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
            // Resolved via AppLanguage so it honours the in-app language override; `trackName` (the
            // localized date) rides along after it.
            let shareTitle = "\(settingsStore.appLanguage.localizedString(forKey: "GPX route")) – \(trackName)"

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
                    return Loaded(profile: profile, speedProfile: [], coordinates: [], cameraRect: .world, gpxFileURL: nil, shareTitle: shareTitle)
                }

                let speedProfile = SpeedProfile.build(from: route)

                let url = try? GPXExporter.write(
                    route: route,
                    trackName: trackName,
                    fileName: fileName,
                    in: GPXExporter.exportsDirectory(forTrip: id)
                )
                let coordinates = route.map(\.coordinate)
                return Loaded(
                    profile: profile,
                    speedProfile: speedProfile,
                    coordinates: coordinates,
                    cameraRect: Self.boundingRect(of: coordinates),
                    gpxFileURL: url,
                    shareTitle: shareTitle
                )
            }.value

            loaded = prepared
        }
        .toolbar {
            if let loaded, let gpxFileURL = loaded.gpxFileURL {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: gpxFileURL, preview: SharePreview(loaded.shareTitle)) {
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
        .fullScreenCover(isPresented: $isShowingFullScreenMap) {
            if let loaded {
                RouteMapFullScreenView(coordinates: loaded.coordinates, cameraRect: loaded.cameraRect)
            }
        }
    }

    /// A detail row: an orange leading icon (matching the trip-log summary and the home screen's stat
    /// icons, so the accent carries across screens) beside the name, value trailing. The icon sits in a
    /// fixed-width column so titles align across glyphs of different widths.
    private func infoRow(_ title: LocalizedStringKey, _ systemImage: String, _ value: String) -> some View {
        LabeledContent {
            Text(value)
        } label: {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.orange)
                    .frame(width: 24)
            }
        }
    }

    /// The track, framed to itself. Interaction is off deliberately: inside a `Form` a pannable map
    /// swallows the vertical drag meant for the page. Tapping the row instead opens the full-screen
    /// interactive map (`RouteMapFullScreenView`), where exploring the ride doesn't fight the scroll.
    /// The corner glyph advertises that the static preview is a doorway to it.
    private func routeMap(for track: Loaded) -> some View {
        Map(initialPosition: .rect(track.cameraRect), interactionModes: []) {
            routeMapContent(for: track.coordinates)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.primary)
                .padding(6)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                .padding(8)
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

/// The orange polyline plus start/finish flags — the single source of truth for how a track draws,
/// shared by the Form's static preview and the full-screen interactive map so the two never drift.
@MapContentBuilder
private func routeMapContent(for coordinates: [CLLocationCoordinate2D]) -> some MapContent {
    MapPolyline(coordinates: coordinates)
        .stroke(.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    if let start = coordinates.first {
        Marker("Start", systemImage: "flag", coordinate: start)
            .tint(.green)
    }
    if let finish = coordinates.last {
        Marker("Finish", systemImage: "flag.checkered", coordinate: finish)
            .tint(.red)
    }
}

/// The recorded track on a fully interactive, full-screen map — the counterpart to the Form's static
/// preview. It gets its own cover precisely because zoom/pan needs room the embedded map can't give it
/// without hijacking the detail form's scroll. Same `cameraRect` as the preview, so it opens framed to
/// the ride and the user zooms out from there. MapKit rendering is free on Apple platforms, so this
/// costs nothing beyond the tiles the preview already draws.
private struct RouteMapFullScreenView: View {
    let coordinates: [CLLocationCoordinate2D]
    let cameraRect: MKMapRect
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Map(initialPosition: .rect(cameraRect)) {
                routeMapContent(for: coordinates)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    let container = try! TripModelContainer.inMemory()
    let profile = stride(from: 0.0, through: 12_400.0, by: 200.0).map {
        AltitudeSample(distance: $0, altitude: 100 + 30 * sin($0 / 1000))
    }
    let start = CLLocationCoordinate2D(latitude: 59.9139, longitude: 10.7522)
    let previewBase = Date()
    let route = (0..<200).map { index in
        RouteSample(
            latitude: start.latitude + Double(index) * 10 / 111_320,
            longitude: start.longitude,
            altitude: 100,
            timestamp: previewBase.addingTimeInterval(Double(index)),
            speed: 6.8 + 2.5 * sin(Double(index) / 12),
            distance: Double(index) * 10
        )
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
        routeData: try? TripPayloadCoder.encode(route),
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
