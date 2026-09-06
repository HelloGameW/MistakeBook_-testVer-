import Foundation
import Contracts
import Storage
import Intelligence
import Export
import Workflow

/// The only production service composition. Local processing remains the default; optional API providers are routed through Contracts and Keychain-backed credentials.
enum ProductionAssembly {
    static func make() async throws -> any AppService {
        let files = FileManager.default
        let root = try files.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                 appropriateFor: nil, create: true).appendingPathComponent("MistakeBook", isDirectory: true)
        let temporary = try files.url(for: .cachesDirectory, in: .userDomainMask,
                                      appropriateFor: nil, create: true).appendingPathComponent("MistakeBookExports", isDirectory: true)
        guard let seedURL = Bundle.main.url(forResource: "seed", withExtension: "json", subdirectory: "Taxonomy") else {
            throw AppError(code: .invalidTaxonomy)
        }
        try files.createDirectory(at: temporary, withIntermediateDirectories: true)
        // These are disposable export copies from a previous launch, never source records/assets.
        for url in try files.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("MistakeBook-") || url.lastPathComponent.hasPrefix(".images-") {
            try files.removeItem(at: url)
        }
        return try await make(rootDirectory: root, temporaryDirectory: temporary, taxonomySeedURL: seedURL)
    }

    static func make(rootDirectory: URL, temporaryDirectory: URL, taxonomySeedURL: URL) async throws -> any AppService {
        let storage = try await StorageFactory.make(configuration: StorageConfiguration(
            rootDirectory: rootDirectory, inMemory: false, excludeFromBackup: true,
            protection: .completeUntilFirstUserAuthentication))
        let recognition = RecognitionOptions(languages: ["zh-Hans", "en-US"], quality: .accurate,
                                             usesLanguageCorrection: true, maxPixelDimension: 4096)
        let credentialStore = KeychainCredentialStore()
        let intelligence = try IntelligenceFactory.make(configuration: IntelligenceConfiguration(
            recognition: recognition,
            analysis: AnalysisOptions(useEnhancedModel: true, language: "zh-Hans", timeoutSeconds: 30),
            value: ValueAnalysisOptions()), credentialStore: credentialStore)
        let exporter = try ExportFactory.make(assetStore: storage.assets, configuration: PDFExportConfiguration(
            temporaryDirectory: temporaryDirectory, fileLifetimeSeconds: 86_400))
        let seedProvider = try IntelligenceFactory.makeTaxonomySeedProvider(resourceURL: taxonomySeedURL)
        return try await WorkflowFactory.make(repository: storage.repository, assets: storage.assets,
            intelligence: intelligence, exporter: exporter, seedProvider: seedProvider,
            configuration: WorkflowConfiguration(maxBatchSize: 20, maxConcurrentJobs: 1,
                initialSettings: AppSettings(recognitionLanguages: ["zh-Hans", "en-US"],
                    enhancedAnalysisEnabled: true,
                    autoArchivePolicy: AutoArchivePolicy(version: "unvalidated-disabled", enabledRules: []),
                    processingMode: .api, ocrProvider: .glm,
                    analysisProvider: .appleFoundationModels, mistakeValueProvider: .localHeuristic)),
            credentialStore: credentialStore)
    }
}
