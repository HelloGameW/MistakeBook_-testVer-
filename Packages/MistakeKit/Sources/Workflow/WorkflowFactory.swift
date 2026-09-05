import Foundation
import Contracts

public enum WorkflowFactory {
    public static func make(repository: any MistakeRepository, assets: any AssetStore,
                            intelligence: IntelligenceServices, exporter: any PDFExportService,
                            seedProvider: any TaxonomySeedProvider,
                            configuration: WorkflowConfiguration,
                            credentialStore: any CredentialStore = KeychainCredentialStore()) async throws -> any AppService {
        try Task.checkCancellation()
        let service = LocalAppService(repository: repository, assets: assets, intelligence: intelligence,
                                      exporter: exporter, seedProvider: seedProvider, configuration: configuration,
                                      credentialStore: credentialStore)
        try await service.startup()
        return service
    }
}
