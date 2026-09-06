import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreGraphics) && canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif
import Contracts

/// 智谱 BigModel GLM OCR（工具 API）：POST /paas/v4/files/ocr，
/// multipart 上传图片（`tool_type=hand_write`），返回 `words_result` 行级文本与像素坐标。
/// 接入文档：https://docs.bigmodel.cn/cn/guide/tools/zhipu-ocr
public struct GLMOCRService: OCRService, Sendable {
    /// GLM-OCR is selected server-side by the OCR tool endpoint; the API does
    /// not take a `model` form field. Keep the identifier in metadata/UI so the
    /// selected image-recognition capability is explicit without sending an
    /// undocumented parameter.
    public static let modelIdentifier = "glm-ocr"
    private static let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/files/ocr")!
    /// 文档限制单图 8M；工作图是最大 4096px 的 PNG，可能超限，超出即重编码 JPEG。
    private static let maxUploadBytes = 7_500_000
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
        guard !image.bytes.isEmpty, image.pixelWidth > 0, image.pixelHeight > 0 else {
            throw AppError(code: .unsupportedInput)
        }
        var uploadBytes = image.bytes
        var mime = "image/png"
        var filename = "image.png"
        switch image.mediaType {
        case .png: break
        case .jpeg: mime = "image/jpeg"; filename = "image.jpg"
        case .heic:
            // HEIC 不在文档支持列表（PNG/JPG/JPEG/BMP），重编码为 JPEG 上传。
            #if canImport(CoreGraphics) && canImport(ImageIO)
            guard let recompressed = Self.recompressedJPEG(image.bytes) else { throw AppError(code: .unsupportedInput) }
            uploadBytes = recompressed; mime = "image/jpeg"; filename = "image.jpg"
            #else
            throw AppError(code: .unsupportedInput)
            #endif
        }
        #if canImport(CoreGraphics) && canImport(ImageIO)
        if uploadBytes.count > Self.maxUploadBytes, let recompressed = Self.recompressedJPEG(uploadBytes) {
            uploadBytes = recompressed; mime = "image/jpeg"; filename = "image.jpg"
        }
        #endif
        let languageType = options.languages.contains(where: { $0.hasPrefix("en") }) && !options.languages.contains(where: { $0.hasPrefix("zh") }) ? "ENG" : "CHN_ENG"
        let boundary = "mistakebook.glm.\(UUID().uuidString)"
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.multipartBody(imageBytes: uploadBytes, filename: filename, mime: mime,
                                              languageType: languageType, boundary: boundary)

        let data = try await NetworkSupport.checkedData(for: request)
        return try Self.parse(response: data, image: image)
    }

    /// 响应解析（独立出来便于单元测试）：status 校验 + 行级文本/像素坐标归一化。
    /// 请求携带 `probability=true` 时，行置信度取 `probability.average`。
    static func parse(response: Data, image: ImagePayload) throws -> RecognizedPage {
        struct Location: Decodable { let left: Double; let top: Double; let width: Double; let height: Double }
        struct Probability: Decodable {
            let average: Double?
            let variance: Double?
            let min: Double?
        }
        struct Entry: Decodable {
            let words: String
            let location: Location
            let probability: Probability?
        }
        // 失败响应形如 {"task_id":null,"message":"...","status":null,"words_result_num":0}，
        // status/words_result 均可能缺失，用可选字段容忍两种形态。
        struct OCRResponse: Decodable {
            let status: String?
            let message: String?
            let words_result_num: Int?
            let words_result: [Entry]?
        }
        let decoded: OCRResponse
        do { decoded = try JSONDecoder().decode(OCRResponse.self, from: response) }
        catch { throw AppError(code: .invalidModelOutput) }
        guard decoded.status == "succeeded" else { throw AppError(code: .modelUnavailable, isRetryable: true) }
        let entries = decoded.words_result ?? []
        guard !entries.isEmpty else { throw AppError(code: .invalidModelOutput) }

        var regions: [SourceRegion] = []
        var lines: [OCRLine] = []
        for entry in entries.prefix(3000) {
            let text = entry.words.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let rect = Self.safeRect(x: entry.location.left / Double(image.pixelWidth),
                                     y: entry.location.top / Double(image.pixelHeight),
                                     width: entry.location.width / Double(image.pixelWidth),
                                     height: entry.location.height / Double(image.pixelHeight))
            guard let normalized = rect else { continue }
            let confidence = entry.probability?.average.map {
                Confidence(value: min(1, max(0, $0)), source: .remoteService, calibrated: false)
            }
            let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: normalized,
                                      purpose: .unknown, isUserConfirmed: false)
            regions.append(region)
            lines.append(OCRLine(id: UUID(), regionID: region.id, assetID: image.assetID,
                                 rawText: String(text.prefix(4000)), confidence: confidence,
                                 scriptStyle: .printed, normalizedRect: normalized))
        }
        guard !lines.isEmpty else { throw AppError(code: .invalidModelOutput) }
        return RecognizedPage(assetID: image.assetID, regions: regions, lines: lines,
                              providerID: Self.modelIdentifier, providerVersion: Self.modelIdentifier,
                              supportedLanguages: ["zh-Hans", "en-US"], warnings: [], candidates: [])
    }

    private static func safeRect(x: Double, y: Double, width: Double, height: Double) -> NormalizedRect? {
        let x0 = min(0.999_999, max(0, x)), y0 = min(0.999_999, max(0, y))
        let w = min(1 - x0, max(0.000_001, width)), h = min(1 - y0, max(0.000_001, height))
        return try? NormalizedRect(x: x0, y: y0, width: w, height: h)
    }

    static func multipartBody(imageBytes: Data, filename: String, mime: String,
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
        append(field: "probability", value: "true")
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mime)\r\n\r\n".data(using: .utf8)!)
        body.append(imageBytes)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// 大图降采样重编码为 JPEG，规避文档 8M 上传限制。
    /// 仅在带 ImageIO 的平台可用；其他平台原样上传，超限时由服务端报错。
    #if canImport(CoreGraphics) && canImport(ImageIO)
    private static func recompressedJPEG(_ bytes: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil) else { return nil }
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2600,
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
    #endif
}
