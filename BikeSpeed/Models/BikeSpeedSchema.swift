import Foundation
import SwiftData

/// V1 is the schema the JSON trip log was imported into.
///
/// **When V2 arrives**: copy the *current* `StoredTrip` source into a `BikeSpeedSchemaV2` enum (renaming
/// the enum, not the class), evolve the top-level `StoredTrip`, and add a `MigrationStage` below. A
/// lightweight stage covers adding an optional attribute; anything that reshapes existing data needs
/// `.custom(willMigrate:didMigrate:)`.
enum BikeSpeedSchemaV1: VersionedSchema {
    nonisolated static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    nonisolated static var models: [any PersistentModel.Type] { [StoredTrip.self] }
}

/// Deliberately empty, and present from the first byte ever written. An app that ships unversioned and
/// *then* needs a migration has to guess what its original schema was; this one never will.
enum BikeSpeedMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] { [BikeSpeedSchemaV1.self] }
    nonisolated static var stages: [MigrationStage] { [] }
}

nonisolated enum TripModelContainer {
    static var schema: Schema { Schema(versionedSchema: BikeSpeedSchemaV1.self) }

    /// The CloudKit container every rider's trips mirror to — private database, so a trip follows the
    /// user's iCloud account across their devices and nobody else's.
    ///
    /// **Derived from the bundle id, never hardcoded.** `BikeSpeed.entitlements` names the same container as
    /// `iCloud.$(PRODUCT_BUNDLE_IDENTIFIER)`, which Xcode expands to `iCloud.<bundle id>` at build time; this
    /// computes the identical string at runtime from `Bundle.main.bundleIdentifier`. So the two can never
    /// drift, and anyone forking this open-source app gets a working container by changing only their team
    /// and bundle id — there is no `lekanger`-specific string to hunt down. See the README's "Running your
    /// own copy".
    static let cloudKitContainerID: String = {
        guard let bundleID = Bundle.main.bundleIdentifier else {
            preconditionFailure("No bundle identifier — cannot derive the CloudKit container id")
        }
        return "iCloud.\(bundleID)"
    }()

    /// The app's real store, mirrored to the user's private iCloud database.
    ///
    /// Enabling sync was exactly what `StoredTrip` was shaped for: `cloudKitDatabase:` here plus the
    /// entitlements file, no code and no migration, because the model satisfies the CloudKit mirroring
    /// rules from day one. Passing a `cloudKitDatabase` hands the store to `NSPersistentCloudKitContainer`,
    /// which still opens the **local** store when the user is signed out of iCloud — mirroring just stays
    /// dormant until an account appears — so this does not throw for the no-account case. The only new way
    /// it throws is genuine misprovisioning (wrong/missing entitlement, an unprovisioned container id),
    /// which is a build defect and correctly fatal at the call site.
    static func app() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false,
                cloudKitDatabase: .private(cloudKitContainerID)
            )
        )
    }

    /// For tests and previews. `isStoredInMemoryOnly` is what makes the suite safe under Swift Testing's
    /// parallel execution: every test gets its own store with no file to collide over — the property the old
    /// `TripLogStoreTests` had to buy with a per-test temp directory.
    static func inMemory() throws -> ModelContainer {
        let schema = schema
        return try ModelContainer(
            for: schema,
            migrationPlan: BikeSpeedMigrationPlan.self,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        )
    }
}
