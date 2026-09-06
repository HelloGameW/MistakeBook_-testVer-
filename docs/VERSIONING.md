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

当前版本为 `0.2.10`，构建号为 `12`。`0.2.6`–`0.2.9` 依次修复了编译错误与模拟器架构切片问题；`0.2.10` 修复回归测试首次运行暴露的三处产品缺陷：`StoredRecordEntity.isDeleted` 与 SwiftData `PersistentModel.isDeleted` 语义冲突导致软删除不持久（重命名为 `isSoftDeleted`）；令牌存储负载经秒级 ISO8601 往返后严格相等比较必然失败（改为字段级比较）；Workflow 测试改用不依赖模拟器 Keychain 的凭据存储，并修正分段测试的表格 fixture 几何。
