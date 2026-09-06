# API 配置

MistakeBook 支持本地、API 和自动三种处理模式。

- OCR：Apple Vision、GLM-OCR、自定义模型 OCR、百度教育 OCR。
- 错因分析：OpenAI-compatible Chat Completions 风格模型接口。
- 错题价值量化：OpenAI-compatible 模型接口，模型返回维度分，客户端按固定权重计算总分。
- 百度教育 OCR：支持试卷切题与试卷分析策略。

## GLM-OCR

在“设置 → 模型选择 → 智谱 GLM”中填写 BigModel API Key，并在“设置 → 模型选择 → 任务分配”将文字识别设为“智谱 GLM · glm-ocr”。图像识别使用智谱 OCR 文件解析工具，不发送未经文档定义的 `model` 表单字段：

- Endpoint：`https://open.bigmodel.cn/api/paas/v4/files/ocr`
- Method：`POST`，`Authorization: Bearer <API_KEY>`，`multipart/form-data`
- 表单字段：`file`、`tool_type=hand_write`、`language_type=CHN_ENG`、`probability=true`
- 支持 PNG/JPG/JPEG/BMP，单张图片不超过 8 MB；返回的 `words_result` 行文本、像素坐标和置信度会转换为应用内部的 OCR 行。

接口参数和返回结构以[智谱 OCR 官方文档](https://docs.bigmodel.cn/cn/guide/tools/zhipu-ocr)为准。

## DeepSeek

设置页提供“使用 DeepSeek 官方配置”快捷填充：

- 错因分析、价值量化：`https://api.deepseek.com` + `/chat/completions` + `deepseek-v4-flash`。
- 图片 OCR：使用 `deepseek-v4-flash-vision-exp`；普通文本模型不接受图片。
- DeepSeek 请求显式关闭 thinking 模式以保证结构化 JSON 提取稳定，并设置 JSON 输出与最大输出长度。
- HEIC 图片在发送到 DeepSeek OCR 前会转换为 JPEG；本地原图不会被覆盖。

DeepSeek 的模型名称和服务能力可能调整，快捷配置按当前官方文档提供的 V4 模型填写；如果服务商返回模型不可用，请在设置页更新模型名称。

所有 API 密钥均通过系统 Keychain 保存，不写入 SwiftData、UserDefaults、plist 或源码。自定义 Base URL 应使用 HTTPS。

如果未来公开分发并共享开发者密钥，建议改为服务端代理并重新核对隐私、配额和滥用控制。
