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

当前版本为 `0.8.0`，构建号为 `27`。`0.8.0` 为功能版本：模型选择统一归入“模型选择”父级，图像识别默认使用智谱 `glm-ocr`，并接入 OCR 文件解析接口；同时新增跟随系统/浅色/深色配色、暗色与着色 App 图标，以及本机公告中心和管理入口，并保留各服务商的模型预设与手动输入能力。
