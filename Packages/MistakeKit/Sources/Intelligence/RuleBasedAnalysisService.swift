import Foundation
import Contracts

/// Safe, deliberately narrow offline analysis. It compares user material with
/// supplied reference material and refuses unsupported reasoning tasks.
public struct RuleBasedAnalysisService: AnalysisService, Sendable {
    public init() {}

    public func analyze(snapshot: RecordContentSnapshot, options: AnalysisOptions) async throws -> AnalysisResult {
        try Task.checkCancellation()
        let stem = snapshot.stem.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let student = snapshot.studentWork.displayText.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = snapshot.referenceAnswer?.displayText.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !stem.isEmpty || !student.isEmpty else {
            return Self.insufficient(snapshot: snapshot, limitation: "题干和作答均为空，暂无法判断。")
        }
        guard !student.isEmpty, !reference.isEmpty else {
            return Self.insufficient(snapshot: snapshot, limitation: "缺少学生作答或参考答案/教师批注，暂无法判断。")
        }

        var hypotheses: [Hypothesis] = []
        var limitations = ["基础规则仅覆盖可安全规范化的短答案和简单数值比较，不等同于通用判题。"]

        if let studentNumber = Self.numericValue(student),
           let referenceNumber = Self.numericValue(reference),
           Self.looksLikeNumericTask(stem),
           abs(studentNumber - referenceNumber) > 0.0000001 {
            if let evidence = Self.evidencePair(snapshot: snapshot, student: student, reference: reference) {
                hypotheses.append(Hypothesis(id: UUID(), kind: .possibleSolutionError,
                    summary: "可解析的数值作答与参考答案不一致。", evidence: evidence,
                    reason: "基础规则只比较了明确的数值结果，不能据此断定具体知识错误。",
                    nextAction: "检查运算步骤、单位和题干条件，并与原图核对。",
                    certainty: .needsConfirmation, userDecision: .pending))
            }
        }

        let isSetTask = stem.localizedCaseInsensitiveContains("子集")
            || stem.localizedCaseInsensitiveContains("subset")
            || stem.contains("∈") || stem.contains("⊆") || student.contains("∈") || student.contains("⊆")
        if isSetTask, Self.normalizedSetExpression(student) != Self.normalizedSetExpression(reference),
           let evidence = Self.evidencePair(snapshot: snapshot, student: student, reference: reference) {
            hypotheses.append(Hypothesis(id: UUID(), kind: .referenceDifference,
                summary: "集合成员/子集表达式与参考材料存在差异。", evidence: evidence,
                reason: "规则只发现规范化表达不同，尚未证明集合关系或推理一定错误。",
                nextAction: "逐项核对集合元素、符号方向和题干限定。",
                certainty: .needsConfirmation, userDecision: .pending))
        }

        let isShortEnglish = student.count <= 200 && reference.count <= 200
            && student.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
            && reference.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil
        if isShortEnglish && Self.normalizedText(student) != Self.normalizedText(reference),
           !hypotheses.contains(where: { $0.kind == .possibleSolutionError }),
           let evidence = Self.evidencePair(snapshot: snapshot, student: student, reference: reference) {
            hypotheses.append(Hypothesis(id: UUID(), kind: .referenceDifference,
                summary: "英语短答案与参考材料规范化后不一致。", evidence: evidence,
                reason: "词句差异可能来自表达方式或识别误差，不能仅凭关键词缺失断言知识错误。",
                nextAction: "核对原图拼写、时态和题目要求的答题形式。",
                certainty: .needsConfirmation, userDecision: .pending))
        }

        if hypotheses.isEmpty && Self.normalizedText(student) != Self.normalizedText(reference),
           student.count <= 1000 && reference.count <= 1000,
           let evidence = Self.evidencePair(snapshot: snapshot, student: student, reference: reference) {
            hypotheses.append(Hypothesis(id: UUID(), kind: .referenceDifference,
                summary: "学生作答与参考材料存在文本差异。", evidence: evidence,
                reason: "文本差异本身不是概念错误的充分证据，需结合题干和教师批注。",
                nextAction: "对照原题和参考解析，人工确认差异是否影响结论。",
                certainty: .needsConfirmation, userDecision: .pending))
        }

        if hypotheses.isEmpty {
            limitations.append("当前材料未触发安全规则；复杂证明、图形推理和主观评分保留原图待人工判断。")
        }
        return AnalysisResult(status: hypotheses.isEmpty ? .insufficientEvidence : .hypotheses,
                              hypotheses: hypotheses, limitations: limitations,
                              engineID: "mistakebook.rules", engineVersion: "1",
                              inputContentRevision: snapshot.contentRevision,
                              referenceAnswerSource: snapshot.referenceAnswerSource)
    }

    public func capabilities() async throws -> CapabilityReport {
        try Task.checkCancellation()
        return CapabilityReport(checkedAt: Date(), features: [
            FeatureCapability(feature: .basicAnalysis, subjectID: nil, state: .available,
                              reason: "可离线执行受限规则比较。", supportedLanguages: ["zh-Hans", "en"]),
            FeatureCapability(feature: .enhancedAnalysis, subjectID: nil, state: .unavailable,
                              reason: "基础规则服务未启用设备端生成模型。", supportedLanguages: [])
        ])
    }

    fileprivate static func insufficient(snapshot: RecordContentSnapshot, limitation: String) -> AnalysisResult {
        AnalysisResult(status: .insufficientEvidence, hypotheses: [], limitations: [limitation],
                       engineID: "mistakebook.rules", engineVersion: "1",
                       inputContentRevision: snapshot.contentRevision,
                       referenceAnswerSource: snapshot.referenceAnswerSource)
    }

    fileprivate static func numericValue(_ text: String) -> Double? {
        let normalized = text.replacingOccurrences(of: "，", with: ",")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let direct = Double(normalized.replacingOccurrences(of: ",", with: "")) { return direct }
        guard let range = normalized.range(of: #"[-+]?\d[\d\s+\-*/().]*"#, options: .regularExpression) else { return nil }
        let candidate = String(normalized[range])
        guard candidate.contains(where: { "+-*/".contains($0) }) else { return nil }
        var parser = ArithmeticParser(candidate)
        return parser.parse()
    }

    fileprivate static func looksLikeNumericTask(_ text: String) -> Bool {
        text.contains(where: { "+-*/=×÷".contains($0) })
            || text.localizedCaseInsensitiveContains("计算")
            || text.localizedCaseInsensitiveContains("solve")
    }

    fileprivate static func normalizedText(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: #"[\p{P}\p{S}\s]+"#, with: "", options: .regularExpression)
            .lowercased()
    }

    fileprivate static func normalizedSetExpression(_ text: String) -> String {
        normalizedText(text).replacingOccurrences(of: "，", with: ",")
    }

    private static func evidencePair(snapshot: RecordContentSnapshot, student: String, reference: String) -> [Evidence]? {
        guard let studentEvidence = evidence(snapshot: snapshot, source: .student, purpose: .studentWork, fallbackText: student),
              let referenceEvidence = evidence(snapshot: snapshot, source: .reference, purpose: .referenceAnswer, fallbackText: reference) else {
            return nil
        }
        return [studentEvidence, referenceEvidence]
    }

    private static func evidence(snapshot: RecordContentSnapshot, source: EvidenceSource,
                                 purpose: RegionPurpose, fallbackText: String) -> Evidence? {
        let region = snapshot.sourceRegions.first(where: { $0.purpose == purpose }) ?? snapshot.sourceRegions.first
        guard let region else { return nil }
        let line = snapshot.ocrLines.first(where: { $0.regionID == region.id }) ?? snapshot.ocrLines.first
        let quote = String((line?.rawText ?? fallbackText).prefix(240))
        return Evidence(regionID: region.id, lineID: line?.id, quote: quote.isEmpty ? nil : quote, evidenceSource: source)
    }
}

private struct ArithmeticParser {
    private let characters: [Character]
    private var index = 0

    init(_ expression: String) { self.characters = Array(expression) }

    mutating func parse() -> Double? {
        let value = parseExpression()
        skipSpaces()
        return index == characters.count ? value : nil
    }

    private mutating func parseExpression() -> Double? {
        guard var value = parseTerm() else { return nil }
        while true {
            skipSpaces()
            guard index < characters.count else { return value }
            let op = characters[index]
            guard op == "+" || op == "-" else { return value }
            index += 1
            guard let rhs = parseTerm() else { return nil }
            value = op == "+" ? value + rhs : value - rhs
        }
    }

    private mutating func parseTerm() -> Double? {
        guard var value = parseFactor() else { return nil }
        while true {
            skipSpaces()
            guard index < characters.count else { return value }
            let op = characters[index]
            guard op == "*" || op == "/" else { return value }
            index += 1
            guard let rhs = parseFactor(), op != "/" || abs(rhs) > 0.0000000001 else { return nil }
            value = op == "*" ? value * rhs : value / rhs
        }
    }

    private mutating func parseFactor() -> Double? {
        skipSpaces()
        if index < characters.count, characters[index] == "+" || characters[index] == "-" {
            let negative = characters[index] == "-"
            index += 1
            guard let value = parseFactor() else { return nil }
            return negative ? -value : value
        }
        if index < characters.count, characters[index] == "(" {
            index += 1
            guard let value = parseExpression() else { return nil }
            skipSpaces()
            guard index < characters.count, characters[index] == ")" else { return nil }
            index += 1
            return value
        }
        let start = index
        while index < characters.count && (characters[index].isNumber || characters[index] == ".") { index += 1 }
        guard start < index else { return nil }
        return Double(String(characters[start..<index]))
    }

    private mutating func skipSpaces() {
        while index < characters.count && characters[index].isWhitespace { index += 1 }
    }
}
