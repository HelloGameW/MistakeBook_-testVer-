# 构建说明

这是统一后的 MistakeBook iOS/iPadOS 26 源码工程。

## Xcode

1. 使用支持 iOS 26 SDK 的 Xcode 打开 `MistakeBook.xcodeproj`。
2. 选择 `MistakeBook` scheme。
3. 在 Signing & Capabilities 中选择自己的 Team 和唯一 Bundle Identifier。
4. 在 iOS 26 模拟器或真机上 Build / Test / Run。

## 当前验证边界

通用 Swift 代码已在 Swift 6 环境完成编译检查。由于打包环境没有 Xcode、iOS SDK、Simulator 或真机，Apple 专属框架（SwiftUI、Vision、SwiftData、PDFKit、UIKit、Security 等）仍需在 Xcode 环境完成最终构建和运行验证。
