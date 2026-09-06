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
}
