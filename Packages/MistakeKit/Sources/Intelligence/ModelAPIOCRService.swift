import Foundation
import Contracts

public struct ModelAPIOCRService: OCRService, Sendable {
    private let credentialStore: any CredentialStore
    private let client = OpenAICompatibleClient()

    public init(credentialStore: any CredentialStore) { self.credentialStore = credentialStore }

    public func supportedLanguages() async throws -> [String] { ["zh-Hans", "en-US"] }

    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        try Task.checkCancellation()
        guard let configuration = options.modelAPI,
              let key = try await credentialStore.read(kind: .ocrModelAPIKey) else { throw AppError(code: .invalidConfiguration) }
        let mime: String
        switch image.mediaType { case .jpeg: mime = "image/jpeg"; case .png: mime = "image/png"; case .heic: mime = "image/heic" }
        let uri = "data:\(mime);base64,\(image.bytes.base64EncodedString())"
        let json = try await client.requestJSON(prompt: Self.prompt(languages: options.languages), imageDataURI: uri,
                                                configuration: configuration, apiKey: key)
        let envelope: Envelope
        do { envelope = try JSONDecoder().decode(Envelope.self, from: json) }
        catch { throw AppError(code: .invalidModelOutput) }
        return try Self.normalize(envelope: envelope, image: image, model: configuration.model)
    }

    private struct Envelope: Decodable { let lines: [Line] }
    private struct Line: Decodable {
        let text: String
        let x: Double
        let y: Double
        let width: Double
        let height: Double
        let style: String?
        let purpose: String?
        let questionIndex: Int?
        let confidence: Double?
    }

    private static func normalize(envelope: Envelope, image: ImagePayload, model: String) throws -> RecognizedPage {
        guard !envelope.lines.isEmpty, envelope.lines.count <= 3000 else { throw AppError(code: .invalidModelOutput) }
        var regions: [SourceRegion] = []
        var lines: [OCRLine] = []
        var questionRegions: [Int: [SourceRegion]] = [:]
        var questionLineIDs: [Int: [UUID]] = [:]
        for item in envelope.lines {
            guard !item.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let rect = try NormalizedRect(x: item.x, y: item.y, width: item.width, height: item.height)
            let purpose: RegionPurpose
            switch item.purpose {
            case "stem", "option": purpose = .stem
            case "studentWork", "answer": purpose = .studentWork
            case "referenceAnswer": purpose = .referenceAnswer
            case "diagram": purpose = .diagram
            default: purpose = .unknown
            }
            let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: rect, purpose: purpose, isUserConfirmed: false)
            let lineID = UUID()
            let style: ScriptStyle = item.style == "handwritten" ? .handwritten : (item.style == "printed" ? .printed : .unknown)
            let confidence = item.confidence.map { Confidence(value: min(1, max(0, $0)), source: .remoteService, calibrated: false) }
            regions.append(region)
            lines.append(OCRLine(id: lineID, regionID: region.id, assetID: image.assetID, rawText: String(item.text.prefix(4000)),
                                 confidence: confidence, scriptStyle: style, normalizedRect: rect))
            if let index = item.questionIndex {
                questionRegions[index, default: []].append(region)
                questionLineIDs[index, default: []].append(lineID)
            }
        }
        guard !lines.isEmpty else { throw AppError(code: .invalidModelOutput) }
        let candidates = questionRegions.keys.sorted().enumerated().map { order, index in
            SegmentationCandidate(id: UUID(), order: order, regions: questionRegions[index] ?? [],
                                  lineIDs: questionLineIDs[index] ?? [], needsConfirmation: true, warnings: [])
        }
        return RecognizedPage(assetID: image.assetID, regions: regions, lines: lines,
                              providerID: "model-api.ocr", providerVersion: model,
                              supportedLanguages: ["zh-Hans", "en-US"], warnings: [], candidates: candidates)
    }

    private static func prompt(languages: [String]) -> String {
        """
        你是试卷 OCR 结构化接口。只识别图片中真实可见内容，不解题、不补全缺失文字。
        保留数学/物理/化学公式，公式可使用 LaTeX。坐标必须以整张图左上角为原点并归一化到 0...1。
        style 只能是 printed, handwritten, unknown。purpose 只能是 stem, option, studentWork, referenceAnswer, diagram, unknown。
        questionIndex 从 0 开始；不能确定时使用 null。confidence 是 0...1 或 null。
        语言偏好：\(languages.joined(separator: ","))。只返回 JSON：
        {"lines":[{"text":"","x":0.0,"y":0.0,"width":0.1,"height":0.05,"style":"printed","purpose":"stem","questionIndex":0,"confidence":0.9}]}
        """
    }
}
