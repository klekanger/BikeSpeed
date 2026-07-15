import Foundation
import SwiftData
import Testing
@testable import BikeSpeed

// MARK: - Stores

/// A throwaway store, in memory.
///
/// `isStoredInMemoryOnly` is what makes this suite safe under Swift Testing's parallel execution: every test
/// gets its own store with no file on disk to collide over. The old `TripLogStoreTests` had to buy the same
/// property with a per-test temp directory and a `defer` to reap it; here it falls out for free.
@MainActor
func makeStack(sync: any TripSyncEngine = NoOpTripSyncEngine()) throws -> TripDataStack {
    TripDataStack(container: try TripModelContainer.inMemory(), sync: sync)
}

// MARK: - Sync

/// Records what the stack told it. The point of this spy is not to test the no-op engine — it is to fail if a
/// *new* mutation path is ever added to `TripDataStack` that forgets to announce itself. Without it, the sync
/// seam would rot silently, and the failure would surface a year from now as rides that never reached the
/// server.
final class SpyTripSyncEngine: TripSyncEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var _changed: [UUID] = []
    private var _deleted: [UUID] = []

    var changed: [UUID] { lock.withLock { _changed } }
    var deleted: [UUID] { lock.withLock { _deleted } }

    func tripDidChange(_ id: UUID) async { lock.withLock { _changed.append(id) } }
    func tripWasDeleted(_ id: UUID) async { lock.withLock { _deleted.append(id) } }
    func pullChanges() async throws {}
}

// MARK: - Trips

func makeEntry(
    id: UUID = UUID(),
    startDate: Date = Date(timeIntervalSince1970: 1_760_000_000),
    duration: TimeInterval = 1800,
    distance: Double = 12_400,
    averageSpeed: Double = 6.8,
    maxSpeed: Double = 11.4,
    totalAscent: Double? = 312,
    totalDescent: Double? = 296
) -> TripLogEntry {
    TripLogEntry(
        id: id,
        startDate: startDate,
        duration: duration,
        distance: distance,
        averageSpeed: averageSpeed,
        maxSpeed: maxSpeed,
        totalAscent: totalAscent,
        totalDescent: totalDescent
    )
}

func makeRoute(count: Int = 3) -> [RouteSample] {
    (0..<count).map { index in
        RouteSample(
            latitude: 59.9139 + Double(index) * 0.001,
            longitude: 10.7522,
            altitude: 100 + Double(index),
            timestamp: Date(timeIntervalSince1970: 1_760_000_000 + Double(index))
        )
    }
}

func makeProfile(count: Int = 3) -> [AltitudeSample] {
    (0..<count).map { index in
        AltitudeSample(distance: Double(index) * 25, altitude: 100 + Double(index) * 3)
    }
}

// MARK: - The legacy JSON layout

/// Writes a `TripLog.json` (and optionally `Routes/<uuid>.json`) into a throwaway directory shaped exactly
/// like the Application Support folder the shipped app wrote. Returns the directory to hand to
/// `LegacyTripLogImporter`.
func makeLegacyDirectory(log: String, routes: [UUID: String] = [:]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("LegacyImport-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data(log.utf8).write(to: directory.appendingPathComponent("TripLog.json"))

    if !routes.isEmpty {
        let routesDirectory = directory.appendingPathComponent("Routes", isDirectory: true)
        try FileManager.default.createDirectory(at: routesDirectory, withIntermediateDirectories: true)
        for (id, json) in routes {
            try Data(json.utf8).write(to: routesDirectory.appendingPathComponent("\(id.uuidString).json"))
        }
    }
    return directory
}

func removeDirectory(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

func legacyLogExists(in directory: URL) -> Bool {
    FileManager.default.fileExists(atPath: directory.appendingPathComponent("TripLog.json").path)
}
