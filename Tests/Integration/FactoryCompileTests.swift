import Foundation
import XCTest
import Contracts
import Intelligence
import Storage
import Workflow
import Export
import UI
import TestSupport
import PreviewSupport

final class FactoryCompileTests: XCTestCase {
    func testFrozenFactoryTypesAreVisible() {
        XCTAssertEqual(ContractSchema.version, "1.0.0")
    }
}

// Compile-only integration coverage; does not invoke production factories.
@MainActor
private func compileFactorySurface() async throws {
    let storage = try await StorageFactory.make(configuration: ContractSamples.storageConfiguration())
    let intelligence = try IntelligenceFactory.make(configuration: ContractSamples.intelligenceConfiguration())
    let seed = try IntelligenceFactory.makeTaxonomySeedProvider(resourceURL: URL(fileURLWithPath: "/synthetic/seed.json"))
    let exporter = try ExportFactory.make(assetStore: storage.assets, configuration: ContractSamples.pDFExportConfiguration())
    let service = try await WorkflowFactory.make(repository: storage.repository, assets: storage.assets,
        intelligence: intelligence, exporter: exporter, seedProvider: seed,
        configuration: ContractSamples.workflowConfiguration())
    _ = MistakeBookRootView(service: service)
    _ = PreviewAssembly.make()
}
