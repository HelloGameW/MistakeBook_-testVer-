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

当前版本为 `0.6.0`，构建号为 `24`。`0.6.0` 为功能版本：新增智谱 GLM OCR 服务商（multipart 调用 /paas/v4/files/ocr，`tool_type=hand_write`）与密钥可用性验证（验证通过显示绿灯，密钥状态显示"已填入 API"）；识别失败的任务状态如实标记为失败（此前误标为完成）；修正区域框选拖拽无响应（minimumDistance 0）；修复 Apple 智能无法关闭的问题（关闭时错因分析回落规则引擎）；界面文案整体书面化。
