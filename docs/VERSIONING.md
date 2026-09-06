# 版本规则

App 的用户可见版本号来自 `Config/Shared.xcconfig` 中的 `MARKETING_VERSION`，构建号来自 `CURRENT_PROJECT_VERSION`。

- 修复 bug：`主版本.次版本.修订号 + 1`，例如 `0.2.0` → `0.2.1`。
- 新增功能：次版本号 `+ 1`，修订号归零，例如 `0.2.1` → `0.3.0`。
- 每次版本变更同时将构建号递增 1。

使用仓库内脚本更新版本：

```sh
sh Scripts/bump-version.sh bugfix
sh Scripts/bump-version.sh feature
```

当前版本为 `0.2.7`，构建号为 `9`。`0.2.6` 修复了两处编译错误（FoundationModels `respond(to:)` 的 `Prompt` 类型适配、补齐 SettingsView 缺失的 `SecretField`）；`0.2.7` 继续修复 UI 目标的两处编译错误（`SecretField` 初始化器改用 `_text` 赋值 Binding、`RecordQuery` 实参顺序改为 `includeDeleted` → `sort` → `includeArchived`，并补充 `import UIKit`）。
