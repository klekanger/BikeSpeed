import Foundation

/// The seam a Pro/Plus tier reaches through.
///
/// Nothing implements it today except the no-op. Its whole job right now is to make sure every mutation in
/// `TripDataStack` already *has* somewhere to announce itself, so that shipping sync is adding a type rather
/// than editing every call site — and `TripDataStackTests` fails if a new mutation path forgets to.
///
/// Note what is deliberately **not** here: iCloud. CloudKit mirroring is a property of the *store*, not of
/// the app's code — `ModelConfiguration(cloudKitDatabase:)` in `TripModelContainer` turns it on, and
/// `StoredTrip` is already shaped to satisfy it. This protocol is for a backend that is *not* CloudKit: a
/// web service with an account, which has to be told what changed. iOS 18's SwiftData History is how a real
/// implementation would answer that ("what happened since my last token"), including which trip a delete
/// removed — see `StoredTrip.id`'s `.preserveValueOnDeletion`.
nonisolated protocol TripSyncEngine: Sendable {
    /// A trip was created or edited locally.
    func tripDidChange(_ id: UUID) async

    /// A trip was deleted locally. Takes the id, not the model: a deleted `@Model` has nothing left to read.
    func tripWasDeleted(_ id: UUID) async

    /// Pull remote changes into the local store.
    func pullChanges() async throws
}

/// The free tier — and for now, everyone. Sync is a Pro feature; for everybody else the local store *is*
/// the truth, and there is nothing to tell.
nonisolated struct NoOpTripSyncEngine: TripSyncEngine {
    func tripDidChange(_ id: UUID) async {}
    func tripWasDeleted(_ id: UUID) async {}
    func pullChanges() async throws {}
}
