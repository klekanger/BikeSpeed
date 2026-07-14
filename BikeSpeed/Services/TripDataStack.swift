import Foundation
import Observation
import SwiftData

/// Owns the store and every seam a Pro tier will need to reach through. One object in the environment, so
/// `TripControlBar`, `TripLogListView` and `TripLogDetailView` each depend on exactly one thing.
///
/// This is what replaced `TripLogStore`. Note what is *not* here: any notion of an in-memory `entries`
/// array, or an ordering the store has to maintain. The trip list is a `@Query`, which is live, sorted by
/// the database, and never loads a row it does not draw.
@MainActor
@Observable
final class TripDataStack {
    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let repository: TripRepository

    /// `NoOpTripSyncEngine` today. Every mutation below already notifies it, so the day a real engine
    /// appears, no call site changes. `TripDataStackTests` is what keeps that promise honest.
    @ObservationIgnored let sync: any TripSyncEngine

    init(container: ModelContainer, sync: any TripSyncEngine = NoOpTripSyncEngine()) {
        self.container = container
        self.repository = TripRepository(modelContainer: container)
        self.sync = sync
    }

    /// The one place a trip is written, called from `TripControlBar` at Save.
    ///
    /// The encode is O(samples) and happens off the run loop. The insert is O(1) once the blobs are bytes,
    /// and happens on the **main context** — so the new row is in the list's `@Query` the moment this
    /// returns, with no reliance on a background context's save propagating. This is the one moment a user
    /// is actively waiting to see their ride appear.
    ///
    /// **Throws rather than swallowing.** The caller has just finished a ride and is about to be told it was
    /// saved, and `TripManager.reset()` will throw the only other copy away. A `try?` here would mean a full
    /// disk silently eats the ride *and* the app cheerfully confirms it — so the failure has to reach the
    /// rider while their trip is still in memory to retry with. Same for the encodes: a track that fails to
    /// encode must not quietly persist a trip with no track.
    func save(_ entry: TripLogEntry, altitudeProfile: [AltitudeSample], route: [RouteSample]) async throws {
        let payloads = try await Task.detached {
            (
                altitude: altitudeProfile.isEmpty ? nil : try TripPayloadCoder.encode(altitudeProfile),
                route: route.isEmpty ? nil : try TripPayloadCoder.encode(route)
            )
        }.value

        let trip = StoredTrip(
            entry: entry,
            altitudeData: payloads.altitude,
            routeData: payloads.route,
            updatedAt: Date()
        )
        container.mainContext.insert(trip)
        try container.mainContext.save()

        await sync.tripDidChange(entry.id)
    }

    /// The one place a trip is removed — the swipe *and* the detail view's button, exactly as `TripLogStore`
    /// kept a single private `delete(ids:)` for exactly this reason.
    ///
    /// Deleting the row takes its external-storage blobs with it: Core Data owns their lifetime. There is no
    /// second source of truth to fall out of step, and so no orphaned track to reap — the whole job
    /// `TripLogStore.reapOrphanedRoutes()` existed to do simply has no subject any more.
    ///
    /// **The soft-delete seam.** When sync ships, the `delete` below becomes
    /// `trip.deletedAt = now; trip.updatedAt = now` — and nothing else changes, because
    /// `TripLogListView`'s `@Query` already filters `deletedAt == nil`.
    /// `async` purely so the sync notification is *awaited* rather than fired into a detached `Task`. The
    /// delete itself is synchronous and complete before the first `await`. Firing and forgetting would leave
    /// no way to observe that the engine was told — and a test that has to sleep to find out is a test that
    /// will eventually lie.
    func delete(_ trips: [StoredTrip]) async {
        let ids = trips.map(\.id)
        for trip in trips {
            container.mainContext.delete(trip)
        }
        try? container.mainContext.save()

        for id in ids { await sync.tripWasDeleted(id) }
    }
}
