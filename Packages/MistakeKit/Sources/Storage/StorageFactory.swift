import Foundation
import SwiftData
import Contracts

public enum StorageFactory {
    public static func make(configuration: StorageConfiguration) async throws -> StorageServices {
        try Task.checkCancellation()
        guard configuration.rootDirectory.isFileURL else { throw AppError(code: .unsupportedInput) }
        let schema = Schema([
            StoredRecordEntity.self, StoredJobEntity.self, StoredBatchEntity.self,
            StoredTaxonomyEntity.self, StoredSettingsEntity.self, StoredTombstoneEntity.self,
            StoredRegionUndoEntity.self, StoredDeletionEntity.self, StoredTransactionEntity.self,
            StoredMetadataEntity.self
        ])
        let root = configuration.rootDirectory.standardizedFileURL
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if configuration.excludeFromBackup {
            var protectedRoot = root
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try protectedRoot.setResourceValues(values)
        }
        #if os(iOS)
        let protection: FileProtectionType = configuration.protection == .complete ? .complete : .completeUntilFirstUserAuthentication
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: root.path)
        #endif
        let modelConfiguration: ModelConfiguration
        if configuration.inMemory {
            modelConfiguration = ModelConfiguration("MistakeBook", schema: schema, isStoredInMemoryOnly: true,
                                                    allowsSave: true, groupContainer: .automatic, cloudKitDatabase: .none)
        } else {
            let databaseURL = root.appendingPathComponent("MistakeBook.store")
            modelConfiguration = ModelConfiguration("MistakeBook", schema: schema, url: databaseURL,
                                                    allowsSave: true, cloudKitDatabase: .none)
        }
        let container: ModelContainer
        do { container = try ModelContainer(for: schema, configurations: [modelConfiguration]) }
        catch { throw AppError(code: .internalFailure, isRetryable: true) }
        let repository = SwiftDataMistakeRepository(container: container)
        let assets = try await FileAssetStore(configuration: configuration)
        return StorageServices(repository: repository, assets: assets)
    }
}
