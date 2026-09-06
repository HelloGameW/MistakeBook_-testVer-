# 可选成就模块接入说明

## 结论

当前 `MistakeBook_Beta` 0.8.1（build 28）不直接接入成就 UI 或生产装配。成就功能已整理为独立的 `Packages/AchievementsKit` Swift Package，主工程当前不引用该目录，现有完成版本的行为、持久化模型和契约保持不变。

这是有意的接入闸门：主工程的 `AppService` 没有成就契约，也没有独立的“复习会话”事件；直接修改 `Contracts`、`LocalAppService`、SwiftData schema 或根 Tab 会扩大回归面。因此本版本只交付可编译验收的业务模块和接线协议，暂不把它视为 0.8.1 的产品功能。

## 模块边界

```text
MistakeBook AppService / RecordEvent / BatchEvent
                 │  适配字段（宿主负责）
                 ▼
        MistakeBookAchievementBridge
                 │  AchievementEvent
                 ▼
          AchievementEngine (actor)
                 │
                 ▼
   Achievements/state-v1.json（独立文件）
```

模块的唯一输入是 `AchievementEvent`。事件的 `id` 必须在重试和流重连时保持一致；重复事件会被忽略。模块只写自己的状态文件，不写错题记录、图片、设置和 SwiftData。

## 当前版本的最小接线方案

接入评审通过后，在 App 层（不是 `MistakeKit` 的 Contracts 层）增加本地包依赖，并在 `ProductionAssembly` 完成后启动一个可取消的观察任务：

```swift
import AchievementsKit
import Contracts

private func snapshot(_ record: MistakeRecord) -> AchievementRecordSnapshot {
    AchievementRecordSnapshot(
        id: record.id,
        recordRevision: record.recordRevision,
        reviewState: AchievementReviewState(rawValue: record.reviewState.rawValue) ?? .new,
        hasConfirmedClassification:
            record.classification.assignmentState == .userConfirmed &&
            record.classification.primaryNodeID != nil,
        acceptedAnalysisCount: record.analysisResult?.hypotheses
            .filter { $0.userDecision == .accepted }.count ?? 0,
        subjectID: record.classification.subjectID)
}

let store = JSONFileAchievementStateStore(
    fileURL: root.appendingPathComponent("Achievements/state-v1.json"))
let engine = try AchievementEngine(store: store)
let bridge = MistakeBookAchievementBridge(engine: engine)

let task = Task {
    let stream = try await service.observeRecords(recordID: nil)
    for await event in stream {
        guard event.kind != .failed else { continue }
        let kind: AchievementRecordChangeKind = switch event.kind {
        case .initial: .initial
        case .upserted: .upserted
        case .restored: .restored
        case .deleted: .deleted
        case .cleared: .cleared
        }
        do {
            _ = try await bridge.ingest(AchievementRecordChange(
                kind: kind, recordID: event.recordID,
                record: event.record.map(snapshot),
                occurredAt: event.record?.updatedAt ?? Date()))
        } catch {
            // 只记录诊断；不影响 AppService 已经完成的业务操作。
        }
    }
}
```

上例中的 `task` 必须由宿主保存并在清空数据、退出会话或模块关闭时取消。`initial` 事件只建立基线，避免首次开启功能时把历史错题全部算成新成就。若未来增加“导入批次”成就，应在批次终态处发送一次 `AchievementEvent.imported(...)`，不要在每个记录事件和批次事件中重复代表同一个目标。

## 接入验收与否决条件

满足以下条件后才适合进入后续功能版本：

1. `Packages/AchievementsKit` 自己的测试通过，主工程原有测试结果不发生变化。
2. 成就 JSON 文件位于独立目录，删除/损坏时只能影响成就，不得阻塞错题导入、查询、编辑、导出或清空流程。
3. 观察任务可取消；成就存储失败只记录为非阻塞错误，不回滚或阻断 `AppService` 的成功操作。
4. 初始事件不补发历史成就；升级、重启、重复推送不会重复解锁。
5. 只有真实用户动作才发送 `recordReviewed`、`recordMastered`、`recordClassified` 和 `analysisConfirmed`，不能把 OCR/自动分类的中间状态冒充用户成就。
6. UI 单独增加页面或入口，不修改现有错题/归档页面的核心状态机。

出现以下任一情况，当前版本应否决接入，继续以独立包形式保留：

- 必须改动 `MistakeKit` 的冻结 Contracts 或 SwiftData schema；
- 成就存储错误会阻塞现有业务操作；
- 无法为事件提供稳定 ID，或重连会重复累计；
- 只能通过全局 `AppService` 改写来截获事件，且没有可取消生命周期；
- 为了成就 UI 需要改变现有根导航、导入队列或记录编辑流程；
- 无法在真实 iOS/Xcode 环境证明主工程回归测试通过。

## 数据迁移与卸载

模块状态 schema 由 `AchievementModule.schemaVersion` 独立管理，目前为 1。未来升级只能在模块内部迁移 `AchievementState`；迁移失败应让成就模块不可用，并保留错题主数据。卸载功能时可删除 `Achievements/state-v1.json`，不会触碰 `MistakeBook.store` 或资源文件。
