import Foundation

/// High-level execution policy. `.automatic` prefers private/local processing and
/// can fall back to configured API providers when the local result is unavailable
/// or obviously low quality.
public enum ProcessingMode: String, Codable, Sendable, Equatable, CaseIterable {
    case local
    case api
    case automatic
}

public enum OCRProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case appleVision
    case modelAPI
    case baiduEducation
    /// 智谱 BigModel GLM OCR（工具 API，`tool_type=hand_write`）。
    case glm
}

public enum AnalysisProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case localRules
    case appleFoundationModels
    case modelAPI
}

public enum MistakeValueProviderKind: String, Codable, Sendable, Equatable, CaseIterable {
    case localHeuristic
    case modelAPI
}

/// Non-secret configuration for an OpenAI-compatible Chat Completions endpoint.
/// API keys are intentionally stored separately through `CredentialStore`.
public struct ModelAPIConfiguration: Codable, Sendable, Equatable {
    public let baseURL: String
    public let endpointPath: String
    public let model: String
    public let timeoutSeconds: Double

    public init(baseURL: String, endpointPath: String = "/chat/completions", model: String, timeoutSeconds: Double = 30) {
        self.baseURL = baseURL
        self.endpointPath = endpointPath
        self.model = model
        self.timeoutSeconds = timeoutSeconds
    }

    /// Current DeepSeek OpenAI-compatible presets. The text preset is used for
    /// analysis/value scoring; the vision preset is required for image OCR.
    public static var deepSeekText: ModelAPIConfiguration {
        ModelAPIConfiguration(baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash")
    }

    public static var deepSeekVision: ModelAPIConfiguration {
        ModelAPIConfiguration(baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash-vision-exp")
    }

    public var isDeepSeek: Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "deepseek.com" || host.hasSuffix(".deepseek.com")
    }

    public var isDeepSeekVisionModel: Bool {
        model.lowercased() == "deepseek-v4-flash-vision-exp"
    }
}

public enum BaiduEducationStrategy: String, Codable, Sendable, Equatable, CaseIterable {
    case automatic
    case paperCut
    case documentAnalysis
}

/// Non-secret configuration for Baidu Education OCR.
public struct BaiduEducationConfiguration: Codable, Sendable, Equatable {
    public let strategy: BaiduEducationStrategy
    public let languageType: String
    public let detectDirection: Bool
    public let recognizeFormula: Bool
    public let layoutAnalysis: Bool
    public let mixedHandwriting: Bool

    public init(strategy: BaiduEducationStrategy = .automatic,
                languageType: String = "CHN_ENG",
                detectDirection: Bool = true,
                recognizeFormula: Bool = true,
                layoutAnalysis: Bool = true,
                mixedHandwriting: Bool = true) {
        self.strategy = strategy
        self.languageType = languageType
        self.detectDirection = detectDirection
        self.recognizeFormula = recognizeFormula
        self.layoutAnalysis = layoutAnalysis
        self.mixedHandwriting = mixedHandwriting
    }
}

public enum CredentialKind: String, Codable, Sendable, Equatable, CaseIterable {
    case ocrModelAPIKey
    case glmAPIKey
    case analysisModelAPIKey
    case mistakeValueModelAPIKey
    case baiduAPIKey
    case baiduSecretKey
}

/// Contains presence only. Secret values are never surfaced by settings reads.
public struct CredentialStatus: Codable, Sendable, Equatable {
    public let configured: [CredentialKind]

    public init(configured: [CredentialKind]) {
        self.configured = configured
    }

    public func contains(_ kind: CredentialKind) -> Bool { configured.contains(kind) }
}
