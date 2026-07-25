import Foundation
import Observation
import SwiftData

/// Owns the store and every seam a Pro tier will reach through. One object in the environment, so
/// `TripControlBar`, `TripLogListView` and `TripLogDetailView` each depend on exactly one thing.
///
/// Replaced `TripLogStore`. Note what is *not* here: any in-memory `entries` array or ordering the store must
/// maintain. The trip list is a `@Query` — live, sorted by the database, and never loading a row it doesn't draw.
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
    /// The encode is O(samples), off the run loop; the insert is on the **main context**, so the new row is in
    /// the list's `@Query` the moment this returns — no reliance on a background save propagating, and this is
    /// the one moment a user is actively watching for their ride to appear.
    ///
    /// **Throws rather than swallowing.** `TripManager.reset()` throws away the only other copy, so a `try?`
    /// would let a full disk silently eat the ride while the app confirms it saved. The failure has to reach
    /// the rider while the trip is still in memory to retry. Same for the encodes: a track that fails to encode
    /// must not quietly persist a trip with no track.
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

    /// The one place a trip is removed — the swipe *and* the detail view's button, one path as `TripLogStore`
    /// kept a single private `delete(ids:)`.
    ///
    /// Deleting the row takes its external-storage blobs with it: Core Data owns their lifetime, so there's no
    /// second source of truth to fall out of step and no orphaned track to reap —
    /// `TripLogStore.reapOrphanedRoutes()` has no subject any more.
    ///
    /// **The soft-delete seam.** When sync ships, this becomes `trip.deletedAt = now; trip.updatedAt = now` and
    /// nothing else changes, because `TripLogListView`'s `@Query` already filters `deletedAt == nil`.
    ///
    /// `async` purely so the sync notification is *awaited* rather than fired into a detached `Task`; the delete
    /// itself is synchronous and complete before the first `await`. Fire-and-forget would leave no way to observe
    /// the engine was told, and a test that has to sleep to find out will eventually lie.
    func delete(_ trips: [StoredTrip]) async {
        let ids = trips.map(\.id)
        for trip in trips {
            container.mainContext.delete(trip)
        }
        try? container.mainContext.save()

        for id in ids { await sync.tripWasDeleted(id) }
    }
}
