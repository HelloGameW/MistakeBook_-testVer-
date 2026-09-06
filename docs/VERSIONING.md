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

当前版本为 `0.6.1`，构建号为 `25`。`0.6.1` 修复 `credentialTitle` 的 switch 漏掉新增的 `glmAPIKey` case 导致的 switch must be exhaustive 编译错误；已全仓库排查 `OCRProviderKind`/`CredentialKind` 的全部 switch 均已穷尽。
