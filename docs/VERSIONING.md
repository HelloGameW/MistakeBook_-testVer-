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

当前版本为 `0.3.1`，构建号为 `14`。`0.3.0` 新增错题内容双模式并修复详情页空白闪退；`0.3.1` 修正图片模式测试的坐标假设——`UIGraphicsImageRenderer` 默认继承模拟器 3x 显示缩放，PNG 实际像素为点尺寸的三倍，测试渲染时已强制 `scale = 1`（产品裁剪逻辑经该轮验证正确）。
