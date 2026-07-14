import Charts
import MapKit
import SwiftUI

/// Full detail for a single saved trip: date, duration, distance, average/max speed, the recorded
/// track on a map, and a height-profile chart plotted against accumulated distance.
struct TripLogDetailView: View {
    let entry: TripLogEntry

    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var tripLogStore: TripLogStore
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss

    @State private var isShowingDeleteConfirmation = false
    /// Loaded in `.task` rather than at init: the track lives in its own file (see `TripLogStore`) and
    /// reading it is work the trip *list* must never pay for. Nil while loading and for any trip that
    /// has no track — every trip saved before this feature shipped.
    @State private var track: LoadedTrack?

    /// Everything the Route section and the share sheet need, derived **once** when the track loads.
    /// `Map(initialPosition:)` consults its rect exactly once, at first creation, so recomputing the
    /// bounding box inside the view builder would redo an O(samples) pass on every re-render — every
    /// delete-confirmation toggle, every environment change — and throw the answer away each time.
    private struct LoadedTrack {
        let coordinates: [CLLocationCoordinate2D]
        let cameraRect: MKMapRect
        /// The GPX backing the share sheet. `ShareLink` needs a URL that already exists, so it cannot be
        /// built lazily at tap time.
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
                // Absent, not zero, on trips recorded without altitude data (including anything
                // saved before v2) — a row reading "0 m" would claim the ride was flat.
                if let totalAscent = entry.totalAscent {
                    LabeledContent("Total ascent", value: settingsStore.measurementSystem.formattedAltitude(meters: totalAscent, locale: locale))
                }
                if let totalDescent = entry.totalDescent {
                    LabeledContent("Total descent", value: settingsStore.measurementSystem.formattedAltitude(meters: totalDescent, locale: locale))
                }
            }

            if let track, track.coordinates.count >= 2 {
                Section("Route") {
                    routeMap(for: track)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
            }

            Section("Height profile") {
                if entry.altitudeProfile.isEmpty {
                    Text("No altitude data for this trip")
                        .foregroundStyle(.secondary)
                } else {
                    Chart(entry.altitudeProfile, id: \.distance) { sample in
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
            }
        }
        .navigationTitle(entry.startDate.formatted(date: .abbreviated, time: .omitted))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Read through `routes` rather than `tripLogStore.route(for:)`: the store is `@MainActor`, so
            // going through it would decode the track — and then render its GPX — on the run loop, stalling
            // the first frame of a long trip. Both are O(samples), and a long ride is thousands of them.
            let routes = tripLogStore.routes
            let id = entry.id
            // Resolved here, on the main actor, so it can see the environment locale: `Date.formatted()`
            // without one follows the *device* language, not the in-app override (see `AppLanguage`).
            let trackName = entry.startDate.formatted(
                Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)
            )
            let fileName = "BikeSpeed-\(Self.fileNameDateFormatter.string(from: entry.startDate))"

            let prepared: ([RouteSample], URL?)? = await Task.detached {
                guard let route = routes.load(id), !route.isEmpty else { return nil }
                let url = try? GPXExporter.write(
                    route: route,
                    trackName: trackName,
                    fileName: fileName,
                    in: GPXExporter.exportsDirectory(forTrip: id)
                )
                return (route, url)
            }.value

            guard let (route, gpxFileURL) = prepared else { return }
            let coordinates = route.map(\.coordinate)
            track = LoadedTrack(
                coordinates: coordinates,
                cameraRect: Self.boundingRect(of: coordinates),
                gpxFileURL: gpxFileURL
            )
        }
        .toolbar {
            if let gpxFileURL = track?.gpxFileURL {
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
                tripLogStore.delete(id: entry.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    /// The track, framed to itself. Interaction is off deliberately: this map lives inside a `Form`, and
    /// a pannable map there swallows the vertical drag the user meant for the page — the ride is being
    /// looked at, not explored, and the GPX export is there for anyone who wants to do more with it.
    private func routeMap(for track: LoadedTrack) -> some View {
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

    /// The camera rect for a track: its bounding box, padded so the polyline doesn't run along the edge
    /// of the frame. The padding has a floor in *metres* because a ride can be perfectly straight — a due
    /// north commute has a bounding box zero wide, and a purely proportional inset of zero would leave the
    /// camera on a degenerate rect.
    private static func boundingRect(of coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
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

    /// Fixed format on purpose — this names a file, so it has to be stable and sortable rather than
    /// localized. The *track name* inside the GPX is the one a human reads, and that one is localized.
    private static let fileNameDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmm"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        TripLogDetailView(entry: TripLogEntry(
            id: UUID(),
            startDate: Date(),
            duration: 1830,
            distance: 12_400,
            averageSpeed: 6.8,
            maxSpeed: 11.4,
            altitudeProfile: stride(from: 0.0, through: 12_400.0, by: 200.0).map {
                AltitudeSample(distance: $0, altitude: 100 + 30 * sin($0 / 1000))
            },
            totalAscent: 312,
            totalDescent: 296
        ))
        .environmentObject(SettingsStore())
        .environmentObject(TripLogStore())
    }
}
