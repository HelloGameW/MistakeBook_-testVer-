import Foundation

/// Bundles use protocol existentials so Workflow never imports implementation modules.
public struct IntelligenceServices: Sendable {
    public let ocr: any OCRService
    public let segmentation: any SegmentationService
    public let analysis: any AnalysisService
    public let value: any MistakeValueService
    public let classification: any ClassificationService
    public let capabilities: any CapabilityProvider
    public init(ocr: any OCRService, segmentation: any SegmentationService,
                analysis: any AnalysisService, value: any MistakeValueService,
                classification: any ClassificationService, capabilities: any CapabilityProvider) {
        self.ocr = ocr; self.segmentation = segmentation; self.analysis = analysis
        self.value = value; self.classification = classification; self.capabilities = capabilities
    }
}

public struct StorageServices: Sendable {
    public let repository: any MistakeRepository
    public let assets: any AssetStore
    public init(repository: any MistakeRepository, assets: any AssetStore) {
        self.repository = repository; self.assets = assets
    }
}
