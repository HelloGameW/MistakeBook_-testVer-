import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Contracts

public struct BaiduEducationOCRService: OCRService, Sendable {
    private let tokenProvider: BaiduTokenProvider
    public init(credentialStore: any CredentialStore) { self.tokenProvider = BaiduTokenProvider(credentialStore: credentialStore) }

    public func supportedLanguages() async throws -> [String] { ["zh-Hans", "en-US"] }

    public func recognize(image: ImagePayload, options: RecognitionOptions) async throws -> RecognizedPage {
        try Task.checkCancellation()
        let config = options.baiduEducation ?? BaiduEducationConfiguration()
        switch config.strategy {
        case .paperCut:
            return try await paperCut(image: image, config: config)
        case .documentAnalysis:
            return try await documentAnalysis(image: image, config: config)
        case .automatic:
            do {
                let cut = try await paperCut(image: image, config: config)
                if !cut.candidates.isEmpty && !cut.lines.isEmpty { return cut }
            } catch is CancellationError { throw CancellationError() }
            catch let error as AppError where error.code == .invalidModelOutput || error.code == .unsupportedInput {
                // Structurally unusable paper-cut output may be recovered by document analysis.
            }
            return try await documentAnalysis(image: image, config: config)
        }
    }

    private func paperCut(image: ImagePayload, config: BaiduEducationConfiguration) async throws -> RecognizedPage {
        let data = try await request(endpoint: "https://aip.baidubce.com/rest/2.0/ocr/v1/paper_cut_edu", image: image,
                                     fields: ["language_type": config.languageType,
                                              "detect_direction": config.detectDirection ? "true" : "false",
                                              "words_type": config.mixedHandwriting ? "handprint_mix" : "handwring_only",
                                              "splice_text": "true", "enhance": "true"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError(code: .invalidModelOutput) }
        try Self.throwIfBaiduError(root)
        guard let questions = root["qus_result"] as? [[String: Any]], !questions.isEmpty else { throw AppError(code: .invalidModelOutput) }
        var regions: [SourceRegion] = []
        var lines: [OCRLine] = []
        var candidates: [SegmentationCandidate] = []
        for (index, question) in questions.enumerated() {
            var qRegions: [SourceRegion] = []
            var qLineIDs: [UUID] = []
            let elements = question["qus_element"] as? [[String: Any]] ?? []
            for element in elements {
                let type = Self.int(element["elem_type"]) ?? -1
                let purpose: RegionPurpose
                switch type { case 0, 1, 3: purpose = .stem; case 2: purpose = .studentWork; case 4: purpose = .diagram; case 5: purpose = .referenceAnswer; default: purpose = .unknown }
                let probability = Self.double(element["elem_probability"])
                let words = element["elem_word"] as? [[String: Any]] ?? []
                if words.isEmpty, let rect = Self.rect(from: element["elem_location"], image: image) {
                    let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: rect, purpose: purpose, isUserConfirmed: false)
                    regions.append(region); qRegions.append(region)
                }
                for word in words {
                    guard let text = word["word"] as? String, !text.isEmpty,
                          let rect = Self.rect(from: word["word_location"], image: image) else { continue }
                    let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: rect, purpose: purpose, isUserConfirmed: false)
                    let lineID = UUID()
                    let style: ScriptStyle = (word["word_type"] as? String) == "handwriting" ? .handwritten : ((word["word_type"] as? String) == "print" ? .printed : .unknown)
                    let conf = probability.map { Confidence(value: min(1, max(0, $0)), source: .remoteService, calibrated: false) }
                    regions.append(region); qRegions.append(region); qLineIDs.append(lineID)
                    lines.append(OCRLine(id: lineID, regionID: region.id, assetID: image.assetID,
                                         rawText: String(text.prefix(4000)), confidence: conf, scriptStyle: style, normalizedRect: rect))
                }
            }
            if !qRegions.isEmpty || !qLineIDs.isEmpty {
                candidates.append(SegmentationCandidate(id: UUID(), order: index, regions: qRegions, lineIDs: qLineIDs,
                                                        needsConfirmation: true, warnings: []))
            }
        }
        guard !lines.isEmpty else { throw AppError(code: .invalidModelOutput) }
        return RecognizedPage(assetID: image.assetID, regions: regions, lines: lines,
                              providerID: "baidu.education.paper-cut", providerVersion: "2026-01",
                              supportedLanguages: ["zh-Hans", "en-US"], warnings: [], candidates: candidates)
    }

    private func documentAnalysis(image: ImagePayload, config: BaiduEducationConfiguration) async throws -> RecognizedPage {
        let data = try await request(endpoint: "https://aip.baidubce.com/rest/2.0/ocr/v1/doc_analysis", image: image,
                                     fields: ["language_type": config.languageType, "result_type": "big",
                                              "detect_direction": config.detectDirection ? "true" : "false",
                                              "words_type": config.mixedHandwriting ? "handprint_mix" : "handwring_only",
                                              "layout_analysis": config.layoutAnalysis ? "true" : "false",
                                              "recg_formula": config.recognizeFormula ? "true" : "false",
                                              "line_probability": "true"])
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError(code: .invalidModelOutput) }
        try Self.throwIfBaiduError(root)
        var regions: [SourceRegion] = []
        var lines: [OCRLine] = []
        let results = root["results"] as? [[String: Any]] ?? []
        for item in results {
            guard let words = item["words"] as? [String: Any], let text = words["word"] as? String, !text.isEmpty,
                  let rect = Self.rect(from: words["words_location"], image: image) else { continue }
            let handwritten = (item["words_type"] as? String) == "handwriting"
            let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: rect,
                                      purpose: handwritten ? .studentWork : .unknown, isUserConfirmed: false)
            let lineID = UUID()
            regions.append(region)
            lines.append(OCRLine(id: lineID, regionID: region.id, assetID: image.assetID, rawText: String(text.prefix(4000)),
                                 confidence: nil, scriptStyle: handwritten ? .handwritten : .printed, normalizedRect: rect))
        }
        if config.recognizeFormula {
            for item in root["formula_result"] as? [[String: Any]] ?? [] {
                guard let text = item["form_words"] as? String, !text.isEmpty,
                      let rect = Self.rect(from: item["form_location"], image: image) else { continue }
                let region = SourceRegion(id: UUID(), assetID: image.assetID, normalizedRect: rect, purpose: .unknown, isUserConfirmed: false)
                regions.append(region)
                lines.append(OCRLine(id: UUID(), regionID: region.id, assetID: image.assetID, rawText: String(text.prefix(4000)),
                                     confidence: nil, scriptStyle: .unknown, normalizedRect: rect))
            }
        }
        guard !lines.isEmpty else { throw AppError(code: .invalidModelOutput) }
        return RecognizedPage(assetID: image.assetID, regions: regions, lines: lines,
                              providerID: "baidu.education.doc-analysis", providerVersion: "2026",
                              supportedLanguages: ["zh-Hans", "en-US"], warnings: [], candidates: [])
    }

    private func request(endpoint: String, image: ImagePayload, fields: [String: String]) async throws -> Data {
        let token = try await tokenProvider.token()
        guard var components = URLComponents(string: endpoint) else { throw AppError(code: .invalidConfiguration) }
        components.queryItems = [URLQueryItem(name: "access_token", value: token)]
        guard let url = components.url else { throw AppError(code: .invalidConfiguration) }
        var body = fields
        body["image"] = image.bytes.base64EncodedString()
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = NetworkSupport.formBody(body)
        return try await NetworkSupport.checkedData(for: request)
    }

    private static func throwIfBaiduError(_ root: [String: Any]) throws {
        guard root["error_code"] != nil else { return }
        let code = int(root["error_code"]) ?? 0
        switch code {
        case 110, 111: throw AppError(code: .authenticationFailed)
        case 17, 18, 19: throw AppError(code: .rateLimited, isRetryable: true)
        default: throw AppError(code: .networkUnavailable, isRetryable: true)
        }
    }

    private static func rect(from value: Any?, image: ImagePayload) -> NormalizedRect? {
        guard image.pixelWidth > 0, image.pixelHeight > 0 else { return nil }
        if let d = value as? [String: Any], let left = double(d["left"]), let top = double(d["top"]),
           let width = double(d["width"]), let height = double(d["height"]) {
            return safeRect(x: left / Double(image.pixelWidth), y: top / Double(image.pixelHeight),
                            width: width / Double(image.pixelWidth), height: height / Double(image.pixelHeight))
        }
        if let points = value as? [[String: Any]], !points.isEmpty {
            let xs = points.compactMap { double($0["x"]) }, ys = points.compactMap { double($0["y"]) }
            guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return nil }
            return safeRect(x: minX / Double(image.pixelWidth), y: minY / Double(image.pixelHeight),
                            width: (maxX - minX) / Double(image.pixelWidth), height: (maxY - minY) / Double(image.pixelHeight))
        }
        return nil
    }

    private static func safeRect(x: Double, y: Double, width: Double, height: Double) -> NormalizedRect? {
        let x0 = min(0.999_999, max(0, x)), y0 = min(0.999_999, max(0, y))
        let w = min(1 - x0, max(0.000_001, width)), h = min(1 - y0, max(0.000_001, height))
        return try? NormalizedRect(x: x0, y: y0, width: w, height: h)
    }
    private static func double(_ value: Any?) -> Double? {
        if let x = value as? Double { return x }; if let x = value as? Int { return Double(x) }
        if let x = value as? NSNumber { return x.doubleValue }; if let x = value as? String { return Double(x) }; return nil
    }
    private static func int(_ value: Any?) -> Int? {
        guard let number = double(value), number.isFinite else { return nil }
        return Int(exactly: number)
    }
}

private actor BaiduTokenProvider {
    private let credentialStore: any CredentialStore
    private var cached: (value: String, expiresAt: Date, apiKey: String, secret: String)?
    init(credentialStore: any CredentialStore) { self.credentialStore = credentialStore }

    func token() async throws -> String {
        guard let apiKey = try await credentialStore.read(kind: .baiduAPIKey), !apiKey.isEmpty,
              let secret = try await credentialStore.read(kind: .baiduSecretKey), !secret.isEmpty else {
            cached = nil
            throw AppError(code: .authenticationFailed)
        }
        if let cached, cached.apiKey == apiKey, cached.secret == secret,
           cached.expiresAt.timeIntervalSinceNow > 300 { return cached.value }
        var components = URLComponents(string: "https://aip.baidubce.com/oauth/2.0/token")!
        components.queryItems = [URLQueryItem(name: "grant_type", value: "client_credentials"),
                                 URLQueryItem(name: "client_id", value: apiKey),
                                 URLQueryItem(name: "client_secret", value: secret)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data = try await NetworkSupport.checkedData(for: request)
        struct TokenResponse: Decodable { let access_token: String?; let expires_in: Int?; let error: String? }
        guard let response = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let token = response.access_token, !token.isEmpty else { throw AppError(code: .authenticationFailed) }
        cached = (token, Date().addingTimeInterval(TimeInterval(max(0, response.expires_in ?? 2_592_000))), apiKey, secret)
        return token
    }
}
