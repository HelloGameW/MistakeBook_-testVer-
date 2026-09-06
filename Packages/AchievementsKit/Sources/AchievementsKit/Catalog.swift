import Foundation

/// The catalog is a value, not a singleton service. Hosts may replace it,
/// append their own definitions, or ship a later catalog without changing the
/// engine or the persisted statistics.
public enum DefaultAchievementCatalog {
    public static let definitions: [AchievementDefinition] = [
        AchievementDefinition(id: "organizing.first-record", category: .organizing,
            title: "初次整理", detail: "保存第一道错题", iconSystemName: "book.closed.fill",
            requirement: .eventCount(kind: .recordCreated, target: 1)),
        AchievementDefinition(id: "organizing.record-collector-10", category: .organizing,
            title: "错题收集者", detail: "累计整理 10 道错题", iconSystemName: "books.vertical.fill",
            requirement: .uniqueRecordCount(kind: .recordCreated, target: 10)),
        AchievementDefinition(id: "organizing.record-collector-50", category: .organizing,
            title: "错题档案馆", detail: "累计整理 50 道错题", iconSystemName: "archivebox.fill",
            requirement: .uniqueRecordCount(kind: .recordCreated, target: 50)),
        AchievementDefinition(id: "reviewing.first-review", category: .reviewing,
            title: "开始复习", detail: "完成第一次复习状态更新", iconSystemName: "arrow.clockwise.circle.fill",
            requirement: .eventCount(kind: .recordReviewed, target: 1)),
        AchievementDefinition(id: "mastery.first", category: .mastery,
            title: "初见掌握", detail: "掌握第一道错题", iconSystemName: "checkmark.seal.fill",
            requirement: .uniqueRecordCount(kind: .recordMastered, target: 1)),
        AchievementDefinition(id: "mastery.ten", category: .mastery,
            title: "掌握十题", detail: "累计掌握 10 道不同错题", iconSystemName: "medal.fill",
            requirement: .uniqueRecordCount(kind: .recordMastered, target: 10)),
        AchievementDefinition(id: "reflection.first-analysis", category: .reflection,
            title: "认真核对", detail: "确认第一次错因分析", iconSystemName: "checkmark.message.fill",
            requirement: .eventCount(kind: .analysisConfirmed, target: 1)),
        AchievementDefinition(id: "exploration.subjects-3", category: .exploration,
            title: "学科探索者", detail: "在 3 个学科整理过错题", iconSystemName: "graduationcap.fill",
            requirement: .uniqueSubjectCount(target: 3)),
        AchievementDefinition(id: "consistency.streak-3", category: .consistency,
            title: "三日坚持", detail: "连续 3 个日历日有学习活动", iconSystemName: "flame.fill",
            requirement: .activeDayStreak(target: 3))
    ]
}
