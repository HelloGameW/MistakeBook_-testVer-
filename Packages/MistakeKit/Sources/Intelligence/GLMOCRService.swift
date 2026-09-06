import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Contracts

/// 智谱 BigModel GLM OCR（工具 API）：POST /paas/v4/files/ocr，
/// multipart 上传图片（`tool_type=hand_write`），返回 `words_result` 行级文本与像素坐标。
public struct GLMOCRService: OCRService, Sendable {
    private static let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/files/ocr")!
    private let credentialStore: any CredentialStore

    public init(credentialStore: any CredentialStore) {
        self.credentialStore = credentialStore
    }

    public func supportedLanguages() async throws -> [String] { ["zh-Hans", "en-US"] }

    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        try Task.checkCancellation()
        guard let key = try await credentialStore.read(kind: .glmAPIKey), !key.isEmpty else {
            throw AppError(code: .authenticationFailed)
        }
        let mime: String
        let filename: String
        switch image.mediaType {
        case .png: mime = "image/png"; filename = "image.png"
        case .jpeg: mime = "image/jpeg"; filename = "image.jpg"
        case .heic: throw AppError(code: .unsupportedInput)
        }
        let languageType = options.languages.contains(where: { $0.hasPrefix("en") }) && !options.languages.contains(where: { $0.hasPrefix("zh") }) ? "ENG" : "CHN_ENG"
        let boundary = "mistakebook.glm.\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(imageBytes: image.bytes, filename: filename, mime: mime,
                                              languageType: languageType, boundary: boundary)

        let data = try await NetworkSupport.checkedData(for: request)
        return try Self.parse(response: data, image: image)
    }

    /// 响应解析（独立出来便于单元测试）：status 校验 + 行级文本/像素坐标归一化。
    static func parse(response: Data, image: ImagePayload) throws -> RecognizedPage {
        struct Location: Decodable { let left: Double; let top: Double; let width: Double; let height: Double }
        struct Entry: Decodable { let words: String; let location: Location }
        struct OCRResponse: Decodable {
            let status: String
            let words_result_num: Int
            let words_result: [Entry]
        }
        guard image.pixelWidth > 0, image.pixelHeight > 0 else { throw AppError(code: .unsupportedInput) }
        let decoded: OCRResponse
        do { decoded = try JSONDecoder().decode(OCRResponse.self, from: response) }
        catch { throw AppError(code: .invalidModelOutput) }
        guard decoded.status == "succeeded" else { throw AppError(code: .modelUnavailable, isRetryable: true) }
        guard !decoded.words_result.isEmpty else { throw AppError(code: .invalidModelOutput) }

        var regions: [SourceRegion] = []
        var lines: [OCRLine] = []
        for entry in decoded.words_result.prefix(3000) {
            let text = entry.words.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let rect = Self.safeRect(x: entry.location.left / Double(image.pixelWidth),
                                     y: entry.location.top / Double(image.pixelHeight),
                                     width: entry.location.width / Double(image.pixelWidth),
                                     height: entry.location.height / Double(image.pixelHeight))
            guard let normalized = rect else { continue }
            let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: normalized,
                                      purpose: .unknown, isUserConfirmed: false)
            regions.append(region)
            lines.append(OCRLine(id: UUID(), regionID: region.id, assetID: image.assetID,
                                 rawText: String(text.prefix(4000)), confidence: nil,
                                 scriptStyle: .printed, normalizedRect: normalized))
        }
        guard !lines.isEmpty else { throw AppError(code: .invalidModelOutput) }
        return RecognizedPage(assetID: image.assetID, regions: regions, lines: lines,
                              providerID: "glm.ocr", providerVersion: "hand_write",
                              supportedLanguages: ["zh-Hans", "en-US"], warnings: [], candidates: [])
    }

    private static func safeRect(x: Double, y: Double, width: Double, height: Double) -> NormalizedRect? {
        let x0 = min(0.999_999, max(0, x)), y0 = min(0.999_999, max(0, y))
        let w = min(1 - x0, max(0.000_001, width)), h = min(1 - y0, max(0.000_001, height))
        return try? NormalizedRect(x: x0, y: y0, width: w, height: h)
    }

    private static func multipartBody(imageBytes: Data, filename: String, mime: String,
                                      languageType: String, boundary: String) -> Data {
        var body = Data()
        func append(field: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(field)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        append(field: "tool_type", value: "hand_write")
        append(field: "language_type", value: languageType)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageBytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }
}
