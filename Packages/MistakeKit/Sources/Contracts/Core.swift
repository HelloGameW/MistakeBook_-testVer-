import Foundation

public enum ContractSchema {
    public static let version = "1.1.0"
    public static let schemaVersion = 1

    public static func requireSupported(_ version: Int) throws {
        guard version == schemaVersion else {
            throw AppError(code: .unsupportedSchemaVersion)
        }
    }
}

public enum AppErrorCode: String, Codable, Sendable, Equatable, CaseIterable {
    case permissionDenied, unsupportedInput, unsupportedLanguage, modelUnavailable
    case invalidModelOutput, storageFull, assetMissing, revisionConflict, invalidTaxonomy
    case cancelled, internalFailure, featureUnavailable, unsupportedSchemaVersion
    case invalidConfirmation, notFound, expiredToken
    case invalidConfiguration, authenticationFailed, networkUnavailable, rateLimited
}

public struct AppError: Error, Codable, Sendable, Equatable, LocalizedError {
    public let code: AppErrorCode
    /// Opaque correlation ID only. Do not include student text, paths, names or underlying descriptions.
    public let logID: String
    public let isRetryable: Bool

    public init(code: AppErrorCode, logID: String = UUID().uuidString, isRetryable: Bool = false) {
        self.code = code
        self.logID = logID
        self.isRetryable = isRetryable
    }

    public var localizationKey: String { "error.\(code.rawValue)" }
    public var errorDescription: String? { displayMessage }
    public var displayMessage: String {
        switch code {
        case .permissionDenied: "尚未获得权限，可改用文件导入。"
        case .unsupportedInput: "无法处理此输入，请检查图片或填写内容。"
        case .unsupportedLanguage: "设备暂不支持所选识别语言。"
        case .modelUnavailable: "设备增强模型尚不可用，可使用基础整理功能。"
        case .invalidModelOutput: "分析结果未通过校验，请人工确认。"
        case .storageFull: "存储空间不足，请释放空间后重试。"
        case .assetMissing: "找不到关联图片，请检查原始素材。"
        case .revisionConflict: "内容已发生变化，请重新载入后保存。"
        case .invalidTaxonomy: "知识树变更无效或仍有记录引用。"
        case .cancelled: "操作已取消，已保存的内容仍可使用。"
        case .internalFailure: "操作未完成，请重试并保留问题编号。"
        case .featureUnavailable: "此功能尚未接入正式实现。"
        case .unsupportedSchemaVersion: "数据版本不受支持，请使用兼容版本。"
        case .invalidConfirmation: "清空确认无效，请重新确认。"
        case .notFound: "记录不存在或已被删除。"
        case .expiredToken: "操作凭据已失效，请重新操作。"
        case .invalidConfiguration: "API 配置不完整或地址无效，请检查设置。"
        case .authenticationFailed: "API 凭据无效或已失效，请重新填写。"
        case .networkUnavailable: "网络服务暂不可用，可切换到本地模式或稍后重试。"
        case .rateLimited: "API 请求过于频繁或额度不足，请稍后重试。"
        }
    }

    /// Implementations must propagate cancellation; this helper is for persisted error DTOs.
    public static func normalized(_ error: any Error, logID: String = UUID().uuidString) -> AppError {
        if let error = error as? AppError { return error }
        if error is CancellationError { return AppError(code: .cancelled, logID: logID) }
        return AppError(code: .internalFailure, logID: logID, isRetryable: true)
    }
}

/// Stable wire format: {"kind":"unchanged"} or {"kind":"set","value":...}.
/// FieldChange<T?>.set(nil) explicitly clears the field; missing/unchanged preserves it.
public enum FieldChange<Value: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    case unchanged
    case set(Value)

    private enum CodingKeys: String, CodingKey { case kind, value }
    private enum Kind: String, Codable { case unchanged, set }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(Kind.self, forKey: .kind) {
        case .unchanged: self = .unchanged
        case .set: self = .set(try c.decode(Value.self, forKey: .value))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .unchanged: try c.encode(Kind.unchanged, forKey: .kind)
        case .set(let value):
            try c.encode(Kind.set, forKey: .kind)
            try c.encode(value, forKey: .value)
        }
    }
}

public enum ContractJSON {
    /// Shared configured coders. JSONEncoder/JSONDecoder keep no mutable state
    /// between calls, so one instance per process is safe across actors; the
    /// wrapper exists only to satisfy Sendable checking.
    private static let shared = CoderBox()

    /// Compact output: stored payloads and wire bodies are parsed by machines,
    /// and pretty-printed JSON inflated every persisted record.
    /// `sortedKeys` stays: query fingerprints depend on deterministic encoding.
    public static func encoder() -> JSONEncoder { shared.encoder }
    public static func decoder() -> JSONDecoder { shared.decoder }

    private final class CoderBox: @unchecked Sendable {
        let encoder: JSONEncoder
        let decoder: JSONDecoder
        init() {
            encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
        }
    }
}

public enum RecordSelection: Codable, Sendable, Equatable {
    case ids([UUID])
    case all(RecordQuery)
}

public enum JobTarget: Codable, Sendable, Equatable {
    case job(UUID)
    case batch(UUID)
}

public extension EditableText {
    var displayText: String { correctedText ?? rawText }
}

public extension MistakeRecord {
    var isAnalysisStale: Bool {
        guard let analysisResult else { return false }
        return analysisResult.inputContentRevision != contentRevision
    }

    public var isMistakeValueStale: Bool {
        guard let mistakeValue else { return false }
        return mistakeValue.inputContentRevision != contentRevision
    }

    var contentSnapshot: RecordContentSnapshot {
        RecordContentSnapshot(recordID: id, contentRevision: contentRevision,
            sourceRegions: sourceRegions, ocrLines: ocrLines, stem: stem, studentWork: studentWork,
            referenceAnswer: referenceAnswer, referenceAnswerSource: referenceAnswerSource)
    }
}
