import CoreGraphics
import CoreImage
import CryptoKit
import Foundation
import ImageIO
import Contracts

/// File-backed asset store. Raw bytes are immutable; working, derived and
/// thumbnail files are separate records with explicit parent relationships.
public actor FileAssetStore: AssetStore {
    private let configuration: StorageConfiguration
    private let fileManager = FileManager.default
    private let rootURL: URL
    private var assets: [UUID: ImageAsset] = [:]
    private var pendingByTransaction: [UUID: Set<UUID>] = [:]
    private var retentionTokens: [UUID: AssetRetentionToken] = [:]
    private var releasedRetentionIDs: Set<UUID> = []

    public init(configuration: StorageConfiguration) async throws {
        self.configuration = configuration
        self.rootURL = configuration.rootDirectory.standardizedFileURL
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        for folder in Self.folders {
            try fileManager.createDirectory(at: rootURL.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        if !configuration.inMemory {
            try loadIndex()
            try removeStagingDirectories()
        }
    }

    public func beginTransaction() async throws -> AssetTransaction {
        try Task.checkCancellation()
        let transaction = AssetTransaction(id: UUID(), createdAt: Date())
        pendingByTransaction[transaction.id] = []
        let staging = stagingURL(transaction.id)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: true)
        return transaction
    }

    public func importPage(page: ImportedPage, transaction: AssetTransaction) async throws -> ImportedAssets {
        try Task.checkCancellation()
        guard pendingByTransaction[transaction.id] != nil else { throw AppError(code: .expiredToken) }
        guard !page.bytes.isEmpty, page.bytes.count <= 100 * 1024 * 1024 else { throw AppError(code: .unsupportedInput) }
        guard let source = CGImageSourceCreateWithData(page.bytes as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0, Double(pixelWidth) * Double(pixelHeight) <= 100_000_000 else {
            throw AppError(code: .unsupportedInput)
        }

        let hash = Self.sha256(page.bytes)
        let duplicate = assets.values.first(where: { $0.role == .raw && $0.contentHash == hash })
        let rawID = UUID()
        let workingID = UUID()
        let rawRelative = "Assets/raw/\(rawID.uuidString).\(page.mediaType.rawValue)"
        let workingRelative = "Assets/working/\(workingID.uuidString).png"
        let now = Date()
        let raw = ImageAsset(id: rawID, parentAssetID: nil, role: .raw,
                             pixelWidth: pixelWidth, pixelHeight: pixelHeight,
                             contentHash: hash, mediaType: page.mediaType,
                             relativePath: rawRelative,
                             transform: ImageTransformMetadata(operation: nil, sourceRect: nil, mappingToParent: nil),
                             createdAt: now)
        guard let normalized = Self.normalizedImage(source: source, maxDimension: 4096),
              let normalizedBytes = Self.pngData(normalized) else { throw AppError(code: .unsupportedInput) }
        let working = ImageAsset(id: workingID, parentAssetID: rawID, role: .working,
                                 pixelWidth: normalized.width, pixelHeight: normalized.height,
                                 contentHash: Self.sha256(normalizedBytes),
                                 mediaType: .png, relativePath: workingRelative,
                                 transform: ImageTransformMetadata(operation: nil, sourceRect: nil, mappingToParent: nil),
                                 createdAt: now)
        let transactionFolder = stagingURL(transaction.id)
        let rawStage = transactionFolder.appendingPathComponent(rawRelative)
        let workingStage = transactionFolder.appendingPathComponent(workingRelative)
        try fileManager.createDirectory(at: rawStage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workingStage.deletingLastPathComponent(), withIntermediateDirectories: true)
        try page.bytes.write(to: rawStage, options: .atomic)
        try normalizedBytes.write(to: workingStage, options: .atomic)
        assets[rawID] = raw; assets[workingID] = working
        pendingByTransaction[transaction.id, default: []].formUnion([rawID, workingID])
        try persistIndex()
        return ImportedAssets(raw: raw, working: working, duplicateOfAssetID: duplicate?.id)
    }

    public func transform(request: ImageTransformRequest, transaction: AssetTransaction) async throws -> ImageTransformResult {
        try Task.checkCancellation()
        guard pendingByTransaction[transaction.id] != nil else { throw AppError(code: .expiredToken) }
        guard let sourceAsset = assets[request.sourceAssetID],
              let sourceURL = safeURL(relativePath: sourceAsset.relativePath) else { throw AppError(code: .assetMissing) }
        guard let sourceImage = try Self.loadCGImage(at: sourceURL) else {
            throw AppError(code: .assetMissing)
        }

        let output: CGImage
        switch request.operation {
        case .crop:
            guard let crop = request.cropRect else { throw AppError(code: .unsupportedInput) }
            let pixelRect = CGRect(x: crop.x * Double(sourceImage.width),
                                   y: crop.y * Double(sourceImage.height),
                                   width: crop.width * Double(sourceImage.width),
                                   height: crop.height * Double(sourceImage.height))
            guard let cropped = sourceImage.cropping(to: pixelRect.integral) else { throw AppError(code: .unsupportedInput) }
            output = cropped
        case .rotateClockwise90:
            guard let rotated = Self.rotated(sourceImage, clockwise: true) else { throw AppError(code: .internalFailure, isRetryable: true) }
            output = rotated
        case .rotateCounterClockwise90:
            guard let rotated = Self.rotated(sourceImage, clockwise: false) else { throw AppError(code: .internalFailure, isRetryable: true) }
            output = rotated
        case .rotate180:
            guard let rotated = Self.rotated180(sourceImage) else { throw AppError(code: .internalFailure, isRetryable: true) }
            output = rotated
        case .enhance:
            guard let enhanced = Self.enhanced(sourceImage) else { throw AppError(code: .internalFailure, isRetryable: true) }
            output = enhanced
        }

        let sourceToDerived = try Self.mapping(operation: request.operation, crop: request.cropRect)
        let mappingToParent = try Self.inverseMapping(operation: request.operation, crop: request.cropRect)
        // Encode once: the same bytes feed the content hash and the staged file.
        guard let derivedBytes = Self.pngData(output) else { throw AppError(code: .internalFailure, isRetryable: true) }
        let derivedID = UUID()
        let relative = "Assets/derived/\(derivedID.uuidString).png"
        let now = Date()
        let derived = ImageAsset(id: derivedID, parentAssetID: sourceAsset.id, role: .derived,
                                 pixelWidth: output.width, pixelHeight: output.height,
                                 contentHash: Self.sha256(derivedBytes), mediaType: .png,
                                 relativePath: relative,
                                 transform: ImageTransformMetadata(operation: request.operation,
                                                                    sourceRect: request.cropRect,
                                                                    mappingToParent: mappingToParent),
                                 createdAt: now)
        let stageURL = stagingURL(transaction.id).appendingPathComponent(relative)
        try fileManager.createDirectory(at: stageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try derivedBytes.write(to: stageURL, options: .atomic)
        assets[derivedID] = derived
        pendingByTransaction[transaction.id, default: []].insert(derivedID)
        let affected = request.affectedRegions.map { region in
            guard region.assetID == sourceAsset.id,
                  let mappedRect = Self.mapRect(region.normalizedRect, using: sourceToDerived) else { return region }
            return SourceRegion(id: region.id, assetID: derivedID, normalizedRect: mappedRect,
                                purpose: region.purpose, isUserConfirmed: region.isUserConfirmed)
        }
        try persistIndex()
        return ImageTransformResult(derivedAsset: derived, sourceToDerived: sourceToDerived,
                                    affectedRegions: affected, warnings: [])
    }

    public func metadata(assetID: UUID) async throws -> ImageAsset {
        try Task.checkCancellation()
        guard let asset = assets[assetID] else { throw AppError(code: .assetMissing) }
        return asset
    }

    public func loadImage(assetID: UUID) async throws -> ImagePayload {
        try Task.checkCancellation()
        guard let asset = assets[assetID], let url = safeURL(relativePath: asset.relativePath),
              let data = try? Data(contentsOf: url) else { throw AppError(code: .assetMissing) }
        return ImagePayload(assetID: assetID, bytes: data, mediaType: asset.mediaType,
                            orientation: .up, pixelWidth: asset.pixelWidth, pixelHeight: asset.pixelHeight)
    }

    public func thumbnail(request: ThumbnailRequest) async throws -> ImagePayload {
        try Task.checkCancellation()
        guard request.maxPixelDimension > 0, let sourceAsset = assets[request.assetID],
              let sourceURL = safeURL(relativePath: sourceAsset.relativePath),
              let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: request.maxPixelDimension
              ] as CFDictionary) else { throw AppError(code: .assetMissing) }
        let id = UUID()
        let relative = "Assets/thumbnail/\(id.uuidString).png"
        let url = rootURL.appendingPathComponent(relative)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Encode once: the same bytes feed the content hash and the file.
        guard let thumbnailBytes = Self.pngData(image) else { throw AppError(code: .internalFailure, isRetryable: true) }
        try thumbnailBytes.write(to: url, options: .atomic)
        let asset = ImageAsset(id: id, parentAssetID: sourceAsset.id, role: .thumbnail,
                               pixelWidth: image.width, pixelHeight: image.height,
                               contentHash: Self.sha256(thumbnailBytes), mediaType: .png,
                               relativePath: relative,
                               transform: ImageTransformMetadata(operation: nil, sourceRect: nil, mappingToParent: nil),
                               createdAt: Date())
        assets[id] = asset
        try persistIndex()
        guard let data = try? Data(contentsOf: url) else { throw AppError(code: .assetMissing) }
        return ImagePayload(assetID: id, bytes: data, mediaType: .png, orientation: .up,
                            pixelWidth: image.width, pixelHeight: image.height)
    }

    public func commit(transaction: AssetTransaction) async throws {
        try Task.checkCancellation()
        guard let ids = pendingByTransaction.removeValue(forKey: transaction.id) else { throw AppError(code: .expiredToken) }
        do {
            for id in ids {
                guard let asset = assets[id] else { continue }
                let source = stagingURL(transaction.id).appendingPathComponent(asset.relativePath)
                let destination = rootURL.appendingPathComponent(asset.relativePath)
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard !fileManager.fileExists(atPath: destination.path) else { throw AppError(code: .revisionConflict) }
                try fileManager.moveItem(at: source, to: destination)
                try applyFileAttributes(destination)
            }
            try? fileManager.removeItem(at: stagingURL(transaction.id))
            try persistIndex()
        } catch {
            pendingByTransaction[transaction.id] = ids
            throw AppError(code: .internalFailure, isRetryable: true)
        }
    }

    public func rollback(transaction: AssetTransaction) async throws {
        // Compensation must finish even when the importing task was cancelled.
        guard let ids = pendingByTransaction[transaction.id] else { return }
        for id in ids {
            if let asset = assets[id], let url = safeURL(relativePath: asset.relativePath), fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
        let staging = stagingURL(transaction.id)
        if fileManager.fileExists(atPath: staging.path) { try fileManager.removeItem(at: staging) }
        for id in ids { assets.removeValue(forKey: id) }
        pendingByTransaction.removeValue(forKey: transaction.id)
        try persistIndex()
    }

    public func cleanup(referencedAssetIDs: [UUID]) async throws -> AssetCleanupResult {
        try Task.checkCancellation()
        var keep = Set(referencedAssetIDs)
        keep.formUnion(retentionTokens.values.flatMap(\.assetIDs))
        keep.formUnion(pendingByTransaction.values.flatMap { $0 })
        var changed = true
        while changed {
            changed = false
            for id in keep {
                if let parent = assets[id]?.parentAssetID, keep.insert(parent).inserted { changed = true }
            }
        }
        var removed: [UUID] = []
        let candidates = assets.keys.filter { !keep.contains($0) }
        for id in candidates {
            guard let asset = assets[id] else { continue }
            guard let url = safeURL(relativePath: asset.relativePath) else { throw AppError(code: .unsupportedInput) }
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            assets.removeValue(forKey: id); removed.append(id)
        }
        try persistIndex()
        return AssetCleanupResult(removedAssetIDs: removed, warnings: [])
    }

    public func acquireRetention(assetIDs: [UUID]) async throws -> AssetRetentionToken {
        try Task.checkCancellation()
        let missing = assetIDs.first(where: { assets[$0] == nil })
        guard missing == nil else { throw AppError(code: .assetMissing) }
        let token = AssetRetentionToken(id: UUID(), assetIDs: assetIDs, createdAt: Date())
        retentionTokens[token.id] = token
        return token
    }

    public func releaseRetention(token: AssetRetentionToken) async throws {
        // Release is idempotent compensation, including on cancellation.
        if releasedRetentionIDs.contains(token.id) { return }
        retentionTokens.removeValue(forKey: token.id)
        releasedRetentionIDs.insert(token.id)
    }

    public func clearAll() async throws {
        try Task.checkCancellation()
        for folder in Self.folders {
            let url = rootURL.appendingPathComponent(folder)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
        assets.removeAll(); pendingByTransaction.removeAll(); retentionTokens.removeAll(); releasedRetentionIDs.removeAll()
        try persistIndex()
    }

    private static let folders = ["Assets/raw", "Assets/working", "Assets/derived", "Assets/thumbnail", ".staging"]
    private var indexURL: URL { rootURL.appendingPathComponent("asset-index.json") }
    private func stagingURL(_ id: UUID) -> URL { rootURL.appendingPathComponent(".staging").appendingPathComponent(id.uuidString) }

    private func safeURL(relativePath: String) -> URL? {
        let rootPath = rootURL.resolvingSymlinksInPath().standardizedFileURL.path
        let url = rootURL.appendingPathComponent(relativePath).resolvingSymlinksInPath().standardizedFileURL
        guard !relativePath.hasPrefix("/"), url.path.hasPrefix(rootPath + "/") else { return nil }
        return url
    }

    private func loadIndex() throws {
        guard fileManager.fileExists(atPath: indexURL.path) else { return }
        do { assets = try ContractJSON.decoder().decode([UUID: ImageAsset].self, from: Data(contentsOf: indexURL)) }
        catch { throw AppError(code: .internalFailure, isRetryable: true) }
    }

    private func persistIndex() throws {
        guard !configuration.inMemory else { return }
        let pending = Set(pendingByTransaction.values.flatMap { $0 })
        let data = try ContractJSON.encoder().encode(assets.filter { !pending.contains($0.key) })
        try data.write(to: indexURL, options: .atomic)
        try applyFileAttributes(indexURL)
    }

    private func removeStagingDirectories() throws {
        let staging = rootURL.appendingPathComponent(".staging")
        for url in try fileManager.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            try fileManager.removeItem(at: url)
        }
        // Keep metadata for committed-but-missing files so loadImage reports assetMissing.
        // Silently dropping it would erase the evidence needed to diagnose damaged imports.
        try persistIndex()
    }

    private func applyFileAttributes(_ url: URL) throws {
        if configuration.excludeFromBackup {
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        }
#if os(iOS)
        let protection: FileProtectionType = configuration.protection == .complete ? .complete : .completeUntilFirstUserAuthentication
        try fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
#endif
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func normalizedImage(source: CGImageSource, maxDimension: Int) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension
        ] as CFDictionary)
    }

    private static func pngData(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, "public.png" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func loadCGImage(at url: URL) throws -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func enhanced(_ image: CGImage) -> CGImage? {
        let input = CIImage(cgImage: image)
        guard let filter = CIFilter(name: "CIColorControls") else { return image }
        filter.setValue(input, forKey: kCIInputImageKey); filter.setValue(1.08, forKey: kCIInputContrastKey)
        filter.setValue(0.02, forKey: kCIInputBrightnessKey)
        guard let output = filter.outputImage else { return nil }
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }

    private static func rotated(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let output = CIImage(cgImage: image).oriented(forExifOrientation: clockwise ? 6 : 8)
        return CIContext(options: nil).createCGImage(output, from: output.extent)
    }

    private static func rotated180(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.translateBy(x: CGFloat(image.width), y: CGFloat(image.height)); context.rotate(by: .pi)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    private static func mapping(operation: TransformOperation, crop: NormalizedRect?) throws -> CoordinateMapping {
        switch operation {
        case .crop:
            guard let crop else { throw AppError(code: .unsupportedInput) }
            return try CoordinateMapping(values: [1 / crop.width, 0, -crop.x / crop.width,
                                                   0, 1 / crop.height, -crop.y / crop.height, 0, 0, 1])
        case .rotateClockwise90: return try CoordinateMapping(values: [0, -1, 1, 1, 0, 0, 0, 0, 1])
        case .rotateCounterClockwise90: return try CoordinateMapping(values: [0, 1, 0, -1, 0, 1, 0, 0, 1])
        case .rotate180: return try CoordinateMapping(values: [-1, 0, 1, 0, -1, 1, 0, 0, 1])
        case .enhance: return .identity
        }
    }

    private static func inverseMapping(operation: TransformOperation, crop: NormalizedRect?) throws -> CoordinateMapping {
        switch operation {
        case .crop:
            guard let crop else { throw AppError(code: .unsupportedInput) }
            return try CoordinateMapping(values: [crop.width, 0, crop.x, 0, crop.height, crop.y, 0, 0, 1])
        case .rotateClockwise90: return try CoordinateMapping(values: [0, 1, 0, -1, 0, 1, 0, 0, 1])
        case .rotateCounterClockwise90: return try CoordinateMapping(values: [0, -1, 1, 1, 0, 0, 0, 0, 1])
        case .rotate180: return try CoordinateMapping(values: [-1, 0, 1, 0, -1, 1, 0, 0, 1])
        case .enhance: return .identity
        }
    }

    private static func mapRect(_ rect: NormalizedRect, using mapping: CoordinateMapping) -> NormalizedRect? {
        let points = [(rect.x, rect.y), (rect.x + rect.width, rect.y),
                      (rect.x, rect.y + rect.height), (rect.x + rect.width, rect.y + rect.height)].map { point -> (Double, Double) in
            let m = mapping.values
            let denominator = m[6] * point.0 + m[7] * point.1 + m[8]
            let x = (m[0] * point.0 + m[1] * point.1 + m[2]) / denominator
            let y = (m[3] * point.0 + m[4] * point.1 + m[5]) / denominator
            return (x, y)
        }
        let x = max(0, min(1, points.map(\.0).min() ?? 0)); let y = max(0, min(1, points.map(\.1).min() ?? 0))
        let right = min(1, points.map(\.0).max() ?? 1); let bottom = min(1, points.map(\.1).max() ?? 1)
        return try? NormalizedRect(x: x, y: y, width: right - x, height: bottom - y)
    }
}
