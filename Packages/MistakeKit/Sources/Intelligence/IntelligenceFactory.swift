import Foundation
import Contracts

public enum IntelligenceFactory {
    public static func make(configuration: IntelligenceConfiguration,
                            credentialStore: any CredentialStore = UnavailableCredentialStore()) throws -> IntelligenceServices {
        guard configuration.recognition.maxPixelDimension > 0,
              configuration.analysis.timeoutSeconds > 0 else { throw AppError(code: .unsupportedInput) }

        let vision = VisionOCRService()
        let modelOCR = ModelAPIOCRService(credentialStore: credentialStore)
        let baiduOCR = BaiduEducationOCRService(credentialStore: credentialStore)
        let glmOCR = GLMOCRService(credentialStore: credentialStore)
        let ocr = RoutingOCRService(vision: vision, model: modelOCR, baidu: baiduOCR, glm: glmOCR)

        let foundation = FoundationModelsAnalysisService()
        let modelAnalysis = ModelAPIAnalysisService(credentialStore: credentialStore)
        let analysis = RoutingAnalysisService(foundation: foundation, model: modelAnalysis)

        let value = RoutingMistakeValueService(model: ModelAPIMistakeValueService(credentialStore: credentialStore))
        let capabilities = CompositeCapabilityProvider(ocr: ocr, analysis: analysis, credentialStore: credentialStore)
        let curriculum = CurriculumQuantificationEngine().map { $0 as any CurriculumQuantificationService } ?? NoCurriculumQuantification()
        return IntelligenceServices(ocr: ocr, segmentation: HeuristicSegmentationService(), analysis: analysis,
                                     value: value, classification: KeywordClassificationService(), capabilities: capabilities,
                                     gradingMarkDetection: GradingMarkHeuristicsDetector(),
                                     curriculumQuantification: curriculum)
    }

    public static func makeTaxonomySeedProvider(resourceURL: URL) throws -> any TaxonomySeedProvider {
        try JSONTaxonomySeedProvider(resourceURL: resourceURL)
    }
}

private struct CompositeCapabilityProvider: CapabilityProvider, Sendable {
    let ocr: RoutingOCRService
    let analysis: RoutingAnalysisService
    let credentialStore: any CredentialStore

    func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        let languages = (try? await ocr.supportedLanguages()) ?? []
        let analysisReport = try await analysis.capabilities()
        let credentials = (try? await credentialStore.status()) ?? CredentialStatus(configured: [])
        let remoteOCRReady = credentials.contains(.ocrModelAPIKey)
            || credentials.contains(.glmAPIKey)
            || (credentials.contains(.baiduAPIKey) && credentials.contains(.baiduSecretKey))
        let valueReady = credentials.contains(.mistakeValueModelAPIKey)
        let fixed = [
            FeatureCapability(feature: .ocr, subjectID: "local-or-api", state: languages.isEmpty && !remoteOCRReady ? .unavailable : .available,
                              reason: remoteOCRReady ? "手机本地识别可用，已配置的联网识别也能使用。" : "使用手机本地识别，无需联网。",
                              supportedLanguages: languages),
            FeatureCapability(feature: .segmentation, subjectID: nil, state: .available,
                              reason: "自动按题号拆分每道题，之后可以手动调整。", supportedLanguages: []),
            FeatureCapability(feature: .classification, subjectID: nil, state: .available,
                              reason: "根据本地知识树推荐归类，由你确认。", supportedLanguages: []),
            FeatureCapability(feature: .mistakeValue, subjectID: "local-or-api", state: .available,
                              reason: valueReady ? "本地估算和已配置的服务商都可用。" : "本地估算复习价值，无需配置。", supportedLanguages: [])
        ]
        return CapabilityReport(checkedAt: Date(), features: fixed + analysisReport.features)
    }
}
