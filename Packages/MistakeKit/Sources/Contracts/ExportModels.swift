// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

public enum ExportMode: String, Codable, Sendable, Equatable, CaseIterable {
    case practice
    case withSolutions
}

public enum BlankSpace: String, Codable, Sendable, Equatable, CaseIterable {
    case none
    case small
    case medium
    case large
}

public enum ExportSort: String, Codable, Sendable, Equatable, CaseIterable {
    case selectionOrder
    case subjectAndTaxonomy
}

public enum PageSize: String, Codable, Sendable, Equatable, CaseIterable {
    case a4
}

public enum ExportImageDisposition: String, Codable, Sendable, Equatable, CaseIterable {
    case includeFullImage
    case crop
    case exclude
}

public enum AnswerRisk: String, Codable, Sendable, Equatable, CaseIterable {
    case unknown
    case mayContainAnswer
    case userConfirmedClean
}

public struct ExportImageDecision: Codable, Sendable, Equatable {
    public let regionID: UUID
    public let assetID: UUID
    public let disposition: ExportImageDisposition
    public let cropRect: NormalizedRect?
    public let answerRisk: AnswerRisk
    public let userConfirmed: Bool

    public init(regionID: UUID, assetID: UUID, disposition: ExportImageDisposition, cropRect: NormalizedRect?, answerRisk: AnswerRisk, userConfirmed: Bool) {
        self.regionID = regionID
        self.assetID = assetID
        self.disposition = disposition
        self.cropRect = cropRect
        self.answerRisk = answerRisk
        self.userConfirmed = userConfirmed
    }
}

public struct ExportRecord: Codable, Sendable, Equatable {
    public let record: MistakeRecord
    public let version: RecordVersion
    public let classificationPath: [String]
    public let images: [ExportImageDecision]

    public init(record: MistakeRecord, version: RecordVersion, classificationPath: [String], images: [ExportImageDecision]) {
        self.record = record
        self.version = version
        self.classificationPath = classificationPath
        self.images = images
    }
}

/// Value-only frozen final order; exporter must not requery records or taxonomy.
public struct ExportSnapshot: Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date
    public let records: [ExportRecord]
    public let retentionToken: AssetRetentionToken
    public let options: ExportOptions

    public init(id: UUID, createdAt: Date, records: [ExportRecord], retentionToken: AssetRetentionToken, options: ExportOptions) {
        self.id = id
        self.createdAt = createdAt
        self.records = records
        self.retentionToken = retentionToken
        self.options = options
    }
}

public struct ExportRequest: Codable, Sendable, Equatable {
    public let selection: RecordSelection
    public let options: ExportOptions
    public let imageDecisions: [ExportImageDecision]

    public init(selection: RecordSelection, options: ExportOptions, imageDecisions: [ExportImageDecision]) {
        self.selection = selection
        self.options = options
        self.imageDecisions = imageDecisions
    }
}

public struct ExportSummary: Codable, Sendable, Equatable {
    public let recordCount: Int
    public let pageCount: Int
    public let warnings: [ServiceWarning]

    public init(recordCount: Int, pageCount: Int, warnings: [ServiceWarning]) {
        self.recordCount = recordCount
        self.pageCount = pageCount
        self.warnings = warnings
    }
}

/// File remains valid until releaseExport, explicit cleanup or next-launch stale-file cleanup.
public struct ExportArtifact: Codable, Sendable, Equatable {
    public let id: UUID
    public let fileURL: URL
    public let summary: ExportSummary
    public let createdAt: Date

    public init(id: UUID, fileURL: URL, summary: ExportSummary, createdAt: Date) {
        self.id = id
        self.fileURL = fileURL
        self.summary = summary
        self.createdAt = createdAt
    }
}

