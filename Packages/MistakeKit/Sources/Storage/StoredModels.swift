import Foundation
import SwiftData

// Soft-delete state uses a custom name: `isDeleted` collides with SwiftData's
// PersistentModel.isDeleted context semantics and does not persist reliably.
@Model
final class StoredRecordEntity {
    @Attribute(.unique) var idString: String
    var payload: Data
    var isSoftDeleted: Bool
    var recordRevision: Int
    var contentRevision: Int
    var createdAt: Date
    var updatedAt: Date
    var searchText: String
    var subjectID: String?
    var primaryNodeID: String?

    init(idString: String, payload: Data, isSoftDeleted: Bool, recordRevision: Int,
         contentRevision: Int, createdAt: Date, updatedAt: Date, searchText: String,
         subjectID: String?, primaryNodeID: String?) {
        self.idString = idString; self.payload = payload; self.isSoftDeleted = isSoftDeleted
        self.recordRevision = recordRevision; self.contentRevision = contentRevision
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.searchText = searchText
        self.subjectID = subjectID; self.primaryNodeID = primaryNodeID
    }
}

@Model
final class StoredJobEntity {
    @Attribute(.unique) var idString: String
    var payload: Data
    var stateRaw: String
    var attempt: Int
    var updatedAt: Date

    init(idString: String, payload: Data, stateRaw: String, attempt: Int, updatedAt: Date) {
        self.idString = idString; self.payload = payload; self.stateRaw = stateRaw
        self.attempt = attempt; self.updatedAt = updatedAt
    }
}

@Model
final class StoredBatchEntity {
    @Attribute(.unique) var idString: String
    var payload: Data
    var updatedAt: Date

    init(idString: String, payload: Data, updatedAt: Date) {
        self.idString = idString; self.payload = payload; self.updatedAt = updatedAt
    }
}

@Model
final class StoredTaxonomyEntity {
    @Attribute(.unique) var idString: String
    var payload: Data
    var version: String

    init(idString: String, payload: Data, version: String) {
        self.idString = idString; self.payload = payload; self.version = version
    }
}

@Model
final class StoredSettingsEntity {
    @Attribute(.unique) var idString: String
    var payload: Data

    init(idString: String, payload: Data) { self.idString = idString; self.payload = payload }
}

@Model
final class StoredTombstoneEntity {
    @Attribute(.unique) var idString: String
    var payload: Data

    init(idString: String, payload: Data) { self.idString = idString; self.payload = payload }
}

@Model
final class StoredRegionUndoEntity {
    @Attribute(.unique) var idString: String
    var payload: Data

    init(idString: String, payload: Data) { self.idString = idString; self.payload = payload }
}

@Model
final class StoredDeletionEntity {
    @Attribute(.unique) var idString: String
    var payload: Data
    var isConsumed: Bool

    init(idString: String, payload: Data, isConsumed: Bool) {
        self.idString = idString; self.payload = payload; self.isConsumed = isConsumed
    }
}

@Model
final class StoredTransactionEntity {
    @Attribute(.unique) var idString: String
    var payload: Data

    init(idString: String, payload: Data) { self.idString = idString; self.payload = payload }
}

@Model
final class StoredMetadataEntity {
    @Attribute(.unique) var key: String
    var value: String

    init(key: String, value: String) { self.key = key; self.value = value }
}
