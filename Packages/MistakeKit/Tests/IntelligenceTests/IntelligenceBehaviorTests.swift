import XCTest
import Contracts
import Intelligence

final class IntelligenceBehaviorTests: XCTestCase {
    func testSegmentationDoesNotTreatOptionNumbersAsQuestionStarts() async throws {
        let assetID = UUID()
        let pageRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage, purpose: .unknown, isUserConfirmed: false)
        let lines = try [
            OCRLine(id: UUID(), regionID: pageRegion.id, assetID: assetID, rawText: "1. 计算 1+1", confidence: nil, scriptStyle: .printed, normalizedRect: try NormalizedRect(x: 0.1, y: 0.1, width: 0.3, height: 0.05)),
            OCRLine(id: UUID(), regionID: pageRegion.id, assetID: assetID, rawText: "(1) 选项", confidence: nil, scriptStyle: .printed, normalizedRect: try NormalizedRect(x: 0.1, y: 0.2, width: 0.3, height: 0.05)),
            OCRLine(id: UUID(), regionID: pageRegion.id, assetID: assetID, rawText: "2. 说明原因", confidence: nil, scriptStyle: .printed, normalizedRect: try NormalizedRect(x: 0.1, y: 0.4, width: 0.3, height: 0.05))
        ]
        let page = RecognizedPage(assetID: assetID, regions: [pageRegion], lines: lines, providerID: "test", providerVersion: "1", supportedLanguages: [], warnings: [], candidates: [])
        let candidates = try await HeuristicSegmentationService().segment(page: page, options: SegmentationOptions(allowOverlappingRegions: true))
        XCTAssertEqual(candidates.count, 2)
        XCTAssertFalse(candidates.contains { $0.lineIDs.count == 1 && $0.lineIDs.contains(lines[1].id) })
    }

    func testSegmentationCarriesVisualRegionsIntoQuestionCandidate() async throws {
        let assetID = UUID()
        let pageRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage, purpose: .unknown, isUserConfirmed: false)
        let tableRegion = SourceRegion(id: UUID(), assetID: assetID,
                                       normalizedRect: try NormalizedRect(x: 0.15, y: 0.2, width: 0.7, height: 0.25),
                                       purpose: .diagram, isUserConfirmed: false)
        let line = OCRLine(id: UUID(), regionID: pageRegion.id, assetID: assetID,
                           rawText: "1. 比较下表数据", confidence: nil, scriptStyle: .printed,
                           normalizedRect: try NormalizedRect(x: 0.1, y: 0.1, width: 0.5, height: 0.06))
        let page = RecognizedPage(assetID: assetID, regions: [pageRegion, tableRegion], lines: [line],
                                  providerID: "test", providerVersion: "1", supportedLanguages: [],
                                  warnings: [], candidates: [])
        let candidates = try await HeuristicSegmentationService().segment(
            page: page, options: SegmentationOptions(allowOverlappingRegions: true))
        XCTAssertTrue(candidates.first?.regions.contains(tableRegion) == true)
        XCTAssertTrue(candidates.first?.warnings.contains { $0.code == "segmentation.visualRegion" } == true)
    }

    func testRuleAnalysisProducesEvidenceAndRejectsComplexProof() async throws {
        let assetID = UUID()
        let studentRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage, purpose: .studentWork, isUserConfirmed: false)
        let referenceRegion = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage, purpose: .referenceAnswer, isUserConfirmed: false)
        let studentLine = OCRLine(id: UUID(), regionID: studentRegion.id, assetID: assetID, rawText: "3", confidence: nil, scriptStyle: .unknown, normalizedRect: .fullPage)
        let referenceLine = OCRLine(id: UUID(), regionID: referenceRegion.id, assetID: assetID, rawText: "2", confidence: nil, scriptStyle: .unknown, normalizedRect: .fullPage)
        let snapshot = RecordContentSnapshot(recordID: UUID(), contentRevision: 1, sourceRegions: [studentRegion, referenceRegion], ocrLines: [studentLine, referenceLine], stem: EditableText(rawText: "计算 1+1", correctedText: nil, provenance: .ocr, isLocked: false), studentWork: EditableText(rawText: "3", correctedText: nil, provenance: .ocr, isLocked: false), referenceAnswer: EditableText(rawText: "2", correctedText: nil, provenance: .teacher, isLocked: false), referenceAnswerSource: nil)
        let result = try await RuleBasedAnalysisService().analyze(snapshot: snapshot, options: AnalysisOptions(useEnhancedModel: false, language: "zh-Hans", timeoutSeconds: 1))
        XCTAssertEqual(result.inputContentRevision, 1)
        XCTAssertTrue(result.hypotheses.contains { $0.kind == .possibleSolutionError })
        XCTAssertTrue(result.hypotheses.flatMap(\.evidence).contains { $0.lineID == studentLine.id })
    }

    func testSeedProviderDecodesStableTaxonomy() async throws {
        let root = TaxonomyNode(id: "math", parentID: nil, name: "数学", subjectID: "math", aliases: ["math"], origin: .seed, isActive: true, version: 1, userModifiedFields: [])
        let child = TaxonomyNode(id: "math/algebra", parentID: "math", name: "代数", subjectID: "math", aliases: ["algebra"], origin: .seed, isActive: true, version: 1, userModifiedFields: [])
        let seed = try TaxonomySeed(schemaVersion: 1, seedVersion: "test", nodes: [root, child])
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("mistakebook-seed-\(UUID().uuidString).json")
        try ContractJSON.encoder().encode(seed).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let loaded = try await JSONTaxonomySeedProvider(resourceURL: url).loadSeed()
        XCTAssertEqual(loaded, seed)
    }
    func testLocalMistakeValueUsesFixedBoundedScore() async throws {
        let snapshot = RecordContentSnapshot(
            recordID: UUID(), contentRevision: 3, sourceRegions: [], ocrLines: [],
            stem: EditableText(rawText: "函数定义域", correctedText: nil, provenance: .user, isLocked: false),
            studentWork: EditableText(rawText: "遗漏分母不为零条件", correctedText: nil, provenance: .user, isLocked: false),
            referenceAnswer: nil, referenceAnswerSource: nil)
        let result = try await LocalHeuristicMistakeValueService().evaluate(
            snapshot: snapshot, analysis: nil, options: ValueAnalysisOptions())
        XCTAssertTrue((0...1).contains(result.overallScore))
        XCTAssertEqual(result.inputContentRevision, 3)
        let d = result.dimensions
        let expected = d.knowledgeValue * 0.20 + d.representativeness * 0.15 + d.recurrenceRisk * 0.25
            + d.reasoningValue * 0.15 + d.examValue * 0.10 + d.reviewPriority * 0.15
        XCTAssertEqual(result.overallScore, expected, accuracy: 0.000001)
    }

    func testRuleAnalysisUsesInsufficientEvidenceWhenNoSafeRuleMatches() async throws {
        let snapshot = RecordContentSnapshot(
            recordID: UUID(), contentRevision: 1, sourceRegions: [], ocrLines: [],
            stem: EditableText(rawText: "证明该命题", correctedText: nil, provenance: .user, isLocked: false),
            studentWork: EditableText(rawText: "略", correctedText: nil, provenance: .user, isLocked: false),
            referenceAnswer: nil, referenceAnswerSource: nil)
        let result = try await RuleBasedAnalysisService().analyze(
            snapshot: snapshot,
            options: AnalysisOptions(useEnhancedModel: false, language: "zh-Hans", timeoutSeconds: 1))
        XCTAssertEqual(result.status, .insufficientEvidence)
        XCTAssertTrue(result.hypotheses.isEmpty)
    }

    func testRuleAnalysisUsesExplicitStudentCauseCueWithoutReference() async throws {
        let assetID = UUID()
        let region = SourceRegion(id: UUID(), assetID: assetID, normalizedRect: .fullPage,
                                  purpose: .studentWork, isUserConfirmed: false)
        let line = OCRLine(id: UUID(), regionID: region.id, assetID: assetID,
                           rawText: "我审题时漏看了单位，导致计算错误。", confidence: nil,
                           scriptStyle: .unknown, normalizedRect: .fullPage)
        let snapshot = RecordContentSnapshot(
            recordID: UUID(), contentRevision: 1, sourceRegions: [region], ocrLines: [line],
            stem: EditableText(rawText: "计算题", correctedText: nil, provenance: .user, isLocked: false),
            studentWork: EditableText(rawText: line.rawText, correctedText: nil, provenance: .user, isLocked: false),
            referenceAnswer: nil, referenceAnswerSource: nil)
        let result = try await RuleBasedAnalysisService().analyze(
            snapshot: snapshot, options: AnalysisOptions(useEnhancedModel: false, language: "zh-Hans", timeoutSeconds: 1))
        XCTAssertEqual(result.status, .hypotheses)
        XCTAssertTrue(result.hypotheses.contains { $0.kind == .reading })
        XCTAssertTrue(result.hypotheses.contains { $0.kind == .procedure })
        XCTAssertTrue(result.hypotheses.flatMap(\.evidence).contains { $0.lineID == line.id })
    }

}
