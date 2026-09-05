// Frozen contract 1.0.0. Changes require coordinated contract migration.
import Foundation

public enum MediaType: String, Codable, Sendable, Equatable, CaseIterable {
    case jpeg
    case png
    case heic
}

public enum ImageOrientation: String, Codable, Sendable, Equatable, CaseIterable {
    case up
    case upMirrored
    case down
    case downMirrored
    case left
    case leftMirrored
    case right
    case rightMirrored
}

public enum AssetRole: String, Codable, Sendable, Equatable, CaseIterable {
    case raw
    case working
    case derived
    case thumbnail
}

public enum RegionPurpose: String, Codable, Sendable, Equatable, CaseIterable {
    case stem
    case studentWork
    case referenceAnswer
    case diagram
    case unknown
}

public enum TransformOperation: String, Codable, Sendable, Equatable, CaseIterable {
    case rotateClockwise90
    case rotate180
    case rotateCounterClockwise90
    case crop
    case enhance
}

public enum ConfidenceSource: String, Codable, Sendable, Equatable, CaseIterable {
    case vision
    case rule
    case deviceModel
    case remoteService
    case user
}

public struct Confidence: Codable, Sendable, Equatable {
    public let value: Double
    public let source: ConfidenceSource
    public let calibrated: Bool

    public init(value: Double, source: ConfidenceSource, calibrated: Bool) {
        self.value = value
        self.source = source
        self.calibrated = calibrated
    }
}

public struct ServiceWarning: Codable, Sendable, Equatable {
    public let code: String
    public let message: String
    public let regionID: UUID?

    public init(code: String, message: String, regionID: UUID?) {
        self.code = code
        self.message = message
        self.regionID = regionID
    }
}

public struct ImageTransformMetadata: Codable, Sendable, Equatable {
    public let operation: TransformOperation?
    public let sourceRect: NormalizedRect?
    public let mappingToParent: CoordinateMapping?

    public init(operation: TransformOperation?, sourceRect: NormalizedRect?, mappingToParent: CoordinateMapping?) {
        self.operation = operation
        self.sourceRect = sourceRect
        self.mappingToParent = mappingToParent
    }
}

public struct ImageAsset: Codable, Sendable, Equatable {
    public let id: UUID
    public let parentAssetID: UUID?
    public let role: AssetRole
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let contentHash: String
    public let mediaType: MediaType
    public let relativePath: String
    public let transform: ImageTransformMetadata
    public let createdAt: Date

    public init(id: UUID, parentAssetID: UUID?, role: AssetRole, pixelWidth: Int, pixelHeight: Int, contentHash: String, mediaType: MediaType, relativePath: String, transform: ImageTransformMetadata, createdAt: Date) {
        self.id = id
        self.parentAssetID = parentAssetID
        self.role = role
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.contentHash = contentHash
        self.mediaType = mediaType
        self.relativePath = relativePath
        self.transform = transform
        self.createdAt = createdAt
    }
}

public struct ImportedPage: Codable, Sendable, Equatable {
    public let id: UUID
    public let bytes: Data
    public let mediaType: MediaType
    public let sourceName: String
    public let order: Int

    public init(id: UUID, bytes: Data, mediaType: MediaType, sourceName: String, order: Int) {
        self.id = id
        self.bytes = bytes
        self.mediaType = mediaType
        self.sourceName = sourceName
        self.order = order
    }
}

public struct ImagePayload: Codable, Sendable, Equatable {
    public let assetID: UUID
    public let bytes: Data
    public let mediaType: MediaType
    public let orientation: ImageOrientation
    public let pixelWidth: Int
    public let pixelHeight: Int

    public init(assetID: UUID, bytes: Data, mediaType: MediaType, orientation: ImageOrientation, pixelWidth: Int, pixelHeight: Int) {
        self.assetID = assetID
        self.bytes = bytes
        self.mediaType = mediaType
        self.orientation = orientation
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

public struct SourceRegion: Codable, Sendable, Equatable {
    public let id: UUID
    public let assetID: UUID
    public let normalizedRect: NormalizedRect
    public let purpose: RegionPurpose
    public let isUserConfirmed: Bool

    public init(id: UUID, assetID: UUID, normalizedRect: NormalizedRect, purpose: RegionPurpose, isUserConfirmed: Bool) {
        self.id = id
        self.assetID = assetID
        self.normalizedRect = normalizedRect
        self.purpose = purpose
        self.isUserConfirmed = isUserConfirmed
    }
}

public struct AssetTransaction: Codable, Sendable, Equatable {
    public let id: UUID
    public let createdAt: Date

    public init(id: UUID, createdAt: Date) {
        self.id = id
        self.createdAt = createdAt
    }
}

public struct ImportedAssets: Codable, Sendable, Equatable {
    public let raw: ImageAsset
    public let working: ImageAsset
    public let duplicateOfAssetID: UUID?

    public init(raw: ImageAsset, working: ImageAsset, duplicateOfAssetID: UUID?) {
        self.raw = raw
        self.working = working
        self.duplicateOfAssetID = duplicateOfAssetID
    }
}

public struct ImageTransformRequest: Codable, Sendable, Equatable {
    public let sourceAssetID: UUID
    public let operation: TransformOperation
    public let cropRect: NormalizedRect?
    public let affectedRegions: [SourceRegion]

    public init(sourceAssetID: UUID, operation: TransformOperation, cropRect: NormalizedRect?, affectedRegions: [SourceRegion]) {
        self.sourceAssetID = sourceAssetID
        self.operation = operation
        self.cropRect = cropRect
        self.affectedRegions = affectedRegions
    }
}

public struct ImageTransformResult: Codable, Sendable, Equatable {
    public let derivedAsset: ImageAsset
    public let sourceToDerived: CoordinateMapping?
    public let affectedRegions: [SourceRegion]
    public let warnings: [ServiceWarning]

    public init(derivedAsset: ImageAsset, sourceToDerived: CoordinateMapping?, affectedRegions: [SourceRegion], warnings: [ServiceWarning]) {
        self.derivedAsset = derivedAsset
        self.sourceToDerived = sourceToDerived
        self.affectedRegions = affectedRegions
        self.warnings = warnings
    }
}

public struct AssetRetentionToken: Codable, Sendable, Equatable {
    public let id: UUID
    public let assetIDs: [UUID]
    public let createdAt: Date

    public init(id: UUID, assetIDs: [UUID], createdAt: Date) {
        self.id = id
        self.assetIDs = assetIDs
        self.createdAt = createdAt
    }
}

public struct AssetCleanupResult: Codable, Sendable, Equatable {
    public let removedAssetIDs: [UUID]
    public let warnings: [ServiceWarning]

    public init(removedAssetIDs: [UUID], warnings: [ServiceWarning]) {
        self.removedAssetIDs = removedAssetIDs
        self.warnings = warnings
    }
}

public struct ThumbnailRequest: Codable, Sendable, Equatable {
    public let assetID: UUID
    public let maxPixelDimension: Int

    public init(assetID: UUID, maxPixelDimension: Int) {
        self.assetID = assetID
        self.maxPixelDimension = maxPixelDimension
    }
}

