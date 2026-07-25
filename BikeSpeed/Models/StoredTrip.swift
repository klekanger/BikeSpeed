import Foundation
import SwiftData

/// The persisted form of a completed trip.
///
/// **Deliberately a different type from `TripLogEntry`.** The entry is the domain value (a `Codable` struct
/// the list rows render, `TripLogSummary` reduces, and a future web service would put on the wire); this is
/// the row. Keeping them apart keeps `import SwiftData` out of the rest of `Models/`, and means a REST
/// payload type already exists the day that backend appears.
///
/// **Every constraint here is a CloudKit constraint, not a SwiftData one.** `NSPersistentCloudKitContainer`
/// refuses to mirror a schema with unique constraints, non-optional attributes without defaults, or
/// relationships without inverses. So: no `@Attribute(.unique)`, every attribute defaulted, no relationships.
/// That keeps enabling sync one line and never a second migration —
/// `StoredTripTests.theSchemaIsCloudKitCompatible` fails the build if anyone breaks it.
///
/// `nonisolated` because `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` would otherwise pin this to the main
/// actor, and a main-actor `@Model` can't be touched inside a `@ModelActor` — where the import runs and the
/// detail view's track is fetched.
@Model
nonisolated final class StoredTrip {

    // MARK: - Identity and sync metadata
    //
    // Present from day one so enabling sync is never a migration. Nothing writes `deletedAt`, `syncedAt` or
    // `remoteID` yet; `TripDataStack` is the single seam that will.

    /// Stable identity across devices and backends — the same UUID the JSON log used, so an imported trip
    /// keeps the id its route file was named with.
    ///
    /// **No `@Attribute(.unique)`**: CloudKit mirroring rejects unique constraints, so the store accepts a
    /// duplicate id. Dedup is the *application's* job — see `LegacyTripLogImporter`, which filters against the
    /// existing ids rather than leaning on the store to reject a collision.
    ///
    /// `.preserveValueOnDeletion` carries this id into a SwiftData History *tombstone* (iOS 18); without it a
    /// `HistoryDelete` knows only an opaque `PersistentIdentifier`, so a future sync would see that *a* trip
    /// was deleted but not *which*. Free now, impossible to add later without a migration.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Last local mutation — the dirty clock. `syncedAt == nil || updatedAt > syncedAt` means "this row
    /// owes the server something". Stamped on insert; nothing edits a saved trip today.
    var updatedAt: Date = Date(timeIntervalSince1970: 0)

    /// Soft-delete tombstone. **Unwritten today** — `TripDataStack.delete` hard-deletes, since with no sync no
    /// peer can miss the deletion. Exists so that when sync ships, `delete` sets this instead of
    /// `context.delete` and *nothing else changes*: the list's `@Query` already filters on it.
    var deletedAt: Date?

    /// When the server last acknowledged this row. Nil = never synced.
    var syncedAt: Date?

    /// A web service's own primary key, if it insists on assigning one. Free to carry now, impossible to
    /// add later without a migration.
    var remoteID: String?

    // MARK: - Trip data

    var startDate: Date = Date(timeIntervalSince1970: 0)
    var duration: TimeInterval = 0     // seconds, active only
    var distance: Double = 0           // meters
    var averageSpeed: Double = 0       // m/s
    var maxSpeed: Double = 0           // m/s
    /// Optional because a trip recorded without usable altitude has no answer to "how much did you climb",
    /// and 0 would call it flat. (Satisfying CloudKit is a bonus.)
    var totalAscent: Double?
    var totalDescent: Double?

    // MARK: - Payloads
    //
    // *Encoded value arrays*, not relationships. A 40 km ride is thousands of samples; as a to-many
    // relationship that's thousands of CKRecords for one trip, against CloudKit's 400-per-operation cap. As
    // external storage it's one CKRecord + one CKAsset — and Core Data faults the blob in only on property
    // access, so the list never pays for a track it doesn't draw.
    //
    // Encoding is `TripPayloadCoder`'s, byte-identical to what `Routes/<uuid>.json` held — so the importer
    // copies those files in as bytes rather than re-encoding.

    /// The height profile: `[AltitudeSample]`, JSON.
    @Attribute(.externalStorage) var altitudeData: Data?

    /// The recorded track: `[RouteSample]`, JSON.
    @Attribute(.externalStorage) var routeData: Data?

    // MARK: - Indices
    //
    // The list sorts by `startDate`; everything else looks up by `id`. `#Index` (iOS 18) makes both an index
    // seek rather than a table scan once the log holds years of rides. Note `#Index`, *not* `#Unique` — see `id`.
    #Index<StoredTrip>([\.startDate], [\.id])

    init(
        id: UUID,
        startDate: Date,
        duration: TimeInterval,
        distance: Double,
        averageSpeed: Double,
        maxSpeed: Double,
        totalAscent: Double?,
        totalDescent: Double?,
        altitudeData: Data?,
        routeData: Data?,
        updatedAt: Date
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.averageSpeed = averageSpeed
        self.maxSpeed = maxSpeed
        self.totalAscent = totalAscent
        self.totalDescent = totalDescent
        self.altitudeData = altitudeData
        self.routeData = routeData
        self.updatedAt = updatedAt
    }
}

extension StoredTrip {
    /// Builds a row from a domain value plus its already-encoded payloads — the inverse of `entry`, kept
    /// beside it so the mapping lives in one place. `TripDataStack.save` and `TripRepository.insert` both go
    /// through here; adding a scalar then touches only this init, the designated init, and `entry`.
    convenience init(entry: TripLogEntry, altitudeData: Data?, routeData: Data?, updatedAt: Date) {
        self.init(
            id: entry.id,
            startDate: entry.startDate,
            duration: entry.duration,
            distance: entry.distance,
            averageSpeed: entry.averageSpeed,
            maxSpeed: entry.maxSpeed,
            totalAscent: entry.totalAscent,
            totalDescent: entry.totalDescent,
            altitudeData: altitudeData,
            routeData: routeData,
            updatedAt: updatedAt
        )
    }

    /// The row as the domain value the pure code speaks — `TripLogSummary`, the list rows, one day a REST payload.
    ///
    /// **Touches no blob**, which is the whole point: this runs once per visible row on every list render, and
    /// faulting a track in here is exactly what the file-per-route layout existed to avoid. Do not fold the
    /// altitude profile back in.
    var entry: TripLogEntry {
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
}
