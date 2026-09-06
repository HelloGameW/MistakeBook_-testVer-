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

当前版本为 `0.7.0`，构建号为 `26`。`0.7.0` 为功能版本：智谱 GLM 升级为全功能服务商——错因分析与复习价值可选用 GLM 对话模型（BigModel OpenAI 兼容端点 /chat/completions），GLM 密钥验证的探针图改为真实渲染图（修复 1×1 探针导致的 400），各服务商提供常用模型预设下拉（ChatGPT：gpt-6 astra / gpt-5.6 sol / luna / terra），手动输入保留。
