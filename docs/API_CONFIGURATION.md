# API 配置

MistakeBook 支持本地、API 和自动三种处理模式。

- OCR：Apple Vision、自定义模型 OCR、百度教育 OCR。
- 错因分析：OpenAI-compatible Chat Completions 风格模型接口。
- 错题价值量化：OpenAI-compatible 模型接口，模型返回维度分，客户端按固定权重计算总分。
- 百度教育 OCR：支持试卷切题与试卷分析策略。

所有 API 密钥均通过系统 Keychain 保存，不写入 SwiftData、UserDefaults、plist 或源码。自定义 Base URL 应使用 HTTPS。

如果未来公开分发并共享开发者密钥，建议改为服务端代理并重新核对隐私、配额和滥用控制。
