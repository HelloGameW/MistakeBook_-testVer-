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

当前版本为 `0.2.9`，构建号为 `11`。`0.2.6`–`0.2.8` 依次修复了 Intelligence、UI、Export 目标的五处编译错误；`0.2.9` 修复模拟器测试构建失败（Xcode 26 会把模拟器 App 目标的 ARCHS_STANDARD 扩展出 x86_64 切片，而 SwiftPM 包模块只构建 arm64 模拟器切片，导致 x86_64 切片无法解析包模块；已在 xcconfig 中对模拟器 SDK 排除 x86_64）。
