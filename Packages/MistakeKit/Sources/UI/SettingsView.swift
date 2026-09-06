#if os(iOS)
import SwiftUI
import UIKit
import Contracts

@MainActor
struct SettingsView: View {
    let service: any AppService

    @Environment(\.dismiss) private var dismiss
    @State private var capabilities = CapabilityReport(checkedAt: .now, features: [])
    @State private var credentialStatus = CredentialStatus(configured: [])

    @State private var processingMode: ProcessingMode = .local
    @State private var languageText = "zh-Hans, en-US"
    @State private var appleEnhanced = true

    @State private var deepSeek = ProviderProfile(baseURL: "https://api.deepseek.com", model: "deepseek-v4-flash")
    @State private var openAICompatible = ProviderProfile(baseURL: "https://api.openai.com/v1", model: "")

    @State private var baiduStrategy: BaiduEducationStrategy = .automatic
    @State private var baiduFormula = true
    @State private var baiduLayout = true
    @State private var baiduMixed = true

    // Secret fields are never populated from Keychain.
    @State private var baiduAPIKey = ""
    @State private var baiduSecretKey = ""

    @State private var ocrChoice: OCRChoice = .appleVision
    @State private var analysisChoice: AnalysisChoice = .appleIntelligence
    @State private var valueChoice: ValueChoice = .local

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var actionMessage: String?
    @State private var pendingClearConfirmation: ClearDataConfirmation?
    @State private var showingClearAlert = false
    @State private var showingAllExport = false
    @State private var showingSavePrompt = false
    @State private var loadedSnapshot: SettingsSnapshot?

    var body: some View {
        NavigationStack {
            Form {
                messageSections
                modeSection
                providerSection
                assignmentSection
                saveSection
                statusSection
                dataSection
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { closeToolbar }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .task { load() }
            .sheet(isPresented: $showingAllExport) { AllRecordsExportSheet(service: service) }
            .alert("是否保存已更改的设置？", isPresented: $showingSavePrompt) {
                Button("保存") { Task { await saveAndClose(close: false) } }
                Button("不保存", role: .destructive) { dismiss() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("你有尚未保存的设置更改。")
            }
            .alert("确认清空本机数据", isPresented: $showingClearAlert, presenting: pendingClearConfirmation) { confirmation in
                Button("清空且无法撤销", role: .destructive) { clear(confirmation) }
                Button("取消", role: .cancel) {}
            } message: { confirmation in
                Text("将删除 \(confirmation.inventory.recordCount) 道错题、\(confirmation.inventory.assetCount) 张图片，并停止 \(confirmation.inventory.activeJobCount) 个进行中的任务。")
            }
        }
    }

    // The form is split into one property per section: a single giant body
    // expression previously exceeded the type-checker's time budget.
    @ViewBuilder
    private var messageSections: some View {
        if let errorMessage { Section { ErrorBanner(message: errorMessage) } }
        if let actionMessage { Section { NoticeBanner(message: actionMessage) } }
    }

    private var closeToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("关闭") { attemptClose() }
        }
    }

    private var modeSection: some View {
        Section {
            Picker("处理方式", selection: $processingMode) {
                Text("本机处理").tag(ProcessingMode.local)
                Text("联网处理").tag(ProcessingMode.api)
                Text("自动").tag(ProcessingMode.automatic)
            }
            .pickerStyle(.segmented)
            Text(modeExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            TextField("识别语言（逗号分隔）", text: $languageText)
        } header: {
            Text("处理方式")
        } footer: {
            Text("本机处理时，图片和文字不会离开设备。")
        }
    }

    private var providerSection: some View {
        Section {
            NavigationLink {
                ProviderDetailView(title: "DeepSeek", showsModelPresets: true, profile: $deepSeek)
            } label: {
                providerRow("DeepSeek", detail: deepSeek.model.isEmpty ? "未填写模型" : deepSeek.model)
            }
            NavigationLink {
                ProviderDetailView(title: "ChatGPT / OpenAI 兼容", showsModelPresets: false, profile: $openAICompatible)
            } label: {
                providerRow("ChatGPT / OpenAI 兼容", detail: openAICompatible.model.isEmpty ? "未填写模型" : "已配置")
            }
            NavigationLink {
                BaiduProviderView(strategy: $baiduStrategy, formula: $baiduFormula,
                                  layout: $baiduLayout, mixed: $baiduMixed,
                                  apiKey: $baiduAPIKey, secretKey: $baiduSecretKey,
                                  keySaved: credentialStatus.contains(.baiduAPIKey))
            } label: {
                providerRow("百度教育", detail: credentialStatus.contains(.baiduAPIKey) ? "已配置" : "未填写密钥")
            }
            NavigationLink {
                AppleIntelligenceView(enabled: $appleEnhanced, capabilities: capabilities)
            } label: {
                providerRow("Apple 智能", detail: appleEnhanced ? "已开启" : "已关闭")
            }
        } header: {
            Text("服务商")
        } footer: {
            Text("在这里填写密钥和模型；下面决定每件事分别交给谁做。")
        }
    }

    private func providerRow(_ name: String, detail: String) -> some View {
        LabeledContent(name) {
            Text(detail).foregroundStyle(.secondary)
        }
    }

    private var assignmentSection: some View {
        Section {
            LabeledContent("文字识别用") {
                Picker("文字识别用", selection: $ocrChoice) {
                    Text("手机本地识别").tag(OCRChoice.appleVision)
                    Text("DeepSeek").tag(OCRChoice.deepSeek)
                    Text("ChatGPT").tag(OCRChoice.openAICompatible)
                    Text("百度教育").tag(OCRChoice.baiduEducation)
                }
                .labelsHidden()
            }
            LabeledContent("错因分析用") {
                Picker("错因分析用", selection: $analysisChoice) {
                    Text("本机规则").tag(AnalysisChoice.localRules)
                    Text("Apple 智能").tag(AnalysisChoice.appleIntelligence)
                    Text("DeepSeek").tag(AnalysisChoice.deepSeek)
                    Text("ChatGPT").tag(AnalysisChoice.openAICompatible)
                }
                .labelsHidden()
            }
            LabeledContent("复习价值用") {
                Picker("复习价值用", selection: $valueChoice) {
                    Text("本机估算").tag(ValueChoice.local)
                    Text("DeepSeek").tag(ValueChoice.deepSeek)
                    Text("ChatGPT").tag(ValueChoice.openAICompatible)
                }
                .labelsHidden()
            }
        } header: {
            Text("谁负责什么")
        } footer: {
            Text("选中的服务商会使用你在上面填写的密钥和模型。")
        }
    }

    private var saveSection: some View {
        Section("保存") {
            Button(isSaving ? "正在保存…" : "保存设置") { save() }
                .disabled(isSaving)
            if !credentialStatus.configured.isEmpty {
                Menu("清除已保存的密钥") {
                    ForEach(credentialStatus.configured, id: \.self) { kind in
                        Button(credentialTitle(kind), role: .destructive) { clearCredential(kind) }
                    }
                }
            }
        }
    }

    private var statusSection: some View {
        Section("服务状态") {
            if isLoading && capabilities.features.isEmpty {
                HStack { ProgressView(); Text("正在检查…") }
            }
            ForEach(capabilities.features, id: \.featureKey) { feature in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(featureTitle(feature.feature))
                        Spacer()
                        Text(UIStrings.capabilityState(feature.state)).foregroundStyle(capabilityColor(feature.state))
                    }
                    Text(feature.reason).font(.caption).foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var dataSection: some View {
        Section("数据") {
            Button("导出全部题目") { showingAllExport = true }
            Button("清空本机数据", role: .destructive) { prepareClear() }
            Text("清空会终止任务并删除题目、图片、撤销记录、设置和已保存的密钥，确认后无法找回。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var modeExplanation: String {
        switch processingMode {
        case .local: "全部在本机完成，最快且不联网。"
        case .api: "按上面“谁负责什么”的分配，调用对应服务商。"
        case .automatic: "先在本机处理，效果不好时才联网。"
        }
    }

    private var hasUnsavedChanges: Bool {
        guard let loadedSnapshot else { return false }
        return loadedSnapshot != currentSnapshot
    }

    private var currentSnapshot: SettingsSnapshot {
        SettingsSnapshot(processingMode: processingMode, languageText: languageText, appleEnhanced: appleEnhanced,
                         deepSeek: deepSeek, openAICompatible: openAICompatible,
                         baiduStrategy: baiduStrategy, baiduFormula: baiduFormula, baiduLayout: baiduLayout, baiduMixed: baiduMixed,
                         ocrChoice: ocrChoice, analysisChoice: analysisChoice, valueChoice: valueChoice)
    }

    private func attemptClose() {
        if hasUnsavedChanges { showingSavePrompt = true } else { dismiss() }
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
                appleEnhanced = s.enhancedAnalysisEnabled
                processingMode = s.resolvedProcessingMode
                apply(s.ocrModelAPI, to: &deepSeek, and: &openAICompatible)
                apply(s.analysisModelAPI, to: &deepSeek, and: &openAICompatible)
                apply(s.mistakeValueModelAPI, to: &deepSeek, and: &openAICompatible)
                ocrChoice = ocrChoice(from: s)
                analysisChoice = analysisChoice(from: s)
                valueChoice = valueChoice(from: s)
                let baidu = s.baiduEducation ?? BaiduEducationConfiguration()
                baiduStrategy = baidu.strategy; baiduFormula = baidu.recognizeFormula
                baiduLayout = baidu.layoutAnalysis; baiduMixed = baidu.mixedHandwriting
                errorMessage = nil
            } catch { errorMessage = UIErrorMessage.from(error) }
            isLoading = false
            loadedSnapshot = currentSnapshot
        }
    }

    private func ocrChoice(from s: AppSettings) -> OCRChoice {
        switch s.resolvedOCRProvider {
        case .appleVision: return .appleVision
        case .baiduEducation: return .baiduEducation
        case .modelAPI: return s.ocrModelAPI?.isDeepSeek == true ? .deepSeek : .openAICompatible
        }
    }

    private func analysisChoice(from s: AppSettings) -> AnalysisChoice {
        switch s.resolvedAnalysisProvider {
        case .localRules: return .localRules
        case .appleFoundationModels: return .appleIntelligence
        case .modelAPI: return s.analysisModelAPI?.isDeepSeek == true ? .deepSeek : .openAICompatible
        }
    }

    private func valueChoice(from s: AppSettings) -> ValueChoice {
        switch s.resolvedMistakeValueProvider {
        case .localHeuristic: return .local
        case .modelAPI: return s.mistakeValueModelAPI?.isDeepSeek == true ? .deepSeek : .openAICompatible
        }
    }

    /// Routes a stored role config into the DeepSeek or OpenAI-compatible profile
    /// by host, so provider pages always show what the roles currently use.
    private func apply(_ config: ModelAPIConfiguration?, to deepSeek: inout ProviderProfile, and openAI: inout ProviderProfile) {
        guard let config else { return }
        if config.isDeepSeek {
            deepSeek.baseURL = config.baseURL; deepSeek.endpoint = config.endpointPath
            deepSeek.model = config.model; deepSeek.timeoutSeconds = config.timeoutSeconds
        } else {
            openAI.baseURL = config.baseURL; openAI.endpoint = config.endpointPath
            openAI.model = config.model; openAI.timeoutSeconds = config.timeoutSeconds
        }
    }

    private func save() { Task { await saveAndClose(close: false) } }

    private func saveAndClose(close: Bool = true) {
        guard !isSaving else { return }
        guard validate() else { return }
        isSaving = true
        let languages = languageText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let ocrModelAPI: ModelAPIConfiguration?
        var ocrProvider: OCRProviderKind
        switch ocrChoice {
        case .appleVision: ocrProvider = .appleVision; ocrModelAPI = nil
        case .baiduEducation: ocrProvider = .baiduEducation; ocrModelAPI = nil
        case .deepSeek: ocrProvider = .modelAPI; ocrModelAPI = deepSeek.configuration()
        case .openAICompatible: ocrProvider = .modelAPI; ocrModelAPI = openAICompatible.configuration()
        }
        let analysisModelAPI: ModelAPIConfiguration?
        var analysisProvider: AnalysisProviderKind
        switch analysisChoice {
        case .localRules: analysisProvider = .localRules; analysisModelAPI = nil
        case .appleIntelligence: analysisProvider = .appleFoundationModels; analysisModelAPI = nil
        case .deepSeek: analysisProvider = .modelAPI; analysisModelAPI = deepSeek.configuration()
        case .openAICompatible: analysisProvider = .modelAPI; analysisModelAPI = openAICompatible.configuration()
        }
        let valueModelAPI: ModelAPIConfiguration?
        var valueProvider: MistakeValueProviderKind
        switch valueChoice {
        case .local: valueProvider = .localHeuristic; valueModelAPI = nil
        case .deepSeek: valueProvider = .modelAPI; valueModelAPI = deepSeek.configuration()
        case .openAICompatible: valueProvider = .modelAPI; valueModelAPI = openAICompatible.configuration()
        }
        let next = AppSettings(recognitionLanguages: languages.isEmpty ? ["zh-Hans"] : languages,
            enhancedAnalysisEnabled: appleEnhanced, autoArchivePolicy: AutoArchivePolicy(version: "suggestions-only", enabledRules: []),
            processingMode: processingMode, ocrProvider: ocrProvider, analysisProvider: analysisProvider,
            mistakeValueProvider: valueProvider,
            ocrModelAPI: ocrModelAPI, analysisModelAPI: analysisModelAPI, mistakeValueModelAPI: valueModelAPI,
            baiduEducation: BaiduEducationConfiguration(strategy: baiduStrategy, recognizeFormula: baiduFormula,
                                                        layoutAnalysis: baiduLayout, mixedHandwriting: baiduMixed))
        Task {
            do {
                _ = try await service.updateSettings(settings: next)
                await saveCredentials()
                actionMessage = "设置已保存。"
                errorMessage = nil
                loadedSnapshot = currentSnapshot
                if close { dismiss() }
            } catch { errorMessage = UIErrorMessage.from(error) }
            isSaving = false
        }
    }

    /// Writes each provider's key into the roles currently assigned to it.
    private func saveCredentials() async {
        let entries: [(CredentialKind, String)] = keyEntries()
        for (kind, value) in entries where !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try? await service.setCredential(kind: kind, value: value)
        }
        credentialStatus = (try? await service.credentialStatus()) ?? credentialStatus
    }

    private func keyEntries() -> [(CredentialKind, String)] {
        var entries: [(CredentialKind, String)] = []
        switch ocrChoice {
        case .deepSeek: entries.append((.ocrModelAPIKey, deepSeek.apiKey))
        case .openAICompatible: entries.append((.ocrModelAPIKey, openAICompatible.apiKey))
        case .baiduEducation:
            entries.append((.baiduAPIKey, baiduAPIKey))
            entries.append((.baiduSecretKey, baiduSecretKey))
        case .appleVision: break
        }
        switch analysisChoice {
        case .deepSeek: entries.append((.analysisModelAPIKey, deepSeek.apiKey))
        case .openAICompatible: entries.append((.analysisModelAPIKey, openAICompatible.apiKey))
        default: break
        }
        switch valueChoice {
        case .deepSeek: entries.append((.mistakeValueModelAPIKey, deepSeek.apiKey))
        case .openAICompatible: entries.append((.mistakeValueModelAPIKey, openAICompatible.apiKey))
        case .local: break
        }
        return entries
    }

    private func validate() -> Bool {
        switch ocrChoice {
        case .deepSeek where deepSeek.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             .openAICompatible where openAICompatible.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            errorMessage = "文字识别选择的联网服务商还没有填写模型名称，请进入该服务商页面填写。"
            return false
        default: break
        }
        switch analysisChoice {
        case .deepSeek where deepSeek.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             .openAICompatible where openAICompatible.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            errorMessage = "错因分析选择的联网服务商还没有填写模型名称，请进入该服务商页面填写。"
            return false
        default: break
        }
        switch valueChoice {
        case .deepSeek where deepSeek.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
             .openAICompatible where openAICompatible.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty:
            errorMessage = "复习价值选择的联网服务商还没有填写模型名称，请进入该服务商页面填写。"
            return false
        default: break
        }
        return true
    }

    private func clearCredential(_ kind: CredentialKind) {
        Task {
            do { try await service.clearCredential(kind: kind); credentialStatus = try await service.credentialStatus(); actionMessage = "密钥已清除。" }
            catch { errorMessage = UIErrorMessage.from(error) }
        }
    }

    private func credentialTitle(_ kind: CredentialKind) -> String {
        switch kind {
        case .ocrModelAPIKey: "清除文字识别密钥"
        case .analysisModelAPIKey: "清除错因分析密钥"
        case .mistakeValueModelAPIKey: "清除复习价值密钥"
        case .baiduAPIKey: "清除百度 API Key"
        case .baiduSecretKey: "清除百度 Secret Key"
        }
    }

    private func prepareClear() {
        Task { do { pendingClearConfirmation = try await service.prepareClearAllData(); showingClearAlert = true } catch { errorMessage = UIErrorMessage.from(error) } }
    }

    private func clear(_ confirmation: ClearDataConfirmation) {
        Task { do { try await service.clearAllData(confirmation: confirmation); credentialStatus = CredentialStatus(configured: []); actionMessage = "本机数据与密钥已清空。" } catch { errorMessage = UIErrorMessage.from(error) } }
    }

    private func featureTitle(_ feature: CapabilityFeature) -> String {
        switch feature {
        case .importImages: "图片导入"
        case .ocr: "文字识别"
        case .segmentation: "自动分题"
        case .basicAnalysis: "基础分析"
        case .enhancedAnalysis: "智能错因分析"
        case .mistakeValue: "复习价值"
        case .classification: "知识归档"
        case .pdfExport: "PDF 导出"
        }
    }

    private func capabilityColor(_ state: CapabilityState) -> Color {
        switch state { case .available: .green; case .partial, .notReady: .orange; case .unavailable: .secondary }
    }
}

private struct ProviderProfile: Equatable {
    var apiKey = ""
    var baseURL: String
    var endpoint = "/chat/completions"
    var model = ""
    var timeoutSeconds = 60.0

    init(baseURL: String, model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    func configuration() -> ModelAPIConfiguration {
        ModelAPIConfiguration(baseURL: baseURL.trimmingCharacters(in: .whitespacesAndNewlines),
                              endpointPath: endpoint.isEmpty ? "/chat/completions" : endpoint,
                              model: model.trimmingCharacters(in: .whitespacesAndNewlines),
                              timeoutSeconds: timeoutSeconds > 0 ? timeoutSeconds : 60)
    }
}

private enum OCRChoice: Hashable { case appleVision, deepSeek, openAICompatible, baiduEducation }
private enum AnalysisChoice: Hashable { case localRules, appleIntelligence, deepSeek, openAICompatible }
private enum ValueChoice: Hashable { case local, deepSeek, openAICompatible }

private struct SettingsSnapshot: Equatable {
    var processingMode: ProcessingMode
    var languageText: String
    var appleEnhanced: Bool
    var deepSeek: ProviderProfile
    var openAICompatible: ProviderProfile
    var baiduStrategy: BaiduEducationStrategy
    var baiduFormula: Bool
    var baiduLayout: Bool
    var baiduMixed: Bool
    var ocrChoice: OCRChoice
    var analysisChoice: AnalysisChoice
    var valueChoice: ValueChoice
}

/// Second-level page for an OpenAI-compatible provider: key, model and custom
/// endpoint settings live together here.
private struct ProviderDetailView: View {
    let title: String
    let showsModelPresets: Bool
    @Binding var profile: ProviderProfile

    var body: some View {
        Form {
            Section {
                SecureField("粘贴密钥（保存后不再显示）", text: $profile.apiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("API 密钥")
            } footer: {
                Text("密钥只保存在本机钥匙串里，不会显示出来；留空则保持原样。")
            }

            Section {
                TextField("模型名称", text: $profile.model)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if showsModelPresets {
                    Menu("选择常用模型") {
                        Button("文字模型 deepseek-v4-flash") { profile.model = "deepseek-v4-flash" }
                        Button("能看图的模型 deepseek-v4-flash-vision-exp") { profile.model = "deepseek-v4-flash-vision-exp" }
                    }
                }
            } header: {
                Text("模型")
            } footer: {
                Text("文字识别必须选择“能看图的模型”。")
            }

            Section {
                TextField("服务地址", text: $profile.baseURL)
                TextField("接口路径", text: $profile.endpoint)
                LabeledContent("等待时间（秒）") {
                    TextField("60", value: $profile.timeoutSeconds, format: .number.grouping(.never))
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                }
            } header: {
                Text("自定义设置")
            } footer: {
                Text("不确定时保持默认即可。")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct BaiduProviderView: View {
    @Binding var strategy: BaiduEducationStrategy
    @Binding var formula: Bool
    @Binding var layout: Bool
    @Binding var mixed: Bool
    @Binding var apiKey: String
    @Binding var secretKey: String
    let keySaved: Bool

    var body: some View {
        Form {
            Section {
                SecureField("粘贴 API Key", text: $apiKey)
                SecureField("粘贴 Secret Key", text: $secretKey)
            } header: {
                Text("API 密钥")
            } footer: {
                Text("两个密钥都可以在百度智能云控制台找到；保存后不再显示。")
            }
            Section {
                Picker("识别方式", selection: $strategy) {
                    Text("自动：切题失败后改用整页识别").tag(BaiduEducationStrategy.automatic)
                    Text("按题切图").tag(BaiduEducationStrategy.paperCut)
                    Text("整页识别").tag(BaiduEducationStrategy.documentAnalysis)
                }
                Toggle("识别公式", isOn: $formula)
                Toggle("分析版面", isOn: $layout)
                Toggle("手写和印刷混排", isOn: $mixed)
            } header: {
                Text("识别设置")
            }
        }
        .navigationTitle("百度教育")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Text(keySaved ? "已配置" : "")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct AppleIntelligenceView: View {
    @Binding var enabled: Bool
    let capabilities: CapabilityReport

    var body: some View {
        Form {
            Section {
                Toggle("用设备端智能分析错因", isOn: $enabled)
            } footer: {
                Text("不联网、不留记录。是否可用取决于机型和地区设置。")
            }
            Section("当前状态") {
                ForEach(capabilities.features.filter { $0.feature == .enhancedAnalysis || $0.feature == .basicAnalysis }, id: \.featureKey) { feature in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(feature.reason).font(.subheadline)
                    }
                }
            }
        }
        .navigationTitle("Apple 智能")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension FeatureCapability { var featureKey: String { "\(feature.rawValue)-\(subjectID ?? "all")" } }

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
