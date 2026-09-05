# MistakeBook

MistakeBook 是面向 iOS/iPadOS 26 的错题整理应用。
Model gpt 6(max),gpt luna(max)

## 核心能力

- 试卷/错题导入、图像处理与 OCR。
- Apple Vision 本地 OCR。
- 可选模型 OCR 与百度教育 OCR。
- 错因分析，支持本地规则与可配置模型 API。
- 错题价值量化与复习优先级。
- 知识分类、归档、搜索、编辑、删除恢复。
- PDF 导出。
- API 密钥使用系统 Keychain 保存。

## 工程结构

```text
MistakeBook/
├── MistakeBook.xcodeproj/
├── MistakeBook/                 # App 入口与生产装配
├── Packages/MistakeKit/         # 统一业务 Package
│   ├── Sources/Contracts
│   ├── Sources/Intelligence
│   ├── Sources/Storage
│   ├── Sources/Workflow
│   ├── Sources/UI
│   └── Sources/Export
├── Resources/                    # 知识树等 App 资源
├── Config/                       # Xcode 共享配置
├── Tests/                        # 工程级合成样例与集成检查
└── docs/                         # API 与构建说明
```

## 处理模式

- **本地**：Apple Vision OCR + 本地能力。
- **API**：按设置使用模型 OCR / 百度教育 OCR，以及模型错因分析和价值量化。
- **自动**：优先本地，在配置允许且本地结果不足时使用远程 Provider。

详细配置见 `docs/API_CONFIGURATION.md`，构建说明见 `docs/BUILD.md`。
