import Foundation
import XCTest
import Contracts
import TestSupport
@testable import Intelligence

final class NetworkRegressionTests: XCTestCase {
    func testAnalysisRejectsUnsupportedClaimsAndMismatchedStatus() throws {
        let snapshot = ContractSamples.recordContentSnapshot()
        let hypothesis = Hypothesis(id: UUID(), kind: .knowledge, summary: "缺少证据的判断", evidence: [],
                                    reason: "", nextAction: "", certainty: .tentative, userDecision: .pending)
        func result(_ status: AnalysisStatus, _ hypotheses: [Hypothesis]) -> AnalysisResult {
            AnalysisResult(status: status, hypotheses: hypotheses, limitations: [], engineID: "test",
                           engineVersion: "1", inputContentRevision: snapshot.contentRevision,
                           referenceAnswerSource: snapshot.referenceAnswerSource)
        }
        XCTAssertThrowsError(try FoundationModelsAnalysisService.validated(result(.hypotheses, [hypothesis]), snapshot: snapshot))
        XCTAssertThrowsError(try FoundationModelsAnalysisService.validated(result(.hypotheses, []), snapshot: snapshot))
        XCTAssertThrowsError(try FoundationModelsAnalysisService.validated(result(.insufficientEvidence, [hypothesis]), snapshot: snapshot))
        XCTAssertNoThrow(try FoundationModelsAnalysisService.validated(result(.insufficientEvidence, []), snapshot: snapshot))
    }

    func testFormRoundTripPreservesBase64AndReservedCharacters() throws {
        let fields = ["image": "+/8=", "text": "空 格+a&b=c%"]
        let body = String(decoding: NetworkSupport.formBody(fields), as: UTF8.self)
        var decoded: [String: String] = [:]
        // Decode as application/x-www-form-urlencoded, including plus-to-space.
        for pair in body.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            XCTAssertEqual(parts.count, 2)
            guard parts.count == 2 else { return }
            let key = try XCTUnwrap(String(parts[0]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            let value = try XCTUnwrap(String(parts[1]).replacingOccurrences(of: "+", with: " ").removingPercentEncoding)
            decoded[key] = value
        }
        XCTAssertEqual(decoded, fields)
    }

    func testJSONExtractionIgnoresSurroundingProse() throws {
        let data = try XCTUnwrap(OpenAICompatibleClient.extractJSONObject(from: "结果：```json\n{\"status\":\"ok\"}\n```\n说明结束。"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
        XCTAssertEqual(object["status"], "ok")
    }

    func testMalformedJSONIsRejected() {
        XCTAssertNil(OpenAICompatibleClient.extractJSONObject(from: "说明 {invalid} 结束"))
        XCTAssertNil(OpenAICompatibleClient.extractJSONObject(from: "没有 JSON"))
    }

    func testGLMOCRRequestUsesDocumentedMultipartFields() throws {
        let body = GLMOCRService.multipartBody(imageBytes: Data([0x01, 0x02]), filename: "question.png",
                                                mime: "image/png", languageType: "CHN_ENG", boundary: "test-boundary")
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertEqual(GLMOCRService.modelIdentifier, "glm-ocr")
        XCTAssertTrue(text.contains("name=\"tool_type\"\r\n\r\nhand_write"))
        XCTAssertTrue(text.contains("name=\"language_type\"\r\n\r\nCHN_ENG"))
        XCTAssertTrue(text.contains("name=\"probability\"\r\n\r\ntrue"))
        XCTAssertTrue(text.contains("name=\"file\"; filename=\"question.png\""))
    }

    func testGLMOCRResponseParsesWordsLocationsAndConfidence() throws {
        let assetID = UUID()
        let image = ImagePayload(assetID: assetID, bytes: Data([0x01]), mediaType: .png,
                                 orientation: .up, pixelWidth: 1000, pixelHeight: 500)
        let response = #"""
        {
            "task_id": "task-1",
            "message": "success",
            "status": "succeeded",
            "words_result_num": 1,
            "words_result": [{
                "location": {"left": 100, "top": 50, "width": 400, "height": 80},
                "words": "计算 1 + 1",
                "probability": {"average": 0.91, "variance": 0.02, "min": 0.84}
            }]
        }
        """#

        let page = try GLMOCRService.parse(response: Data(response.utf8), image: image)
        XCTAssertEqual(page.providerID, "glm-ocr")
        XCTAssertEqual(page.providerVersion, "glm-ocr")
        XCTAssertEqual(page.lines.count, 1)
        XCTAssertEqual(page.lines[0].rawText, "计算 1 + 1")
        XCTAssertEqual(try XCTUnwrap(page.lines[0].confidence?.value), 0.91, accuracy: 0.000001)
        XCTAssertEqual(page.lines[0].normalizedRect.x, 0.1, accuracy: 0.000001)
        XCTAssertEqual(page.lines[0].normalizedRect.y, 0.1, accuracy: 0.000001)
        XCTAssertEqual(page.lines[0].normalizedRect.width, 0.4, accuracy: 0.000001)
        XCTAssertEqual(page.lines[0].normalizedRect.height, 0.16, accuracy: 0.000001)
    }
}
