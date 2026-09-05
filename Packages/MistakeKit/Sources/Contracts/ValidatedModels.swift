import Foundation

public struct ExportOptions: Codable, Sendable, Equatable {
    public let mode: ExportMode
    public let includeHandwriting: Bool
    public let includeHypotheses: Bool
    public let blankSpace: BlankSpace
    public let sort: ExportSort
    public let pageSize: PageSize

    public init(mode: ExportMode, includeHandwriting: Bool, includeHypotheses: Bool,
                blankSpace: BlankSpace, sort: ExportSort, pageSize: PageSize) throws {
        guard mode != .practice || (!includeHandwriting && !includeHypotheses) else {
            throw AppError(code: .unsupportedInput)
        }
        self.mode = mode; self.includeHandwriting = includeHandwriting; self.includeHypotheses = includeHypotheses
        self.blankSpace = blankSpace; self.sort = sort; self.pageSize = pageSize
    }
    private enum CodingKeys: String, CodingKey { case mode, includeHandwriting, includeHypotheses, blankSpace, sort, pageSize }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(mode: c.decode(ExportMode.self, forKey: .mode),
                      includeHandwriting: c.decode(Bool.self, forKey: .includeHandwriting),
                      includeHypotheses: c.decode(Bool.self, forKey: .includeHypotheses),
                      blankSpace: c.decode(BlankSpace.self, forKey: .blankSpace),
                      sort: c.decode(ExportSort.self, forKey: .sort), pageSize: c.decode(PageSize.self, forKey: .pageSize))
    }
}

public struct TaxonomySeed: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let seedVersion: String
    public let nodes: [TaxonomyNode]
    public init(schemaVersion: Int, seedVersion: String, nodes: [TaxonomyNode]) throws {
        try ContractSchema.requireSupported(schemaVersion)
        guard !seedVersion.isEmpty else { throw AppError(code: .invalidTaxonomy) }
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count, !ids.contains("") else { throw AppError(code: .invalidTaxonomy) }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            guard !node.name.isEmpty, !node.subjectID.isEmpty, node.version >= 1,
                  let subject = byID[node.subjectID], subject.parentID == nil,
                  subject.subjectID == subject.id else { throw AppError(code: .invalidTaxonomy) }
            var visited: Set<String> = [node.id]
            var parentID = node.parentID
            while let id = parentID {
                guard let parent = byID[id], parent.subjectID == node.subjectID,
                      visited.insert(id).inserted else { throw AppError(code: .invalidTaxonomy) }
                parentID = parent.parentID
            }
        }
        self.schemaVersion = schemaVersion; self.seedVersion = seedVersion; self.nodes = nodes
    }
    private enum CodingKeys: String, CodingKey { case schemaVersion, seedVersion, nodes }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(schemaVersion: c.decode(Int.self, forKey: .schemaVersion),
                      seedVersion: c.decode(String.self, forKey: .seedVersion), nodes: c.decode([TaxonomyNode].self, forKey: .nodes))
    }
}
