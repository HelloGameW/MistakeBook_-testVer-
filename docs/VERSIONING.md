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

当前版本为 `0.5.0`，构建号为 `20`。说明：错题量化体系应用时（提交 b3ef331）误将 README/VERSIONING 手写为 0.5.0/19 而未执行版本脚本，导致 xcconfig 停留在 0.4.3 并被后续修复轮顺延为 0.4.4/19，出现版本号回退假象；现按功能规则正式补齐为 0.5.0/20。今后版本号一律通过 `Scripts/bump-version.sh` 变更，不再手改。
