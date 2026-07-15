import Foundation

/// Renders a recorded track as GPX 1.1 — the interchange format every other cycling app reads, so a
/// trip saved here can still be pushed to Strava or Komoot. Writing it is the whole feature; there is
/// no import, no sync, and nothing to maintain against someone else's API.
///
/// `nonisolated` because the project's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin
/// these to the main actor, and rendering a few thousand `<trkpt>` elements into a string and writing
/// them to disk is exactly the work that must not happen on the run loop. Nothing here is shared state,
/// so there is nothing to isolate.
nonisolated enum GPXExporter {

    /// Coordinates are formatted through `String(format:)`, which is **not** locale-aware — it always
    /// emits a `.` decimal separator. That is load-bearing, not incidental: a `NumberFormatter` on a
    /// comma-decimal locale (nb_NO, the app's other language) would write `lat="59,9139000"`, which is
    /// not valid GPX, and every export would be silently rejected by every app the rider tried to open
    /// it in. `GPXExporterTests` pins the separator for exactly this reason — don't swap this for a
    /// formatter.
    private static func decimal(_ value: Double, places: Int) -> String {
        String(format: "%.\(places)f", value)
    }

    /// Builds the GPX document. An empty route yields a valid file with an empty track segment rather
    /// than nothing at all — the caller may still want to share it, and a malformed file is worse than
    /// an empty one.
    static func makeGPX(route: [RouteSample], trackName: String) -> String {
        let timestamps = ISO8601DateFormatter()
        timestamps.formatOptions = [.withInternetDateTime]
        timestamps.timeZone = TimeZone(secondsFromGMT: 0)

        let points = route.map { sample -> String in
            var point = """
                  <trkpt lat="\(decimal(sample.latitude, places: 7))" lon="\(decimal(sample.longitude, places: 7))">
            """
            // Omitted rather than defaulted: a point recorded without usable vertical accuracy has no
            // height, and `<ele>0</ele>` would assert the rider was at sea level.
            if let altitude = sample.altitude {
                point += "\n        <ele>\(decimal(altitude, places: 1))</ele>"
            }
            point += "\n        <time>\(timestamps.string(from: sample.timestamp))</time>"
            point += "\n      </trkpt>"
            return point
        }

        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="BikeSpeed" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(escaped(trackName))</name>
            <trkseg>
        \(points.joined(separator: "\n"))
            </trkseg>
          </trk>
        </gpx>
        """
    }

    /// Exports get a directory of their own under `tmp/`, so `clearExports()` can drop the lot without
    /// touching anything else the system keeps there.
    static var exportsDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("GPXExports", isDirectory: true)
    }

    /// One directory per trip. The rider sees the *file* name in the share sheet, so it stays a clean,
    /// sortable date — but a date to the minute is not unique (a trip need only be 5 s and 10 m to be
    /// saveable, so two can start within the same minute), and two trips exporting to one path would
    /// leave a share sheet handing over the wrong ride's track. The trip's id disambiguates the
    /// directory instead of uglifying the file name.
    static func exportsDirectory(forTrip id: UUID) -> URL {
        exportsDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Call once at launch. iOS reaps `tmp/` only under storage pressure, never while the app runs, so
    /// without this every visit to a trip's detail view would leave another `.gpx` behind for the life of
    /// the install. Launch is the safe moment: no share sheet can still be reading a file.
    static func clearExports() {
        try? FileManager.default.removeItem(at: exportsDirectory)
    }

    /// Writes the document somewhere `ShareLink` can hand it to another app.
    static func write(
        route: [RouteSample],
        trackName: String,
        fileName: String,
        in directory: URL = exportsDirectory
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(sanitized(fileName)).gpx")
        try Data(makeGPX(route: route, trackName: trackName).utf8).write(to: url, options: .atomic)
        return url
    }

    /// The track name is a date the app formatted itself, so this is belt-and-braces — but it is user
    /// data flowing into markup, and the cost of being wrong is a file no importer will parse.
    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// A localized date can carry a `/` (en) or a `.` (nb), which would either break the path or leave
    /// the file with a second extension.
    private static func sanitized(_ fileName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let cleaned = fileName.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
            .reduce(into: "") { $0.append($1) }
        return cleaned.isEmpty ? "route" : cleaned
    }
}
