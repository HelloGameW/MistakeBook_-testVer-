# AchievementsKit

`AchievementsKit` 是 MistakeBook 的可选、无 UI、无 SwiftData 依赖成就模块。

它只接受宿主应用发出的事实事件，计算并持久化自己的成就状态；不会调用、修改或依赖 `MistakeKit` 的 `Contracts`、`AppService`、SwiftData schema、资源、版本号或生产装配。因此它可以先作为独立包验收，确认无回归后再接入主工程。

## 包含内容

- `AchievementEngine`：actor 串行处理事件，稳定事件 ID 幂等去重。
- `AchievementStateStore`：内存存储和独立 JSON 文件存储。
- `AchievementDefinition`：可替换目录和可 Codable 的内置规则。
- `MistakeBookAchievementBridge`：只镜像现有错题事件所需字段，初始流只建立基线，不奖励历史记录。
- `DefaultAchievementCatalog`：整理、复习、掌握、错因核对、学科探索、连续学习六类默认成就。

## 最小使用

```swift
let store = JSONFileAchievementStateStore(
    fileURL: root.appendingPathComponent("Achievements/state-v1.json"))
let engine = try AchievementEngine(store: store)

let update = try await engine.ingest(
    .recordCreated(recordID: recordID, occurredAt: Date(), subjectID: "math"))
for achievement in update.newlyUnlocked {
    print(achievement.definition.title)
}
```

默认目录不会接收现有记录的历史补发；如果产品确实要补发，需要由宿主显式发送带有确定规则的迁移事件。
