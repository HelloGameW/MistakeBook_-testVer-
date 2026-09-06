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

当前版本为 `0.4.4`，构建号为 `19`。`0.4.4` 修复设置页"服务商"分节的非法 Section 形态（`Section("标题") { } footer: { }` 不是合法初始化器，导致 extra trailing closure 编译错误），已改为 `Section { } header: { } footer: { }`，并全仓库排查确认无同类写法。
