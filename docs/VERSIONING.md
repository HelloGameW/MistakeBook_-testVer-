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

当前版本为 `0.4.3`，构建号为 `18`。`0.4.3` 修复设置页 SwiftUI body 表达式超出类型检查时间预算的问题（CI 报 "the compiler is unable to type-check this expression in reasonable time"），已将巨型 body 拆分为七个独立的 Section 子视图属性。
