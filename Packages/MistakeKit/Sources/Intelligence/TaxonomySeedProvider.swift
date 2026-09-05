import Foundation
import Contracts

public struct JSONTaxonomySeedProvider: TaxonomySeedProvider, Sendable {
    private let resourceURL: URL

    public init(resourceURL: URL) throws {
        guard resourceURL.isFileURL else { throw AppError(code: .unsupportedInput) }
        self.resourceURL = resourceURL
    }

    public func loadSeed() async throws -> TaxonomySeed {
        try Task.checkCancellation()
        do {
            let data = try Data(contentsOf: resourceURL, options: [.mappedIfSafe])
            return try ContractJSON.decoder().decode(TaxonomySeed.self, from: data)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError(code: .invalidTaxonomy)
        }
    }
}
