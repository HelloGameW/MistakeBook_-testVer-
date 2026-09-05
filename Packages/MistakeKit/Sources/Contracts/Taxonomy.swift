// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

public enum TaxonomyOrigin: String, Codable, Sendable, Equatable, CaseIterable {
    case seed
    case user
}

public enum AssignmentState: String, Codable, Sendable, Equatable, CaseIterable {
    case unclassified
    case suggested
    case automatic
    case userConfirmed
}

public enum AssignedBy: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case rule
    case deviceModel
    case user
}

public enum TaxonomyDeleteMode: String, Codable, Sendable, Equatable, CaseIterable {
    case rejectIfReferenced
    case moveToParent
    case makeUnclassified
}

/// userModifiedFields contains name, parentID, aliases or isActive; seed upgrades preserve these fields.
public struct TaxonomyNode: Codable, Sendable, Equatable {
    public let id: String
    public let parentID: String?
    public let name: String
    public let subjectID: String
    public let aliases: [String]
    public let origin: TaxonomyOrigin
    public let isActive: Bool
    public let version: Int
    public let userModifiedFields: [String]

    public init(id: String, parentID: String?, name: String, subjectID: String, aliases: [String], origin: TaxonomyOrigin, isActive: Bool, version: Int, userModifiedFields: [String]) {
        self.id = id
        self.parentID = parentID
        self.name = name
        self.subjectID = subjectID
        self.aliases = aliases
        self.origin = origin
        self.isActive = isActive
        self.version = version
        self.userModifiedFields = userModifiedFields
    }
}

public struct ClassificationCandidate: Codable, Sendable, Equatable {
    public let nodeID: String
    public let score: Double?
    public let basis: String
    public let evidence: [Evidence]
    public let source: AssignedBy
    public let calibrated: Bool
    public let validationPolicyID: String?

    public init(nodeID: String, score: Double?, basis: String, evidence: [Evidence], source: AssignedBy, calibrated: Bool, validationPolicyID: String?) {
        self.nodeID = nodeID
        self.score = score
        self.basis = basis
        self.evidence = evidence
        self.source = source
        self.calibrated = calibrated
        self.validationPolicyID = validationPolicyID
    }
}

public struct ClassificationResult: Codable, Sendable, Equatable {
    public let subjectID: String?
    public let candidates: [ClassificationCandidate]
    public let primaryNodeID: String?
    public let assignmentState: AssignmentState
    public let assignedBy: AssignedBy
    public let taxonomyVersion: String
    public let inputContentRevision: Int
    public let suggestedTags: [String]

    public init(subjectID: String?, candidates: [ClassificationCandidate], primaryNodeID: String?, assignmentState: AssignmentState, assignedBy: AssignedBy, taxonomyVersion: String, inputContentRevision: Int, suggestedTags: [String]) {
        self.subjectID = subjectID
        self.candidates = candidates
        self.primaryNodeID = primaryNodeID
        self.assignmentState = assignmentState
        self.assignedBy = assignedBy
        self.taxonomyVersion = taxonomyVersion
        self.inputContentRevision = inputContentRevision
        self.suggestedTags = suggestedTags
    }
}

public struct TaxonomySnapshot: Codable, Sendable, Equatable {
    public let version: String
    public let nodes: [TaxonomyNode]

    public init(version: String, nodes: [TaxonomyNode]) {
        self.version = version
        self.nodes = nodes
    }
}

public struct AutoArchiveRule: Codable, Sendable, Equatable {
    public let id: String
    public let nodeID: String
    public let minimumScore: Double?
    public let validationEvidenceID: String

    public init(id: String, nodeID: String, minimumScore: Double?, validationEvidenceID: String) {
        self.id = id
        self.nodeID = nodeID
        self.minimumScore = minimumScore
        self.validationEvidenceID = validationEvidenceID
    }
}

/// Empty enabledRules means suggestions only; no magic confidence threshold.
public struct AutoArchivePolicy: Codable, Sendable, Equatable {
    public let version: String
    public let enabledRules: [AutoArchiveRule]

    public init(version: String, enabledRules: [AutoArchiveRule]) {
        self.version = version
        self.enabledRules = enabledRules
    }
}

public struct ClassificationOptions: Codable, Sendable, Equatable {
    public let policy: AutoArchivePolicy
    public let useEnhancedModel: Bool

    public init(policy: AutoArchivePolicy, useEnhancedModel: Bool) {
        self.policy = policy
        self.useEnhancedModel = useEnhancedModel
    }
}

public struct TaxonomyNodePatch: Codable, Sendable, Equatable {
    public let expectedVersion: Int
    public let name: FieldChange<String>
    public let parentID: FieldChange<String?>
    public let aliases: FieldChange<[String]>
    public let isActive: FieldChange<Bool>

    public init(expectedVersion: Int, name: FieldChange<String>, parentID: FieldChange<String?>, aliases: FieldChange<[String]>, isActive: FieldChange<Bool>) {
        self.expectedVersion = expectedVersion
        self.name = name
        self.parentID = parentID
        self.aliases = aliases
        self.isActive = isActive
    }
}

public struct TaxonomyDeleteRequest: Codable, Sendable, Equatable {
    public let nodeID: String
    public let expectedTaxonomyVersion: String
    public let mode: TaxonomyDeleteMode

    public init(nodeID: String, expectedTaxonomyVersion: String, mode: TaxonomyDeleteMode) {
        self.nodeID = nodeID
        self.expectedTaxonomyVersion = expectedTaxonomyVersion
        self.mode = mode
    }
}

public struct ClassificationSelection: Codable, Sendable, Equatable {
    public let primaryNodeID: String?
    public let tags: [String]
    public let expectedRecordRevision: Int
    public let expectedTaxonomyVersion: String

    public init(primaryNodeID: String?, tags: [String], expectedRecordRevision: Int, expectedTaxonomyVersion: String) {
        self.primaryNodeID = primaryNodeID
        self.tags = tags
        self.expectedRecordRevision = expectedRecordRevision
        self.expectedTaxonomyVersion = expectedTaxonomyVersion
    }
}

