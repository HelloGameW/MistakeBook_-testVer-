import Foundation
import Contracts

/// 课标属性层文件（按 subjectID 组织，键与 seed.json 节点 ID 对齐）。
private struct CurriculumParameters: Decodable {
    struct StaticWeights: Decodable {
        let hourShare: Double
        let cognitive: Double
        let examWeight: Double
        let scope: Double
        let centrality: Double
        let competency: Double
    }
        struct TargetFit: Decodable {
            let normal: Double
            let stretch: Double
            let beyond: Double
            let fBase: Double

            // JSON 键为 F_base（大写 F + 下划线），合成解码会找不到键。
            enum CodingKeys: String, CodingKey { case normal, stretch, beyond, fBase = "F_base" }
        }
    struct Repeat: Decodable { let alpha: Double; let cap: Double }
    struct Propagation: Decodable { let lambda: Double; let cap: Double }
    struct Priority: Decodable { let gamma: Double }
    struct DueFactor: Decodable {
        let firstPending: Double
        let overdueShort: Double
        let overdueLong: Double
        let notDue: Double
        let unplanned: Double
    }
    struct Levels: Decodable { let high: Double; let medium: Double }

    enum CodingKeys: String, CodingKey {
        case staticWeights, scopeTable
        case repeatParams = "repeat"
        case targetFit, propagation, priority, dueFactor, levels
    }

    let staticWeights: StaticWeights
    let scopeTable: [String: [String: Double]]
    let repeatParams: Repeat
    let targetFit: TargetFit
    let propagation: Propagation
    let priority: Priority
    let dueFactor: DueFactor
    let levels: Levels
}

private struct CurriculumErrorTypeFile: Decodable {
    struct Entry: Decodable { let id: String; let name: String; let weight: Double }
    let types: [Entry]
}

private struct CurriculumSubjectFile: Decodable {
    struct Standard: Decodable { let competencies: [String]? }
    struct NodeAttribute: Decodable {
        let courseType: String
        let theme: String?
        let hours: Double?
        let cognitiveLevel: Double
        let competencies: [String]
        let examScope: String
        let examWeightPrior: Double
        let prerequisites: [String]

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            courseType = try c.decodeIfPresent(String.self, forKey: .courseType) ?? "必修"
            theme = try c.decodeIfPresent(String.self, forKey: .theme)
            hours = try c.decodeIfPresent(Double.self, forKey: .hours)
            cognitiveLevel = try c.decodeIfPresent(Double.self, forKey: .cognitiveLevel) ?? 2
            competencies = try c.decodeIfPresent([String].self, forKey: .competencies) ?? []
            examScope = try c.decodeIfPresent(String.self, forKey: .examScope) ?? "高考"
            examWeightPrior = try c.decodeIfPresent(Double.self, forKey: .examWeightPrior) ?? 0
            prerequisites = try c.decodeIfPresent([String].self, forKey: .prerequisites) ?? []
        }

        enum CodingKeys: String, CodingKey {
            case courseType, theme, hours, cognitiveLevel, competencies
            case examScope, examWeightPrior, prerequisites
        }
    }
    let subjectID: String
    let name: String
    let attributesVersion: String
    let standard: Standard?
    let attributes: [String: NodeAttribute]
}

/// 学科内的静态特征与图计算（W(k) 六特征、先修 DAG 中心度/传导）。
private struct CurriculumSubject {
    let file: CurriculumSubjectFile
    let params: CurriculumParameters

    init(file: CurriculumSubjectFile, params: CurriculumParameters) {
        self.file = file
        self.params = params
    }

    var attributesVersion: String { file.attributesVersion }
    var attributes: [String: CurriculumSubjectFile.NodeAttribute] { file.attributes }

    /// 下游覆盖率结构中心度（学科内归一）。
    func centrality(of nodeID: String) -> Double {
        let total = max(attributes.count - 1, 1)
        var raw: [String: Double] = [:]
        for nid in attributes.keys {
            raw[nid] = Double(descendants(of: nid).count) / Double(total)
        }
        let maxRaw = raw.values.max() ?? 0
        guard maxRaw > 0 else { return 0 }
        return (raw[nodeID] ?? 0) / maxRaw
    }

    func descendants(of nodeID: String) -> Set<String> {
        var seen: Set<String> = []
        var stack = [nodeID]
        while let current = stack.popLast() {
            for (successor, attr) in attributes where attr.prerequisites.contains(current) && !seen.contains(successor) {
                seen.insert(successor)
                stack.append(successor)
            }
        }
        seen.remove(nodeID)
        return seen
    }

    func hourShare(of nodeID: String) -> Double? {
        guard let attr = attributes[nodeID], let hours = attr.hours, hours > 0 else { return nil }
        let total = attributes.values.compactMap(\.hours).reduce(0, +)
        return total > 0 ? hours / total : nil
    }

    func scopeValue(for attr: CurriculumSubjectFile.NodeAttribute) -> Double {
        params.scopeTable["gaokao"]?[attr.courseType] ?? 0.8
    }

    /// W(k) 与六特征明细；缺数据的特征自动关闭并按剩余权重归一。
    func staticFeatures(_ nodeID: String) -> [String: Double] {
        guard let attr = attributes[nodeID] else { return [:] }
        let competencyTotal = max(file.standard?.competencies?.count ?? 0, 1)
        var features: [String: Double?] = [
            "hourShare": hourShare(of: nodeID),
            "cognitive": attr.cognitiveLevel / 4,
            "examWeight": attr.examWeightPrior,
            "scope": scopeValue(for: attr),
            "centrality": centrality(of: nodeID),
            "competency": min(Double(attr.competencies.count) / Double(competencyTotal), 1),
        ]
        let weights = params.staticWeights
        var weightedSum = 0.0
        var weightSum = 0.0
        for (key, value) in features {
            guard let value, value.isFinite else { continue }
            let weight: Double
            switch key {
            case "hourShare": weight = weights.hourShare
            case "cognitive": weight = weights.cognitive
            case "examWeight": weight = weights.examWeight
            case "scope": weight = weights.scope
            case "centrality": weight = weights.centrality
            case "competency": weight = weights.competency
            default: continue
            }
            weightedSum += weight * min(max(value, 0), 1)
            weightSum += weight
        }
        guard weightSum > 0 else { return [:] }
        features["W"] = weightedSum / weightSum
        return features.compactMapValues { $0 }
    }

    /// 主考点全权重 + 次要考点半权重的平均。
    func weightedStaticImportance(_ nodeIDs: [String]) -> (W: Double, nodeIDs: [String]) {
        guard !nodeIDs.isEmpty else { return (0, []) }
        var parts: [Double] = []
        var used: [String] = []
        for (index, nodeID) in nodeIDs.enumerated() {
            guard attributes[nodeID] != nil else { continue }
            let features = staticFeatures(nodeID)
            guard let w = features["W"] else { continue }
            parts.append(index == 0 ? w : w * 0.5)
            used.append(nodeID)
        }
        return (parts.isEmpty ? 0 : parts.reduce(0, +) / Double(parts.count), used)
    }

    /// 目标适配（两把尺不可混用）：考试范围尺决定放弃，认知层级尺只在合格考降档。
    func targetFit(nodeID: String) -> (fit: Double, reason: String) {
        guard let attr = attributes[nodeID] else { return (1, "未知考点") }
        let goal = "gaokao"
        if attr.examScope == "非新高考主干" || (goal == "huige" && attr.courseType == "选择性必修") {
            return (params.targetFit.beyond, "超出考试范围(战略性放弃)")
        }
        if goal == "huige" && attr.cognitiveLevel >= 3 {
            return (params.targetFit.stretch, "合格考目标·掌握/运用级内容降档")
        }
        return (params.targetFit.normal, "目标考试范围内")
    }

    /// 下游考点未掌握 → 上游错题优先级放大。
    func propagationFactor(nodeID: String, masteryMap: [String: Double]) -> Double {
        var total = 0.0
        for descendant in descendants(of: nodeID) {
            let features = staticFeatures(descendant)
            guard let w = features["W"] else { continue }
            total += w * (1 - min(max(masteryMap[descendant] ?? 0, 0), 1))
        }
        return min(1 + params.propagation.lambda * total, params.propagation.cap)
    }
}

/// 课标量化体系引擎（docs/03 模型的 Swift 移植，参考实现见 课标量化体系/src）。
///
///     W(k) = Σ wᵢ·fᵢ（缺数据特征自动关闭并按剩余权重归一）
///     I(q) = 100 × W(k̄) × F_repeat × F_error × F_target × F_prop
///     P(q) = I(q) × (1 − mastery)^γ × F_due
///
/// 属性层 JSON 随包内置（Bundle.module），键与 seed.json 节点 ID 对齐。
public struct CurriculumQuantificationEngine: CurriculumQuantificationService {
    private let params: CurriculumParameters
    private let errorTypeWeights: [String: Double]
    private let errorTypeNames: [String: String]
    private let subjects: [String: CurriculumSubject]

    /// 一次量化所需的可解释明细。
    struct Assessment {
        let staticWeight: Double
        let features: [String: Double]
        let repeatFactor: Double
        let errorWeight: Double
        let errorName: String
        let targetFactor: Double
        let targetReason: String
        let propagationFactor: Double
        let mastery: Double
        let dueFactor: Double
        let importance: Double
        let priority: Double
        let examValue: Double
        let reasoningValue: Double
        let recurrenceRisk: Double
        let theme: String
        let nodeID: String
        let reason: String
    }

    /// 属性层覆盖的学科清单；新增学科 = 增加数据文件 + 在此登记。
    private static let subjectIDs = ["math", "physics", "chemistry", "biology",
                                     "chinese", "english", "civics", "history", "geography"]

    public init?() {
        guard let paramsURL = Bundle.module.url(forResource: "params", withExtension: "json",
                                                subdirectory: "CurriculumQuantification"),
              let errorURL = Bundle.module.url(forResource: "error_types", withExtension: "json",
                                               subdirectory: "CurriculumQuantification") else { return nil }
        do {
            params = try JSONDecoder().decode(CurriculumParameters.self, from: Data(contentsOf: paramsURL))
            let errorFile = try JSONDecoder().decode(CurriculumErrorTypeFile.self, from: Data(contentsOf: errorURL))
            errorTypeWeights = Dictionary(uniqueKeysWithValues: errorFile.types.map { ($0.id, $0.weight) })
            errorTypeNames = Dictionary(uniqueKeysWithValues: errorFile.types.map { ($0.id, $0.name) })
            var loaded: [String: CurriculumSubject] = [:]
            for id in Self.subjectIDs {
                guard let url = Bundle.module.url(forResource: id, withExtension: "json",
                                                  subdirectory: "CurriculumQuantification/subjects"),
                      let subjectFile = try? JSONDecoder().decode(CurriculumSubjectFile.self, from: Data(contentsOf: url)) else { continue }
                loaded[subjectFile.subjectID] = CurriculumSubject(file: subjectFile, params: params)
            }
            guard !loaded.isEmpty else { return nil }
            subjects = loaded
        } catch { return nil }
    }

    // MARK: - CurriculumQuantificationService

    public func quantifiedResult(base: MistakeValueResult, nodeID: String?, hypothesisKinds: [HypothesisKind],
                                 times: Int, mastery: Double, due: CurriculumDueState) async -> MistakeValueResult? {
        guard let nodeID, !nodeID.isEmpty,
              let assessment = assess(nodeIDs: [nodeID], times: times,
                                      hypothesisKinds: hypothesisKinds, mastery: mastery, due: due) else { return nil }
        let dimensions = MistakeValueDimensions(
            knowledgeValue: assessment.staticWeight,
            representativeness: base.dimensions.representativeness,
            recurrenceRisk: assessment.recurrenceRisk,
            reasoningValue: assessment.reasoningValue,
            examValue: assessment.examValue,
            reviewPriority: assessment.priority / 100)
        return LocalHeuristicMistakeValueService.result(
            dimensions: dimensions,
            reason: assessment.reason + "；" + base.reason,
            engineID: "curriculum.quantification",
            engineVersion: subjectVersion(for: nodeID) ?? "unknown",
            revision: base.inputContentRevision)
    }

    // MARK: - 模型

    func assess(nodeIDs: [String], times: Int, hypothesisKinds: [HypothesisKind],
                mastery: Double, due: CurriculumDueState) -> Assessment? {
        guard let primary = nodeIDs.first, let subject = subject(for: primary) else { return nil }
        let weighted = subject.weightedStaticImportance(nodeIDs)
        guard weighted.W > 0, let first = weighted.nodeIDs.first,
              let attr = subject.attributes[first] else { return nil }

        let fRepeat = repeatFactor(times: times)
        let error = mostSevereError(hypothesisKinds)
        let (fit, fitReason) = subject.targetFit(nodeID: primary)
        let fTarget = params.targetFit.fBase + 0.5 * fit
        let fProp = subject.propagationFactor(nodeID: primary, masteryMap: [primary: mastery])

        let importance = _clamp(100 * weighted.W * fRepeat * error.weight * fTarget * fProp, 0, 100)
        let clampedMastery = _clamp(mastery, 0, 1)
        let priority = _clamp(importance * pow(1 - clampedMastery, params.priority.gamma) * dueFactor(due), 0, 100)

        let features = subject.staticFeatures(primary)
        let examValue = _clamp((features["examWeight"] ?? 0) * 0.5 + (features["scope"] ?? 0) * 0.5, 0, 1)
        let reasoningValue = _clamp((features["cognitive"] ?? 0) * error.weight, 0, 1)
        let recurrenceRisk = _clamp(fRepeat * fProp / 2, 0, 1)

        let reason = "考点「\(attr.theme ?? first)」静态重要度 W=\(formatted(weighted.W))；"
            + "错因[\(error.name)]×\(formatted(error.weight))，第\(max(1, times))次出错×\(formatted(fRepeat))，"
            + "目标适配(\(fitReason))×\(formatted(fTarget))，依赖传导×\(formatted(fProp))；"
            + "掌握度\(formatted(clampedMastery))，时效\(due.rawValue)"

        return Assessment(staticWeight: weighted.W, features: features,
                          repeatFactor: fRepeat, errorWeight: error.weight, errorName: error.name,
                          targetFactor: fTarget, targetReason: fitReason, propagationFactor: fProp,
                          mastery: clampedMastery, dueFactor: dueFactor(due),
                          importance: importance, priority: priority,
                          examValue: examValue, reasoningValue: reasoningValue, recurrenceRisk: recurrenceRisk,
                          theme: attr.theme ?? "", nodeID: first, reason: reason)
    }

    private func repeatFactor(times: Int) -> Double {
        _clamp(1 + params.repeatParams.alpha * log2(1 + Double(max(times, 1))), 1, params.repeatParams.cap)
    }

    private func dueFactor(_ due: CurriculumDueState) -> Double {
        switch due {
        case .firstPending: params.dueFactor.firstPending
        case .overdueShort: params.dueFactor.overdueShort
        case .overdueLong: params.dueFactor.overdueLong
        case .notDue: params.dueFactor.notDue
        case .unplanned: params.dueFactor.unplanned
        }
    }

    /// App 错因假设 → 模型错因权重（取候选中最严重者）；无候选时取审题类折中值。
    private func mostSevereError(_ kinds: [HypothesisKind]) -> (weight: Double, name: String) {
        let mapped: [(weight: Double, name: String)] = kinds.map { kind -> (weight: Double, name: String) in
            let id: String
            switch kind {
            case .knowledge, .confusion: id = "concept"
            case .possibleSolutionError: id = "principle"
            case .reasoning, .strategy: id = "transfer"
            case .procedure: id = "operation"
            case .reading: id = "reading"
            case .expression: id = "presentation"
            case .recognitionConcern, .referenceDifference: id = "reading"
            }
            return (weight: errorTypeWeights[id] ?? 0.6, name: errorTypeNames[id] ?? "未分类错因")
        }
        return mapped.max(by: { $0.weight < $1.weight }) ?? (weight: 0.6, name: "未分类错因")
    }

    private func subject(for nodeID: String) -> CurriculumSubject? {
        let root = nodeID.split(separator: "/").first.map(String.init) ?? nodeID
        return subjects[root]
    }

    private func subjectVersion(for nodeID: String) -> String? {
        subject(for: nodeID).map { $0.attributesVersion }
    }

    private func formatted(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func _clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        max(lo, min(hi, x))
    }
}
