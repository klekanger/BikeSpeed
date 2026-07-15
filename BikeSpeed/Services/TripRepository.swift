import Foundation
import SwiftData

/// A trip on its way into the store, payloads already encoded. `Sendable`, so it can cross into the actor —
/// a `@Model` never can.
struct ImportableTrip: Sendable {
    let entry: TripLogEntry
    let altitudeData: Data?
    let routeData: Data?
    let updatedAt: Date
}

/// The off-main-actor door into the store.
///
/// Deliberately narrow. Only the two jobs that genuinely must not run on the run loop live here: reading a
/// trip's payload blobs (a file read, then an O(samples) decode, then an O(samples) GPX render), and the
/// one-shot legacy import (a bulk write of the user's entire history at launch).
///
/// Everything else — the list's `@Query`, saving a finished trip, deleting one — runs on the main context
/// via `TripDataStack`. That is not laziness. It keeps the two paths the user is actively *watching* free of
/// any dependence on SwiftData propagating a background context's save into the main one, which is
/// historically the framework's flakiest corner.
@ModelActor
actor TripRepository {

    /// A trip's payloads, as bytes rather than decoded arrays: the decode is the caller's to schedule.
    /// `TripLogDetailView` does it inside a `Task.detached` together with the GPX render, in one hop.
    struct Payloads: Sendable {
        let altitudeData: Data?
        let routeData: Data?
    }

    /// `propertiesToFetch` (iOS 18) is the point of this method: without it, fetching a row to read two
    /// blobs materializes every column of it.
    func payloads(for id: UUID) throws -> Payloads {
        var descriptor = FetchDescriptor<StoredTrip>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        descriptor.propertiesToFetch = [\.altitudeData, \.routeData]
        guard let trip = try modelContext.fetch(descriptor).first else {
            return Payloads(altitudeData: nil, routeData: nil)
        }
        return Payloads(altitudeData: trip.altitudeData, routeData: trip.routeData)
    }

    /// The ids already in the store — the importer's dedupe key. CloudKit forbids `@Attribute(.unique)`, so
    /// there is no database-level collision to lean on and the check has to be explicit.
    func existingIDs() throws -> Set<UUID> {
        var descriptor = FetchDescriptor<StoredTrip>()
        descriptor.propertiesToFetch = [\.id]
        return Set(try modelContext.fetch(descriptor).map(\.id))
    }

    /// Bulk insert for the importer, keyed on `id` so a retry after a partial import cannot duplicate a
    /// ride. Returns the ids actually written.
    @discardableResult
    func insert(_ trips: [ImportableTrip]) throws -> [UUID] {
        let existing = try existingIDs()
        let fresh = trips.filter { !existing.contains($0.entry.id) }
        for trip in fresh {
            modelContext.insert(StoredTrip(
                entry: trip.entry,
                altitudeData: trip.altitudeData,
                routeData: trip.routeData,
                updatedAt: trip.updatedAt
            ))
        }
        try modelContext.save()
        return fresh.map(\.entry.id)
    }

    /// Post-import verification: which of these trips are actually in the store, and how many bytes of track
    /// each one carries. The importer compares this against what it read off disk *before* it deletes
    /// anything — it verifies from the store, not from what it believes it wrote.
    func routeByteCounts(for ids: [UUID]) throws -> [UUID: Int] {
        let descriptor = FetchDescriptor<StoredTrip>(predicate: #Predicate { ids.contains($0.id) })
        return try modelContext.fetch(descriptor).reduce(into: [:]) { counts, trip in
            counts[trip.id] = trip.routeData?.count ?? 0
        }
    }
}
