import Foundation
import Contracts

public struct RoutingOCRService: OCRService, Sendable {
    let vision: VisionOCRService
    let model: ModelAPIOCRService
    let baidu: BaiduEducationOCRService

    public init(vision: VisionOCRService = VisionOCRService(), model: ModelAPIOCRService,
                baidu: BaiduEducationOCRService) {
        self.vision = vision; self.model = model; self.baidu = baidu
    }

    public func supportedLanguages() async throws -> [String] {
        var values = (try? await vision.supportedLanguages()) ?? []
        values.append(contentsOf: ["zh-Hans", "en-US"])
        return Array(Set(values)).sorted()
    }

    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        switch options.processingMode ?? .local {
        case .local:
            return try await vision.recognize(image: image, options: options)
        case .api:
            return try await remote(provider: options.provider ?? .modelAPI, image: image, options: options)
        case .automatic:
            do {
                let local = try await vision.recognize(image: image, options: options)
                if Self.isUsable(local) { return local }
            } catch is CancellationError { throw CancellationError() }
            catch { /* configured remote provider is the fallback */ }
            let provider = options.provider ?? .baiduEducation
            if provider == .appleVision { return try await vision.recognize(image: image, options: options) }
            return try await remote(provider: provider, image: image, options: options)
        }
    }

    private func remote(provider: OCRProviderKind, image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        switch provider {
        case .appleVision: return try await vision.recognize(image: image, options: options)
        case .modelAPI: return try await model.recognize(image: image, options: options)
        case .baiduEducation: return try await baidu.recognize(image: image, options: options)
        }
    }

    private static func isUsable(_ page: RecognizedPage) -> Bool {
        let meaningful = page.lines.filter { !$0.rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard meaningful.count >= 2, meaningful.reduce(0, { $0 + $1.rawText.count }) >= 20 else { return false }
        let confidences = meaningful.compactMap(\.confidence?.value)
        return confidences.isEmpty || confidences.reduce(0, +) / Double(confidences.count) >= 0.55
    }
}

public struct RoutingAnalysisService: AnalysisService, Sendable {
    let rules: RuleBasedAnalysisService
    let foundation: FoundationModelsAnalysisService
    let model: ModelAPIAnalysisService

    public init(rules: RuleBasedAnalysisService = RuleBasedAnalysisService(),
                foundation: FoundationModelsAnalysisService = FoundationModelsAnalysisService(),
                model: ModelAPIAnalysisService) {
        self.rules = rules; self.foundation = foundation; self.model = model
    }

    public func analyze(snapshot: RecordContentSnapshot, options: AnalysisOptions) async throws -> AnalysisResult {
        let provider = options.provider ?? (options.useEnhancedModel ? .appleFoundationModels : .localRules)
        switch options.processingMode ?? .local {
        case .local:
            return try await local(provider: provider, snapshot: snapshot, options: options)
        case .api:
            return provider == .modelAPI
                ? try await model.analyze(snapshot: snapshot, options: options)
                : try await local(provider: provider, snapshot: snapshot, options: options)
        case .automatic:
            let localOptions = AnalysisOptions(useEnhancedModel: true, language: options.language,
                                               timeoutSeconds: options.timeoutSeconds, processingMode: .local,
                                               provider: .appleFoundationModels, modelAPI: options.modelAPI)
            if provider == .modelAPI {
                let report = try? await foundation.capabilities()
                let enhancedReady = report?.features.contains(where: { $0.feature == .enhancedAnalysis && $0.state == .available }) == true
                if !enhancedReady {
                    do { return try await model.analyze(snapshot: snapshot, options: options) }
                    catch is CancellationError { throw CancellationError() }
                    catch { return try await rules.analyze(snapshot: snapshot, options: localOptions) }
                }
            }
            return try await foundation.analyze(snapshot: snapshot, options: localOptions)
        }
    }

    private func local(provider: AnalysisProviderKind, snapshot: RecordContentSnapshot, options: AnalysisOptions) async throws -> AnalysisResult {
        switch provider {
        case .localRules: return try await rules.analyze(snapshot: snapshot, options: options)
        case .appleFoundationModels: return try await foundation.analyze(snapshot: snapshot, options: options)
        case .modelAPI: return try await rules.analyze(snapshot: snapshot, options: options)
        }
    }

    public func capabilities() async throws -> CapabilityReport {
        let local = try await foundation.capabilities()
        let remote = try await model.capabilities()
        return CapabilityReport(checkedAt: Date(), features: local.features + remote.features)
    }
}

public struct RoutingMistakeValueService: MistakeValueService, Sendable {
    let local: LocalHeuristicMistakeValueService
    let model: ModelAPIMistakeValueService
    public init(local: LocalHeuristicMistakeValueService = LocalHeuristicMistakeValueService(), model: ModelAPIMistakeValueService) {
        self.local = local; self.model = model
    }

    public func evaluate(snapshot: RecordContentSnapshot, analysis: AnalysisResult?, options: ValueAnalysisOptions) async throws -> MistakeValueResult {
        switch options.processingMode ?? .local {
        case .local:
            return try await local.evaluate(snapshot: snapshot, analysis: analysis, options: options)
        case .api:
            return options.provider == .modelAPI
                ? try await model.evaluate(snapshot: snapshot, analysis: analysis, options: options)
                : try await local.evaluate(snapshot: snapshot, analysis: analysis, options: options)
        case .automatic:
            guard options.provider == .modelAPI else { return try await local.evaluate(snapshot: snapshot, analysis: analysis, options: options) }
            do { return try await model.evaluate(snapshot: snapshot, analysis: analysis, options: options) }
            catch is CancellationError { throw CancellationError() }
            catch { return try await local.evaluate(snapshot: snapshot, analysis: analysis, options: options) }
        }
    }
}

public struct UnavailableCredentialStore: CredentialStore, Sendable {
    public init() {}
    public func read(kind: CredentialKind) async throws -> String? { nil }
    public func write(kind: CredentialKind, value: String) async throws { throw AppError(code: .featureUnavailable) }
    public func remove(kind: CredentialKind) async throws {}
    public func removeAll() async throws {}
    public func status() async throws -> CredentialStatus { CredentialStatus(configured: []) }
}
