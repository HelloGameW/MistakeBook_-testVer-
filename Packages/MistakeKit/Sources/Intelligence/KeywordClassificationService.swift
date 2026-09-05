import Foundation
import Contracts

/// Keyword/alias ranking over the supplied taxonomy. It never invents node IDs
/// and intentionally emits suggestions, not automatic assignments.
public struct KeywordClassificationService: ClassificationService, Sendable {
    public init() {}

    public func classify(snapshot: RecordContentSnapshot, taxonomy: TaxonomySnapshot,
                         options: ClassificationOptions) async throws -> ClassificationResult {
        try Task.checkCancellation()
        let validNodes = try Self.validNodes(taxonomy.nodes)
        let text = [snapshot.stem.displayText, snapshot.studentWork.displayText,
                    snapshot.referenceAnswer?.displayText ?? ""].joined(separator: " ")
        let normalized = Self.normalized(text)
        let subjectRoots = validNodes.filter { $0.parentID == nil && $0.isActive }
        let subject = subjectRoots
            .map { ($0, Self.score(node: $0, text: normalized)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?.0
        let scoped = validNodes.filter { node in
            guard node.isActive else { return false }
            if let subject { return node.subjectID == subject.id }
            return node.parentID != nil
        }
        let scored = scoped.compactMap { node -> (TaxonomyNode, Double)? in
            let score = Self.score(node: node, text: normalized)
            return score > 0 ? (node, score) : nil
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? lhs.0.id < rhs.0.id : lhs.1 > rhs.1
        }
        let evidence = Self.evidence(snapshot: snapshot)
        let candidates = scored.prefix(5).map { node, score in
            ClassificationCandidate(nodeID: node.id, score: score,
                                    basis: "题干/作答命中节点名称或别名；score 仅用于排序，未校准。",
                                    evidence: evidence, source: .rule, calibrated: false,
                                    validationPolicyID: nil)
        }
        return ClassificationResult(subjectID: subject?.id, candidates: Array(candidates),
                                    primaryNodeID: candidates.first?.nodeID,
                                    assignmentState: candidates.isEmpty ? .unclassified : .suggested,
                                    assignedBy: candidates.isEmpty ? .none : .rule,
                                    taxonomyVersion: taxonomy.version,
                                    inputContentRevision: snapshot.contentRevision,
                                    suggestedTags: Array(candidates.dropFirst().prefix(2).map(\.nodeID)))
    }

    private static func validNodes(_ nodes: [TaxonomyNode]) throws -> [TaxonomyNode] {
        let ids = Set(nodes.map(\.id))
        guard ids.count == nodes.count else { throw AppError(code: .invalidTaxonomy) }
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        for node in nodes {
            guard node.isActive, !node.name.isEmpty,
                  let root = byID[node.subjectID], root.parentID == nil,
                  root.subjectID == root.id else { continue }
            var visited: Set<String> = [node.id]
            var parent = node.parentID
            while let parentID = parent {
                guard let parentNode = byID[parentID], parentNode.subjectID == node.subjectID,
                      visited.insert(parentID).inserted else { throw AppError(code: .invalidTaxonomy) }
                parent = parentNode.parentID
            }
        }
        return nodes
    }

    private static func score(node: TaxonomyNode, text: String) -> Double {
        let terms = ([node.name] + node.aliases).map(normalized).filter { $0.count >= 2 }
        guard !terms.isEmpty else { return 0 }
        return terms.reduce(0) { partial, term in partial + (text.contains(term) ? 1 : 0) }
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "zh_CN"))
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    private static func evidence(snapshot: RecordContentSnapshot) -> [Evidence] {
        guard let region = snapshot.sourceRegions.first else { return [] }
        let line = snapshot.ocrLines.first(where: { $0.regionID == region.id }) ?? snapshot.ocrLines.first
        return [Evidence(regionID: region.id, lineID: line?.id,
                         quote: line.map { String($0.rawText.prefix(240)) }, evidenceSource: .student)]
    }
}
