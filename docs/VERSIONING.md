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

当前版本为 `0.2.8`，构建号为 `10`。`0.2.6`/`0.2.7` 依次修复 Intelligence 与 UI 目标的四处编译错误；`0.2.8` 修复 Export 目标的一处编译错误（`drawWrapped` 调用缺少 `spacing:` 参数，该调用位于 `#if os(iOS)` 的 PDF 渲染函数内，Windows 本地编译检查无法覆盖）。
