import SwiftData

/// The first versioned store shape, and the baseline a later `SchemaMigrationPlan` migrates
/// from. Its models are nested classes that stay frozen; the top-level names
/// (`ActionRecord`, …) are typealiases to the current version, so the next version adds
/// its own nested classes and moves the aliases. Stores written before versioning (the
/// same models without `ActionRecord.mutationPayload`) open under it through lightweight
/// migration.
enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [SchemaV1.FavoriteItem.self, SchemaV1.HistoryItem.self, SchemaV1.ActionRecord.self, SchemaV1.PackageGroup.self]
    }
}
