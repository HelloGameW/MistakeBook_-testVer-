# 构建说明

这是统一后的 MistakeBook iOS/iPadOS 26 源码工程。

## Xcode

1. 使用支持 iOS 26 SDK 的 Xcode 打开 `MistakeBook.xcodeproj`。
2. 选择 `MistakeBook` scheme。
3. 在 Signing & Capabilities 中选择自己的 Team 和唯一 Bundle Identifier。
4. 在 iOS 26 模拟器或真机上 Build / Test / Run。

版本号规则见 `docs/VERSIONING.md`。提交 bug 修复前运行 `sh Scripts/bump-version.sh bugfix`；提交新功能前运行 `sh Scripts/bump-version.sh feature`。

## Windows 本地编译检查（可选）

本机安装了 Swift 6.3.3（Asserts 工具链，`%LOCALAPPDATA%\Programs\Swift`）。该分发版把标准库放在独立的 Platforms 目录，构建前需要把工具链和运行时加入 PATH，并用 `SDKROOT` 指向 Windows SDK：

```sh
export PATH="/c/Users/$USERNAME/AppData/Local/Programs/Swift/Toolchains/6.3.3+Asserts/usr/bin:/c/Users/$USERNAME/AppData/Local/Programs/Swift/Runtimes/6.3.3/usr/bin:$PATH"
export SDKROOT='C:\Users\'"$USERNAME"'\AppData\Local\Programs\Swift\Platforms\6.3.3\Windows.platform\Developer\SDKs\Windows.sdk'
cd Packages/MistakeKit
swift build
```

预期结果：Contracts、Intelligence、Workflow、Export、UI、TestSupport、PreviewSupport 七个目标通过；`Storage` 失败属预期（`CoreGraphics`/`SwiftData` 等框架不存在于 Windows）。UI 与 PreviewSupport 在 Windows 上因 `#if os(iOS)` 编译为空模块，SwiftUI/Vision/FoundationModels/SwiftData 代码的最终验证仍以 Xcode/Codemagic 为准。

## 当前验证边界

通用 Swift 代码已在 Swift 6 环境完成编译检查。由于打包环境没有 Xcode、iOS SDK、Simulator 或真机，Apple 专属框架（SwiftUI、Vision、SwiftData、PDFKit、UIKit、Security 等）仍需在 Xcode 环境完成最终构建和运行验证。
