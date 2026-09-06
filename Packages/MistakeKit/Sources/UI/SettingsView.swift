#if os(iOS)
import SwiftUI
import Contracts

@MainActor
struct SettingsView: View {
    let service: any AppService

    @Environment(\.dismiss) private var dismiss
    @State private var capabilities = CapabilityReport(checkedAt: .now, features: [])
    @State private var credentialStatus = CredentialStatus(configured: [])

    @State private var languageText = "zh-Hans, en-US"
    @State private var enhancedAnalysisEnabled = true
    @State private var autoArchivePolicy = AutoArchivePolicy(version: "suggestions-only", enabledRules: [])
    @State private var processingMode: ProcessingMode = .local
    @State private var ocrProvider: OCRProviderKind = .appleVision
    @State private var analysisProvider: AnalysisProviderKind = .appleFoundationModels
    @State private var valueProvider: MistakeValueProviderKind = .localHeuristic

    @State private var ocrBaseURL = ""
    @State private var ocrEndpoint = "/chat/completions"
    @State private var ocrModel = ""
    @State private var analysisBaseURL = ""
    @State private var analysisEndpoint = "/chat/completions"
    @State private var analysisModel = ""
    @State private var valueBaseURL = ""
    @State private var valueEndpoint = "/chat/completions"
    @State private var valueModel = ""

    @State private var baiduStrategy: BaiduEducationStrategy = .automatic
    @State private var baiduFormula = true
    @State private var baiduLayout = true
    @State private var baiduMixed = true

    // SecretFields are intentionally never populated from Keychain.
    @State private var ocrKey = ""
    @State private var analysisKey = ""
    @State private var valueKey = ""
    @State private var baiduAPIKey = ""
    @State private var baiduSecretKey = ""

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var pendingClearConfirmation: ClearDataConfirmation?
    @State private var showingClearAlert = false
    @State private var showingAllExport = false

    var body: some View {
        NavigationStack {
            Form {
                if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
                if let actionMessage { Section { NoticeBanner(message: actionMessage) } }

                Section("处理模式") {
                    Picker("模式", selection: $processingMode) {
                        Text("本地").tag(ProcessingMode.local)
                        Text("API").tag(ProcessingMode.api)
                        Text("自动").tag(ProcessingMode.automatic)
                    }
                    .pickerStyle(.segmented)
                    Text(modeExplanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    TextField("识别语言（逗号分隔）", text: $languageText)
                    Toggle("允许 Apple 设备端增强分析", isOn: $enhancedAnalysisEnabled)
                }

                Section("OCR") {
                    Picker("识别服务", selection: $ocrProvider) {
                        Text("Apple Vision").tag(OCRProviderKind.appleVision)
                        Text("模型 API").tag(OCRProviderKind.modelAPI)
                        Text("百度教育 OCR").tag(OCRProviderKind.baiduEducation)
                    }
                    if processingMode == .local && ocrProvider != .appleVision {
                        NoticeBanner(message: "本地模式会强制使用 Apple Vision；这里选择的 API OCR 只在 API/自动模式生效。")
                    }
                    if ocrProvider == .modelAPI {
                        APIConfigurationFields(title: "OCR 模型", deepSeekModel: ModelAPIConfiguration.deepSeekVision.model,
                                               baseURL: $ocrBaseURL, endpoint: $ocrEndpoint, model: $ocrModel)
                    }
                    if ocrProvider == .baiduEducation {
                        Picker("百度识别策略", selection: $baiduStrategy) {
                            Text("自动：切题失败后转试卷分析").tag(BaiduEducationStrategy.automatic)
                            Text("试卷切题").tag(BaiduEducationStrategy.paperCut)
                            Text("试卷分析").tag(BaiduEducationStrategy.documentAnalysis)
                        }
                        Toggle("公式识别", isOn: $baiduFormula)
                        Toggle("版面分析", isOn: $baiduLayout)
                        Toggle("手写 / 印刷混排", isOn: $baiduMixed)
                    }
                }

                Section("错因分析") {
                    Picker("分析服务", selection: $analysisProvider) {
                        Text("本地规则").tag(AnalysisProviderKind.localRules)
                        Text("Apple Foundation Models").tag(AnalysisProviderKind.appleFoundationModels)
                        Text("模型 API").tag(AnalysisProviderKind.modelAPI)
                    }
                    if analysisProvider == .modelAPI {
                        APIConfigurationFields(title: "错因模型", deepSeekModel: ModelAPIConfiguration.deepSeekText.model,
                                               baseURL: $analysisBaseURL, endpoint: $analysisEndpoint, model: $analysisModel)
                    }
                    Text("API 错因输出会校验 regionID / lineID 与原始 OCR 证据；引用不存在的证据会被拒绝。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("错题价值量化") {
                    Picker("量化服务", selection: $valueProvider) {
                        Text("本地启发式").tag(MistakeValueProviderKind.localHeuristic)
                        Text("模型 API").tag(MistakeValueProviderKind.modelAPI)
                    }
                    if valueProvider == .modelAPI {
                        APIConfigurationFields(title: "价值模型", deepSeekModel: ModelAPIConfiguration.deepSeekText.model,
                                               baseURL: $valueBaseURL, endpoint: $valueEndpoint, model: $valueModel)
                    }
                    Text("模型只判断六个维度；最终总分由 App 的固定权重计算，避免模型直接给出漂移总分。")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                if processingMode != .local || ocrProvider != .appleVision || analysisProvider == .modelAPI || valueProvider == .modelAPI {
                    Section("API 凭据") {
                        if ocrProvider == .modelAPI {
                            SecretField(secretLabel("OCR API Key", .ocrModelAPIKey), text: $ocrKey)
                                .textContentType(.password)
                        }
                        if analysisProvider == .modelAPI {
                            SecretField(secretLabel("错因分析 API Key", .analysisModelAPIKey), text: $analysisKey)
                                .textContentType(.password)
                        }
                        if valueProvider == .modelAPI {
                            SecretField(secretLabel("价值量化 API Key", .mistakeValueModelAPIKey), text: $valueKey)
                                .textContentType(.password)
                        }
                        if ocrProvider == .baiduEducation {
                            SecretField(secretLabel("百度 API Key", .baiduAPIKey), text: $baiduAPIKey)
                                .textContentType(.password)
                            SecretField(secretLabel("百度 Secret Key", .baiduSecretKey), text: $baiduSecretKey)
                                .textContentType(.password)
                        }
                        Text("留空不会覆盖已经保存的密钥。密钥仅写入系统 Keychain，不写入 SwiftData、设置 JSON 或日志。")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("保存当前填写的密钥") { saveCredentials() }
                        if !credentialStatus.configured.isEmpty {
                            Menu("清除已保存的密钥") {
                                ForEach(credentialStatus.configured, id: \.self) { kind in
                                    Button(credentialTitle(kind), role: .destructive) { clearCredential(kind) }
                                }
                            }
                        }
                    }
                }

                Section("保存") {
                    Button(isSaving ? "保存中…" : "保存设置") { saveSettings() }
                        .disabled(isSaving)
                }

                Section("设备与服务能力") {
                    if isLoading && capabilities.features.isEmpty {
                        HStack { ProgressView(); Text("正在检查能力…") }
                    }
                    ForEach(capabilities.features, id: \.featureKey) { feature in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(featureTitle(feature.feature))
                                Spacer()
                                Text(UIStrings.capabilityState(feature.state)).foregroundStyle(capabilityColor(feature.state))
                            }
                            if let subjectID = feature.subjectID { Text(subjectID).font(.caption).foregroundStyle(.secondary) }
                            Text(feature.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }

                Section("隐私与备份") {
                    Label("本地模式不上传题目内容。API/自动模式在调用远程能力时会把对应图片或题目文本发送到你配置的服务商。", systemImage: "lock.shield")
                    Label("题目、原图和附件仍保存在本机；导出 PDF 是阅读副本，不是数据库备份。", systemImage: "externaldrive")
                }

                Section("数据管理") {
                    Button("导出全部题目") { showingAllExport = true }
                    Button("清空本地数据", role: .destructive) { prepareClear() }
                    Text("清空会终止作业并删除记录、原图、缓存、撤销令牌、设置以及本 App 保存的 API 密钥，确认后无法撤销。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
            .task { load() }
            .sheet(isPresented: $showingAllExport) { AllRecordsExportSheet(service: service) }
            .alert("确认清空本地数据", isPresented: $showingClearAlert, presenting: pendingClearConfirmation) { confirmation in
                Button("清空且无法撤销", role: .destructive) { clear(confirmation) }
                Button("取消", role: .cancel) {}
            } message: { confirmation in
                Text("将删除 \(confirmation.inventory.recordCount) 道错题、\(confirmation.inventory.assetCount) 个图片资产，并终止 \(confirmation.inventory.activeJobCount) 个活动作业。")
            }
        }
    }

    private var modeExplanation: String {
        switch processingMode {
        case .local: "全部学习内容保持在设备端；OCR 强制使用 Apple Vision。"
        case .api: "按下方 Provider 直接调用配置的接口。"
        case .automatic: "优先走本地路径；OCR 明显低质量时可转到所选 API，价值量化 API 失败会回退本地。"
        }
    }

    private func load() {
        Task {
            do {
                async let loadedSettings = service.settings()
                async let loadedCapabilities = service.capabilities()
                async let loadedCredentials = service.credentialStatus()
                let s = try await loadedSettings
                capabilities = try await loadedCapabilities
                credentialStatus = try await loadedCredentials
                languageText = s.recognitionLanguages.joined(separator: ", ")
                enhancedAnalysisEnabled = s.enhancedAnalysisEnabled
                autoArchivePolicy = s.autoArchivePolicy
                processingMode = s.resolvedProcessingMode
                ocrProvider = s.resolvedOCRProvider
                analysisProvider = s.resolvedAnalysisProvider
                valueProvider = s.resolvedMistakeValueProvider
                apply(s.ocrModelAPI, base: &ocrBaseURL, endpoint: &ocrEndpoint, model: &ocrModel)
                apply(s.analysisModelAPI, base: &analysisBaseURL, endpoint: &analysisEndpoint, model: &analysisModel)
                apply(s.mistakeValueModelAPI, base: &valueBaseURL, endpoint: &valueEndpoint, model: &valueModel)
                let baidu = s.baiduEducation ?? BaiduEducationConfiguration()
                baiduStrategy = baidu.strategy; baiduFormula = baidu.recognizeFormula
                baiduLayout = baidu.layoutAnalysis; baiduMixed = baidu.mixedHandwriting
                errorMessage = nil
            } catch { errorMessage = UIErrorMessage.from(error) }
            isLoading = false
        }
    }

    private func saveSettings() {
        isSaving = true
        let languages = languageText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let next = AppSettings(recognitionLanguages: languages.isEmpty ? ["zh-Hans"] : languages,
            enhancedAnalysisEnabled: enhancedAnalysisEnabled, autoArchivePolicy: autoArchivePolicy,
            processingMode: processingMode, ocrProvider: ocrProvider, analysisProvider: analysisProvider,
            mistakeValueProvider: valueProvider,
            ocrModelAPI: modelConfiguration(base: ocrBaseURL, endpoint: ocrEndpoint, model: ocrModel),
            analysisModelAPI: modelConfiguration(base: analysisBaseURL, endpoint: analysisEndpoint, model: analysisModel),
            mistakeValueModelAPI: modelConfiguration(base: valueBaseURL, endpoint: valueEndpoint, model: valueModel),
            baiduEducation: BaiduEducationConfiguration(strategy: baiduStrategy, recognizeFormula: baiduFormula,
                                                        layoutAnalysis: baiduLayout, mixedHandwriting: baiduMixed))
        Task {
            do { _ = try await service.updateSettings(settings: next); actionMessage = "设置已保存。"; errorMessage = nil }
            catch { errorMessage = UIErrorMessage.from(error) }
            isSaving = false
        }
    }

    private func saveCredentials() {
        let entries: [(CredentialKind, String)] = [(.ocrModelAPIKey, ocrKey), (.analysisModelAPIKey, analysisKey),
            (.mistakeValueModelAPIKey, valueKey), (.baiduAPIKey, baiduAPIKey), (.baiduSecretKey, baiduSecretKey)]
        Task {
            do {
                for (kind, value) in entries where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    try await service.setCredential(kind: kind, value: value)
                }
                ocrKey = ""; analysisKey = ""; valueKey = ""; baiduAPIKey = ""; baiduSecretKey = ""
                credentialStatus = try await service.credentialStatus()
                actionMessage = "密钥已保存到 Keychain。"; errorMessage = nil
            } catch { errorMessage = UIErrorMessage.from(error) }
        }
    }

    private func clearCredential(_ kind: CredentialKind) {
        Task {
            do { try await service.clearCredential(kind: kind); credentialStatus = try await service.credentialStatus(); actionMessage = "密钥已清除。" }
            catch { errorMessage = UIErrorMessage.from(error) }
        }
    }

    private func modelConfiguration(base: String, endpoint: String, model: String) -> ModelAPIConfiguration? {
        let b = base.trimmingCharacters(in: .whitespacesAndNewlines), m = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !b.isEmpty, !m.isEmpty else { return nil }
        return ModelAPIConfiguration(baseURL: b, endpointPath: endpoint.isEmpty ? "/chat/completions" : endpoint, model: m, timeoutSeconds: 30)
    }

    private func apply(_ config: ModelAPIConfiguration?, base: inout String, endpoint: inout String, model: inout String) {
        guard let config else { return }; base = config.baseURL; endpoint = config.endpointPath; model = config.model
    }

    private func secretLabel(_ name: String, _ kind: CredentialKind) -> String { credentialStatus.contains(kind) ? "\(name)（已保存）" : name }
    private func credentialTitle(_ kind: CredentialKind) -> String {
        switch kind {
        case .ocrModelAPIKey: "清除 OCR API Key"
        case .analysisModelAPIKey: "清除错因分析 API Key"
        case .mistakeValueModelAPIKey: "清除价值量化 API Key"
        case .baiduAPIKey: "清除百度 API Key"
        case .baiduSecretKey: "清除百度 Secret Key"
        }
    }

    private func prepareClear() {
        Task { do { pendingClearConfirmation = try await service.prepareClearAllData(); showingClearAlert = true } catch { errorMessage = UIErrorMessage.from(error) } }
    }
    private func clear(_ confirmation: ClearDataConfirmation) {
        Task { do { try await service.clearAllData(confirmation: confirmation); credentialStatus = CredentialStatus(configured: []); actionMessage = "本地数据与密钥已清空。" } catch { errorMessage = UIErrorMessage.from(error) } }
    }

    private func featureTitle(_ feature: CapabilityFeature) -> String {
        switch feature {
        case .importImages: "图片导入"
        case .ocr: "文字识别"
        case .segmentation: "建议分题"
        case .basicAnalysis: "基础分析"
        case .enhancedAnalysis: "增强错因分析"
        case .mistakeValue: "错题价值量化"
        case .classification: "知识归档"
        case .pdfExport: "PDF 导出"
        }
    }
    private func capabilityColor(_ state: CapabilityState) -> Color {
        switch state { case .available: .green; case .partial, .notReady: .orange; case .unavailable: .secondary }
    }
}

private struct APIConfigurationFields: View {
    let title: String
    let deepSeekModel: String
    @Binding var baseURL: String
    @Binding var endpoint: String
    @Binding var model: String
    var body: some View {
        Group {
            Button("使用 DeepSeek 官方配置") {
                baseURL = ModelAPIConfiguration.deepSeekText.baseURL
                endpoint = ModelAPIConfiguration.deepSeekText.endpointPath
                model = deepSeekModel
            }
            TextField("\(title) Base URL", text: $baseURL).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Endpoint", text: $endpoint).textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Model", text: $model).textInputAutocapitalization(.never).autocorrectionDisabled()
        }
    }
}

private extension FeatureCapability { var featureKey: String { "\(feature.rawValue)-\(subjectID ?? "all")" } }

/// One-way secret input: values are only written to Keychain through AppService
/// and are never read back into this field.
private struct SecretField: View {
    let title: String
    @Binding var text: String

    init(_ title: String, text: Binding<String>) {
        self.title = title
        self.text = text
    }

    var body: some View {
        SecureField(title, text: $text)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
    }
}

struct AllRecordsExportSheet: View {
    let service: any AppService
    @State private var records: [MistakeRecord] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading { ProgressView("正在载入全部题目…") }
            else if let errorMessage { ErrorBanner(message: errorMessage).padding() }
            else { ExportSheet(service: service, records: records, onFinished: {}) }
        }
        .task {
            do {
                let query = RecordQuery(text: "", subjectID: nil, taxonomyNodeID: nil, includeDescendants: true,
                                        reviewStates: [], reviewRequiredOnly: false, includeDeleted: false,
                                        sort: .updatedNewest, includeArchived: true)
                records = try await service.list(query: query, page: PageRequest(cursor: nil, limit: 200)).records
            } catch { errorMessage = UIErrorMessage.from(error) }
            isLoading = false
        }
    }
}
#endif
