import Foundation
import Testing

@testable import BikeSpeed

/// The export is the app's only interoperability surface: whatever comes out of here has to be readable
/// by Strava, Komoot and Garmin, none of which are lenient. So these tests parse the output back as XML
/// rather than matching strings — a test that only greps for `<trkpt` would happily pass on a document
/// no importer could open.
@Suite
struct GPXExporterTests {

    @Test
    func everyRouteSampleBecomesATrackPoint() throws {
        let gpx = GPXExporter.makeGPX(route: makeRoute(count: 3), trackName: "Morning ride")

        let track = try parse(gpx)

        #expect(track.points.count == 3)
    }

    @Test
    func coordinatesAndElevationsSurviveTheRoundTrip() throws {
        let route = [
            RouteSample(latitude: 59.9139, longitude: 10.7522, altitude: 100, timestamp: .distantPast),
            RouteSample(latitude: 59.9184, longitude: 10.7530, altitude: 142.5, timestamp: .distantPast),
        ]

        let track = try parse(GPXExporter.makeGPX(route: route, trackName: "Ride"))

        let first = try #require(track.points.first)
        expectClose(first.latitude, 59.9139, within: 0.000_001)
        expectClose(first.longitude, 10.7522, within: 0.000_001)
        expectClose(try #require(first.elevation), 100, within: 0.05)
        expectClose(try #require(track.points.last?.elevation), 142.5, within: 0.05)
    }

    @Test
    func timestampsAreISO8601() throws {
        let sample = RouteSample(
            latitude: 59.9139,
            longitude: 10.7522,
            altitude: 100,
            timestamp: Date(timeIntervalSince1970: 1_770_000_000)
        )

        let track = try parse(GPXExporter.makeGPX(route: [sample], trackName: "Ride"))

        let time = try #require(track.points.first?.time)
        #expect(time == "2026-02-02T02:40:00Z")

        // The point of the format, rather than of the string: a GPX consumer has to be able to read it back.
        let formatter = ISO8601DateFormatter()
        let parsed = try #require(formatter.date(from: time))
        expectClose(parsed.timeIntervalSince1970, 1_770_000_000, within: 1)
    }

    /// **The interoperability guard.** Coordinates must always use a `.` decimal separator. Norwegian —
    /// the app's other language — writes decimals with a comma, so a `NumberFormatter` on the current
    /// locale would emit `lat="59,9139000"`: not valid GPX, and silently unreadable by every app the
    /// rider would want to open it in. `String(format:)` is not locale-aware, which is exactly why
    /// `GPXExporter` uses it; this test is what stops someone "improving" that.
    @Test(.tags(.edgeCase))
    func coordinatesUseDotDecimalSeparators() throws {
        // Deliberately a name a Norwegian device would produce, comma and all: the rule is about the
        // *numbers*, and a blanket "no commas in the document" check would both miss the point and fail
        // on a perfectly good track name.
        let track = try parse(GPXExporter.makeGPX(route: makeRoute(count: 2), trackName: "14. juli 2026, 10:02"))

        let decimal = /^-?[0-9]+\.[0-9]+$/
        for point in track.points {
            #expect(point.rawLatitude.wholeMatch(of: decimal) != nil, "latitude '\(point.rawLatitude)' is not a dot-separated decimal")
            #expect(point.rawLongitude.wholeMatch(of: decimal) != nil, "longitude '\(point.rawLongitude)' is not a dot-separated decimal")
        }
        #expect(track.points.isEmpty == false)
    }

    /// A point recorded without usable vertical accuracy has no height — the tag is left out rather than
    /// written as `0`, which would place the rider at sea level.
    @Test
    func aSampleWithoutAltitudeOmitsTheElevationTag() throws {
        let sample = RouteSample(latitude: 59.9139, longitude: 10.7522, altitude: nil, timestamp: .distantPast)

        let track = try parse(GPXExporter.makeGPX(route: [sample], trackName: "Ride"))

        #expect(track.points.count == 1)
        #expect(track.points.first?.elevation == nil)
    }

    /// Nothing stops a caller asking to export a trip whose route never recorded. It has to produce a
    /// valid, empty document — a malformed one is worse than an empty one, since the rider only finds out
    /// once the import fails somewhere else.
    @Test(.tags(.edgeCase))
    func anEmptyRouteProducesAValidEmptyTrack() throws {
        let track = try parse(GPXExporter.makeGPX(route: [], trackName: "Ride"))

        #expect(track.points.isEmpty)
    }

    /// The track name reaches the file as markup, so it has to be escaped. A date is what actually goes in
    /// there today, but the rule shouldn't depend on that staying true.
    @Test
    func aTrackNameContainingMarkupIsEscaped() throws {
        let gpx = GPXExporter.makeGPX(route: makeRoute(count: 1), trackName: "Tom & Jerry's <ride>")

        let track = try parse(gpx) // would throw on unescaped `<`

        #expect(track.name == "Tom & Jerry's <ride>")
    }

    @Test
    func writingProducesAReadableFileNamedAfterTheTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GPXExporterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = try GPXExporter.write(
            route: makeRoute(count: 2),
            trackName: "Ride",
            fileName: "BikeSpeed-2026-07-04-0915",
            in: directory
        )

        #expect(url.lastPathComponent == "BikeSpeed-2026-07-04-0915.gpx")
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(try parse(written).points.count == 2)
    }

    /// The one guard between a localized date and the filesystem. Its only production caller passes an
    /// already-safe `yyyy-MM-dd-HHmm`, so nothing exercises it in practice — which is precisely why it
    /// needs pinning here: the day someone swaps the file name for a localized date, exactly as
    /// `sanitized`'s doc comment anticipates, the separators have to be gone before they reach the path.
    @Test(.tags(.edgeCase))
    func aFileNameCarryingPathSeparatorsIsSanitized() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GPXExporterTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // A Norwegian and an English localized date, in one name: `.` and `/` both.
        let url = try GPXExporter.write(
            route: makeRoute(count: 1),
            trackName: "Ride",
            fileName: "14/07/2026 10.02",
            in: directory
        )

        #expect(
            url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
            "a `/` in the name must not let the file escape its directory"
        )
        #expect(url.pathExtension == "gpx")
        #expect(
            url.deletingPathExtension().lastPathComponent.contains(".") == false,
            "a `.` in the name would leave the file with a second extension"
        )
        #expect(try parse(String(contentsOf: url, encoding: .utf8)).points.count == 1)
    }

    // MARK: - Helpers

    private func makeRoute(count: Int) -> [RouteSample] {
        (0..<count).map { index in
            RouteSample(
                latitude: 59.9139 + Double(index) * 0.001,
                longitude: 10.7522,
                altitude: 100 + Double(index),
                timestamp: Date(timeIntervalSince1970: 1_770_000_000 + Double(index))
            )
        }
    }

    private func parse(_ gpx: String) throws -> ParsedTrack {
        let collector = GPXCollector()
        let parser = XMLParser(data: Data(gpx.utf8))
        parser.delegate = collector
        try #require(parser.parse(), "the document must be well-formed XML: \(parser.parserError?.localizedDescription ?? "unknown error")")
        return ParsedTrack(name: collector.name, points: collector.points)
    }
}

private struct ParsedTrack {
    let name: String
    let points: [ParsedPoint]
}

private struct ParsedPoint {
    let rawLatitude: String
    let rawLongitude: String
    let elevation: Double?
    let time: String?

    var latitude: Double { Double(rawLatitude) ?? .nan }
    var longitude: Double { Double(rawLongitude) ?? .nan }
}

/// Reads the document back the way an importer would. `nonisolated` because `XMLParser` calls its delegate
/// synchronously on the caller's thread, and the app's `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would
/// otherwise make these callbacks main-actor-isolated and unable to satisfy the protocol.
private nonisolated final class GPXCollector: NSObject, XMLParserDelegate {
    private(set) var name = ""
    private(set) var points: [ParsedPoint] = []

    private var currentElement = ""
    private var currentText = ""
    private var latitude = ""
    private var longitude = ""
    private var elevation: Double?
    private var time: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String]
    ) {
        currentElement = elementName
        currentText = ""
        if elementName == "trkpt" {
            latitude = attributes["lat"] ?? ""
            longitude = attributes["lon"] ?? ""
            elevation = nil
            time = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        switch elementName {
        case "name": name = text
        case "ele": elevation = Double(text)
        case "time": time = text
        case "trkpt":
            points.append(ParsedPoint(
                rawLatitude: latitude,
                rawLongitude: longitude,
                elevation: elevation,
                time: time
            ))
        default: break
        }
        currentText = ""
    }
}
